# GitHub Actions setup

All AWS access uses **OIDC**, so there are no long-lived keys and no secrets in GitHub. The three IAM roles and the OIDC provider are created by `terraform/s3-state` (see [its README](../terraform/s3-state/README.md)). Workflows build each role ARN from the repository variable `AWS_ACCOUNT_ID`:

| Workflow | Role | Runs when |
|---|---|---|
| `app-<app>.yml` → `_build-app.yml` | `refplatform-gh-build` | push touching `apps/<app>/**` or `terraform/apps/<app>/**` (any branch), or a manual run |
| `app-<app>.yml` → `_deploy-app.yml` | `refplatform-gh-deploy` | after a successful build on `main`, or a manual run with `image_tag` (rollback) |
| `apps-redeploy-all.yml` | `refplatform-gh-deploy` | manual, `main`: re-apply every app with its current image |
| `infra-eks.yml` | `refplatform-gh-infra` | PR / push to `main` touching `terraform/eks/**`, or a manual run |

## One-time setup

1. Apply `terraform/s3-state` with `github_repository = "owner/repo"`. Set `create_github_oidc_provider = false` if the account already has the GitHub provider.
2. **Settings → Secrets and variables → Actions → Variables:**
   - `AWS_ACCOUNT_ID`: the 12-digit account (`terraform -chdir=terraform/s3-state output -raw account_id`).
   - `AWS_REGION` (optional, default `eu-central-1`).
3. **Settings → Environments:**
   - `infra`: add yourself as a required reviewer. Used for apply on `main` and for PR plans (PR code would otherwise run with admin rights unreviewed).
   - `infra-plan`: deployment branches = `main` only. Used for the automatic plan before apply.
4. Put your own IAM ARN in `terraform/eks/terraform.tfvars` → `cluster_admin_principal_arns`. The CI roles are added automatically.

## Flow per app

```
push apps/simple-cms/** ──► build: npm ci, lint, tsc, docker build, smoke test GET /simple-cms/api/health
                            push ECR refplatform/simple-cms:sha-<12>   (skipped if the tag exists)
        (main only) ──────► deploy: terraform apply in terraform/apps/simple-cms with that exact tag
```

- Deploy uses the image from the **same run** (`needs:`), so parallel builds of different apps can't mix up images.
- Deploys of one app are serialized (`concurrency: refplatform-deploy-<app>`). Different apps deploy in parallel.
- Rollback: **Actions → app-<app> → Run workflow** on `main`, with `image_tag = sha-…`. The last 15 `sha-` tags are kept.
- An app folder without a `Dockerfile` (still a placeholder) makes the build a no-op, and the deploy is skipped.
- Changes to `terraform/modules/**` don't trigger anything. Run **apps-redeploy-all**.

## Flow for the platform

`infra-eks.yml`: fmt check → init → validate → `plan -out` (shown in the job summary). On `main` with changes, the `apply` job waits for approval in `infra`, then applies that exact saved plan. Destroy is never run from CI.

## Troubleshooting

### `Not authorized to perform sts:AssumeRoleWithWebIdentity`
- `AWS_ACCOUNT_ID` must be the account where `terraform/s3-state` created the roles.
- `github_repository` must match exactly (`owner/name`, case-sensitive). The trust policy pins the `repository` claim.
- Deploy only works from `main`. Infra only works from jobs in Environments `infra` / `infra-plan`. Check the job's `environment:`.
- The trust policy uses `repo:OWNER*/REPO*:…` so both the classic and the `OWNER@id/REPO@id` subject formats match.
- CloudTrail → `AssumeRoleWithWebIdentity` shows the rejected subject claim.

### Terraform can call AWS but not the cluster (`Unauthorized`, `the server has asked for the client to provide credentials`)
The role has no EKS access entry. Apply `terraform/eks` with `github_ci_roles_enabled = true` (the default).

### Build fails with `RepositoryNotFoundException`
The app isn't in `terraform/eks/apps.tf` yet, or `infra-eks` hasn't been applied since it was added.

### Pods never become ready / ALB returns 502
The app's health path is wrong or not under its base path. `health_path` in `terraform/apps/<app>/main.tf` must return 200 at the full path (e.g. `/simple-cms/api/health`). The ALB target group health check uses the same path.
