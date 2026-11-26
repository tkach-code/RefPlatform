# RefPlatform

A reference hosting platform for many small, independent demo apps on one EKS cluster.

```
https://<generated>.cloudfront.net  ── CloudFront refplatform-cdn
   └─ ALB refplatform-alb (Ingress group "refplatform")
        ├─ /simple-cms*   → namespace simple-cms   (Next.js CMS + MongoDB)
        ├─ /empty-login*  → namespace empty-login
        ├─ /<app>*        → namespace <app>
        ├─ /*             → namespace index-app    (landing page)
        └─ anything else  → 404 "no route"
```

Each app has its own folder, namespace, image repository, Terraform state and GitHub workflow, and ships on its own.

| Folder | What |
|---|---|
| `apps/<app>/` | App source (one folder per app) |
| `terraform/s3-state/` | Bootstrap: state bucket `refplatform-tfstate-<account>` + GitHub OIDC roles (local state) |
| `terraform/eks/` | Platform: VPC, EKS `refplatform-eks`, ALB, CloudFront, ECR repos, Secrets Store CSI, SSM parameters |
| `terraform/modules/` | Shared modules: `web-app` (namespace, IRSA, secret, Deployment, Service, Ingress), `mongodb` |
| `terraform/apps/<app>/` | One small Terraform root per app |
| `.github/workflows/` | `app-<app>.yml` per app, `infra-eks.yml`, `apps-redeploy-all.yml`, reusable `_build-app.yml` / `_deploy-app.yml` |
| `doc/` | Plan, route registry and manual runbook |

## Start from zero

First time? Follow the step-by-step walkthrough in [doc/first-deployment.md](doc/first-deployment.md). The steps below are the short version.

1. **Bootstrap** (local, once): see [terraform/s3-state/README.md](terraform/s3-state/README.md).
   ```bash
   cd terraform/s3-state && cp terraform.tfvars.example terraform.tfvars   # set github_repository
   terraform init && terraform apply
   ```
2. **GitHub setup** (once):
   - Repository variable `AWS_ACCOUNT_ID` (12 digits). Optionally set `AWS_REGION` (default `eu-central-1`).
   - Environment `infra` with yourself as a required reviewer.
   - Environment `infra-plan`, with deployment branches limited to `main`.
   - No secrets are needed: the workflows assume `refplatform-gh-{build,deploy,infra}` through OIDC.
3. **Platform:** put your IAM ARN in `terraform/eks/terraform.tfvars`, then merge to `main` and approve `infra-eks`. Or run it locally:
   ```bash
   cd terraform/eks
   terraform init -backend-config="bucket=refplatform-tfstate-<account-id>"
   terraform apply
   ```
4. **Apps:** pushing to `main` under `apps/<app>/**` builds and deploys that app. Or run the `app-<app>` workflow manually.
   simple-cms ends up at `https://<cloudfront>/simple-cms/`. Seed its admin user once: [terraform/apps/README.md](terraform/apps/README.md#simple-cms-admin-user).

## Add an app

The full step-by-step guide (code, ECR, Terraform, secrets, workflow, verification, troubleshooting, removal) is [apps/new-app/README.md](apps/new-app/README.md). The short checklist is in [terraform/apps/README.md](terraform/apps/README.md#add-an-app), and the contract every app must follow is in [doc/multi-app-platform-plan.md](doc/multi-app-platform-plan.md) §5. In short:
- Serve under `/<app>`.
- Expose `GET /<app>/api/health`.
- Include a Dockerfile listening on port 3000.
- Register the app in `terraform/eks/apps.tf`.
- Copy a `terraform/apps/<app>` root and an `app-<app>.yml` workflow.

## Tear down

Apps first, then the platform, then the bootstrap. Steps are in [doc/readme.md](doc/readme.md#destroy-everything).
