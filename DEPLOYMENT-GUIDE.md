# CloudCart — End-to-End Deployment Guide

A step-by-step runbook. Follow it top to bottom.

**The journey:** Docker on your laptop → push images to ECR → create an EKS
cluster with `eksctl` → deploy the same containers → open the app through a
LoadBalancer → add DynamoDB.

> Region used throughout: **us-east-1**. Change it consistently if you must.

---

## Step 0 — Install tools & set up credentials

Install: Docker (or Colima), AWS CLI v2, `kubectl`, `eksctl`.

```bash
docker --version
aws --version
kubectl version --client
eksctl version
```

**Credentials — do NOT use root.** Create one IAM admin user and use it:

1. Root sign-in → IAM → Users → create an admin user (e.g. `cloudcart-admin`) →
   attach **AdministratorAccess** → enable MFA.
2. Create an access key for that user.
3. Configure the CLI:
   ```bash
   aws configure         # paste key + secret, region = us-east-1, output = json
   aws sts get-caller-identity   # should show the IAM user, NOT root
   ```

> macOS + Colima: run `colima start` before any `docker` command.

---

## Step 1 — Run ONE service in a container

See how a single container works before the whole app.

```bash
docker build -t product-service:1.0 ./services/product-service
docker run --rm -p 3001:3000 product-service:1.0
```
In another terminal:
```bash
curl localhost:3001/health
curl localhost:3001/products
```
`Ctrl+C` to stop. You just built an image from a `Dockerfile`, ran it, and
called its HTTP API.

---

## Step 2 — Run the WHOLE app with Docker Compose

```bash
docker compose up --build
```
Open **http://localhost:8080** — browse products, sign up / log in, add to cart, checkout, and check **/dashboard** for live charts.

```bash
docker compose ps     # short, clean names: frontend, cart-service, order-service, ...
docker compose logs order-service
docker compose down
```

Notes:
- Each service is its own container.
- Compose gives each container a DNS name equal to its service name, so
  `order-service` reaches `http://inventory-service:3000`. **Kubernetes works
  the same way.**
- No AWS needed here (`USE_DYNAMODB=false`).

---

## Step 3 (optional) — Same containers on LOCAL Kubernetes

If you have kind or minikube and want to show Kubernetes before AWS:

```bash
# build the seven images (compose already did this; re-tag if needed)
for s in frontend product-service inventory-service cart-service order-service payment-service auth-service; do
  path=$([ "$s" = "frontend" ] && echo "frontend" || echo "services/$s")
  docker build -t $s:1.0 ./$path
  kind load docker-image $s:1.0        # minikube: minikube image load $s:1.0
done

kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/local/
kubectl get pods -n cloudcart -w
```

Show the core ideas:
```bash
kubectl get deploy,rs,pod -n cloudcart                    # Deployment -> ReplicaSet -> Pods
kubectl delete pod -l app=product-service -n cloudcart    # watch it self-heal
kubectl scale deployment product-service --replicas=4 -n cloudcart
kubectl port-forward svc/frontend 8080:80 -n cloudcart    # open http://localhost:8080
```

---

## Step 4 — Push images to Amazon ECR

ECR is your private image registry on AWS. EKS pulls images from here.

```bash
export AWS_REGION=us-east-1
./scripts/push-to-ecr.sh
```
The script logs Docker in to ECR, creates each `cloudcart-*` repository if
missing, then builds/tags/pushes all seven images with tag `1.0`.

> Note on names: locally the images are short (`product-service:1.0`). In ECR
> they get a `cloudcart-` prefix (`cloudcart-product-service`) because a registry
> is shared across many projects and needs unique repo names.

---

## Step 5 — Create the EKS cluster with eksctl (primary path)

One command builds the VPC, control plane, and a **managed worker node group**,
and updates your kubeconfig automatically.

```bash
eksctl create cluster \
  --name cloudcart \
  --region us-east-1 \
  --version 1.31 \
  --managed \
  --node-type t3.medium \
  --nodes 2 --nodes-min 2 --nodes-max 4 \
  --with-oidc \
  --node-volume-size 30
```
This takes **~15–20 minutes**. When it finishes:
```bash
kubectl get nodes            # kubeconfig was configured for you
```

You can view the cluster in the **AWS Console** (EKS → Clusters → cloudcart) to
see the control plane, node group, and EC2 worker nodes. The console is just for
viewing here — the cluster was created from the CLI.

**What eksctl creates for you:** a **new dedicated VPC** (default `192.168.0.0/16`,
not your default VPC), public + private subnets across the AZs with the correct
EKS tags, an Internet Gateway and NAT gateway, and all **security groups**
(cluster + node) with the right inbound/outbound rules for control-plane ↔ node
and node ↔ node traffic plus internet egress. You don't configure any of that by
hand. (The Terraform path in Appendix A builds its own VPC on `vpc_cidr` from
tfvars instead — change that CIDR if it clashes with an existing VPC.)

<details>
<summary>Granting another IAM user or role kubectl access</summary>

