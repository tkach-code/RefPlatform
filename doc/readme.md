# Manual runbook

Short reference. For a first deployment with explanations, see [first-deployment.md](first-deployment.md).

Region `eu-central-1`. Commands are bash (Git Bash on Windows). `<acct>` = 12-digit AWS account ID.

## Create everything from zero

```bash
aws configure                                   # credentials of your admin IAM user/role
aws sts get-caller-identity                     # note the Arn for cluster_admin_principal_arns
```

### 1. Bootstrap (state bucket + GitHub OIDC roles)
```bash
cd terraform/s3-state
cp terraform.tfvars.example terraform.tfvars    # github_repository = "owner/repo"
terraform init
terraform apply -auto-approve
terraform output                                # bucket_name = refplatform-tfstate-<acct>
```
GitHub: variable `AWS_ACCOUNT_ID`, Environments `infra` (reviewer) and `infra-plan` (main only). See [github-readme.md](github-readme.md).

### 2. Platform (EKS, ALB, CloudFront, ECR)
Put your IAM ARN in `terraform/eks/terraform.tfvars` → `cluster_admin_principal_arns`. Then either merge to `main` and approve **infra-eks**, or:
```bash
cd terraform/eks
terraform init -backend-config="bucket=refplatform-tfstate-<acct>"
terraform apply -auto-approve                   # ~20 min
terraform output public_base_url                # https://<id>.cloudfront.net
aws eks update-kubeconfig --region eu-central-1 --name refplatform-eks
kubectl get nodes
```

### 3. Apps
Push to `main` (or run **app-simple-cms** manually). Manual alternative:
```bash
aws ecr get-login-password --region eu-central-1 | docker login --username AWS --password-stdin <acct>.dkr.ecr.eu-central-1.amazonaws.com
docker build -t <acct>.dkr.ecr.eu-central-1.amazonaws.com/refplatform/simple-cms:sha-manual01 apps/simple-cms
docker push <acct>.dkr.ecr.eu-central-1.amazonaws.com/refplatform/simple-cms:sha-manual01

cd terraform/apps/simple-cms
terraform init -backend-config="bucket=refplatform-tfstate-<acct>"
terraform apply -var="image=<acct>.dkr.ecr.eu-central-1.amazonaws.com/refplatform/simple-cms:sha-manual01"
terraform output url                            # https://<id>.cloudfront.net/simple-cms/
```
Tags are immutable: every manual push needs a new tag.

### 4. simple-cms admin user (once per fresh database)
See [terraform/apps/README.md → simple-cms admin user](../terraform/apps/README.md#simple-cms-admin-user). Credentials:
```bash
cd terraform/apps/simple-cms
terraform output -raw admin_email
terraform output -raw admin_password
```

## Useful checks
```bash
kubectl get ingress -A                          # all apps in group refplatform
kubectl -n simple-cms get pods
kubectl -n simple-cms logs deploy/simple-cms
aws elbv2 describe-load-balancers --names refplatform-alb --query 'LoadBalancers[0].DNSName'
aws ssm get-parameters-by-path --path /refplatform/platform --query 'Parameters[].[Name,Value]' --output table
terraform plan                                  # in any stack: drift after manual changes in AWS
```

## Destroy everything

Order: **apps → eks → s3-state**. The state lives in the bucket, so the bucket goes last.

1. Disable the workflows (GitHub → Actions → each `app-*` and `infra-eks` → Disable), or a push will recreate things.
2. Every app:
   ```bash
   for app in simple-cms index-app empty-login; do
     (cd terraform/apps/$app && terraform init -backend-config="bucket=refplatform-tfstate-<acct>" && terraform destroy -auto-approve -var image=unused)
   done
   kubectl get ns; kubectl get pv                # no app namespaces or volumes left
   ```
   An app that was never deployed has empty state, so its destroy is a no-op.
3. Platform (~15 min; ECR repositories are force-deleted with their images):
   ```bash
   cd terraform/eks
   terraform destroy -auto-approve               # needs python3 for the Ingress cleanup; rerun if "Ingress still exists"
   kubectl config delete-context arn:aws:eks:eu-central-1:<acct>:cluster/refplatform-eks
   kubectl config delete-cluster arn:aws:eks:eu-central-1:<acct>:cluster/refplatform-eks
   ```
4. Bootstrap. Empty the versioned bucket first:
   ```bash
   BUCKET=refplatform-tfstate-<acct>
   aws s3api delete-objects --bucket "$BUCKET" --delete "$(aws s3api list-object-versions --bucket "$BUCKET" --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json)"
   aws s3api delete-objects --bucket "$BUCKET" --delete "$(aws s3api list-object-versions --bucket "$BUCKET" --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json)"   # fails if none: fine
   cd terraform/s3-state && terraform destroy -auto-approve
   ```
5. Verify (all empty):
   ```bash
   aws eks list-clusters
   aws ecr describe-repositories --query 'repositories[].repositoryName'
   aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName'
   aws ec2 describe-nat-gateways --filter Name=state,Values=available --query 'NatGateways[].NatGatewayId'
   aws ec2 describe-addresses --query 'Addresses[].PublicIp'
   aws ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[].VolumeId'
   aws secretsmanager list-secrets --query 'SecretList[].Name'
   aws cloudfront list-distributions --query 'DistributionList.Items[].Comment'
   aws ssm get-parameters-by-path --path /refplatform --recursive --query 'Parameters[].Name'
   aws s3 ls | grep refplatform-tfstate
   ```
   NAT gateway, Elastic IP, ALB and EKS bill by the hour.
6. Local cleanup (optional): `terraform/s3-state/terraform.tfstate*`, every `.terraform/` folder.
