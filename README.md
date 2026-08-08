# Scoops

## Kubernetes

### 1. Create a namespace

```bash
kubectl create ns scoops
```

### 2. Create secret to pull private images (skip if public)

```bash
kubectl create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username=<your-username> \
  --docker-password=<your-PAT-with-read:packages> \
  --docker-email=<any-email>
```

### 3. Use kustomize to apply the overlays
```bash
kubectl kustomize manifests/overlays/dev
k apply -k manifests/overlays/dev
```