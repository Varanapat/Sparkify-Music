-- Staging tables: raw JSON exactly as loaded by COPY (docs/data_model.md §1, §4)

-- Column ORDER must match log_json_path.json, because COPY with a JSONPath file maps by position.
CREATE TABLE staging_events (
    artist          VARCHAR(512),
    auth            VARCHAR(32),
    first_name      VARCHAR(64),
    gender          VARCHAR(4),
    item_in_session INTEGER,
    last_name       VARCHAR(64),
    length          FLOAT,
    level           VARCHAR(10),
    location        VARCHAR(256),
    method          VARCHAR(8),
    page            VARCHAR(32),
    registration    FLOAT,
    session_id      INTEGER,
    song            VARCHAR(512),
    status          INTEGER,
    ts              BIGINT,           -- epoch milliseconds (UTC)
    user_agent      VARCHAR(512),
    user_id         VARCHAR(10)       -- '' for logged-out events
)
DISTSTYLE EVEN;

-- COPY ... FORMAT AS JSON 'auto' maps by name, so these names must equal the JSON keys.
CREATE TABLE staging_songs (
    num_songs        INTEGER,
    artist_id        VARCHAR(18),
    artist_latitude  FLOAT,
    artist_longitude FLOAT,
    artist_location  VARCHAR(512),
    artist_name      VARCHAR(512),
    song_id          VARCHAR(18),
    title            VARCHAR(512),
    duration         FLOAT,
    year             INTEGER
)
DISTSTYLE EVEN;
