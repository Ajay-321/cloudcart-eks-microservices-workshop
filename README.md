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

---

## Bastion server setup (optional)

An Ubuntu EC2 admin box inside the VPC to run
`git`/`aws`/`kubectl`/`eksctl`/`terraform`/`docker`. It's useful for a **private
cluster** (no public API endpoint) or a **clean, consistent workshop
environment**. It gets its permissions from an attached **IAM instance
profile**, so there are **no AWS access keys stored on the box**.

> **Note:** for demo/workshop purposes only — in real production, scope these
> IAM permissions down to least privilege.

**Facts:** Ubuntu latest (default LTS) AMI; a small instance is fine (e.g.
`t3.medium`); root EBS volume 20 GB (gp3).

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

---

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
