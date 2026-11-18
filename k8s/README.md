# Kubernetes manifests

Everything needed to run the iVolve stack on Kubernetes (tested on a local
[kind](https://kind.sigs.k8s.io/) cluster named `ivolve`).

```
k8s/
├── namespace.yaml          # namespace "ivolve"
├── configmap.yaml          # non-secret env: DB_HOST, DB_NAME, service URLs
├── secret.example.yaml     # template for credentials (secret.yaml is git-ignored)
├── storageclass.yaml       # local-path SC; on EKS use ebs.csi.aws.com
├── mysql-service.yaml      # headless service (clusterIP: None) for the StatefulSet
├── mysql-statefulset.yaml  # MySQL 8 + PVC 1Gi
├── auth-deployment.yaml    # Flask auth service  :5000  (+ Service)
├── roadmap-deployment.yaml # Spring roadmap svc :8080  (+ Service)
├── frontend-deployment.yaml# Next.js frontend   :3000  (+ Service, 2 replicas)
├── ingress.yaml            # nginx Ingress → frontend
└── kustomization.yaml      # apply everything with one command
```

`kind/kind-config.yaml` lives outside this folder on purpose: it configures the
cluster itself (`kind: Cluster`), it is not a Kubernetes manifest.

## 1. Create the cluster (once)

```bash
kind create cluster --config kind/kind-config.yaml --name ivolve
```

It maps host ports 80/443 into the node and labels the node
`ingress-ready=true`, which is what the ingress controller needs.

## 2. Install the ingress controller (once)

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait -n ingress-nginx --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=300s
```

If the controller stays in `ContainerCreating` / `ImagePullBackOff`, see
[Troubleshooting](#troubleshooting).

## 3. Build the images and load them into the cluster

kind nodes cannot pull images that only exist on your machine, so every local
image has to be side-loaded:

```bash
docker build -t ivolve-auth-service:latest    ./auth-service
docker build -t ivolve-roadmap-service:latest ./roadmap-service
docker build -t ivolve-frontend:latest        ./frontend

kind load docker-image ivolve-auth-service:latest    --name ivolve
kind load docker-image ivolve-roadmap-service:latest --name ivolve
kind load docker-image ivolve-frontend:latest        --name ivolve
```

> `kind load` fails on image references that contain a digest
> (`content digest ... not found`). Load by tag and point the workload at the tag.

## 4. Apply

```bash
# 1) credentials — real file, never committed
cp k8s/secret.example.yaml k8s/secret.yaml
$EDITOR k8s/secret.yaml
kubectl apply -f k8s/secret.yaml

# 2) everything else
kubectl apply -k k8s/
```

`kubectl apply -k k8s/` (kustomize) is used instead of `-f k8s/` because the
folder contains `kustomization.yaml`, which is not an object Kubernetes can
create by itself.

The Ingress is part of the kustomization, so the controller from step 2 must be
`Ready` before this command — otherwise you get
`failed calling webhook "validate.nginx.ingress.kubernetes.io": connection refused`.
If that happens, wait for the controller and just re-run the same command.

## 5. Verify

```bash
kubectl get pods,pvc,svc,ingress -n ivolve
kubectl rollout status deploy/frontend -n ivolve
```

Expected: `mysql-0` 1/1 Running with its PVC `Bound`, one `auth-service` pod,
one `roadmap-service` pod, two `frontend` pods, and the Ingress with an address.

Then open the app:

```bash
curl -I http://localhost/
```

No `host:` is set in `ingress.yaml` on purpose, so the rule matches any
hostname or bare IP — the app answers directly on `http://localhost/` without
editing a hosts file.

## Access without an ingress controller

Useful for a quick check or when ingress is broken:

```bash
kubectl port-forward -n ivolve svc/frontend 8080:3000
# → http://localhost:8080
```

## Troubleshooting

**`no matches for kind "Cluster" in version "kind.x-k8s.io/v1alpha4"`**
You ran `kubectl apply` on `kind-config.yaml`. That file is for `kind create
cluster`, not for `kubectl`.

**Controller stuck in `ContainerCreating`, event `FailedMount ... secret
"ingress-nginx-admission" not found`**
The admission jobs that generate that secret are missing. `kubectl apply` does
not recreate deleted resources, so re-apply the full manifest:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait -n ingress-nginx --for=condition=complete job --all --timeout=300s
```

**Images cannot be pulled inside the kind node after the host DNS changed**
The node keeps its own `/etc/resolv.conf`, generated when the cluster was
created, so a stale/broken DNS server survives there:

```bash
docker exec ivolve-control-plane cat /etc/resolv.conf
docker exec ivolve-control-plane sh -c 'printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf'
```

**`kubectl delete ns ivolve` finishes but the PV stays around**
`storageclass.yaml` uses `reclaimPolicy: Retain` on purpose (a deleted PVC must
not silently delete data). Clean up by hand if you really want the space:

```bash
kubectl get pv
kubectl delete pv <name>
```

**Pods stay `Pending` after recreating the cluster**
The images were loaded into the old node. Repeat step 3.

## Moving to EKS

Three things change, everything else is identical:

| item | kind | EKS |
|---|---|---|
| `storageClassName` | `ivolve-storage` (local-path) | `gp2`/`ebs.csi.aws.com` |
| images | side-loaded with `kind load` | pushed to ECR and pulled by the node |
| `imagePullPolicy` | `IfNotPresent` | `IfNotPresent` (works because ECR tags are immutable per commit) |

A kustomize `base/` + `overlays/kind` + `overlays/eks` split is the next step so
those three differences do not turn into a second copy of the manifests.
