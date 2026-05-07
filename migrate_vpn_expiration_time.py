"""Migration: Add vpn_expiration_time column to users table"""
from models import engine
from sqlalchemy import text

migrations = [
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS vpn_expiration_time TIMESTAMP",
]

with engine.connect() as conn:
    for sql in migrations:
        print("Running:", sql[:70])
        conn.execute(text(sql))
    conn.commit()
    print("Done. vpn_expiration_time column added to users table.")
