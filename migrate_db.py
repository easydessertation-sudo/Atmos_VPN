import os
import urllib.parse
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from dotenv import load_dotenv

# Load old DB url
load_dotenv()
old_db_url = os.environ.get("DATABASE_URL")
if not old_db_url:
    raise Exception("DATABASE_URL not found in .env")

# New DB URL (URL encode the password Atmosvpn@#123)
new_password = urllib.parse.quote_plus("Atmosvpn@#123")
new_db_url = f"postgresql://postgres.vugzuytgtreieokhigog:{new_password}@aws-1-us-west-2.pooler.supabase.com:5432/postgres"

print("Connecting to OLD DB...")
old_engine = create_engine(old_db_url)

print("Connecting to NEW DB...")
new_engine = create_engine(new_db_url)

# Import models so we can get all tables
import models

print("Creating tables in NEW DB...")
models.Base.metadata.create_all(bind=new_engine)

print("\nCopying data...")
OldSession = sessionmaker(bind=old_engine)
NewSession = sessionmaker(bind=new_engine)

old_session = OldSession()
new_session = NewSession()

try:
    for table in models.Base.metadata.sorted_tables:
        print(f"Copying {table.name}...")
        
        # Read all rows from old
        result = old_session.execute(table.select()).mappings().all()
        
        if result:
            # We insert directly via engine so we don't need to load ORM objects
            # Convert mappings to dicts
            rows = [dict(r) for r in result]
            
            # Use engine connection to insert
            with new_engine.begin() as conn:
                conn.execute(table.insert(), rows)
            print(f"  -> Copied {len(rows)} rows.")
        else:
            print("  -> 0 rows.")

    print("\n✅ Migration complete!")
except Exception as e:
    print(f"❌ Error: {e}")
finally:
    old_session.close()
    new_session.close()
