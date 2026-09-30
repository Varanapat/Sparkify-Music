# Sparkify Music Streaming Analytics

A data warehouse project for analyzing user listening behavior, subscription activity, and music streaming patterns using **Amazon Redshift** and a **Star Schema**.

The project transforms raw event logs and song metadata into an analytics-ready dimensional model so that Data Analytics and Product teams can answer questions about listening behavior, subscription changes, and user engagement.

> **Project focus:** Data Warehouse Design · ETL · Amazon Redshift · SQL Analytics · Business KPIs · Amazon QuickSight

---

## 1. Project Overview

The Sparkify dataset contains two primary sources of raw JSON data:

- **Song Metadata (`song_data`)** — song and artist information derived from the Million Song Dataset.
- **User Event Logs (`log_data`)** — simulated application activity such as playing songs, navigating pages, skipping songs, and changing subscription levels.

The data is processed through a staging layer and transformed into a **Star Schema** consisting of one fact table and four dimension tables.

### Architecture

```text
                    ┌──────────────────┐
                    │    song_data     │
                    │   Song Metadata  │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │  staging_songs   │
                    └────────┬─────────┘
                             │
                             │
┌──────────────────┐         │         ┌────────────────────┐
│    log_data      │         │         │ log_json_path.json │
│   Event Logs     │─────────┼────────▶│   JSONPath Mapping │
└────────┬─────────┘         │         └────────────────────┘
         │                   │
         ▼                   ▼
┌──────────────────┐   ┌──────────────────┐
│  staging_events  │   │  Transformation  │
└────────┬─────────┘   │     & ETL        │
         │             └────────┬─────────┘
         └──────────────────────┘
                        │
                        ▼
              ┌─────────────────────┐
              │    Star Schema      │
              └─────────┬───────────┘
                        │
       ┌────────────────┼────────────────┐
       ▼                ▼                ▼
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│ dim_users   │  │ dim_songs   │  │dim_artists  │
└──────┬──────┘  └──────┬──────┘  └──────┬──────┘
       │                │                │
       └────────────────┼────────────────┘
                        ▼
               ┌─────────────────┐
               │ fact_songplays  │
               └────────┬────────┘
                        │
                        ▼
               ┌─────────────────┐
               │ Amazon QuickSight│
               │    Dashboard     │
               └─────────────────┘
```

---

## 2. Raw Data

### 2.1 Song Metadata — `song_data`

Song metadata is stored as JSON files and organized in S3 using the first three characters of the track ID.

Example:

```text
song_data/A/B/C/TRABCEI128F424C983.json
```

Example record:

```json
{
  "num_songs": 1,
  "artist_id": "AR8IEZO1187B99055E",
  "artist_latitude": null,
  "artist_longitude": null,
  "artist_location": "",
  "artist_name": "Marc Shaiman",
  "song_id": "SOINLJW12A8C13314C",
  "title": "City Slickers",
  "duration": 149.86404,
  "year": 2008
}
```

### 2.2 User Event Logs — `log_data`

Event logs represent user interactions with the Sparkify application.

Example:

```text
log_data/2018/11/2018-11-12-events.json
```

Each JSON record represents one user action, such as:

- Opening a page
- Playing a song
- Skipping a song
- Changing subscription level
- Navigating through the application

Example record:

```json
{
  "artist": "Sydney Youngblood",
  "auth": "Logged In",
  "firstName": "Jacob",
  "gender": "M",
  "itemInSession": 53,
  "lastName": "Klein",
  "length": 238.07955,
  "level": "paid",
  "location": "Tampa-St. Petersburg-Clearwater, FL",
  "method": "PUT",
  "page": "NextSong",
  "registration": 1540558108796.0,
  "sessionId": 954,
  "song": "Ain't No Sunshine",
  "status": 200,
  "ts": 1541057188796,
  "userAgent": "Mozilla/5.0...",
  "userId": "73"
}
```

### 2.3 JSONPath Mapping — `log_json_path.json`

Because the event logs contain mixed-case JSON keys such as `firstName`, `sessionId`, and `itemInSession`, a JSONPath mapping file is used when loading event data into Amazon Redshift.

