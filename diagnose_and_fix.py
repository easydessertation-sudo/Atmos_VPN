"""
diagnose_and_fix.py
===================
Diagnoses and fixes the WireGuard handshake failure on all real servers.

Root cause of "Handshake did not complete after 5 seconds":
  → UDP port 51820 is blocked by iptables/UFW
  → WireGuard receives the packet but OS drops it before WG can respond

Fixes applied:
  1. Force-open UDP 51820 directly in iptables (bypass UFW issues)
  2. Force-open UDP 51820 in UFW (if UFW is active)
  3. Verify WireGuard is listening on 51820
  4. Run wg show to confirm peer list
  5. Re-apply NAT rule for 10.0.0.0/8 (just in case)
  6. Print full diagnostic output for each server

Usage:
    .\\venv\\Scripts\\python diagnose_and_fix.py
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

SERVERS = [
    {"name": "Dallas (LA)",  "ip": "198.23.209.178", "password": "cL47Nmm6Ha6YyQ4T5g"},
    {"name": "Tel Aviv (Frankfurt)", "ip": "64.177.68.146",  "password": "5[Mq@Ku]TaDYzG--"},
    {"name": "Singapore",    "ip": "149.28.158.97",  "password": "B5z{C=S!V!d8nF3K"},
    {"name": "Johannesburg", "ip": "139.84.245.35",  "password": "iD3=XCfxe[V)Xg6j"},
]

DIAGNOSE_AND_FIX_SCRIPT = r"""
#!/bin/bash
ETH=$(ip route ls default | awk '{print $5}' | head -n 1)
echo "=== INTERFACE: $ETH ==="

# ── 1. Force-open UDP 51820 in raw iptables (most reliable) ──────
echo ""
echo "=== STEP 1: Force-open UDP 51820 in iptables ==="
# Remove any existing DROP rules for 51820 first
iptables -D INPUT -p udp --dport 51820 -j DROP 2>/dev/null || true
# Add ACCEPT rules (prepend so they run before any DROP)
iptables -I INPUT 1 -p udp --dport 51820 -j ACCEPT
iptables -I INPUT 1 -p udp --sport 51820 -j ACCEPT
echo "iptables INPUT rules for 51820:"
iptables -L INPUT -n --line-numbers | grep -E "51820|ACCEPT|DROP" | head -10

# ── 2. UFW: allow 51820/udp and OpenSSH ──────────────────────────
echo ""
echo "=== STEP 2: UFW status and rules ==="
ufw status | head -5
ufw allow 51820/udp 2>/dev/null && echo "UFW: 51820/udp allowed" || echo "UFW not active or rule exists"
ufw allow OpenSSH   2>/dev/null || true

# ── 3. Re-apply NAT masquerade for all VPN subnets ───────────────
echo ""
echo "=== STEP 3: NAT masquerade rules ==="
# Clear any duplicate MASQUERADE rules first
iptables -t nat -D POSTROUTING -s 10.0.0.0/8 -o $ETH -j MASQUERADE 2>/dev/null || true
# Add clean rule
iptables -t nat -A POSTROUTING -s 10.0.0.0/8 -o $ETH -j MASQUERADE
echo "NAT POSTROUTING rules:"
iptables -t nat -L POSTROUTING -n | grep -E "MASQUERADE|Chain"

# ── 4. MSS clamping (mobile network compatibility) ───────────────
echo ""
echo "=== STEP 4: MSS clamping ==="
iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
echo "MSS clamp rule applied."

# ── 5. IP forwarding confirmed ────────────────────────────────────
echo ""
echo "=== STEP 5: IP forwarding ==="
sysctl -w net.ipv4.ip_forward=1
cat /proc/sys/net/ipv4/ip_forward

