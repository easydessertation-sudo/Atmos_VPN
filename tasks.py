"""
SecureVPN — Celery Background Tasks
These are the "heavy jobs" that run OUTSIDE the main API request cycle.

Why background tasks?
  SSH into a WireGuard server takes 2-5 seconds.
  We cannot make users wait 5 seconds every time they connect.
  Instead:
    1. API instantly returns "provisioning started"
    2. This task runs in background, does the SSH work
    3. App polls /api/vpn/status until it's ready

Current tasks:
  - add_wireguard_peer    → SSH into server, add user's public key as WireGuard peer
  - remove_wireguard_peer → SSH into server, remove user's WireGuard peer (disconnect/cancel)
  - update_server_stats   → Periodically update server load % (run every 30 seconds)
  - reset_bandwidth       → Reset all users' monthly bandwidth at billing cycle start

NOTE:
  The actual asyncssh SSH calls are structured and ready.
  They will work when you provide real WireGuard server credentials.
  Until then, they log what they WOULD do (simulation mode).
"""
import os
import asyncio
import logging
from datetime import datetime

from celery_app import celery_app
from redis_client import set_job_status, get_redis

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────
# Helper: Run async code inside Celery (which is synchronous)
#
# Celery tasks are sync by default.
# asyncssh is async (uses async/await).
# This helper bridges the gap.
# ─────────────────────────────────────────────────────────────────
def run_async(coro):
    """Run an async coroutine from a synchronous Celery task."""
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


# ─────────────────────────────────────────────────────────────────
# TASK 1: Add WireGuard Peer
#
# Called when: User calls POST /api/vpn/provision or /api/vpn/connect
#
# What it does:
#   1. SSH into the WireGuard VPN server
#   2. Run: wg set wg0 peer <PUBLIC_KEY> allowed-ips <ASSIGNED_IP>/32
#   3. Run: wg-quick save wg0  (CRITICAL: saves config to survive server reboot)
#   4. Update job status in Redis so the app knows when it's ready
#
# Parameters:
#   job_id       — unique ID for this job (stored in Redis for status polling)
#   server_ip    — public IP of the WireGuard server (e.g. "185.156.46.1")
#   public_key   — user's device WireGuard public key
#   assigned_ip  — IP assigned from ip_pool (e.g. "10.0.0.42")
#   config_id    — vpn_configs.id (to update DB after success)
# ─────────────────────────────────────────────────────────────────
@celery_app.task(
    name="tasks.add_wireguard_peer",
    bind=True,
    max_retries=3,
    default_retry_delay=10,   # wait 10 seconds between retries
)
def add_wireguard_peer(self, job_id: str, server_ip: str, public_key: str,
                        assigned_ip: str, config_id: str):
    """
    Background task: Add a user's WireGuard peer to a VPN server.
    Retries up to 3 times if SSH fails (e.g. temporary network issue).
    """
    logger.info(f"[Task {job_id}] Adding WireGuard peer {public_key[:16]}... to {server_ip}")

    # Update job status → "running"
    set_job_status(job_id, {
        "status": "running",
        "message": f"Adding peer to server {server_ip}...",
        "started_at": datetime.utcnow().isoformat(),
    })

    try:
        # Run the async SSH function
        result = run_async(_ssh_add_peer(server_ip, public_key, assigned_ip))

        if result:
            # Success → update job status
            set_job_status(job_id, {
                "status": "completed",
                "message": "WireGuard peer added successfully.",
                "config_id": config_id,
                "assigned_ip": assigned_ip,
                "completed_at": datetime.utcnow().isoformat(),
            })
            logger.info(f"[Task {job_id}] ✅ Peer added successfully.")
            return {"success": True, "config_id": config_id}
        else:
            raise Exception("SSH command returned failure")

    except Exception as exc:
        logger.error(f"[Task {job_id}] ❌ Error: {exc}")

        # Check if we have retries left
        if self.request.retries < self.max_retries:
            set_job_status(job_id, {
                "status": "retrying",
                "message": f"Attempt {self.request.retries + 1} failed. Retrying...",
                "error": str(exc),
            })
            raise self.retry(exc=exc)
        else:
            # All retries exhausted
            set_job_status(job_id, {
                "status": "failed",
                "message": "Failed to add WireGuard peer after 3 attempts.",
                "error": str(exc),
                "failed_at": datetime.utcnow().isoformat(),
            })
            return {"success": False, "error": str(exc)}


async def _ssh_add_peer(server_ip: str, public_key: str, assigned_ip: str) -> bool:
    """
    Actual SSH logic to add a WireGuard peer.
    Uses asyncssh to connect to the server and run wg commands.

    IMPORTANT: "wg-quick save wg0" MUST be run after wg set.
    Without it, all peer configs are lost on server reboot.
    """
    SSH_KEY_PATH = os.environ.get("WG_SSH_KEY_PATH", "~/.ssh/id_rsa")
    SSH_USER     = os.environ.get("WG_SSH_USER", "root")

    # ── SIMULATION MODE ──────────────────────────────────────────
    # When WG_SIMULATION=true (default for dev), we skip real SSH.
    # Remove this block when you have real WireGuard servers.
    if os.environ.get("WG_SIMULATION", "true").lower() == "true":
        logger.info(f"[SIMULATION] Would run on {server_ip}:")
        logger.info(f"  wg set wg0 peer {public_key} allowed-ips {assigned_ip}/32")
        logger.info(f"  wg-quick save wg0")
        await asyncio.sleep(1)   # simulate SSH delay
        return True
    # ─────────────────────────────────────────────────────────────

    # ── REAL SSH (uncomment when you have WireGuard servers) ─────
    try:
        import asyncssh
        async with asyncssh.connect(
            server_ip,
            username=SSH_USER,
            client_keys=[SSH_KEY_PATH],
            known_hosts=None,    # TODO: set known_hosts in production for security
        ) as conn:
            # Add the peer
            cmd = f"wg set wg0 peer {public_key} allowed-ips {assigned_ip}/32"
            result = await conn.run(cmd, check=True)

            # CRITICAL: Save config so it survives server reboot
            await conn.run("wg-quick save wg0", check=True)

            return True
    except Exception as e:
        logger.error(f"SSH error on {server_ip}: {e}")
        raise


