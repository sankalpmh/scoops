# Scoops

Scoops is a static ice-cream storefront built with HTML, CSS and JavaScript. It is containerized with Nginx and currently deployed to Google Cloud Run.

## Deployment architecture

The primary deployment path uses GitHub Actions and Google Cloud:

```text
GitHub (main branch)
        |
        v
GitHub Actions
  - Authenticate to Google Cloud using OIDC / Workload Identity Federation
  - Build the Docker image
        |
        v
Artifact Registry
        |
        v
Cloud Run (asia-south1)
```

The GitHub Actions workflow is `.github/workflows/build.yaml`.

## Application and container

- Static website files: HTML, CSS, JavaScript and images.
- Web server: Nginx on Alpine Linux.
- Container port: 80.
- The Dockerfile runs `apk upgrade --no-cache` during the image build to apply available Alpine package updates.
- The `.dockerignore` file excludes GitHub workflow files, Kubernetes manifests, Markdown files and temporary GitHub OIDC credential files from the Docker build context.

### Run locally with Python

From the repository root:

```powershell
python -m http.server 8080
```

Open http://localhost:8080.

### Build and run the container locally

```powershell
docker build -t scoops:local .
docker run --rm -p 8080:80 scoops:local
```

Open http://localhost:8080.

## Google Cloud deployment

| Setting | Value |
|---|---|
| Google Cloud project | `project-1d7cad77-567e-48ed-b75` |
| Region | `asia-south1` (Mumbai) |
| Artifact Registry repository | `scoops-repo` |
| Image name | `scoops` |
| Cloud Run service | `scoops` |
| Runtime service account | `scoops-cloudrun-runtime@project-1d7cad77-567e-48ed-b75.iam.gserviceaccount.com` |
| Container port | `80` |
| CPU | `1` |
| Memory | `256Mi` |
| Minimum instances | `0` |
| Maximum instances | `1` |

Cloud Run can scale the service to zero when it is idle. Artifact Registry image storage is billed separately from Cloud Run usage.

To print the current service URL:

```powershell
gcloud run services describe scoops `
  --project=project-1d7cad77-567e-48ed-b75 `
  --region=asia-south1 `
  --format="value(status.url)"
```

### Public access

The service is configured for public access using the Cloud Run Invoker IAM check setting. This was configured separately from the GitHub deployment identity:

```powershell
gcloud run services update scoops `
  --project=project-1d7cad77-567e-48ed-b75 `
  --region=asia-south1 `
  --no-invoker-iam-check
```

The GitHub deployment service account is not granted permission to change Cloud Run IAM policies. If the Cloud Run service is deleted and recreated, an administrator must configure public access again.

## GitHub Actions CI/CD

Workflow: `.github/workflows/build.yaml`

### Triggers

- Automatically runs when code is pushed to `main`.
- Supports manual execution through `workflow_dispatch` in the GitHub Actions tab.
- Pushes that only change `docs/**`, Markdown files, `manifests/**`, `.github/**` or `.gitignore` do not trigger a deployment.

### Pipeline stages

1. Check out the repository.
2. Authenticate to Google Cloud using GitHub OIDC and Workload Identity Federation.
3. Configure Docker authentication for Artifact Registry.
4. Build the image from the repository Dockerfile.
5. Push two image tags to Artifact Registry:
   - The full Git commit SHA.
   - `latest`.
6. Deploy the commit-SHA image to Cloud Run.
7. Print the Cloud Run service URL.

The Cloud Run deployment uses the commit-SHA image tag so that each deployment refers to a specific source revision.

### GitHub repository secrets

Configure these under **Settings → Secrets and variables → Actions → Repository secrets**:

