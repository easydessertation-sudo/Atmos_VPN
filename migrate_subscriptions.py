"""
Migration: Add missing columns to subscriptions table.
Run once: python migrate_subscriptions.py
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

columns = [
    ("amount_usd",  "FLOAT",       "NULL"),
    ("currency",    "VARCHAR(5)",  "'USD'"),
]

with engine.connect() as conn:
    for col_name, col_type, col_default in columns:
        try:
            if col_default == "NULL":
                sql = text(
                    f"ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS {col_name} {col_type};"
                )
            else:
                sql = text(
                    f"ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS "
                    f"{col_name} {col_type} DEFAULT {col_default};"
                )
            conn.execute(sql)
            print(f"OK: Added column subscriptions.{col_name}")
        except Exception as e:
            print(f"WARN: {col_name}: {e}")
    conn.commit()

print("\nDone! Subscriptions table migration complete.")