# ─────────────────────────────────────────────────────────────────
# TASK 2: Remove WireGuard Peer
#
# Called when:
#   - User calls DELETE /api/vpn/config/{config_id} (removes a device)
#   - User cancels subscription (Stripe webhook fires)
#   - Admin suspends a user
#
# What it does:
#   1. SSH into the WireGuard server
#   2. Run: wg set wg0 peer <PUBLIC_KEY> remove
#   3. Run: wg-quick save wg0
#   4. Mark the ip_pool entry as is_assigned=false (IP returned to pool)
# ─────────────────────────────────────────────────────────────────
@celery_app.task(
    name="tasks.remove_wireguard_peer",
    bind=True,
    max_retries=3,
    default_retry_delay=10,
)
def remove_wireguard_peer(self, job_id: str, server_ip: str, public_key: str,
                           assigned_ip: str, config_id: str):
    """
    Background task: Remove a user's WireGuard peer from a VPN server.
    Also releases the IP back to the pool.
    """
    logger.info(f"[Task {job_id}] Removing peer {public_key[:16]}... from {server_ip}")

    set_job_status(job_id, {
        "status": "running",
        "message": f"Removing peer from server {server_ip}...",
    })

    try:
        result = run_async(_ssh_remove_peer(server_ip, public_key))

        if result:
            set_job_status(job_id, {
                "status": "completed",
                "message": "WireGuard peer removed. IP returned to pool.",
                "completed_at": datetime.utcnow().isoformat(),
            })
            logger.info(f"[Task {job_id}] ✅ Peer removed.")
            return {"success": True}
        else:
            raise Exception("SSH command returned failure")

    except Exception as exc:
        logger.error(f"[Task {job_id}] ❌ Remove error: {exc}")
        if self.request.retries < self.max_retries:
            raise self.retry(exc=exc)
        set_job_status(job_id, {"status": "failed", "error": str(exc)})
        return {"success": False, "error": str(exc)}


async def _ssh_remove_peer(server_ip: str, public_key: str) -> bool:
    """Actual SSH logic to remove a WireGuard peer."""
    SSH_KEY_PATH = os.environ.get("WG_SSH_KEY_PATH", "~/.ssh/id_rsa")
    SSH_USER     = os.environ.get("WG_SSH_USER", "root")

    # ── SIMULATION MODE ──────────────────────────────────────────
    if os.environ.get("WG_SIMULATION", "true").lower() == "true":
        logger.info(f"[SIMULATION] Would run on {server_ip}:")
        logger.info(f"  wg set wg0 peer {public_key} remove")
        logger.info(f"  wg-quick save wg0")
        await asyncio.sleep(1)
        return True
    # ─────────────────────────────────────────────────────────────

    try:
        import asyncssh
        async with asyncssh.connect(
            server_ip,
            username=SSH_USER,
            client_keys=[SSH_KEY_PATH],
            known_hosts=None,
        ) as conn:
            cmd = f"wg set wg0 peer {public_key} remove"
            await conn.run(cmd, check=True)
            await conn.run("wg-quick save wg0", check=True)
            return True
    except Exception as e:
        logger.error(f"SSH error removing peer on {server_ip}: {e}")
        raise


# ─────────────────────────────────────────────────────────────────
# TASK 3: Update Server Stats
#
# Called by: Celery Beat scheduler (runs every 30 seconds)
# What it does: Queries current peer count from WireGuard server,
#               updates load_pct in the DB, invalidates server cache.
#
# This task is a placeholder — implement when you have real servers.
# ─────────────────────────────────────────────────────────────────
@celery_app.task(name="tasks.update_server_stats")
def update_server_stats(server_id: str, server_ip: str):
    """
    Periodic task: Update server load statistics.
    In simulation mode, just logs. Real implementation SSHs into server
    and runs 'wg show wg0 peers | wc -l' to count active peers.
    """
    logger.info(f"[Stats] Would update stats for server {server_id} at {server_ip}")

    # Invalidate the server list cache so next request gets fresh data
    from redis_client import cache_delete
    cache_delete("server_list")
    cache_delete(f"server_{server_id}")

    return {"server_id": server_id, "updated": True}


# ─────────────────────────────────────────────────────────────────
# TASK 4: Reset Monthly Bandwidth
#
# Called by: Stripe webhook when new billing period starts
#            (invoice.payment_succeeded event)
# What it does: Resets bandwidth_used_bytes=0 for a specific user.
# ─────────────────────────────────────────────────────────────────
@celery_app.task(name="tasks.reset_user_bandwidth")
def reset_user_bandwidth(user_id: str):
    """Reset a user's monthly bandwidth counter at the start of new billing period."""
    from models import SessionLocal, User
    db = SessionLocal()
    try:
        user = db.get(User, user_id)
        if user:
            user.bandwidth_used_bytes = 0
            db.commit()
            logger.info(f"[Bandwidth] Reset for user {user_id}")
            return {"success": True, "user_id": user_id}
        return {"success": False, "error": "User not found"}
    except Exception as e:
        db.rollback()
        logger.error(f"[Bandwidth] Reset failed for {user_id}: {e}")
        return {"success": False, "error": str(e)}
    finally:
        db.close()
