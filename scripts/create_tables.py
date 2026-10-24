"""Drop and recreate staging + star-schema tables on Redshift.

Usage:
    python3 scripts/create_tables.py

Runs sql/00_drop_tables.sql, sql/01_create_staging.sql and sql/02_create_star_schema.sql.
Needs config/dwh.cfg (copy config/dwh.cfg.example). Safe to run again: it rebuilds everything.
"""
from dwh_utils import connect, load_config, run_file

FILES = ["00_drop_tables.sql", "01_create_staging.sql", "02_create_star_schema.sql"]

if __name__ == "__main__":
    conn = connect(load_config())
    for name in FILES:
        run_file(conn, name)
        print(f"ok  {name}")
    conn.close()
    print("Tables created.")
