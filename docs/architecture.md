# AWS Architecture — Sparkify Data Warehouse

> GUIDELINE Step 5 · Design only. Nothing has been created in AWS yet.
> Diagrams: [`docs/architecture.drawio`](architecture.drawio). The file has 3 pages:
> **1 As-built architecture** · **2 Data flow** · **3 Ideal architecture** (File → Export as → PNG for each page).

## 1. Services and Why We Chose Them

| Service | Role in the project | Why this service (vs alternatives) |
|---|---|---|
| **Amazon S3** | Raw data storage (`song_data`, `log_data`, JSONPath) | Cheap and durable (11 nines). Redshift `COPY` reads it in parallel. Raw data stays separate from the warehouse, so the DW can be rebuilt at any time |
| **Amazon Redshift** (provisioned, 1 node) | Data warehouse (staging + star schema) | Columnar MPP database built for OLAP and star-schema joins. Provisioned can be **paused** when idle and sits inside our own VPC subnets, so the network design shows clearly. Serverless was not chosen |
| **Amazon VPC** | Private network, 2 AZs, public/private subnets | Isolates the warehouse from the internet. A Redshift subnet group needs subnets in the VPC |
| **S3 Gateway VPC Endpoint** | Private path from the VPC to S3 | Free. Redshift `COPY` traffic never leaves the AWS network, so no NAT Gateway is needed |
| **Amazon EC2** | Runs the Python ETL (`etl.py`) and the Metabase dashboard (Docker) | One small instance does both jobs. Metabase is free and open source (QuickSight has a monthly per-user fee) |
| **AWS Systems Manager — Session Manager** | Shell access to EC2 | No SSH key pair and **no port 22** open. Every session is logged |
| **AWS IAM** | Roles for Redshift → S3 and EC2 → SSM | No access keys stored in code or on the server (least privilege) |
| **Amazon CloudWatch + SNS** | Alarms on Redshift CPU / disk → email | The team finds out about problems before the demo, not during it |

## 2. Network Design

### 2.1 VPC and subnets

| Resource | CIDR / value | AZ | Purpose |
|---|---|---|---|
| VPC `sparkify-vpc` | `10.0.0.0/16` | — | DNS hostnames + DNS resolution **enabled** (required by the endpoint and SSM) |
| Public subnet A | `10.0.1.0/24` | us-east-1a | EC2 (ETL + Metabase) |
| Public subnet B | `10.0.2.0/24` | us-east-1b | Empty (reserved for an ALB / standby in the ideal design) |
| Private subnet A | `10.0.11.0/24` | us-east-1a | Redshift node |
| Private subnet B | `10.0.12.0/24` | us-east-1b | Second subnet of the Redshift subnet group |
| Internet Gateway | — | — | Internet access for the public subnets only |
| NAT Gateway | **none** | — | Not needed: private subnets only talk to S3 (via the endpoint). Saves about $33/month per NAT |

> The "VPC and more" wizard uses its own default CIDRs (e.g. `10.0.0.0/20`). Change them to the values above
> so the screenshots match the report.

### 2.2 Route tables

| Route table | Destination | Target | Used by |
|---|---|---|---|
| `rtb-public` | `10.0.0.0/16` | local | Public A, Public B |
| | `0.0.0.0/0` | Internet Gateway | |
| | S3 prefix list (`pl-xxxx`) | S3 gateway endpoint | |
| `rtb-private` | `10.0.0.0/16` | local | Private A, Private B |
| | S3 prefix list (`pl-xxxx`) | S3 gateway endpoint | |

The private route table has **no** `0.0.0.0/0` route. Redshift cannot reach the internet, only S3.

### 2.3 Security Groups

| SG | Direction | Protocol / Port | Source / Destination | Why |
|---|---|---|---|---|
| `sg-app` (EC2) | Inbound | TCP 3000 | Each team member's public IP `/32` | Metabase is open to the group only |
| | Inbound | TCP 22 | **not opened** | Session Manager replaces SSH |
| | Outbound | All | `0.0.0.0/0` | pip / Docker image pulls, SSM agent (HTTPS 443), Redshift 5439 |
| `sg-redshift` | Inbound | TCP 5439 | **`sg-app`** (SG reference, not an IP) | Only the EC2 instance can connect to the warehouse |
| | Outbound | All | default | `COPY` from S3 through the endpoint |

Referencing `sg-app` instead of an IP range means the rule still works if the EC2 private IP changes. It also blocks every other host in the VPC.

## 3. Identity and Access (IAM)

| Role | Trusted by | Permissions | Used for |
|---|---|---|---|
| `RedshiftS3ReadRole` | `redshift.amazonaws.com` | `s3:GetObject` on `sparkify-raw-<group>/*`, `s3:ListBucket` on `sparkify-raw-<group>` | `COPY ... IAM_ROLE '<arn>'` |
| `EC2SSMRole` (instance profile) | `ec2.amazonaws.com` | AWS managed policy `AmazonSSMManagedInstanceCore` | Session Manager access |

