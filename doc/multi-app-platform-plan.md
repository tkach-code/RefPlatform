# RefPlatform: multi-app platform plan

Status: **deployed** (manually, from a local machine) to **eu-central-1** on 2026-11-26. All three apps are live behind one CloudFront URL. CI/CD (GitHub Actions) is not wired up yet.
Last updated 2026-11-25.

## Decisions

| # | Topic | Decision |
|---|---|---|
| D1 | `index-app` | Plain web app at `/`: a landing page with links to the other demo apps |
| D2 | `empty-login` and future apps | Standalone demo apps. No SSO, no shared login |
| D3 | Data | MongoDB only for `simple-cms`. Other apps bring their own databases/services. **Every app gets its own namespace** |
| D4 | Existing data/state | None kept. Everything is deployed from zero, so no state migration, imports or `moved` blocks |
| D5 | URL | Generated `*.cloudfront.net` domain, apps on **sub-routes** (`/<app>`). No custom domain for now |
| D6 | App code | `index-app`: static site on unprivileged nginx. `empty-login`: Express 5, no real auth |
| D7 | Infra delivery | GitHub pipeline: plan on PR, apply on `main` after manual approval (Environment `infra`) |
| D8 | Environments | One environment, single cluster. Demo / educational use |
| D9 | **Naming** | The old names `globomantics` / `demo-*` / `app-*` go away. All shared infra uses the **`refplatform`** prefix (§2) |
| D10 | **Apps folder** | App source moves from `code/` to top-level **`apps/`**: `apps/simple-cms`, `apps/index-app`, `apps/empty-login` |
| D11 | Git hygiene | The repo is local-only and the git history will be deleted after the redesign, so committed keys/state files aren't a concern |

## Progress

