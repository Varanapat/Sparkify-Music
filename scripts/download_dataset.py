"""Download the Sparkify raw dataset from the public Udacity bucket to data/raw/.

Usage:
    python3 scripts/download_dataset.py

Uses only the Python standard library (no AWS credentials needed, the source bucket is public).
"""
import os
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor

BUCKET_URL = "https://udacity-dend.s3.us-west-2.amazonaws.com"
PREFIXES = ["log_data/", "song_data/", "log_json_path.json"]
NS = "{http://s3.amazonaws.com/doc/2006-03-01/}"
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "data", "raw")


def list_keys(prefix):
    keys, token = [], None
    while True:
        query = {"list-type": "2", "prefix": prefix, "max-keys": "1000"}
        if token:
            query["continuation-token"] = token
        root = ET.fromstring(urllib.request.urlopen(f"{BUCKET_URL}/?{urllib.parse.urlencode(query)}").read())
        for c in root.iter(NS + "Contents"):
            if int(c.find(NS + "Size").text) > 0:
                keys.append(c.find(NS + "Key").text)
        nxt = root.find(NS + "NextContinuationToken")
        if nxt is None:
            return keys
        token = nxt.text


def download(key):
    dest = os.path.join(OUT_DIR, key)
    if os.path.exists(dest):
        return
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    for attempt in range(5):  # S3 occasionally drops connections, so retry
        try:
            urllib.request.urlretrieve(f"{BUCKET_URL}/{urllib.parse.quote(key)}", dest)
            return
        except Exception:
            if attempt == 4:
                raise
            time.sleep(1 + attempt)


if __name__ == "__main__":
    for prefix in PREFIXES:
        keys = list_keys(prefix)
        print(f"{prefix}: {len(keys)} files")
        with ThreadPoolExecutor(max_workers=16) as pool:
            list(pool.map(download, keys))
    print("Done ->", os.path.abspath(OUT_DIR))
