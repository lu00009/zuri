#!/usr/bin/env python3
"""
Neon PostgreSQL Verification and Initialization Script
Connects to the DATABASE_URL configured in .env, validates the connection,
creates all necessary tables, and reports status.
"""
import sys
import os

# Add parent directory to path so app modules can be loaded
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from sqlalchemy import text
from app.core.config import settings
from app.db.base import Base
from app.db.session import engine, get_normalized_db_url
import app.models  # Registers all models with Base.metadata


def main():
    raw_url = settings.DATABASE_URL
    normalized_url = get_normalized_db_url(raw_url)

    # Obfuscate password for display
    display_url = normalized_url
    if "@" in display_url and "://" in display_url:
        protocol_part, rest = display_url.split("://", 1)
        user_pass, host_db = rest.split("@", 1)
        user = user_pass.split(":")[0] if ":" in user_pass else user_pass
        display_url = f"{protocol_part}://{user}:*****@{host_db}"

    print(f"Connecting to database: {display_url}")

    try:
        with engine.connect() as conn:
            ver_query = text("SELECT version();") if "postgresql" in normalized_url else text("SELECT sqlite_version();")
            result = conn.execute(ver_query).scalar()
            print(f"Connected successfully!")
            print(f"Database engine: {result}\n")

            print("Creating all tables from SQLAlchemy models...")
            Base.metadata.create_all(bind=engine)
            print("All tables created or verified successfully!\n")

            # List existing tables
            if "postgresql" in normalized_url:
                tables = conn.execute(
                    text(
                        "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;"
                    )
                ).fetchall()
                print("Active tables in public schema:")
                for t in tables:
                    print(f"  - {t[0]}")
            else:
                tables = conn.execute(
                    text("SELECT name FROM sqlite_master WHERE type='table';")
                ).fetchall()
                print("Active tables in SQLite:")
                for t in tables:
                    print(f"  - {t[0]}")

        print("\nNeon PostgreSQL is ready to use with Zuri / PocketBrain!")
    except Exception as e:
        print(f"\nConnection / Initialization failed: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