# ── 6. Check WireGuard is listening on UDP 51820 ──────────────────
echo ""
echo "=== STEP 6: WireGuard listening check ==="
systemctl is-active wg-quick@wg0 && echo "wg-quick@wg0: ACTIVE" || echo "wg-quick@wg0: NOT ACTIVE"
ss -ulnp | grep 51820 && echo "UDP 51820: LISTENING" || echo "UDP 51820: NOT LISTENING!"

# ── 7. Show current WireGuard peers ──────────────────────────────
echo ""
echo "=== STEP 7: wg show wg0 ==="
wg show wg0

echo ""
echo "=== DONE ==="
"""


async def fix_server(s: dict) -> dict:
    try:
        import asyncssh
    except ImportError:
        logger.error("asyncssh not installed.")
        return {"server": s["name"], "ok": False, "wg_listening": False, "peers": 0}

    name = s["name"]
    ip   = s["ip"]
    pwd  = s["password"]

    logger.info(f"\n{'='*60}")
    logger.info(f"  {name}  |  {ip}")
    logger.info(f"{'='*60}")

    try:
        async with asyncssh.connect(
            ip, username="root", password=pwd,
            known_hosts=None, connect_timeout=20,
        ) as conn:
            result = await conn.run(DIAGNOSE_AND_FIX_SCRIPT, timeout=60)
            output = result.stdout or ""

            # Parse key status lines
            wg_active   = "wg-quick@wg0: ACTIVE" in output
            listening   = "UDP 51820: LISTENING" in output
            peer_lines  = [l for l in output.splitlines() if "peer:" in l.lower()]
            peer_count  = len(peer_lines)
            iface_line  = [l for l in output.splitlines() if "=== INTERFACE:" in l]
            interface   = iface_line[0].replace("=== INTERFACE:", "").replace("===","").strip() if iface_line else "unknown"

            # Print summary lines
            for line in output.splitlines():
                if any(kw in line for kw in [
                    "=== STEP", "INTERFACE", "ACTIVE", "NOT ACTIVE",
                    "LISTENING", "peer:", "allowed ips", "MASQUERADE",
                    "ip_forward", "=== DONE"
                ]):
                    logger.info(f"  {line.strip()}")

            if not wg_active:
                logger.error(f"  ❌ WireGuard is NOT active on {name}! Restarting...")
                await conn.run("systemctl restart wg-quick@wg0", timeout=30)
                await asyncio.sleep(3)
                result2 = await conn.run("systemctl is-active wg-quick@wg0 && ss -ulnp | grep 51820")
                logger.info(f"  After restart: {result2.stdout.strip()}")

            return {
                "server":    name,
                "ip":        ip,
                "interface": interface,
                "wg_active": wg_active,
                "listening": listening,
                "peers":     peer_count,
                "ok":        wg_active and listening,
            }

    except Exception as e:
        logger.error(f"  ❌ SSH failed: {e}")
        return {"server": name, "ok": False, "error": str(e)}


async def main():
    logger.info("=" * 60)
    logger.info("  AtmosVPN — Handshake Fix Diagnostic")
    logger.info("  Fixing: 'Handshake did not complete after 5s'")
    logger.info("=" * 60)

    results = []
    for s in SERVERS:
        r = await fix_server(s)
        results.append(r)

    logger.info(f"\n{'='*60}")
    logger.info("  FINAL SUMMARY")
    logger.info(f"{'='*60}")
    for r in results:
        status = "✅ READY" if r.get("ok") else "❌ ISSUE"
        listen = "UDP:51820 OPEN" if r.get("listening") else "UDP:51820 BLOCKED"
        peers  = f"{r.get('peers', 0)} peers"
        logger.info(f"  {status}  {r.get('server'):25s}  {listen}  {peers}")

    logger.info("")
    all_ok = all(r.get("ok") for r in results)
    if all_ok:
        logger.info("  ✅ All servers ready — handshake should now succeed!")
        logger.info("  Tell users to toggle WireGuard OFF then ON in the app.")
    else:
        logger.info("  ❌ Some servers still have issues — check output above.")


if __name__ == "__main__":
    asyncio.run(main())
