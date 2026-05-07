"""
sync_peers.py
=============
One-time recovery script — SSHes into each real server and re-adds
ALL active vpn_config peers from the database.

Run this when:
  - fix_servers.py was run (wg0.conf was reset, all peers lost)
  - Celery was not running and peers weren't added on provision
  - "VPN connects but no internet" reported by users

Usage:
    .\\venv\\Scripts\\python sync_peers.py
"""
import asyncio
import logging
import sys
import json
import os

from dotenv import load_dotenv
load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)

# Per-server SSH passwords (same as in .env)
PASSWORDS_JSON = os.environ.get("VPN_SERVER_PASSWORDS", "{}")
try:
    SERVER_PASSWORDS = json.loads(PASSWORDS_JSON)
except Exception:
    SERVER_PASSWORDS = {}


async def add_peer_to_server(server_ip: str, public_key: str, assigned_ip: str) -> bool:
    """SSH into server and add WireGuard peer."""
    try:
        import asyncssh
    except ImportError:
        logger.error("asyncssh not installed.")
        return False

    password = SERVER_PASSWORDS.get(server_ip)
    if not password:
        logger.warning(f"  No password for {server_ip} — skipping")
        return False

    try:
        async with asyncssh.connect(
            server_ip,
            username="root",
            password=password,
            known_hosts=None,
            connect_timeout=20,
        ) as conn:
            # Add peer to running WireGuard
            await conn.run(
                f"wg set wg0 peer {public_key} allowed-ips {assigned_ip}/32",
                check=True
            )
            # Persist to wg0.conf
            persist = (
                f"echo '' >> /etc/wireguard/wg0.conf && "
                f"echo '[Peer]' >> /etc/wireguard/wg0.conf && "
                f"echo 'PublicKey = {public_key}' >> /etc/wireguard/wg0.conf && "
                f"echo 'AllowedIPs = {assigned_ip}/32' >> /etc/wireguard/wg0.conf"
            )
            await conn.run(persist, check=True)
            return True
    except Exception as e:
        logger.error(f"  SSH failed for {server_ip}: {e}")
        return False


async def main():
    from models import SessionLocal, VPNConfig, VPNServer

    logger.info("=" * 60)
    logger.info("  AtmosVPN — Peer Sync Recovery Script")
    logger.info("=" * 60)

    db = SessionLocal()
    try:
        # Get all active VPN configs
        configs = db.query(VPNConfig).filter_by(is_active=True).all()
        logger.info(f"\nFound {len(configs)} active vpn_configs to sync.\n")

        if not configs:
            logger.info("Nothing to sync. Done.")
            return

        # Group by server
        by_server = {}
        for c in configs:
            by_server.setdefault(c.server_id, []).append(c)

        total_ok = 0
        total_fail = 0

        for server_id, cfgs in by_server.items():
            server = db.get(VPNServer, server_id)
            if not server or not server.ip_address:
                logger.warning(f"Server {server_id} not found or no IP — skipping")
                continue

            logger.info(f"{'─'*50}")
            logger.info(f"Server: {server.name} ({server.ip_address}) — {len(cfgs)} peers")

            for c in cfgs:
                if c.assigned_ip in ("pending", "needs-reprovision", None):
                    logger.info(f"  SKIP  {c.device_name or c.id} — invalid IP ({c.assigned_ip})")
                    continue

                ok = await add_peer_to_server(server.ip_address, c.public_key, c.assigned_ip)
                if ok:
                    logger.info(f"  ✅ Added  {c.device_name or str(c.id)[:8]}  IP={c.assigned_ip}")
                    total_ok += 1
                else:
                    logger.error(f"  ❌ Failed {c.device_name or str(c.id)[:8]}  IP={c.assigned_ip}")
                    total_fail += 1

        logger.info(f"\n{'='*60}")
        logger.info(f"  Done — {total_ok} peers added, {total_fail} failed")
        logger.info(f"{'='*60}")
        if total_ok > 0:
            logger.info("  Users can now connect — internet should work immediately.")

    finally:
        db.close()


if __name__ == "__main__":
    asyncio.run(main())
