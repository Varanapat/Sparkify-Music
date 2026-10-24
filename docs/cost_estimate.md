# Cost Estimate & $50 Budget Plan

> GUIDELINE Step 8 · Prices from **AWS Pricing Calculator**, region **US East (N. Virginia)**, checked **2026-10-17**.
> Calculator exports: [`cost-estimate-scenario-a.pdf`](cost-estimate-scenario-a.pdf) · [`cost-estimate-scenario-b.pdf`](cost-estimate-scenario-b.pdf)
> Prices exclude tax and free tier. Learner Lab bills the same on-demand prices against the lab budget.

## 1. Unit Prices Used

| Service | Item | Price (us-east-1, on-demand) |
|---|---|---|
| Amazon Redshift | `ra3.large` node | **$0.543 / hour** |
| Amazon EC2 | `t3.small` (Linux) | $0.0208 / hour |
| Amazon EBS | gp3 volume | $0.08 / GB-month |
| Amazon S3 | Standard storage | $0.023 / GB-month |
| Amazon S3 | PUT/COPY/POST/LIST · GET | $0.005 per 1,000 · $0.0004 per 1,000 |
| Amazon CloudWatch | Standard-resolution alarm | $0.10 / alarm-month |
| Amazon VPC | Public IPv4 address (in use) | $0.005 / hour |
| VPC S3 gateway endpoint · SNS email (first 1,000) | — | Free |

**Redshift is over 90% of the bill in both scenarios** (91% in A, 95% in B). Every cost decision is really about how many hours Redshift runs.

## 2. Scenario A — This Project in Learner Lab (pay only while working)

Assumptions: Redshift runs **40 hours** for the whole project and is paused otherwise. EC2 runs **80 hours** (it runs whenever a Lab session is open).

| Redshift hours (plan) | Task |
|---|---|
| 8 h | First build: create tables, `COPY`, debug load errors |
| 16 h | ETL development, data-quality checks, KPI queries |
| 8 h | Metabase dashboard + screenshots |
| 8 h | Demo rehearsal + demo day |

| Service | Configuration | Monthly cost |
|---|---|---|
| Amazon Redshift | 1 × `ra3.large`, 40 h | **$21.72** |
| Amazon EC2 | 1 × `t3.small`, 80 h + 8 GB gp3 | $1.73 |
| Amazon S3 | 1 GB, 20k PUT, 150k GET | $0.18 |
| Amazon CloudWatch | 3 alarms | $0.30 |
| **Calculator total** | | **$23.93** |
| + Public IPv4 (not in calculator) | 80 h × $0.005 | $0.40 |
| + EBS kept while EC2 is stopped | full month 8 GB − prorated part | ~$0.57 |
| **Expected project total** | | **≈ $25 of $50** |

> The calculator charges public IPv4 for a full month and prorates EBS by running hours, so these two items were
> added by hand with the real Learner Lab behaviour (EC2 is stopped between sessions and its public IP is released).

## 3. Scenario B — Same Architecture Running 24/7 (production)

| Service | Configuration | Monthly cost |
|---|---|---|
| Amazon Redshift | 1 × `ra3.large`, 730 h | **$396.39** |
| Amazon EC2 | 1 × `t3.small`, 730 h + 8 GB gp3 | $15.82 |
| Amazon VPC | 1 public IPv4, 730 h | $3.65 |
| Amazon CloudWatch | 3 alarms | $0.30 |
| Amazon S3 | 1 GB, 20k PUT, 150k GET | $0.18 |
| **Total** | | **$416.34 / month · $4,996.08 / 12 months** |

## 4. Comparison

| | Scenario A (project) | Scenario B (24/7) |
|---|---|---|
| Redshift hours | 40 | 730 |
| Monthly cost | ≈ $25 | $416.34 |
| Share of B | **≈ 6%** | 100% |

**Interpretation for the report:** the architecture is identical. The ~94% saving comes only from **pausing Redshift
when nobody uses it**, plus design choices that remove always-on charges (no NAT Gateway ≈ $33/month saved,
free S3 gateway endpoint, Metabase instead of per-user QuickSight licences).

Ways to lower Scenario B in a real company (chapter 5):

