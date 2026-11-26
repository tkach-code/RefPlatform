# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

RefPlatform: one EKS cluster hosting many independent demo apps behind one CloudFront URL, each app on its own path prefix (`https://<cf>/<app>/`). Everything uses the `refplatform` naming convention (see `doc/multi-app-platform-plan.md` §2).

- `apps/<app>/` — app source, one folder per app. `simple-cms` (Next.js 16 + React 19 + TS + Tailwind v4 + MongoDB + NextAuth v5 beta) is the main app. `index-app` is the landing page at `/`: static HTML on unprivileged nginx, port 3000. `nginx.conf` serves `/api/health`, and `public/index.html` links to every app. `empty-login` is Express 5 with its routes mounted at `BASE_PATH` (`/empty-login`) in `server.js`. The asset and form URLs in its `public/*.html` hard-code the prefix, and login accepts any credentials.
- `terraform/` — apply in this order:
  1. `s3-state` — bootstrap, **local state**: bucket `refplatform-tfstate-<account>` + GitHub OIDC provider and roles `refplatform-gh-{build,deploy,infra}` (only when `github_repository` is set).
  2. `eks` — platform, state key `platform/eks.tfstate`: VPC, EKS `refplatform-eks`, LB controller + shared Ingress `refplatform-ingress/public` (ALB `refplatform-alb`, group `refplatform`, catch-all 404 at order 1000), CloudFront `refplatform-cdn`, ECR `refplatform/<app>` for each entry in `apps.tf`, Secrets Store CSI + ASCP, StorageClass `refplatform-gp3`, SSM params `/refplatform/platform/*`, EKS admin access entries.
  3. `apps/<app>` — one thin root per app, state key `apps/<app>.tfstate`. Uses `terraform/modules/web-app` (namespace, quota, IRSA role `refplatform-<app>-irsa` with an inline policy for its own secret `refplatform/apps/<app>`, SecretProviderClass, Deployment, Service, Ingress in the shared group) plus app-specific resources (simple-cms: `modules/mongodb`). Platform values come from SSM, not remote state.
- `doc/` — `multi-app-platform-plan.md` (decisions, route/order registry, app contract), `first-deployment.md` (step-by-step first deployment from zero), `readme.md` (manual runbook incl. destroy), `github-readme.md` (CI setup).

## App contract and routing

- The ALB routes by path prefix and **does not strip it**, so each app serves under `/<app>` (Next.js `basePath`). `index-app` owns `/` with the highest `group.order` (900). Other apps use unique orders < 900 (simple-cms 100, empty-login 110). Keep the registry tables in the plan doc and `terraform/apps/README.md` in sync.
- Every app exposes `GET <base>/api/health` → 200 (used by k8s probes, the ALB health check via the `healthcheck-path` annotation, and the CI smoke test). It needs a Dockerfile listening on port 3000 that starts without secrets.
- Apps share one hostname: cookies must be app-prefixed and/or path-scoped.
- Never put `load-balancer-name` or other "exclusive" ALB annotations on app Ingresses. Only the shared Ingress in `terraform/eks/modules/ingress` sets them.

## simple-cms (run in `apps/simple-cms`)

```bash
npm install
npm run dev              # http://localhost:3000/simple-cms, admin at /simple-cms/admin/login
npm run build            # output: "standalone" (used by the Dockerfile)
npm run lint
npx tsc --noEmit --incremental false
npm run mongo:memory     # in-memory MongoDB when Docker isn't available
npm run seed             # WIPES and reseeds all collections, incl. admin user
```

No test suite. Env: `.env.local` from the template literally named `.env example`: `MONGODB_URI`, `AUTH_SECRET`, `AUTH_URL` (origin only, no path), `ADMIN_EMAIL`, `ADMIN_PASSWORD`.