The identity that created the cluster is admin automatically. To grant someone
else access, add an **EKS access entry**:
```bash
eksctl create accessentry \
  --cluster cloudcart --region us-east-1 \
  --principal-arn arn:aws:iam::<ACCOUNT_ID>:user/<their-user> \
  --access-policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope cluster
```
(The Terraform path can do this automatically via the `access_entries` variable.)
</details>

---

## Step 6 — Deploy CloudCart to EKS + expose it

The `k8s/aws/` deployments reference your ECR images with placeholders. Fill
them in with your account id and region, then apply:

```bash
export AWS_REGION=us-east-1
./scripts/render-aws-manifests.sh      # replaces <ACCOUNT_ID> and <REGION>

kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/aws/
kubectl get pods -n cloudcart -w
```

The `frontend` Service is `type: LoadBalancer`, so EKS provisions an AWS load
balancer with a public address:

```bash
kubectl get svc frontend -n cloudcart
# wait for EXTERNAL-IP to become a hostname like a1b2...elb.amazonaws.com
```
Open `http://<EXTERNAL-IP>` — that is CloudCart running on EKS.

---

## Step 7 — Turn on DynamoDB (persistence + Pod Identity)

So far the AWS pods still use in-memory data. Now give them a real database with
**no stored AWS keys**, using EKS Pod Identity.

```bash
# 1) Create the tables
./scripts/create-dynamodb-tables.sh

# 2) Make sure the Pod Identity agent is installed
eksctl create addon --cluster cloudcart --region us-east-1 --name eks-pod-identity-agent

# 3) Create the service account the pods use
kubectl apply -f k8s/aws/service-account.yaml

# 4) Create an IAM policy scoped to the 5 tables, then associate it (see eks/pod-identity.md)
eksctl create podidentityassociation \
  --cluster cloudcart --region us-east-1 \
  --namespace cloudcart \
  --service-account-name cloudcart-dynamodb \
  --permission-policy-arns arn:aws:iam::<ACCOUNT_ID>:policy/CloudCartDynamoDBPolicy

# 5) Restart the backends so they pick up the identity
kubectl rollout restart deployment -n cloudcart
```
Place an order in the UI, then confirm it persisted:
```bash
aws dynamodb scan --table-name cloudcart-orders --region us-east-1
```

Key point: the Pod assumes an IAM role scoped to only these tables. **No AWS
access keys live in Kubernetes.**

---

## Step 8 — Cleanup (do this to avoid charges!)

```bash
eksctl delete cluster --name cloudcart --region us-east-1
```
DynamoDB tables and ECR repos are separate:
```bash
for t in products inventory carts orders payments users; do
  aws dynamodb delete-table --table-name cloudcart-$t --region us-east-1; done
for r in frontend product-service inventory-service cart-service order-service payment-service auth-service; do
  aws ecr delete-repository --repository-name cloudcart-$r --force --region us-east-1; done
```

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---------|--------------------|
| `docker` errors on macOS | Start the engine: `colima start` (or open Docker Desktop). |
| Pods `ImagePullBackOff` on EKS | Placeholders not rendered — rerun `render-aws-manifests.sh`. |
| Pods `CrashLoopBackOff` | `kubectl logs <pod> -n cloudcart`; often a wrong `DYNAMODB_TABLE` name. |
| DynamoDB `AccessDeniedException` | Pod Identity association/policy not applied; check the service account. |
| LoadBalancer `EXTERNAL-IP` stuck `<pending>` | Give it a minute; check account load balancer limits. |
| `kubectl` "You must be logged in" | Re-run `aws eks update-kubeconfig --name cloudcart --region us-east-1`. |

---

## Appendix A — Infrastructure as Code (Terraform)

Prefer repeatable infra or CI over eksctl + scripts? Build everything (VPC, EKS,
ECR, DynamoDB, KMS, Pod Identity) with Terraform. You edit only
`environments/dev/us-east-1/terraform.tfvars`.

```bash
# one-time: create the state bucket named in backend.tf
aws s3 mb s3://ajay-eks-demo-terraform-bucket --region us-east-1
aws s3api put-bucket-versioning --bucket ajay-eks-demo-terraform-bucket \
  --versioning-configuration Status=Enabled

cd environments/dev/us-east-1
terraform init
terraform apply
terraform output -raw configure_kubectl   # run the printed command
```

Key tfvars knobs:
- Node group: `instance_types`, `desired_size`, `min_size`, `max_size`, `capacity_type`.
- `enable_auto_mode = true` → EKS Auto Mode (AWS manages nodes; node-group values ignored).
- `access_entries` → grant other IAM users/roles kubectl access.
- `dynamodb_tables` → add/change tables, GSIs, TTL, streams — no module edits.

## Appendix B — EKS Auto Mode (advanced, optional)

Auto Mode lets AWS manage the nodes for you (no node group to size). Skip it in a
first session. To try it later, set `enable_auto_mode = true` in the Terraform
tfvars and re-apply.

## Appendix C — EC2 bastion (advanced, optional)

For a private cluster (no public API endpoint), run `kubectl` from an EC2 admin
box inside the VPC. Best practice: attach an **IAM instance profile** to that EC2
(so there are **no** access keys on the box), SSH in, then
`aws eks update-kubeconfig`. Not needed for a cluster with a public API endpoint.