| Secret | Value |
|---|---|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/215616534003/locations/global/workloadIdentityPools/scoops-github-pool/providers/scoops-github-provider` |
| `GCP_DEPLOY_SERVICE_ACCOUNT` | `scoops-github-deploy@project-1d7cad77-567e-48ed-b75.iam.gserviceaccount.com` |

No service-account JSON key is used or required.

### Workload Identity Federation configuration

The GitHub Actions workflow authenticates through Google Cloud Workload Identity Federation.

| Setting | Value |
|---|---|
| Workload Identity Pool | `scoops-github-pool` |
| OIDC Provider | `scoops-github-provider` |
| OIDC issuer | `https://token.actions.githubusercontent.com/` |
| GitHub repository | `sankalpmh/scoops` |
| GitHub repository ID | `1471870931` |
| Allowed branch | `refs/heads/main` |

The provider maps the GitHub repository ID to `attribute.repository_id` and checks both the repository ID and branch in its attribute condition.

### Google Cloud identities and IAM

Two service accounts are used for separation of duties:

| Service account | Purpose |
|---|---|
| `scoops-github-deploy@project-1d7cad77-567e-48ed-b75.iam.gserviceaccount.com` | Used by GitHub Actions to push the image and deploy Cloud Run |
| `scoops-cloudrun-runtime@project-1d7cad77-567e-48ed-b75.iam.gserviceaccount.com` | Identity used by the running Cloud Run container |

The deployment service account has these permissions:

| IAM role | Scope | Purpose |
|---|---|---|
| `roles/iam.workloadIdentityUser` | On the deployment service account | Allows the trusted GitHub repository identity to impersonate it |
| `roles/artifactregistry.writer` | `scoops-repo` repository | Push container images |
| `roles/run.developer` | Project | Create and update Cloud Run services |
| `roles/iam.serviceAccountUser` | On the runtime service account | Attach the runtime identity to Cloud Run |

The runtime service account has no additional API roles because this static website does not need to access other Google Cloud services.

## Deploy manually with gcloud

The GitHub Actions workflow is the normal deployment path. For a manual deployment, authenticate with the Google Cloud CLI and run these commands in PowerShell:

```powershell
$PROJECT_ID = "project-1d7cad77-567e-48ed-b75"
$REGION = "asia-south1"
$IMAGE = "$REGION-docker.pkg.dev/$PROJECT_ID/scoops-repo/scoops:manual"

gcloud config set project $PROJECT_ID
gcloud auth configure-docker "$REGION-docker.pkg.dev"

docker build --pull -t $IMAGE .
docker push $IMAGE

gcloud run deploy scoops `
  --image $IMAGE `
  --project=$PROJECT_ID `
  --region=$REGION `
  --platform=managed `
  --service-account="scoops-cloudrun-runtime@$PROJECT_ID.iam.gserviceaccount.com" `
  --port=80 `
  --cpu=1 `
  --memory=256Mi `
  --min=0 `
  --max=1
```

## Kubernetes manifests (alternative path)

Kubernetes manifests are retained under `manifests/` for a separate Kubernetes deployment or lab.

- `manifests/base`: base Deployment, Service and HTTPRoute resources.
- `manifests/overlays/dev`: one replica and NodePort configuration.
- `manifests/overlays/prod`: three replicas.

Apply the development overlay:

```bash
kubectl create namespace scoops
kubectl apply -k manifests/overlays/dev
```

The current base Deployment references an image in GitHub Container Registry (`ghcr.io/shoaib720/scoops`) and an image pull secret named `ghcr-pull-secret`. This Kubernetes manifest path is separate from the current GitHub Actions pipeline, which publishes to Google Artifact Registry and deploys to Cloud Run. Update the manifest image reference and configure registry access before using the GCP-built image with a Kubernetes cluster.

## Repository structure

```text
.
├── .github/
│   └── workflows/
│       └── build.yaml
├── assets/
├── js/
├── pages/
├── styles/
├── manifests/
│   ├── base/
│   └── overlays/
│       ├── dev/
│       └── prod/
├── Dockerfile
├── .dockerignore
└── index.html
```
