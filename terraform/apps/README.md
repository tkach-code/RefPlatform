# App stacks

One small Terraform root per app. Each one uses the shared [`web-app`](../modules/web-app) module and adds any app-specific infrastructure (simple-cms adds [`mongodb`](../modules/mongodb)).

| App | Path | group.order | Extra |
|---|---|---|---|
| simple-cms | `/simple-cms` | 100 | MongoDB |
| empty-login | `/empty-login` | 110 | — |
| index-app | `/` | 900 (must be highest) | — |

Keep this table in sync with [doc/multi-app-platform-plan.md](../../doc/multi-app-platform-plan.md) §1.

What `web-app` creates for app `<app>`:
- namespace `<app>`, with a ResourceQuota and LimitRange
- IAM role `refplatform-<app>-irsa` and ServiceAccount `<app>`
- when `secrets` is set: Secrets Manager `refplatform/apps/<app>`, mounted with the CSI driver and exposed as env vars (the role can read only this secret)
- Deployment, Service (port 80 → `container_port`), and an Ingress in the shared ALB group, with the ALB health check on `health_path`

State: `s3://refplatform-tfstate-<account>/apps/<app>.tfstate`. Platform values come from SSM `/refplatform/platform/*`.

## Deploy

CI: `.github/workflows/app-<app>.yml` builds on every push touching `apps/<app>/**` or `terraform/apps/<app>/**`, and deploys from `main`. Run it manually with `image_tag` to redeploy or roll back.
After changing `terraform/modules/**`, run **apps-redeploy-all** to re-apply every deployed app with its current image.

Locally:
```bash
cd terraform/apps/<app>
terraform init -backend-config="bucket=refplatform-tfstate-<account-id>"
terraform apply -var="image=<account>.dkr.ecr.eu-central-1.amazonaws.com/refplatform/<app>:sha-<12>"
terraform output url
```

## Add an app

1. **Code** in `apps/<app>/`. Follow the app contract:
   - Serve everything under `/<app>` (Next.js `basePath`; `index-app` uses `/`).
   - Return 200 from `GET /<app>/api/health`.
   - Provide a `Dockerfile`, listening on port 3000.
   - Start without real secrets (CI smoke test).
   - Prefix cookie names with the app name, or scope them to `Path=/<app>`.
2. **Registry:** pick an unused `group.order` (< 900) and add a row to the table above and to the plan doc.
3. **ECR:** add `<app>` to `terraform/eks/apps.tf`, then merge and approve `infra-eks`.
4. **Terraform:** copy `terraform/apps/empty-login` to `terraform/apps/<app>`. Change `locals` (`app`, `path`, `order`, `health_path`), the backend `key` in `versions.tf`, and add `env`/`secrets` or extra resources.
5. **Workflow:** copy `.github/workflows/app-empty-login.yml` to `app-<app>.yml` and replace the name and health path.
6. **Ship:** merge to `main`. The app is at `https://<cloudfront>/<app>/`. Add a link to it in `index-app`.

Remove an app:
1. Run `terraform destroy -var image=unused` in `terraform/apps/<app>` (the image value doesn't matter for destroy).
2. Remove it from `terraform/eks/apps.tf` (deletes the repository).
3. Delete its workflow, Terraform root and code.

## simple-cms admin user

The database starts empty. Seed content and the admin user once after the first deploy, from `apps/simple-cms`:

```bash
kubectl -n simple-cms port-forward svc/mongodb 27017:27017 &
cd terraform/apps/simple-cms
ADMIN_EMAIL=$(terraform output -raw admin_email)
ADMIN_PASSWORD=$(terraform output -raw admin_password)
MONGO_PW=$(kubectl -n simple-cms get secret mongodb -o jsonpath='{.data.mongodb-root-password}' | base64 -d)
cd ../../../apps/simple-cms
MONGODB_URI="mongodb://root:${MONGO_PW}@127.0.0.1:27017/simple-cms?authSource=admin" \
  ADMIN_EMAIL="$ADMIN_EMAIL" ADMIN_PASSWORD="$ADMIN_PASSWORD" npm run seed
```

`npm run seed` **wipes** all collections. To reset content later, sign in and use **Admin → Seed data**.
Sign in at `$(terraform output -raw admin_url)` with `admin_email` / `admin_password`.
