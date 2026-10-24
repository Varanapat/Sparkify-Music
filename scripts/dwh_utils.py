"""Shared helpers for create_tables.py and etl.py: read config/dwh.cfg, connect to Redshift, run .sql files."""
import configparser
import os
import re

import psycopg2

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SQL_DIR = os.path.join(ROOT, "sql")
CONFIG_PATH = os.environ.get("DWH_CONFIG", os.path.join(ROOT, "config", "dwh.cfg"))


def load_config():
    config = configparser.ConfigParser()
    if not config.read(CONFIG_PATH):
        raise SystemExit(f"Config not found: {CONFIG_PATH}\nCopy config/dwh.cfg.example to config/dwh.cfg and fill it in.")
    return config


def connect(config):
    c = config["CLUSTER"]
    return psycopg2.connect(host=c["HOST"], dbname=c["DB_NAME"], user=c["DB_USER"],
                            password=c["DB_PASSWORD"], port=c["DB_PORT"], connect_timeout=15)


def placeholders(config):
    """Values for the {PLACEHOLDERS} used in sql/03_copy_from_s3.sql."""
    return {
        "LOG_DATA": config["S3"]["LOG_DATA"],
        "LOG_JSONPATH": config["S3"]["LOG_JSONPATH"],
        "SONG_DATA": config["S3"]["SONG_DATA"],
        "IAM_ROLE": config["IAM_ROLE"]["ARN"],
        "REGION": config["AWS"]["REGION"],
    }


def read_statements(filename, values=None):
    """Return the SQL statements of sql/<filename>. Comments are removed first, because some contain ';'."""
    with open(os.path.join(SQL_DIR, filename)) as f:
        text = re.sub(r"--.*", "", f.read())
    for key, value in (values or {}).items():
        text = text.replace("{" + key + "}", value)
    return [s.strip() for s in text.split(";") if s.strip()]


def run_file(conn, filename, values=None):
    """Run every statement of a SQL file in one transaction (all or nothing). Returns the rows of the last SELECT."""
    rows = []
    with conn.cursor() as cur:
        try:
            for statement in read_statements(filename, values):
                cur.execute(statement)
                if cur.description:
                    rows = cur.fetchall()
            conn.commit()
        except Exception:
            conn.rollback()
            raise
    return rows
