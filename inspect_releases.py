from sqlalchemy import create_engine, text
import os
from dotenv import load_dotenv

load_dotenv()

engine = create_engine(os.environ["DATABASE_URL"])
with engine.connect() as conn:
    result = conn.execute(text("SELECT * FROM app_releases"))
    columns = result.keys()
    rows = result.fetchall()
    
    print(f"Total rows in app_releases: {len(rows)}")
    for row in rows:
        row_dict = dict(zip(columns, row))
        print(row_dict)
