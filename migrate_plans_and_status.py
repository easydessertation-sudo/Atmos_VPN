import os
from sqlalchemy import text
from dotenv import load_dotenv

# Load env vars
load_dotenv()

from models import engine, SessionLocal, VPNServer

def run_migration():
    print("Starting database migration...")
    
    # 1. Add required_plan column using raw SQL (SQLite or PostgreSQL compatible)
    with engine.begin() as conn:
        try:
            # Try to add the column. If it exists, this will throw an error and we catch it.
            conn.execute(text("ALTER TABLE vpn_servers ADD COLUMN required_plan VARCHAR(50) DEFAULT 'free';"))
            print("Added 'required_plan' column to vpn_servers.")
        except Exception as e:
            if "duplicate column name" in str(e).lower() or "already exists" in str(e).lower():
                print("'required_plan' column already exists.")
            else:
                print(f"Could not add column (it might already exist): {e}")

    # 2. Update specific servers to be "starter"
    db = SessionLocal()
    try:
        # The user requested: Germany, Israel, south africa -> starter
        paid_countries = ["Germany", "Israel", "South Africa"]
        
        # Make all free by default first (just in case)
        db.query(VPNServer).update({"required_plan": "free"})
        
        # Update the specific paid countries
        updated = db.query(VPNServer).filter(
            VPNServer.country.in_(paid_countries)
        ).update({"required_plan": "starter"}, synchronize_session=False)
        
        db.commit()
        print(f"Updated {updated} servers to require the 'starter' plan (Germany, Israel, South Africa).")
        
    except Exception as e:
        print(f"Error updating servers: {e}")
        db.rollback()
    finally:
        db.close()

if __name__ == "__main__":
    run_migration()
