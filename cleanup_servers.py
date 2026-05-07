"""
cleanup_servers.py
==================
Marks all fake seeded servers as offline and ensures only the 4 real
servers (Dallas, Tel Aviv, Singapore, Johannesburg) are visible in the API.

Run once:
    .\\venv\\Scripts\\python cleanup_servers.py
"""
from dotenv import load_dotenv
load_dotenv()

from models import SessionLocal, VPNServer
import logging

logging.basicConfig(level=logging.INFO, format="%(levelname)s  %(message)s")
logger = logging.getLogger(__name__)

# These are the 4 real servers with confirmed working IPs
REAL_SERVERS = {
    "dal-1": {
        "name": "Dallas", "city": "Dallas", "country": "United States",
        "country_code": "us", "flag": "🇺🇸", "ping_ms": 120,
        "ip_address": "198.23.209.178",
    },
    "tlv-1": {
        "name": "Tel Aviv", "city": "Tel Aviv", "country": "Israel",
        "country_code": "il", "flag": "🇮🇱", "ping_ms": 80,
        "ip_address": "64.177.68.146",
    },
    "sgp-2": {
        "name": "Singapore", "city": "Singapore", "country": "Singapore",
        "country_code": "sg", "flag": "🇸🇬", "ping_ms": 60,
        "ip_address": "149.28.158.97",
    },
    "jnb-1": {
        "name": "Johannesburg", "city": "Johannesburg", "country": "South Africa",
        "country_code": "za", "flag": "🇿🇦", "ping_ms": 170,
        "ip_address": "139.84.245.35",
    },
}

# Fake seeded IDs to take offline
FAKE_SERVER_IDS = [
    "lon-1", "lon-2", "nyc-1", "lax-1", "fra-1",
    "ams-1", "tok-1", "sgp-1", "par-1",
]


def main():
    db = SessionLocal()
    try:
        logger.info("=" * 55)
        logger.info("  Server DB Cleanup")
        logger.info("=" * 55)

        # ── 1. Disable all fake seed servers ──────────────────────
        logger.info("\n[1] Marking fake seed servers as offline...")
        for sid in FAKE_SERVER_IDS:
            s = db.get(VPNServer, sid)
            if s:
                s.is_online = False
                logger.info(f"   ❌ offline → {sid} ({s.name})")
            else:
                logger.info(f"   SKIP: {sid} not in DB")

        db.commit()

        # ── 2. Ensure all 4 real servers are online & correct ─────
        logger.info("\n[2] Ensuring real servers are online with correct data...")
        for sid, data in REAL_SERVERS.items():
            s = db.get(VPNServer, sid)
            if s:
                s.is_online    = True
                s.name         = data["name"]
                s.city         = data["city"]
                s.country      = data["country"]
                s.country_code = data["country_code"]
                s.flag         = data["flag"]
                s.ping_ms      = data["ping_ms"]
                s.ip_address   = data["ip_address"]
                logger.info(f"   ✅ updated → {sid} ({s.name}) @ {s.ip_address}")
            else:
                # Create it fresh
                s = VPNServer(
                    id=sid,
                    name=data["name"],
                    city=data["city"],
                    country=data["country"],
                    country_code=data["country_code"],
                    flag=data["flag"],
                    ping_ms=data["ping_ms"],
                    ip_address=data["ip_address"],
                    wg_port=51820,
                    is_online=True,
                    capacity_mbps=1000,
                    max_peers=500,
                    current_peers=0,
                    load_pct=0,
                    is_streaming=True,
                    is_gaming=True,
                    is_p2p=True,
                    is_crypto=False,
                )
                db.add(s)
                logger.info(f"   ✅ created → {sid} ({s.name})")

        db.commit()

        # ── 3. Print final state ───────────────────────────────────
        logger.info("\n[3] Final server list (is_online=True only):")
        online = db.query(VPNServer).filter_by(is_online=True).order_by(VPNServer.ping_ms).all()
        for s in online:
            logger.info(f"   {s.flag}  {s.id:10s}  {s.name:20s}  {s.ip_address or 'NO IP':18s}  {s.ping_ms}ms")

        logger.info(f"\n   Total online servers: {len(online)}")
        logger.info("\n✅ Done! Restart the backend to clear any Redis cache.")

    finally:
        db.close()


if __name__ == "__main__":
    main()
