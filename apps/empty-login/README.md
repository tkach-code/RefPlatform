# empty-login

RefPlatform standalone demo app (no shared login/SSO): a minimal Express 5 login page. `POST /empty-login/login` accepts any username/password (no real auth) and redirects to `/empty-login/home?username=...`.

## Run locally

```bash
npm install
npm run dev          # http://localhost:3000/empty-login/  (PORT / HOST env vars override 3000 / 0.0.0.0)
```

Docker: `docker build -t empty-login . && docker run --rm -p 3000:3000 empty-login`

The base path is `BASE_PATH` in `server.js`. The asset and form URLs in `public/*.html` hard-code `/empty-login`, so change them together.

| | |
|---|---|
| Public URL | `https://<cloudfront>/empty-login` |
| Base path | `/empty-login` |
| Health check | `GET /empty-login/api/health` → 200 |
| Infrastructure | [terraform/apps/empty-login](../../terraform/apps/empty-login) |
| Image | ECR `refplatform/empty-login:sha-<12>` |

## Contract (must hold before the first deploy)

- Serve every page, API and asset under `/empty-login`. The ALB forwards paths unchanged. For Next.js, set `basePath`: `"/empty-login"` in `next.config.ts`, and wrap raw `fetch()`/image/CSS URLs (see `apps/simple-cms/lib/base-path.ts`).
- `GET /empty-login/api/health` returns 200 without auth or a database.
- `Dockerfile` in this folder. The container listens on port **3000** and starts without real secrets (the CI smoke test runs it bare).
- If `package-lock.json` exists: `npm ci` works, and `npm run lint` runs if defined. `tsc --noEmit` runs when `tsconfig.json` exists.
- Cookies are prefixed with `empty-login.` or scoped to `Path=/empty-login`. All apps share one hostname.
- Config comes from env vars: `env` / `secrets` in `terraform/apps/empty-login/main.tf` (secrets are stored in Secrets Manager `refplatform/apps/empty-login`).
