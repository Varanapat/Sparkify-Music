-- Transform staging -> star schema (docs/data_model.md §5). Tables are empty here (00-02 just rebuilt them).
-- ts is epoch milliseconds (UTC): TIMESTAMP 'epoch' + ts/1000 * INTERVAL '1 second'
-- Logged-out events (user_id = '') are excluded from users and both facts.

-- 1. dim_artists: one row per artist_id (shortest name wins, see §5.2); '' -> NULL
INSERT INTO dim_artists (artist_id, name, location, latitude, longitude)
SELECT artist_id, artist_name, NULLIF(artist_location, ''), artist_latitude, artist_longitude
FROM (
    SELECT s.*,
           ROW_NUMBER() OVER (PARTITION BY artist_id ORDER BY LEN(artist_name), artist_name) AS rn
    FROM staging_songs s
    WHERE artist_id IS NOT NULL
)
WHERE rn = 1;

-- 2. dim_songs: year 0 means unknown -> NULL
INSERT INTO dim_songs (song_id, title, artist_id, year, duration)
SELECT song_id, title, artist_id, NULLIF(year, 0), duration
FROM (
    SELECT s.*, ROW_NUMBER() OVER (PARTITION BY song_id ORDER BY title) AS rn
    FROM staging_songs s
    WHERE song_id IS NOT NULL
)
WHERE rn = 1;

-- 3. dim_users (SCD Type 2): a new version starts whenever the level differs from the user's previous event (§5.1)
INSERT INTO dim_users (user_id, first_name, last_name, gender, level, valid_from, valid_to, is_current)
WITH ev AS (
    SELECT user_id, first_name, last_name, gender, level,
           TIMESTAMP 'epoch' + ts / 1000 * INTERVAL '1 second' AS event_time,
           LAG(level) OVER (PARTITION BY user_id ORDER BY ts, session_id, item_in_session) AS prev_level
    FROM staging_events
    WHERE user_id <> ''
),
versions AS (
    SELECT user_id, first_name, last_name, gender, level, event_time AS valid_from,
           LEAD(event_time) OVER (PARTITION BY user_id ORDER BY event_time) AS next_from
    FROM ev
    WHERE prev_level IS NULL OR prev_level <> level
)
SELECT user_id, first_name, last_name, gender, level, valid_from,
       COALESCE(next_from, TIMESTAMP '9999-12-31 00:00:00'),
       next_from IS NULL
FROM versions;

-- 4. dim_time: every distinct timestamp of a logged-in event
INSERT INTO dim_time (start_time, hour, day, week, month, year, weekday, weekday_name, is_weekend)
SELECT start_time,
       EXTRACT(hour FROM start_time), EXTRACT(day FROM start_time), EXTRACT(week FROM start_time),
       EXTRACT(month FROM start_time), EXTRACT(year FROM start_time), EXTRACT(dow FROM start_time),
       CASE EXTRACT(dow FROM start_time)
            WHEN 0 THEN 'Sunday' WHEN 1 THEN 'Monday' WHEN 2 THEN 'Tuesday' WHEN 3 THEN 'Wednesday'
            WHEN 4 THEN 'Thursday' WHEN 5 THEN 'Friday' ELSE 'Saturday' END,
       EXTRACT(dow FROM start_time) IN (0, 6)
FROM (
    SELECT DISTINCT TIMESTAMP 'epoch' + ts / 1000 * INTERVAL '1 second' AS start_time
    FROM staging_events
    WHERE user_id <> ''
);

-- 5. fact_page_events: every logged-in event; user_key = the dim_users version valid at that time
INSERT INTO fact_page_events (start_time, user_key, user_id, level, session_id, item_in_session,
                              page, http_method, http_status, location, user_agent)
SELECT e.start_time, u.user_key, e.user_id, e.level, e.session_id, e.item_in_session,
       e.page, e.method, e.status, e.location, e.user_agent
FROM (
    SELECT *, TIMESTAMP 'epoch' + ts / 1000 * INTERVAL '1 second' AS start_time
    FROM staging_events
    WHERE user_id <> ''
) e
JOIN dim_users u
  ON u.user_id = e.user_id AND e.start_time >= u.valid_from AND e.start_time < u.valid_to;

-- 6. fact_songplays: NextSong events; song/artist ids are NULL when not in the catalog (§5.3)
INSERT INTO fact_songplays (start_time, user_key, user_id, level, song_id, artist_id, session_id,
                            song_title, artist_name, song_length, location, user_agent)
WITH catalog AS (   -- one row per (title, artist, duration) so the join cannot duplicate plays
    SELECT title, artist_name, duration, song_id, artist_id
    FROM (
        SELECT s.*, ROW_NUMBER() OVER (PARTITION BY title, artist_name, duration ORDER BY song_id) AS rn
        FROM staging_songs s
    )
    WHERE rn = 1
)
SELECT e.start_time, u.user_key, e.user_id, e.level, c.song_id, c.artist_id, e.session_id,
       e.song, e.artist, e.length, e.location, e.user_agent
FROM (
    SELECT *, TIMESTAMP 'epoch' + ts / 1000 * INTERVAL '1 second' AS start_time
    FROM staging_events
    WHERE user_id <> '' AND page = 'NextSong'
) e
JOIN dim_users u
  ON u.user_id = e.user_id AND e.start_time >= u.valid_from AND e.start_time < u.valid_to
LEFT JOIN catalog c
  ON c.title = e.song AND c.artist_name = e.artist AND c.duration = e.length;