```json
{
  "jsonpaths": [
    "$.artist",
    "$.auth",
    "$.firstName",
    "$.gender",
    "$.itemInSession",
    "$.lastName",
    "$.length",
    "$.level",
    "$.location",
    "$.method",
    "$.page",
    "$.registration",
    "$.sessionId",
    "$.song",
    "$.status",
    "$.ts",
    "$.userAgent",
    "$.userId"
  ]
}
```

---

## 3. Data Warehouse Design

The analytical grain is a **song-play event**, represented by records where:

```sql
page = 'NextSong'
```

The warehouse follows a **Star Schema** to simplify analytical queries and reduce unnecessary joins.

### Star Schema

```text
                         ┌─────────────────┐
                         │    dim_users    │
                         ├─────────────────┤
                         │ user_id (PK)    │
                         │ first_name      │
                         │ last_name       │
                         │ gender          │
                         │ level           │
                         └────────┬────────┘
                                  │
                                  │
┌─────────────────┐               │
│   dim_songs     │               │
├─────────────────┤               │
│ song_id (PK)    │───────┐       │
│ title           │       │       │
│ artist_id       │       │       │
│ year            │       │       │
│ duration        │       │       │
└─────────────────┘       │       │
                          ▼       ▼
                    ┌────────────────────┐
                    │   fact_songplays   │
                    ├────────────────────┤
                    │ songplay_key (PK)  │
                    │ start_time         │
                    │ user_id            │
                    │ level              │
                    │ song_id            │
                    │ artist_id          │
                    │ session_id         │
                    │ location           │
                    │ user_agent         │
                    └─────────┬──────────┘
                              │
                 ┌────────────┴────────────┐
                 ▼                         ▼
        ┌─────────────────┐       ┌─────────────────┐
        │  dim_artists    │       │    dim_time     │
        ├─────────────────┤       ├─────────────────┤
        │ artist_id (PK)  │       │ start_time (PK) │
        │ name            │       │ hour            │
        │ location        │       │ day             │
        │ latitude        │       │ week            │
        │ longitude       │       │ month           │
        └─────────────────┘       │ year            │
                                  │ weekday         │
                                  └─────────────────┘
```

---

## 4. Data Model

### Fact Table

#### `fact_songplays`

Stores song-play activity generated from user event logs.

| Column | Type | Description |
|---|---|---|
| `songplay_key` | BIGINT | Surrogate primary key |
| `start_time` | TIMESTAMP | Song-play timestamp |
| `user_id` | VARCHAR(50) | User identifier |
| `level` | VARCHAR(20) | Subscription level (`free` / `paid`) |
| `song_id` | VARCHAR(100) | Song identifier |
| `artist_id` | VARCHAR(100) | Artist identifier |
| `session_id` | INT | User session identifier |
| `location` | VARCHAR(255) | User location |
| `user_agent` | VARCHAR(500) | Client user-agent |

### Dimension Tables

#### `dim_users`

Contains user information.

- `user_id`
- `first_name`
- `last_name`
- `gender`
- `level`

#### `dim_songs`

Contains song information.

- `song_id`
- `title`
- `artist_id`
- `year`
- `duration`

#### `dim_artists`

Contains artist information.

- `artist_id`
- `name`
- `location`
- `latitude`
- `longitude`

#### `dim_time`

Provides time-based attributes for analytical queries.

- `start_time`
- `hour`
- `day`
- `week`
- `month`
- `year`
- `weekday`

---

## 5. Amazon Redshift Optimization

The warehouse uses Redshift distribution and sort strategies to improve analytical query performance.

### Distribution Keys

`fact_songplays` and `dim_songs` use:

```sql
DISTKEY(song_id)
```

This supports colocated joins between song-play records and song metadata.

### Distribution Style

Small dimension tables use:

```sql
DISTSTYLE ALL
```

for:

- `dim_users`
- `dim_artists`
- `dim_time`

Replicating small dimensions across nodes can reduce network data movement during joins.

### Sort Keys

`start_time` is used as a sort key for time-oriented queries:

```sql
SORTKEY(start_time)
```

This supports efficient date-range filtering through Redshift zone maps.

---

## 6. ETL Pipeline

The ETL process consists of three main stages:

```text
S3 Raw Data
    │
    ▼
Staging Tables
    │
    ├── Data type conversion
    ├── Timestamp conversion
    ├── Deduplication
    ├── Filtering invalid users
    └── Song metadata matching
    │
    ▼
Production Star Schema
    │
    ├── dim_users
    ├── dim_songs
    ├── dim_artists
    ├── dim_time
    └── fact_songplays
    │
    ▼
Business Analytics
```

