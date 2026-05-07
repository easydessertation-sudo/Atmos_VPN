"""
live_check2.py — Live server verification (no emojis, runs on Windows)
"""
import asyncio
import logging
import os
from dotenv import load_dotenv
load_dotenv()

logging.disable(logging.CRITICAL)  # silence asyncssh noise

SERVERS = [
    ("Dallas",       "198.23.209.178", "cL47Nmm6Ha6YyQ4T5g"),
    ("Tel Aviv",     "64.177.68.146",  "5[Mq@Ku]TaDYzG--"),
    ("Singapore",    "149.28.158.97",  "B5z{C=S!V!d8nF3K"),
    ("Johannesburg", "139.84.245.35",  "iD3=XCfxe[V)Xg6j"),
]

CHECK_SCRIPT = """
ETH=$(ip route ls default | awk '{print $5}' | head -n 1)
echo "IFACE=$ETH"
echo "FWD=$(cat /proc/sys/net/ipv4/ip_forward)"
echo "WG=$(systemctl is-active wg-quick@wg0)"
echo "PEERS=$(wg show wg0 | grep -c '^  peer:' 2>/dev/null || echo 0)"
echo "HS=$(wg show wg0 | grep -c 'latest handshake' 2>/dev/null || echo 0)"
echo "NAT=$(iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -c MASQUERADE || echo 0)"
echo "UDP=$(ss -ulnp 2>/dev/null | grep -c 51820 || echo 0)"
echo "---WG_SHOW_START---"
wg show wg0 2>/dev/null
echo "---WG_SHOW_END---"
"""


async def check_server(name, ip, pwd):
    import asyncssh
    print(f"\n  {'='*50}")
    print(f"  Server: {name}  ({ip})")
    print(f"  {'='*50}")
    try:
        async with asyncssh.connect(
            ip, username="root", password=pwd,
            known_hosts=None, connect_timeout=20
        ) as conn:
            r = await conn.run(CHECK_SCRIPT, timeout=30)
            out = r.stdout or ""
            lines = out.splitlines()

            def get_val(key):
                for l in lines:
                    if l.startswith(key + "="):
                        return l.split("=", 1)[1].strip()
                return "?"

            iface   = get_val("IFACE")
            fwd     = get_val("FWD")
            wg      = get_val("WG")
            peers   = get_val("PEERS")
            hs      = get_val("HS")
            nat     = get_val("NAT")
            udp     = get_val("UDP")

            fwd_ok  = fwd == "1"
            wg_ok   = wg == "active"
            nat_ok  = nat != "0"
            udp_ok  = udp != "0"
            hs_ok   = hs != "0"

            print(f"  Interface:     {iface}")
            print(f"  IP Forwarding: {fwd}   {'[OK]' if fwd_ok else '[FAIL - must be 1!]'}")
            print(f"  WireGuard:     {wg}   {'[OK]' if wg_ok else '[FAIL - not running!]'}")
            print(f"  Peers:         {peers}   {'[OK]' if peers != '0' else '[FAIL - no peers registered!]'}")
            print(f"  Last Handshake:{hs}   {'[OK - client connected]' if hs_ok else '[FAIL - client never reached server!]'}")
            print(f"  NAT rules:     {nat}   {'[OK]' if nat_ok else '[FAIL - no MASQUERADE!]'}")
            print(f"  UDP 51820:     {udp}   {'[OK - listening]' if udp_ok else '[FAIL - not listening!]'}")

            # Show wg output
            in_wg = False
            print(f"\n  wg show wg0:")
            for line in lines:
                if "---WG_SHOW_START---" in line:
                    in_wg = True
                    continue
                if "---WG_SHOW_END---" in line:
                    in_wg = False
                if in_wg:
                    print(f"    {line}")

            # Diagnosis
            print(f"\n  DIAGNOSIS:")
            issues = []
            if not fwd_ok:  issues.append("IP forwarding is OFF -> sysctl -w net.ipv4.ip_forward=1")
            if not wg_ok:   issues.append("WireGuard is NOT running -> systemctl start wg-quick@wg0")
            if peers == "0": issues.append("NO peers registered on this server -> client pubkey not added")
            if not hs_ok and peers != "0":  issues.append("NO handshake -> UDP 51820 is BLOCKED upstream (check provider firewall/security group!)")
            if not nat_ok:  issues.append("No NAT rule -> no internet after tunnel")

            if not issues:
                print(f"  [ALL OK] Server is correctly configured.")
            else:
                for i, issue in enumerate(issues, 1):
                    print(f"  [{i}] {issue}")

            return {
                "name": name, "wg": wg_ok, "fwd": fwd_ok,
                "peers": peers, "hs": hs_ok, "nat": nat_ok, "udp": udp_ok
            }
    except Exception as e:
        print(f"  SSH FAILED: {e}")
        return {"name": name, "error": str(e)}


async def main():
    print("=" * 55)
    print("  AtmosVPN - Live Server State Check")
    print("=" * 55)
    results = []
    for s in SERVERS:
        r = await check_server(*s)
        results.append(r)

    print(f"\n{'='*55}")
    print(f"  FINAL SUMMARY")
    print(f"{'='*55}")
    for r in results:
        if "error" in r:
            print(f"  [FAIL] {r['name']:15s}  SSH ERROR: {r['error']}")
        else:
            ok = r.get("wg") and r.get("fwd") and r.get("nat")
            hs = "[HS:YES]" if r.get("hs") else "[HS:NO - HANDSHAKE NEVER COMPLETED]"
            status = "[OK]" if ok else "[ISSUES]"
            print(f"  {status} {r['name']:15s}  peers={r['peers']}  {hs}")


if __name__ == "__main__":
    asyncio.run(main())
