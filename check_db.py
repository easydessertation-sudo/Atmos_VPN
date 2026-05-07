from sqlalchemy import create_engine, text
import os
from dotenv import load_dotenv
load_dotenv()

e = create_engine(os.environ["DATABASE_URL"])
with e.connect() as conn:
    r = conn.execute(text(
        "SELECT column_name FROM information_schema.columns "
        "WHERE table_name='blog_posts' ORDER BY ordinal_position"
    ))
    print("blog_posts columns:")
    for row in r:
        print(" ", row[0])

    r2 = conn.execute(text(
        "SELECT table_name FROM information_schema.tables "
        "WHERE table_name IN ('seo_settings','media_files')"
    ))
    print("\nNew tables:")
    for row in r2:
        print(" ", row[0], "- EXISTS")