### 6.1 Staging Tables

```sql
CREATE TABLE staging_events (
    artist          VARCHAR(500),
    auth            VARCHAR(50),
    firstName       VARCHAR(100),
    gender          VARCHAR(10),
    itemInSession   INT,
    lastName        VARCHAR(100),
    length          NUMERIC(10, 5),
    level           VARCHAR(20),
    location        VARCHAR(255),
    method          VARCHAR(20),
    page            VARCHAR(50),
    registration    NUMERIC(20, 0),
    sessionId       INT,
    song            VARCHAR(500),
    status          INT,
    ts              BIGINT,
    userAgent       VARCHAR(500),
    userId          VARCHAR(50)
);

CREATE TABLE staging_songs (
    num_songs        INT,
    artist_id        VARCHAR(100),
    artist_latitude  NUMERIC(10, 5),
    artist_longitude NUMERIC(10, 5),
    artist_location  VARCHAR(255),
    artist_name      VARCHAR(500),
    song_id          VARCHAR(100),
    title            VARCHAR(500),
    duration         NUMERIC(10, 5),
    year             INT
);
```

### 6.2 Production Tables

```sql
CREATE TABLE dim_users (
    user_id     VARCHAR(50) NOT NULL SORTKEY,
    first_name  VARCHAR(100),
    last_name   VARCHAR(100),
    gender      VARCHAR(10),
    level       VARCHAR(20),
    PRIMARY KEY (user_id)
) DISTSTYLE ALL;

CREATE TABLE dim_songs (
    song_id     VARCHAR(100) NOT NULL DISTKEY,
    title       VARCHAR(500) NOT NULL SORTKEY,
    artist_id   VARCHAR(100) NOT NULL,
    year        INT,
    duration    NUMERIC(10, 5),
    PRIMARY KEY (song_id)
);

CREATE TABLE dim_artists (
    artist_id   VARCHAR(100) NOT NULL SORTKEY,
    name        VARCHAR(500) NOT NULL,
    location    VARCHAR(255),
    latitude    NUMERIC(10, 5),
    longitude   NUMERIC(10, 5),
    PRIMARY KEY (artist_id)
) DISTSTYLE ALL;

CREATE TABLE dim_time (
    start_time  TIMESTAMP NOT NULL SORTKEY,
    hour        INT NOT NULL,
    day         INT NOT NULL,
    week        INT NOT NULL,
    month       INT NOT NULL,
    year        INT NOT NULL,
    weekday     INT NOT NULL,
    PRIMARY KEY (start_time)
) DISTSTYLE ALL;

CREATE TABLE fact_songplays (
    songplay_key BIGINT IDENTITY(1,1),
    start_time   TIMESTAMP NOT NULL SORTKEY,
    user_id      VARCHAR(50) NOT NULL,
    level        VARCHAR(20) NOT NULL,
    song_id      VARCHAR(100) DISTKEY,
    artist_id    VARCHAR(100),
    session_id   INT NOT NULL,
    location     VARCHAR(255),
    user_agent   VARCHAR(500),
    PRIMARY KEY (songplay_key),
    FOREIGN KEY (start_time) REFERENCES dim_time (start_time),
    FOREIGN KEY (user_id) REFERENCES dim_users (user_id),
    FOREIGN KEY (song_id) REFERENCES dim_songs (song_id),
    FOREIGN KEY (artist_id) REFERENCES dim_artists (artist_id)
);
```

### 6.3 Load Data from S3

The Redshift `COPY` command is used to load data from Amazon S3 into the staging tables.

```sql
COPY staging_events
FROM 's3://udacity-dend/log_data'
IAM_ROLE 'arn:aws:iam::<YOUR_ACCOUNT_ID>:role/<YOUR_REDSHIFT_ROLE>'
FORMAT AS JSON 's3://udacity-dend/log_json_path.json'
REGION 'us-west-2';

COPY staging_songs
FROM 's3://udacity-dend/song_data'
IAM_ROLE 'arn:aws:iam::<YOUR_ACCOUNT_ID>:role/<YOUR_REDSHIFT_ROLE>'
FORMAT AS JSON 'auto'
REGION 'us-west-2';
```

