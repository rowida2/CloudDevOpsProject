# iVolve — End-to-End DevOps Project Documentation

Final project for the NTI DevOps track in collaboration with iVolve Technologies.
This document describes the **whole delivery stack**, not just the application:
containers, infrastructure as code, configuration management, Kubernetes, CI,
and GitOps. The application itself is deliberately small — it exists to give the
pipeline something real to deploy.

> Status: reflects the repository at `ca67c5e`. The local Kubernetes cluster is
> `kind` with a single control-plane node, named `ivolve`.

---

## 1. Overview

### 1.1 What the application does

1. A visitor opens the frontend on port `3000` and signs up or logs in.
2. The frontend calls the **auth-service** (Python/Flask) over HTTP on `5000`.
3. The auth-service hashes/checks credentials against **MySQL 8**.
4. On success a session cookie is set and the browser is redirected to
   `/roadmap`, which renders data from the **roadmap-service** (Java/Spring,
   port `8080`).

The browser never talks to MySQL or to the backends directly — the frontend is
the only entry point.

### 1.2 The delivery pipeline

```text
  developer push
       │
       ▼
  GitHub  ──────────────► Jenkins (EC2, installed by Ansible)
       │                       │
       │                       ├─ build image (BUILD_NUMBER tag)
       │                       ├─ Trivy scan
       │                       ├─ push to ECR
       │                       └─ update image tag in k8s/ + push commit
       ▼
  GitHub (main)  ───────► ArgoCD Application
                              │
                              ├─ kustomize build k8s/
                              └─ sync → kind / EKS namespace "ivolve"
```

Infrastructure is created with Terraform; the Jenkins host is configured by
Ansible; Kubernetes manifests are the single source of truth for the workload.

---

## 2. Stage 1 — Docker and Docker Compose

### 2.1 Services

| Service | Stack | Port | Notes |
|---|---|---|---|
| `frontend` | Node.js 22, Express 5, EJS | 3000 | public entry point, sessions |
| `auth-service` | Python 3.12, Flask 3.1, bcrypt | 5000 | `/health`, `/api/auth/signup`, `/api/auth/login` |
| `roadmap-service` | Java 21, Spring Boot 3.5, Maven | 8080 | `/api/roadmap` |
| `mysql` | MySQL 8.0 | 3306 | database `ivolve`, named volume `mysql-data` |

All four run on one bridge network (`ivolve-net`). Only port `3000` is published
to the host.

### 2.2 Image build choices

- **`frontend`** — `node:22-alpine`, `npm ci`, runs as the built-in `node` user.
- **`auth-service`** — `python:3.12-slim`, dedicated `appuser`, dependencies
  installed before copying source so the layer stays cached.
- **`roadmap-service`** — multi-stage: Maven builds the jar, a slim
  `eclipse-temurin` JRE runs it. The builder and its ~100 MB of Maven cache
  never reach the final image.
- `.dockerignore` files in every service keep local junk and Git metadata out of
  the build context.
- Health checks are defined for MySQL and both backends; `make health` probes
  all three.

### 2.3 Local workflow

```bash
cp .env.example .env            # real values stay local (.env is git-ignored)
make up                         # docker compose up -d --build
make ps                         # status + health
make logs                       # follow all logs
make down                       # stop, keep the DB volume
make reset                      # stop AND delete the DB volume (destructive)
```

See `README.md` for environment variables, routes and image sizes.

---

## 3. Stage 2 — Terraform (AWS infrastructure)

### 3.1 Layout

```text
terraform/
├── bootstrap/main.tf      # S3 state bucket + DynamoDB lock table (local state)
├── main.tf                # providers, S3 backend, module wiring
├── variables.tf
├── outputs.tf
└── modules/
    ├── network/           # VPC, 2 public + 2 private subnets, IGW, NAT
    ├── ecr/               # 3 repositories: frontend, auth-service, roadmap-service
    ├── server/            # Jenkins EC2 + security group
    └── eks/               # EKS control plane, managed node group, EBS CSI addon
```

### 3.2 Why two states

`bootstrap` creates the S3 bucket and the DynamoDB lock table. It cannot store
**its own** state in the bucket it is creating, so it uses a local `tfstate`.
The root configuration then uses:

```hcl
backend "s3" {
  bucket         = "ivolve-tfstate-CHANGE-ME"
  key            = "cloud-devops/terraform.tfstate"
  region         = "eu-central-1"
  dynamodb_table = "ivolve-tf-lock"
  encrypt        = true
}
```

Order of operations: `terraform init && terraform apply` in `bootstrap/`, then
`terraform init && terraform apply` in `terraform/`.

### 3.3 Outputs

| Output | Meaning |
|---|---|
| `ecr_urls` | the three ECR repository URLs Jenkins pushes to |
| `jenkins_public_ip` | where Ansible connects and where the Jenkins UI lives |
| `eks_cluster_name` | cluster name used in `aws eks update-kubeconfig` |

### 3.4 Before applying in AWS Academy Learner Lab

These are **configuration placeholders/gaps**, not tested production settings:

- `region` is `eu-central-1` in `variables.tf`, `main.tf`, `bootstrap` and the
  Jenkinsfiles. Learner Lab only supports a limited set of regions (typically
  `us-east-1` / `us-west-2`) — change them consistently first.
- `ami_id` is a placeholder and `key_name` must be an existing EC2 key pair.
- `allowed_ssh_cidr` defaults to `0.0.0.0/0`; restrict it to your own `/32`.
- The `eks` module creates IAM roles. Learner Lab does not allow role creation:
  switch it to the pre-existing `LabRole` / `LabInstanceProfile`.
- Never commit AWS credentials. The lab credentials are temporary and must be
  exported only into the current shell.
- No paid resource should be created without agreeing on the cost first.

---

## 4. Stage 3 — Ansible (Jenkins host configuration)

### 4.1 Inventory

`ansible/inventory/aws_ec2.yml` is a **dynamic inventory** using
`amazon.aws.aws_ec2`. It selects running EC2 instances tagged `Role=jenkins`
and uses their public IP as the hostname, so no static IP list is maintained.

```bash
cd ansible
ansible-inventory -i inventory/aws_ec2.yml --list    # preview discovered hosts
ansible-playbook site.yml                            # configure them
```

`ansible.cfg` sets `remote_user = ubuntu`, disables host key checking, and uses
`~/.ssh/ivolve-key.pem`.

### 4.2 Roles

| Role | Responsibility |
|---|---|
| `java` | Java 17 (required by the Jenkins war) |
| `jenkins` | apt key + repo, install, enable and start the service |
| `docker` | Docker Engine + Compose plugin, add `ubuntu` to the `docker` group |
| `trivy` | vulnerability scanner used by the Jenkins `Scan Image` stage |

`site.yml` runs them in that order against `hosts: all` with `become: true`.

> Known ordering issue: in `roles/jenkins/tasks/main.yml` the apt repository is
> added **before** its GPG key task. The key task should come first. Also,
> when running from a world-writable mount such as `/mnt/d`, Ansible ignores
> `ansible.cfg` — run from `~/CloudDevOpsProject/ansible` instead.

---

## 5. Stage 4 — Kubernetes

### 5.1 Cluster

Local development uses a `kind` cluster named `ivolve` with one control-plane
node. `kind/kind-config.yaml` publishes host ports `80`/`443` and labels the
node `ingress-ready=true`.

```bash
kind create cluster --config kind/kind-config.yaml --name ivolve
```

### 5.2 Workloads

| Object | Purpose |
|---|---|
| `Namespace ivolve` | all application resources |
| `ConfigMap ivolve-config` | non-secret config: DB host/port/name, service URLs |
| `Secret ivolve-secret` | credentials — **real file is git-ignored** |
| `StorageClass ivolve-storage` | `rancher.io/local-path`, `Retain` |
| `Service mysql` + `StatefulSet mysql` | headless service, 1 replica, PVC 1Gi |
| `Deployment/Service auth-service` | Flask, `:5000`, 1 replica |
| `Deployment/Service roadmap-service` | Spring, `:8080`, 1 replica |
| `Deployment/Service frontend` | Node, `:3000`, 2 replicas |
| `Ingress ivolve` | nginx class,Prefix `/` → frontend, no `host:` rule |
| `kustomization.yaml` | single apply entry point for all of the above |

Every workload has `imagePullPolicy: IfNotPresent`; the backends and frontend
also have readiness and liveness probes. MySQL has a readiness probe only.

### 5.3 Deploy

Local images have to be side-loaded into the kind node — the node cannot pull
images that exist only on your machine:

```bash
docker build -t ivolve-auth-service:latest    ./auth-service
docker build -t ivolve-roadmap-service:latest ./roadmap-service
docker build -t ivolve-frontend:latest        ./frontend

for img in ivolve-auth-service ivolve-roadmap-service ivolve-frontend; do
  kind load docker-image "$img:latest" --name ivolve
done

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
cp k8s/secret.example.yaml k8s/secret.yaml   # then fill in real values
kubectl apply -f k8s/secret.yaml
kubectl apply -k k8s/
```

`kubectl apply -k` is required because the directory contains
`kustomization.yaml`. The Ingress needs the ingress controller to be `Ready`
before it can be created (the admission webhook must be reachable).

For full step-by-step instructions and the troubleshooting cases that actually
happened during development, see `k8s/README.md`.

### 5.4 Secrets

`k8s/secret.example.yaml` contains placeholders only. The real
`k8s/secret.yaml` is listed in `.gitignore` and must never be committed. ArgoCD
therefore cannot recreate it from Git — create it once on each new cluster.
For a fully GitOps-managed solution the next step would be Sealed Secrets or
SOPS-encrypted manifests.

---

## 6. Stage 5 — Jenkins CI

### 6.1 Pipelines

Three Jenkinsfiles, one per microservice: `jenkins/<service>/Jenkinsfile`.
They share a library registered in Jenkins as `ivolve-shared-lib`:

```groovy
@Library('ivolve-shared-lib') _
```

### 6.2 Stages

