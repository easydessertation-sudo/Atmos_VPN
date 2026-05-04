"""
Migration: Add app settings columns to users table.
Run once: python migrate_app_settings.py
"""
import os
import sys
sys.stdout.reconfigure(encoding='utf-8')

from dotenv import load_dotenv
from sqlalchemy import create_engine, text

load_dotenv()

DATABASE_URL = os.environ.get("DATABASE_URL", "")
if not DATABASE_URL:
    print("ERROR: DATABASE_URL not in .env")
    exit(1)

engine = create_engine(DATABASE_URL)

columns = [
    ("dark_theme",         "BOOLEAN",     "TRUE"),
    ("language",           "VARCHAR(20)", "'english'"),
    ("auto_connect",       "BOOLEAN",     "FALSE"),
    ("preferred_protocol", "VARCHAR(20)", "'wireguard'"),
]

with engine.connect() as conn:
    for col_name, col_type, col_default in columns:
        try:
            conn.execute(text(
                f"ALTER TABLE users ADD COLUMN IF NOT EXISTS "
                f"{col_name} {col_type} NOT NULL DEFAULT {col_default};"
            ))
            print(f"OK: Added users.{col_name}")
        except Exception as e:
            print(f"WARN: {col_name}: {e}")
    conn.commit()

print("\nDone! App settings columns added.")
