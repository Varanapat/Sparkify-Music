# GUIDELINE — Sparkify Data Warehouse on AWS (Step-by-Step)

> คู่มือนี้คือ "ลำดับการทำงาน" ตั้งแต่ศูนย์จนส่งงาน สำหรับโปรเจกต์ Data Warehouse วิชา Cloud
> โดยใช้ README ของ Sparkify เป็นตัวตั้ง และใช้รูปเล่มของรุ่นพี่ (G21 ตามใจเชฟ) เป็น reference เรื่องโครงรายงาน
>
> ✅ = ต้องทำ · ⭐ = ทำแล้วได้คะแนนเพิ่ม · ⚠️ = จุดที่คนพังบ่อย

---

## Step 0 — อ่านก่อนเริ่ม: Review ตัวอย่างที่มีอยู่

### 0.1 รูปเล่มรุ่นพี่ (G21 ตามใจเชฟ) — เอาอะไรมาใช้ได้

รุ่นพี่ทำ **Web Application** (EC2 + ALB + Auto Scaling + RDS ใน VPC 2 AZ) ไม่ใช่ Data Warehouse
แต่สิ่งที่ควร "ยืม" มาคือ **สิ่งที่อาจารย์ให้คะแนน** ซึ่งเห็นชัดจากเล่ม:

| สิ่งที่รุ่นพี่มี | ความหมายสำหรับโปรเจกต์เรา |
|---|---|
| Architecture diagram มี Region → VPC → AZ 2 ฝั่ง → Public/Private subnet → Security Group | Diagram ของเราก็ต้องวาด **ระดับ network** แบบนี้ ไม่ใช่แค่ S3 → Redshift → Dashboard ลอย ๆ |
| ฐานข้อมูลอยู่ใน **Private subnet** | Redshift ของเราต้องอยู่ private subnet เหมือนกัน |
| บทที่ 4.2 มี screenshot ของทุก service ที่ใช้จริง (EC2, ALB, ASG, RDS, VPC, Route table, SG) | ต้องเก็บ screenshot ทุก service **ระหว่างทำ** (ไม่ใช่มาย้อนเก็บตอนท้าย เพราะ Lab อาจหมดอายุ) |
| 5.5 ประมาณการค่าใช้จ่าย (รูปจาก Pricing Calculator) | ต้องมี cost estimate |
| 5.6 ออกแบบเพิ่มเติม "โดยไม่คำนึงถึงค่าใช้จ่าย" | ต้องมี section "ideal architecture" (สิ่งที่ Lab ทำไม่ได้แต่ production ควรมี) |
| โครงเล่ม 5 บท | ใช้โครงเดียวกันได้ (ดู Step 9) |

จุดอ่อนของเล่มรุ่นพี่ที่ **ไม่ควรเลียนแบบ**: บทที่ 2 อธิบายทฤษฎีกว้างเกิน (HTML/CSS/PHP) แต่แทบไม่อธิบายว่า
*ทำไม* เลือก service นั้น และไม่พูดถึง Security/Resiliency เป็นระบบ → ของเราควรมีตาราง mapping 4 pillars ชัด ๆ (Step 7)

### 0.2 README Sparkify — ใช้ได้ แต่มีจุดต้องแก้/ระวัง

1. ⚠️ **ความ original** — Sparkify คือโปรเจกต์ Udacity Data Engineering ที่โด่งดังมาก มี repo บน GitHub เป็นพัน ๆ อัน
   ถ้าอาจารย์รู้จัก อาจมองว่าก๊อป → **ต้องทำให้เป็นของเราเอง** เช่น ตั้ง business question ใหม่, เพิ่ม KPI ของตัวเอง,
   ออกแบบ network/security เอง, หรือทำ dashboard ของตัวเอง (README ไม่มี network design เลย ซึ่งเป็นส่วนที่วิชานี้ให้คะแนน)