- [x] App source in `apps/simple-cms` (`git mv`, history kept). `apps/index-app` and `apps/empty-login` are placeholders with a contract README
- [x] Rename to `refplatform` across Terraform, workflows and docs (§2.3)
- [x] Terraform restructure (§4): `terraform/app` removed; `terraform/modules/{web-app,mongodb}` and `terraform/apps/{simple-cms,index-app,empty-login}` added; all roots pass `terraform validate`
- [x] simple-cms changes for `/simple-cms` (§6): lint, tsc, build, Docker smoke test and a local end-to-end login test pass
- [x] Workflows (§7): `_build-app`, `_deploy-app`, `app-*`, `apps-redeploy-all`, `infra-eks`. The old `build-app`/`deploy-app` are removed
- [x] Docs: `CLAUDE.md`, root `README.md`, `terraform/*/README.md`, `terraform/apps/README.md`, `apps/*/README.md`, `doc/readme.md`, `doc/github-readme.md`
- [x] First real deployment from zero (§8 steps 2-5), manual, region eu-central-1, 2026-11-26. See [first-deployment.md](first-deployment.md)
- [ ] Switch day-to-day deploys to GitHub Actions ([first-deployment.md §7](first-deployment.md#7-optional-switch-to-github-actions-path-b))
- [x] `index-app` (nginx on 3000, links to the apps) and `empty-login` (Express mounted at `/empty-login`) code, with Dockerfiles and health endpoints

---

## 1. How it works

```
Browser
  └─ https://dxxxx.cloudfront.net            single entry point: CloudFront "refplatform-cdn" (platform stack)
       └─ http://<ALB>                        one ALB, Ingress group "refplatform", listener :80
            ├─ /simple-cms*   → ns simple-cms  / svc simple-cms   (group.order 100)
            ├─ /empty-login*  → ns empty-login / svc empty-login  (group.order 110)
            ├─ /<next-app>*   → ns <next-app>  / ...              (group.order 120, 130, …)
            ├─ /*             → ns index-app   / svc index-app    (group.order 900)  landing page
            └─ everything else → fixed 404 "no route"             (group.order 1000) ns refplatform-ingress
```

- CloudFront has one default behaviour that forwards every path unchanged to the ALB.
- The ALB evaluates Ingresses lowest `group.order` first (ties sorted by namespace/name). `index-app` owns `/`, so it must have the **highest** app order (900). Until it's deployed, `/` returns the catch-all 404.
- **The ALB does not strip the prefix.** Each app must serve under `/<app>` (Next.js `basePath`).
- Each app is fully isolated: its own namespace, quota, ServiceAccount + IRSA role, Secrets Manager secret, Deployment, Service, Ingress, ECR repo, Terraform state and workflow.

### Route / order registry (keep current, orders must be unique)

| App | Source | Path | group.order | Namespace | ECR repo | Extra infra |
|---|---|---|---|---|---|---|
| simple-cms | `apps/simple-cms` | `/simple-cms` | 100 | `simple-cms` | `refplatform/simple-cms` | MongoDB |
| empty-login | `apps/empty-login` | `/empty-login` | 110 | `empty-login` | `refplatform/empty-login` | — |
| index-app | `apps/index-app` | `/` | 900 | `index-app` | `refplatform/index-app` | — |
| *(catch-all)* | — | `/` | 1000 | `refplatform-ingress` | — | — |

---

## 2. Naming convention (D9)

### 2.1 Rules
- **Shared/platform resources:** `refplatform-<component>` (AWS names allow hyphens; use lowercase).
- **Per-app AWS resources:** `refplatform-<app>-<component>` (IAM roles, etc.), so one app's resources are easy to find and to scope IAM to.
- **Hierarchical names** (ECR, Secrets Manager, SSM, S3 keys): `refplatform/<scope>/<name>` with `/` as separator.
- **Kubernetes:** an app namespace is just `<app>` (short, readable URLs/kubectl). Shared namespaces use the `refplatform-` prefix. Every resource gets the labels `app.kubernetes.io/part-of=refplatform` and `app.kubernetes.io/name=<app>`.
- **Tags on every AWS resource:** `Project=refplatform`, `ManagedBy=terraform`, `Stack=<bootstrap|platform|app>`, and on app resources `App=<app>`. (No `Environment` tag, since there is one environment per D8.)
- **App names:** lowercase, dashes, ≤ 20 chars (they appear in IAM role names, limited to 64 chars).

### 2.2 Name map

| Resource | Old | New |
|---|---|---|
| State bucket | `app-tfstate-<account>` | `refplatform-tfstate-<account>` |
| State keys | `app/terraform.tfstate` | `platform/eks.tfstate`, `apps/<app>.tfstate` |
| VPC | `demo-eks-cluster-vpc` | `refplatform-vpc` |
| EKS cluster | `demo-eks-cluster` | `refplatform-eks` |
| Cluster IAM (node, EBS CSI, LB controller) | `demo-eks-cluster-*` | `refplatform-eks-*` (derived from the cluster name) |
| ALB Ingress group | `demo` | `refplatform` |
| Shared Ingress namespace / name | `ingress` / `public` | `refplatform-ingress` / `public` |
| ALB (AWS name, set via `load-balancer-name` annotation) | auto `k8s-demo-…` | `refplatform-alb` |
| CloudFront | `globomantics application` (per app) | `refplatform-cdn` (shared) |
| ECR | `globomantics` | `refplatform/<app>` |
| Secrets Manager read policy | `demo-eks-cluster-secrets-manager-read` (shared, scope `eks/<cluster>/*`) | none shared: inline policy `read-own-secret` on each app's IRSA role, scoped to that app's secret only |
| App secret | `eks/demo-eks-cluster/globomantics` | `refplatform/apps/<app>` |
| App IRSA role | `demo-eks-cluster-globomantics` | `refplatform-<app>-irsa` |
| App namespace / SA / Deployment / Service / Ingress | `globomantics` / `globomantics-app` | `<app>` (all of them) |
| StorageClass | `ebs-gp3` (inside the mongodb module) | `refplatform-gp3` (platform stack) |
| MongoDB Helm release / DB name | `globomantics` / `globomantics` | `mongodb` in ns `simple-cms` / DB `simple-cms` |
| SSM parameters | — | `/refplatform/platform/public_base_url`, `/refplatform/platform/ingress_group`, … |
| GitHub OIDC roles | set by hand | `refplatform-gh-build`, `refplatform-gh-deploy`, `refplatform-gh-infra` (created by `terraform/s3-state`) |
| GitHub settings | secrets `AWS_ROLE_ARN`, `AWS_BUILD_ROLE_ARN` + ~20 variables | variable `AWS_ACCOUNT_ID` only (role ARNs derived by name). Environments `infra`, `infra-plan` |

### 2.3 Where the old names live (rename checklist)
- Terraform: `terraform/eks/main.tf` (tags, `cluster_name`, ECR repo), `terraform/eks/modules/ingress/main.tf` (group `demo`), `terraform/eks/modules/ecr/main.tf` (stale "payment-api" comment), `terraform/eks/modules/eks/main.tf`, `terraform/s3-state/main.tf` (bucket + tags), all of `terraform/app/**` (removed and replaced, §4).
- Workflows: `build-app.yml`, `deploy-app.yml` (replaced, §7).
- Docs: `CLAUDE.md`, `terraform/eks/README.md`, `terraform/app/README.md`, `doc/readme.md`, `doc/github-readme.md`.
- **simple-cms technical identifiers** (renamed): `package.json` name → `simple-cms`, local Mongo DB name in `.env example` and `scripts/start-memory-mongo.ts` → `simple-cms`, default admin email `admin@globomantics.local` → `admin@refplatform.local` (`.env example`, `scripts/seed.ts`, `app/admin/login/page.tsx`).
- **simple-cms visible branding** ("Globomantics" title in README / `AdminNav.tsx` / login page, the `globo-*` Tailwind color tokens, seeded marketing content): this is the demo site's *content*, not infra. **Default: leave it as-is.** See open question Q1.

---

## 3. Repository layout (target)

```
apps/                    (was code/)
  simple-cms/            Next.js CMS demo
  index-app/             landing page (static, nginx)
  empty-login/           demo app (Express)

terraform/
  s3-state/              bootstrap (local state): refplatform-tfstate-<account> bucket,
                         recommended: GitHub OIDC provider + refplatform-gh-* roles
  eks/                   PLATFORM (S3 key platform/eks.tfstate): refplatform-vpc, refplatform-eks,
                         LB controller, refplatform-ingress/public + 404, CSI/ASCP, refplatform-secrets-read,
                         refplatform-gp3 StorageClass, ECR refplatform/<app> for each app, refplatform-cdn, SSM params
  modules/
    web-app/             reusable: namespace, quota, limit range, SA + IRSA, secret + SecretProviderClass,
                         Deployment, Service, Ingress (path, order, health-check path)
    mongodb/             reusable Bitnami MongoDB release
  apps/
    simple-cms/          thin root (S3 key apps/simple-cms.tfstate): web-app + mongodb
    index-app/           thin root: web-app
    empty-login/         thin root: web-app
  (terraform/app/ removed)

.github/workflows/
  _build-app.yml  _deploy-app.yml          reusable
  app-simple-cms.yml  app-index-app.yml  app-empty-login.yml
  apps-redeploy-all.yml                    manual
  infra-eks.yml                            platform
```

**Why a thin root per app** (rather than one generic root with toggles): each demo app brings its own databases and services (D3). Its own root folder can hold those next to the standard `web-app` module without feature flags. The common parts stay in one module.

---

## 4. Terraform changes

### 4.1 `terraform/s3-state` (bootstrap)
Bucket `refplatform-tfstate-<account>`, `Stack=bootstrap` tags. Recommended: also the GitHub OIDC provider and the three `refplatform-gh-*` roles (§7.3), so a rebuild from zero is fully reproducible.

### 4.2 Platform stack (`terraform/eks`)
1. **S3 backend** `refplatform-tfstate-<account>` / `platform/eks.tfstate`, `use_lockfile = true`, Terraform `>= 1.10`.
2. **One `project` local** (`refplatform`) that every name is built from: cluster `${project}-eks`, VPC `${project}-vpc`, group `${project}`, etc.
3. **`apps` variable** (list of app names) → ECR `for_each`, repo `refplatform/<app>`. Lifecycle rule: keep the last 10 `sha-` tags (today's rule doesn't match `sha-`, so nothing expires).
4. **Shared Ingress:** namespace `refplatform-ingress`, group `refplatform`, `alb.ingress.kubernetes.io/load-balancer-name: refplatform-alb`.
5. **Shared CloudFront** `refplatform-cdn` (from `terraform/app/modules/cloudfront`). Optional: a `*/_next/static/*` behaviour with *CachingOptimized*.
6. **`refplatform-gp3` StorageClass** (cluster-scoped, so it can't live in an app's module).
7. **No shared secrets policy.** A shared policy would let any app read every app's secrets, so each app's IRSA role gets an inline policy for its own secret instead (`terraform/modules/web-app`).
8. **SSM** `/refplatform/platform/{public_base_url, ingress_group, ingress_class, cluster_name}` for the app stacks.
9. **EKS admin access:** an explicit `cluster_admin_principal_arns` list (you + `refplatform-gh-infra` + `refplatform-gh-deploy`) instead of "current caller" in `modules/eks/access.tf`.

### 4.3 `terraform/modules/web-app`
Inputs: `name`, `image`, `container_port` (3000), `replicas`, `resources`, `quota`, `limit_range`, `path`, `ingress_order`, `health_path`, `env`, `secrets` (map → Secrets Manager `refplatform/apps/<name>` → env vars), `cluster_name`, `aws_region`.
It always sets the Ingress annotation `alb.ingress.kubernetes.io/healthcheck-path = health_path`. **This is required:** the default health check `/` is 404 under a base path → targets unhealthy → 502.

### 4.4 `terraform/apps/<app>` roots
`backend.tf` (key `apps/<app>.tfstate`), `providers.tf`, `versions.tf`, `variables.tf` (only `image` is required), and `main.tf` with `locals { name, path, order }` + `module "web_app"` + any app-specific resources. Settings live in `locals`, committed, so there's no long `-var` list in CI.
simple-cms adds `module "mongodb"` and secrets `MONGODB_URI`, `AUTH_SECRET`, `ADMIN_EMAIL`, `ADMIN_PASSWORD`. `AUTH_URL` = SSM `public_base_url` (origin only; see §6).

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

---

## 6. simple-cms changes for `/simple-cms`

| Change | Where |
|---|---|
| `basePath: "/simple-cms"` (+ `NEXT_PUBLIC_BASE_PATH`) | `next.config.ts` (links, `redirect`, `router.push`, `_next`, fonts get the prefix automatically) |
| Prefix raw `fetch("/api/...")` through a helper | `app/admin/registrations/page.tsx`, `components/admin/AdminNav.tsx`, `components/ConferenceSignup.tsx`, `components/admin/CrudTable.tsx` |
| Auth.js: server keeps its default `basePath` `/api/auth` (Next.js strips `/simple-cms` before route handlers; setting `/simple-cms/api/auth` server-side breaks with `UnknownAction`). The client `SessionProvider basePath="/simple-cms/api/auth"`. `AUTH_URL` = CloudFront origin **without a path** | `lib/auth.config.ts`, `components/admin/Providers.tsx`, Terraform env |
| Cookie names prefixed `simple-cms.` | `lib/auth.config.ts` |
| String `<Image src="/...">` gets no prefix | site pages + image paths in `scripts/seed.ts` |
| Health path `/simple-cms/api/health` | Terraform + workflow |
| Technical renames from §2.3 (package name, DB name, admin email) | as listed |
| Local dev: `http://localhost:3000/simple-cms` | `README.md` |

---

## 7. CI/CD

### 7.1 Per-app workflow (`app-simple-cms.yml`)
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
- Build → deploy in **one run** via `needs:` (replaces `workflow_run` and its "latest successful build" lookup, which would mix up apps that build in parallel).
- Image `<account>.dkr.ecr.<region>.amazonaws.com/refplatform/<app>:sha-<12>`. Immutable, and the push is skipped if the tag exists.
- Deploy: `terraform -chdir=terraform/apps/<app> init -backend-config="bucket=refplatform-tfstate-<account>"`, then `apply -auto-approve -var image=…`.
- `concurrency: refplatform-deploy-<app>`. Branch pushes only build/test. Only `main` deploys.
- Changes to `terraform/modules/**` → manual `apps-redeploy-all.yml` (matrix over `terraform/apps/*`, current image).

### 7.2 Infra (`infra-eks.yml`)
PR on `terraform/eks/**` → fmt, validate, plan (in the job summary). Push `main` → plan → apply in Environment `infra` (you approve). `destroy` and `s3-state` stay manual.

### 7.3 GitHub OIDC roles
Workflows build the ARN `arn:aws:iam::${{ vars.AWS_ACCOUNT_ID }}:role/<role>`, so no secrets are needed. Each role's trust policy pins the `repository` claim and matches `sub` with `repo:OWNER*/REPO*:…`, which covers both subject formats.

| Role | Trusted for | Scope |
|---|---|---|
| `refplatform-gh-build` | any ref | ECR push `refplatform/*` |
| `refplatform-gh-deploy` | `ref:refs/heads/main` | state `apps/*`, EKS describe + access entry, Secrets Manager `refplatform/apps/*`, IAM `refplatform-*-irsa` (create + inline policies), SSM `/refplatform/*` read, ECR describe |
| `refplatform-gh-infra` | `environment:infra`, `environment:infra-plan` | `AdministratorAccess` + EKS access entry |

---

## 8. Fresh-start rollout order

Step-by-step walkthrough of steps 2-5: [first-deployment.md](first-deployment.md).

1. `git mv code apps`, the renames (§2.3), the Terraform restructure (§4), simple-cms changes (§6), workflows (§7) and docs, all on one branch.
2. Manual: `terraform/s3-state` apply → set GitHub secrets → create Environment `infra`.
3. `terraform/eks` apply (via `infra-eks`, or locally against the S3 backend the first time).
4. `app-simple-cms` → `https://<cf>/simple-cms/`.
5. `app-index-app` → `https://<cf>/`, `app-empty-login` → `https://<cf>/empty-login/`.

---

## 9. Checklist: add a new app

1. `apps/<app>/` following §5.
2. Free `group.order` → add a row to the §1 registry.
3. Add `<app>` to `apps` in `terraform/eks` → PR → approve `infra-eks` (creates ECR `refplatform/<app>`).
4. `terraform/apps/<app>/`: copy `empty-login`'s root, change `locals`, add app-specific DBs/services.
5. `.github/workflows/app-<app>.yml`: copy a caller and change the name/health path.
6. Merge → `https://<cf>/<app>/`. Add a link in `index-app`.

Remove: manual `terraform destroy` in `terraform/apps/<app>`, remove it from `apps` (ECR needs `force_delete` or an empty repo), delete its workflow and code.

---

## 10. Risks and gotchas
- Missing ALB health-check path → 502 (§4.3).
- `index-app` order not the highest → `/` swallows every app.
- Cookie collisions on the shared hostname (§5).
- Capacity: per-app quotas default to 2 CPU / 4 Gi requests. Use small quotas for small demos and size the node group for the sum.
- `NEXT_PUBLIC_*` values are build-time. Keep base paths static.
- `load-balancer-name` must be set on exactly one Ingress in the group (the shared one), or ALB names conflict.

## 11. Questions (resolved 2026-11-25: both defaults kept)
| # | Question | Default |
|---|---|---|
| Q1 | Rename simple-cms's *visible* "Globomantics" branding (titles, `globo-*` colour tokens, seeded content) too, or keep it as the CMS demo's sample content? | Keep it. Only technical identifiers are renamed |
| Q2 | Keep the folder name `terraform/eks` for the platform stack, or rename it to `terraform/platform`? Keep `terraform/eks` (as written in this plan). Renaming is cheap: the folder, the `infra-eks.yml` paths, and the docs |
