"""Run COPY from S3, transform into the star schema, then run data quality checks.

Usage (after create_tables.py):
    python3 scripts/etl.py

Exit code 1 if a data-quality check fails, so a broken load cannot go unnoticed.
If COPY fails, the latest rows of sys_load_error_detail are printed.
"""
import sys
import time

from dwh_utils import connect, load_config, placeholders, run_file


def print_load_errors(conn):
    with conn.cursor() as cur:
        cur.execute("SELECT start_time, table_name, column_name, error_message "
                    "FROM sys_load_error_detail ORDER BY start_time DESC LIMIT 10")
        for row in cur.fetchall():
            print("  load error:", row)


def timed(conn, filename, values=None):
    start = time.time()
    rows = run_file(conn, filename, values)
    print(f"ok  {filename} ({time.time() - start:.1f}s)")
    return rows


if __name__ == "__main__":
    config = load_config()
    conn = connect(config)

    try:
        timed(conn, "03_copy_from_s3.sql", placeholders(config))
    except Exception as exc:
        print(f"COPY failed: {exc}")
        conn.rollback()
        print_load_errors(conn)
        sys.exit(1)

    timed(conn, "04_transform_load.sql")
    results = timed(conn, "05_data_quality.sql")
    conn.close()

    width = max(len(r[0]) for r in results)
    for check, actual, expected, status in results:
        print(f"  {status:<4}  {check:<{width}}  actual={actual:g}" + ("" if expected is None else f"  expected={expected:g}"))

    failed = [r[0] for r in results if r[3] == "FAIL"]
    if failed:
        print(f"\nData quality FAILED: {len(failed)} check(s)")
        sys.exit(1)
    print("\nETL finished, all data quality checks passed.")
