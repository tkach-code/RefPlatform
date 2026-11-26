# GitHub Actions setup

All AWS access uses **OIDC**, so there are no long-lived keys and no secrets in GitHub. The three IAM roles and the OIDC provider are created by `terraform/s3-state` (see [its README](../terraform/s3-state/README.md)). Workflows build each role ARN from the repository variable `AWS_ACCOUNT_ID`:

| Workflow | Role | Runs when |
|---|---|---|
| `app-<app>.yml` → `_build-app.yml` | `refplatform-gh-build` | push touching `apps/<app>/**` or `terraform/apps/<app>/**` (any branch), or a manual run |
| `app-<app>.yml` → `_deploy-app.yml` | `refplatform-gh-deploy` | after a successful build on `main`, or a manual run with `image_tag` (rollback) |
| `apps-redeploy-all.yml` | `refplatform-gh-deploy` | manual, `main`: re-apply every app with its current image |
| `infra-eks.yml` | `refplatform-gh-infra` | PR / push to `main` touching `terraform/eks/**`, or a manual run |

## One-time setup

Do these steps in order. Steps 1–3 are on AWS and in the repo. Steps 4–5 are in the GitHub web UI and need admin rights on the repo.

### 1. Check that nothing secret gets pushed

The nested `.gitignore` files (`apps/simple-cms/`, `terraform/*/`) keep out `.env`, `.mongo-memory-uri`, `terraform.tfstate*`, `.terraform/` and `.helm/`. Before the first push, check what is about to go out:

```bash
git status --porcelain -uall                       # nothing unexpected staged
git log origin/main..HEAD --name-only --format=   | grep -iE 'tfstate|\.env$|\.terraform/|\.pem|kubeconfig'   # must print nothing
```

The committed `terraform.tfvars` files hold no secrets. They do contain your account ID and admin IAM ARN, which become public if the repo is public.

### 2. The CI roles must trust this repo (`terraform/s3-state`)

Set `github_repository = "owner/repo"` in `terraform/s3-state/terraform.tfvars`. It is case-sensitive and must match the GitHub URL. Set `create_github_oidc_provider = false` if the account already has the `token.actions.githubusercontent.com` provider. Then:

```bash
cd terraform/s3-state && terraform plan && terraform apply   # "No changes" is fine if it was applied with this value already
```

Check the live trust policy. It must name your repo, not `OWNER/REPO`:

```bash
aws iam get-role --role-name refplatform-gh-build \
  --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition' --output json
```

### 3. The CI roles must have cluster access (`terraform/eks`)

`terraform/eks/terraform.tfvars` must contain:

```hcl
cluster_admin_principal_arns = ["arn:aws:iam::<acct>:user/<you>"]   # keeps your kubectl access when CI applies
github_ci_roles_enabled      = true                                 # access entries for refplatform-gh-deploy / -infra
```

Run `terraform plan` / `apply` in `terraform/eks`, and **commit the tfvars before any CI run of `infra-eks`**. CI applies the committed file. If it still says `false`, the first `infra-eks` apply removes the CI roles' cluster access, and every app deploy after that fails. Check:

```bash
aws eks list-access-entries --cluster-name refplatform-eks --output text   # must list refplatform-gh-deploy and refplatform-gh-infra
```

(`refplatform-gh-build` only pushes to ECR and needs no cluster access.)

### 4. Repository variables

**Settings → Secrets and variables → Actions → Variables tab** (not Secrets) → **New repository variable**:

| Name | Value |
|---|---|
| `AWS_ACCOUNT_ID` | the 12-digit account (`terraform -chdir=terraform/s3-state output -raw account_id`) |
| `AWS_REGION` | optional, default `eu-central-1` |

No secrets are needed. The roles are assumed through OIDC.

### 5. Environments

Names must match exactly. The `refplatform-gh-infra` trust policy only accepts `environment:infra` and `environment:infra-plan`.

**Settings → Environments → New environment**:

- **`infra`**: tick **Required reviewers**, add yourself, **Save protection rules**. Leave deployment branches at **No restriction**, because PR plans also run here. Used for apply on `main` and for PR plans (PR code would otherwise run with admin rights unreviewed).
- **`infra-plan`**: no reviewers. **Deployment branches and tags → Selected branches and tags → Add rule → `main`**. Used for the automatic plan before apply.