2. ⚠️ **ไม่มี Infrastructure design** — README มีแต่ data model + SQL ไม่มี VPC / subnet / security group / IAM / monitoring / backup
   ซึ่งเป็นแก่นของวิชา Cloud
3. ⚠️ **Song matching rate ต่ำมาก** — `song_data` ของ Udacity เป็น subset เล็ก ๆ ทำให้ `fact_songplays` ส่วนใหญ่มี
   `song_id` / `artist_id` เป็น `NULL` (ปกติ match ได้แค่หลักร้อยจากหลายพันแถว)
   → KPI 3 (JOIN `dim_artists`) จะเหลือข้อมูลน้อยมาก ต้องเขียนอธิบายในรายงาน หรือรายงาน match rate เป็น DQ metric
4. ⚠️ **`DISTKEY(song_id)` บน fact จะ skew** — เพราะ `song_id` เป็น NULL เกือบทั้งหมด → NULL ทุกแถว hash ไปลง slice เดียว
   → แนะนำเปลี่ยน fact เป็น `DISTSTYLE AUTO` (หรือ `EVEN`) แล้วเขียนอธิบายเหตุผลในรายงาน (จะดูเข้าใจ Redshift จริง ได้คะแนนกว่า copy มา)
5. ⚠️ **`s3://udacity-dend` เป็น bucket ของคนอื่น** อยู่ `us-west-2` และอาจถูกปิดเมื่อไหร่ก็ได้
   → ให้ **copy data มาไว้ bucket ของเราเอง** (ได้โชว์การใช้ S3 จริง + ไม่พึ่งของคนอื่น)
6. ⚠️ **IAM Role / QuickSight / Redshift Serverless อาจใช้ไม่ได้ใน AWS Academy Learner Lab** — ดู Step 1
7. เล็กน้อย: `dim_songs` ใช้ `SORTKEY(title)` ไม่ค่อยมีเหตุผล (ไม่ได้ filter ด้วย title) · `dim_users.level` เก็บแค่ค่าล่าสุด
   (ถ้าอยากโชว์ความรู้ DW เพิ่ม ⭐ ทำเป็น SCD Type 2 ได้)

---

## Step 1 — เช็คเงื่อนไขก่อนลงมือ (วันแรก)

- [ ] ✅ ถามอาจารย์/อ่าน spec: ต้องส่งอะไรบ้าง (GitHub link, diagram, รูปเล่ม, demo สด?), deadline, เกณฑ์คะแนน
      (ถ้าเกณฑ์มี Resiliency / Availability / Cost / Security ให้จดไว้เลย จะใช้ใน Step 7)
- [ ] ✅ ถามว่าใช้ dataset ที่เป็นโปรเจกต์สาธารณะ (Sparkify) ได้ไหม
- [ ] ✅ เปิด **Learner Lab → README / "AWS Services and Limits"** แล้วเช็คให้ชัดว่า service ต่อไปนี้ใช้ได้ไหม และมี limit อะไร:

| Service | สิ่งที่ต้องเช็ค | ถ้าใช้ไม่ได้ ให้ใช้แทน |
|---|---|---|
| Amazon Redshift (provisioned) | node type ที่อนุญาต, จำนวน node สูงสุด | — (ตัวหลัก ต้องได้) |
| Redshift Serverless | รองรับไหม | ใช้ provisioned cluster 1 node |
| Amazon QuickSight | รองรับไหม (ส่วนใหญ่ Learner Lab **ไม่รองรับ**) | Metabase บน EC2 / Redshift Query Editor v2 (มี chart) |
| IAM | สร้าง role เองได้ไหม (ส่วนใหญ่ **ไม่ได้**) | ใช้ `LabRole` ที่ Lab เตรียมไว้ |
| Region | ใช้ได้แค่ region ไหน (มักเป็น `us-east-1`, `us-west-2`) | ทำทุกอย่างใน region เดียว |
| Cloud9 | AWS ปิดรับลูกค้าใหม่ไปแล้ว | ใช้ EC2 + Session Manager หรือ CloudShell |

