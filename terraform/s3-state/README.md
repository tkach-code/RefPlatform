# Bootstrap: state bucket and GitHub OIDC roles

Applied once, by hand, with **local state** (the bucket can't hold state until it exists).

Creates:
- S3 bucket `refplatform-tfstate-<account-id>` (versioned, encrypted, private). It holds:
  - `platform/eks.tfstate` from `terraform/eks`
  - `apps/<app>.tfstate` from `terraform/apps/<app>`
- When `github_repository` is set: the GitHub OIDC provider and three roles. Workflows build each ARN from the repository variable `AWS_ACCOUNT_ID`.

| Role | Who can assume it | Permissions |
|---|---|---|
| `refplatform-gh-build` | any branch of the repo | push to ECR `refplatform/*` |
| `refplatform-gh-deploy` | `main` only | state `apps/*`, Secrets Manager `refplatform/apps/*`, IAM roles `refplatform-*-irsa`, SSM `/refplatform/*` read, ECR describe, EKS describe (+ cluster admin access entry from `terraform/eks`) |
| `refplatform-gh-infra` | GitHub Environments `infra` and `infra-plan` | `AdministratorAccess` (the platform stack creates VPC, EKS, IAM, CloudFront) |

## Apply

```bash
cd terraform/s3-state
cp terraform.tfvars.example terraform.tfvars   # set github_repository = "owner/repo"
terraform init
terraform apply
terraform output                               # account_id -> GitHub variable AWS_ACCOUNT_ID
```

If the account already has the `token.actions.githubusercontent.com` provider, set `create_github_oidc_provider = false`.

Then in GitHub:
- **Settings → Secrets and variables → Actions → Variables:** `AWS_ACCOUNT_ID`, and optionally `AWS_REGION`.
- **Settings → Environments:**
  - `infra`: add yourself as a required reviewer. It is used for apply, and for plans on pull requests (PR code runs with admin rights, so it needs approval).
  - `infra-plan`: limit deployment branches to `main`. It is used for the automatic plan on `main`.

## Destroy

Last, after `terraform/apps/*` and `terraform/eks`. The bucket is versioned and `force_destroy = false`, so empty every object version first (commands in [doc/readme.md](../../doc/readme.md#destroy-everything)), then `terraform destroy`.
