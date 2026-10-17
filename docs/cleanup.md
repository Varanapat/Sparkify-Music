# Cleanup Runbook — Learner Lab

> GUIDELINE Step 10 · For the team member whose Learner Lab hosts the project.
> Part 1–2 are used **every session**. Part 3 is done **once**, only after the demo and grading are finished.
> Why it matters: Redshift costs **$0.543/hour** and the Learner Lab does **not** pause it for you
> (see [`cost_estimate.md`](cost_estimate.md) §5).

## 0. Before You Build: Tag Everything

When creating each resource, add the tag **`Project = sparkify`**.
At cleanup time, **Resource Groups & Tag Editor** (available in Learner Lab) can then list every remaining resource in one search.

Suggested names (use them everywhere so screenshots, scripts and this runbook match):

| Resource | Name |
|---|---|
| S3 bucket | `sparkify-raw-<group>` |
| VPC | `sparkify-vpc` |
| Security groups | `sg-app`, `sg-redshift` |
| Redshift subnet group | `sparkify-redshift-subnets` |
| Redshift cluster | `sparkify-dwh` |
| EC2 instance | `sparkify-app` |
| SNS topic | `sparkify-alerts` |
| CloudWatch alarms | `sparkify-redshift-cpu-high`, `sparkify-redshift-disk-high`, `sparkify-redshift-health` |

## 1. Start of Every Session

- [ ] Start Lab → wait for the green dot → note **"Used $X of $50"** in the spend log ([`cost_estimate.md`](cost_estimate.md) §6)
- [ ] EC2 starts automatically (Lab behaviour). If you do **not** need it today: EC2 → Instances → *Stop*
- [ ] Need SQL today? Redshift → Clusters → `sparkify-dwh` → Actions → **Resume** (takes a few minutes)
- [ ] Need Metabase? Use the **new public IP** of `sparkify-app`. Update `sg-app` port 3000 if your own IP changed

## 2. End of Every Session (do not skip)

- [ ] Redshift → Clusters → `sparkify-dwh` → Actions → **Pause** → status becomes *Paused*
- [ ] EC2 → Instances → `sparkify-app` → **Stop** (the Lab would stop it anyway, but stopping now saves budget)
- [ ] Note **"Used $X of $50"** and the Redshift hours used today in the spend log
- [ ] End Lab

CloudShell alternative for pause / resume:

```bash
aws redshift pause-cluster --cluster-identifier sparkify-dwh
```

```bash
aws redshift resume-cluster --cluster-identifier sparkify-dwh
```

```bash
aws redshift describe-clusters --cluster-identifier sparkify-dwh --query "Clusters[0].ClusterStatus"
```

## 3. Final Teardown (after demo and grading only)

> ⚠️ **Deleting is permanent.** Do this only after the group confirms the demo is finished, the grade is in,
> and every screenshot / export below has been saved.

### 3.1 Collect evidence first

- [ ] All screenshots for report chapter 4 are in `screenshots/` (checklist: "Proof" column in [`well_architected.md`](well_architected.md))
- [ ] KPI query results exported (CSV or screenshots) and Metabase dashboard screenshots saved
- [ ] ETL log and data-quality results saved
- [ ] Final **"Used $X of $50"** noted, for the actual-cost table in the report

### 3.2 Delete in this order

The order follows dependencies. For example, a VPC cannot be deleted while a Redshift cluster or EC2 instance still uses its subnets.

| # | Service | Action | Notes |
|---|---|---|---|
| 1 | CloudWatch | Alarms → select the 3 `sparkify-*` alarms → *Delete* | |
| 2 | SNS | Topics → `sparkify-alerts` → *Delete* (subscriptions are removed with it) | |
| 3 | Redshift | Clusters → `sparkify-dwh` → Actions → *Delete* → **untick "Create final snapshot"** | A paused cluster can be deleted directly. Takes several minutes |
| 4 | Redshift | Snapshots → delete any **manual** snapshots | Automated snapshots are removed with the cluster |
| 5 | Redshift | Configurations → Subnet groups → `sparkify-redshift-subnets` → *Delete* | Only after step 3 has finished |
| 6 | EC2 | Instances → `sparkify-app` → *Terminate* | Root EBS volume is deleted with it (check step 7) |
| 7 | EC2 | Volumes: none left · Elastic IPs: **release** any (an unattached EIP is charged) | |
| 8 | VPC | Security groups → delete **`sg-redshift` first**, then `sg-app` | `sg-redshift` references `sg-app` |
| 9 | VPC | Endpoints → S3 gateway endpoint → *Delete* | |
| 10 | VPC | Your VPCs → `sparkify-vpc` → *Delete VPC* | Also deletes its subnets, route tables and internet gateway |
| 11 | S3 | `sparkify-raw-<group>` → **Empty** (removes all object **versions**, because Versioning is on) → *Delete* | Raw data can be downloaded again with `scripts/download_dataset.py` |
| 12 | Secrets Manager | Delete any `sparkify` / Redshift admin secret still listed | Only if you chose "Manage admin credentials in Secrets Manager" |
| 13 | CloudWatch Logs | Delete any `sparkify` / Redshift log groups | Only if logging was enabled |

### 3.3 Verify nothing is left

- [ ] **Resource Groups & Tag Editor** → Tag Editor → Region `us-east-1`, Resource types *All supported*, Tag `Project = sparkify` → **0 results**
- [ ] Redshift: no clusters · EC2: no running/stopped instances, no volumes, no Elastic IPs · VPC: only the default VPC · S3: bucket gone
- [ ] Next day: **"Used $X"** on the Lab page has **not increased**

Screenshot the empty Redshift / EC2 / S3 pages. They prove cleanup in the report (Cost pillar).

### 3.4 Local files

- [ ] Delete `config/dwh.cfg` (contains the Redshift password). It is gitignored, but it should not stay on laptops
- [ ] Check the GitHub repo once more: no passwords, keys or `dwh.cfg` in any commit