- [ ] ⚠️ จำไว้: Learner Lab มี **budget จำกัด** และ session หมดอายุ ~4 ชม. — บาง service (เช่น Redshift) **ยังรันและกินเงินต่อ**
      แม้ session หมด → ต้อง Pause/Delete เสมอ (Step 10)

---

## Step 2 — ตั้ง GitHub Repo

```text
sparkify-dwh-aws/
├── README.md                  # เอกสารหลักของโปรเจกต์ (แก้จาก README Sparkify + เพิ่ม infra)
├── .gitignore
├── docs/
│   ├── architecture.drawio     # ไฟล์ต้นฉบับ diagram
│   ├── architecture.png
│   ├── erd.png
│   └── cost-estimate.pdf       # export จาก AWS Pricing Calculator
├── sql/
│   ├── 00_drop_tables.sql
│   ├── 01_create_staging.sql
│   ├── 02_create_star_schema.sql
│   ├── 03_copy_from_s3.sql
│   ├── 04_transform_load.sql
│   ├── 05_data_quality.sql
│   └── 06_kpi_queries.sql
├── scripts/
│   ├── upload_to_s3.sh         # copy raw data เข้า bucket เรา
│   ├── create_tables.py
│   └── etl.py
├── config/
│   └── dwh.cfg.example         # ตัวอย่าง config (ไม่มี password จริง)
└── screenshots/                # เก็บหลักฐานทุก step
    ├── s3/ vpc/ redshift/ ec2/ dashboard/ cloudwatch/
```

- [ ] ✅ สร้าง repo, เพิ่ม collaborator ทุกคนในกลุ่ม
- [ ] ✅ `.gitignore` อย่างน้อยต้องมี:

```gitignore
dwh.cfg
.env
*.pem
__pycache__/
.venv/
```

- [ ] ⚠️ **ห้าม commit** AWS Access Key / Session Token ของ Learner Lab, password Redshift, ไฟล์ `.pem`
      (ถ้าเผลอ commit ไปแล้ว การลบใน commit ถัดไปไม่พอ — ต้องเปลี่ยน password และ rewrite history)
- [ ] ⭐ แบ่งงานผ่าน GitHub Issues / Project board + ทำงานเป็น branch แล้ว PR (อาจารย์เห็น contribution ของแต่ละคน)

---

## Step 3 — เข้าใจ Data + ตั้ง Business Questions ของตัวเอง

- [ ] ✅ โหลดตัวอย่าง `song_data` 2–3 ไฟล์ และ `log_data` 1 ไฟล์มาเปิดดูในเครื่อง (Python/pandas)
- [ ] ✅ สำรวจ: แต่ละ field หมายถึงอะไร, มี null ตรงไหน, `page` มีค่าอะไรบ้าง, `userId` ว่างกี่แถว, `ts` เป็น epoch ms
- [ ] ✅ ลอง match song ↔ event (title + artist + duration) ในเครื่องก่อน → จะได้รู้ match rate ล่วงหน้า (ไม่ตกใจตอนอยู่บน Redshift)
- [ ] ✅ เขียน **Business Questions 3–5 ข้อ** (ข้อนี้คือจุดที่ทำให้งานเป็นของเรา) เช่น
  - ช่วงเวลาไหน traffic สูงสุด → capacity planning (มีใน README)
  - Free vs Paid ฟังกี่เพลง/session ต่างกันแค่ไหน (มีใน README)
  - ⭐ ของใหม่: Downgrade (paid→free) เกิดกับ user แบบไหน / หน้าไหนที่ user เปิดบ่อยก่อนออก (ใช้ `page` อื่นที่ไม่ใช่ NextSong)
  - ⭐ ของใหม่: Device/Browser (จาก `userAgent`) กับ engagement
  - ⭐ ของใหม่: เมือง/รัฐที่มี paid user สัดส่วนสูง
- [ ] ⚠️ ถ้าคำถามต้องใช้ข้อมูลที่ fact table ตัดทิ้ง (เช่น page อื่น) อาจต้องเพิ่ม fact table ที่ 2 เช่น `fact_page_events` ⭐