> Replace `<YOUR_ACCOUNT_ID>` and `<YOUR_REDSHIFT_ROLE>` with your AWS account and Redshift IAM role. Avoid committing credentials or sensitive configuration to Git.

---

## 7. Data Transformation

### Timestamp Conversion

Event timestamps are stored as Unix epoch milliseconds and converted to Redshift timestamps:

```sql
TIMESTAMP 'epoch'
    + (ts / 1000) * INTERVAL '1 second'
```

### User Deduplication

The latest user state is selected using `ROW_NUMBER()`:

```sql
ROW_NUMBER() OVER (
    PARTITION BY userId
    ORDER BY ts DESC
)
```

### Song Matching

Song metadata is matched to event logs using:

- Song title
- Artist name
- Song duration within a tolerance of 2 seconds

```sql
LEFT JOIN staging_songs s
    ON e.song = s.title
    AND e.artist = s.artist_name
    AND ABS(e.length - s.duration) < 2.0
```

Only events representing song plays are loaded into the fact table:

```sql
WHERE e.page = 'NextSong';
```

---

## 8. Business KPIs & Analytical Queries

Once the Star Schema is populated, the warehouse can support several business questions.

### KPI 1 — Peak Listening Hours

Identifies the hours with the highest number of song plays for each subscription level.

```sql
SELECT
    t.hour,
    f.level,
    COUNT(f.songplay_key) AS total_plays,
    DENSE_RANK() OVER (
        PARTITION BY f.level
        ORDER BY COUNT(f.songplay_key) DESC
    ) AS rank
FROM fact_songplays f
JOIN dim_time t
    ON f.start_time = t.start_time
GROUP BY t.hour, f.level
ORDER BY f.level, total_plays DESC;
```

**Business use cases:**

- Streaming infrastructure capacity planning
- Understanding user activity patterns
- Identifying high-traffic periods for marketing analysis

---

### KPI 2 — Average Session Duration & Activity

Measures engagement across Free and Paid users.

```sql
WITH session_metrics AS (
    SELECT
        user_id,
        session_id,
        level,
        MIN(start_time) AS session_start,
        MAX(start_time) AS session_end,
        COUNT(songplay_key) AS songs_played_in_session,
        DATEDIFF(
            'minute',
            MIN(start_time),
            MAX(start_time)
        ) AS session_duration_minutes
    FROM fact_songplays
    GROUP BY user_id, session_id, level
)
SELECT
    level,
    COUNT(DISTINCT session_id) AS total_sessions,
    ROUND(AVG(session_duration_minutes), 2) AS avg_duration_minutes,
    ROUND(AVG(songs_played_in_session), 2) AS avg_songs_per_session
FROM session_metrics
GROUP BY level;
```

This provides measures such as:

- Total sessions
- Average session duration
- Average number of songs per session

---

### KPI 3 — Subscription Upgrade Path

Analyzes users who transition from Free to Paid and the artists they listened to before the transition.

```sql
WITH user_level_progression AS (
    SELECT
        user_id,
        level,
        start_time,
        LAG(level, 1) OVER (
            PARTITION BY user_id
            ORDER BY start_time
        ) AS prev_level
    FROM fact_songplays
),
upgraded_users AS (
    SELECT DISTINCT
        user_id,
        start_time AS upgraded_at
    FROM user_level_progression
    WHERE prev_level = 'free'
      AND level = 'paid'
)
SELECT
    a.name AS artist_name,
    COUNT(f.songplay_key) AS plays_before_upgrade
FROM fact_songplays f
JOIN upgraded_users u
    ON f.user_id = u.user_id
    AND f.start_time < u.upgraded_at
JOIN dim_artists a
    ON f.artist_id = a.artist_id
GROUP BY a.name
ORDER BY plays_before_upgrade DESC
LIMIT 10;
```

---

## 9. Amazon QuickSight Dashboard

The warehouse can be connected to **Amazon QuickSight** for interactive data visualization.

### Data Connection

1. Configure the required Redshift network/security settings.
2. Create a QuickSight dataset using **Amazon Redshift** as the data source.
3. Join `fact_songplays` with the relevant dimension tables.
4. Use **SPICE** for in-memory analytical performance.

### Recommended Dashboard Components

| Visualization | Metric |
|---|---|
| KPI Cards | Total Streams, Unique Listeners, Paid vs Free |
| Line Chart | Streams by hour, separated by subscription level |
| Horizontal Bar Chart | Top Artists and Songs |
| Geospatial Map | Sessions by city/state |

