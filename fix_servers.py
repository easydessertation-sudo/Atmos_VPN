"""
fix_servers.py
==============
Fixes all 4 issues reported by the frontend team:
  1. Full NAT/Masquerading  (PostUp with both FORWARD directions)
  2. IP Forwarding          (already set, but re-confirmed)
  3. IP Pool subnet fix     (DB pool now matches per-server wg0 subnet)
  4. MTU/MSS Clamping       (TCPMSS rule added to PostUp)

Also fixes a bonus issue:
  5. Per-server subnet isolation — each server gets its own /24:
       dal-1  → 10.8.0.0/24   (wg0 = 10.8.0.1)
       tlv-1  → 10.9.0.0/24   (wg0 = 10.9.0.1)
       sgp-2  → 10.10.0.0/24  (wg0 = 10.10.0.1)
       jnb-1  → 10.11.0.0/24  (wg0 = 10.11.0.1)

Run once:
    .\\venv\\Scripts\\python fix_servers.py
"""

import asyncio
import logging
import sys
from dotenv import load_dotenv
load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────
# Server definitions — each gets a unique /24 subnet
# ─────────────────────────────────────────────────────────────────
SERVERS = [
    {
        "id":           "dal-1",
        "name":         "Dallas",
        "ip_address":   "198.23.209.178",
        "ssh_password": "cL47Nmm6Ha6YyQ4T5g",
        "wg_subnet":    "10.8.0",      # server = 10.8.0.1,  clients = 10.8.0.2–254
    },
    {
        "id":           "tlv-1",
        "name":         "Tel Aviv",
        "ip_address":   "64.177.68.146",
        "ssh_password": "5[Mq@Ku]TaDYzG--",
        "wg_subnet":    "10.9.0",      # server = 10.9.0.1,  clients = 10.9.0.2–254
    },
    {
        "id":           "sgp-2",
        "name":         "Singapore",
        "ip_address":   "149.28.158.97",
        "ssh_password": "B5z{C=S!V!d8nF3K",
        "wg_subnet":    "10.10.0",     # server = 10.10.0.1, clients = 10.10.0.2–254
    },
    {
        "id":           "jnb-1",
        "name":         "Johannesburg",
        "ip_address":   "139.84.245.35",
        "ssh_password": "iD3=XCfxe[V)Xg6j",
        "wg_subnet":    "10.11.0",     # server = 10.11.0.1, clients = 10.11.0.2–254
    },
    # ── Add Hetzner here when ready ─────────────────────────────
    # {
    #     "id":           "hel-1",
    #     "name":         "Helsinki",
    #     "ip_address":   "<HETZNER_IP>",
    #     "ssh_password": "<HETZNER_PASSWORD>",
    #     "wg_subnet":    "10.12.0",
    # },
]


def make_wg_config_script(subnet: str) -> str:
    """
    Build the bash script that:
      - Reads the existing private/public key (already generated)
      - Writes a corrected wg0.conf with:
          * correct per-server subnet
          * full NAT PostUp (both FORWARD directions + MASQUERADE)
          * MSS clamping PostUp rule
          * IP forwarding ensured
      - Restarts wg-quick@wg0
    """
    server_ip = f"{subnet}.1"
    return f"""
#!/bin/bash
set -e

PRIVKEY=$(cat /etc/wireguard/privatekey)
PUBKEY=$(cat /etc/wireguard/publickey)
ETH=$(ip route ls default | awk '{{print $5}}' | head -n 1)

echo "Interface: $ETH"
echo "Server WG IP: {server_ip}/24"
echo "WG Public Key: $PUBKEY"

# ── Write corrected wg0.conf ────────────────────────────────────
# NOTE: SaveConfig = false avoids wg-quick save wiping PostUp rules
cat > /etc/wireguard/wg0.conf << WGEOF
[Interface]
Address = {server_ip}/24
ListenPort = 51820
PrivateKey = $PRIVKEY
SaveConfig = false

# NAT: forward VPN traffic to internet
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $ETH -j MASQUERADE; iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $ETH -j MASQUERADE; iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
WGEOF

# ── Ensure IP forwarding is persistent ──────────────────────────
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-wireguard.conf
sysctl -w net.ipv4.ip_forward=1

# ── Restart WireGuard ────────────────────────────────────────────
systemctl restart wg-quick@wg0
sleep 2
systemctl is-active wg-quick@wg0 && echo "WG_STATUS=active" || echo "WG_STATUS=failed"
wg show wg0 | head -5
echo "===FIX_DONE==="
"""


