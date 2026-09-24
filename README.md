# CloudCart — Kubernetes & Amazon EKS Workshop

This repository is a hands-on demo that shows how to build and deploy a real
microservices application on **Amazon EKS** (managed Kubernetes). CloudCart is a
small e-commerce store composed of **seven microservices (one `frontend` + six
backend services)** that are containerized with Docker, published to Amazon ECR,
and run on an EKS cluster — exposed to the internet through a Kubernetes
LoadBalancer Service (an AWS ELB), with optional persistence in Amazon DynamoDB.
It's meant as a learning/workshop reference you can follow end to end: run it
locally first, see how the pieces talk, then move the **same containers** to AWS.

> **Docker on your laptop → Amazon ECR → Amazon EKS → LoadBalancer → DynamoDB**

### What you'll learn

- Containerizing a set of microservices with Docker and running them together via Docker Compose
- Publishing images to a private registry (Amazon ECR)
- Standing up a managed Kubernetes cluster with Amazon EKS (via eksctl or Terraform)
- Deploying microservices as Kubernetes Deployments + Services, and exposing the app with a LoadBalancer
- Adding managed persistence with Amazon DynamoDB, accessed securely via EKS Pod Identity (no static keys)
- Automating the whole infrastructure with Terraform and a GitHub Actions CI/CD pipeline

### Architecture at a glance

```
browser ──▶ frontend ──▶ product / inventory / cart / order / payment / auth
                                     order ──▶ inventory + payment
```

The `frontend` is the only public entry point (LoadBalancer); it proxies
`/api/*` calls to the six backend services, which talk to each other over the
cluster's internal network (ClusterIP) — the same service-discovery model
Docker Compose uses locally.

See the full end-to-end architecture (Terraform → GitHub Actions → EKS →
microservices → LoadBalancer → UI) in
[`diagrams/architecture-flow.svg`](./diagrams/architecture-flow.svg).

### Who is this for

Developers and DevOps learners who want a concrete, runnable example of the
container → registry → Kubernetes → load balancer → (optional) database flow on
AWS.

---

## Two ways through this workshop

- **Manual, step by step (recommended for learning)** — Steps 1–5: run locally
  with Docker → push images to ECR → create the cluster with eksctl → deploy the
  app WITHOUT DynamoDB (Demo A) → deploy WITH DynamoDB + Pod Identity (Demo B).
  You run a few small scripts; nothing to edit.
