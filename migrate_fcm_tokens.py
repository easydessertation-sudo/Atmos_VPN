"""
Migration: Create fcm_tokens table.
Run once: python migrate_fcm_tokens.py
"""
import os
import sys
sys.stdout.reconfigure(encoding='utf-8')

from dotenv import load_dotenv
from sqlalchemy import create_engine
import models

load_dotenv()

DATABASE_URL = os.environ.get("DATABASE_URL", "")
if not DATABASE_URL:
    print("ERROR: DATABASE_URL not in .env")
    exit(1)

# Clean DB url print for logs (hiding credentials)
print(f"Connecting to database: {DATABASE_URL.split('@')[-1] if '@' in DATABASE_URL else DATABASE_URL}")
engine = create_engine(DATABASE_URL)

try:
    print("Creating fcm_tokens table...")
    # This will check models, find FCMToken (which we added),
    # and create the table if it does not exist.
    models.Base.metadata.create_all(bind=engine)
    print("✅ Success: fcm_tokens table created (or already exists)")
except Exception as e:
    print(f"❌ Error creating tables: {e}")
    sys.exit(1)