async def fix_server(s: dict) -> bool:
    try:
        import asyncssh
    except ImportError:
        logger.error("asyncssh not installed. Run: pip install asyncssh")
        return False

    name     = s["name"]
    ip       = s["ip_address"]
    password = s["ssh_password"]
    subnet   = s["wg_subnet"]
    script   = make_wg_config_script(subnet)

    logger.info(f"  [SSH] Connecting to {name} ({ip})...")
    try:
        async with asyncssh.connect(
            ip,
            username="root",
            password=password,
            known_hosts=None,
            connect_timeout=30,
        ) as conn:
            logger.info(f"  [SSH] Connected. Applying fixes...")
            result = await conn.run(script, timeout=60)

            output = result.stdout or ""
            stderr = result.stderr or ""

            for line in output.splitlines():
                if any(k in line for k in ["Interface:", "Server WG IP:", "WG_STATUS", "===FIX_DONE==="]):
                    logger.info(f"  [OUT] {line.strip()}")

            if "===FIX_DONE===" in output:
                if "WG_STATUS=active" in output:
                    logger.info(f"  ✅ {name} — WireGuard restarted and ACTIVE")
                    return True
                else:
                    logger.error(f"  ❌ {name} — WireGuard failed to start. Check server manually.")
                    logger.error(f"  stderr: {stderr[-500:]}")
                    return False
            else:
                logger.error(f"  ❌ {name} — Script did not complete.")
                logger.error(f"  output: {output[-500:]}")
                return False

    except Exception as e:
        logger.error(f"  ❌ {name} ({ip}) SSH error: {e}")
        return False


def fix_ip_pool(db):
    """
    Delete old wrong IP pool entries and re-seed with correct per-server subnets.
    Old entries were like 10.20.x.x, 10.21.x.x — now they'll be 10.8.x.x, 10.9.x.x etc.
    Also clears any old ASSIGNED entries so users need to re-provision (fresh start).
    """
    from models import IPPool, VPNConfig

    for s in SERVERS:
        server_id = s["id"]
        subnet    = s["wg_subnet"]   # e.g. "10.8.0"

        # Count current entries
        old_count = db.query(IPPool).filter_by(server_id=server_id).count()
        logger.info(f"  [DB] {server_id}: deleting {old_count} old IP pool entries...")

        # Delete all pool entries for this server
        db.query(IPPool).filter_by(server_id=server_id).delete()
        db.flush()

        # Also clear any vpn_configs assigned_ip for this server
        # (they'll need to re-provision with the new correct IPs)
        old_configs = db.query(VPNConfig).filter_by(server_id=server_id, is_active=True).all()
        for cfg in old_configs:
            cfg.assigned_ip = "needs-reprovision"
            cfg.is_active   = False   # force re-provision
        if old_configs:
            logger.info(f"  [DB] {server_id}: invalidated {len(old_configs)} existing vpn_configs (re-provision required)")

        # Re-seed with correct subnet — .2 to .254 (.1 is reserved for server)
        new_entries = []
        for host in range(2, 255):
            new_entries.append(IPPool(
                server_id=server_id,
                ip_address=f"{subnet}.{host}",
                is_assigned=False,
            ))
        db.bulk_save_objects(new_entries)
        db.flush()
        logger.info(f"  [DB] {server_id}: seeded 253 IPs ({subnet}.2 → {subnet}.254) ✅")


async def main():
    from models import SessionLocal

    logger.info("=" * 60)
    logger.info("  AtmosVPN — Server Fix Script (No-Internet Fix)")
    logger.info("=" * 60)

    # ── Step 1: Fix IP pool in DB ──────────────────────────────
    logger.info("\n[STEP 1] Fixing IP pool subnet assignments in database...")
    db = SessionLocal()
    try:
        fix_ip_pool(db)
        db.commit()
        logger.info("  [DB] IP pool fix committed ✅")
    except Exception as e:
        db.rollback()
        logger.exception(f"  [DB] Failed: {e}")
        sys.exit(1)
    finally:
        db.close()

    # ── Step 2: SSH fix each server ────────────────────────────
    logger.info("\n[STEP 2] Fixing WireGuard config on each server...")
    results = []
    for s in SERVERS:
        logger.info(f"\n{'─' * 50}")
        logger.info(f"  {s['name']} ({s['id']}) — {s['ip_address']}")
        logger.info(f"  New subnet: {s['wg_subnet']}.0/24  (server={s['wg_subnet']}.1)")
        ok = await fix_server(s)
        results.append({"server": s["name"], "ok": ok})

    # ── Summary ────────────────────────────────────────────────
    logger.info(f"\n{'=' * 60}")
    logger.info("  RESULTS")
    logger.info(f"{'=' * 60}")
    for r in results:
        status = "✅ Fixed" if r["ok"] else "❌ Failed"
        logger.info(f"  {status:15s}  {r['server']}")
    logger.info("")
    logger.info("Next steps:")
    logger.info("  1. Restart your VPN backend server")
    logger.info("  2. Users should DELETE their old WireGuard profile from the app")
    logger.info("  3. Users re-provision via POST /api/vpn/provision to get new IPs")
    logger.info("  4. Test with WireGuard app — internet should now work")


if __name__ == "__main__":
    asyncio.run(main())