### 6. First run

- If you push before steps 2–5 are done, the app workflows triggered by the push fail at the AWS login. Nothing gets built or deployed, so this is harmless. Re-run them afterwards.
- A push that only touches `terraform/eks/**` runs `infra-eks` but **no app workflow**. To deploy the apps for the first time from CI, go to **Actions → app-&lt;app&gt; → Run workflow**, choose branch `main` and leave `image_tag` empty, once for each app.
- `infra-eks` on `main`: the `plan` job (in `infra-plan`) runs by itself. The `apply` job waits under **Review deployments** until you approve it in `infra`.

### 7. Verify that CI actually deployed

A green run is not proof that the app was deployed. Check that the image built from your commit is the one running:

```bash
TAG=sha-$(git rev-parse --short=12 origin/main)
for a in simple-cms empty-login index-app; do
  aws ecr describe-images --repository-name refplatform/$a --image-ids imageTag=$TAG --query 'imageDetails[0].imagePushedAt' --output text
  kubectl get deploy $a -n $a -o jsonpath='{.spec.template.spec.containers[0].image}{" ready="}{.status.readyReplicas}/{.spec.replicas}{"\n"}'
done
CF=$(aws cloudfront list-distributions --query 'DistributionList.Items[0].DomainName' --output text)
for p in api/health simple-cms/api/health empty-login/api/health; do curl -s -o /dev/null -w "/$p %{http_code}\n" https://$CF/$p; done
```

The tag only matches if `origin/main`'s last commit triggered that app's build. Otherwise, compare against the run's tag in the build job summary.

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
- New app: ECR registration in `infra-eks` first, then the app and its workflow in a second merge. See [apps/new-app/README.md](../apps/new-app/README.md).

## Flow for the platform

`infra-eks.yml`: fmt check → init → validate → `plan -out` (shown in the job summary). On `main` with changes, the `apply` job waits for approval in `infra`, then applies that exact saved plan. Destroy is never run from CI.

## Troubleshooting

### `Not authorized to perform sts:AssumeRoleWithWebIdentity`
- `AWS_ACCOUNT_ID` must be the account where `terraform/s3-state` created the roles.
- `github_repository` must match exactly (`owner/name`, case-sensitive). The trust policy pins the `repository` claim.
- Deploy only works from `main`. Infra only works from jobs in Environments `infra` / `infra-plan`. Check the job's `environment:`.
- The trust policy uses `repo:OWNER*/REPO*:…` so both the classic and the `OWNER@id/REPO@id` subject formats match.
- CloudTrail → `AssumeRoleWithWebIdentity` shows the rejected subject claim.

- The live trust policy still says `OWNER/REPO` → `terraform/s3-state` was applied before `github_repository` was set. Set it and apply again (step 2).

### Terraform can call AWS but not the cluster (`Unauthorized`, `the server has asked for the client to provide credentials`)
The role has no EKS access entry. Apply `terraform/eks` with `github_ci_roles_enabled = true` (the default), and make sure the **committed** `terraform/eks/terraform.tfvars` says `true` as well. Otherwise the next `infra-eks` apply removes the entry again.

### Runs are green, but the cluster still runs the old image
The app workflows didn't run for that commit (for example, the push only touched `terraform/eks/**`), or only `infra-eks` ran. Check that ECR has the `sha-<commit>` tag (setup step 7). If it doesn't, run **app-&lt;app&gt; → Run workflow** on `main`.

### Build fails with `RepositoryNotFoundException`
The app isn't in `terraform/eks/apps.tf` yet, or `infra-eks` hasn't been applied since it was added. Apply it, then re-run the app workflow ([apps/new-app/README.md](../apps/new-app/README.md) step 2).

### Pods never become ready / ALB returns 502
The app's health path is wrong or not under its base path. `health_path` in `terraform/apps/<app>/main.tf` must return 200 at the full path (e.g. `/simple-cms/api/health`). The ALB target group health check uses the same path.
