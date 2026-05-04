"""
One-time migration script.
Adds the 6 Security Center columns to the 'users' table in PostgreSQL.
Run once:  python migrate_security_columns.py
"""
import os
import sys

# Fix Windows console encoding
sys.stdout.reconfigure(encoding='utf-8')

from dotenv import load_dotenv
from sqlalchemy import create_engine, text

load_dotenv()

DATABASE_URL = os.environ.get("DATABASE_URL", "")

if not DATABASE_URL:
    print("ERROR: DATABASE_URL not found in .env. Aborting.")
    exit(1)

engine = create_engine(DATABASE_URL)

columns = [
    ("kill_switch_enabled",     "BOOLEAN", "TRUE"),
    ("auto_connect_wifi",       "BOOLEAN", "FALSE"),
    ("dns_leak_protection",     "BOOLEAN", "TRUE"),
    ("ad_blocker_enabled",      "BOOLEAN", "TRUE"),
    ("tracker_blocker_enabled", "BOOLEAN", "FALSE"),
    ("malware_protection",      "BOOLEAN", "TRUE"),
]

with engine.connect() as conn:
    for col_name, col_type, col_default in columns:
        try:
            sql = text(
                f"ALTER TABLE users ADD COLUMN IF NOT EXISTS "
                f"{col_name} {col_type} NOT NULL DEFAULT {col_default};"
            )
            conn.execute(sql)
            print(f"OK: Added column: {col_name}")
        except Exception as e:
            print(f"WARN: Column {col_name}: {e}")
    conn.commit()

print("\nDone! All Security Center columns added to the database.")