| Stage | Shared step | What it does |
|---|---|---|
| Build Image | `buildImage` | `docker build -t <service>:<BUILD_NUMBER> ./<service>` |
| Scan Image | `scanImage` | Trivy vulnerability scan |
| Push Image | `pushImage` | ECR login, tag, push |
| Delete Image | `deleteImage` | removes the local image after push |
| Update Manifests | `updateManifests` | `sed` the `image:` line in `k8s/<service>-deployment.yaml` to the ECR tag |
| Push Manifests | `pushManifests` | commits and pushes that change back to `main` |

Using `BUILD_NUMBER` as the image tag makes each deployment immutable and
traceable to a Jenkins build — much better than `:latest`.

> Before running: replace `<ACCOUNT_ID>` and the region in every Jenkinsfile,
> and configure the ECR credentials/Jenkins credentials binding. The
> `deleteImage` step must not remove an image that a subsequent stage still
> needs.

---

## 7. Stage 6 — ArgoCD GitOps

### 7.1 Application

`argocd/application.yaml` defines the ArgoCD `Application`:

```yaml
source:
  repoURL: https://github.com/rowida2/CloudDevOpsProject.git
  targetRevision: main
  path: k8s
destination:
  server: https://kubernetes.default.svc
  namespace: ivolve
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
```

Because `k8s/` contains a `kustomization.yaml`, ArgoCD uses `kustomize build`
automatically; the `directory.exclude` entry is a leftover from the flat-file
days and is not what keeps `secret.yaml` out — the kustomization simply never
lists it.

### 7.2 The loop

1. Jenkins pushes a commit with a new ECR image tag.
2. ArgoCD detects the new revision on `main`.
3. It renders `k8s/` with kustomize and compares it with the cluster.
4. With `selfHeal: true` it reverts manual drift; with `prune: true` it removes
   resources it manages that disappeared from Git.

Install ArgoCD and create the Application:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f argocd/application.yaml
kubectl get application -n argocd
kubectl port-forward -n argocd svc/argocd-server 8080:80
# initial password:
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

> On a kind node with slow/broken DNS the `quay.io/argoproj/argocd` image may
> need to be pulled on the host and side-loaded with `kind load docker-image`.
> The same applies to the ingress controller image.

---

## 8. Verification checklist

| Layer | Command | Expected |
|---|---|---|
| Compose | `make health` | 200 for frontend, healthy for auth/roadmap |
| Terraform | `terraform validate` | no errors (after filling the placeholders) |
| Ansible | `ansible-playbook --syntax-check site.yml` | no errors |
| Kubernetes | `kubectl get pods,pvc -n ivolve` | 5 Running pods, PVC `Bound` |
| Ingress | `curl -I http://localhost/` | `200 OK` |
| Jenkins | open `http://<jenkins-ip>:8080` | login page |
| ArgoCD | `kubectl get app -n argocd` | `ivolve-app` — `Healthy`, `Synced` |

---

## 9. Known limitations / next improvements

These are deliberately documented rather than hidden — they are good discussion
material for the final presentation:

1. **AWS Academy limitations** — region, AMI, key pair and IAM role placeholders
   described in §3.4 must be adapted before any `terraform apply`.
2. **Secrets** — a manually created `Secret` is not managed by GitOps. Use
   Sealed Secrets / SOPS / an external secrets operator in a real setup.
3. **Resource requests/limits** — currently none. Add them so the scheduler can
   place pods and so one container cannot starve the node.
4. **Security contexts** — images run as non-root, but the manifests do not
   enforce `runAsNonRoot`, `allowPrivilegeEscalation: false` or
   `capabilities.drop: [ALL]`.
5. **Probes** — add a `startupProbe` for MySQL's slow first init and a liveness
   probe for the frontend.
6. **Scheduling** — both frontend replicas can land on the same node; add
   topology spread or pod anti-affinity before moving to a multi-node EKS cluster.
7. **Kustomize overlays** — split `base/` + `overlays/kind` + `overlays/eks` so
   the image registry, storage class and replica count differ by three lines
   instead of a second copy of every manifest.
8. **DNS in kind** — if the host DNS changes after the cluster is created, the
   node keeps the old resolver. Fix it with:
   ```bash
   docker exec ivolve-control-plane sh -c \
     'printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf'
   ```
9. **Local-only material** — `docs/learning/`, `scripts/` and PDFs are kept on
   this machine via `.gitignore`; the public repository contains code and
   deliverables only.

---

## 10. Repository map

```text
.
├── README.md                 # app + Docker quick start (the entry document)
├── docs/PROJECT.md           # this document — the full stack
├── docker-compose.yml
├── Makefile
├── .env.example
├── frontend/ auth-service/ roadmap-service/    # source + Dockerfiles
├── terraform/                # bootstrap + root + modules
├── ansible/                  # dynamic inventory + roles
├── jenkins/                  # 3 Jenkinsfiles + shared library steps
├── k8s/                      # manifests + kustomization + README
├── kind/kind-config.yaml     # cluster definition (not a k8s manifest)
└── argocd/application.yaml   # GitOps Application
```
