# Innovate Inc. — Cloud Architecture Design

**Author:** [your name]
**Date:** 2026-07-28
**Cloud provider:** AWS
**Status:** Draft — see [`communications/`](communications/) for the clarifying-questions message sent before this design and the delivery summary sent after.

## Contents

1. [Cloud Environment Structure](#1-cloud-environment-structure)
2. [Network Design](#2-network-design)
3. [Compute Platform (EKS)](#3-compute-platform-eks)
4. [Database](#4-database)
5. [CI/CD](#5-cicd)
6. [Cost Considerations](#6-cost-considerations)
7. [Assumptions](#7-assumptions)

---

## 1. Cloud Environment Structure

**Recommendation: 7 AWS accounts total, under one AWS Organization, provisioned via Control Tower + Terraform.**

| # | Account | Purpose |
|---|---|---|
| 1 | Management | Org root — consolidated billing, SCPs. No workloads. |
| 2 | Log Archive | Immutable CloudTrail / VPC Flow Log destination (S3 + Object Lock). |
| 3 | Security/Audit | GuardDuty, Security Hub, IAM Access Analyzer aggregation. |
| 4 | Shared Services | Central ECR, Route 53 hosted zones. |
| 5 | Dev | Development workloads — fastest iteration; more latitude to diverge from Prod's exact sizing/config. |
| 6 | Staging | Pre-prod — same architecture as Prod, held close to its exact config (not just scaled down), so it's a valid pre-release test bed. |
| 7 | Production | Customer-facing workloads + production database only. |

3 platform/governance accounts (1–3) + 1 shared-tooling account (4) + 3 environment accounts (5–7) = **7 accounts**. No other accounts are recommended at launch.

**Why full per-environment separation:** an AWS account is a hard security boundary that no in-account IAM policy fully replicates — a mistake or leaked credential in Dev cannot reach Staging or Prod. This is AWS's standard reference pattern; it's affordable here specifically because provisioning is templated in Terraform, so isolation isn't traded for setup effort. Cost is instead controlled *within* each non-prod account (§6).

- **Isolation:** hard account boundaries per environment; Production restricted to break-glass human access, all changes via CI/CD.
- **Billing:** consolidated invoice; AWS Budgets + Cost Anomaly Detection per account, so a runaway Dev cost is visible immediately, not buried in the total.
- **Management:** SCPs enforce guardrails (no root use, mandatory CloudTrail) at the account level; AWS IAM Identity Center (SSO) gives engineers scoped federated access instead of per-account IAM users.

---

## 2. Network Design

**3 VPCs total — one each in Dev, Staging, and Production** (the only accounts running workloads; Management, Log Archive, Security/Audit, and Shared Services don't need a VPC). All three share the **same topology** — this is deliberate, so Staging validates what will actually run in Prod rather than something shaped differently. Each VPC spans 3 Availability Zones, with non-overlapping CIDRs across the three so they can be peered/Transit-Gatewayed later without renumbering. Standard 3-tier subnets, repeated per AZ:

- **Public** — ALB + a single shared NAT Gateway in all three environments at launch (cost-optimized). **Production alone** is the environment eligible to graduate to per-AZ NAT Gateways for outbound HA once justified (§7) — Dev/Staging never carry real user traffic, so that redundancy isn't worth ~3x the cost there, now or later.
- **Private app** — EKS nodes/pods; outbound only via NAT or VPC endpoints.
- **Private data** — Aurora only, no internet route in or out.

![Innovate Inc. AWS production architecture — request path from users through Route 53, CloudFront, WAF, and the ALB into an EKS cluster (frontend pods, backend pods, KEDA autoscaling, Karpenter node autoscaling with a min=5 floor), through to an isolated Aurora PostgreSQL Serverless v2 database, alongside security/platform services (Secrets Manager, KMS, ECR, GuardDuty, Security Hub) and a GitOps CI/CD pipeline (GitHub Actions → ECR → Argo CD → EKS)](architecture-diagram.svg)

**Securing the network:**
- CloudFront + AWS WAF (managed rules) + Shield Standard at the edge; TLS via ACM everywhere.
- Least-privilege Security Groups (ALB → app → DB only, nothing else); the database is never publicly reachable.
- VPC Endpoints for S3/ECR/Secrets Manager/KMS — internal AWS traffic never crosses the public internet.
- VPC Flow Logs → Log Archive account; GuardDuty + Security Hub enabled org-wide.
- EKS API endpoint private/restricted; secrets live in Secrets Manager via the CSI driver — never in images or manifests.

---

## 3. Compute Platform (EKS)

**Why EKS:** managed control plane, IRSA for scoped per-pod AWS permissions, and a scaling path from hundreds to millions of users without a re-platform.

**How the app runs on it:** frontend and backend are each a **Deployment** (replica-managed, rolling updates) fronted by a **Service**; a single **Ingress**, reconciled by the **AWS Load Balancer Controller**, provisions and points the ALB at both Services (`/api` → backend, `/` → frontend). Runtime config comes from **ConfigMaps**, secrets from Secrets Manager via the CSI driver (§2) — nothing sensitive in the image or the manifest. One Helm chart (or Kustomize base) per service, with per-environment overlays (Dev/Staging/Prod) for replica counts and resource sizing.

**Node groups & scaling:**
- Small on-demand **system node group** for platform add-ons (CoreDNS, Karpenter, Argo CD, KEDA).
- **Application node group:** `min=5` floor, no fixed max, On-Demand + Spot. **Karpenter** provisions/removes nodes above the floor based on real (`Pending`-pod) demand — this is what carries growth from hundreds to millions of users over time.
- **KEDA** scales the backend on request-rate (a faster-reacting signal than CPU for an I/O-bound Flask app); the frontend uses standard HPA. At today's traffic, the `min=5` floor runs well under capacity, so its spare headroom absorbs a sudden burst without waiting on Karpenter — no separate buffer needed yet. Revisit (e.g. a small low-priority "pause pod" reserve) once `min` gets tuned down closer to real steady-state usage and that natural slack disappears.
- SQS + KEDA is reserved for future async/background work only — not the synchronous API path (a queue doesn't fit a request/response call a React client is waiting on).
- ResourceQuotas/LimitRanges per namespace, Pod Disruption Budgets, pods spread across all 3 AZs.

**Containerization:**
- Multi-stage Dockerfiles, minimal non-root images; one **ECR** repo per service, immutable SHA tags, scan-on-push.
- **GitOps:** Argo CD reconciles cluster state from git (Helm/Kustomize per environment) — audit trail + `git revert` rollback, no CI running `kubectl apply` directly.
- Argo Rollouts for canary/blue-green once traffic justifies it.

---

## 4. Database

**Amazon Aurora PostgreSQL, Serverless v2.** Wire-compatible with Postgres; storage auto-scales to 128TB with up to 15 read replicas, so the same engine carries the app from launch to millions of users with no migration. Serverless v2 scales ACUs to 0 when idle (matching today's low cost) and up automatically with load; it's production-grade (GA since 2022) and supports Aurora Global Database if cross-region DR is needed later.

- **HA:** Aurora's storage layer is already replicated across 3 AZs by design, independent of which instance is primary — so failover is really about the compute/writer endpoint. With at least one reader in a different AZ from the writer, an instance failure, AZ outage, or planned maintenance promotes that reader to writer automatically, typically in under 30 seconds, with no data loss (writes are synchronously durable to the storage layer, not dependent on the reader). The app reconnects via the cluster's static **writer endpoint** DNS name, which Aurora re-points automatically — no manual failover steps or connection-string changes. As read traffic grows, add read replicas (doesn't affect write availability) behind the **reader endpoint**; consider **RDS Proxy** later to pool connections and smooth reconnects during failover once concurrent connection count justifies it.
- **Backups:** continuous, incremental backups to S3 run in the background with no performance impact on the live database — no backup window, no locking, unlike a traditional `pg_dump`. **Point-in-time recovery** restores to any second within the 35-day retention window, not just daily snapshot boundaries — this matters for recovering from a bad migration or application bug that isn't caught immediately. Manual snapshots are taken and tagged before any risky schema migration, retained independently of the rolling PITR window so they don't auto-expire. As a lower-cost interim step before full Aurora Global Database (below), automated snapshots can also be copied cross-region on a schedule — cheaper than a live secondary cluster, at the cost of a coarser RPO (last snapshot, not near-real-time).
- **DR:** Aurora Global Database as the documented future phase — a secondary, read-only cluster in a second region with typically sub-1-second replication lag, promotable to primary in under a minute during a full region outage, paired with Route 53 failover routing to redirect traffic. This isn't just a database change: a real region failover also needs an EKS cluster and app already deployed in the secondary region, so this upgrade phase includes compute, not the database alone. Two separate health checks, not one: the **ALB/Kubernetes liveness probe** stays shallow (HTTP-only, no DB call) so a shared DB blip doesn't pull every pod out of rotation at once; **Route 53's health check** separately polls a deeper `/readyz` endpoint that does verify DB connectivity, since only the regional-failover decision should weigh that. Not needed at MVP scale (§7).
- **Security:** KMS encryption at rest using a customer-managed key (not the AWS-managed default, for auditable key rotation/usage); in-transit encryption via Postgres-native TLS (`sslmode=require`, Aurora's own RDS-issued certificate — independent of the ACM certs used at the ALB/CloudFront edge, see §2). Credentials live in Secrets Manager with automatic rotation; only the backend's IRSA role can read them — the frontend has no path to the database at all.
- **Restore drills:** quarterly, restore the latest automated snapshot into an isolated scratch environment, run schema/row-count validation, and record actual time-to-restore against the target RTO — an untested backup isn't a verified one, and this is also how the DR runbook stays accurate instead of aspirational.

---

## 5. CI/CD

PR → GitHub Actions (lint/test/build/scan) → push to ECR (SHA-tagged) → CI commits the new image tag into the Helm chart's `values.yaml` in the GitOps repo → **Argo CD detects that git commit** (not the ECR push — it has no visibility into ECR) and syncs (auto to Dev/Staging, approval-gated to Prod) → rollback via `git revert`.

---

## 6. Cost Considerations

Cost-effectiveness isn't a single line item — it's a constraint threaded through every section above (Aurora scale-to-0, Karpenter's reactive `min` floor, no standing burst buffer, single NAT). Summarized:

- **Accounts are free; resources aren't.** The 7-account structure (§1) costs nothing by itself — AWS Organizations accounts have no fee — so isolation didn't have to be traded against cost. What actually costs money (compute, NAT, database) is sized per environment, not per account.
- Aurora Serverless v2 + Karpenter/Spot + scale-to-0 keep idle cost low at today's traffic, scaling up automatically only as real usage grows (§3, §4).
- Dev and Staging share Production's architecture (§2) but are sized down — smaller Karpenter `min` floor, lower Aurora ACU ceiling, and (unlike Production) permanently on a single NAT Gateway since they never carry customer traffic — real isolation without paying production-level cost in non-prod.
- Single shared NAT Gateway in Production at launch (vs. per-AZ) — roughly 3x cheaper, with a documented small availability trade-off and upgrade path (§7).

---

## 7. Assumptions

Made explicit in lieu of a live requirements session; also sent as direct questions to the client (see [`communications/01-clarifying-questions.md`](communications/01-clarifying-questions.md)).

| Assumption | If wrong |
|---|---|
| No named compliance regime (HIPAA/PCI) beyond general data protection | Adds dedicated controls (BAA-eligible services, stricter log retention) |
| Single region acceptable at launch; cross-region DR is a later phase. Deferred specifically because it roughly doubles Production's footprint (a second EKS cluster, a second Aurora replica, cross-region replication/data-transfer cost) for protection against a failure mode — full region outage — that's rare relative to the cost of running it continuously | Would need Aurora Global Database + a second EKS cluster + cross-region ECR/Secrets replication now instead of as a later upgrade |
| No existing AWS footprint to integrate with | Existing resources would need import into the Organization |
| Budget favors reactive scaling (Karpenter/KEDA/Serverless v2), relying on the `min=5` floor's existing slack for burst absorption rather than a dedicated standing buffer | A known growth event (e.g. a launch date) should be pre-scaled for directly instead; once `min` is tuned tighter to real usage, a small pause-pod buffer should be reintroduced |
| Single shared NAT Gateway acceptable in Production at launch | Move Production to per-AZ NAT Gateways if outbound HA is a hard requirement from day one (Dev/Staging stay single-NAT regardless) |

---

*See [`communications/`](communications/) for the clarifying-questions message sent before this design and the summary sent on delivery.*
