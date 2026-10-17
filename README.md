<p align="center">
  <img src="docs/assets/banner.svg" alt="Sparkify Cloud Data Warehouse" width="100%">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/AWS-Learner%20Lab-FF9900?style=for-the-badge" alt="AWS Learner Lab">
  <img src="https://img.shields.io/badge/Amazon%20Redshift-ra3.large-8C4FFF?style=for-the-badge" alt="Amazon Redshift">
  <img src="https://img.shields.io/badge/Amazon%20S3-raw%20data-569A31?style=for-the-badge" alt="Amazon S3">
  <img src="https://img.shields.io/badge/Python-3.12-3776AB?style=for-the-badge&logo=python&logoColor=white" alt="Python">
  <img src="https://img.shields.io/badge/Metabase-dashboard-509EE3?style=for-the-badge&logo=metabase&logoColor=white" alt="Metabase">
  <img src="https://img.shields.io/badge/status-work%20in%20progress-1DB954?style=for-the-badge" alt="Status">
</p>

<p align="center">
  <b>Cloud Technology Infrastructure — Data Engineering</b> · group project (5 members) · AWS Academy Learner Lab (us-east-1, $50 budget)
</p>

> 🎶 Sections marked _TODO_ are filled in step by step following [`guidance/GUIDELINE_README.md`](guidance/GUIDELINE_README.md).
> The original Sparkify reference is kept unchanged in [`guidance/README.md`](guidance/README.md).

---

## 🎧 1. Project Overview

Sparkify, a music streaming startup, collects user activity logs and song metadata as JSON files but cannot
answer business questions from them. This project builds a **cloud data warehouse on AWS** (S3 → Redshift → Metabase)
inside a secured VPC to turn the raw logs into analytics.

<p align="center"><img src="docs/assets/now_playing.svg" alt="Now playing: the ELT pipeline" width="640"></p>

## 🎯 2. Business Questions

| # | Question | Business use |
|---|---|---|
| BQ1 | Which hours and days of the week have the highest listening traffic? | Capacity planning / scaling |
| BQ2 | How does engagement (songs per session) differ between free and paid users? | Value of the subscription |
| BQ3 | Upgrade funnel — what % of users who open the Upgrade page actually submit, and how active are they? | Target free users for promotions |
| BQ4 | Churn risk — which paid users visit the Downgrade page, and does their activity drop beforehand? | Retention early-warning list |
| BQ5 | Which states have the highest ratio of paid users? | Regional marketing |

> BQ3 and BQ4 need non-`NextSong` events, so the model adds a second fact table `fact_page_events`.

## 💿 3. Dataset & Profiling

| Source | Files | Content |
|---|---|---|
| `song_data` | 14,896 JSON | Song + artist metadata (subset of the Million Song Dataset) |
| `log_data` | 30 JSON | App events, Nov 2018 — 8,056 events, 97 users, 941 sessions |
| `log_json_path.json` | 1 | JSONPath mapping for Redshift `COPY` |

Download locally: `python3 scripts/download_dataset.py` → `data/raw/`
Profiling notebook: [`notebooks/01_data_profiling.ipynb`](notebooks/01_data_profiling.ipynb)

<p align="center"><img src="docs/figures/profiling_page_counts.png" alt="Events by page type" width="70%"></p>

**Early answers from the raw data** (to be confirmed on Redshift):

<p align="center"><img src="docs/figures/profiling_bq1_hour_weekday.png" alt="BQ1 song plays by hour and weekday" width="100%"></p>
<p align="center"><img src="docs/figures/profiling_bq2_to_bq5.png" alt="BQ2 to BQ5 overview" width="100%"></p>

| 🔎 Finding | 🛠️ Design impact |
|---|---|
| Song match rate ≈ **4.7%** (319 / 6,820 plays) | No `DISTKEY(song_id)` on the fact table; match rate reported as a DQ metric |
| 396 `artist_id`s have >1 `artist_name` | Deduplicate `dim_artists` + duplicate-key DQ check |
| 286 events with empty `userId` (logged-out pages only) | Filter before loading user tables |
| 8 users switch free ↔ paid during the month | `dim_users` as **SCD Type 2** |
| Paid sessions: **28.4** songs vs free: **2.1** | Strong signal for BQ2 |

