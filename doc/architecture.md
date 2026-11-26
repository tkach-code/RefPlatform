# RefPlatform architecture

RefPlatform hosts many small, independent web apps on one EKS cluster in **eu-central-1**, behind one CloudFront URL. Each app lives on its own path prefix (`https://<cf>/<app>/`) and ships on its own.

## Principles

| Topic | Rule |
|---|---|
| Isolation | Every app gets its own namespace, quota, IAM role, secret, image repository, Terraform state and workflow |
| URL | One generated `*.cloudfront.net` domain. Apps live on **sub-routes** (`/<app>`). The landing page `index-app` owns `/` |
| Auth | No shared login or SSO. Each app handles its own sessions |
| Data | Each app brings its own databases and services (simple-cms runs MongoDB in its namespace) |
| Environments | One environment, one cluster |
| Infra delivery | GitHub Actions: plan on PR, apply on `main` after manual approval (Environment `infra`) |
| App delivery | Push to `main` builds, tests and deploys only the app that changed |

---

## 1. How it works

```
Browser
  └─ https://dxxxx.cloudfront.net            single entry point: CloudFront "refplatform-cdn"
       └─ http://<ALB>                        one ALB "refplatform-alb", Ingress group "refplatform", listener :80
            ├─ /simple-cms*   → ns simple-cms  / svc simple-cms   (group.order 100)
            ├─ /empty-login*  → ns empty-login / svc empty-login  (group.order 110)
            ├─ /<next-app>*   → ns <next-app>  / ...              (group.order 120, 130, …)
            ├─ /*             → ns index-app   / svc index-app    (group.order 900)  landing page
            └─ everything else → fixed 404 "no route"             (group.order 1000) ns refplatform-ingress
```

- CloudFront forwards every path unchanged to the ALB. Only `*/_next/static/*` is cached.
- The ALB evaluates Ingresses lowest `group.order` first. `index-app` owns `/`, so it must have the **highest** app order (900). Without it, `/` returns the catch-all 404.
- **The ALB does not strip the prefix.** Each app must serve under `/<app>` (Next.js `basePath`, Express mount, …).
- App stacks read platform values from SSM `/refplatform/platform/*`, not from the platform's Terraform state.

### Route / order registry (keep current, orders must be unique)

| App | Source | Path | group.order | Namespace | ECR repo | Extra infra |
|---|---|---|---|---|---|---|
| simple-cms | `apps/simple-cms` | `/simple-cms` | 100 | `simple-cms` | `refplatform/simple-cms` | MongoDB |
| empty-login | `apps/empty-login` | `/empty-login` | 110 | `empty-login` | `refplatform/empty-login` | — |
| index-app | `apps/index-app` | `/` | 900 | `index-app` | `refplatform/index-app` | — |
| *(catch-all)* | — | `/` | 1000 | `refplatform-ingress` | — | — |

The same table, shorter, is in [terraform/apps/README.md](../terraform/apps/README.md). Keep both in sync.

### Apps

| App | Stack | What |
|---|---|---|
| `simple-cms` | Next.js 16, React 19, TypeScript, Tailwind v4, MongoDB, Auth.js v5 | Marketing site with an authenticated admin area for content CRUD |
| `empty-login` | Express 5 | Minimal login page. Accepts any credentials |
| `index-app` | Static HTML on unprivileged nginx | Landing page with links to every app |

---

## 2. Naming convention

### 2.1 Rules
- **Shared/platform resources:** `refplatform-<component>` (lowercase, hyphens).
- **Per-app AWS resources:** `refplatform-<app>-<component>` (IAM roles, etc.), so one app's resources are easy to find and to scope IAM to.
- **Hierarchical names** (ECR, Secrets Manager, SSM, S3 keys): `refplatform/<scope>/<name>`.
- **Kubernetes:** an app's namespace is just `<app>`. Shared namespaces use the `refplatform-` prefix. Every resource gets the labels `app.kubernetes.io/part-of=refplatform` and `app.kubernetes.io/name=<app>`.
- **Tags on every AWS resource:** `Project=refplatform`, `ManagedBy=terraform`, `Stack=<bootstrap|platform|app>`, and on app resources `App=<app>`.
- **App names:** lowercase, dashes, ≤ 20 chars (they appear in IAM role names, limited to 64 chars).

### 2.2 Resource names

