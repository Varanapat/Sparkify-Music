# Well-Architected Review — 4 Pillars

> GUIDELINE Step 7 · Maps every design decision to the four pillars used in this course:
> **Security · Availability · Resiliency · Cost**.
> Environment: AWS Academy Learner Lab (us-east-1, budget $50). Details of each component are in [`architecture.md`](architecture.md).
>
> Each row has a **"Proof"** column: the screenshot or query result to capture during the build (Step 6). Those images go into report chapter 4.

## 0. Summary

| Pillar | Goal for this project | What we do (as-built in Learner Lab) | Main limitation in Learner Lab | Ideal / production (chapter 5) |
|---|---|---|---|---|
| **Security** | Nobody outside the team can reach the data. No secrets leak | Redshift in **private subnets**, not public · **SG chain** (only EC2 → Redshift 5439) · Metabase open to **team IPs only** · **no SSH** (Session Manager) · S3 **Block Public Access + SSE-S3** · Redshift **encrypted** · IAM **role** instead of access keys · secrets **gitignored** | `LabRole` is broad (cannot create least-privilege roles). Metabase uses HTTP | Least-privilege role per service, Secrets Manager with rotation, KMS CMK, HTTPS + WAF, CloudTrail, GuardDuty |
| **Availability** | The system can be used during the demo and work sessions | Network spans **2 AZs** · Redshift **subnet group in 2 AZs** · S3 is regional (multi-AZ by design) · Metabase restarts automatically | One Redshift node and one EC2 → **single points of failure**. Lab stops EC2 at session end | Redshift RA3 Multi-AZ multi-node, Metabase on ECS Fargate in 2 AZs behind an ALB |
| **Resiliency** | Recover from mistakes and failures without losing data | **Raw data kept in S3 (Versioning on)** → the warehouse can always be **rebuilt by re-running the ETL** · Redshift **automated snapshots** · ETL is **idempotent** (drop → create → load) · **data-quality gate** stops bad loads · CloudWatch **alarms → SNS email** | Snapshots in one region only, 1-day retention | Cross-region snapshot copy, S3 Cross-Region Replication, Step Functions retries |
| **Cost** | Finish the whole project inside **$50** | Smallest allowed node (**1 × `ra3.large`**) · **Pause Redshift** after every session · `t3.small` EC2 · **no NAT Gateway** (S3 gateway endpoint is free) · **Metabase instead of QuickSight** · everything in **one region** · delete all after the demo | Budget is small and Redshift is billed per hour while running | Reserved nodes or Redshift Serverless for 24/7 use, S3 lifecycle → Glacier, cost alerts with AWS Budgets |

## 1. Security

Security is designed in layers ("defense in depth"). Even if one layer fails, another still protects the data.

| Layer | Control | How it is configured | Why | Proof (screenshot) |
|---|---|---|---|---|
| Network | Private subnets for Redshift | Subnet group = Private A + Private B. `rtb-private` has **no** `0.0.0.0/0` route | The warehouse has no path to or from the internet | VPC → Route tables (`rtb-private`) |
| Network | Redshift not public | *Publicly accessible* = **No** | No public endpoint exists at all | Redshift → Cluster → Network and security |
| Network | Security-group chain | `sparkify-sg-redshift` inbound 5439 **only from `sparkify-sg-app`** (SG reference, not an IP) | Only the EC2 instance can connect, even inside the VPC | EC2 → Security Groups → `sparkify-sg-redshift` inbound |
| Network | Metabase restricted | `sparkify-sg-app` inbound 3000 from each team member's IP `/32` only | The dashboard is not open to the internet | `sparkify-sg-app` inbound rules |
| Network | No SSH | No key pair, port 22 **closed**, access via **Session Manager** | Removes the most attacked port. Sessions are logged | `sparkify-sg-app` (no port 22) + Session Manager terminal |
| Network | Private path to S3 | **S3 gateway endpoint** + Redshift **Enhanced VPC Routing** | `COPY` traffic stays on the AWS network and follows our routes | VPC → Endpoints · Redshift → Network and security |
| Identity | IAM role, not keys | Redshift uses `LabRole`, EC2 uses `LabInstanceProfile` | No access key is stored in code, config or on the server | Redshift → Associated IAM roles · EC2 → IAM role |
| Data at rest | S3 encryption | Default encryption **SSE-S3** | Data on disk is encrypted | S3 → bucket → Properties |
| Data at rest | Redshift encryption | Cluster **encryption on** | Warehouse storage and snapshots are encrypted | Redshift → Cluster → Properties |
| Data access | S3 Block Public Access | **All four** settings on | Bucket cannot be made public by mistake | S3 → bucket → Permissions |
| Secrets | No secrets in Git | `config/dwh.cfg`, `.env`, `*.pem` in `.gitignore`; admin password in Secrets Manager (option) or local file | Learner Lab keys / passwords never reach GitHub | `.gitignore` file + GitHub repo with no secrets |