## ☁️ 4. Architecture

<p align="center"><img src="docs/figures/architecture_as_built.png" alt="As-built AWS architecture" width="100%"></p>

Full design (network, security groups, IAM, monitoring, Learner Lab constraints): [`docs/architecture.md`](docs/architecture.md) ·
editable diagrams: [`docs/architecture.drawio`](docs/architecture.drawio)

| Layer | Choice |
|---|---|
| Environment | **AWS Academy Learner Lab** — constraints in [`docs/architecture.md` §0](docs/architecture.md) |
| Region | `us-east-1` |
| Network | VPC `10.0.0.0/16`, 2 AZs, 2 public + 2 private subnets, Internet Gateway, S3 gateway endpoint, **no NAT** |
| Raw storage | S3 `sparkify-raw-<group>` (Block Public Access, SSE-S3, Versioning) |
| Data warehouse | Redshift provisioned, 1 × `ra3.large`, **private subnets**, not publicly accessible, Enhanced VPC Routing |
| ETL + dashboard | EC2 `t3.small` in a public subnet: Python ETL + Metabase (Docker) |
| Access | **Session Manager** (no SSH key, port 22 closed) |
| Security groups | `sg-app`: 3000 from team IPs only · `sg-redshift`: 5439 from `sg-app` only |
| IAM | Pre-created `LabRole` (Redshift → S3) and `LabInstanceProfile` (EC2 → SSM). Learner Lab cannot create custom roles |
| Monitoring | CloudWatch alarms (CPU, disk, health) → SNS email |

<details>
<summary>🔀 <b>Data flow</b> (click to expand)</summary>
<br>
<p align="center"><img src="docs/figures/data_flow.png" alt="ELT data flow" width="100%"></p>
</details>

## 🗂️ 5. Data Model

<p align="center"><img src="docs/figures/erd.png" alt="Star schema ERD" width="100%"></p>

Full design, data dictionary and rationale: [`docs/data_model.md`](docs/data_model.md) · ERD sources: [`docs/erd.drawio`](docs/erd.drawio) / [`docs/erd.mmd`](docs/erd.mmd)

| Table | Type | Grain | DISTSTYLE | SORTKEY |
|---|---|---|---|---|
| `fact_songplays` | Fact | one song play | `AUTO` | `start_time` |
| `fact_page_events` | Fact | one page event (logged-in) | `AUTO` | `start_time` |
| `dim_users` | Dimension, **SCD Type 2** | one user version (level period) | `ALL` | `user_id` |
| `dim_songs` | Dimension | one song | `ALL` | `song_id` |
| `dim_artists` | Dimension | one artist (deduplicated) | `ALL` | `artist_id` |
| `dim_time` | Dimension | one timestamp | `ALL` | `start_time` |

Why not the classic `DISTKEY(song_id)`? A picture is worth a thousand slices:

<p align="center"><img src="docs/assets/meme_distkey.svg" alt="Meme: DISTKEY(song_id) no, DISTSTYLE AUTO yes" width="560"></p>

## 🔄 6. ETL Pipeline

_TODO (Step 6)._ Planned run order:

```text
00_drop → 01_create_staging → 02_create_star_schema → 03_copy_from_s3 → 04_transform_load → 05_data_quality → 06_kpi_queries
```

## ✅ 7. Data Quality

_TODO (Step 6.6)._ Expected values from profiling, to compare with Redshift:

| Check | Expected |
|---|---|
| `staging_events` / `staging_songs` rows | 8,056 / 14,896 |
| `fact_songplays` rows (NextSong only) | 6,820 |
| `fact_page_events` rows (logged-in) | 7,770 |
| `dim_users` versions / current users | 106 / 97 |
| `dim_artists` rows (no duplicate keys) | 9,553 |
| NULL `user_id` / `start_time` in facts | 0 |
| Song match rate | ≈ 4.7% |

## 📊 8. KPI Results & Dashboard

_TODO (Step 6.7)._ Metabase dashboard screenshots will go in `screenshots/dashboard/`.

## 🏛️ 9. Well-Architected Pillars