| Option | How it saves | Example |
|---|---|---|
| Pause/resume schedule | Run Redshift only in business hours | 12 h × 22 working days = 264 h → **$143.35/month** instead of $396.39 |
| Reserved nodes | 1- or 3-year commitment for always-on clusters | Discount vs on-demand (check calculator) |
| Redshift Serverless | Pay per second of query compute, nothing when idle | Good for spiky dashboard use |
| Elastic IP / no public IP | Put the dashboard behind an ALB in private subnets | Removes per-instance public IPv4 charges |

## 5. $50 Budget Plan (Learner Lab)

| Item | Amount |
|---|---|
| Lab budget | $50.00 |
| Planned use (Scenario A) | ≈ $25 |
| **Safety buffer** | **≈ $25** (≈ 45 extra Redshift hours) |

**What a mistake costs:**

| Mistake | Extra cost | Budget left after (from plan) |
|---|---|---|
| Redshift left running overnight (12 h) | $6.52 | ≈ $18 buffer |
| Redshift left running 1 full day (24 h) | $13.03 | ≈ $12 buffer |
| Redshift left running a weekend (48 h) | $26.06 | **buffer gone** |
| EC2 left running 24 h | $0.50 | negligible |

**Rules for the team member who builds:**
1. **Pause Redshift** at the end of every session (Console → Redshift → Clusters → Actions → *Pause*). The Lab does **not** do it.
2. Check **"Used $X of $50"** on the Lab page at the start and end of every session, and write it down (proof for chapter 4).
3. Resume Redshift only when you need SQL. Writing code, diagrams and the report do not need it.
4. Never create a second Redshift node (Lab maximum is 2, and it would double the cost).
5. After the demo, **delete everything** (Step 10).

## 6. Actual Spend Log (fill in during the build)

| Date | Session work | Redshift hours | "Used" on Lab page |
|---|---|---|---|
| 2026-10-23 | สร้าง S3 + อัปโหลดข้อมูล, VPC, Security Groups, Redshift subnet group (ทุกอย่างฟรี) | 0 | $0 |
| 2026-10-24 | สร้าง EC2 + Redshift `sparkify-dwh` (1 × `ra3.large`), ETL ผ่าน (COPY 666.7 วินาที, DQ ผ่านทุกข้อ), KPI ครบ, Metabase ต่อ Redshift ได้ | ≈ 1.3–1.5 _(ประมาณจากกราฟ CloudWatch CPUUtilization: ข้อมูลช่วง 20:17 ถึง ~21:36 UTC ของ 2026-10-23 (= ราว 03:17–04:36 เวลาไทย 2026-10-24) คิดเป็น ≈ $0.7–0.8 ที่ $0.543/ชม.)_ | $0.4 _(ตรวจตอนเริ่ม session ถัดไป ต่ำกว่าประมาณการ $0.7–0.8 อาจเพราะยอดบนหน้า Lab อัปเดตช้า หรือชั่วโมงจริงน้อยกว่าที่ประมาณ)_ |
| 2026-10-24 (รอบเย็น) | สร้าง SNS `sparkify-alerts` + CloudWatch alarm 3 ตัว, ทดสอบบังคับ ALARM ได้อีเมลแจ้งเตือน (Redshift Paused ตลอดรอบ, EC2 เปิดอัตโนมัติ) | 0 | $0.8 _(เริ่มรอบที่ $0.4, เพิ่ม $0.4 ผมคาดว่าเป็นยอดของ Redshift รอบก่อนที่เพิ่งถูกนับ ซึ่งสอดคล้องกับประมาณการ $0.7–0.8 ไม่ได้ยืนยัน)_ |
| 2026-10-25 | Resume Redshift, สร้าง Metabase ใหม่ + dashboard `Sparkify KPI` (KPI cards, BQ1–BQ5, Top 10 artists), alarm `health` ส่งอีเมลตอน Pause (Pause + Stop EC2 ก่อนจบ) | ≈ 2 _(ประมาณโดยผู้ทำจากเวลาทำงานรอบนี้ คิดเป็น ≈ $1.1 ที่ $0.543/ชม.)_ | $0.9 _(เริ่มรอบที่ $0.8 ตามที่บันทึกก่อนหน้า ยอดอาจอัปเดตช้า)_ |
| **Total** | | | |
