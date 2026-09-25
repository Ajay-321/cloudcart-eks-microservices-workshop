# CloudCart — Kubernetes & Amazon EKS Workshop

This repository is a hands-on demo that shows how to build and deploy a real microservices application on **Amazon EKS** (managed Kubernetes). CloudCart is a small e-commerce store composed of **seven microservices (one `frontend` + six backend services)** that are containerized with Docker, published to Amazon ECR, and run on an EKS cluster — exposed to the internet through a Kubernetes LoadBalancer Service (an AWS ELB), with optional persistence in Amazon DynamoDB. It's meant as a learning/workshop reference you can follow end to end: start on your laptop with Docker, then move the same containers to AWS.

> **Docker on your laptop → Amazon ECR → Amazon EKS → LoadBalancer → DynamoDB**

### What you'll learn

- Containerizing microservices with Docker and running them together with Docker Compose
- Publishing images to a private registry (Amazon ECR)
- Standing up a managed Kubernetes cluster with Amazon EKS
- Deploying microservices as Kubernetes Deployments + Services, exposed via a LoadBalancer
- Adding managed persistence with Amazon DynamoDB via EKS Pod Identity (no static keys)
- Automating the whole thing with Terraform + GitHub Actions CI/CD

### Architecture at a glance

```
browser ──▶ frontend ──▶ product / inventory / cart / order / payment / auth
                                     order ──▶ inventory + payment
```

The `frontend` is the only public entry point (a Kubernetes LoadBalancer Service). It proxies `/api/*` to the six backend services, which are ClusterIP-only and talk to each other over the cluster's internal network — the same service-discovery model Docker Compose uses locally. See the full end-to-end diagram in [`diagrams/architecture-flow.svg`](./diagrams/architecture-flow.svg).

---

## How this workshop is structured

There are two paths through this workshop, and they build on each other.

- **Manual path (great for learning / first-time)** — test the app locally with Docker on your laptop, then do everything on an **EC2 bastion server**: create the EKS cluster, deploy the microservices **without DynamoDB** (in-memory) to see the whole app on a real cluster fast, then redeploy **with DynamoDB** for real persistence. You touch every piece by hand so you understand what each one does.
- **Automated path (real life)** — once you understand the pieces, automate all of it with **Terraform** (infrastructure as code) plus a **GitHub Actions CI/CD pipeline** that builds, deploys, and seeds the app on every push.

New here? Do the manual steps first to understand each piece. In real projects, automate it (last section).

---

## Contents