---

## Step 4 — ออกแบบ Data Model

- [ ] ✅ ยืนยัน **grain** ของ fact: 1 แถว = 1 การเล่นเพลง (`page = 'NextSong'`)
- [ ] ✅ วาด **ERD / Star Schema** (dbdiagram.io หรือ draw.io) → `docs/erd.png`
- [ ] ✅ ตัดสินใจเรื่อง Redshift physical design และ **เขียนเหตุผลไว้** (ส่วนนี้คือที่โชว์ความเข้าใจ):

| Table | DISTSTYLE | SORTKEY | เหตุผล |
|---|---|---|---|
| `fact_songplays` | `AUTO` (หรือ `EVEN`) | `start_time` | `song_id` ส่วนใหญ่เป็น NULL → ถ้าใช้ KEY จะ skew |
| `dim_users` | `ALL` | `user_id` | ตารางเล็ก, replicate ทุก node |
| `dim_songs` | `ALL` (ข้อมูลเล็ก) | `song_id` | — |
| `dim_artists` | `ALL` | `artist_id` | — |
| `dim_time` | `ALL` | `start_time` | — |

- [ ] ⭐ ถ้าทำเพิ่ม: `dim_users` แบบ SCD Type 2 (`valid_from`, `valid_to`, `is_current`) เพื่อเก็บประวัติ free/paid

---

## Step 5 — ออกแบบ AWS Architecture Diagram

เครื่องมือ: **draw.io (diagrams.net)** → เปิด shape library "AWS 2025/AWS Architecture Icons"

### 5.1 Architecture ที่แนะนำ (ทำได้จริงใน Learner Lab)

```text
AWS Cloud
└── Region (us-east-1)
    ├── Amazon S3  ── bucket: sparkify-raw-<group>      (Block Public Access, SSE-S3, Versioning)
    │                  ├── song_data/  log_data/  log_json_path.json
    │
    ├── IAM: LabRole  (Redshift ใช้ role นี้อ่าน S3)
    │
    └── VPC  10.0.0.0/16
        ├── Internet Gateway
        ├── S3 Gateway VPC Endpoint  (ให้ Redshift/EC2 คุยกับ S3 ผ่าน network ภายใน AWS)
        │
        ├── AZ-a
        │   ├── Public subnet 10.0.1.0/24 ── EC2 (ETL runner + Metabase dashboard)  [SG: sg-app]
        │   └── Private subnet 10.0.11.0/24 ─┐
        └── AZ-b                             ├── Redshift Subnet Group ── Redshift cluster  [SG: sg-redshift]
            ├── Public subnet 10.0.2.0/24    │
            └── Private subnet 10.0.12.0/24 ─┘

Monitoring: CloudWatch (Redshift CPU / Storage alarms) → SNS (email แจ้งเตือน)
Users ──HTTPS/3000 (เฉพาะ IP กลุ่ม)──▶ EC2 Metabase ──5439──▶ Redshift ◀──COPY── S3
```

### 5.2 Security Group rules

| SG | Inbound | Source | เหตุผล |
|---|---|---|---|
| `sg-app` (EC2) | 3000 (Metabase) | IP ของกลุ่ม `/32` | เปิดเฉพาะคนในกลุ่ม |
| `sg-app` (EC2) | 22 (SSH) | ไม่เปิด — ใช้ Session Manager แทน ⭐ | ลด attack surface |
| `sg-redshift` | 5439 | `sg-app` | Redshift รับเฉพาะจาก EC2 เท่านั้น |

- [ ] ✅ วาด diagram ให้มี Region / VPC / AZ / subnet / SG / ลูกศร data flow (ดูรุ่นพี่ รูป 3.1 เป็นแนว)
- [ ] ✅ วาด **Data Flow diagram** แยกอีกรูป (S3 raw → staging → star schema → KPI → dashboard)
- [ ] ⭐ วาดอีกรูป "Ideal / Production architecture" สำหรับบท 5 (Step 9)