Example dashboard structure:

```text
┌────────────────┬────────────────┬──────────────────┐
│ Total Streams  │ Unique Users  │   Paid vs Free   │
└────────────────┴────────────────┴──────────────────┘

┌─────────────────────────────────────────────────────┐
│             Streams by Hour (0–23)                  │
│                                                     │
└─────────────────────────────────────────────────────┘

┌──────────────────────────┬──────────────────────────┐
│     Top Artists/Songs    │     Geographic Map       │
│                          │                          │
└──────────────────────────┴──────────────────────────┘
```

---

## 10. Data Quality Considerations

Before presenting analytical results, validate the data pipeline.

### Recommended Checks

- Compare record counts between staging and production.
- Verify that `userId` is not null for fact records.
- Verify that `start_time` is populated.
- Check for duplicate dimension keys.
- Check song-to-artist relationships.
- Validate that only `NextSong` events enter `fact_songplays`.

### Important Edge Case

Some event records have an empty `userId`, typically representing users who have not logged in yet. These records should be filtered out when populating the production fact and user dimension tables.

---

## 11. Project Deliverables

The final project should include:

- [ ] Raw data source configuration
- [ ] Staging table DDL
- [ ] Production Star Schema DDL
- [ ] ETL / transformation SQL
- [ ] Data quality checks
- [ ] Business KPI queries
- [ ] ER Diagram / warehouse architecture
- [ ] Amazon QuickSight dashboard
- [ ] Screenshots of query results and dashboard

For automation, the project can be organized with Python scripts such as:

```text
create_tables.py
etl.py
```

Python can use libraries such as `psycopg2` or `boto3` to automate database and AWS operations.

---

## 12. Suggested Project Structure

```text
sparkify-music-streaming-analytics/
│
├── README.md
├── sql/
│   ├── create_tables.sql
│   ├── staging_tables.sql
│   ├── etl.sql
│   └── analytics.sql
│
├── scripts/
│   ├── create_tables.py
│   └── etl.py
│
├── config/
│   └── dwh.cfg.example
│
├── dashboard/
│   └── screenshots/
│
└── docs/
    └── architecture.png
```

> Keep credentials, IAM information, passwords, and private configuration outside version control. Use a configuration file or environment variables and commit only a safe example configuration such as `dwh.cfg.example`.

---

## 13. AWS Cost & Cleanup

Because Amazon Redshift and QuickSight can incur costs, resources should be monitored carefully during development.

Recommended practices:

- Use the smallest practical Redshift Serverless capacity during development.
- Avoid leaving provisioned Redshift resources running unnecessarily.
- Monitor AWS usage and available credits.
- Remove the Redshift namespace/workgroup after project evaluation.
- Disable or delete QuickSight resources when they are no longer needed.

---

## 14. Technologies

| Category | Technology |
|---|---|
| Cloud Storage | Amazon S3 |
| Data Warehouse | Amazon Redshift |
| Data Visualization | Amazon QuickSight |
| Database | PostgreSQL-compatible Redshift SQL |
| Programming | Python |
| Data Format | JSON |
| ETL | SQL / Python |
| Modeling | Star Schema |
| Query Engine | Amazon Redshift |

---

## 15. Learning Outcomes

This project demonstrates practical experience with:

- Designing a dimensional data warehouse
- Building a Star Schema
- Working with Amazon Redshift
- Loading JSON data from Amazon S3
- Designing staging and production tables
- Performing ETL transformations with SQL
- Handling Unix epoch timestamps
- Deduplicating records with window functions
- Optimizing Redshift distribution and sort keys
- Writing business-oriented analytical queries
- Building dashboards with Amazon QuickSight
- Applying data quality checks to an ETL pipeline

---

## 16. Summary

**Sparkify Music Streaming Analytics** transforms raw music metadata and user event logs into a structured analytical warehouse on Amazon Redshift.

The pipeline follows:

```text
Raw JSON
   ↓
Amazon S3
   ↓
Redshift Staging
   ↓
ETL & Data Transformation
   ↓
Star Schema
   ↓
Business KPI Queries
   ↓
Amazon QuickSight
```

The resulting warehouse provides a foundation for analyzing listening behavior, session engagement, subscription activity, and other business metrics from Sparkify's streaming data.
# Sparkify-Music
