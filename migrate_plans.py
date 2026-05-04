"""
Migration: Update plan names and bandwidth limits for new plan structure.
  - Renames: essential->starter, elite->pro, ultimate->premium (if any exist)
  - Sets free users bandwidth_limit_bytes to 10 GB
  - Sets starter users to 100 GB
Run once: python migrate_plans.py
"""
import os
import sys
sys.stdout.reconfigure(encoding='utf-8')

from dotenv import load_dotenv
from sqlalchemy import create_engine, text

load_dotenv()

DATABASE_URL = os.environ.get("DATABASE_URL", "")
if not DATABASE_URL:
    print("ERROR: DATABASE_URL not found in .env")
    exit(1)

engine = create_engine(DATABASE_URL)

GB_10  = 10_737_418_240
GB_100 = 107_374_182_400

with engine.connect() as conn:
    # 1. Rename old plan names to new ones (in case any users have them)
    renames = [
        ("essential", "starter"),
        ("elite",     "pro"),
        ("ultimate",  "premium"),
    ]
    for old, new in renames:
        r = conn.execute(text(f"UPDATE users SET plan = '{new}' WHERE plan = '{old}'"))
        if r.rowcount > 0:
            print(f"OK: Renamed {r.rowcount} user(s) from plan '{old}' -> '{new}'")

    # 2. Set free users to 10 GB bandwidth limit
    r = conn.execute(text(
        f"UPDATE users SET bandwidth_limit_bytes = {GB_10} WHERE plan = 'free'"
    ))
    print(f"OK: Set {r.rowcount} free user(s) to 10 GB bandwidth limit")

    # 3. Set starter users to 100 GB bandwidth limit
    r = conn.execute(text(
        f"UPDATE users SET bandwidth_limit_bytes = {GB_100} WHERE plan = 'starter'"
    ))
    print(f"OK: Set {r.rowcount} starter user(s) to 100 GB bandwidth limit")

    # 4. Set pro/premium users to NULL (unlimited) bandwidth limit
    r = conn.execute(text(
        "UPDATE users SET bandwidth_limit_bytes = NULL WHERE plan IN ('pro', 'premium')"
    ))
    print(f"OK: Set {r.rowcount} pro/premium user(s) to unlimited bandwidth")

    # 5. Also rename plan in subscriptions table if any exist
    for old, new in renames:
        r = conn.execute(text(f"UPDATE subscriptions SET plan = '{new}' WHERE plan = '{old}'"))
        if r.rowcount > 0:
            print(f"OK: Renamed {r.rowcount} subscription(s) from '{old}' -> '{new}'")

    conn.commit()

print("\nDone! Plan migration complete.")
