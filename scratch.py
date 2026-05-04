import psycopg2

DATABASE_URL = "postgresql://postgres.uxhkcnzoikqdrnkxxmnw:Securevpn%40%24123@aws-1-ap-southeast-1.pooler.supabase.com:6543/postgres"

migrations = [
    # --- vpn_servers ---
    "ALTER TABLE vpn_servers ADD COLUMN IF NOT EXISTS status VARCHAR(50) DEFAULT 'Active';",
    "ALTER TABLE vpn_servers ADD COLUMN IF NOT EXISTS uptime_pct FLOAT DEFAULT 99.9;",
    "ALTER TABLE vpn_servers ADD COLUMN IF NOT EXISTS is_streaming BOOLEAN DEFAULT FALSE;",
    "ALTER TABLE vpn_servers ADD COLUMN IF NOT EXISTS is_gaming BOOLEAN DEFAULT FALSE;",
    "ALTER TABLE vpn_servers ADD COLUMN IF NOT EXISTS is_crypto BOOLEAN DEFAULT FALSE;",
    "ALTER TABLE vpn_servers ADD COLUMN IF NOT EXISTS is_p2p BOOLEAN DEFAULT FALSE;",
    "ALTER TABLE vpn_servers ADD COLUMN IF NOT EXISTS is_dedicated_ip BOOLEAN DEFAULT FALSE;",
    "ALTER TABLE vpn_servers ADD COLUMN IF NOT EXISTS wg_public_key TEXT;",
    "ALTER TABLE vpn_servers ADD COLUMN IF NOT EXISTS wg_port INTEGER DEFAULT 51820;",
    "ALTER TABLE vpn_servers ADD COLUMN IF NOT EXISTS max_peers INTEGER DEFAULT 500;",
    "ALTER TABLE vpn_servers ADD COLUMN IF NOT EXISTS current_peers INTEGER DEFAULT 0;",
    "ALTER TABLE vpn_servers ADD COLUMN IF NOT EXISTS hetzner_server_id VARCHAR(100);",
    "ALTER TABLE vpn_servers ADD COLUMN IF NOT EXISTS protocols JSONB DEFAULT '[]';",
    "ALTER TABLE vpn_servers ADD COLUMN IF NOT EXISTS capacity_mbps INTEGER DEFAULT 1000;",
    "ALTER TABLE vpn_servers ADD COLUMN IF NOT EXISTS country_code VARCHAR(10);",
    "ALTER TABLE vpn_servers ADD COLUMN IF NOT EXISTS flag VARCHAR(10);",
    "ALTER TABLE vpn_servers ADD COLUMN IF NOT EXISTS ping_ms INTEGER DEFAULT 0;",
    "ALTER TABLE vpn_servers ADD COLUMN IF NOT EXISTS load_pct FLOAT DEFAULT 0.0;",

    # --- support_tickets ---
    "ALTER TABLE support_tickets ADD COLUMN IF NOT EXISTS priority VARCHAR(20) DEFAULT 'Medium';",
    "ALTER TABLE support_tickets ADD COLUMN IF NOT EXISTS agent_name VARCHAR(100);",
    "ALTER TABLE support_tickets ADD COLUMN IF NOT EXISTS category VARCHAR(100);",
    "ALTER TABLE support_tickets ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT NOW();",

    # --- users (extra columns admin panel may use) ---
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_plan VARCHAR(50) DEFAULT 'Free';",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS country VARCHAR(100);",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE;",

    # --- admin_users (new table for admin panel login) ---
    """CREATE TABLE IF NOT EXISTS admin_users (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name VARCHAR(100) NOT NULL,
        email VARCHAR(255) NOT NULL UNIQUE,
        password_hash VARCHAR(255) NOT NULL,
        role VARCHAR(50) NOT NULL DEFAULT 'Operations',
        two_fa_enabled BOOLEAN DEFAULT FALSE,
        last_login TIMESTAMP,
        status VARCHAR(20) DEFAULT 'Active',
        created_at TIMESTAMP DEFAULT NOW()
    );""",

    # --- audit_logs (new table) ---
    """CREATE TABLE IF NOT EXISTS audit_logs (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        admin_email VARCHAR(255),
        action TEXT,
        ip_address VARCHAR(50),
        created_at TIMESTAMP DEFAULT NOW()
    );""",
]

try:
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()
    ok = 0
    failed = 0
    for sql in migrations:
        try:
            cur.execute(sql)
            ok += 1
            label = sql.strip()[:80].replace("\n", " ")
            print("OK: " + label)
        except Exception as e:
            conn.rollback()
            failed += 1
            print("SKIP: " + str(e)[:100])
    conn.commit()
    print("\nDone. OK=" + str(ok) + " Skipped=" + str(failed))
except Exception as e:
    print("Connection error: " + str(e))
finally:
    if 'conn' in locals():
        conn.close()
