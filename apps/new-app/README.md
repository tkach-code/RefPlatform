# Adding a new app to RefPlatform

A checklist for adding an app to the platform: cluster, ALB routing, CloudFront, ECR, CI/CD. It uses `new-app` as the example name. Replace it everywhere with your app's name.

When you are done, the app runs at `https://<cloudfront>/new-app/`, has its own namespace, image repository, Terraform state and workflow, and ships independently of the other apps.

## 0. Pick the name and the route

The **folder name is the app's identity**. The same string becomes:

| Thing | Value |
|---|---|
| Source folder | `apps/new-app` |
| URL path / base path | `/new-app` |
| Health path | `/new-app/api/health` |
| ECR repository | `refplatform/new-app` |
| Kubernetes namespace, ServiceAccount, Deployment, Service, Ingress | `new-app` |
| IAM role (IRSA) | `refplatform-new-app-irsa` |
| Secrets Manager secret | `refplatform/apps/new-app` |
| Terraform root / state key | `terraform/apps/new-app` / `apps/new-app.tfstate` |
| Workflow | `.github/workflows/app-new-app.yml` |

Rules: lowercase letters, digits and `-` only, starting with a letter. Keep it short (the IAM role name `refplatform-<app>-irsa` must stay within 64 characters). Renaming later means a new ECR repo, namespace and state, so choose carefully.

Pick an **unused ALB `group.order`, below 900**. `index-app` (`/`) must keep the highest order so its catch-all `/` doesn't swallow the other apps. Used today:

| App | Path | order |
|---|---|---|
| simple-cms | `/simple-cms` | 100 |
| empty-login | `/empty-login` | 110 |
| **new-app** | `/new-app` | **120** (next free) |
| index-app | `/` | 900 |
| catch-all 404 | `/` | 1000 |

## 1. Write the app so it follows the app contract

The ALB routes by path prefix and **does not strip it**, and all apps share one hostname. Every app must:

- [ ] **Serve everything under `/new-app`**, including pages, API routes, static assets and redirects. Next.js: `basePath: "/new-app"`. Vite: `base: "/new-app/"`. Express: mount the router at `/new-app` (`app.use(BASE_PATH, router)`, as in `apps/empty-login/server.js`). Plain HTML: asset URLs must include the prefix.
- [ ] **Return 200 from `GET /new-app/api/health`** without touching the database or secrets (Node apps: `{"status":"ok"}`). This one path is used by the CI smoke test, the Kubernetes probes and the ALB target health check.
- [ ] **Have a `Dockerfile`** in `apps/new-app` that listens on **port 3000** on `0.0.0.0` and runs as a non-root user (see `apps/empty-login/Dockerfile`). Add a `.dockerignore` (`node_modules`, `.git`, `.env*`).
- [ ] **Start without real secrets.** CI runs the bare container for the smoke test, with no env vars.
- [ ] **Scope cookies:** prefix cookie names with `new-app.` and/or set `Path=/new-app`. Otherwise they collide with other apps on the same domain.
- [ ] **Take configuration only from env vars** (plain vars or the app's own secret, see step 4).
- [ ] **Use relative links to other apps** (`/simple-cms/`), never the CloudFront domain.
- [ ] **For Node apps:** commit `package-lock.json`. CI runs `npm ci`, `npm run lint --if-present`, and `npx tsc --noEmit` if `tsconfig.json` exists. These must pass.
- [ ] Don't commit `.env` files. Add a `.gitignore` like `apps/simple-cms/.gitignore`, and an `.env example` template if the app needs env vars locally.

Check it locally the same way CI does:

```bash
cd apps/new-app
docker build -t new-app-local .
docker run --rm -d -p 3000:3000 --name new-app-local new-app-local
curl -i http://localhost:3000/new-app/api/health      # must be 200
curl -i http://localhost:3000/new-app/                 # the app itself, assets load from /new-app/...
docker rm -f new-app-local
```

## 2. First merge: register the app in the platform (ECR repository)

CI pushes images to `refplatform/new-app`, which `terraform/eks` creates. **This must be applied before the app's workflow runs for the first time.** Otherwise the build fails with `RepositoryNotFoundException`.

1. Add the app to `terraform/eks/apps.tf`:
   ```hcl
   locals {
     apps = [
       "simple-cms",
       "index-app",
       "empty-login",
       "new-app",
     ]
   }
   ```
2. Add the app to both route registries (keep them in sync):
   - `doc/architecture.md` §1, "Route / order registry" table
   - `terraform/apps/README.md`, the table at the top
3. Open a PR. `infra-eks` runs a plan (approve it in Environment `infra`). It should show only `aws_ecr_repository` + lifecycle policy for `refplatform/new-app` being **added**, and nothing changed or destroyed.
4. Merge to `main`. `infra-eks` plans again in `infra-plan`, then the `apply` job waits: **Actions → infra-eks → Review deployments → Approve**.
5. Check:
   ```bash
   aws ecr describe-repositories --repository-names refplatform/new-app --query 'repositories[0].repositoryUri' --output text
   ```

Locally instead of CI: `cd terraform/eks && terraform plan && terraform apply`. Still commit `apps.tf`, or the next CI apply deletes the repository again, together with its images (`force_delete`).

Keep this merge separate from step 5. If the app code, Terraform root and workflow land in the same push, the app build starts before you have approved the ECR apply, and it fails.

## 3. Terraform root for the app (`terraform/apps/new-app`)

Copy the simplest existing root and change its names:

```bash
cp -r terraform/apps/empty-login terraform/apps/new-app
rm -rf terraform/apps/new-app/.terraform terraform/apps/new-app/.terraform.lock.hcl
```

Then edit:

- **`main.tf`**, the `locals` block and the header comment:
  ```hcl
  locals {
    app         = "new-app"
    path        = "/new-app"
    order       = 120
    health_path = "/new-app/api/health"
  }
  ```
- **`versions.tf`**, the backend key: `key = "apps/new-app.tfstate"`. **If you forget this, the new app shares and overwrites empty-login's state.**
- **`main.tf`**, the `module "web_app"` inputs, as needed:
  - `replicas` (default 1)
  - `env = { KEY = "value" }` for plain env vars
  - `secrets = { ... }` for secret env vars (step 4)
  - `resources = { requests_cpu, requests_memory, limits_cpu, limits_memory }` if the defaults (50m/128Mi request, 500m/256Mi limit) aren't enough. The namespace also has a quota (`quota`) and a LimitRange (`limit_range`). See `terraform/modules/web-app/variables.tf`.
  - `container_port`, only if the container doesn't listen on 3000.
- `outputs.tf`, `platform.tf`, `providers.tf`, `variables.tf` and `.gitignore` need no changes. Platform values (ALB group, OIDC provider, public URL, StorageClass) come from SSM `/refplatform/platform/*`.

**Never** add `load-balancer-name` or other ALB-wide annotations to the app. Only the shared Ingress in `terraform/eks/modules/ingress` sets them.

Validate offline:

```bash
cd terraform/apps/new-app
terraform fmt -check && terraform init -backend=false && terraform validate
```

### App-specific infrastructure (optional)

**In-cluster** resources go in the same root, in the app's namespace `module.web_app.namespace`: a database as a Helm chart, a cache, extra Kubernetes objects. `terraform/apps/simple-cms` with `modules/mongodb` is the example (it adds the `helm` provider in `providers.tf`/`versions.tf`). For persistent volumes, use the StorageClass `local.platform.storage_class_name` (`refplatform-gp3`). CI can deploy these with no extra setup.

**AWS** resources (S3 bucket, SQS queue, RDS, DynamoDB, …) need one more step. The CI deploy role `refplatform-gh-deploy` may only manage app state, `refplatform/apps/*` secrets, `refplatform-*-irsa` roles and their inline policies, plus the cluster through its access entry. Creating anything else from `app-new-app` fails with `AccessDenied`. Choose one:
- extend the `deploy` policy in `terraform/s3-state/github.tf`, scoped to `refplatform-new-app*` names, and apply `terraform/s3-state` **by hand** (CI never applies it); or
- create the resource in `terraform/eks` (applied by the admin role `refplatform-gh-infra`) and publish its name through SSM `/refplatform/...`.

Either way, the app reaches AWS through its IRSA role `refplatform-new-app-irsa` (`module.web_app` output). Add an `aws_iam_role_policy` on it in the app root (CI may do that). Never use node or shared roles.

## 4. Secrets (optional)

Put secret values in the `secrets` map of `module "web_app"`. The module stores them in Secrets Manager `refplatform/apps/new-app`, mounts them with the Secrets Store CSI driver, and exposes them as env vars. Only this app's IRSA role can read the secret.

- Generate secrets in Terraform (`random_password`), as `terraform/apps/simple-cms/main.tf` does for `AUTH_SECRET`. Don't put secret values in committed files or GitHub.
- The map keys must be known at plan time (literal keys, values may be computed).
- The app must still start without them (CI smoke test).

## 5. Workflow (`.github/workflows/app-new-app.yml`)

```bash
cp .github/workflows/app-empty-login.yml .github/workflows/app-new-app.yml
```

Replace every `empty-login` with `new-app`: the header comment, `name:`, the three `paths:`, `app:` in both jobs, and `health_path: /new-app/api/health`. The result triggers on pushes touching `apps/new-app/**`, `terraform/apps/new-app/**` or the workflow itself. It builds on every branch and deploys from `main`.

Nothing else in CI needs changes:
- `_build-app.yml` / `_deploy-app.yml` are generic.
- `apps-redeploy-all.yml` picks up every folder in `terraform/apps/` automatically.
- The GitHub OIDC roles already cover every `refplatform/*` ECR repo, every `apps/*` state key, `refplatform/apps/*` secrets and `refplatform-*-irsa` roles. No new GitHub variables, secrets or environments are needed. The only exception is extra AWS resources (step 3).

## 6. Second merge: ship it

1. Add a link to the landing page in `apps/index-app/public/index.html` (relative URL):
   ```html
   <li><a href="/new-app/">New App</a>: one-line description</li>
   ```
   This change triggers the `app-index-app` workflow, which redeploys the landing page.
2. Commit `apps/new-app/**`, `terraform/apps/new-app/**`, `.github/workflows/app-new-app.yml` and the index link. Open a PR: the build (lint, type check, docker build, smoke test, ECR push) runs on the branch, but there's no deploy.
3. Merge to `main`. `app-new-app` builds `sha-<12-char-commit>` and runs `terraform apply` in `terraform/apps/new-app` with that tag. This first apply creates the namespace, IRSA role, secret, Deployment, Service and Ingress.

CloudFront needs no change. Its default behavior forwards every path to the ALB without caching. `*/_next/static/*` is already cached for any Next.js app.

## 7. Verify

```bash
TAG=sha-$(git rev-parse --short=12 origin/main)
aws ecr describe-images --repository-name refplatform/new-app --image-ids imageTag=$TAG --query 'imageDetails[0].imagePushedAt' --output text
kubectl -n new-app get deploy,pods,ingress
kubectl -n new-app get deploy new-app -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

CF=$(aws cloudfront list-distributions --query 'DistributionList.Items[0].DomainName' --output text)
curl -s -o /dev/null -w '%{http_code}\n' https://$CF/new-app/api/health   # 200
curl -s -o /dev/null -w '%{http_code}\n' https://$CF/new-app/             # 200 (or a 30x to /new-app)
curl -s -o /dev/null -w '%{http_code}\n' https://$CF/simple-cms/api/health # other apps still 200
```

A new Ingress joining the ALB group takes about a minute to become routable. Until then you may get the catch-all 404.

`terraform -chdir=terraform/apps/new-app output url` prints the public URL (after `terraform init -backend-config="bucket=refplatform-tfstate-<account-id>"`).

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Build: `RepositoryNotFoundException` | Step 2 not applied yet. Approve/apply `infra-eks`, then re-run the workflow |
| Build: "has no Dockerfile. Nothing to build." and no deploy | `apps/new-app/Dockerfile` is missing. The build is a no-op without it |
| Build: smoke test fails | The container doesn't answer `/new-app/api/health` on port 3000 without env vars. Check the logs printed by the step |
| `https://<cf>/new-app/` returns 404 from the platform | Ingress not in the group yet (wait a minute), or the app doesn't serve under `/new-app` |
| Page loads but CSS/JS 404 | Assets are requested from `/…` instead of `/new-app/…`. Fix the base path |
| Pods not ready / ALB 502 | Health path wrong or slow. `kubectl -n new-app describe pod`, `kubectl -n new-app logs deploy/new-app` |
| Another app broke after deploy | Duplicate `group.order`, or the app's path overlaps another app's. Orders must be unique and < 900 |
| Logged out of another app / odd sessions | Unscoped cookies. Prefix and path-scope them |
| Pod `Pending`, quota exceeded | Raise `quota` / `resources` in `terraform/apps/new-app/main.tf` |
| Deploy: `AccessDenied` creating an S3 bucket / queue / DB | The deploy role can't create general AWS resources. See step 3, "App-specific infrastructure" |
| Deploy: `the server has asked for the client to provide credentials` | CI role has no EKS access entry. See `doc/github-readme.md` troubleshooting |

## Removing the app later

1. `cd terraform/apps/new-app && terraform init -backend-config="bucket=refplatform-tfstate-<account-id>" && terraform destroy -var image=unused`
2. Remove `new-app` from `terraform/eks/apps.tf` and apply `infra-eks` (this deletes the ECR repo and its images).
3. Delete `apps/new-app`, `terraform/apps/new-app`, `.github/workflows/app-new-app.yml`, the index-app link and the registry rows.

Do step 1 before removing the Terraform root. `apps-redeploy-all` and the state in S3 still refer to the app until it is destroyed.

## Reference

- `doc/architecture.md`: §1 route registry, §5 app contract
- `terraform/apps/README.md`: what the `web-app` module creates
- `terraform/modules/web-app/variables.tf`: all module inputs
- `doc/github-readme.md`: CI flow and troubleshooting
