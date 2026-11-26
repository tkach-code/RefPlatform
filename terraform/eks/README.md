# Platform stack (Terraform)

Shared infrastructure for every RefPlatform app:
- **VPC** `refplatform-vpc` (2 AZs, public and private subnets, one NAT).
- **EKS** `refplatform-eks` with AL2023 managed nodes `refplatform-eks-nodes`.
- **AWS Load Balancer Controller** and the shared Ingress `refplatform-ingress/public`. It creates the ALB `refplatform-alb` (Ingress group `refplatform`) with a catch-all 404 at `group.order` 1000.
- **CloudFront** `refplatform-cdn`: the single public HTTPS entry point, with the ALB as origin. `*/_next/static/*` is cached; everything else passes through.
- **ECR** repository `refplatform/<app>` for each app in [`apps.tf`](apps.tf). Immutable `sha-` tags, last 15 kept.
- **Secrets Store CSI Driver + ASCP.** Each app stack creates its own secret `refplatform/apps/<app>` and a role that can read only that secret.
- **StorageClass** `refplatform-gp3` for app databases.
- **SSM parameters** under `/refplatform/platform/*`. App stacks read these instead of this stack's state.
- **EKS access entries** (cluster admin): `cluster_admin_principal_arns`, the `refplatform-gh-infra`/`-deploy` roles, and whoever runs the apply.

State: `s3://refplatform-tfstate-<account>/platform/eks.tfstate` (bucket from `terraform/s3-state`).

## Prerequisites

Terraform `>= 1.10`, AWS CLI v2, kubectl. `python3` is needed only for `terraform destroy` (Ingress cleanup helper).
`terraform/s3-state` must already be applied. If you applied it without `github_repository`, set `github_ci_roles_enabled = false`.

## Apply

**CI** (`.github/workflows/infra-eks.yml`): a pull request runs a plan. A push to `main` runs a plan, then an apply after you approve the `infra` environment.

**Locally:**
```bash
cd terraform/eks
# terraform.tfvars: put your own IAM user/role ARN in cluster_admin_principal_arns
terraform init -backend-config="bucket=refplatform-tfstate-<account-id>"
terraform plan
terraform apply        # first run ~15-20 min; CloudFront adds a few minutes
```

Then:
```bash
terraform output public_base_url              # https://<id>.cloudfront.net -> apps at /<app>/
$(terraform output -raw update_kubeconfig_command)
kubectl get nodes
```

### Ordering notes
- `vpc-cni` installs before the node group. `kube-proxy`, `coredns` and `aws-ebs-csi-driver` install after it.
- The LB controller, shared Ingress, CSI driver/ASCP and StorageClass install after the cluster and access entries exist.
- CloudFront needs the ALB hostname, so it's created after the shared Ingress is ready.

## Add or remove an app

Edit the list in [`apps.tf`](apps.tf) and apply. Adding creates `refplatform/<app>` in ECR, so do it before the app's first build. Removing deletes the repository and its images (`force_delete`). Routing lives in `terraform/apps/<app>`, not here.

## How apps attach

App stacks use [`terraform/modules/web-app`](../modules/web-app). It reads `/refplatform/platform/{public_base_url,ingress_group_name,ingress_class_name,oidc_provider_arn,storage_class_name}` and creates an Ingress like this:

```yaml
annotations:
  alb.ingress.kubernetes.io/group.name: refplatform
  alb.ingress.kubernetes.io/group.order: "100"          # unique, < 1000. "/" app highest
  alb.ingress.kubernetes.io/healthcheck-path: /<app>/api/health
  alb.ingress.kubernetes.io/scheme: internet-facing
  alb.ingress.kubernetes.io/target-type: ip
spec.rules[0].http.paths[0]: { path: /<app>, pathType: Prefix }
```

Never set `load-balancer-name` (or other "exclusive" ALB annotations) on app Ingresses. The shared Ingress owns them, and a conflict stops the controller for the whole group.

## Destroy

Destroy every `terraform/apps/*` stack first, because their Ingresses hold the shared ALB. Then:

```bash
terraform destroy
```

Destroying the shared Ingress runs `modules/ingress/cleanup.cmd` (Windows/POSIX polyglot → `cleanup.py`, needs `python3`). It deletes the ALB, its security groups and the controller finalizer. If it still reports "Ingress still exists", run destroy again.

## Layout

```text
terraform/eks/
├── apps.tf              # app registry (ECR repos)
├── main.tf              # wiring, StorageClass, SSM parameters
├── variables.tf / terraform.tfvars
├── outputs.tf / providers.tf / versions.tf (S3 backend)
└── modules/
    ├── vpc/             # VPC, subnets, NAT, IGW
    ├── eks/             # EKS, nodes, add-ons, OIDC, access entries
    ├── ingress/         # LB controller, shared Ingress + 404, destroy cleanup
    ├── secrets_store/   # Secrets Store CSI driver + ASCP
    ├── cloudfront/      # refplatform-cdn
    └── ecr/             # one repository per app
```
