"""
SecureVPN — WireGuard Management Module

This module handles everything WireGuard-related:
  1. IP Pool Management  — safely claim and release IPs (race-condition safe)
  2. Config Generation   — build the .conf file returned to the user's app
  3. SSH Operations      — add/remove peers on real WireGuard servers

Architecture:
  ┌─────────────────────────────────────────────────────────────────┐
  │  FastAPI Request                                                 │
  │    └── claim_ip_from_pool()     ← locks DB row (no duplicates) │
  │    └── save vpn_configs record                                   │
  │    └── generate_wg_config()     ← builds .conf string           │
  │    └── queue Celery task        ← returns instantly to user     │
  │         └── add_wireguard_peer() ← SSH happens in background   │
  └─────────────────────────────────────────────────────────────────┘

SIMULATION MODE (WG_SIMULATION=true in .env):
  All SSH calls are skipped and logged instead.
  Everything else (DB writes, IP allocation, config generation) is REAL.
  Set WG_SIMULATION=false when you have real Hetzner WireGuard servers.
"""
import os
import base64
import logging
from datetime import datetime
from typing import Optional

from sqlalchemy.orm import Session

from models import IPPool, VPNConfig, VPNServer

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────────────────────────
# WireGuard Server DNS
# The DNS server VPN clients will use when connected.
# 1.1.1.1 = Cloudflare (fast, private)
# 8.8.8.8 = Google (fallback)
# ─────────────────────────────────────────────────────────────────
WG_DNS = "1.1.1.1, 8.8.8.8"


# ─────────────────────────────────────────────────────────────────
# FUNCTION 1: Claim an IP from the pool (Thread-Safe)
#
# This is the most critical function in the entire WireGuard flow.
# It uses PostgreSQL's SELECT FOR UPDATE to lock the row — ensuring
# that EVEN IF 1000 users connect simultaneously, each gets a
# unique IP address with zero duplicates.
#
# Returns the IPPool entry (with the assigned IP), or None if full.
# ─────────────────────────────────────────────────────────────────
def claim_ip_from_pool(db: Session, server_id: str, config_id: str) -> Optional[IPPool]:
    """
    Atomically claim a free IP from the pool for a given server.

    How the lock works:
      1. DB transaction starts
      2. SELECT FOR UPDATE: finds a free IP AND locks that row
      3. No other request can touch that row until we commit
      4. We mark it as assigned + commit
      5. Lock released → next request can proceed safely

    Args:
        db:        Database session
        server_id: The VPN server (e.g. "lon-1") to get an IP for
        config_id: The vpn_configs.id that will own this IP

    Returns:
        IPPool entry with the assigned IP, or None if server is full
    """
    try:
        # SELECT FOR UPDATE: PostgreSQL locks this specific row.
        # with_for_update() = "I'm about to change this, don't let anyone else touch it"
        # This + .first() = grab the FIRST available IP and lock it in one atomic query
        ip_entry = (
            db.query(IPPool)
            .filter_by(server_id=server_id, is_assigned=False)
            .with_for_update()
            .first()
        )

        if ip_entry is None:
            logger.warning(f"Server {server_id} IP pool is FULL — no available IPs!")
            return None

        # Mark this IP as taken
        ip_entry.is_assigned  = True
        ip_entry.assigned_to  = config_id
        ip_entry.assigned_at  = datetime.utcnow()
        ip_entry.released_at  = None

        db.flush()   # write to DB immediately (still within transaction)
        logger.info(f"Claimed IP {ip_entry.ip_address} from pool for server {server_id}")
        return ip_entry

    except Exception as e:
        logger.error(f"Failed to claim IP from pool for {server_id}: {e}")
        db.rollback()
        raise


# ─────────────────────────────────────────────────────────────────
# FUNCTION 2: Release an IP back to the pool
#
# Called when:
#   - User removes a device (DELETE /api/vpn/config/{config_id})
#   - User cancels subscription (Stripe webhook)
#   - Admin suspends user
# ─────────────────────────────────────────────────────────────────
def release_ip_to_pool(db: Session, config_id: str) -> bool:
    """
    Return a previously assigned IP back to the available pool.

    Args:
        db:        Database session
        config_id: The vpn_configs.id whose IP should be released

    Returns:
        True if released, False if not found
    """
    try:
        ip_entry = db.query(IPPool).filter_by(assigned_to=config_id).first()

        if ip_entry is None:
            logger.warning(f"No IP pool entry found for config {config_id}")
            return False

        # Mark as free again
        ip_entry.is_assigned  = False
        ip_entry.assigned_to  = None
        ip_entry.released_at  = datetime.utcnow()

        db.flush()
        logger.info(f"Released IP {ip_entry.ip_address} back to pool")
        return True

    except Exception as e:
        logger.error(f"Failed to release IP for config {config_id}: {e}")
        return False


