-- Drop all staging and star-schema tables (facts first, then dimensions, then staging)
DROP TABLE IF EXISTS fact_songplays;
DROP TABLE IF EXISTS fact_page_events;
DROP TABLE IF EXISTS dim_users;
DROP TABLE IF EXISTS dim_songs;
DROP TABLE IF EXISTS dim_artists;
DROP TABLE IF EXISTS dim_time;
DROP TABLE IF EXISTS staging_events;
DROP TABLE IF EXISTS staging_songs;