- [Prerequisites](#prerequisites)
- [Repository structure](#repository-structure)
- [The app](#the-app)
- [Bastion server setup (EC2)](#bastion-server-setup-ec2)
- [Step 1 — Clone the repo](#step-1--clone-the-repo)
- [Step 2 — Run locally with Docker](#step-2--run-locally-with-docker)
- [Step 3 — Push images to Amazon ECR](#step-3--push-images-to-amazon-ecr)
- [Step 4 — Create the EKS cluster](#step-4--create-the-eks-cluster)
- [Step 5 — Deploy on EKS WITHOUT DynamoDB (in-memory)](#step-5--deploy-on-eks-without-dynamodb-in-memory)
- [Step 6 — Deploy on EKS WITH DynamoDB (persistence + Pod Identity)](#step-6--deploy-on-eks-with-dynamodb-persistence--pod-identity)
- [Automate everything: Terraform + GitHub Actions (CI/CD)](#automate-everything-terraform--github-actions-cicd)
- [Terraform, in short](#terraform-in-short)
- [Cleanup (avoid charges)](#cleanup-avoid-charges)

---

## Prerequisites

You need an AWS account and a few CLI tools. The easiest path for this workshop is the **bastion EC2 server** (a section below) — it comes with every tool pre-installed, so you don't install anything on your laptop.

### Accounts & access

- AWS account
- IAM admin user (not root)
- AWS CLI v2 configured (`aws configure`, region `us-east-1`)
- Verify with `aws sts get-caller-identity`

### Local tools (pre-installed on the bastion)

| Tool | Purpose |
|------|---------|
| Docker | Build and run containers |
| AWS CLI v2 | Talk to AWS |
| kubectl | Control Kubernetes |
| eksctl | Create/manage EKS clusters |
| Terraform ≥ 1.5 | Infrastructure as code |
| git | Clone this repo |

> **Note:** On the bastion these are all installed automatically by its user-data script.

### AWS resources to create once

- An RSA PEM key pair for SSH (bastion)
- An IAM role + instance profile for the bastion
- An S3 bucket for Terraform remote state (automated path only)

### Credentials rule

Do **not** use the root account. Instead:

1. Create an IAM admin user.
2. Create an access key for that user.
3. Run `aws configure` and set the region to `us-east-1`.
4. Verify with `aws sts get-caller-identity`.

---

## Repository structure

```
.
├── frontend/                      # Web UI (multi-page storefront) + /api proxy to backends
├── services/                      # 6 backend microservices, each with its own Dockerfile + src
│   ├── product-service/           # Product catalogue API
│   ├── inventory-service/         # Stock levels API
│   ├── cart-service/              # Shopping cart API
│   ├── order-service/             # Places orders (calls inventory + payment)
│   ├── payment-service/           # Mock payment API
│   └── auth-service/              # Signup/login, issues JWTs
├── k8s/                           # Kubernetes manifests
│   ├── namespace.yaml             # The cloudcart namespace
│   ├── local/                     # Local k8s (kind/minikube), in-memory data
│   ├── aws/                       # EKS with DynamoDB + Pod Identity + LoadBalancer
│   └── aws-nodynamo/              # EKS with in-memory data (no DynamoDB / no Pod Identity)
├── scripts/                       # Helper automation scripts
│   ├── push-to-ecr.sh             # Build + push all 7 images to ECR
│   ├── create-dynamodb-tables.sh  # Create 6 DynamoDB tables + the IAM policy
│   ├── seed-dynamodb.sh           # Load the 24-product catalogue + stock into DynamoDB
│   ├── render-aws-manifests.sh          # Fill <ACCOUNT_ID>/<REGION> in k8s/aws
│   └── render-aws-nodynamo-manifests.sh # Fill <ACCOUNT_ID>/<REGION> in k8s/aws-nodynamo
├── modules/                       # Reusable Terraform modules
│   ├── vpc/                       # VPC, subnets, NAT, routing
│   ├── eks/                       # EKS cluster + managed node group
│   ├── ecr/                       # Container registries
│   ├── dynamodb/                  # DynamoDB tables
│   ├── kms/                       # KMS key for table encryption
│   └── eks-pod-identity/          # Pod Identity IAM role + association
├── environments/
│   └── dev/us-east-1/             # The ONE Terraform env you deploy (edit terraform.tfvars)
├── eks/                           # eksctl reference + Pod Identity notes
├── diagrams/                      # Architecture diagrams (SVG)
├── .github/workflows/             # GitHub Actions: Terraform infra + app deploy pipelines
├── docker-compose.yml             # Run the whole app locally with Docker
├── DEPLOYMENT-GUIDE.md            # Detailed runbook + troubleshooting
└── README.md                      # This file
```

---

## The app

CloudCart is a small storefront. The `frontend` serves a few HTML pages and proxies `/api/*` calls to the backends.

| Page | Path | What it does |
|------|------|--------------|
| Storefront | `/` | Browse the product catalogue and add items to the cart |
| Login | `/login` | Sign in (auth-service issues a JWT) |
| Sign up | `/signup` | Create an account |
| Dashboard | `/dashboard` | View your account and orders after signing in |

Under the hood, seven Node.js/Express microservices do the work. Each backend can run with in-memory data (`USE_DYNAMODB=false`) or persist to DynamoDB.

| Service | Role |
|---------|------|
| `frontend` | Web UI + `/api/*` proxy; the only public (LoadBalancer) service |
| `product-service` | Product catalogue API |
| `inventory-service` | Stock levels API |
| `cart-service` | Shopping cart API |
| `order-service` | Places orders (calls inventory + payment) |
| `payment-service` | Mock payment API |
| `auth-service` | Signup/login, issues JWTs |

> **Data mode:** `USE_DYNAMODB=false` keeps everything in memory (great for the first EKS deploy). `USE_DYNAMODB=true` reads/writes the DynamoDB tables.

---

## Bastion server setup (EC2)

The whole manual demo runs from one small Ubuntu EC2 admin box (the "bastion"). It has every tool pre-installed and gets its permissions from an **attached IAM instance profile** — so there are **no AWS access keys stored on the box**.

> **Note:** these are demo/workshop settings — in real production, scope the IAM permissions down to least privilege.

**Facts:** Ubuntu latest AMI, `t3.medium`, 30 GB gp3 root volume.

### 1. Create the RSA PEM key pair

Console path: EC2 → Key Pairs → Create key pair → RSA → `.pem` (name `cloudcart-bastion`), or CLI:

```bash
aws ec2 create-key-pair --key-name cloudcart-bastion \
  --key-type rsa --query 'KeyMaterial' --output text > cloudcart-bastion.pem
chmod 400 cloudcart-bastion.pem
```

The PEM is a secret, already covered by `.gitignore` (`*.pem`).

### 2. Create the IAM role + instance profile

Console: IAM → Roles → Create role → EC2. Use this EC2 **trust policy**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Principal": { "Service": "ec2.amazonaws.com" }, "Action": "sts:AssumeRole" }
  ]
}
```

Then attach this custom **inline policy**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Sid": "EKSAccess", "Effect": "Allow", "Action": "eks:*", "Resource": "*" },
    { "Sid": "EC2Access", "Effect": "Allow", "Action": "ec2:*", "Resource": "*" },
    { "Sid": "CloudFormationAccess", "Effect": "Allow", "Action": "cloudformation:*", "Resource": "*" },
    {
      "Sid": "IAMAccess",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:PassRole",
        "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:CreatePolicy", "iam:DeletePolicy",
        "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:GetPolicy", "iam:GetPolicyVersion",
        "iam:ListPolicyVersions", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
        "iam:CreateServiceLinkedRole", "iam:TagRole", "iam:TagPolicy",
        "iam:GetOpenIDConnectProvider", "iam:CreateOpenIDConnectProvider",
        "iam:DeleteOpenIDConnectProvider", "iam:TagOpenIDConnectProvider"
      ],
      "Resource": "*"
    },
    { "Sid": "AutoScalingAccess", "Effect": "Allow", "Action": "autoscaling:*", "Resource": "*" },
    {
      "Sid": "LogsAccess", "Effect": "Allow",
      "Action": ["logs:CreateLogGroup","logs:CreateLogStream","logs:DescribeLogGroups","logs:DescribeLogStreams","logs:PutLogEvents","logs:PutRetentionPolicy"],
      "Resource": "*"
    },
    {
      "Sid": "KMSAccess", "Effect": "Allow",
      "Action": ["kms:DescribeKey","kms:CreateGrant","kms:ListGrants","kms:RevokeGrant"],
      "Resource": "*"
    },
    {
      "Sid": "SSMAccess", "Effect": "Allow",
      "Action": ["ssm:DescribeInstanceInformation","ssm:GetParameter","ssm:GetParameters","ssm:GetParametersByPath"],
      "Resource": "*"
    }
  ]
}
```

The `iam:CreatePolicy` permission lets the bastion create `CloudCartDynamoDBPolicy` (done by `create-dynamodb-tables.sh`).

Also attach these AWS **managed policies**:

- `AmazonSSMFullAccess`
- `AmazonDynamoDBFullAccess`
- `AmazonS3FullAccess`
- `AmazonEC2ContainerRegistryFullAccess`

ECR Full Access lets the bastion run `push-to-ecr.sh` (it includes `ecr:CreateRepository`).

### 3. Launch the Ubuntu EC2 instance

Console: EC2 → Launch instance. Choose the **latest Ubuntu AMI**, **t3.medium**, **30 GB gp3** root volume, select the `cloudcart-bastion` key pair, attach the IAM role/instance profile, and a security group allowing SSH (**TCP 22**) from your IP. SSM Session Manager is a keyless alternative. Paste the user-data below into Advanced details → User data:

```bash
#!/bin/bash
set -e
exec > /var/log/user-data.log 2>&1

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

# Verification file
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

Bootstrapping takes a few minutes. Once done, `/home/ubuntu/BOOTSTRAP_DONE` exists:

```bash
ls /home/ubuntu/BOOTSTRAP_DONE       # exists when bootstrap is complete
cat /home/ubuntu/versions.txt        # confirms tool versions
tail -f /var/log/user-data.log       # follow the bootstrap log if troubleshooting
```

### 5. Verify tools + AWS identity

Confirm the bastion's IAM role is in effect:

```bash
aws sts get-caller-identity          # should show the bastion's assumed role
```

From here on, run **all deployment steps on this bastion**.

### SSH into the bastion from your laptop (with the PEM key)

**macOS / Linux:**

```bash
chmod 400 cloudcart-bastion.pem
ssh -i cloudcart-bastion.pem ubuntu@<EC2_PUBLIC_IP_OR_DNS>
```

**Windows / PuTTY:** convert `cloudcart-bastion.pem` to `.ppk` with PuTTYgen, then connect to `ubuntu@<EC2_PUBLIC_IP>` using that key.

Default user is `ubuntu`. Get the public IP/DNS from the EC2 console, and make sure the security group allows inbound **TCP 22** from your IP. Keyless alternative: `aws ssm start-session --target <INSTANCE_ID>`.

> Everything below runs from this bastion.

---

## Step 1 — Clone the repo

Clone onto the bastion (or your laptop). If you're on the bastion and returning later, run `git pull` first so you have the latest scripts.

```bash
git clone https://github.com/Ajay-321/cloudcart-eks-microservices-workshop.git
cd cloudcart-eks-microservices-workshop
```

---

## Step 2 — Run locally with Docker

Before Kubernetes, see how a container works. First run ONE service as a single container to understand the basics, then automate the whole app with Docker Compose (instead of starting containers one by one).

### Manual — one container

```bash
# Build an image from a service's Dockerfile
docker build -t product-service:1.0 ./services/product-service

# Run it as a container (host:container port)
docker run -d -p 8080:3000 --name product-service product-service:1.0

# Test it
curl localhost:8080/products
```

Each backend listens on port **3000** inside the container. Stop it with `docker rm -f product-service` before the next step.

### Automate — the whole app with Docker Compose

```bash
docker compose up --build      # build + start all 7 services
docker compose ps              # see them running
# open http://<EC2_PUBLIC_IP>:8080   (Compose publishes the frontend on 8080)
docker compose down            # stop everything
```

> **Open the EC2 security group:** to reach the app in your browser while it
> runs on the bastion, add inbound rules to the instance's security group for
> **TCP 8080** (Docker Compose frontend) and **TCP 80** (if you map a container
> to port 80). Only the frontend needs a published port — backends talk over
> Docker's internal network. For a demo you can allow these from your IP or
> `0.0.0.0/0`.

Why this matters: Compose gives each service a DNS name (e.g. `http://inventory-service:3000`) — Kubernetes works the same way, which is the bridge to the next steps.

---

## Step 3 — Push images to Amazon ECR

ECR is your private Docker registry; EKS pulls images from here. Do it by hand once to see the steps, then use the script.

### Option 1 — Manual (understand the steps)

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export ECR="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# 1) Log Docker in to ECR (token valid ~12h)
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR"

# 2) Create a repo (one per image; ignore error if it exists)
aws ecr create-repository --repository-name cloudcart-product-service --region "$AWS_REGION" || true

# 3) Build, 4) tag, 5) push
docker build -t cloudcart-product-service:1.0 ./services/product-service
docker tag  cloudcart-product-service:1.0 "$ECR/cloudcart-product-service:1.0"
docker push "$ECR/cloudcart-product-service:1.0"
```

Repeat for the other six images. The `frontend` build path is `./frontend`; the backends are `./services/<name>`. Tedious by hand — hence the script.

### Option 2 — Automate with the script

```bash
export AWS_REGION=us-east-1

# Make the scripts executable (first time on Linux)
chmod +x scripts/*.sh

./scripts/push-to-ecr.sh       # logs in, creates repos if missing, builds + pushes all seven
```

> **Permissions:** the bastion role needs `AmazonEC2ContainerRegistryFullAccess` (includes `ecr:CreateRepository`). ECR PowerUser alone is NOT enough.

---

## Step 4 — Create the EKS cluster

Create a managed Kubernetes cluster with eksctl from the bastion (eksctl is already installed). Use **version 1.36** and a node group of min 1 / desired 2 / max 4.

```bash
eksctl create cluster \
  --name cloudcart --region us-east-1 --version 1.36 \
  --managed --node-type t3.medium \
  --nodes 2 --nodes-min 1 --nodes-max 4 --with-oidc
```

This takes ~15–20 min and configures kubectl for you. Use the AWS Console only to view the cluster.

### Point kubectl at the cluster

```bash
# This workshop's values
aws eks update-kubeconfig --region us-east-1 --name cloudcart

# Generic form
aws eks update-kubeconfig --region <REGION> --name <CLUSTER_NAME>
```

Confirm nodes are Ready: `kubectl get nodes`.

### If pods stay Pending (not enough nodes)

Check what's wrong, then scale the node group:

```bash
kubectl get pods -n cloudcart
kubectl describe pod <POD> -n cloudcart

# Scale with eksctl (this workshop's node group)
eksctl scale nodegroup --cluster cloudcart --region us-east-1 \
  --name <NODEGROUP_NAME> --nodes 3 --nodes-min 1 --nodes-max 4

# Generic form
eksctl scale nodegroup --cluster <CLUSTER_NAME> --region <REGION> \
  --name <NODEGROUP_NAME> --nodes <N> --nodes-min <MIN> --nodes-max <MAX>

# Or with the AWS CLI in one line
aws eks update-nodegroup-config --cluster-name cloudcart --region us-east-1 \
  --nodegroup-name <NODEGROUP_NAME> \
  --scaling-config minSize=1,maxSize=4,desiredSize=2
```

---

## Step 5 — Deploy on EKS WITHOUT DynamoDB (in-memory)

Fastest way to see the whole app on a real cluster. Backends use in-memory data (`USE_DYNAMODB=false`) — no tables, no IAM, no Pod Identity. Only the frontend gets a public ELB.

Run each step one at a time:

```bash
export AWS_REGION=us-east-1

# 1) Make scripts executable (first time on Linux)
chmod +x scripts/*.sh

# 2) Fill <ACCOUNT_ID>/<REGION> into the no-DynamoDB image references
./scripts/render-aws-nodynamo-manifests.sh

# 3) Create the namespace
kubectl apply -f k8s/namespace.yaml

# 4) Deploy all services (in-memory mode)
kubectl apply -f k8s/aws-nodynamo/

# 5) Watch pods come up until all are Running
kubectl get pods -n cloudcart -w
```

Then get the URL:

```bash
kubectl get svc frontend -n cloudcart
# wait for EXTERNAL-IP to become an ELB hostname, then open http://<EXTERNAL-IP>
```

> **Open the LoadBalancer's security group** for inbound **TCP 80** (and 443 if you add TLS). The frontend Service is `type: LoadBalancer` (port 80 → targetPort 3000), and the classic ELB auto-creates its own security group. For a demo, allow from your IP or `0.0.0.0/0`.

### Validate the deployment

```bash
kubectl get pods -n cloudcart        # all Running (1/1)
kubectl get svc -n cloudcart         # frontend = LoadBalancer w/ EXTERNAL-IP; others ClusterIP
kubectl get deploy -n cloudcart      # all replicas available
kubectl rollout status deployment/frontend -n cloudcart
kubectl logs -n cloudcart deployment/order-service --tail=50   # check logs if needed
```

**Reset before the DynamoDB demo:** `kubectl delete -f k8s/aws-nodynamo/` (keep the namespace).

---

## Step 6 — Deploy on EKS WITH DynamoDB (persistence + Pod Identity)

Now add real persistence. Pods reach DynamoDB via **EKS Pod Identity** — a scoped IAM role, no static keys in Kubernetes. **IMPORTANT (beginners):** run these ONE AT A TIME and wait for each to finish. Running them all at once can race — table creation, seeding, deploy, and Pod Identity need to complete in order.

```bash
export AWS_REGION=us-east-1

# 1) Make scripts executable (first time on Linux)
chmod +x scripts/*.sh

# 2) Create the 6 DynamoDB tables + the CloudCartDynamoDBPolicy IAM policy (idempotent)
./scripts/create-dynamodb-tables.sh

# 3) Seed the catalogue: 24 products + matching stock (tables start empty)
./scripts/seed-dynamodb.sh

# 4) Fill <ACCOUNT_ID>/<REGION> into the DynamoDB image references
./scripts/render-aws-manifests.sh

# 5) Create the namespace (skip if it already exists)
kubectl apply -f k8s/namespace.yaml

# 6) Create the service account the pods use for DynamoDB access
kubectl apply -f k8s/aws/service-account.yaml

# 7) Install the EKS Pod Identity agent (once per cluster)
eksctl create addon --cluster cloudcart --region us-east-1 --name eks-pod-identity-agent

# 8) Associate the CloudCartDynamoDBPolicy with the service account
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
eksctl create podidentityassociation \
  --cluster cloudcart --region us-east-1 \
  --namespace cloudcart \
  --service-account-name cloudcart-dynamodb \
  --permission-policy-arns arn:aws:iam::${ACCOUNT_ID}:policy/CloudCartDynamoDBPolicy

# 9) Deploy the app (references DynamoDB + the service account)
kubectl apply -f k8s/aws/

# 10) Restart backends so they pick up the Pod Identity credentials
kubectl rollout restart deployment -n cloudcart

# 11) Get the URL
kubectl get svc frontend -n cloudcart
# open http://<EXTERNAL-IP>
```

The 6 tables are: `cloudcart-products`, `cloudcart-inventory`, `cloudcart-carts`, `cloudcart-orders`, `cloudcart-payments`, `cloudcart-users`. Note that `create-dynamodb-tables.sh` also creates the `CloudCartDynamoDBPolicy` IAM policy.

**Why seed?** The tables are created empty. `seed-dynamodb.sh` loads the 24-product catalogue and matching stock so the storefront has something to show.

### Validate the deployment

```bash
kubectl get pods -n cloudcart        # all Running (1/1)
kubectl get svc -n cloudcart
kubectl get deploy -n cloudcart
kubectl rollout status deployment/frontend -n cloudcart
kubectl logs -n cloudcart deployment/auth-service --tail=50
# After placing an order in the UI, confirm it persisted:
aws dynamodb scan --table-name cloudcart-orders --region us-east-1 --select COUNT
```

If a backend pod CrashLoops with a KMS/AccessDenied error, the Pod Identity association or its KMS permission isn't in place (the Terraform path grants KMS automatically).

### If the Pod Identity association fails

Read the stack events, delete the failed stack, then re-run the association:

```bash
aws cloudformation describe-stack-events \
  --stack-name eksctl-cloudcart-podidentityrole-cloudcart-cloudcart-dynamodb \
  --region us-east-1 \
  --query "StackEvents[?ResourceStatus=='CREATE_FAILED'].[LogicalResourceId,ResourceStatusReason]" --output table

aws cloudformation delete-stack --stack-name eksctl-cloudcart-podidentityrole-cloudcart-cloudcart-dynamodb --region us-east-1
aws cloudformation wait stack-delete-complete --stack-name eksctl-cloudcart-podidentityrole-cloudcart-cloudcart-dynamodb --region us-east-1

# Re-run step 8, then confirm:
eksctl get podidentityassociation --cluster cloudcart --region us-east-1
```

---

## Automate everything: Terraform + GitHub Actions (CI/CD)

The manual steps above are great for learning and a first-time run. In real life you automate all of it — repeatable, reviewable, and hands-off.

**What is Terraform?** Infrastructure as code — it provisions the whole stack (VPC, EKS, ECR, DynamoDB, KMS, Pod Identity) from declarative files. **What is GitHub Actions?** CI/CD — it runs Terraform and the app deploy automatically on push.

### One-time: S3 state bucket

> The S3 remote-state bucket referenced in `backend.tf` must exist before `terraform init`:
> ```bash
> aws s3 mb s3://ajay-eks-demo-terraform-bucket --region us-east-1
> aws s3api put-bucket-versioning --bucket ajay-eks-demo-terraform-bucket --versioning-configuration Status=Enabled
> ```

### Run Terraform locally

```bash
cd environments/dev/us-east-1
# edit terraform.tfvars (region, cluster name, node sizes)
terraform init
terraform plan
terraform apply
terraform output -raw configure_kubectl   # run the printed command to set up kubectl
```

### Run infra in GitHub Actions

Workflow `.github/workflows/dev_cloudcart_eks_workflow.yml` (Terraform infra):

1. Add repo secrets `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`.
2. Create the S3 state bucket first.
3. It runs **plan on push** and **apply on main** (or manual dispatch `tf_apply=true`).

Infra apply takes ~15–20 min.

### Automated app deployment pipeline

Workflow `.github/workflows/dev_cloudcart_app_deploy.yml` — four stages:

1. **Build & push** images to ECR.
2. **Deploy** manifests to EKS.
3. **Seed** DynamoDB.
4. **Print URL** + open **TCP 80** on the ELB security group automatically.

Triggers on push to main or manual **Run workflow**. Infra must exist first.

### Tear down (targeted)

Delete the app/namespace first to release the ELB (an orphaned ELB blocks VPC deletion), then run a targeted `terraform destroy`:

```bash
cd environments/dev/us-east-1

# Delete the app FIRST so the ELB is released
aws eks update-kubeconfig --region us-east-1 --name cloudcart
kubectl delete namespace cloudcart 2>/dev/null || true

# Targeted destroy — Pod Identity + DynamoDB + ECR + EKS + VPC (keep KMS)
terraform destroy \
  -target=module.pod_identity \
  -target=module.dynamodb \
  -target=module.ecr \
  -target=module.eks \
  -target=module.vpc
```

> **Demo tip:** for a same-day re-demo you can destroy only the conflicting resources (`module.pod_identity`, `module.dynamodb`, `module.ecr`, `module.eks`) and keep VPC/NAT + KMS for a short window (small cost). Recreate later with `terraform apply` — no code changes needed.

Full detail and troubleshooting: [DEPLOYMENT-GUIDE.md](./DEPLOYMENT-GUIDE.md).

---

## Terraform, in short

The `modules/` directory holds reusable building blocks (vpc, eks, ecr, dynamodb, kms, eks-pod-identity), and `environments/dev/us-east-1/` is the single environment you actually deploy — edit its `terraform.tfvars` to set the region, cluster name, and node sizes.

```hcl
# environments/dev/us-east-1/terraform.tfvars
region             = "us-east-1"
cluster_name       = "cloudcart"
kubernetes_version = "1.36"

# Managed node group
node_instance_type = "t3.medium"
desired_size       = 2
min_size           = 1
max_size           = 4
```

Remote state lives in the S3 bucket `ajay-eks-demo-terraform-bucket`. Run `terraform init && terraform plan && terraform apply` from the environment directory, then use `terraform output -raw configure_kubectl` to point kubectl at the new cluster.

---

## Cleanup (avoid charges)

Delete everything when you're done so you don't keep paying for the cluster, NAT gateway, and load balancer.

### Delete the cluster

```bash
# If you created it manually with eksctl
eksctl delete cluster --name cloudcart --region us-east-1

# If you created it with Terraform
cd environments/dev/us-east-1
terraform destroy   # tears down VPC + EKS + ECR + DynamoDB + Pod Identity
```

### Reset between the manual and automated runs (IMPORTANT)

> The manual scripts/manifests and Terraform use the **same names** (cluster, ECR repos, DynamoDB tables, IAM policy). If you did the manual flow first, clean those up before running Terraform so they don't conflict.

```bash
export AWS_REGION=us-east-1

# ECR repos
for r in frontend product-service inventory-service cart-service order-service payment-service auth-service; do
  aws ecr delete-repository --repository-name cloudcart-$r --force --region "$AWS_REGION" || true
done

# DynamoDB tables
for t in products inventory carts orders payments users; do
  aws dynamodb delete-table --table-name cloudcart-$t --region "$AWS_REGION" || true
done

# IAM policy
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
aws iam delete-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/CloudCartDynamoDBPolicy || true

# KMS alias
aws kms delete-alias --alias-name alias/cloudcart --region "$AWS_REGION" || true

# Pod Identity CloudFormation stack
aws cloudformation delete-stack --stack-name eksctl-cloudcart-podidentityrole-cloudcart-cloudcart-dynamodb --region "$AWS_REGION" || true
```

These deletes are asynchronous — give AWS a minute or two to finish before recreating.

### Verify it's clean

```bash
aws ecr describe-repositories --region us-east-1 --query 'repositories[].repositoryName'
aws dynamodb list-tables --region us-east-1
aws kms list-aliases --region us-east-1 --query "Aliases[?AliasName=='alias/cloudcart']"
```

Also confirm the cluster is deleted: `eksctl get cluster --region us-east-1`.

### Stop the bastion (keep it for next time)

```bash
aws ec2 stop-instances --instance-ids <INSTANCE_ID>
```
