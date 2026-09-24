# Requirements Document

## Introduction

This feature delivers a single, presentation-ready architecture diagram for the CloudCart
microservices demo. The diagram depicts the complete end-to-end delivery flow of the repo:
Infrastructure-as-Code (Terraform) → CI/CD (GitHub Actions) → AWS infrastructure (Amazon EKS
and supporting components) → microservices deployment → Kubernetes Service → AWS LoadBalancer
→ UI access from a browser. Persistence via Amazon DynamoDB accessed through EKS Pod Identity
is also shown.

The diagram is authored as a standalone SVG file placed in the `diagrams/` folder, matching the
visual style, canvas conventions, and typography of the existing hand-authored diagrams
(`diagrams/eks-architecture.svg`, `diagrams/kubernetes-architecture.svg`) so it can be embedded
in the existing PowerPoint deck
(`Deploying-Microservices-on-AWS-Managed-Kubernetes-Platform _Updated.pptx`) alongside them.

## Glossary

- **Diagram**: The single SVG artifact produced by this feature, saved to the `diagrams/` folder.
- **Author**: The developer who edits, renders, or presents the Diagram.
- **Presentation**: The existing PowerPoint deck the Diagram will be embedded into.
- **IaC_Stage**: The Terraform stage that provisions AWS infrastructure from `environments/dev/us-east-1`.
- **CICD_Stage**: The GitHub Actions workflow that runs `terraform plan` on push and `terraform apply` on `main`.
- **AWS_Infrastructure**: The AWS resources provisioned by the IaC_Stage — VPC, Amazon EKS cluster, managed node group, Amazon ECR, Amazon DynamoDB, AWS KMS, and EKS Pod Identity.
- **EKS_Cluster**: The Amazon EKS Kubernetes cluster (control plane + managed node group) that runs the microservices.
- **Microservices**: The seven CloudCart services — frontend, product-service, inventory-service, cart-service, order-service, payment-service, auth-service.
- **Frontend_Service**: The Kubernetes Service of type LoadBalancer that exposes the frontend Pods.
- **LoadBalancer**: The AWS Elastic Load Balancer provisioned by the Frontend_Service, providing a public DNS name.
- **Browser**: The end-user web browser that accesses the CloudCart UI through the LoadBalancer.
- **Pod_Identity**: EKS Pod Identity — the mechanism giving Pods a scoped IAM role for DynamoDB access without stored access keys.
- **Existing_Style**: The visual conventions of the existing SVG diagrams — approx. 1400x760 canvas, Arial font family, hand-authored SVG shapes and labels.

## Requirements

### Requirement 1: End-to-End Flow Coverage

**User Story:** As an Author, I want a diagram that shows the full CloudCart delivery pipeline in one view, so that I can explain the complete journey from code to running UI in a single slide.

#### Acceptance Criteria

1. THE Diagram SHALL depict the IaC_Stage, the CICD_Stage, the AWS_Infrastructure, the Microservices deployment, the Frontend_Service, the LoadBalancer, and the Browser as distinct labeled elements.
2. THE Diagram SHALL show directional connectors ordered as IaC_Stage → CICD_Stage → AWS_Infrastructure → Microservices → Frontend_Service → LoadBalancer → Browser.
3. THE Diagram SHALL label the CICD_Stage to indicate that `terraform plan` runs on push and `terraform apply` runs on the `main` branch.
4. THE Diagram SHALL indicate that the CICD_Stage provisions infrastructure and that application deployment (ECR image push and `kubectl apply`) is a separate step.
5. THE Diagram SHALL represent the region as us-east-1.

### Requirement 2: AWS Infrastructure Detail

**User Story:** As an Author, I want the AWS infrastructure components shown accurately, so that the audience understands what Terraform provisions.

#### Acceptance Criteria

1. THE Diagram SHALL depict the AWS_Infrastructure as containing a VPC, an EKS_Cluster, an Amazon ECR registry, an Amazon DynamoDB store, AWS KMS, and EKS Pod_Identity.
2. THE Diagram SHALL show the EKS_Cluster containing a Kubernetes control plane and a managed node group.
3. THE Diagram SHALL label the managed node group with the instance type t3.medium and a node count range of 2 to 4.
4. THE Diagram SHALL label the EKS_Cluster with Kubernetes version 1.31.
5. THE Diagram SHALL show the Microservices container images sourced from the Amazon ECR registry.

### Requirement 3: Microservices and Runtime Topology

**User Story:** As an Author, I want the seven microservices and their runtime relationships shown, so that the audience understands the application topology inside the cluster.

#### Acceptance Criteria

1. THE Diagram SHALL depict the seven Microservices as distinct labeled elements named frontend, product-service, inventory-service, cart-service, order-service, payment-service, and auth-service.
2. THE Diagram SHALL show the frontend element routing `/api` requests to the product-service, inventory-service, cart-service, order-service, and auth-service.
3. THE Diagram SHALL show the order-service calling the inventory-service and the payment-service.
4. THE Diagram SHALL place the Microservices within the EKS_Cluster boundary in the `cloudcart` namespace.
5. THE Diagram SHALL show the Microservices reading and writing persistent data in the Amazon DynamoDB store.

### Requirement 4: Access Path and Persistence Security

**User Story:** As an Author, I want the public access path and the credential-free persistence path shown, so that the audience understands how users reach the UI and how Pods reach DynamoDB securely.

#### Acceptance Criteria

1. THE Diagram SHALL show the Frontend_Service as a Kubernetes Service of type LoadBalancer.
2. THE Diagram SHALL show the LoadBalancer as an AWS Elastic Load Balancer exposing a public DNS name.
3. WHEN a user accesses the UI, THE Diagram SHALL show the request path as Browser → LoadBalancer → Frontend_Service → frontend Pods.
4. THE Diagram SHALL show the Microservices accessing the Amazon DynamoDB store through EKS Pod_Identity using a scoped IAM role.
5. THE Diagram SHALL label the Pod_Identity path to indicate no access keys are stored in Kubernetes.

### Requirement 5: Visual Style and Presentation Compatibility

**User Story:** As an Author, I want the new diagram to match the existing diagrams, so that all diagrams look consistent when placed together in the Presentation.

#### Acceptance Criteria

1. THE Diagram SHALL be authored as a valid SVG file saved at `diagrams/architecture-flow.svg`.
2. THE Diagram SHALL use the Arial font family consistent with the Existing_Style.
3. THE Diagram SHALL use a canvas size within 10 percent of the 1400x760 dimensions used by the Existing_Style.
4. THE Diagram SHALL include a title label identifying it as the CloudCart end-to-end architecture.
5. WHEN the Diagram is opened in a standards-compliant SVG renderer, THE Diagram SHALL render all elements, connectors, and labels without overlap that obscures text.
6. WHERE the Author embeds the Diagram in the Presentation, THE Diagram SHALL scale without loss of clarity as a vector image.