**Limitations (write in chapter 5):**
- `LabRole` has wide permissions. In production we would use `RedshiftS3ReadRole` (read **only our bucket**) and `EC2SSMRole` (see [`architecture.md` §3.2](architecture.md)).
- Metabase is served over **HTTP**, so traffic between the browser and EC2 is not encrypted. Production would put it behind an ALB with an HTTPS certificate (ACM) and AWS WAF.
- Team IPs change (home / university Wi-Fi), so the `sparkify-sg-app` rule has to be updated. Option: SSM port forwarding, which needs **no inbound rule at all**.

## 2. Availability

> **Availability** = the system is up and usable when people need it (here: work sessions and the demo).

| Control | How | Why | Proof |
|---|---|---|---|
| 2 Availability Zones | VPC with subnets in `us-east-1a` and `us-east-1b` | Base for multi-AZ deployment | VPC → Resource map |
| Redshift subnet group in 2 AZs | Private A + Private B | Required by Redshift. Lets the cluster be restored or relocated to the other AZ | Redshift → Subnet groups |
| S3 for raw data | Regional service storing data across multiple AZs | Raw data stays available even if one AZ fails | S3 bucket overview |
| Metabase auto-restart | `docker run --restart unless-stopped` | The dashboard comes back by itself after the Lab restarts the EC2 | `docker ps` in Session Manager after a new session |
| Health alarm | CloudWatch `HealthStatus < 1` → SNS email | The team knows immediately if Redshift is unhealthy | CloudWatch → Alarms |

**Single points of failure (honest assessment):**

| Component | What happens if it fails | Why we accept it | Production fix |
|---|---|---|---|
| Redshift (1 node, 1 AZ) | Queries and dashboard stop until restored | Lab allows `ra3.large` only. Multi-AZ needs larger RA3 nodes. Budget | Redshift RA3 **Multi-AZ** |
| EC2 (1 instance) | ETL and Metabase stop | Budget and Lab limit. Raw data and DW are not affected | ECS Fargate in 2 AZs behind an **ALB** |
| Learner Lab session end | EC2 is stopped, public IP changes | Lab behaviour, cannot change | Real account, Elastic IP / DNS name with Route 53 |

**Demo-day checklist:** start the Lab about 30 minutes early → **resume** Redshift → wait for *Available* → check Metabase at the **new** EC2 IP → update `sparkify-sg-app` if the presenter's IP changed.

## 3. Resiliency

> **Resiliency** = the ability to **recover** from failures and mistakes (and not lose data).

The key idea: **raw data in S3 is the source of truth.** The warehouse is a derived copy, so it can always be rebuilt.

| Control | How | Why | Proof |
|---|---|---|---|
| Raw data separated from DW | JSON stays in S3. Redshift only holds loaded copies | Losing the warehouse never loses source data | S3 bucket contents |
| S3 Versioning | Enabled on the bucket | Accidental overwrite or delete can be undone | S3 → Properties → Versioning |
| Redshift automated snapshots | Retention 1 day | Restore the cluster to a recent point in time | Redshift → Snapshots |
| Idempotent ETL | `create_tables.py` drops and recreates, `etl.py` reloads everything | Re-running the pipeline always produces the same result | ETL log of two runs with equal row counts |
| Data-quality gate | `05_data_quality.sql` checks row counts, NULL keys, duplicate keys, song match rate. The pipeline **fails** if a check fails | Bad data does not silently reach the dashboard | DQ output in the ETL log |
| Alerting | CloudWatch alarms (CPU, disk, health) → **SNS email** | Problems are noticed before they become outages | Alarm in `ALARM` state + received email |

