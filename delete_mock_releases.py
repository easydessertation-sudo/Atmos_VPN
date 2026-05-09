from sqlalchemy import create_engine, text
import os
from dotenv import load_dotenv

load_dotenv()

engine = create_engine(os.environ["DATABASE_URL"])
with engine.connect() as conn:
    result = conn.execute(text("DELETE FROM app_releases"))
    conn.commit()
    print(f"Deleted {result.rowcount} rows from app_releases.")