- **Automated with Terraform + GitHub Actions** — Step 6: Terraform provisions
  all infrastructure (VPC + EKS + ECR + DynamoDB + KMS + Pod Identity). Here you
  edit just one file, `environments/dev/us-east-1/terraform.tfvars` (region,
  cluster name, node sizes, tags), and for CI you add two repo secrets
  `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. You still deploy the app with
  the Step 4/5 manifests afterward.

New here? Follow Steps 1–5 in order. Want repeatable infra? Jump to Step 6.

---

## Contents

- [The app](#the-app)
- [Prerequisites](#prerequisites)
- [Step 1 — Run locally with Docker](#step-1--run-locally-with-docker)
- [Step 2 — Push images to Amazon ECR](#step-2--push-images-to-amazon-ecr)
- [Step 3 — Create the EKS cluster](#step-3--create-the-eks-cluster)
- [Step 4 — Demo A: Deploy WITHOUT DynamoDB (in-memory)](#step-4--demo-a-deploy-without-dynamodb-in-memory)
- [Step 5 — Demo B: Deploy WITH DynamoDB (persistence + Pod Identity)](#step-5--demo-b-deploy-with-dynamodb-persistence--pod-identity)
- [Step 6 — Automate everything: Terraform + GitHub Actions (CI/CD)](#step-6--automate-everything-terraform--github-actions-cicd)
- [Cleanup (avoid charges)](#cleanup-avoid-charges)
- [Repository structure](#repository-structure)
- [Terraform, in short](#terraform-in-short)
- [Bastion server setup (optional)](#bastion-server-setup-optional)

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

Before starting the workshop you need an AWS account and a set of CLI tools.
You can run everything two ways: **(a)** on your own laptop, or **(b)** on the
bastion server described later in this README (see Bastion server setup), which
comes with all tools pre-installed via userdata.

### Accounts & access
- An **AWS account**.
- An **IAM admin user** (not root — see below).
- **AWS CLI v2** configured (`aws configure`, region `us-east-1`).
- Verify with `aws sts get-caller-identity`.

### Local tools (if running from your laptop)

| Tool | Version |
|------|---------|
| Docker | Docker Desktop, or Colima on macOS |
| AWS CLI | v2 |
| kubectl | latest stable |
| eksctl | latest |
| Terraform | ≥ 1.5 |
| git | latest |

On the bastion these are all preinstalled.

### AWS resources to create once
- The **S3 state bucket** for Terraform remote state — created once before
  `terraform init` (see the command already in this README).
- *(optional)* The **bastion server**, for a private-cluster / clean-environment
  workflow (see Bastion server setup).

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

> **Optional — local Kubernetes:** to run the same containers on kind/minikube
> before touching AWS, apply `k8s/namespace.yaml` then `k8s/local/` (in-memory,
> `USE_DYNAMODB=false`). See `DEPLOYMENT-GUIDE.md` for the kind/minikube walkthrough.

---

## Step 2 — Push images to Amazon ECR

```bash
export AWS_REGION=us-east-1
./scripts/push-to-ecr.sh       # builds + pushes all seven images
```

> **Bastion/role permissions:** pushing needs ECR access. Attach
> `AmazonEC2ContainerRegistryFullAccess` to the instance role (it includes
> `ecr:GetAuthorizationToken`, push/pull, AND `ecr:CreateRepository` which the
> script uses to create the `cloudcart-*` repos). `AmazonEC2ContainerRegistryPowerUser`
> alone is NOT enough — it lacks `CreateRepository`.

---

## Step 3 — Create the EKS cluster

Create the cluster from the CLI — run this from your laptop or from the **bastion server** (see [Bastion server setup](#bastion-server-setup-optional)), both have `eksctl` installed.

```bash
eksctl create cluster \
  --name cloudcart --region us-east-1 --version 1.31 \
  --managed --node-type t3.medium \
  --nodes 1 --nodes-min 1 --nodes-max 2 --with-oidc
```
This uses a small 1-node group (min 1, max 2) to keep demo cost low. You can scale it up if pods don't fit — see the note below.

Takes ~15–20 min and configures `kubectl` for you.

> Tip: use the **AWS Console only to *view*** the cluster (nodes, node group).
> Creating clusters through the console wizard live is slow and error-prone.

Once the cluster is created you point `kubectl` at it with `aws eks update-kubeconfig`. eksctl usually does this automatically, but run it manually if you're on a different machine (e.g. the bastion) or your kubeconfig isn't set.

```bash
# Point kubectl at the cluster (this workshop's values)
aws eks update-kubeconfig --region us-east-1 --name cloudcart
```

```bash
# Generic form — substitute your own region and cluster name
aws eks update-kubeconfig --region <REGION> --name <CLUSTER_NAME>
```

Then `kubectl get nodes` to confirm the nodes are Ready. Next, pick a demo below.

### If pods stay Pending (not enough nodes)

A single `t3.medium` has limited CPU/memory and a capped number of pods it can run. When you deploy all services (each with its own replicas), some pods may sit in `Pending` with a "too many pods" or "Insufficient cpu/memory" event.

Check what's happening:

```bash
kubectl get pods -n cloudcart
kubectl describe pod <POD_NAME> -n cloudcart   # look at Events for the reason
```

Fix it by scaling the managed node group with the CLI — no need to recreate the cluster. First find the node group name, then scale:

```bash
# Find the node group name
eksctl get nodegroup --cluster cloudcart --region us-east-1

# Scale it up (e.g. to 2 nodes; must be within min/max)
eksctl scale nodegroup \
  --cluster cloudcart --region us-east-1 \
  --name <NODEGROUP_NAME> \
  --nodes 2 --nodes-min 1 --nodes-max 2