---

## Step 6 — Build บน AWS จริง (ทำตามลำดับ)

> ทุก sub-step: **แคป screenshot เก็บใน `screenshots/` ทันที** + จดค่าที่ตั้งไว้ใน README

### 6.1 S3 — เก็บ Raw Data

- [ ] สร้าง bucket `sparkify-raw-<groupname>` ใน region เดียวกับ Redshift
- [ ] เปิด Block all public access, Default encryption (SSE-S3), Versioning
- [ ] Copy data มาไว้ bucket เรา (รันใน CloudShell หรือ EC2):

```bash
# ถ้า bucket ต้นทางยังเปิด public อยู่
aws s3 sync s3://udacity-dend/log_data  s3://sparkify-raw-<group>/log_data  --source-region us-west-2
aws s3 sync s3://udacity-dend/song_data s3://sparkify-raw-<group>/song_data --source-region us-west-2
aws s3 cp   s3://udacity-dend/log_json_path.json s3://sparkify-raw-<group>/ --source-region us-west-2
```

- [ ] ⚠️ `song_data` มีไฟล์เล็กจำนวนมาก sync อาจนาน → ถ้าช้ามากให้ sync แค่บาง prefix (เช่น `song_data/A/A/`) ตอน dev ก่อน
- [ ] ⚠️ ถ้า `udacity-dend` เข้าไม่ได้แล้ว → หา dataset mirror (Kaggle/GitHub) โหลดลงเครื่องแล้ว `aws s3 cp --recursive` ขึ้นเอง

### 6.2 VPC + Networking

- [ ] สร้าง VPC ด้วย "VPC and more" wizard: 2 AZ, 2 public + 2 private subnet, **NAT Gateway = None** (NAT กินเงิน), S3 Gateway endpoint = เลือก
- [ ] สร้าง Security Groups `sg-app`, `sg-redshift` ตามตาราง 5.2

### 6.3 Redshift

- [ ] สร้าง **Cluster subnet group** ใช้ private subnet ทั้ง 2 AZ
- [ ] สร้าง cluster: node เล็กสุดที่ Lab อนุญาต, 1 node, Publicly accessible = **No**, SG = `sg-redshift`
- [ ] Associate IAM role = **`LabRole`** (ARN หน้าตาแบบ `arn:aws:iam::<account-id>:role/LabRole`)
- [ ] เปิด automated snapshot (retention 1 วันก็พอ) → ใช้ตอบเรื่อง Resiliency
- [ ] ⚠️ จด endpoint, db name, user ลง `dwh.cfg` (ไฟล์จริงอยู่ในเครื่อง ไม่ขึ้น Git)

### 6.4 EC2 (ETL runner + Dashboard)

- [ ] Launch EC2 `t3.small`/`t3.micro` (Amazon Linux 2023) ใน public subnet, SG = `sg-app`, IAM instance profile = `LabInstanceProfile`
- [ ] ติดตั้ง: `python3-pip`, `psycopg2-binary`, `boto3`, `git`, `docker`
- [ ] `git clone` repo ของกลุ่มลงมา

### 6.5 Load + ETL

- [ ] รัน `create_tables.py` (drop → create staging → create star schema)
- [ ] รัน `etl.py`: COPY จาก **bucket ของเรา** + INSERT … SELECT เข้า star schema

```sql
COPY staging_events
FROM 's3://sparkify-raw-<group>/log_data'
IAM_ROLE 'arn:aws:iam::<account-id>:role/LabRole'
FORMAT AS JSON 's3://sparkify-raw-<group>/log_json_path.json'
REGION 'us-east-1';
```

- [ ] ⚠️ COPY พังให้ดู `SELECT * FROM sys_load_error_detail ORDER BY start_time DESC LIMIT 20;` (หรือ `stl_load_errors`)
- [ ] ✅ ทดสอบ query ผ่าน **Redshift Query Editor v2** ด้วย (แคปภาพผลลัพธ์ทุก KPI)

