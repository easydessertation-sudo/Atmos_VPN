import asyncio
import asyncssh
import sys

# Fix Windows encoding
sys.stdout.reconfigure(encoding="utf-8")

servers = [
    {"name": "Tel Aviv",     "ip": "64.177.68.146",  "pwd": "5[Mq@Ku]TaDYzG--"},
    {"name": "Singapore",    "ip": "149.28.158.97",  "pwd": "B5z{C=S!V!d8nF3K"},
    {"name": "Johannesburg", "ip": "139.84.245.35",  "pwd": "iD3=XCfxe[V)Xg6j"},
    {"name": "Helsinki",     "ip": "204.168.212.162","pwd": "AtmosVPN@Hel2024!"},
    {"name": "Germany",      "ip": "178.105.51.242", "pwd": "AtmosVPN@Ger2024!"},
]

async def check(s):
    name = s["name"]
    try:
        async with asyncssh.connect(
            s["ip"], username="root", password=s["pwd"],
            known_hosts=None, connect_timeout=15
        ) as conn:
            r = await conn.run("systemctl is-active wg-quick@wg0 && wg show wg0 | head -6", timeout=20)
            status = r.stdout.strip() if r.stdout else r.stderr.strip()
            print(f"\n[{name}] OK - SSH connected")
            print(status)
    except Exception as e:
        print(f"\n[{name}] FAILED: {e}")

async def main():
    await asyncio.gather(*[check(s) for s in servers])

asyncio.run(main())