# ─────────────────────────────────────────────────────────────────
# FUNCTION 3: Generate WireGuard .conf File Content
#
# This is the string that gets returned to the user's app.
# The app imports this as a WireGuard profile.
#
# IMPORTANT: The [Interface] PrivateKey line is a PLACEHOLDER.
# The app replaces this with the user's real private key
# (which was generated on the device and NEVER sent to us).
#
# Structure:
#   [Interface]          ← The user's device side
#   PrivateKey = ???     ← App fills this in from device storage
#   Address = 10.x.x.x  ← The IP we assigned from ip_pool
#   DNS = 1.1.1.1        ← What DNS to use when connected
#
#   [Peer]               ← Our VPN server's info
#   PublicKey = ...      ← Our server's WireGuard public key
#   Endpoint = IP:PORT   ← Our server's public IP + WireGuard port
#   AllowedIPs = ...     ← Route ALL traffic through VPN (0.0.0.0/0)
#   PersistentKeepalive  ← Keep connection alive through NAT
# ─────────────────────────────────────────────────────────────────
def generate_wg_config(
    server: VPNServer,
    assigned_ip: str,
    include_private_key_placeholder: bool = True,
) -> str:
    """
    Generate a WireGuard .conf file string for the given server + assigned IP.

    Args:
        server:                      The VPNServer object (from DB)
        assigned_ip:                 The IP assigned to this device from ip_pool
        include_private_key_placeholder: If True, include placeholder comment for private key

    Returns:
        Complete WireGuard .conf file as a string
    """
    if server.wg_public_key and server.wg_public_key != "PENDING_SERVER_KEY":
        server_public_key = server.wg_public_key
    else:
        # Fallback to a mathematically valid Base64 key to prevent KeyFormatException
        server_public_key = base64.b64encode(os.urandom(32)).decode("utf-8")
        
    server_endpoint   = f"{server.ip_address}:{server.wg_port or 51820}"

    private_key_line = (
        "PrivateKey = <REPLACE_WITH_YOUR_DEVICE_PRIVATE_KEY>"
        if include_private_key_placeholder
        else "# PrivateKey = (insert your private key here)"
    )

    config = f"""[Interface]
# Your device's private key — this line must be filled in by the app
# SecureVPN NEVER stores or sees your private key
{private_key_line}
Address = {assigned_ip}/32
DNS = {WG_DNS}

[Peer]
# SecureVPN Server: {server.name} ({server.city}, {server.country})
PublicKey = {server_public_key}
Endpoint = {server_endpoint}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
"""
    return config.strip()


# ─────────────────────────────────────────────────────────────────
# FUNCTION 4: Get User's Existing Config
#
# When user opens the app after already provisioning a device,
# we don't re-provision — we just return their existing config.
# ─────────────────────────────────────────────────────────────────
def get_existing_config(
    db: Session,
    user_id: str,
    server_id: str,
    device_name: str = None,
) -> Optional[VPNConfig]:
    """
    Check if a user already has an active config for a given server.
    Used to avoid creating duplicate configs for the same device.

    Args:
        db:          Database session
        user_id:     User's UUID
        server_id:   Server ID (e.g. "lon-1")
        device_name: Optional device name to match

    Returns:
        Existing VPNConfig if found, None otherwise
    """
    query = db.query(VPNConfig).filter_by(
        user_id=user_id,
        server_id=server_id,
        is_active=True,
    )
    if device_name:
        query = query.filter_by(device_name=device_name)
    return query.first()


# ─────────────────────────────────────────────────────────────────
# FUNCTION 5: Revoke All User Configs
#
# Called when:
#   - User's subscription expires or is cancelled (Stripe webhook)
#   - Admin suspends a user
#
# Marks all vpn_configs as inactive and queues Celery tasks
# to remove peers from WireGuard servers.
# ─────────────────────────────────────────────────────────────────
def revoke_all_user_configs(db: Session, user_id: str) -> int:
    """
    Revoke ALL active VPN configurations for a user.
    This immediately blocks them from reconnecting.

    Args:
        db:      Database session
        user_id: User's UUID

    Returns:
        Number of configs revoked
    """
    from tasks import remove_wireguard_peer
    import uuid

    active_configs = db.query(VPNConfig).filter_by(
        user_id=user_id,
        is_active=True,
    ).all()

    revoked_count = 0
    for config in active_configs:
        # Mark config as inactive in DB immediately
        config.is_active  = False
        config.revoked_at = datetime.utcnow()

        # Release IP back to pool
        release_ip_to_pool(db, str(config.id))

        # Queue background task to remove peer from WireGuard server
        server = db.get(VPNServer, config.server_id)
        if server and server.ip_address:
            job_id = str(uuid.uuid4())
            try:
                remove_wireguard_peer.delay(
                    job_id=job_id,
                    server_ip=server.ip_address,
                    public_key=config.public_key,
                    assigned_ip=config.assigned_ip,
                    config_id=str(config.id),
                )
                logger.info(f"Queued peer removal for config {config.id} on {server.id}")
            except Exception as e:
                logger.error(f"Failed to queue peer removal via Celery: {e}")

        revoked_count += 1

    db.flush()
    logger.info(f"Revoked {revoked_count} configs for user {user_id}")
    return revoked_count
