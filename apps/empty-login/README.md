# empty-login

A minimal Express 5 login page. `POST /empty-login/login` accepts any username and password (there is no real authentication) and redirects to `/empty-login/home?username=...`. It sets no cookies and needs no secrets or database.

| | |
|---|---|
| Public URL | `https://<cloudfront>/empty-login/` |
| Base path | `/empty-login` |
| Health check | `GET /empty-login/api/health` → 200 `{"status":"ok"}` |
| Infrastructure | [terraform/apps/empty-login](../../terraform/apps/empty-login) (ALB order 110) |
| CI | [app-empty-login.yml](../../.github/workflows/app-empty-login.yml) |
| Image | ECR `refplatform/empty-login:sha-<12>` |

## Run locally

```bash
npm install
npm run dev          # http://localhost:3000/empty-login/  (PORT / HOST env vars override 3000 / 0.0.0.0)
```

Docker:

```bash
docker build -t empty-login .
docker run --rm -p 3000:3000 empty-login
```

## Structure

| File | What |
|---|---|
| `server.js` | Express app. Serves `public/` and the routes under `BASE_PATH`, the health endpoint, and redirects `/` to `/empty-login/` |
| `routes.js` | `POST /login` |
| `public/` | `index.html` (login form), `home.html`, `script.js`, `styles.css` |

The base path is `BASE_PATH` in `server.js`. The asset and form URLs in `public/*.html` hard-code `/empty-login`, so change them together, along with `terraform/apps/empty-login/main.tf` and the workflow's `health_path`.

Configuration, when needed, goes into `env` / `secrets` of `module "web_app"` in `terraform/apps/empty-login/main.tf`. Secrets are stored in Secrets Manager `refplatform/apps/empty-login`.

This is the simplest app on the platform and the template to copy when [adding a new app](../new-app/README.md).
