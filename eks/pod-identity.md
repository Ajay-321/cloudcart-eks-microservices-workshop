# EKS Pod Identity — DynamoDB access

Backend Pods use a dedicated Kubernetes service account to get scoped, keyless
access to DynamoDB via EKS Pod Identity.

## 1. Create the DynamoDB tables

```bash
./scripts/create-dynamodb-tables.sh
```

## 2. Create an IAM policy

Create a policy named `CloudCartDynamoDBPolicy` scoped to only the five CloudCart
tables. Replace `<ACCOUNT_ID>` with your account id.

Create it from the CLI (save the JSON below as `dynamodb-policy.json` first):

```bash
aws iam create-policy \
  --policy-name CloudCartDynamoDBPolicy \
  --policy-document file://dynamodb-policy.json
```

Example policy (`dynamodb-policy.json`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:Scan"
      ],
      "Resource": [
        "arn:aws:dynamodb:us-east-1:<ACCOUNT_ID>:table/cloudcart-products",
        "arn:aws:dynamodb:us-east-1:<ACCOUNT_ID>:table/cloudcart-inventory",
        "arn:aws:dynamodb:us-east-1:<ACCOUNT_ID>:table/cloudcart-carts",
        "arn:aws:dynamodb:us-east-1:<ACCOUNT_ID>:table/cloudcart-orders",
        "arn:aws:dynamodb:us-east-1:<ACCOUNT_ID>:table/cloudcart-payments"
      ]
    }
  ]
}
```

## 3. Associate the IAM role

Install the Pod Identity Agent if needed:

```bash
eksctl create addon --cluster cloudcart --region us-east-1 --name eks-pod-identity-agent
```

Make sure the service account exists:

```bash
kubectl apply -f k8s/aws/service-account.yaml
```

Then create the association:

```bash
eksctl create podidentityassociation \
  --cluster cloudcart \
  --region us-east-1 \
  --namespace cloudcart \
  --service-account-name cloudcart-dynamodb \
  --permission-policy-arns arn:aws:iam::<ACCOUNT_ID>:policy/CloudCartDynamoDBPolicy
```

EKS Pod Identity supplies temporary AWS credentials to Pods using the associated service account. Do not put AWS access keys in Kubernetes Secrets.

## Note

DynamoDB is optional. Run with `USE_DYNAMODB=false` (local manifests) for an
in-memory setup, and switch it on only when you want persistent state.
