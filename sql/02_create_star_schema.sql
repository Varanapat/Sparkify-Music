-- Star schema: 2 fact tables + 4 dimensions (docs/data_model.md §3, §4)
-- Redshift does not enforce PK/FK; they are declared for the optimizer and checked in 05_data_quality.sql.

CREATE TABLE dim_users (
    user_key   INTEGER IDENTITY(1,1) PRIMARY KEY,   -- surrogate key, one per SCD2 version
    user_id    VARCHAR(10) NOT NULL,                -- natural key
    first_name VARCHAR(64),
    last_name  VARCHAR(64),
    gender     VARCHAR(4),
    level      VARCHAR(10) NOT NULL,
    valid_from TIMESTAMP NOT NULL,
    valid_to   TIMESTAMP NOT NULL,                  -- 9999-12-31 for the current version
    is_current BOOLEAN NOT NULL
)
DISTSTYLE ALL
SORTKEY (user_id);

CREATE TABLE dim_artists (
    artist_id VARCHAR(18) PRIMARY KEY,
    name      VARCHAR(256) NOT NULL,
    location  VARCHAR(256),
    latitude  FLOAT,
    longitude FLOAT
)
DISTSTYLE ALL
SORTKEY (artist_id);

CREATE TABLE dim_songs (
    song_id   VARCHAR(18) PRIMARY KEY,
    title     VARCHAR(256) NOT NULL,
    artist_id VARCHAR(18) REFERENCES dim_artists (artist_id),
    year      INTEGER,                              -- NULL when unknown (0 in source)
    duration  FLOAT
)
DISTSTYLE ALL
SORTKEY (song_id);

CREATE TABLE dim_time (
    start_time   TIMESTAMP PRIMARY KEY,
    hour         SMALLINT,
    day          SMALLINT,
    week         SMALLINT,
    month        SMALLINT,
    year         SMALLINT,
    weekday      SMALLINT,                          -- 0 = Sunday ... 6 = Saturday
    weekday_name VARCHAR(10),
    is_weekend   BOOLEAN
)
DISTSTYLE ALL
SORTKEY (start_time);

-- song_id / artist_id are NULL for ~95% of plays (no match in the catalog), so no DISTKEY(song_id): it would skew.
CREATE TABLE fact_songplays (
    songplay_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    start_time  TIMESTAMP NOT NULL REFERENCES dim_time (start_time),
    user_key    INTEGER NOT NULL REFERENCES dim_users (user_key),
    user_id     VARCHAR(10) NOT NULL,
    level       VARCHAR(10) NOT NULL,
    song_id     VARCHAR(18) REFERENCES dim_songs (song_id),
    artist_id   VARCHAR(18) REFERENCES dim_artists (artist_id),
    session_id  INTEGER NOT NULL,
    song_title  VARCHAR(256) NOT NULL,
    artist_name VARCHAR(256) NOT NULL,
    song_length FLOAT NOT NULL,
    location    VARCHAR(256) NOT NULL,
    user_agent  VARCHAR(512) NOT NULL
)
DISTSTYLE AUTO
SORTKEY (start_time);

CREATE TABLE fact_page_events (
    event_id        BIGINT IDENTITY(1,1) PRIMARY KEY,
    start_time      TIMESTAMP NOT NULL REFERENCES dim_time (start_time),
    user_key        INTEGER NOT NULL REFERENCES dim_users (user_key),
    user_id         VARCHAR(10) NOT NULL,
    level           VARCHAR(10) NOT NULL,
    session_id      INTEGER NOT NULL,
    item_in_session INTEGER NOT NULL,
    page            VARCHAR(32) NOT NULL,
    http_method     VARCHAR(8) NOT NULL,
    http_status     INTEGER NOT NULL,
    location        VARCHAR(256) NOT NULL,
    user_agent      VARCHAR(512) NOT NULL
)
DISTSTYLE AUTO
SORTKEY (start_time);