```

Generic form:

```bash
eksctl scale nodegroup --cluster <CLUSTER_NAME> --region <REGION> \
  --name <NODEGROUP_NAME> --nodes <DESIRED> --nodes-min <MIN> --nodes-max <MAX>
```

> `<DESIRED>` must be ≤ the node group's max. To go higher than the current max,
> raise `--nodes-max` in the same command. After the new node joins
> (`kubectl get nodes`), the Pending pods schedule automatically.

Alternatively, scale it in one line with the AWS CLI:

```bash
aws eks update-nodegroup-config --cluster-name cloudcart \
  --nodegroup-name <NODEGROUP_NAME> \
  --scaling-config minSize=1,maxSize=2,desiredSize=2 --region us-east-1
```

---

## Step 4 — Demo A: Deploy WITHOUT DynamoDB (in-memory)

The fastest way to show the whole app on a real cluster. Backends use
in-memory/seed data (`USE_DYNAMODB=false`) — no tables, no IAM, no Pod Identity.
Only the frontend is exposed, via a LoadBalancer ELB.

```bash
export AWS_REGION=us-east-1

# Render <ACCOUNT_ID>/<REGION> into the no-DynamoDB manifests
./scripts/render-aws-nodynamo-manifests.sh

# Deploy
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/aws-nodynamo/
kubectl get pods -n cloudcart -w
```

Then expose/open:
```bash
kubectl get svc frontend -n cloudcart
# wait for EXTERNAL-IP to become an ELB hostname, then open http://<EXTERNAL-IP>
```

> **Open the LoadBalancer ports:** the frontend Service provisions an AWS load
> balancer (`port: 80` → `targetPort: 3000`). Make sure its security group allows
> inbound **TCP 80** (HTTP) so the app opens in a browser, and **TCP 443** if you
> later add HTTPS/TLS. If you mapped the app to 8080, allow **TCP 8080** too. For
> a demo you can allow these from your IP (or `0.0.0.0/0`); lock them down for
> anything real.

> This reuses the **same images** pushed in Step 2. Only the frontend gets a
> public ELB — the backends stay internal (`ClusterIP`).

**Reset before the DynamoDB demo:** `kubectl delete -f k8s/aws-nodynamo/`
(keep the namespace).

---

## Step 5 — Demo B: Deploy WITH DynamoDB (persistence + Pod Identity)

Now add real persistence with DynamoDB. Pods get access via **EKS Pod
Identity** — a scoped IAM role, **no access keys in Kubernetes**.

```bash
export AWS_REGION=us-east-1

# 1) Create the 6 DynamoDB tables AND the CloudCartDynamoDBPolicy IAM policy (idempotent)
./scripts/create-dynamodb-tables.sh

# 2) Render <ACCOUNT_ID>/<REGION> into the DynamoDB manifests
./scripts/render-aws-manifests.sh

# 3) Deploy the app (references DynamoDB + a service account)
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/aws/
```

Then wire up Pod Identity:
```bash
# 4) Install the EKS Pod Identity agent (once per cluster)
eksctl create addon --cluster cloudcart --region us-east-1 --name eks-pod-identity-agent

# 5) Create the service account the pods use
kubectl apply -f k8s/aws/service-account.yaml

# 6) Associate the CloudCartDynamoDBPolicy (created in step 1) to the SA
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
eksctl create podidentityassociation \
  --cluster cloudcart --region us-east-1 \
  --namespace cloudcart \
  --service-account-name cloudcart-dynamodb \
  --permission-policy-arns arn:aws:iam::${ACCOUNT_ID}:policy/CloudCartDynamoDBPolicy

# 7) Restart backends so they pick up the identity
kubectl rollout restart deployment -n cloudcart

