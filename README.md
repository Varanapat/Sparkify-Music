# Sparkify Data Warehouse on AWS

> Cloud Technology Infrastructure — Data Engineering group project (5 members)
>
> Status: **work in progress** — sections marked _TODO_ are filled in step by step following [`guidance/GUIDELINE_README.md`](guidance/GUIDELINE_README.md).
> The original Sparkify reference is kept unchanged in [`guidance/README.md`](guidance/README.md).
> Environment: **AWS Academy Learner Lab** (us-east-1, budget $50).

## 1. Project Overview

Sparkify, a music streaming startup, collects user activity logs and song metadata as JSON files but cannot
answer business questions from them. This project builds a cloud data warehouse on AWS (S3 → Redshift → Metabase)
inside a secured VPC to turn the raw logs into analytics.

## 2. Business Questions

| # | Question | Business use |
|---|---|---|
| BQ1 | Which hours and days of the week have the highest listening traffic? | Capacity planning / scaling |
| BQ2 | How does engagement (songs per session) differ between free and paid users? | Value of the subscription |
| BQ3 | Upgrade funnel — what % of users who open the Upgrade page actually submit, and how active are they? | Target free users for promotions |
| BQ4 | Churn risk — which paid users visit the Downgrade page, and does their activity drop beforehand? | Retention early-warning list |
| BQ5 | Which states have the highest ratio of paid users? | Regional marketing |

> BQ3 and BQ4 need non-`NextSong` events, so the model adds a second fact table `fact_page_events`.

## 3. Dataset

| Source | Files | Content |
|---|---|---|
| `song_data` | 14,896 JSON | Song + artist metadata (subset of the Million Song Dataset) |
| `log_data` | 30 JSON | App events, Nov 2018 — 8,056 events, 97 users, 941 sessions |
| `log_json_path.json` | 1 | JSONPath mapping for Redshift `COPY` |

Download locally: `python3 scripts/download_dataset.py` → `data/raw/`

Profiling notebook: [`notebooks/01_data_profiling.ipynb`](notebooks/01_data_profiling.ipynb) — key findings:

| Finding | Design impact |
|---|---|
| Song match rate ≈ **4.7%** (319 / 6,820 plays) | No `DISTKEY(song_id)` on the fact table; match rate reported as a DQ metric |
| 396 `artist_id`s have >1 `artist_name` | Deduplicate `dim_artists` + duplicate-key DQ check |
| 286 events with empty `userId` (logged-out pages only) | Filter before loading user tables |
| 8 users switch free ↔ paid during the month | `dim_users.level` = latest event (or SCD Type 2) |
| Paid sessions: 28.4 songs vs free: 2.1 | Strong signal for BQ2 |

## 4. Architecture

Full design (network, security groups, IAM, monitoring, ideal architecture): [`docs/architecture.md`](docs/architecture.md)
Diagrams: [`docs/architecture.drawio`](docs/architecture.drawio). Pages: as-built, data flow, ideal.

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

## 5. Data Model

Full design, data dictionary and rationale: [`docs/data_model.md`](docs/data_model.md) · ERD: [`docs/erd.drawio`](docs/erd.drawio) / [`docs/erd.mmd`](docs/erd.mmd)

| Table | Type | Grain | DISTSTYLE | SORTKEY |
|---|---|---|---|---|
| `fact_songplays` | Fact | one song play | `AUTO` | `start_time` |
| `fact_page_events` | Fact | one page event (logged-in) | `AUTO` | `start_time` |
| `dim_users` | Dimension, **SCD Type 2** | one user version (level period) | `ALL` | `user_id` |
| `dim_songs` | Dimension | one song | `ALL` | `song_id` |
| `dim_artists` | Dimension | one artist (deduplicated) | `ALL` | `artist_id` |
| `dim_time` | Dimension | one timestamp | `ALL` | `start_time` |

## 6. ETL Pipeline — _TODO (Step 6)_

## 7. Data Quality — _TODO (Step 6.6)_

## 8. KPI Results & Dashboard — _TODO (Step 6.7)_

## 9. Well-Architected Pillars

Full review with proof checklist and failure scenarios: [`docs/well_architected.md`](docs/well_architected.md)

| Pillar | As-built (Learner Lab) | Ideal (production) |
|---|---|---|
| **Security** | Redshift in private subnets, not public · SG chain (EC2 → Redshift 5439 only) · Metabase for team IPs only · no SSH (Session Manager) · S3 Block Public Access + SSE-S3 · Redshift encrypted · IAM role instead of keys · secrets gitignored | Least-privilege roles, Secrets Manager rotation, KMS CMK, HTTPS + WAF, CloudTrail, GuardDuty |
| **Availability** | 2 AZs, Redshift subnet group in 2 AZs, S3 multi-AZ, Metabase auto-restart, health alarm | Redshift Multi-AZ, Metabase on ECS Fargate behind ALB |
| **Resiliency** | Raw data in S3 (Versioning) → DW rebuildable · automated snapshots · idempotent ETL · data-quality gate · CloudWatch → SNS email | Cross-region snapshot copy, S3 CRR, Step Functions retries |
| **Cost** | 1 × `ra3.large`, pause when idle, `t3.small`, no NAT, free S3 endpoint, Metabase, one region, delete after demo | Reserved nodes / Serverless, S3 lifecycle → Glacier, AWS Budgets |

## 10. Cost Estimate — _TODO (Step 8)_

## 11. How to Run — _TODO_

## 12. Repository Structure

```text
├── README.md                # this file (main project doc)
├── guidance/                # original Sparkify README, step-by-step guide, progress checkpoint
├── config/dwh.cfg.example   # config template (copy to config/dwh.cfg, never commit)
├── data/raw/                # downloaded dataset (gitignored)
├── docs/                    # diagrams, ERD, cost estimate, figures/
├── notebooks/               # local data profiling (Jupyter)
├── requirements.txt         # Python packages for notebooks
├── screenshots/             # evidence per AWS service
├── scripts/                 # download / upload / create_tables / etl
└── sql/                     # 00–06 SQL files
```

## 13. Team Roles

| Role | Responsibility | Member |
|---|---|---|
| Infra / Network | VPC, Security Groups, Redshift, EC2, architecture diagram | _TBD_ |
| Data Modeler | ERD, DDL, DIST/SORT key design | _TBD_ |
| ETL | COPY, transform SQL, `etl.py` | _TBD_ |
| Analytics | KPI queries, Metabase dashboard | _TBD_ |
| QA + Docs + PM | DQ checks, screenshots, README, report, cost estimate | _TBD_ |
