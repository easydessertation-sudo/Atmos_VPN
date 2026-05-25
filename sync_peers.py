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


async def rebuild_server_conf(server_ip: str, peers: list) -> bool:
    """
    SSH into server and rewrite wg0.conf cleanly from scratch using DB truth.
    
    Instead of appending (which causes duplicates), this:
      1. Reads the [Interface] block from the existing wg0.conf
      2. Builds a clean [Peer] section from the DB peers list
      3. Writes the combined clean config atomically
      4. Reloads WireGuard with zero downtime via `wg syncconf`
    
    peers: list of (public_key, assigned_ip) tuples
    """
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
            # 1. Read the existing [Interface] block
            r = await conn.run('cat /etc/wireguard/wg0.conf', check=True)
            existing = r.stdout
            
            # Extract only the [Interface] section (stop at first [Peer])
            interface_block = []
            for line in existing.splitlines():
                if line.strip().startswith('[Peer]'):
                    break
                interface_block.append(line)
            
            # Strip trailing blank lines from interface block
            while interface_block and not interface_block[-1].strip():
                interface_block.pop()
            interface_section = '\n'.join(interface_block)
            
            # 2. Deduplicate peers: if same public_key has multiple IPs, merge them
            key_to_ips: dict = {}
            for pk, ip in peers:
                key_to_ips.setdefault(pk, set()).add(ip)
            
            # Build clean [Peer] blocks
            peer_blocks = []
            for pk, ips in key_to_ips.items():
                allowed = ', '.join(f'{ip}/32' for ip in sorted(ips))
                peer_blocks.append(f'[Peer]\nPublicKey = {pk}\nAllowedIPs = {allowed}')
            
            clean_conf = interface_section + '\n\n' + '\n\n'.join(peer_blocks) + '\n'
            
            # 3. Backup and write atomically
            await conn.run('cp /etc/wireguard/wg0.conf /etc/wireguard/wg0.conf.bak', check=False)
            await conn.run('cat > /etc/wireguard/wg0.conf', input=clean_conf, check=True)
            
            # 4. Reload live WireGuard without restarting (zero downtime)
            r = await conn.run(
                'wg-quick strip wg0 > /tmp/wg0_stripped.conf && '
                'wg syncconf wg0 /tmp/wg0_stripped.conf && '
                'rm /tmp/wg0_stripped.conf',
                check=False
            )
            if r.returncode != 0:
                logger.warning(f"  wg syncconf warning on {server_ip}: {r.stderr}")
            
            # 5. Also ensure all peers are active in the running instance
            for pk, ips in key_to_ips.items():
                allowed = ','.join(f'{ip}/32' for ip in sorted(ips))
                await conn.run(
                    f'wg set wg0 peer {pk} allowed-ips {allowed}',
                    check=False
                )
            
            # Report live count
            r = await conn.run('wg show wg0 peers | wc -l', check=False)
            logger.info(f"  ✅ Config rebuilt — {r.stdout.strip()} peers active on {server_ip}")
            return True
    except Exception as e:
        logger.error(f"  SSH failed for {server_ip}: {e}")
        return False


async def add_peer_to_server(server_ip: str, public_key: str, assigned_ip: str) -> bool:
    """
    Add a single peer to a running WireGuard server.
    Uses `wg set` for the live instance (immediate effect).
    Does NOT append to wg0.conf — use rebuild_server_conf() for that.
    """
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
            # Add peer to running WireGuard (immediate, no restart needed)
            await conn.run(
                f"wg set wg0 peer {public_key} allowed-ips {assigned_ip}/32",
                check=True
            )
            # NOTE: We do NOT append to wg0.conf here to prevent duplicates.
            # The full conf rebuild is done by rebuild_server_conf() at the end.
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

            # Collect valid peers for this server
            valid_peers = []
            for c in cfgs:
                if c.assigned_ip in ("pending", "needs-reprovision", None):
                    logger.info(f"  SKIP  {c.device_name or c.id} — invalid IP ({c.assigned_ip})")
                    continue
                valid_peers.append((c.public_key, c.assigned_ip))
                logger.info(f"  Queued: {c.device_name or str(c.id)[:8]}  key={c.public_key[:16]}...  IP={c.assigned_ip}")

            if not valid_peers:
                logger.info(f"  No valid peers for {server.name} — skipping")
                continue

            # Rebuild the entire wg0.conf cleanly (no duplicate appending)
            ok = await rebuild_server_conf(server.ip_address, valid_peers)
            if ok:
                total_ok += len(valid_peers)
            else:
                logger.error(f"  ❌ Failed to rebuild conf for {server.name}")
                total_fail += len(valid_peers)

        logger.info(f"\n{'='*60}")
        logger.info(f"  Done — {total_ok} peers synced, {total_fail} failed")
        logger.info(f"{'='*60}")
        if total_ok > 0:
            logger.info("  Users can now connect — internet should work immediately.")

    finally:
        db.close()


if __name__ == "__main__":
    asyncio.run(main())
