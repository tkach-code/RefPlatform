# First deployment from zero: a guided walkthrough

This guide takes you from an empty AWS account to all three apps running behind one CloudFront URL. It explains what each step creates, why it comes in that order, and how to check it worked.

The other docs are reference material. This one is the tutorial that ties them together:

| Doc | Use it for |
|---|---|
| **this file** | First deployment, step by step, with explanations |
| [architecture.md](architecture.md) | How the platform works, naming, route/order registry, app contract |
| [readme.md](readme.md) | Short manual runbook, useful checks, **destroy everything** |
| [github-readme.md](github-readme.md) | CI/CD setup and troubleshooting |
| [apps/new-app/README.md](../apps/new-app/README.md) | Adding another app to the running platform, step by step |
| [terraform/s3-state/README.md](../terraform/s3-state/README.md), [terraform/eks/README.md](../terraform/eks/README.md), [terraform/apps/README.md](../terraform/apps/README.md) | Reference for each Terraform layer |

---

## 0. The big picture

Infrastructure is split into **three Terraform layers**. Each one is a separate root folder with its own state. You apply them bottom-up and destroy them top-down.

```
 Layer 3  terraform/apps/<app>     one per app: namespace, IAM role, secret, Deployment, Service, Ingress
             │  reads platform values from SSM /refplatform/platform/*
 Layer 2  terraform/eks            VPC, EKS cluster, ALB + shared Ingress, CloudFront, ECR repos, SSM params
             │  stores its state in the bucket from layer 1
 Layer 1  terraform/s3-state       S3 state bucket + GitHub OIDC roles   (local state on your disk)
```

Why three layers?
- **Layer 1 is the chicken-and-egg step.** Terraform stores state in S3, but the bucket must exist first. So this layer keeps its state locally and only creates the bucket and the CI roles.
- **Layer 2 is slow and rarely changes.** The EKS cluster takes ~20 minutes. You don't want it in the same state as an app that redeploys on every commit.
- **Layer 3 is fast and per-app.** Each app has its own state file, so deploying `empty-login` can never touch `simple-cms`.

What a request looks like once everything is up:

```
Browser ─► https://dxxxx.cloudfront.net/simple-cms/   CloudFront refplatform-cdn (HTTPS)
             └─► ALB refplatform-alb (HTTP :80)          rules by path prefix, lowest group.order first
                   ├─ /simple-cms*  (100) → pods in namespace simple-cms   (+ MongoDB)
                   ├─ /empty-login* (110) → pods in namespace empty-login
                   ├─ /*            (900) → pods in namespace index-app    (landing page)
                   └─ other         (1000)→ fixed 404
```

### Two ways to run layers 2 and 3

| | **Path A: local** (recommended for the first time) | **Path B: GitHub Actions** |
|---|---|---|
| Layer 1 | local | local (always) |
| Layer 2 | `terraform apply` on your machine | merge to `main`, approve `infra-eks` |
| Layer 3 | `docker build/push` + `terraform apply` on your machine | push to `main`, the `app-*` workflow builds and deploys |
| Needs | AWS CLI, Terraform, Docker, kubectl | a GitHub repo, the repo variable and Environments |

