-- COPY raw JSON from our S3 bucket into the staging tables.
-- {PLACEHOLDERS} are filled from config/dwh.cfg by scripts/etl.py.

-- App events: JSONPath file maps the JSON keys to table columns by position.
COPY staging_events
FROM '{LOG_DATA}'
IAM_ROLE '{IAM_ROLE}'
FORMAT AS JSON '{LOG_JSONPATH}'
REGION '{REGION}';

-- Song metadata: 'auto' maps JSON keys to columns of the same name.
COPY staging_songs
FROM '{SONG_DATA}'
IAM_ROLE '{IAM_ROLE}'
FORMAT AS JSON 'auto'
REGION '{REGION}';
