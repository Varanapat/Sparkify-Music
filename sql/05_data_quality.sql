-- Data-quality checks. One result set: check_name, actual, expected, status (PASS / FAIL / INFO).
-- scripts/etl.py runs this file and fails the pipeline if any row has status = 'FAIL'.
-- Redshift does not enforce PK/FK, so uniqueness and orphan checks are done here.
-- Expected values are computed from the staging tables, so the checks stay valid for any dataset size.

-- 1. Staging was loaded
SELECT 'staging_events not empty' AS check_name, COUNT(*)::FLOAT AS actual, NULL::FLOAT AS expected,
       CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM staging_events
UNION ALL
SELECT 'staging_songs not empty', COUNT(*), NULL, CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END
FROM staging_songs

-- 2. Row counts: staging vs star schema
UNION ALL
SELECT 'fact_songplays = logged-in NextSong events', (SELECT COUNT(*) FROM fact_songplays),
       (SELECT COUNT(*) FROM staging_events WHERE user_id <> '' AND page = 'NextSong'),
       CASE WHEN (SELECT COUNT(*) FROM fact_songplays)
               = (SELECT COUNT(*) FROM staging_events WHERE user_id <> '' AND page = 'NextSong')
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'fact_page_events = logged-in events', (SELECT COUNT(*) FROM fact_page_events),
       (SELECT COUNT(*) FROM staging_events WHERE user_id <> ''),
       CASE WHEN (SELECT COUNT(*) FROM fact_page_events)
               = (SELECT COUNT(*) FROM staging_events WHERE user_id <> '')
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'fact_page_events NextSong rows = fact_songplays', (SELECT COUNT(*) FROM fact_page_events WHERE page = 'NextSong'),
       (SELECT COUNT(*) FROM fact_songplays),
       CASE WHEN (SELECT COUNT(*) FROM fact_page_events WHERE page = 'NextSong')
               = (SELECT COUNT(*) FROM fact_songplays)
            THEN 'PASS' ELSE 'FAIL' END

-- 3. dim_users (SCD Type 2)
UNION ALL
SELECT 'dim_users distinct users = logged-in users in staging', (SELECT COUNT(DISTINCT user_id) FROM dim_users),
       (SELECT COUNT(DISTINCT user_id) FROM staging_events WHERE user_id <> ''),
       CASE WHEN (SELECT COUNT(DISTINCT user_id) FROM dim_users)
               = (SELECT COUNT(DISTINCT user_id) FROM staging_events WHERE user_id <> '')
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'dim_users current versions = distinct users', (SELECT COUNT(*) FROM dim_users WHERE is_current),
       (SELECT COUNT(DISTINCT user_id) FROM dim_users),
       CASE WHEN (SELECT COUNT(*) FROM dim_users WHERE is_current)
               = (SELECT COUNT(DISTINCT user_id) FROM dim_users)
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'dim_users versions with valid_from >= valid_to', COUNT(*), 0, CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM dim_users WHERE valid_from >= valid_to

-- 4. NULLs in facts
UNION ALL
SELECT 'fact_songplays NULL user_id / user_key / start_time', COUNT(*), 0, CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM fact_songplays WHERE user_id IS NULL OR user_key IS NULL OR start_time IS NULL
UNION ALL
SELECT 'fact_page_events NULL user_id / user_key / start_time', COUNT(*), 0, CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM fact_page_events WHERE user_id IS NULL OR user_key IS NULL OR start_time IS NULL

-- 5. Duplicate primary keys in dimensions (not enforced by Redshift)
UNION ALL
SELECT 'dim_artists duplicate artist_id', COUNT(*) - COUNT(DISTINCT artist_id), 0,
       CASE WHEN COUNT(*) = COUNT(DISTINCT artist_id) THEN 'PASS' ELSE 'FAIL' END FROM dim_artists
UNION ALL
SELECT 'dim_songs duplicate song_id', COUNT(*) - COUNT(DISTINCT song_id), 0,
       CASE WHEN COUNT(*) = COUNT(DISTINCT song_id) THEN 'PASS' ELSE 'FAIL' END FROM dim_songs
UNION ALL
SELECT 'dim_time duplicate start_time', COUNT(*) - COUNT(DISTINCT start_time), 0,
       CASE WHEN COUNT(*) = COUNT(DISTINCT start_time) THEN 'PASS' ELSE 'FAIL' END FROM dim_time
UNION ALL
SELECT 'dim_users duplicate user_key', COUNT(*) - COUNT(DISTINCT user_key), 0,
       CASE WHEN COUNT(*) = COUNT(DISTINCT user_key) THEN 'PASS' ELSE 'FAIL' END FROM dim_users

-- 6. Orphan foreign keys (fact or dimension points at a missing row)
UNION ALL
SELECT 'fact rows with start_time missing in dim_time', COUNT(*), 0, CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT start_time FROM fact_songplays UNION ALL SELECT start_time FROM fact_page_events) f
WHERE f.start_time NOT IN (SELECT start_time FROM dim_time)
UNION ALL
SELECT 'fact rows with user_key missing in dim_users', COUNT(*), 0, CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT user_key FROM fact_songplays UNION ALL SELECT user_key FROM fact_page_events) f
WHERE f.user_key NOT IN (SELECT user_key FROM dim_users)
UNION ALL
SELECT 'fact_songplays song_id/artist_id missing in dimensions', COUNT(*), 0, CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM fact_songplays
WHERE (song_id IS NOT NULL AND song_id NOT IN (SELECT song_id FROM dim_songs))
   OR (artist_id IS NOT NULL AND artist_id NOT IN (SELECT artist_id FROM dim_artists))
UNION ALL
SELECT 'dim_songs artist_id missing in dim_artists', COUNT(*), 0, CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM dim_songs WHERE artist_id NOT IN (SELECT artist_id FROM dim_artists)

-- 7. Metrics to report (not pass/fail)
UNION ALL
SELECT 'INFO song match rate (%)', ROUND(100.0 * COUNT(song_id) / NULLIF(COUNT(*), 0), 1), NULL, 'INFO' FROM fact_songplays
UNION ALL
SELECT 'INFO logged-out events excluded', COUNT(*), NULL, 'INFO' FROM staging_events WHERE user_id = ''
UNION ALL
SELECT 'INFO dim_users versions', COUNT(*), NULL, 'INFO' FROM dim_users;
