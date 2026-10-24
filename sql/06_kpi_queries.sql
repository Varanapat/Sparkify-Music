-- KPI queries for the 5 business questions (README §2) + dashboard cards.
-- Run each statement on its own in Redshift Query Editor v2 / Metabase. Times are UTC.

-- ======================================================================================
-- Dashboard cards
-- ======================================================================================

-- Total plays, unique users, % of users currently on paid, % of plays made on paid
SELECT (SELECT COUNT(*) FROM fact_songplays) AS total_plays,
       (SELECT COUNT(DISTINCT user_id) FROM dim_users) AS unique_users,
       ROUND(100.0 * (SELECT COUNT(*) FROM dim_users WHERE is_current AND level = 'paid')
                   / (SELECT COUNT(*) FROM dim_users WHERE is_current), 1) AS paid_users_pct,
       ROUND(100.0 * (SELECT COUNT(*) FROM fact_songplays WHERE level = 'paid')
                   / (SELECT COUNT(*) FROM fact_songplays), 1) AS paid_plays_pct;

-- Top 10 artists (raw artist name on the event, so all plays count, not only the 4.7% matched)
SELECT artist_name, COUNT(*) AS plays, COUNT(DISTINCT user_id) AS listeners
FROM fact_songplays
GROUP BY artist_name
ORDER BY plays DESC, artist_name
LIMIT 10;

-- Top 10 songs
SELECT song_title, artist_name, COUNT(*) AS plays
FROM fact_songplays
GROUP BY song_title, artist_name
ORDER BY plays DESC, song_title
LIMIT 10;

-- ======================================================================================
-- BQ1: Which hours and days of the week have the highest listening traffic?
-- ======================================================================================

-- Plays by hour of day
SELECT t.hour, COUNT(*) AS plays
FROM fact_songplays f
JOIN dim_time t ON t.start_time = f.start_time
GROUP BY t.hour
ORDER BY t.hour;

-- Plays by day of week (weekday 0 = Sunday)
SELECT t.weekday, t.weekday_name, t.is_weekend, COUNT(*) AS plays
FROM fact_songplays f
JOIN dim_time t ON t.start_time = f.start_time
GROUP BY t.weekday, t.weekday_name, t.is_weekend
ORDER BY t.weekday;

-- Heatmap: hour x weekday
SELECT t.weekday, t.weekday_name, t.hour, COUNT(*) AS plays
FROM fact_songplays f
JOIN dim_time t ON t.start_time = f.start_time
GROUP BY t.weekday, t.weekday_name, t.hour
ORDER BY t.weekday, t.hour;

-- ======================================================================================
-- BQ2: How does engagement (songs per session) differ between free and paid users?
-- ======================================================================================
SELECT level,
       COUNT(*) AS sessions,
       ROUND(AVG(songs::FLOAT), 1) AS avg_songs_per_session,
       MEDIAN(songs) AS median_songs_per_session
FROM (
    SELECT level, session_id, COUNT(*) AS songs
    FROM fact_songplays
    GROUP BY level, session_id
)
GROUP BY level
ORDER BY level;

-- ======================================================================================
-- BQ3: Upgrade funnel. Of the users who open the Upgrade page, what % submit, and how active are they?
-- ======================================================================================

-- Funnel numbers
WITH opened AS (SELECT DISTINCT user_id FROM fact_page_events WHERE page = 'Upgrade'),
     submitted AS (SELECT DISTINCT user_id FROM fact_page_events WHERE page = 'Submit Upgrade')
SELECT (SELECT COUNT(*) FROM opened) AS opened_upgrade_users,
       (SELECT COUNT(*) FROM submitted) AS submitted_upgrade_users,
       (SELECT COUNT(*) FROM opened WHERE user_id IN (SELECT user_id FROM submitted)) AS opened_and_submitted,
       ROUND(100.0 * (SELECT COUNT(*) FROM submitted) / (SELECT COUNT(*) FROM opened), 1) AS submit_pct;

-- Activity of the users who opened the Upgrade page: submitted vs not
WITH opened AS (SELECT DISTINCT user_id FROM fact_page_events WHERE page = 'Upgrade'),
     submitted AS (SELECT DISTINCT user_id FROM fact_page_events WHERE page = 'Submit Upgrade'),
     plays AS (SELECT user_id, COUNT(*) AS plays FROM fact_songplays GROUP BY user_id)
SELECT CASE WHEN s.user_id IS NOT NULL THEN 'submitted' ELSE 'did not submit' END AS outcome,
       COUNT(*) AS users,
       ROUND(AVG(COALESCE(p.plays, 0)::FLOAT), 1) AS avg_plays_per_user
FROM opened o
LEFT JOIN submitted s ON s.user_id = o.user_id
LEFT JOIN plays p ON p.user_id = o.user_id
GROUP BY 1
ORDER BY 1;

-- ======================================================================================
-- BQ4: Churn risk. Which paid users visit the Downgrade page, and does their activity drop beforehand?
-- Compares plays in the 7 days before the first visit with the 7 days before that.
-- (Data covers one month, so visits in the first two weeks have a shorter window.)
-- ======================================================================================
WITH d AS (
    SELECT user_id, MIN(start_time) AS first_visit, COUNT(*) AS visits
    FROM fact_page_events
    WHERE page = 'Downgrade' AND level = 'paid'
    GROUP BY user_id
),
submitted AS (SELECT DISTINCT user_id FROM fact_page_events WHERE page = 'Submit Downgrade')
SELECT d.user_id, d.visits, d.first_visit,
       CASE WHEN s.user_id IS NOT NULL THEN 'yes' ELSE 'no' END AS submitted_downgrade,
       SUM(CASE WHEN p.start_time >= d.first_visit - INTERVAL '7 days' AND p.start_time < d.first_visit
                THEN 1 ELSE 0 END) AS plays_last_7d,
       SUM(CASE WHEN p.start_time >= d.first_visit - INTERVAL '14 days'
                 AND p.start_time < d.first_visit - INTERVAL '7 days'
                THEN 1 ELSE 0 END) AS plays_prior_7d
FROM d
LEFT JOIN submitted s ON s.user_id = d.user_id
LEFT JOIN fact_songplays p ON p.user_id = d.user_id
GROUP BY d.user_id, d.visits, d.first_visit, s.user_id
ORDER BY SUM(CASE WHEN p.start_time >= d.first_visit - INTERVAL '7 days' AND p.start_time < d.first_visit THEN 1 ELSE 0 END)
       - SUM(CASE WHEN p.start_time >= d.first_visit - INTERVAL '14 days'
                   AND p.start_time < d.first_visit - INTERVAL '7 days' THEN 1 ELSE 0 END),
         d.user_id;

-- ======================================================================================
-- BQ5: Which states have the highest ratio of paid users?
-- Uses each user's latest event (location + level). Show user counts next to the ratio:
-- states with few users have unstable ratios.
-- ======================================================================================
WITH latest AS (
    SELECT user_id, level, location,
           ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY start_time DESC, event_id DESC) AS rn
    FROM fact_page_events
)
SELECT SPLIT_PART(location, ', ', 2) AS state,
       COUNT(*) AS users,
       SUM(CASE WHEN level = 'paid' THEN 1 ELSE 0 END) AS paid_users,
       ROUND(1.0 * SUM(CASE WHEN level = 'paid' THEN 1 ELSE 0 END) / COUNT(*), 2) AS paid_ratio
FROM latest
WHERE rn = 1
GROUP BY 1
ORDER BY users DESC, paid_ratio DESC, state;
