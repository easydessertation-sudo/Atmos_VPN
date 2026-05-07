"""
init_real_servers.py
====================
One-time setup script for your real VPN servers (RackNerd + Vultr).

What it does:
  1. Upserts each server record into the Supabase database
  2. SSHes into each server using root password
  3. Installs WireGuard + configures wg0 interface
  4. Reads back the server's WireGuard public key
  5. Saves the public key into the DB so the backend can build client .conf files

Run once per server.  Safe to re-run — skips servers that already have a public key.

Usage:
    cd vpn-backend
    .\\venv\\Scripts\\python init_real_servers.py
"""

import asyncio
import logging
import random
import sys
from datetime import datetime

from dotenv import load_dotenv
load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────────────────────────
# Real server definitions
# Add Hetzner entry here once the server is provisioned.
# ─────────────────────────────────────────────────────────────────
REAL_SERVERS = [
    {
        "id":           "dal-1",
        "name":         "Dallas",
        "city":         "Dallas",
        "country":      "United States",
        "country_code": "us",
        "flag":         "🇺🇸",
        "provider":     "RackNerd",
        "ip_address":   "198.23.209.178",
        "ssh_user":     "root",
        "ssh_password": "cL47Nmm6Ha6YyQ4T5g",
        "ping_ms":      90,
        "capacity_mbps": 1000,
        "is_streaming": True,
        "is_gaming":    True,
        "is_crypto":    False,
        "is_p2p":       True,
    },
    {
        "id":           "tlv-1",
        "name":         "Tel Aviv",
        "city":         "Tel Aviv",
        "country":      "Israel",
        "country_code": "il",
        "flag":         "🇮🇱",
        "provider":     "Vultr",
        "ip_address":   "64.177.68.146",
        "ssh_user":     "root",
        "ssh_password": "5[Mq@Ku]TaDYzG--",
        "ping_ms":      60,
        "capacity_mbps": 1000,
        "is_streaming": True,
        "is_gaming":    False,
        "is_crypto":    True,
        "is_p2p":       False,
    },
    {
        "id":           "sgp-2",
        "name":         "Singapore",
        "city":         "Singapore",
        "country":      "Singapore",
        "country_code": "sg",
        "flag":         "🇸🇬",
        "provider":     "Vultr",
        "ip_address":   "149.28.158.97",
        "ssh_user":     "root",
        "ssh_password": "B5z{C=S!V!d8nF3K",
        "ping_ms":      40,
        "capacity_mbps": 1000,
        "is_streaming": True,
        "is_gaming":    True,
        "is_crypto":    True,
        "is_p2p":       False,
    },
    {
        "id":           "jnb-1",
        "name":         "Johannesburg",
        "city":         "Johannesburg",
        "country":      "South Africa",
        "country_code": "za",
        "flag":         "🇿🇦",
        "provider":     "Vultr",
        "ip_address":   "139.84.245.35",
        "ssh_user":     "root",
        "ssh_password": "iD3=XCfxe[V)Xg6j",
        "ping_ms":      130,
        "capacity_mbps": 1000,
        "is_streaming": True,
        "is_gaming":    False,
        "is_crypto":    False,
        "is_p2p":       False,
    },
    # ── Add Hetzner here once IP and password are available ──────
    # {
    #     "id":           "hel-1",
    #     "name":         "Helsinki",
    #     "city":         "Helsinki",
    #     "country":      "Finland",
    #     "country_code": "fi",
    #     "flag":         "🇫🇮",
    #     "provider":     "Hetzner",
    #     "ip_address":   "<HETZNER_IP>",
    #     "ssh_user":     "root",
    #     "ssh_password": "<HETZNER_PASSWORD>",
    #     "ping_ms":      30,
    #     "capacity_mbps": 1000,
    #     "is_streaming": True,
    #     "is_gaming":    True,
    #     "is_crypto":    False,
    #     "is_p2p":       True,
    # },
]


