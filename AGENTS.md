# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, Cursor, …) working in this repository. Folders with their own `AGENTS.md` add rules for that part of the tree:

- [`apps/simple-cms/AGENTS.md`](apps/simple-cms/AGENTS.md): the Next.js CMS (commands, base path, auth, data, CRUD API)
- [`terraform/AGENTS.md`](terraform/AGENTS.md): infrastructure (layers, commands, apply/destroy order)

## Repository layout

RefPlatform: one EKS cluster hosting many independent apps behind one CloudFront URL, each app on its own path prefix (`https://<cf>/<app>/`). Everything uses the `refplatform` naming convention (see `doc/architecture.md` §2).

- `apps/<app>/`: app source, one folder per app.
  - `simple-cms`: Next.js 16 + React 19 + TS + Tailwind v4 + MongoDB + NextAuth v5 beta. The main app.
  - `index-app`: the landing page at `/`. Static HTML on unprivileged nginx, port 3000. `nginx.conf` serves `/api/health`, and `public/index.html` links to every app.
  - `empty-login`: Express 5, routes mounted at `BASE_PATH` (`/empty-login`) in `server.js`. The asset and form URLs in `public/*.html` hard-code the prefix. Login accepts any credentials.
  - `new-app/README.md`: the full guide for adding an app.
- `terraform/`: bootstrap (`s3-state`), platform (`eks`), shared `modules/`, and one root per app (`apps/<app>`).
- `.github/workflows/`: one `app-<app>.yml` per app, `infra-eks.yml`, `apps-redeploy-all.yml`, reusable `_build-app.yml` / `_deploy-app.yml`.
- `doc/`:
  - `architecture.md`: principles, naming, route/order registry, app contract
  - `first-deployment.md`: step-by-step first deployment from zero
  - `readme.md`: manual runbook, incl. destroy
  - `github-readme.md`: CI setup

Read the relevant doc before changing infrastructure, CI or routing.

## App contract and routing

- The ALB routes by path prefix and **does not strip it**, so each app serves under `/<app>` (Next.js `basePath`, Express mount, …).
- `index-app` owns `/` with the highest `group.order` (900). Other apps use unique orders < 900 (simple-cms 100, empty-login 110). Keep the registry tables in `doc/architecture.md` §1 and `terraform/apps/README.md` in sync.
- Every app exposes `GET <base>/api/health` → 200. The k8s probes, the ALB health check (via the `healthcheck-path` annotation) and the CI smoke test all use it.
- Every app has a Dockerfile listening on port 3000 that starts without secrets.
- Apps share one hostname: cookies must be app-prefixed and/or path-scoped.
- Never put `load-balancer-name` or other "exclusive" ALB annotations on app Ingresses. Only the shared Ingress in `terraform/eks/modules/ingress` sets them.

## CI/CD

- Repository variable `AWS_ACCOUNT_ID` (and optional `AWS_REGION`). No secrets: role ARNs are `arn:aws:iam::<AWS_ACCOUNT_ID>:role/refplatform-gh-*`, assumed through OIDC.
- `app-<app>.yml` (paths `apps/<app>/**`, `terraform/apps/<app>/**`) calls the reusable `_build-app.yml`: lint, tsc, docker build, smoke test on the health path, push. It is a no-op without a Dockerfile. On `main`, it then calls `_deploy-app.yml`: terraform apply with that run's tag. A manual run with `image_tag` rolls back.
- ECR tags are **immutable**: every image needs a new tag. CI uses `sha-<12-char-sha>`, and the last 15 are kept.
- `apps-redeploy-all.yml` (manual) re-applies every `terraform/apps/*` with its current image. Use it after changing `terraform/modules/**`.
- `infra-eks.yml`:
  - On a PR: plan, in Environment `infra` (needs approval).
  - On `main`: plan (Environment `infra-plan`), then apply of the saved plan (Environment `infra`, needs approval).

## Adding an app

Full guide: `apps/new-app/README.md`. Short versions: `doc/architecture.md` §7, `terraform/apps/README.md`.

1. Register the app in `terraform/eks/apps.tf` and get `infra-eks` applied (this creates the ECR repo), in a separate merge.
2. Then add the app code, its `terraform/apps/<app>` root and its caller workflow.

The CI deploy role can't create general AWS resources (S3, SQS, RDS…) for an app. Those need `terraform/s3-state/github.tf` or `terraform/eks`.

## Conventions

- Only `simple-cms` has lint/type checks (see its `AGENTS.md`). There is no test suite.
- Don't commit `.env*`, `terraform.tfstate*` or `.terraform/`.
- Commands in the docs are bash (Git Bash on Windows). Region is `eu-central-1`.
