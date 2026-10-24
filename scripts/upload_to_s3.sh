#!/usr/bin/env bash
# Upload data/raw/ (log_data, song_data, log_json_path.json) to our own S3 bucket.
#
# Usage:  scripts/upload_to_s3.sh <bucket-name>        e.g.  scripts/upload_to_s3.sh sparkify-raw-group1
#
# Run it where `aws` has Learner Lab credentials. In CloudShell there are no local files, so first run
#   git clone <repo> && cd <repo> && python3 scripts/download_dataset.py
# Safe to run again: `aws s3 sync` only uploads what is missing.
set -euo pipefail

BUCKET="${1:?Usage: $0 <bucket-name>}"
SRC="$(cd "$(dirname "$0")/.." && pwd)/data/raw"

[ -d "$SRC/log_data" ] && [ -d "$SRC/song_data" ] && [ -f "$SRC/log_json_path.json" ] \
  || { echo "data/raw is incomplete. Run: python3 scripts/download_dataset.py" >&2; exit 1; }

aws s3api head-bucket --bucket "$BUCKET"

aws s3 sync "$SRC" "s3://$BUCKET/" --only-show-errors

local_count=$(find "$SRC" -type f | wc -l | tr -d ' ')
remote_count=$(aws s3 ls "s3://$BUCKET/" --recursive | wc -l | tr -d ' ')
echo "local files: $local_count, objects in s3://$BUCKET: $remote_count"
[ "$local_count" -eq "$remote_count" ] || { echo "Counts differ. Check the bucket." >&2; exit 1; }
echo "Upload complete."