# Get the URL
kubectl get svc frontend -n cloudcart
# open http://<EXTERNAL-IP>
```

> **Open the LoadBalancer ports:** the frontend Service provisions an AWS load
> balancer (`port: 80` → `targetPort: 3000`). Make sure its security group allows
> inbound **TCP 80** (HTTP) so the app opens in a browser, and **TCP 443** if you
> later add HTTPS/TLS. If you mapped the app to 8080, allow **TCP 8080** too. For
> a demo you can allow these from your IP (or `0.0.0.0/0`); lock them down for
> anything real.

The `create-dynamodb-tables.sh` script creates 6 tables:
`cloudcart-products`, `cloudcart-inventory`, `cloudcart-carts`,
`cloudcart-orders`, `cloudcart-payments`, `cloudcart-users`.

See [eks/pod-identity.md](./eks/pod-identity.md) for the exact IAM policy scoped
to these tables.

> **Note:** `create-dynamodb-tables.sh` (step 1) creates the `CloudCartDynamoDBPolicy` IAM policy for you, so the association in step 6 works. If you ran an older version of the script and the association failed with "Policy ... does not exist", re-run `./scripts/create-dynamodb-tables.sh`, delete the failed CloudFormation stack, then retry step 6:
> ```bash
> aws cloudformation delete-stack \
>   --stack-name eksctl-cloudcart-podidentityrole-cloudcart-cloudcart-dynamodb \
>   --region us-east-1
> aws cloudformation wait stack-delete-complete \
>   --stack-name eksctl-cloudcart-podidentityrole-cloudcart-cloudcart-dynamodb \
>   --region us-east-1
> ```

Verify persistence after placing an order:
```bash
aws dynamodb scan --table-name cloudcart-orders --region us-east-1
```

> Key point: the pod assumes an IAM role scoped to only these tables — no AWS
> access keys live in Kubernetes.

### If the Pod Identity association fails

The association in step 7 provisions a CloudFormation stack for the pod-identity
IAM role. It commonly fails with `Policy ... does not exist or is not attachable`
when `CloudCartDynamoDBPolicy` was never created first (step 6 above), or when a
previous failed attempt left the stack behind.

Read the real reason from the stack events:

```bash
aws cloudformation describe-stack-events \
  --stack-name eksctl-cloudcart-podidentityrole-cloudcart-cloudcart-dynamodb \
  --region us-east-1 \
  --query "StackEvents[?ResourceStatus=='CREATE_FAILED'].[LogicalResourceId,ResourceStatusReason]" \
  --output table
```

Fix: create the policy (step 6), delete the failed stack, then re-run the
association:

```bash
aws cloudformation delete-stack \
  --stack-name eksctl-cloudcart-podidentityrole-cloudcart-cloudcart-dynamodb \
  --region us-east-1
aws cloudformation wait stack-delete-complete \
  --stack-name eksctl-cloudcart-podidentityrole-cloudcart-cloudcart-dynamodb \
  --region us-east-1
```

Then re-run the `eksctl create podidentityassociation` command from step 7.

Check the association exists:

```bash
eksctl get podidentityassociation --cluster cloudcart --region us-east-1
```

---

## Step 6 — Automate everything: Terraform + GitHub Actions (CI/CD)

The repeatable, infra-as-code option. Instead of eksctl + manual steps,
Terraform provisions everything together: VPC + EKS + ECR + DynamoDB + KMS +
Pod Identity.

> **Do this once first** — the S3 state bucket in `backend.tf` must exist before
> `terraform init`, or init fails:
> ```bash
> aws s3 mb s3://ajay-eks-demo-terraform-bucket --region us-east-1
> aws s3api put-bucket-versioning --bucket ajay-eks-demo-terraform-bucket \
>   --versioning-configuration Status=Enabled
> ```

### Run Terraform locally

```bash
cd environments/dev/us-east-1
# edit terraform.tfvars (region, cluster name, node sizes, tags)
terraform init
terraform plan
terraform apply
terraform output -raw configure_kubectl   # run the printed command to set up kubectl
```

### Run it in GitHub Actions

The workflow `.github/workflows/dev_cloudcart_eks_workflow.yml` runs on the
GitHub-hosted `ubuntu-latest` runner. For it to succeed:

1. Add repo secrets (Settings → Secrets and variables → Actions):
   `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (an IAM user with admin rights).