### 6.6 Data Quality

- [ ] สร้าง `sql/05_data_quality.sql` อย่างน้อย:
  - row count staging vs production
  - `user_id`, `start_time` ใน fact ไม่เป็น NULL
  - ไม่มี duplicate PK ใน dimension (Redshift **ไม่ enforce** PK/FK — ต้องเช็คเอง ⚠️)
  - fact มีแต่ `NextSong`
  - **song match rate** = `COUNT(song_id) / COUNT(*)` ของ fact → รายงานตรง ๆ ในเล่ม
- [ ] ⭐ ให้ `etl.py` รัน DQ check ท้าย pipeline แล้ว fail ถ้าไม่ผ่าน

### 6.7 KPI Queries + Dashboard

- [ ] รัน KPI ทุกข้อจาก Step 3 → save ผลเป็น screenshot / CSV
- [ ] Dashboard (เลือกอย่างใดอย่างหนึ่ง):
  - **QuickSight** — ถ้า Lab รองรับ (ต้องตั้ง VPC connection ไป Redshift ด้วย)
  - **Metabase บน EC2** — `docker run -d -p 3000:3000 metabase/metabase` → connect Redshift endpoint (ผ่าน private network)
  - **Query Editor v2 charts** — ง่ายสุด แต่ดูไม่เป็น dashboard เท่าไหร่
- [ ] ✅ Dashboard ขั้นต่ำ: KPI cards (total plays, unique users, % paid), line chart plays by hour, bar top artists/songs, map/table by location

### 6.8 Monitoring ⭐

- [ ] CloudWatch alarm: Redshift `CPUUtilization > 80%`, `PercentageDiskSpaceUsed > 80%`
- [ ] SNS topic ส่ง email เมื่อ alarm ทำงาน (แคปภาพ email ที่ได้รับเป็นหลักฐาน)

---

## Step 7 — Map งานกับ 4 Pillars (ใส่ในเล่ม + README)

| Pillar | ทำจริงในโปรเจกต์ | ในโลกจริง/ideal (บท 5) |
|---|---|---|
| **Security** | Redshift อยู่ private subnet, SG chain (EC2→Redshift เท่านั้น), S3 Block Public Access + SSE, ใช้ IAM role ไม่ฝัง key, ไม่ commit secret, Redshift encryption | Secrets Manager เก็บ password, KMS CMK, IAM least-privilege role แยกต่อ service, CloudTrail audit |
| **Availability** | Subnet group ครอบ 2 AZ, S3 (durability 11 nines) | Redshift RA3 Multi-AZ, dashboard หลัง ALB + Auto Scaling |
| **Resiliency** | Automated snapshot, S3 Versioning, raw data แยกจาก DW (rebuild ได้เสมอด้วยการรัน ETL ใหม่) | Cross-region snapshot copy, S3 Cross-Region Replication |
| **Cost** | node เล็กสุด, ไม่มี NAT GW, Pause cluster เมื่อไม่ใช้, ลบทรัพยากรหลังส่ง | Redshift Serverless (จ่ายตามใช้), Reserved Instances, S3 lifecycle → Glacier |

---

## Step 8 — Cost Estimate

- [ ] ใช้ **AWS Pricing Calculator** (calculator.aws) ใส่: Redshift (node × ชั่วโมง/เดือน), S3 (GB + requests), EC2, CloudWatch/SNS
- [ ] ทำ 2 scenario: (a) แบบที่ทำจริง เปิดเฉพาะเวลาใช้ (b) แบบ production เปิด 24/7
- [ ] Export PDF/link → `docs/cost-estimate.pdf` และแคปใส่เล่ม (รุ่นพี่มีรูป 5.1–5.2 แบบนี้)

---

## Step 9 — รูปเล่มรายงาน (ใช้โครงตามรุ่นพี่)