This guide does **Path A** end to end, because you see every step and its output. [Section 7](#7-optional-switch-to-github-actions-path-b) then hands day-to-day deploys over to GitHub Actions. Both paths use the same state bucket, so you can mix them.

### What it costs

Everything here bills by the hour while it exists. Rough eu-central-1 numbers:

| Resource | ~USD/month |
|---|---|
| EKS control plane | 73 |
| 2 × t3.medium nodes + EBS | 75 |
| NAT gateway (+ data) | 38+ |
| ALB | 20+ |
| Public IPv4 addresses, CloudFront, ECR, Secrets Manager, S3 | ~10 |
| **Total** | **~215/month ≈ 7/day** |

When you're done experimenting, follow [readme.md → Destroy everything](readme.md#destroy-everything).

---

## 1. Prerequisites (one time)

### 1.1 Tools

| Tool | Why | Check |
|---|---|---|
| Terraform ≥ 1.10 | all three layers (S3 native locking needs 1.10) | `terraform version` |
| AWS CLI v2 | credentials, ECR login, kubeconfig | `aws --version` |
| kubectl | look inside the cluster | `kubectl version --client` |
| Docker | build app images | `docker version` (Docker Desktop must be running) |
| Node.js + npm | seed the simple-cms database | `node -v` |
| Python | `terraform destroy` of the platform runs a cleanup helper | `python --version` |
| Git Bash | every command in this guide is bash | — |

On Windows, the destroy helper calls `python` (not `python3`), so the Microsoft Store `python3` stub is fine to ignore.

### 1.2 AWS credentials

```bash
aws sts get-caller-identity
```

You need an IAM user or role with `AdministratorAccess`: layer 2 creates VPCs, IAM roles, EKS and CloudFront. Write down two values from the output:
- `Account`: the 12-digit account ID, written `<acct>` below.
- `Arn`: your principal, e.g. `arn:aws:iam::<acct>:user/<name>`. It goes into `cluster_admin_principal_arns` in step 3.

If `Arn` contains `assumed-role/...`, you're using an assumed role (SSO etc.). Put the **role** ARN in step 3 (`arn:aws:iam::<acct>:role/<RoleName>`), not the session ARN.

### 1.3 Pin the region

The project runs in **eu-central-1** (Frankfurt). Terraform takes its region from the code (`aws_region` variables and the backend `region` in each `versions.tf`), but the AWS CLI uses your profile's default, which may be different. Exporting the variable keeps both in line regardless of profile. Run this in every new terminal, before any other command in this guide:

```bash
export AWS_REGION=eu-central-1
export MSYS_NO_PATHCONV=1   # Git Bash/MSYS: stop rewriting "/refplatform/..." into "C:/Program Files/Git/refplatform/..."
export ACCT=$(aws sts get-caller-identity --query Account --output text)
echo "$ACCT $AWS_REGION"
```

If you skip this, commands like `aws ssm get-parameters-by-path` look in the wrong region and come back empty.

### 1.4 Decide about GitHub now

Layer 1 can also create the IAM roles that GitHub Actions uses. Decide before you apply it:

- **You will use GitHub Actions later:** create the GitHub repository first (it can stay empty for now) and note its `owner/name`. You'll put that in step 2.
- **Local only, no GitHub:** leave `github_repository` empty in step 2 and set `github_ci_roles_enabled = false` in step 3.

You can change your mind later: set the value, re-apply layer 1, then re-apply layer 2.

### 1.5 Check that the account is empty

```bash
aws eks list-clusters
aws s3 ls | grep refplatform
aws iam list-open-id-connect-providers
```

The first two should print nothing. For the third, look for `token.actions.githubusercontent.com`. If it already exists in the account, you **must** set `create_github_oidc_provider = false` in step 2. An account can have only one provider per URL, and creating a second one fails.

---

## 2. Layer 1: bootstrap (`terraform/s3-state`)

**Creates:**
- S3 bucket `refplatform-tfstate-<acct>`: versioned, encrypted, private. Holds every other state file.
- If `github_repository` is set: the GitHub OIDC provider (unless it already exists) and the roles `refplatform-gh-build`, `refplatform-gh-deploy`, `refplatform-gh-infra`.

**Cost:** practically zero.

```bash
cd terraform/s3-state
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region                  = "eu-central-1"
github_repository           = "owner/repo"   # or "" for local only (1.4)
create_github_oidc_provider = false          # false if 1.5 showed the provider already exists
```

Then:

```bash
terraform init                # downloads the AWS provider; state stays local in this folder
terraform plan                # read it: a bucket, its settings, and (optionally) 3 roles + policies
terraform apply               # type "yes"
terraform output              # account_id, bucket_name, bucket_region, github_role_arns
```

**Verify:**
```bash
aws s3 ls | grep refplatform-tfstate
aws iam list-roles --query "Roles[?starts_with(RoleName,'refplatform-gh')].RoleName"
```

**Important: back up the local state.** `terraform/s3-state/terraform.tfstate` is git-ignored and is the only record of layer 1. Lose it, and destroying the bucket later means importing or deleting by hand. Copy it somewhere safe.

---

## 3. Layer 2: platform (`terraform/eks`)

**Creates** (~20-25 min):
1. VPC `refplatform-vpc`: 2 AZs, public and private subnets, 1 NAT gateway.
2. EKS cluster `refplatform-eks` + managed node group (2 × t3.medium) + add-ons (VPC CNI, CoreDNS, kube-proxy, EBS CSI).
3. EKS access entries: who is cluster admin (you + the CI roles).
4. AWS Load Balancer Controller + the shared Ingress `refplatform-ingress/public`. This is what creates the ALB `refplatform-alb` with its catch-all 404.
5. Secrets Store CSI driver + AWS provider (ASCP), so pods can mount Secrets Manager secrets.
6. CloudFront `refplatform-cdn` in front of the ALB (needs the ALB hostname, so it comes last).
7. ECR repositories `refplatform/simple-cms`, `refplatform/index-app`, `refplatform/empty-login` (from `apps.tf`).
8. StorageClass `refplatform-gp3` and SSM parameters `/refplatform/platform/*`. App stacks read these instead of this stack's state.

### 3.1 Configure

Edit `terraform/eks/terraform.tfvars` (this file is committed):

```hcl
aws_region      = "eu-central-1"
cluster_version = "1.37"

cluster_admin_principal_arns = ["arn:aws:iam::<acct>:user/<name>"]   # your Arn from 1.2

github_ci_roles_enabled = true    # false if github_repository was left empty in step 2
```

Why list yourself explicitly? Terraform also grants admin to "whoever runs the apply". Once CI applies this stack, "whoever" becomes the CI role, and you would lose `kubectl` access. The explicit list keeps you in.

### 3.2 Apply

```bash
cd terraform/eks
terraform init -backend-config="bucket=refplatform-tfstate-$ACCT"
terraform plan                # ~100+ resources to add, 0 to change, 0 to destroy
terraform apply               # ~20-25 min. Don't interrupt it
```

`-backend-config` provides the bucket name, which contains the account ID. The key (`platform/eks.tfstate`), region and locking are fixed in `versions.tf`.

If the apply fails partway, read the error, fix the cause, and run `terraform apply` again. Terraform continues from where it stopped. Common first-run issues are at the end of this guide.

### 3.3 Verify

```bash
terraform output public_base_url                  # https://dxxxx.cloudfront.net  ← your platform URL
$(terraform output -raw update_kubeconfig_command)  # writes ~/.kube/config for refplatform-eks
kubectl get nodes                                 # 2 nodes, STATUS Ready
kubectl get pods -A                               # everything Running (aws-load-balancer-controller, coredns, csi...)
kubectl get ingress -A                            # refplatform-ingress/public with an ADDRESS (the ALB)
aws ssm get-parameters-by-path --path /refplatform/platform --query 'Parameters[].[Name,Value]' --output table
aws ecr describe-repositories --query 'repositories[].repositoryName'
```

Open the CloudFront URL in a browser. You should get the **404 "no route"** page from the ALB. That's correct: no app is deployed yet, and the catch-all rule answers everything. A brand-new CloudFront distribution can take a few minutes before it responds.

---

## 4. Layer 3: apps (`terraform/apps/<app>`)

Each app goes through the same two steps:
1. **Build** a Docker image and push it to its ECR repository with a **new, unique tag**. Tags are immutable: pushing the same tag twice fails.
2. **Apply** the app's Terraform root with `-var image=<that image>`.

What `terraform/modules/web-app` creates for each app:

| Resource | Purpose |
|---|---|
| Namespace `<app>` + ResourceQuota + LimitRange | isolation and size limits |
| IAM role `refplatform-<app>-irsa` + ServiceAccount `<app>` | the pod's AWS identity, which can read only its own secret |
| Secrets Manager `refplatform/apps/<app>` + SecretProviderClass | secrets mounted into the pod as env vars (only apps with secrets) |
| Deployment + Service | runs the container on port 3000 |
| Ingress in group `refplatform` with a `group.order` | adds a path rule to the shared ALB |

Do the apps in this order: `empty-login` (simplest, proves the whole chain), then `index-app`, then `simple-cms` (adds MongoDB and secrets).

### 4.1 Log Docker in to ECR (once per terminal; the token lasts 12 h)

```bash
cd <repo root>
REG=$ACCT.dkr.ecr.eu-central-1.amazonaws.com
aws ecr get-login-password | docker login --username AWS --password-stdin $REG
TAG=sha-$(git rev-parse --short=12 HEAD)          # same tag format CI uses
echo $TAG
```

If you rebuild without a new commit, the tag already exists and the push fails. Use a manual tag like `sha-manual02` then.

### 4.2 empty-login (`/empty-login`, order 110)

```bash
docker build -t $REG/refplatform/empty-login:$TAG apps/empty-login
docker run --rm -d -p 3000:3000 --name t1 $REG/refplatform/empty-login:$TAG   # optional local smoke test
curl -s localhost:3000/empty-login/api/health; docker stop t1
docker push $REG/refplatform/empty-login:$TAG

cd terraform/apps/empty-login
terraform init -backend-config="bucket=refplatform-tfstate-$ACCT"
terraform apply -var="image=$REG/refplatform/empty-login:$TAG"
terraform output url
cd ../../..
```

**Verify:**
```bash
kubectl -n empty-login get pods,svc,ingress      # pod Running 1/1, ingress with the same ALB address
curl -s https://<cf-domain>/empty-login/api/health
```

The new path appears on the ALB within ~1 minute. If you get **502/503** at first, the ALB target is still registering or failing its health check (see troubleshooting).

### 4.3 index-app (`/`, order 900)

Same commands, with `index-app`:

```bash
docker build -t $REG/refplatform/index-app:$TAG apps/index-app
docker push $REG/refplatform/index-app:$TAG
cd terraform/apps/index-app
terraform init -backend-config="bucket=refplatform-tfstate-$ACCT"
terraform apply -var="image=$REG/refplatform/index-app:$TAG"
cd ../../..
```

Now `https://<cf-domain>/` shows the landing page instead of the 404. It works because `index-app`'s rule `/*` has the **highest** app order (900): the ALB checks `/simple-cms*` and `/empty-login*` first and only falls through to `/` when they don't match.

### 4.4 simple-cms (`/simple-cms`, order 100, + MongoDB)

```bash
docker build -t $REG/refplatform/simple-cms:$TAG apps/simple-cms     # Next.js build, a few minutes
docker push $REG/refplatform/simple-cms:$TAG
cd terraform/apps/simple-cms
terraform init -backend-config="bucket=refplatform-tfstate-$ACCT"
terraform apply -var="image=$REG/refplatform/simple-cms:$TAG"
```

This root adds:
- `module "mongodb"`: a MongoDB Helm release in namespace `simple-cms`, on a `refplatform-gp3` EBS volume.
- Secrets generated by Terraform (`MONGODB_URI`, `AUTH_SECRET`, `ADMIN_EMAIL`, `ADMIN_PASSWORD`), stored in Secrets Manager `refplatform/apps/simple-cms` and mounted into the pod.
- `AUTH_URL` = the CloudFront origin, read from SSM.

**Verify:**
```bash
kubectl -n simple-cms get pods                   # simple-cms-… and mongodb-… both Running
curl -s https://<cf-domain>/simple-cms/api/health
```

### 4.5 Seed simple-cms (once per fresh database)

The database starts empty, so the public pages have no content and there is no admin user. Seed it through a port-forward. Use two terminals (export `AWS_REGION` and `ACCT` in both, see 1.3).

Terminal 1, keep it open:
```bash
kubectl -n simple-cms port-forward svc/mongodb 27017:27017
```

Terminal 2:
```bash
cd terraform/apps/simple-cms
ADMIN_EMAIL=$(terraform output -raw admin_email)
ADMIN_PASSWORD=$(terraform output -raw admin_password)
MONGO_PW=$(kubectl -n simple-cms get secret mongodb -o jsonpath='{.data.mongodb-root-password}' | base64 -d)
cd ../../../apps/simple-cms
npm install
MONGODB_URI="mongodb://root:${MONGO_PW}@127.0.0.1:27017/simple-cms?authSource=admin" \
  ADMIN_EMAIL="$ADMIN_EMAIL" ADMIN_PASSWORD="$ADMIN_PASSWORD" npm run seed
```

`npm run seed` **wipes** all collections before it writes. Then stop the port-forward (Ctrl+C) and sign in:

```bash
cd ../../terraform/apps/simple-cms
terraform output -raw admin_url; echo
terraform output -raw admin_email; echo
terraform output -raw admin_password; echo
```

---

## 5. Final check

```bash
CF=$(terraform -chdir=terraform/eks output -raw public_base_url)
for p in / /empty-login/api/health /simple-cms/api/health /does-not-exist; do
  printf "%-28s %s\n" "$p" "$(curl -s -o /dev/null -w '%{http_code}' $CF$p)"
done
kubectl get ingress -A
```

Expected: `/` and both health paths → `200`. `/does-not-exist` → `404`, but now it's nginx in `index-app` that answers (it owns `/*`), not the ALB's catch-all. The catch-all at order 1000 only answers while `index-app` isn't deployed.

---

## 6. Day-2 operations (local)

| Task | How |
|---|---|
| Deploy a new version of an app | commit → new `$TAG` → `docker build/push` → `terraform apply -var image=…` in `terraform/apps/<app>` |
| Roll back | `terraform apply -var image=…:<older sha- tag>` (the last 15 tags are kept in ECR) |
| See what's deployed | `terraform -chdir=terraform/apps/<app> output image` |
| Logs | `kubectl -n <app> logs deploy/<app> -f` |
| Restart pods | `kubectl -n <app> rollout restart deploy/<app>` |
| Change platform (nodes, versions, add an app's ECR repo) | edit `terraform/eks`, `terraform plan`, `terraform apply` |
| Changed `terraform/modules/**` | re-apply every app root with its current image |
| Detect manual drift | `terraform plan` in any root should say "No changes" |
| Add a new app | [apps/new-app/README.md](../apps/new-app/README.md) (full guide), short checklist in [terraform/apps/README.md → Add an app](../terraform/apps/README.md#add-an-app) |
| Tear everything down | [readme.md → Destroy everything](readme.md#destroy-everything) |

---

## 7. Optional: switch to GitHub Actions (Path B)

After the first local deployment, CI can take over. Full details in [github-readme.md](github-readme.md). Short version:

1. **Layer 1 knows the repo:** `github_repository = "owner/repo"` in `terraform/s3-state/terraform.tfvars`, then `terraform apply` there. Check that the live trust policy of `refplatform-gh-build` names your repo, not `OWNER/REPO`. Then `github_ci_roles_enabled = true` in `terraform/eks/terraform.tfvars`, and `terraform apply` there. **Commit that tfvars change.** CI applies the committed file, and `false` there would remove the CI roles' cluster access on the first `infra-eks` apply.
2. **Push the code** to the GitHub repository, default branch `main` (the workflows only deploy and apply from `main`):
   ```bash
   git push -u origin main
   ```
   Make sure no `.env`, `terraform.tfstate*` or `.terraform/` is in the pushed history ([github-readme.md](github-readme.md#1-check-that-nothing-secret-gets-pushed)).
   If steps 3–4 aren't done yet, the app workflows started by this push fail at the AWS login. That is harmless: nothing is built or deployed.
3. **GitHub → Settings → Secrets and variables → Actions → Variables:** `AWS_ACCOUNT_ID` = `<acct>`. No secrets: the roles are assumed through OIDC.
4. **GitHub → Settings → Environments:**
   - `infra`: required reviewer = you, deployment branches unrestricted (PR plans run here too).
   - `infra-plan`: deployment branches = `main` only.
5. **First CI deploy:** **Actions → app-&lt;app&gt; → Run workflow** on `main` with `image_tag` empty, once per app. A push that only touches `terraform/eks/**` doesn't start app workflows. Then check that ECR has `sha-<commit>` and that the Deployments run it ([github-readme.md](github-readme.md#7-verify-that-ci-actually-deployed)). A green run alone isn't proof.
6. From then on:
   - a push touching `apps/<app>/**` builds, tests and deploys that app;
   - a push touching `terraform/eks/**` plans, then waits for your approval in `infra` before applying;
   - **Actions → app-<app> → Run workflow** with `image_tag` redeploys or rolls back;
   - **Actions → apps-redeploy-all** after changing `terraform/modules/**`.

Because CI uses the same state bucket, it picks up exactly where your local applies left off.

---

## 8. Troubleshooting the first run

| Symptom | Cause / fix |
|---|---|
| `EntityAlreadyExists … token.actions.githubusercontent.com` in step 2 | The provider already exists. Set `create_github_oidc_provider = false`, apply again |
| `Error: Failed to get existing workspaces: … NoSuchBucket` at `init` | Wrong bucket name or account in `-backend-config`. Check `echo $ACCT` |
| `NoSuchEntity … refplatform-gh-infra` in step 3 | The CI roles weren't created (no `github_repository`). Set `github_ci_roles_enabled = false` |
| Platform apply fails on an add-on or Helm release with a timeout | Usually nodes weren't ready yet. Run `terraform apply` again |
| `kubectl`: `You must be logged in to the server (Unauthorized)` | Your ARN isn't in `cluster_admin_principal_arns`, or it's a session ARN. Fix it and re-apply layer 2 |
| `kubectl` talks to the wrong cluster / region | Re-run `$(terraform -chdir=terraform/eks output -raw update_kubeconfig_command)` |
| `docker push`: `tag invalid … already exists` | ECR tags are immutable. Use a new tag |
| `docker push`: `no basic auth credentials` | The ECR login expired (12 h) or used another region. Repeat 4.1 |
| App URL returns **502/503** | Pod not ready, or the health check fails. `kubectl -n <app> get pods`, `kubectl -n <app> describe pod …`, `kubectl -n <app> logs deploy/<app>`. The health path must return 200 at the full prefixed path |
| Pod stuck in `ContainerCreating` (simple-cms) | Secret mount failed. `kubectl -n simple-cms describe pod …` → check the IRSA role and the secret `refplatform/apps/simple-cms` |
| MongoDB pod `Pending` | The EBS volume didn't bind. `kubectl -n simple-cms get pvc`, `kubectl get sc refplatform-gp3` |
| `/` shows 404 "no route" | `index-app` isn't deployed yet. Expected until 4.3 |
| Admin login loops back to the login page | `AUTH_URL` must be the CloudFront origin over https (it comes from SSM `/refplatform/platform/public_base_url`). Check `kubectl -n simple-cms get deploy simple-cms -o yaml \| grep -A1 AUTH_URL` |
| AWS CLI commands return empty but resources exist | Wrong region. `export AWS_REGION=eu-central-1` (1.3) |
| `aws ssm …`: `parameter name must begin with a forward slash` | Git Bash converted `/refplatform/...` into a Windows path. `export MSYS_NO_PATHCONV=1` (1.3) |
| `docker login`: `lookup <12 digits>: no such host` | `docker login` got the account ID instead of the registry host. `REG` was empty: set it again (4.1) |
