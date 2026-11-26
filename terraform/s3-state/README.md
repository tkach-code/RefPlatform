# Bootstrap: state bucket and GitHub OIDC roles

Applied by hand, never from CI. Its own state lives in the bucket it creates, under `bootstrap/s3-state.tfstate` ([`backend.tf`](backend.tf)), so any machine with admin credentials can run it.

Creates:
- S3 bucket `refplatform-tfstate-<account-id>` (versioned, encrypted, private). It holds:
  - `bootstrap/s3-state.tfstate` from this stack
  - `platform/eks.tfstate` from `terraform/eks`
  - `apps/<app>.tfstate` from `terraform/apps/<app>`
- When `github_repository` is set: the GitHub OIDC provider and three roles. Workflows build each ARN from the repository variable `AWS_ACCOUNT_ID`.

| Role | Who can assume it | Permissions |
|---|---|---|
| `refplatform-gh-build` | any branch of the repo | push to ECR `refplatform/*` |
| `refplatform-gh-deploy` | `main` only | state `apps/*`, Secrets Manager `refplatform/apps/*`, IAM roles `refplatform-*-irsa`, SSM `/refplatform/*` read, ECR describe, EKS describe (+ cluster admin access entry from `terraform/eks`) |
| `refplatform-gh-infra` | GitHub Environments `infra` and `infra-plan` | `AdministratorAccess` (the platform stack creates VPC, EKS, IAM, CloudFront) |

Settings are in the committed `terraform.tfvars`. If the account already has the `token.actions.githubusercontent.com` provider, set `create_github_oidc_provider = false`.

## Change it (existing account)

```bash
cd terraform/s3-state
terraform init -backend-config="bucket=refplatform-tfstate-<account-id>"
terraform plan
terraform apply
terraform output                               # account_id -> GitHub variable AWS_ACCOUNT_ID
```

## First apply in a new account

The bucket doesn't exist yet, so the first apply runs on local state, which is then moved into the new bucket:

```bash
cd terraform/s3-state
mv backend.tf backend.tf.off                   # local state for now
terraform init
terraform apply
mv backend.tf.off backend.tf
terraform init -migrate-state -backend-config="bucket=refplatform-tfstate-<account-id>"   # answer "yes"
rm -f terraform.tfstate terraform.tfstate.backup                                           # now in S3
terraform plan                                 # "No changes"
```

Then in GitHub:
- **Settings → Secrets and variables → Actions → Variables:** `AWS_ACCOUNT_ID`, and optionally `AWS_REGION`.
- **Settings → Environments:**
  - `infra`: add yourself as a required reviewer. It is used for apply, and for plans on pull requests (PR code runs with admin rights, so it needs approval).
  - `infra-plan`: limit deployment branches to `main`. It is used for the automatic plan on `main`.

## Destroy

Last, after `terraform/apps/*` and `terraform/eks`. The bucket can't hold the state of its own deletion, so first move the state back to local, then empty the bucket (versioned, `force_destroy = false`), then destroy:

```bash
cd terraform/s3-state
mv backend.tf backend.tf.off
terraform init -migrate-state                  # copies the state from S3 to ./terraform.tfstate, answer "yes"
# empty every object version (commands in doc/readme.md → Destroy everything)
terraform destroy
```