Least-privilege policy for Redshift. It can only read our bucket, not every bucket (`AmazonS3ReadOnlyAccess` would allow every bucket):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::sparkify-raw-<group>" },
    { "Effect": "Allow", "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::sparkify-raw-<group>/*" }
  ]
}
```

Team members sign in with their own IAM users (or IAM Identity Center), not the root account.

## 4. Component Configuration

### 4.1 S3 bucket `sparkify-raw-<group>`
- Region `us-east-1` (same as Redshift, so there is no cross-region transfer cost)
- Block **all** public access · Default encryption SSE-S3 · Versioning **on**

### 4.2 Redshift cluster
| Setting | Value | Reason |
|---|---|---|
| Node type / count | Smallest node type available (confirmed in Step 6.3) × **1** | Dataset is tiny (~7.5 MB). Keeps cost low |
| Subnet group | Private A + Private B | Spans 2 AZs (required). Allows relocation |
| Publicly accessible | **No** | No public IP. Reachable only inside the VPC |
| Enhanced VPC Routing | **On** | Forces `COPY` traffic through our VPC → S3 endpoint, so it follows our routes and SGs |
| Encryption at rest | **On** | Security pillar |
| Automated snapshots | Retention 1 day | Resiliency pillar |
| Admin password | Stored in `config/dwh.cfg` (gitignored), or the console option "Manage admin credentials in AWS Secrets Manager" | Never committed to Git |
| Pause / resume | Pause when not working | Cost pillar |

### 4.3 EC2 instance
| Setting | Value |
|---|---|
| AMI / type | Amazon Linux 2023 (SSM Agent pre-installed) · `t3.small` (Metabase needs about 1–2 GB RAM) |
| Subnet | Public A, auto-assign public IP (needed to reach SSM and package repos without a NAT) |
| Key pair | **None** (Session Manager only) |
| IAM instance profile | `EC2SSMRole` |
| Software | `python3-pip`, `psycopg2-binary`, `boto3`, `docker` → `metabase/metabase` on port 3000 |

Access options:
- **Shell:** `aws ssm start-session --target <instance-id>` or Console → EC2 → Connect → Session Manager
- **Metabase (option, even safer):** SSM port forwarding (`AWS-StartPortForwardingSession`, port 3000). With this, `sg-app` needs **no inbound rules at all**. The trade-off is that every viewer needs the AWS CLI.

## 5. Monitoring

| Alarm | Metric (namespace `AWS/Redshift`) | Condition | Action |
|---|---|---|---|
| `sparkify-redshift-cpu-high` | `CPUUtilization` | > 80% for 2 × 5 min | SNS `sparkify-alerts` → team email |
| `sparkify-redshift-disk-high` | `PercentageDiskSpaceUsed` | > 80% for 1 × 5 min | SNS `sparkify-alerts` → team email |
| `sparkify-redshift-health` | `HealthStatus` | < 1 for 1 × 5 min | SNS `sparkify-alerts` → team email |

Evidence for the report: an alarm in `ALARM` state (it can be forced with `aws cloudwatch set-alarm-state`) plus a screenshot of the email it sends.

## 6. Traffic Flows (matches page 1 of the diagram)

| # | From → To | Port / path | Controlled by |
|---|---|---|---|
| 1 | Team member → Internet Gateway → EC2 | TCP 3000 (Metabase) | `sg-app` inbound, IP `/32` only |
| 2 | Developer → Systems Manager → EC2 | HTTPS via SSM (no inbound port) | IAM + `EC2SSMRole` |
| 3 | EC2 → Redshift | TCP 5439 | `sg-redshift` inbound from `sg-app` |
| 4 | Redshift → S3 endpoint → S3 | HTTPS inside AWS network | Enhanced VPC Routing + `rtb-private` + `RedshiftS3ReadRole` |
| 5 | Redshift → CloudWatch → SNS → email | AWS-managed | Alarms in §5 |

## 7. Ideal Architecture (cost not considered — for report chapter 5)

Page 3 of the diagram. What changes compared with the as-built design, and why:

| Area | As-built (project) | Ideal (production) | Pillar |
|---|---|---|---|
| Ingestion | Batch JSON files copied to S3 | **Kinesis Data Firehose** streams app events to S3 in near real time | Performance |
| Data lake | One raw bucket | S3 zones `raw / processed / curated`, **Glue Data Catalog**, lifecycle → **S3 Glacier** | Cost, Operations |
| Orchestration | `etl.py` run by hand | **EventBridge** schedule → **Step Functions** (COPY → transform → DQ, with retries) | Reliability |
| Warehouse | Redshift 1 node, single AZ | **Redshift RA3 multi-node, Multi-AZ**, Redshift Spectrum for cold data in S3 | Availability, Performance |
| Dashboard | Metabase on one EC2, HTTP 3000 | Metabase on **ECS Fargate in 2 AZs behind an ALB (HTTPS + ACM + AWS WAF)**, metadata on RDS Multi-AZ, or **QuickSight** | Availability, Security |
| Network | No NAT, 1 EC2 in a public subnet | Workloads in private subnets, **NAT Gateway per AZ**, interface VPC endpoints (Secrets Manager, Logs) | Security, Availability |
| Secrets & keys | Password in local `dwh.cfg` | **Secrets Manager** (auto-rotation), **KMS customer-managed keys** | Security |
| Audit & threats | — | **CloudTrail** (all regions), **GuardDuty** | Security |
| Disaster recovery | Automated snapshots, 1 day | **Cross-region snapshot copy** + **S3 Cross-Region Replication** to us-west-2 | Resiliency |
| Monitoring | 3 CloudWatch alarms | CloudWatch dashboards + alarms on ETL failures and query queue time | Operations |
