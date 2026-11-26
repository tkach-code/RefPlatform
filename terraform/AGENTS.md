# terraform: agent guidance

Platform-wide rules are in the root [`AGENTS.md`](../AGENTS.md). Design and naming are in `doc/architecture.md`.

## Layers (apply in this order)

1. **`s3-state`**: the bootstrap. It uses **local state** and creates:
   - the bucket `refplatform-tfstate-<account>`
   - the GitHub OIDC provider and the roles `refplatform-gh-{build,deploy,infra}`, but only when `github_repository` is set
2. **`eks`**: the platform, state key `platform/eks.tfstate`. It creates:
   - the VPC and the EKS cluster `refplatform-eks`
   - the LB controller and the shared Ingress `refplatform-ingress/public`: ALB `refplatform-alb`, group `refplatform`, catch-all 404 at order 1000
   - CloudFront `refplatform-cdn`
   - ECR `refplatform/<app>` for each entry in `apps.tf`
   - Secrets Store CSI + ASCP, and the StorageClass `refplatform-gp3`
   - SSM parameters `/refplatform/platform/*`
   - EKS admin access entries
3. **`apps/<app>`**: one thin root per app, state key `apps/<app>.tfstate`. Each uses `modules/web-app`, which creates:
   - the namespace and its quota
   - the IRSA role `refplatform-<app>-irsa`, with an inline policy for its own secret `refplatform/apps/<app>`
   - the SecretProviderClass, Deployment and Service
   - an Ingress in the shared group

   App-specific resources sit next to it; simple-cms adds `modules/mongodb`. Platform values come from SSM, not from remote state.

## Commands

```bash
cd terraform/<eks|apps/<app>>
terraform init -backend-config="bucket=refplatform-tfstate-<account-id>"   # key/region/lockfile are in versions.tf
terraform plan
terraform apply                       # apps: -var image=<acct>.dkr.ecr.eu-central-1.amazonaws.com/refplatform/<app>:<tag>
```

- Terraform >= 1.10 (S3 `use_lockfile`).
- Validate offline: `terraform fmt -check && terraform init -backend=false && terraform validate`. This works for every root and is the check to run after editing.
- Don't run `apply` or `destroy` against the real account unless the user asks. CI applies `eks` (with approval) and the app roots.

## Rules

- `eks/terraform.tfvars` is committed and holds `cluster_admin_principal_arns` (human admins). The CI roles are added by `github_ci_roles_enabled`. A `false` committed there removes CI's cluster access on the next `infra-eks` apply.
- App Ingresses must never set `load-balancer-name` or other exclusive ALB annotations. Only `eks/modules/ingress` does.
- Every app root sets a unique `group.order` < 900 (`index-app` = 900) and `health_path` = its full prefixed health URL. Keep `doc/architecture.md` §1 and `apps/README.md` in sync.
- A new app root is copied from `apps/empty-login`. Change `locals` **and** the backend `key` in `versions.tf`.
- Changes under `modules/**` aren't deployed automatically. Run the `apps-redeploy-all` workflow afterwards.
- The deploy role (`refplatform-gh-deploy`) can only manage app state, `refplatform/apps/*` secrets, `refplatform-*-irsa` roles and in-cluster resources. General AWS resources for an app belong in `s3-state/github.tf` (widen the policy) or in `eks`.

## Destroy order

1. Every `apps/*` root (`-var image=unused`).
2. `eks`. The Ingress cleanup helper `eks/modules/ingress/cleanup.cmd` → `cleanup.py` needs `python3`.
3. `s3-state`. Empty the versioned bucket first.

Full commands: `doc/readme.md` → "Destroy everything".

After the first deploy of simple-cms, seed its database via a port-forward (`apps/README.md`).
