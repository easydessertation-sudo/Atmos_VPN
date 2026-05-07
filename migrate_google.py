"""Migration: Add Google OAuth columns to users table"""
from models import Base, engine
from sqlalchemy import text

migrations = [
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS google_id VARCHAR(100) UNIQUE",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url VARCHAR(500)",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS auth_provider VARCHAR(20) DEFAULT 'email'",
]

with engine.connect() as conn:
    for sql in migrations:
        print("Running:", sql[:70])
        conn.execute(text(sql))
    conn.commit()
    print("Done. Google OAuth columns added to users table.")
