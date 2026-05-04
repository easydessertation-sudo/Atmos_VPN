"""
Migration: Create notifications table.
Run once: python migrate_notifications.py
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

CREATE_SQL = """
CREATE TABLE IF NOT EXISTS notifications (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type        VARCHAR(30)  NOT NULL,
    title       VARCHAR(255) NOT NULL,
    message     TEXT         NOT NULL,
    is_read     BOOLEAN      NOT NULL DEFAULT FALSE,
    coming_soon BOOLEAN      NOT NULL DEFAULT FALSE,
    meta        TEXT,
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_notifications_user_id   ON notifications(user_id);
CREATE INDEX IF NOT EXISTS ix_notifications_created_at ON notifications(created_at);
"""

with engine.connect() as conn:
    conn.execute(text(CREATE_SQL))
    conn.commit()
    print("OK: notifications table created (or already exists)")

print("\nDone! Notifications migration complete.")
