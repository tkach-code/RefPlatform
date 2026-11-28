# Deploy Hello App on RefPlatform

## 1. Register the app and provision ECR

1. Open a PR from `main` with only these four files from the demo branch. Add `hello-app` to the [platform registry](../terraform/eks/apps.tf) and reserve Ingress order `120` in the [architecture registry](architecture.md#route--order-registry-keep-current-orders-must-be-unique), [Terraform app registry](../terraform/apps/README.md), and [new-app guide](../apps/new-app/README.md).
2. Approve the `infra-eks` PR plan and check that it adds the ECR repository and lifecycle policy for `refplatform/hello-app`. Merge the PR, then approve the apply in the `infra` environment.
3. Wait for the apply to finish, then verify the repository exists before pushing the app workflow.

   ```bash
   aws ecr describe-repositories --region eu-central-1 \
     --repository-names refplatform/hello-app \
     --query 'repositories[0].repositoryUri' --output text
   ```

   If the demo branch build failed because ECR was missing, rerun it after this check passes.

## 2. Build and test locally

1. On a branch based on the updated `main`, use the [prepared `apps/hello-app` files](../apps/hello-app). If starting from an empty folder, run these commands from the repository root and commit `package.json` and `package-lock.json`.

   ```bash
   mkdir -p apps/hello-app
   cd apps/hello-app
   npm init -y
   npm install express@5.3.0
   ```

2. Use the demo's [`server.js`](../apps/hello-app/server.js), [`Dockerfile`](../apps/hello-app/Dockerfile), [`.dockerignore`](../apps/hello-app/.dockerignore), and [`.gitignore`](../apps/hello-app/.gitignore).
3. Run the checks from `apps/hello-app`. Expect a health response of `{"status":"ok"}` and the greeting page.

   ```bash
   docker build -t hello-app-local .
   docker run --rm -d -p 127.0.0.1:3000:3000 --name hello-app-local hello-app-local
   curl -fsS --retry 10 --retry-connrefused http://127.0.0.1:3000/hello-app/api/health
   curl -fsS http://127.0.0.1:3000/hello-app/
   docker rm -f hello-app-local
   ```

## 3. Deploy and verify

1. Use the [Hello App Terraform root](../terraform/apps/hello-app) and [workflow](../.github/workflows/app-hello-app.yml). The stack uses `/hello-app`, Ingress order `120`, the health path `/hello-app/api/health`, and the state key `apps/hello-app.tfstate`. Leave `secrets` empty.
2. Open a second PR with the app files, Terraform root, and workflow. Check that the branch build passes, then merge to `main`.
3. Wait for `app-hello-app` to succeed on `main`, then check the rollout, health endpoint, and greeting page.

   ```bash
   kubectl -n hello-app rollout status deployment/hello-app --timeout=120s
   kubectl -n hello-app get deploy,pods,ingress
   curl -fsS --retry 12 --retry-delay 5 --retry-all-errors \
     https://d1vqcl59m25vz.cloudfront.net/hello-app/api/health
   curl -fsS https://d1vqcl59m25vz.cloudfront.net/hello-app/
   ```

## 4. Publish the landing-page link

1. After both public checks pass, add the link in [`apps/index-app/public/index.html`](../apps/index-app/public/index.html) and merge the landing-page PR to `main`.

   ```html
   <li><a href="/hello-app/">Hello App</a>: greeting page for the app-onboarding demo</li>
   ```

2. Wait for `app-index-app` to deploy, then click **Hello App** on the [landing page](https://d1vqcl59m25vz.cloudfront.net).