# ─────────────────────────────────────────────────────────────────
# WireGuard setup bash script (runs on each server as root)
# ─────────────────────────────────────────────────────────────────
WG_SETUP_SCRIPT = r"""
export DEBIAN_FRONTEND=noninteractive

# ── Install WireGuard ────────────────────────────────────────────
apt-get update -q 2>/dev/null
apt-get install -y -q wireguard iptables ufw 2>/dev/null

# ── Generate keys (skip if already exist) ───────────────────────
mkdir -p /etc/wireguard
cd /etc/wireguard
if [ ! -f privatekey ]; then
    umask 077
    wg genkey | tee privatekey | wg pubkey > publickey
    echo "Keys generated."
else
    echo "Keys already exist — reusing."
fi

PRIVKEY=$(cat /etc/wireguard/privatekey)
PUBKEY=$(cat /etc/wireguard/publickey)

# ── Detect main network interface (eth0, ens3, ens4, enp1s0…) ──
ETH_IFACE=$(ip route ls default | awk '{print $5}' | head -n 1)

# ── Write wg0.conf ───────────────────────────────────────────────
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = 10.8.0.1/24
SaveConfig = true
ListenPort = 51820
PrivateKey = $PRIVKEY
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $ETH_IFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $ETH_IFACE -j MASQUERADE
EOF

# ── Enable IP forwarding ─────────────────────────────────────────
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-wireguard.conf
sysctl -p /etc/sysctl.d/99-wireguard.conf 2>/dev/null

# ── UFW: allow WireGuard port + SSH ─────────────────────────────
ufw allow 51820/udp 2>/dev/null || true
ufw allow OpenSSH   2>/dev/null || true

# ── Start WireGuard ──────────────────────────────────────────────
systemctl enable  wg-quick@wg0 2>/dev/null
systemctl restart wg-quick@wg0

# ── Output public key for Python to capture ─────────────────────
echo "===WG_PUBKEY_START==="
echo $PUBKEY
echo "===WG_PUBKEY_END==="
"""


# ─────────────────────────────────────────────────────────────────
# DB helpers
# ─────────────────────────────────────────────────────────────────
def upsert_server(db, s: dict):
    """Insert server if it doesn't exist; update IP if it changed."""
    from models import VPNServer, IPPool

    existing = db.get(VPNServer, s["id"])
    if existing:
        logger.info(f"  [DB] Server '{s['id']}' already exists — updating IP/flags.")
        existing.ip_address   = s["ip_address"]
        existing.name         = s["name"]
        existing.city         = s["city"]
        existing.country      = s["country"]
        existing.country_code = s["country_code"]
        existing.flag         = s["flag"]
        existing.ping_ms      = s["ping_ms"]
        existing.capacity_mbps = s["capacity_mbps"]
        existing.is_streaming = s.get("is_streaming", False)
        existing.is_gaming    = s.get("is_gaming",    False)
        existing.is_crypto    = s.get("is_crypto",    False)
        existing.is_p2p       = s.get("is_p2p",       False)
        existing.is_online    = True
        db.flush()
        return existing
    else:
        logger.info(f"  [DB] Inserting new server '{s['id']}'.")
        server = VPNServer(
            id=s["id"],
            name=s["name"],
            city=s["city"],
            country=s["country"],
            country_code=s["country_code"],
            flag=s["flag"],
            ip_address=s["ip_address"],
            ping_ms=s["ping_ms"],
            capacity_mbps=s["capacity_mbps"],
            load_pct=random.randint(5, 30),
            is_online=True,
            is_streaming=s.get("is_streaming", False),
            is_gaming=s.get("is_gaming",    False),
            is_crypto=s.get("is_crypto",    False),
            is_p2p=s.get("is_p2p",       False),
            wg_port=51820,
            max_peers=500,
            current_peers=0,
            protocols="wireguard,openvpn,ikev2",
        )
        db.add(server)
        db.flush()

        # Seed IP pool for this server — 253 usable IPs in a /24 subnet
        index = REAL_SERVERS.index(next(x for x in REAL_SERVERS if x["id"] == s["id"]))
        existing_pool = db.query(IPPool).filter_by(server_id=s["id"]).count()
        if existing_pool == 0:
            for host in range(2, 255):   # 10.8.x.2 → 10.8.x.254 (skip .1 = server itself)
                db.add(IPPool(
                    server_id=s["id"],
                    ip_address=f"10.{20 + index}.0.{host}",
                    is_assigned=False,
                ))
            logger.info(f"  [DB] Seeded 253 IPs for server '{s['id']}'.")

        return server


