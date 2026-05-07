"""
fix_stale_configs.py
====================
Deactivates all VPN configs that point to fake/offline servers.
Users will need to re-provision to get a fresh config for a real server.

Run once:
    .\\venv\\Scripts\\python fix_stale_configs.py
"""
from dotenv import load_dotenv
load_dotenv()

from models import SessionLocal, VPNConfig, VPNServer

FAKE_SERVER_IDS = [
    "lon-1", "lon-2", "ams-1", "par-1", "nyc-1",
    "tok-1", "zur-1", "sto-1", "mum-1", "dub-1",
    "tor-1", "sao-1", "syd-1",
]

db = SessionLocal()
deactivated = 0
for sid in FAKE_SERVER_IDS:
    configs = db.query(VPNConfig).filter_by(server_id=sid, is_active=True).all()
    for c in configs:
        c.is_active = False
        deactivated += 1
        print(f"Deactivated: config {c.id} | user {c.user_id} | server {sid} | ip {c.assigned_ip}")

db.commit()
print(f"\nTotal deactivated: {deactivated}")

print("\n=== Remaining ACTIVE configs (real servers only) ===")
active = db.query(VPNConfig).filter_by(is_active=True).all()
for c in active:
    srv = db.get(VPNServer, c.server_id)
    srv_ip = srv.ip_address if srv else "UNKNOWN"
    print(f"  user={str(c.user_id)[:8]}  server={c.server_id}  endpoint={srv_ip}  client_ip={c.assigned_ip}  pubkey={c.public_key[:20]}...")

db.close()
print("\nDone. Tell users to re-import VPN config in the app (call /api/vpn/provision again).")
