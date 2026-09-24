# k8s/aws-nodynamo — CloudCart on EKS, WITHOUT DynamoDB

These manifests are DynamoDB-free copies of `k8s/aws/`. Use them for a manual
EKS demo where you want the full app (frontend + six backends) running on a
real cluster, but with **in-memory data** — no DynamoDB tables, no Pod Identity,
no IAM policy.

What differs from `k8s/aws/`:

- Every backend has `USE_DYNAMODB: "false"` (in-memory / seed data).
- No `DYNAMODB_TABLE` env var.
- No `serviceAccountName: cloudcart-dynamodb` (so `service-account.yaml` and
  Pod Identity are not needed).
- The `frontend` Service is still `type: LoadBalancer` — one public ELB, and it
  proxies `/api/*` to the backends internally (all backends stay `ClusterIP`).

The original `k8s/aws/` folder is untouched, so the DynamoDB demo still works.

## Deploy

```bash
export AWS_REGION=us-east-1

# 1) Build + push the seven images to ECR (same script as the DynamoDB path)
./scripts/push-to-ecr.sh

# 2) Fill in <ACCOUNT_ID> / <REGION> in the image references of THIS folder
./scripts/render-aws-nodynamo-manifests.sh

# 3) Deploy
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/aws-nodynamo/
kubectl get pods -n cloudcart -w

# 4) Get the public URL (wait for EXTERNAL-IP to become an ELB hostname)
kubectl get svc frontend -n cloudcart
# open http://<EXTERNAL-IP>
```

## Cleanup

```bash
kubectl delete namespace cloudcart   # removes the app and the LoadBalancer/ELB
```

Then delete the node group + cluster in the Console (and ECR repos if you no
longer need the images).

## Switching to the DynamoDB demo later

Deploy from `k8s/aws/` instead (after `render-aws-manifests.sh`), then follow
Step 7 of `DEPLOYMENT-GUIDE.md` to create tables, install the Pod Identity
agent, apply `k8s/aws/service-account.yaml`, and associate the IAM policy.
