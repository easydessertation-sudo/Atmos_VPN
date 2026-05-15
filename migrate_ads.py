"""
migrate_ads.py
--------------
One-time migration: creates the `ads` and `ad_views` tables in your
existing database (Supabase / SQLite).

Run once:
    cd vpn-backend
    python migrate_ads.py
"""
from models import Base, engine, Ad, AdView

print("Creating ads and ad_views tables...")
Base.metadata.create_all(bind=engine, tables=[
    Ad.__table__,
    AdView.__table__,
])
print("[OK] Done - ads and ad_views tables are ready.")
