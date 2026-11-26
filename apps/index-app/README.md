# index-app

RefPlatform landing page with links to every demo app. It owns `/` (ALB group.order 900, the highest), so it receives every path no other app matched.

Static HTML/CSS/JS served by `nginxinc/nginx-unprivileged` on port 3000. `nginx.conf` answers `/api/health` itself. Add a link to the `<ul class="apps">` list in `public/index.html` for every new app (step 6 of [apps/new-app/README.md](../new-app/README.md)). For local Docker runs, see `README.TXT`.

| | |
|---|---|
| Public URL | `https://<cloudfront>/` |
| Base path | `/` |
| Health check | `GET /api/health` → 200 |
| Infrastructure | [terraform/apps/index-app](../../terraform/apps/index-app) |
| Image | ECR `refplatform/index-app:sha-<12>` |

## Contract (must hold before the first deploy)

- Serve at the site root `/`. Don't set a Next.js `basePath`. Links to other apps are relative (`/simple-cms/`, `/empty-login/`), so they work on any CloudFront domain. Avoid routes that start with another app's prefix: those paths never reach this app.
- `GET /api/health` returns 200 without auth or a database.
- `Dockerfile` in this folder. The container listens on port **3000** and starts without real secrets (the CI smoke test runs it bare).
- If `package-lock.json` exists: `npm ci` works, and `npm run lint` runs if defined. `tsc --noEmit` runs when `tsconfig.json` exists.
- Cookies are prefixed with `index-app.` or scoped to `Path=/`. All apps share one hostname.
- Config comes from env vars: `env` / `secrets` in `terraform/apps/index-app/main.tf` (secrets are stored in Secrets Manager `refplatform/apps/index-app`).
