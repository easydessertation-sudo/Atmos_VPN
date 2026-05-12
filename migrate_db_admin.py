import os
import urllib.parse
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from dotenv import load_dotenv

# Load old DB url
load_dotenv()
old_db_url = os.environ.get("DATABASE_URL")
if not old_db_url:
    raise Exception("DATABASE_URL not found in .env")

# The old URL points to the NEW DB now! So I need to hardcode the actual old URL
# The old URL was: postgresql://postgres.uxhkcnzoikqdrnkxxmnw:Securevpn%40%24123@aws-1-ap-southeast-1.pooler.supabase.com:6543/postgres
old_db_url = "postgresql://postgres.uxhkcnzoikqdrnkxxmnw:Securevpn%40%24123@aws-1-ap-southeast-1.pooler.supabase.com:6543/postgres"

# New DB URL
new_password = urllib.parse.quote_plus("Atmosvpn@#123")
new_db_url = f"postgresql://postgres.vugzuytgtreieokhigog:{new_password}@aws-1-us-west-2.pooler.supabase.com:5432/postgres"

print("Connecting to OLD DB...")
old_engine = create_engine(old_db_url)

print("Connecting to NEW DB...")
new_engine = create_engine(new_db_url)

# Import models from admin panel
import models

print("Creating tables in NEW DB...")
models.Base.metadata.create_all(bind=new_engine)

print("\nCopying data for admin tables...")
OldSession = sessionmaker(bind=old_engine)
NewSession = sessionmaker(bind=new_engine)

old_session = OldSession()
new_session = NewSession()

already_copied = {
    'plans', 'users', 'vpn_servers', 'devices', 'notifications', 
    'subscriptions', 'support_tickets', 'usage_logs', 'vpn_configs', 
    'ip_pool', 'vpn_sessions'
}

try:
    for table in models.Base.metadata.sorted_tables:
        if table.name in already_copied:
            print(f"Skipping {table.name} (already copied)...")
            continue
            
        print(f"Copying {table.name}...")
        
        # Read all rows from old
        result = old_session.execute(table.select()).mappings().all()
        
        if result:
            rows = [dict(r) for r in result]
            with new_engine.begin() as conn:
                conn.execute(table.insert(), rows)
            print(f"  -> Copied {len(rows)} rows.")
        else:
            print("  -> 0 rows.")

    print("\n✅ Admin Migration complete!")
except Exception as e:
    print(f"❌ Error: {e}")
finally:
    old_session.close()
    new_session.close()
