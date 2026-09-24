# CloudCart — Kubernetes & Amazon EKS Workshop

CloudCart is a small e-commerce app made of **seven microservices** behind a
responsive, multi-page storefront (catalogue, login/signup, and a live
dashboard). It walks one journey, step by step:

> **Docker on your laptop → Amazon ECR → Amazon EKS → LoadBalancer → DynamoDB**

Run it locally first, see how the pieces talk, then move the **same containers**
to AWS.

---

## What you'll change (that's it)

To deploy end to end you only edit **one file**:
`environments/dev/us-east-1/terraform.tfvars`. Set your region, cluster name,
node sizes, and tags there. Everything else has sensible defaults.

For CI (GitHub Actions), add two repository secrets: `AWS_ACCESS_KEY_ID` and
`AWS_SECRET_ACCESS_KEY`.

---

## The app

```
browser ──▶ frontend ──▶ product / inventory / cart / order / payment / auth
                                     order ──▶ inventory + payment
```

The frontend is a small multi-page storefront, all served on different paths
by the same `frontend` service:

| Path | Page |
|------|------|
| `/` | Home — a live architecture strip (each service pinged in your browser), search + category filters, sort, wishlist, a quick-view modal, cart drawer, and a checkout flow that visualizes the cart → inventory → payment → confirmed call sequence in real time |
| `/login` | Log in (JWT issued by `auth-service`), with a show/hide password toggle |
| `/signup` | Create an account, with a live password-strength meter |
| `/dashboard` | Protected — animated KPI cards, a live cluster-health panel that pings all six services with response times, interactive charts (revenue, inventory, category mix), a top-products leaderboard, and a recent-orders table, all auto-refreshing |

Every page shares one light/dark theme toggle (top right) — dark mode leans into
a "control room" look that suits the dashboard especially well. All of this is
plain HTML/CSS/JS with zero build step, so editing `frontend/public/*` and
refreshing the browser is all it takes to see a change.

| Service | Job |
|---------|-----|
| `frontend` | Web UI (4 pages) + proxies `/api/*` to the backends |
| `product-service` | Product catalogue (24 products across 8 categories) |
| `inventory-service` | Stock levels |
| `cart-service` | Shopping cart |
| `order-service` | Places orders (calls inventory + payment) |
| `payment-service` | Mock payment |
| `auth-service` | Signup / login, issues JWTs, bcrypt-hashed passwords |

Tiny Node.js/Express apps. They start in **in-memory mode**
(`USE_DYNAMODB=false`), so you need **no AWS account** to run them locally.

---

## Prerequisites

- Docker (Docker Desktop, or `colima start` on macOS)
- AWS CLI v2 with an **IAM user** configured (not root — see below)
- `kubectl`
- `eksctl` (manual path) and/or Terraform ≥ 1.5 (infra-as-code path)

### Credentials rule (important)
**Do not use the AWS root account for daily work.** Create an IAM admin user once:

1. Root → **IAM → Users → create** an admin user (e.g. `cloudcart-admin`), attach **AdministratorAccess**, enable **MFA**.
2. Create an **access key** for that user.
3. `aws configure` → paste the key, region `us-east-1`.
4. Check: `aws sts get-caller-identity` shows the IAM user (not root).

---

## Step 1 — Run locally with Docker

```bash
docker compose up --build      # build + start all seven services
# open http://localhost:8080
docker compose ps              # clean names: frontend, cart-service, ...
docker compose down
```

**Why this matters:** Compose gives each service a DNS name (e.g.
`http://inventory-service:3000`). **Kubernetes works the same way** — that's the
bridge to the next steps.

---

## Step 2 — Push images to Amazon ECR

```bash
export AWS_REGION=us-east-1
./scripts/push-to-ecr.sh       # builds + pushes all seven images
```

---

## Step 3 — Create the EKS cluster

Pick ONE path.

### Path A — eksctl (fast, single command)
```bash
eksctl create cluster \
  --name cloudcart --region us-east-1 --version 1.31 \
  --managed --node-type t3.medium \
  --nodes 2 --nodes-min 2 --nodes-max 4 --with-oidc
```
Takes ~15–20 min and configures `kubectl` for you. Then `kubectl get nodes`.

### Path B — Terraform (repeatable, infra as code)
Builds VPC + EKS + ECR + DynamoDB + KMS + Pod Identity together.

> **Do this once first** — the S3 state bucket in `backend.tf` must exist before
> `terraform init`, or init fails:
> ```bash
> aws s3 mb s3://ajay-eks-demo-terraform-bucket --region us-east-1
> aws s3api put-bucket-versioning --bucket ajay-eks-demo-terraform-bucket \
>   --versioning-configuration Status=Enabled
> ```