| Resource | Name |
|---|---|
| State bucket | `refplatform-tfstate-<account>` |
| State keys | `platform/eks.tfstate`, `apps/<app>.tfstate` |
| VPC | `refplatform-vpc` |
| EKS cluster | `refplatform-eks` |
| Cluster IAM (nodes, EBS CSI, LB controller) | `refplatform-eks-*` |
| ALB Ingress group | `refplatform` |
| Shared Ingress namespace / name | `refplatform-ingress` / `public` |
| ALB | `refplatform-alb` (set via the `load-balancer-name` annotation on the shared Ingress) |
| CloudFront | `refplatform-cdn` |
| ECR | `refplatform/<app>` |
| App IRSA role | `refplatform-<app>-irsa`, with an inline policy `read-own-secret` scoped to that app's secret |
| App secret | `refplatform/apps/<app>` |
| App namespace / ServiceAccount / Deployment / Service / Ingress | `<app>` |
| StorageClass | `refplatform-gp3` |
| simple-cms MongoDB | Helm release `mongodb` in ns `simple-cms`, DB `simple-cms` |
| SSM parameters | `/refplatform/platform/{cluster_name, public_base_url, alb_hostname, ingress_group_name, ingress_class_name, oidc_provider_arn, secret_name_prefix, storage_class_name, ecr_registry}` |
| GitHub OIDC roles | `refplatform-gh-build`, `refplatform-gh-deploy`, `refplatform-gh-infra` |
| GitHub settings | variable `AWS_ACCOUNT_ID` (optional `AWS_REGION`). Environments `infra`, `infra-plan` |

---

## 3. Repository layout

```
apps/
  simple-cms/            Next.js CMS
  index-app/             landing page (static, nginx)
  empty-login/           Express login demo
  new-app/               guide for adding an app (README only)

terraform/
  s3-state/              bootstrap (local state): refplatform-tfstate-<account> bucket,
                         GitHub OIDC provider + refplatform-gh-* roles
  eks/                   platform (S3 key platform/eks.tfstate): refplatform-vpc, refplatform-eks,
                         LB controller, refplatform-ingress/public + 404, Secrets Store CSI + ASCP,
                         refplatform-gp3 StorageClass, ECR refplatform/<app>, refplatform-cdn, SSM params
  modules/
    web-app/             reusable: namespace, quota, limit range, SA + IRSA, secret + SecretProviderClass,
                         Deployment, Service, Ingress (path, order, health-check path)
    mongodb/             reusable Bitnami MongoDB release
  apps/
    simple-cms/          thin root (S3 key apps/simple-cms.tfstate): web-app + mongodb
    index-app/           thin root: web-app
    empty-login/         thin root: web-app

.github/workflows/
  _build-app.yml  _deploy-app.yml          reusable
  app-simple-cms.yml  app-index-app.yml  app-empty-login.yml
  apps-redeploy-all.yml                    manual
  infra-eks.yml                            platform

doc/                     architecture (this file), first deployment, runbook, CI setup
```

**One thin root per app** rather than one generic root with toggles: each app can hold its own databases and services next to the standard `web-app` module, without feature flags. The common parts stay in one module.

---

## 4. Terraform

### 4.1 `terraform/s3-state` (bootstrap)
Bucket `refplatform-tfstate-<account>` (versioned, encrypted, private), the GitHub OIDC provider and the three `refplatform-gh-*` roles (§7.3). Local state, applied once by hand.

### 4.2 Platform stack (`terraform/eks`)
1. **S3 backend** `refplatform-tfstate-<account>` / `platform/eks.tfstate`, `use_lockfile = true`, Terraform `>= 1.10`.
2. **One `project` local** (`refplatform`) that every name is built from.
3. **App registry** (`apps.tf`) → one ECR repository `refplatform/<app>` per app. Immutable tags, the last 15 `sha-` images kept.
4. **Shared Ingress:** namespace `refplatform-ingress`, group `refplatform`, `load-balancer-name: refplatform-alb`, catch-all 404 at order 1000.
5. **Shared CloudFront** `refplatform-cdn`, with a `*/_next/static/*` behaviour using *CachingOptimized*.
6. **`refplatform-gp3` StorageClass** (cluster-scoped, so it lives in the platform stack).
7. **No shared secrets policy.** Each app's IRSA role gets an inline policy for its own secret only (`terraform/modules/web-app`).
8. **SSM** `/refplatform/platform/*` for the app stacks.
9. **EKS admin access:** the explicit `cluster_admin_principal_arns` list (humans, in the committed `terraform.tfvars`), plus `refplatform-gh-infra` and `refplatform-gh-deploy` when `github_ci_roles_enabled`.

### 4.3 `terraform/modules/web-app`
Inputs: `name`, `image`, `container_port` (3000), `replicas`, `resources`, `quota`, `limit_range`, `path`, `ingress_order`, `health_path`, `env`, `secrets` (map → Secrets Manager `refplatform/apps/<name>` → env vars), `cluster_name`, `aws_region`.
It always sets the Ingress annotation `alb.ingress.kubernetes.io/healthcheck-path = health_path`. **This is required:** the default health check `/` is 404 under a base path → targets unhealthy → 502.

### 4.4 `terraform/apps/<app>` roots
`versions.tf` (backend key `apps/<app>.tfstate`), `providers.tf`, `platform.tf` (SSM reads), `variables.tf` (only `image` is required), and `main.tf` with `locals { app, path, order, health_path }` + `module "web_app"` + any app-specific resources. Settings live in committed `locals`, so CI passes only the image.
simple-cms adds `module "mongodb"` and the secrets `MONGODB_URI`, `AUTH_SECRET`, `ADMIN_EMAIL`, `ADMIN_PASSWORD`. `AUTH_URL` = SSM `public_base_url` (origin only, no path).