# ─────────────────────────────────────────────────────────────────
# SSH setup (password auth via asyncssh)
# ─────────────────────────────────────────────────────────────────
async def setup_wireguard(s: dict) -> str | None:
    """SSH into server with password, run WireGuard setup, return public key."""
    try:
        import asyncssh
    except ImportError:
        logger.error("asyncssh not installed. Run:  pip install asyncssh")
        return None

    ip       = s["ip_address"]
    user     = s["ssh_user"]
    password = s["ssh_password"]
    name     = s["name"]

    logger.info(f"  [SSH] Connecting to {name} ({ip}) as {user}...")
    try:
        async with asyncssh.connect(
            ip,
            username=user,
            password=password,
            known_hosts=None,               # skip host key verification for setup
            connect_timeout=30,
        ) as conn:
            logger.info(f"  [SSH] Connected to {name}! Running WireGuard setup (this takes ~30s)...")
            result = await conn.run(WG_SETUP_SCRIPT, timeout=120)

            output = result.stdout or ""
            stderr = result.stderr or ""

            if result.exit_status != 0:
                logger.warning(f"  [SSH] Exit status {result.exit_status} on {name}")
                if stderr:
                    logger.debug(f"  [SSH] stderr: {stderr[:500]}")

            # Extract public key from the sentinel markers
            if "===WG_PUBKEY_START===" in output and "===WG_PUBKEY_END===" in output:
                pubkey = (
                    output
                    .split("===WG_PUBKEY_START===")[1]
                    .split("===WG_PUBKEY_END===")[0]
                    .strip()
                )
                if pubkey:
                    logger.info(f"  [SSH] ✅ {name} WireGuard public key: {pubkey}")
                    return pubkey
                else:
                    logger.error(f"  [SSH] ❌ Empty public key captured from {name}.")
            else:
                logger.error(f"  [SSH] ❌ Could not find public key markers in output from {name}.")
                logger.debug(f"  Output snippet: {output[-500:]}")
            return None

    except Exception as e:
        logger.error(f"  [SSH] ❌ Failed to connect/setup {name} ({ip}): {e}")
        return None


# ─────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────
async def main():
    from models import SessionLocal, VPNServer

    logger.info("=" * 60)
    logger.info("  AtmosVPN — Real Server Initialisation")
    logger.info("=" * 60)

    db = SessionLocal()
    results = []

    try:
        for s in REAL_SERVERS:
            logger.info(f"\n{'─'*50}")
            logger.info(f"Processing: {s['name']} ({s['provider']})  |  {s['ip_address']}")

            # 1. Upsert server in DB
            server = upsert_server(db, s)

            # 2. Skip if already has a WireGuard public key
            if server.wg_public_key:
                logger.info(f"  [SKIP] Already has WireGuard key: {server.wg_public_key[:20]}...")
                results.append({"server": s["name"], "status": "already_configured", "key": server.wg_public_key})
                continue

            # 3. SSH + install WireGuard
            pubkey = await setup_wireguard(s)

            if pubkey:
                server.wg_public_key = pubkey
                server.wg_port       = 51820
                results.append({"server": s["name"], "status": "✅ configured", "key": pubkey})
            else:
                results.append({"server": s["name"], "status": "❌ failed",     "key": None})

        db.commit()
        logger.info(f"\n{'='*60}")
        logger.info("  RESULTS SUMMARY")
        logger.info(f"{'='*60}")
        for r in results:
            logger.info(f"  {r['status']:20s}  {r['server']}")
            if r["key"]:
                logger.info(f"  {'':20s}  WG key: {r['key']}")
        logger.info("")

    except Exception as e:
        db.rollback()
        logger.exception(f"Fatal error: {e}")
        sys.exit(1)
    finally:
        db.close()


if __name__ == "__main__":
    asyncio.run(main())