```bash
cd environments/dev/us-east-1
# edit terraform.tfvars (region, sizes, tags)
terraform init
terraform plan     # optional but recommended: catches auth/quota issues fast
terraform apply
terraform output -raw configure_kubectl   # run the printed command
```

> Tip: use the **AWS Console only to *view*** the cluster (nodes, node group).
> Creating clusters through the console wizard live is slow and error-prone.

---

## Step 4 — Deploy CloudCart to EKS

```bash
export AWS_REGION=us-east-1
./scripts/render-aws-manifests.sh          # fill in <ACCOUNT_ID>/<REGION>
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/aws/
kubectl get pods -n cloudcart -w
```

Expose the frontend (a `LoadBalancer` Service creates an AWS load balancer):
```bash
kubectl get svc frontend -n cloudcart
# open http://<EXTERNAL-IP>
```

---

## Step 5 — Add DynamoDB (persistence, no stored keys)

Pods are disposable, so state lives in DynamoDB. Pods get access via **EKS Pod
Identity** — an IAM role, **no access keys in Kubernetes**. See
[eks/pod-identity.md](./eks/pod-identity.md). With Terraform this is created for you.

---

## Cleanup (avoid charges)

```bash
eksctl delete cluster --name cloudcart --region us-east-1        # Path A
cd environments/dev/us-east-1 && terraform destroy               # Path B
```

---

## Suggested session flow (1–2 hours)

| # | Topic | ~Time |
|---|-------|-------|
| 1 | Containers & Docker (Step 1) | 15 min |
| 2 | Why Kubernetes? Control plane vs nodes; Pod/Deployment/Service | 15 min |
| 3 | Push to ECR (Step 2) | 10 min |
| 4 | Create the cluster (Step 3) — **start early, it takes ~15 min** | 15–20 min |
| 5 | Deploy + LoadBalancer (Step 4) | 15 min |
| 6 | DynamoDB + Pod Identity (Step 5) | 15 min |

**Skip in a first session (optional/advanced):** EKS Auto Mode and EC2 bastions.

---

## Repository structure

```
frontend/                UI + API proxy
services/                5 backend microservices (each: Dockerfile + src)
k8s/
  namespace.yaml
  local/                 manifests for local Kubernetes (USE_DYNAMODB=false)
  aws/                   manifests for EKS (ECR images, DynamoDB, LoadBalancer)
scripts/                 push-to-ecr, create-dynamodb-tables, render-aws-manifests
eks/                     eksctl reference + pod-identity notes
modules/                 reusable Terraform: vpc, eks, ecr, dynamodb, kms, eks-pod-identity
environments/dev/us-east-1/   the ONE Terraform env you deploy (edit terraform.tfvars)
.github/workflows/       GitHub Actions Terraform pipeline
docker-compose.yml       run the whole app locally
DEPLOYMENT-GUIDE.md      detailed step-by-step runbook + troubleshooting
```

---

## Terraform, in short

- **Edit only** `environments/dev/us-east-1/terraform.tfvars`.
- Node group is the default. Tune it there:
  ```hcl
  instance_types = ["t3.medium"]
  desired_size   = 2
  min_size       = 2
  max_size       = 4
  ```
- **EKS Auto Mode** (AWS manages nodes) is a one-line switch: `enable_auto_mode = true`.
- **Grant other users kubectl access** via the `access_entries` map (optional).
- **DynamoDB tables** are defined in the `dynamodb_tables` map — add tables, GSIs,
  TTL, etc. without touching module code.
- Remote state uses the S3 bucket in `backend.tf`. **Create it once, before `terraform init`:**
  ```bash
  aws s3 mb s3://ajay-eks-demo-terraform-bucket --region us-east-1
  aws s3api put-bucket-versioning --bucket ajay-eks-demo-terraform-bucket \
    --versioning-configuration Status=Enabled
  ```

## Running it in GitHub Actions

The workflow `.github/workflows/dev_cloudcart_eks_workflow.yml` runs on the
GitHub-hosted `ubuntu-latest` runner — nothing to provision. For it to succeed:

1. Add repo secrets (Settings → Secrets and variables → Actions):
   `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (an IAM user with admin rights).
2. Create the S3 state bucket (command above) — Actions does not create it.
3. `plan` runs on push; **`apply` runs only on `main`** (or a manual run with
   `tf_apply=true`).

Note: infra applies (EKS) take ~15–20 minutes. Terraform builds the
**infrastructure**; deploying the **app** (push images to ECR + `kubectl apply`)
stays a separate manual step — see the guide.

Full detail and troubleshooting: **[DEPLOYMENT-GUIDE.md](./DEPLOYMENT-GUIDE.md)**.
