"""Migration: Add email_verification_code column to users table"""
from models import engine
from sqlalchemy import text

migrations = [
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verification_code VARCHAR(10)",
]

with engine.connect() as conn:
    for sql in migrations:
        try:
            print("Running:", sql[:70])
            conn.execute(text(sql))
            conn.commit()
        except Exception as e:
            print("Already exists or error:", e)
    print("Done. email_verification_code column added/verified on users table.")
