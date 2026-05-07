"""
live_check.py — Live server verification
SSHes into all 4 servers and checks the exact current state:
  - WireGuard status + peer list + handshake times
  - iptables NAT rules (is MASQUERADE actually active?)
  - IP forwarding state
  - Routing table

Run: .\\venv\\Scripts\\python live_check.py
"""
import asyncio, logging, os
from dotenv import load_dotenv
load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", datefmt="%H:%M:%S")
logger = logging.getLogger(__name__)

SERVERS = [
    {"name": "Dallas",       "ip": "198.23.209.178", "password": "cL47Nmm6Ha6YyQ4T5g"},
    {"name": "Tel Aviv",     "ip": "64.177.68.146",  "password": "5[Mq@Ku]TaDYzG--"},
    {"name": "Singapore",    "ip": "149.28.158.97",  "password": "B5z{C=S!V!d8nF3K"},
    {"name": "Johannesburg", "ip": "139.84.245.35",  "password": "iD3=XCfxe[V)Xg6j"},
]

CHECK_SCRIPT = r"""
ETH=$(ip route ls default | awk '{print $5}' | head -n 1)
echo ">>> INTERFACE: $ETH"
echo ""
echo ">>> IP FORWARDING:"
cat /proc/sys/net/ipv4/ip_forward
echo ""
echo ">>> WG STATUS:"
systemctl is-active wg-quick@wg0
echo ""
echo ">>> WG SHOW (peers + last handshake):"
wg show wg0
echo ""
echo ">>> NAT MASQUERADE RULES:"
iptables -t nat -L POSTROUTING -n -v | grep -v "^$" | grep -v "^Chain" | head -20
echo ""
echo ">>> FORWARD RULES:"
iptables -L FORWARD -n | grep -v "^$" | grep -v "^Chain" | head -10
echo ""
echo ">>> DEFAULT ROUTE:"
ip route | grep default
echo ">>> DONE"
"""

async def check_server(s):
    import asyncssh
    name, ip, pwd = s["name"], s["ip"], s["password"]
    print(f"\n{'='*60}")
    print(f"  {name}  ({ip})")
    print(f"{'='*60}")
    try:
        async with asyncssh.connect(ip, username="root", password=pwd,
                                    known_hosts=None, connect_timeout=20) as conn:
            r = await conn.run(CHECK_SCRIPT, timeout=30)
            out = r.stdout or ""
            # Print key lines only
            important_keys = [
                ">>> ", "active", "inactive", "interface", "peer:", "endpoint:",
                "allowed ips:", "latest handshake:", "transfer:", "MASQUERADE",
                "ACCEPT", "ip_forward", "default via"
            ]
            for line in out.splitlines():
                if any(k.lower() in line.lower() for k in important_keys):
                    print(f"  {line}")
            # Summarise
            has_peer     = "peer:" in out.lower()
            has_nat      = "masquerade" in out.lower()
            ip_fwd       = "1" in (out.split(">>> IP FORWARDING:")[1].split("\n")[1] if "IP FORWARDING" in out else "0")
            wg_active    = "active" in out and "inactive" not in out
            handshake    = "latest handshake:" in out.lower()
            print(f"\n  {'✅' if wg_active else '❌'} WireGuard ACTIVE")
            print(f"  {'✅' if has_peer else '❌'} Peers registered")
            print(f"  {'✅' if handshake else '⚠️ '} Recent handshake")
            print(f"  {'✅' if has_nat else '❌'} NAT MASQUERADE active")
            print(f"  {'✅' if ip_fwd else '❌'} IP forwarding ON")
            return {"name": name, "wg": wg_active, "peer": has_peer, "nat": has_nat, "fwd": ip_fwd, "hs": handshake}
    except Exception as e:
        print(f"  ❌ SSH FAILED: {e}")
        return {"name": name, "error": str(e)}

async def main():
    print("="*60)
    print("  AtmosVPN — Live Server State Check")
    print("="*60)
    results = [await check_server(s) for s in SERVERS]
    print(f"\n{'='*60}")
    print("  SUMMARY")
    print(f"{'='*60}")
    for r in results:
        if "error" in r:
            print(f"  ❌ {r['name']:15s}  SSH FAILED: {r['error']}")
        else:
            ok = all([r["wg"], r["nat"], r["fwd"]])
            print(f"  {'✅' if ok else '❌'} {r['name']:15s}  WG={'on' if r['wg'] else 'OFF'}  "
                  f"Peers={'yes' if r['peer'] else 'NO'}  NAT={'yes' if r['nat'] else 'NO'}  "
                  f"FWD={'on' if r['fwd'] else 'OFF'}  HS={'yes' if r['hs'] else 'no'}")

asyncio.run(main())
