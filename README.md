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
| `terraform/s3-state/` | Bootstrap: state bucket `refplatform-tfstate-<account>` + GitHub OIDC roles (applied by hand, its state is in the same bucket) |
| `terraform/eks/` | Platform: VPC, EKS `refplatform-eks`, ALB, CloudFront, ECR repos, Secrets Store CSI, SSM parameters |
| `terraform/modules/` | Shared modules: `web-app` (namespace, IRSA, secret, Deployment, Service, Ingress), `mongodb` |
| `terraform/apps/<app>/` | One small Terraform root per app |
| `.github/workflows/` | `app-<app>.yml` per app, `infra-eks.yml`, `apps-redeploy-all.yml`, reusable `_build-app.yml` / `_deploy-app.yml` |
| `doc/` | [Architecture](doc/architecture.md) (route registry, naming, app contract), [first deployment](doc/first-deployment.md), [runbook](doc/readme.md), [CI setup](doc/github-readme.md) |

## Start from zero

First time? Follow the step-by-step walkthrough in [doc/first-deployment.md](doc/first-deployment.md). The steps below are the short version.

1. **Bootstrap** (by hand, once per account): set `github_repository` in `terraform/s3-state/terraform.tfvars`, then follow [terraform/s3-state/README.md → First apply in a new account](terraform/s3-state/README.md#first-apply-in-a-new-account). The first apply runs on local state, which is then migrated into the new bucket.
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

## Work from another machine

All Terraform state is in S3 and CI is configured on GitHub and AWS, so a fresh clone has everything it needs. On the new machine:

1. **Tools:** Git (Git Bash on Windows), Terraform ≥ 1.10, AWS CLI v2, kubectl, Docker, Node.js, Python.
2. **GitHub:** clone the repo, with an SSH key for that machine added to your GitHub account (or HTTPS via `gh auth login`).
3. **AWS:** `aws configure` with credentials of an IAM principal listed in `cluster_admin_principal_arns` (`terraform/eks/terraform.tfvars`). To use a different principal, add it there and apply `terraform/eks` first.
4. **Shell:** in every terminal:
   ```bash
   export AWS_REGION=eu-central-1 MSYS_NO_PATHCONV=1
   export ACCT=$(aws sts get-caller-identity --query Account --output text)
   ```
5. **kubectl:** `aws eks update-kubeconfig --region eu-central-1 --name refplatform-eks`, then `kubectl get nodes`.
6. **Terraform:** in each root you work on (`terraform/s3-state`, `terraform/eks`, `terraform/apps/<app>`):
   ```bash
   terraform init -backend-config="bucket=refplatform-tfstate-$ACCT"
   terraform plan          # should say "No changes"
   ```
7. **Local app dev (optional):** for simple-cms, create `.env.local` from `apps/simple-cms/.env example` ([apps/simple-cms/README.md](apps/simple-cms/README.md#local-setup)).

## Add an app

The full step-by-step guide (code, ECR, Terraform, secrets, workflow, verification, troubleshooting, removal) is [apps/new-app/README.md](apps/new-app/README.md). The short checklist is in [terraform/apps/README.md](terraform/apps/README.md#add-an-app), and the contract every app must follow is in [doc/architecture.md](doc/architecture.md#5-app-contract-every-app-any-framework). In short:
- Serve under `/<app>`.
- Expose `GET /<app>/api/health`.
- Include a Dockerfile listening on port 3000.
- Register the app in `terraform/eks/apps.tf`.
- Copy a `terraform/apps/<app>` root and an `app-<app>.yml` workflow.

## Tear down

Apps first, then the platform, then the bootstrap. Steps are in [doc/readme.md](doc/readme.md#destroy-everything).