---

## 5. App contract (every app, any framework)

| Rule | Why |
|---|---|
| Serves under `/<app>` (Next.js `basePath`, Vite `base`, Express mount…). `index-app` at `/` | The ALB doesn't rewrite paths |
| `GET /<app>/api/health` → 200 (Node apps: `{"status":"ok"}`) | Probes, ALB health check, CI smoke test |
| `apps/<app>/Dockerfile`, port 3000 (or set `container_port`) | Generic build/deploy |
| Starts without real secrets | CI smoke test runs the container bare |
| Cookie names prefixed with the app name, or `Path=/<app>` | Shared hostname |
| Config only via env / its Secrets Manager secret | Generic wiring |
| Cross-app links are relative (`/simple-cms/`) | Works on any CloudFront domain |

App-specific notes (simple-cms base path and Auth.js setup) are in each app's README.

---

## 6. CI/CD

### 6.1 Per-app workflow (`app-<app>.yml`)
```yaml
on:
  push:
    paths: ['apps/simple-cms/**', 'terraform/apps/simple-cms/**']
  workflow_dispatch:
    inputs: { image_tag: { required: false } }    # set = redeploy/rollback that tag, skip build
jobs:
  build:
    uses: ./.github/workflows/_build-app.yml
    with: { app: simple-cms, health_path: /simple-cms/api/health }
  deploy:
    needs: build
    if: github.ref == 'refs/heads/main'
    uses: ./.github/workflows/_deploy-app.yml
    with: { app: simple-cms, image_tag: ${{ needs.build.outputs.image_tag }} }
```
- Build → deploy in **one run** via `needs:`, so parallel builds of different apps can't mix up images.
- Image `<account>.dkr.ecr.<region>.amazonaws.com/refplatform/<app>:sha-<12>`. Immutable, and the push is skipped if the tag exists.
- Deploy: `terraform -chdir=terraform/apps/<app> init -backend-config="bucket=refplatform-tfstate-<account>"`, then `apply -auto-approve -var image=…`.
- `concurrency: refplatform-deploy-<app>`. Branch pushes only build and test. Only `main` deploys.
- Changes to `terraform/modules/**` → manual `apps-redeploy-all.yml` (matrix over `terraform/apps/*`, current image).

### 6.2 Infra (`infra-eks.yml`)
PR on `terraform/eks/**` → fmt, validate, plan (in the job summary). Push to `main` → plan → apply of the saved plan in Environment `infra` (you approve). `destroy` and `s3-state` stay manual.

### 6.3 GitHub OIDC roles
Workflows build the ARN `arn:aws:iam::${{ vars.AWS_ACCOUNT_ID }}:role/<role>`, so no secrets are needed. Each role's trust policy pins the `repository` claim and matches `sub` with `repo:OWNER*/REPO*:…`, which covers both subject formats.

| Role | Trusted for | Scope |
|---|---|---|
| `refplatform-gh-build` | any ref | ECR push `refplatform/*` |
| `refplatform-gh-deploy` | `ref:refs/heads/main` | state `apps/*`, EKS describe + access entry, Secrets Manager `refplatform/apps/*`, IAM `refplatform-*-irsa` (create + inline policies), SSM `/refplatform/*` read, ECR describe |
| `refplatform-gh-infra` | `environment:infra`, `environment:infra-plan` | `AdministratorAccess` + EKS access entry |

Setup and troubleshooting: [github-readme.md](github-readme.md).

---

## 7. Checklist: add a new app

Short version. The full step-by-step guide is [apps/new-app/README.md](../apps/new-app/README.md).

1. `apps/<app>/` following §5.
2. Free `group.order` (< 900) → add a row to the §1 registry.
3. Add `<app>` to `terraform/eks/apps.tf` → PR → approve `infra-eks` (creates ECR `refplatform/<app>`).
4. `terraform/apps/<app>/`: copy `empty-login`'s root, change `locals` and the backend key, add app-specific DBs/services.
5. `.github/workflows/app-<app>.yml`: copy a caller and change the name and health path.
6. Merge → `https://<cf>/<app>/`. Add a link in `index-app`.

Remove: `terraform destroy` in `terraform/apps/<app>`, remove it from `apps.tf` (deletes the ECR repo and its images), delete its workflow and code.

---

## 8. Risks and gotchas
- Missing ALB health-check path → 502 (§4.3).
- `index-app` order not the highest → `/` swallows every app.
- Cookie collisions on the shared hostname (§5).
- Capacity: each app namespace has a quota (default 500m CPU / 1 Gi requests, 2 CPU / 2 Gi limits, 10 pods). Size the node group for the sum of all apps.
- `NEXT_PUBLIC_*` values are build-time. Keep base paths static.
- `load-balancer-name` must be set on exactly one Ingress in the group (the shared one), or ALB names conflict.