- **Base path:** `next.config.ts` sets `basePath: "/simple-cms"` and inlines `NEXT_PUBLIC_BASE_PATH`. Next adds the prefix to `<Link>`, `redirect()`, `router.push()` and `_next` assets. Wrap raw `fetch("/api/...")`, string `<Image src>`, CSS `url()` and next-auth client callback URLs with `withBasePath()` from `lib/base-path.ts`. Image paths in Mongo are stored unprefixed.
- **Auth split:** `lib/auth.config.ts` is provider-less and used by `middleware.ts` (guards `/admin/:path*` except `/admin/login`). `lib/auth.ts` adds Credentials (bcrypt against `users`). Server-side Auth.js keeps its default basePath `/api/auth` (Next strips `/simple-cms` before route handlers). The client `SessionProvider` (`components/admin/Providers.tsx`) uses `/simple-cms/api/auth`. Cookies are `simple-cms.*` with `Path=/simple-cms`, and `Secure` when `AUTH_URL` is https. API routes enforce auth via `requireAdmin()` in `lib/api-auth.ts`. Middleware doesn't cover `/api`.
- **Data:** `lib/mongodb.ts` caches one `MongoClient` on `global`, and the DB name comes from the URI path. `lib/data.ts` read helpers are used directly by server components. Public `(site)` and admin list pages are `force-dynamic`.
- **Generic CRUD API:** most `app/api/<resource>/route.ts` and `[id]/route.ts` are one-liners over `makeCrudHandlers` / `makeCrudIdHandlers` (`lib/crud.ts`) with a Zod schema from `lib/schemas.ts`. They require an admin session for every method, GET included. Adding a resource = schema + type in `models/types.ts` + two route files + admin pages/form.
- Exceptions: `api/registrations` POST is public. `api/health` is unauthenticated. `api/seed` (admin POST) imports `scripts/seed.ts`, so that script is bundled as well as run via `tsx`.
- Collections: `products`, `categories`, `mediaItems`, `storySections`, `events`, `pageContent`, `registrations`, `users`.

## Terraform

```bash
cd terraform/<eks|apps/<app>>
terraform init -backend-config="bucket=refplatform-tfstate-<account-id>"   # key/region/lockfile are in versions.tf
terraform plan
terraform apply                       # apps: -var image=<acct>.dkr.ecr.eu-central-1.amazonaws.com/refplatform/<app>:<tag>
```

- Terraform >= 1.10 (S3 `use_lockfile`). `terraform init -backend=false && terraform validate` works offline for every root.
- ECR tags are **immutable**: every image needs a new tag. CI uses `sha-<12-char-sha>`, and the last 15 are kept.
- `terraform/eks/terraform.tfvars` is committed and holds `cluster_admin_principal_arns` (human admins). CI roles are added by `github_ci_roles_enabled`.
- Destroy order: every `apps/*` (`-var image=unused`), then `eks` (the Ingress cleanup helper `modules/ingress/cleanup.cmd` → `cleanup.py` needs `python3`), then `s3-state` (empty the versioned bucket first).
- After the first deploy, seed simple-cms via port-forward (`terraform/apps/README.md`).

## CI/CD

- Repository variable `AWS_ACCOUNT_ID` (and optional `AWS_REGION`). No secrets: role ARNs are `arn:aws:iam::<AWS_ACCOUNT_ID>:role/refplatform-gh-*`.
- `app-<app>.yml` (paths `apps/<app>/**`, `terraform/apps/<app>/**`) → reusable `_build-app.yml` (lint, tsc, docker build, smoke test on the health path, push; no-op without a Dockerfile) → on `main`, `_deploy-app.yml` (terraform apply with that run's tag). Manual run with `image_tag` = rollback.
- `apps-redeploy-all.yml` (manual): re-applies every `terraform/apps/*` with its current image. Use it after changing `terraform/modules/**`.
- `infra-eks.yml`: PR → plan (Environment `infra`, needs approval). `main` → plan (Environment `infra-plan`) → apply of the saved plan (Environment `infra`, approval).
- Adding an app: plan doc §9 / `terraform/apps/README.md`. Register it in `terraform/eks/apps.tf` first (ECR repo), then add the app root and caller workflow.