**Failure scenarios and recovery:**

| # | Scenario | Recovery | Data lost? |
|---|---|---|---|
| 1 | Bad transform loads wrong data | DQ gate stops the pipeline → fix SQL → re-run `etl.py` | No |
| 2 | Table dropped by mistake | Re-run `create_tables.py` + `etl.py` from S3 (or restore a table from a snapshot) | No |
| 3 | Redshift cluster deleted | Restore from snapshot, **or** create a new cluster and re-run the ETL | No (raw data in S3) |
| 4 | Raw file deleted or overwritten in S3 | Restore the previous **version** (Versioning) | No |
| 5 | EC2 instance lost | Launch a new EC2, `git clone`, start Metabase again | No (code in Git, data in Redshift) |
| 6 | Learner Lab session ends | EC2 restarts at the next session; Redshift keeps its data (paused or running) | No |
| 7 | Whole AZ fails | Restore the Redshift snapshot into the other AZ of the subnet group | Changes since the last snapshot (rebuilt from S3) |

Recovery targets (to be **measured during the build** and written in chapter 4):
- **RPO** (max data loss): **0** for raw data (S3 + Versioning). Warehouse: rebuildable from S3, so effectively 0.
- **RTO** (time to recover): ETL rebuild time = _measure with `time python etl.py`_ · snapshot restore time = _optional test_.

## 4. Cost

Detailed numbers and the $50 budget plan are in Step 8 (`docs/cost_estimate.md`, to be written).

| Decision | Saves money because | Trade-off |
|---|---|---|
| **1 × `ra3.large`** (smallest allowed) | Fewest node-hours. The dataset is only ~7.5 MB | No parallelism across nodes (not needed for this data) |
| **Pause Redshift** after every session | Compute is not billed while paused (only storage) | Resume takes a few minutes. Must not be forgotten: **the Lab does not pause it for us** |
| **No NAT Gateway** | A NAT Gateway is billed per hour plus per GB | Private subnets have no internet. Not needed: Redshift only talks to S3 |
| **S3 gateway endpoint** | Gateway endpoints for S3 are free | — |
| **`t3.small` EC2** | Burstable, low hourly price. The Lab also stops it at session end | Limited CPU/RAM (enough for Metabase + ETL) |
| **Metabase** instead of QuickSight | Open source, no per-user fee | We maintain it ourselves |
| **One region** (`us-east-1`) | No cross-region data transfer | No cross-region DR (ideal design only) |
| **Delete everything after the demo** | Stops all charges | Take all screenshots first |

**Daily routine (cost + safety):**
- Start of session: resume Redshift, then work.
- End of session: **pause Redshift**, stop EC2, then check the cost shown on the Lab page.

## 5. Other AWS Well-Architected Pillars (bonus)

AWS's official framework has six pillars: Operational Excellence, Security, Reliability, Performance Efficiency,
Cost Optimization and Sustainability. The course's **Availability + Resiliency** together match AWS **Reliability**.
The remaining three are also covered:

| AWS pillar | What we do |
|---|---|
| **Operational Excellence** | Everything is scripted (`sql/00–06`, `create_tables.py`, `etl.py`), version-controlled in Git, documented in README. Monitoring with CloudWatch + SNS |
| **Performance Efficiency** | Columnar MPP warehouse · `DISTSTYLE ALL` for small dimensions (no data movement on joins) · `SORTKEY start_time` on facts (time-range queries) · `DISTSTYLE AUTO` on facts to avoid skew from NULL `song_id` · parallel `COPY` from S3 |
| **Sustainability** | Smallest node, paused when idle, resources deleted after use |