2. Create the S3 state bucket first (command above) — Actions does not create it.
3. `plan` runs on push; **`apply` runs only on `main`** (or a manual run with
   `tf_apply=true`).

Note: infra apply takes ~15–20 min. Terraform builds the **infrastructure**,
while deploying the **app** (ECR push + `kubectl apply` from Step 2/4/5) stays a
separate step.

After `terraform apply`, deploy the app using the Step 4 (no DynamoDB) or
Step 5 (DynamoDB) manifests.

Full detail and troubleshooting: **[DEPLOYMENT-GUIDE.md](./DEPLOYMENT-GUIDE.md)**.

---

## Cleanup (avoid charges)

```bash
eksctl delete cluster --name cloudcart --region us-east-1        # if you used eksctl (Step 3)
cd environments/dev/us-east-1 && terraform destroy               # if you used Terraform (Step 6)
```

---

## Repository structure

```
.
├── frontend/                     # Web UI + /api proxy to the backends
├── services/                     # 6 backend microservices (each: Dockerfile + src)
│   ├── product-service/
│   ├── inventory-service/
│   ├── cart-service/
│   ├── order-service/
│   ├── payment-service/
│   └── auth-service/
├── k8s/
│   ├── namespace.yaml            # the cloudcart namespace
│   ├── local/                    # local Kubernetes (kind/minikube), in-memory
│   ├── aws/                      # EKS: ECR images + DynamoDB + Pod Identity + LoadBalancer
│   └── aws-nodynamo/             # EKS: same app, in-memory (no DynamoDB / no Pod Identity)
├── scripts/
│   ├── push-to-ecr.sh            # build + push all images to ECR
│   ├── create-dynamodb-tables.sh # create the 6 DynamoDB tables
│   ├── render-aws-manifests.sh          # fill <ACCOUNT_ID>/<REGION> in k8s/aws
│   └── render-aws-nodynamo-manifests.sh # fill <ACCOUNT_ID>/<REGION> in k8s/aws-nodynamo
├── modules/                      # reusable Terraform: vpc, eks, ecr, dynamodb, kms, eks-pod-identity
├── environments/
│   └── dev/us-east-1/            # the ONE Terraform env you deploy (edit terraform.tfvars)
├── eks/                          # eksctl reference + pod-identity notes
├── diagrams/                     # architecture SVGs
├── .github/workflows/            # GitHub Actions Terraform pipeline
├── docker-compose.yml            # run the whole app locally
├── DEPLOYMENT-GUIDE.md           # detailed runbook + troubleshooting
└── README.md
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
- Remote state uses the S3 bucket in `backend.tf` — create it once before `terraform init` (see Step 6).

---

## Bastion server setup (optional)

An Ubuntu EC2 admin box inside the VPC to run
`git`/`aws`/`kubectl`/`eksctl`/`terraform`/`docker`. It's useful for a **private
cluster** (no public API endpoint) or a **clean, consistent workshop
environment**. It gets its permissions from an attached **IAM instance
profile**, so there are **no AWS access keys stored on the box**.

> **Note:** for demo/workshop purposes only — in real production, scope these
> IAM permissions down to least privilege.

**Facts:** Ubuntu latest (default LTS) AMI; **recommended instance type
`t3.medium`** (2 vCPU / 4 GB — enough headroom to build all seven images with
Docker); root EBS volume 20 GB (gp3).

### 1. Create the RSA PEM key pair
Console: **EC2 → Key Pairs → Create key pair → RSA → .pem**. Name it e.g.
`cloudcart-bastion` and download the `.pem`. Or from the CLI:

```bash
aws ec2 create-key-pair --key-name cloudcart-bastion \
  --key-type rsa --query 'KeyMaterial' --output text > cloudcart-bastion.pem
