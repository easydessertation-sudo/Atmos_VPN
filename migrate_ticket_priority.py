"""
migrate_ticket_priority.py
--------------------------
Adds the `priority` column to support_tickets if it doesn't already exist.
Run once:
    cd vpn-backend
    python migrate_ticket_priority.py
"""
from models import engine
from sqlalchemy import text

with engine.connect() as conn:
    try:
        conn.execute(text(
            "ALTER TABLE support_tickets ADD COLUMN priority VARCHAR(20) DEFAULT 'medium'"
        ))
        conn.commit()
        print("[OK] priority column added to support_tickets")
    except Exception as e:
        # Column probably already exists (PostgreSQL raises DuplicateColumn error)
        err = str(e).lower()
        if "already exists" in err or "duplicate" in err:
            print("[INFO] priority column already exists — nothing to do")
        else:
            print(f"[ERROR] {e}")