| บท | เนื้อหา (ปรับเป็น DW) |
|---|---|
| **บทที่ 1 บทนำ** | ที่มาของปัญหา (บริษัท streaming มี log มหาศาลแต่ตอบคำถาม business ไม่ได้), วัตถุประสงค์, ขอบเขต (data, KPI, AWS services), ข้อจำกัด (Learner Lab), ประโยชน์ |
| **บทที่ 2 ทฤษฎี/เทคโนโลยี** | OLTP vs OLAP, Data Warehouse, Star Schema, ETL/ELT, Columnar storage, MPP · อธิบาย S3, Redshift, VPC, IAM, EC2, CloudWatch **พร้อมเหตุผลว่าทำไมเลือก** (อย่าเขียนแค่นิยาม) |
| **บทที่ 3 การออกแบบ** | Business questions, Architecture diagram, Network design (subnet/SG table), Data flow, ERD, Data dictionary, Redshift DIST/SORT design + เหตุผล |
| **บทที่ 4 ผลการดำเนินงาน** | Screenshot แต่ละ service (S3, VPC, SG, Redshift, EC2, CloudWatch), ผล COPY/ETL, DQ result, ผล KPI + การตีความ business, Dashboard |
| **บทที่ 5 สรุป** | สรุป, ปัญหา/อุปสรรค (เช่น song match rate ต่ำ, ข้อจำกัด Lab), ข้อจำกัดระบบ, **Cost estimate**, **Ideal architecture ไม่คำนึงค่าใช้จ่าย**, 4 pillars table |
| ภาคผนวก | Link GitHub, SQL หลัก, วิธีรัน |

---

## Step 10 — Cleanup (สำคัญมาก)

- [ ] ระหว่างพัฒนา: จบวันให้ **Pause** Redshift cluster + Stop EC2
- [ ] ⚠️ อย่าลืม: Learner Lab หมด session ≠ Redshift หยุด
- [ ] หลังส่งงาน/สอบ demo: Delete Redshift (snapshot สุดท้ายเก็บได้ถ้าต้องการ), Terminate EC2, ลบ VPC endpoint, ลบ S3 bucket
- [ ] เช็ค budget ที่เหลือในหน้า Learner Lab เป็นระยะ

---

## Timeline แนะนำ (ปรับตาม deadline)

| สัปดาห์ | งาน | Output |
|---|---|---|
| 1 | Step 1–3 | repo พร้อม, business questions, data profiling notebook |
| 2 | Step 4–5 | ERD, architecture diagram, SQL DDL |
| 3 | Step 6.1–6.5 | data อยู่บน Redshift ครบ |
| 4 | Step 6.6–6.8 | DQ, KPI, dashboard, monitoring |
| 5 | Step 7–9 | cost estimate, รูปเล่ม, README final |
| ก่อน demo | ซ้อม demo + Step 10 หลังจบ | — |

## แบ่งงาน 5–6 คน (ตัวอย่าง)

| Role | ความรับผิดชอบ |
|---|---|
| Infra/Network | VPC, SG, Redshift, EC2, diagram |
| Data Modeler | ERD, DDL, DIST/SORT design |
| ETL | COPY, transform SQL, `etl.py` |
| Analytics | KPI queries, dashboard |
| QA + Docs | DQ checks, screenshots, README |
| Report/PM | รูปเล่ม, cost estimate, timeline |

---

## Final Checklist ก่อนส่ง

- [ ] GitHub: README อัปเดต (มี architecture + วิธีรัน), ไม่มี secret, ทุกคนมี commit
- [ ] Diagram: architecture (ระดับ network), data flow, ERD, ideal architecture
- [ ] AWS: screenshot ทุก service + หลักฐานว่า query/ dashboard รันได้จริง
- [ ] DQ results + song match rate
- [ ] KPI ≥ 3 ข้อ พร้อมการตีความทาง business (ไม่ใช่แค่แปะผล SQL)
- [ ] 4 pillars table + cost estimate
- [ ] รูปเล่ม 5 บท
- [ ] Cleanup ทรัพยากรแล้ว