chmod 400 cloudcart-bastion.pem
```

The PEM is a **secret** and is already covered by `.gitignore` (`*.pem`).

### 2. Create the IAM role + instance profile
Console: **IAM → Roles → Create role → EC2**. Attach the trust policy, the
custom inline policy below, and the three managed policies. You attach the role
to the instance at launch as an **IAM instance profile**.

Trust relationship (assume-role) for EC2:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

Custom inline policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EKSFullInfrastructureAccess",
      "Effect": "Allow",
      "Action": ["eks:*"],
      "Resource": "*"
    },
    {
      "Sid": "EKSRequiredSupportingServices",
      "Effect": "Allow",
      "Action": [
        "iam:PassRole",
        "iam:CreateServiceLinkedRole",
        "kms:DescribeKey",
        "kms:CreateGrant",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:PutRetentionPolicy",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeVpcs"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EKSNetworkAndIAMHelpers",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:AttachRolePolicy",
        "iam:GetRole",
        "ec2:CreateSecurityGroup",
        "ec2:Describe*",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress"
      ],
      "Resource": "*"
    }
  ]
}
```

Also attach these AWS managed policies:

- `AmazonSSMFullAccess`
- `AmazonDynamoDBFullAccess`
- `AmazonS3FullAccess`
- `AmazonEC2ContainerRegistryFullAccess`

> The ECR Full Access policy lets the bastion run `push-to-ecr.sh` (create repos + push). For a real production setup, scope all of these down to least privilege.

### 3. Launch the Ubuntu EC2 instance
Console: **EC2 → Launch instance**. Choose the latest **Ubuntu** AMI,
**t3.medium**, a **20 GB gp3** root volume, select the `cloudcart-bastion` key
pair, and attach the IAM role/instance profile. Use a security group allowing
**SSH (TCP 22) from your IP**. (SSM Session Manager is a keyless alternative
since `AmazonSSMFullAccess` is attached — you can skip open port 22 entirely.)
Paste the user-data script below into **Advanced details → User data**:

```bash
#!/bin/bash
set -e
exec > /var/log/user-data.log 2>&1   # capture everything for troubleshooting

apt-get update -y
apt-get install -y unzip curl git gnupg lsb-release

# Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ubuntu

# AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install

# kubectl (latest stable)
KVER=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# eksctl
curl --silent --location "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C /tmp
mv /tmp/eksctl /usr/local/bin

# Terraform
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
apt-get update -y
apt-get install -y terraform

# Verification block — written to a file students (and you) can check
{
  echo "git: $(git --version)"
  echo "aws: $(aws --version)"
  echo "kubectl: $(kubectl version --client)"
  echo "eksctl: $(eksctl version)"
  echo "terraform: $(terraform -version | head -1)"
  echo "docker: $(docker --version)"
} > /home/ubuntu/versions.txt
chown ubuntu:ubuntu /home/ubuntu/versions.txt
touch /home/ubuntu/BOOTSTRAP_DONE
```

### 4. Wait for bootstrap to finish
Check that `/home/ubuntu/BOOTSTRAP_DONE` exists and `cat /home/ubuntu/versions.txt`.
If troubleshooting, tail `/var/log/user-data.log`.

### 5. Use it
From the bastion:

```bash
aws sts get-caller-identity                                    # should show the instance role
aws eks update-kubeconfig --name cloudcart --region us-east-1
kubectl get nodes
```

### SSH into the bastion from your laptop (with the PEM key)

**macOS/Linux:**
```bash
chmod 400 cloudcart-bastion.pem
ssh -i cloudcart-bastion.pem ubuntu@<EC2_PUBLIC_IP_OR_DNS>
```
(the default user for the Ubuntu AMI is `ubuntu`).

**Windows:** use `ssh` from PowerShell/Windows Terminal the same way, or PuTTY
(convert `.pem` to `.ppk` with PuTTYgen, user `ubuntu`).

Get the public IP/DNS from the EC2 console or `aws ec2 describe-instances`.
Ensure the security group allows inbound **TCP 22 from your IP**.

**Keyless alternative:** `aws ssm start-session --target <INSTANCE_ID>` — works
because `AmazonSSMFullAccess` is attached and the SSM agent ships with the
Ubuntu AMI, so no open port 22 is needed.
