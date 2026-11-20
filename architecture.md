# Architecture

## AWS Infrastructure (Terraform)

```
VPC 10.0.0.0/16
├── AZ a
│   ├── public-1  10.0.1.0/24   → Jenkins EC2, NAT Gateway
│   └── private-1 10.0.11.0/24  → EKS worker node 1
└── AZ b
    ├── public-2  10.0.2.0/24
    └── private-2 10.0.12.0/24  → EKS worker node 2

Public route table  : 0.0.0.0/0 → Internet Gateway
Private route table : 0.0.0.0/0 → NAT Gateway
```

- **Network ACLs** are stateless, so return traffic (ports 1024-65535) is allowed explicitly.
- **Security Group** on Jenkins allows SSH (22) and the Jenkins UI (8080) from one IP only.
- **EKS**: the control plane is managed by AWS; worker nodes sit in the private subnets of two AZs and reach the internet through the NAT.
- **State** is stored in S3 (versioned, encrypted) with DynamoDB locking.

## Application on Kubernetes (namespace `ivolve`)

```
Ingress ──► frontend (x2) ──► auth-service ──► mysql-0 (StatefulSet + PVC)
                          └─► roadmap-service
```

| Object | Purpose |
|---|---|
| ConfigMap `ivolve-config` | non-secret settings (DB host, service URLs) |
| Secret `ivolve-secret` | DB credentials, session secret |
| StatefulSet `mysql` + headless Service | database with persistent storage |
| Deployments + ClusterIP Services | the three microservices |
| Ingress | HTTP entry point to the frontend |

## CI/CD Flow
1. A push triggers the Jenkins pipeline for the changed service.
2. Stages: Build → Scan (Trivy, fails on HIGH/CRITICAL) → Push to ECR → Delete local image → Update manifest tag → Push manifest to Git.
3. ArgoCD detects the Git change and syncs the cluster (automated, prune, self-heal).

## Configuration Management
Ansible discovers the Jenkins EC2 through the `aws_ec2` inventory plugin (tag `Role=jenkins`) and applies the roles `java`, `jenkins`, `docker`, `trivy`.
