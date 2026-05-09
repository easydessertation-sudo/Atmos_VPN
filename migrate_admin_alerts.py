"""Create the admin_alerts table in the database."""
from sqlalchemy import create_engine, text
import os
from dotenv import load_dotenv
load_dotenv()

engine = create_engine(os.environ["DATABASE_URL"])
with engine.connect() as conn:
    conn.execute(text("""
        CREATE TABLE IF NOT EXISTS admin_alerts (
            id         VARCHAR(36)  PRIMARY KEY,
            event_type VARCHAR(100) NOT NULL,
            title      VARCHAR(255) NOT NULL,
            message    TEXT,
            meta       TEXT,
            is_read    BOOLEAN      DEFAULT false,
            created_at TIMESTAMP    DEFAULT NOW()
        )
    """))
    conn.commit()
    print("admin_alerts table created (or already exists)")
