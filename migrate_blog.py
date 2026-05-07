"""
Migration: Add new columns to blog_posts, create seo_settings and media_files tables.
Run once:  python migrate_blog.py
"""
import os
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

load_dotenv()

DATABASE_URL = os.environ.get("DATABASE_URL")
engine = create_engine(DATABASE_URL)

MIGRATIONS = [
    # ── blog_posts: add new columns (safe — uses IF NOT EXISTS) ──
    "ALTER TABLE blog_posts ADD COLUMN IF NOT EXISTS slug             VARCHAR(255) UNIQUE;",
    "ALTER TABLE blog_posts ADD COLUMN IF NOT EXISTS excerpt          TEXT;",
    "ALTER TABLE blog_posts ADD COLUMN IF NOT EXISTS tags             VARCHAR(500);",
    "ALTER TABLE blog_posts ADD COLUMN IF NOT EXISTS featured_image   VARCHAR(1000);",
    "ALTER TABLE blog_posts ADD COLUMN IF NOT EXISTS read_time_min    INTEGER DEFAULT 3;",
    "ALTER TABLE blog_posts ADD COLUMN IF NOT EXISTS meta_title       VARCHAR(255);",
    "ALTER TABLE blog_posts ADD COLUMN IF NOT EXISTS meta_description TEXT;",
    "ALTER TABLE blog_posts ADD COLUMN IF NOT EXISTS og_image         VARCHAR(1000);",
    "ALTER TABLE blog_posts ADD COLUMN IF NOT EXISTS canonical_url    VARCHAR(1000);",
    "ALTER TABLE blog_posts ADD COLUMN IF NOT EXISTS robots           VARCHAR(100) DEFAULT 'index, follow';",
    "ALTER TABLE blog_posts ADD COLUMN IF NOT EXISTS updated_at       TIMESTAMP;",

    # ── seo_settings table ────────────────────────────────────────
    """
    CREATE TABLE IF NOT EXISTS seo_settings (
        key                   VARCHAR(50) PRIMARY KEY DEFAULT 'global',
        meta_title            VARCHAR(255) DEFAULT 'AtmosVPN – Ultra-Secure VPN | Protect Your Privacy Online',
        meta_description      TEXT DEFAULT 'Military-grade AES-256 encryption, zero-logs policy, 100+ server locations.',
        og_image_url          VARCHAR(1000) DEFAULT 'https://atmosvpn.com/og-image.png',
        canonical_url         VARCHAR(1000) DEFAULT 'https://atmosvpn.com/',
        robots                VARCHAR(100) DEFAULT 'index, follow',
        og_site_name          VARCHAR(100) DEFAULT 'AtmosVPN',
        og_type               VARCHAR(50) DEFAULT 'website',
        twitter_card          VARCHAR(50) DEFAULT 'summary_large_image',
        twitter_site          VARCHAR(100),
        google_analytics_id   VARCHAR(50),
        google_search_console VARCHAR(500),
        updated_at            TIMESTAMP DEFAULT NOW()
    );
    """,

    # Seed the default global SEO row if not exists
    """
    INSERT INTO seo_settings (key)
    VALUES ('global')
    ON CONFLICT (key) DO NOTHING;
    """,

    # ── media_files table ─────────────────────────────────────────
    """
    CREATE TABLE IF NOT EXISTS media_files (
        id          CHAR(36) PRIMARY KEY,
        name        VARCHAR(255) NOT NULL,
        url         VARCHAR(1000) NOT NULL,
        file_type   VARCHAR(50) NOT NULL,
        mime_type   VARCHAR(100),
        size_bytes  BIGINT DEFAULT 0,
        width       INTEGER,
        height      INTEGER,
        alt_text    VARCHAR(500),
        folder      VARCHAR(100) DEFAULT '/',
        uploaded_by VARCHAR(255),
        created_at  TIMESTAMP DEFAULT NOW()
    );
    """,
]

def run():
    with engine.connect() as conn:
        for sql in MIGRATIONS:
            sql = sql.strip()
            if not sql:
                continue
            print(f"Running: {sql[:80]}...")
            conn.execute(text(sql))
        conn.commit()
    print("\n✅ All migrations applied successfully.")

if __name__ == "__main__":
    run()
