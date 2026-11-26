# index-app

The RefPlatform landing page, with links to every app. It owns `/` (ALB group.order 900, the highest app order), so it receives every path that no other app matched, and nginx answers unknown paths with 404.

Static HTML/CSS/JS served by `nginxinc/nginx-unprivileged` on port 3000. `nginx.conf` answers `/api/health` itself.

| | |
|---|---|
| Public URL | `https://<cloudfront>/` |
| Base path | `/` |
| Health check | `GET /api/health` → 200 |
| Infrastructure | [terraform/apps/index-app](../../terraform/apps/index-app) (ALB order 900) |
| CI | [app-index-app.yml](../../.github/workflows/app-index-app.yml) |
| Image | ECR `refplatform/index-app:sha-<12>` |

## Structure

```
.
├── Dockerfile
├── nginx.conf          # nginx server config, port 3000, /api/health
└── public/             # site root, served as-is
    ├── index.html      # app list: <ul class="apps">
    ├── about.html
    ├── css/style.css
    └── js/main.js
```

## Add a link to a new app

Add an entry to the `<ul class="apps">` list in `public/index.html` (step 6 of [apps/new-app/README.md](../new-app/README.md)). Use relative links (`/simple-cms/`, `/empty-login/`) so they work on any CloudFront domain:

```html
<li><a href="/new-app/">New App</a>: one-line description</li>
```

Don't add pages whose paths start with another app's prefix: those requests never reach this app.

## Run locally

```bash
docker build -t index-app .
docker run --rm -p 8080:3000 index-app
```

Open <http://localhost:8080> (health: <http://localhost:8080/api/health>).

To edit without rebuilding, mount the `public` folder so changes show up on page refresh:

```bash
docker run --rm -p 8080:3000 -v "$(pwd)/public:/usr/share/nginx/html:ro" index-app
```

(PowerShell: use `${PWD}/public` instead of `$(pwd)/public`.)