Full review with proof checklist and failure scenarios: [`docs/well_architected.md`](docs/well_architected.md)

| Pillar | As-built (Learner Lab) | Ideal (production) |
|---|---|---|
| 🔒 **Security** | Redshift in private subnets, not public · SG chain (EC2 → Redshift 5439 only) · Metabase for team IPs only · no SSH (Session Manager) · S3 Block Public Access + SSE-S3 · Redshift encrypted · IAM role instead of keys · secrets gitignored | Least-privilege roles, Secrets Manager rotation, KMS CMK, HTTPS + WAF, CloudTrail, GuardDuty |
| 🟢 **Availability** | 2 AZs, Redshift subnet group in 2 AZs, S3 multi-AZ, Metabase auto-restart, health alarm | Redshift Multi-AZ, Metabase on ECS Fargate behind ALB |
| ♻️ **Resiliency** | Raw data in S3 (Versioning) → DW rebuildable · automated snapshots · idempotent ETL · data-quality gate · CloudWatch → SNS email | Cross-region snapshot copy, S3 CRR, Step Functions retries |
| 💰 **Cost** | 1 × `ra3.large`, pause when idle, `t3.small`, no NAT, free S3 endpoint, Metabase, one region, delete after demo | Reserved nodes / Serverless, S3 lifecycle → Glacier, AWS Budgets |

<details>
<summary>🚀 <b>Ideal production architecture</b> (cost not considered — click to expand)</summary>
<br>
<p align="center"><img src="docs/figures/architecture_ideal.png" alt="Ideal production architecture" width="100%"></p>
</details>

## 💸 10. Cost Estimate

Details and the $50 Learner Lab budget plan: [`docs/cost_estimate.md`](docs/cost_estimate.md) ·
AWS Pricing Calculator exports: [scenario A](docs/cost-estimate-scenario-a.pdf) · [scenario B](docs/cost-estimate-scenario-b.pdf)

| Scenario | Redshift hours | Monthly cost |
|---|---|---|
| 🎵 A — Learner Lab project (pause when idle) | 40 | ≈ **$25** (calculator $23.93 + public IPv4/EBS) |
| 🔁 B — Same architecture 24/7 | 730 | **$416.34** ($4,996 / year) |

> ⏸️ `ra3.large` costs **$0.543/hour**, so Redshift is over 90% of the bill. **Pause it after every session** —
> the Learner Lab does not do it for you. Checklists and teardown order: [`docs/cleanup.md`](docs/cleanup.md)

## ▶️ 11. How to Run

_TODO (after Step 6)._ Local profiling works today:

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
```

```bash
.venv/bin/python scripts/download_dataset.py
```

## 📁 12. Repository Structure

```text
├── README.md                # this file
├── guidance/                # original Sparkify README, step-by-step guide, progress checkpoint
├── config/dwh.cfg.example   # config template (copy to config/dwh.cfg, never commit)
├── data/raw/                # downloaded dataset (gitignored)
├── docs/                    # design docs, diagrams, cost estimate PDFs
│   ├── assets/              # README banner and animated graphics
│   └── figures/             # exported diagrams and profiling charts
├── notebooks/               # local data profiling (Jupyter)
├── report/                  # Word report (Thai) + generator source
├── requirements.txt         # Python packages for notebooks
├── screenshots/             # evidence per AWS service
├── scripts/                 # download / upload / create_tables / etl
└── sql/                     # 00–06 SQL files
```

## 👥 13. Team Roles

| Role | Responsibility | Member |
|---|---|---|
| Infra / Network | VPC, Security Groups, Redshift, EC2, architecture diagram | _TBD_ |
| Data Modeler | ERD, DDL, DIST/SORT key design | _TBD_ |
| ETL | COPY, transform SQL, `etl.py` | _TBD_ |
| Analytics | KPI queries, Metabase dashboard | _TBD_ |
| QA + Docs + PM | DQ checks, screenshots, README, report, cost estimate | _TBD_ |

---

<p align="center"><sub>🎵 Dataset: Sparkify sample from the Udacity Data Engineering program (subset of the Million Song Dataset). Built for learning purposes. 🎵</sub></p>
