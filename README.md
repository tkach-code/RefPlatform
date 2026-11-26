# RefPlatform

A reference platform for hosting many small, independent web apps on a single Amazon EKS cluster, behind one CloudFront URL. Each app lives on its own path, deploys on its own, and is fully isolated from the others. All infrastructure is code and every change ships through GitHub Actions.

## How it works

```
https://<id>.cloudfront.net          CloudFront (HTTPS, single entry point)
  └─ Application Load Balancer       one ALB shared by all apps, routing by path prefix
       ├─ /simple-cms/*   →  simple-cms    Next.js CMS + MongoDB
       ├─ /empty-login/*  →  empty-login   Express login demo
       ├─ /<app>/*        →  <app>         any new app
       └─ /*              →  index-app     landing page
```

- **Path-based routing:** apps share one domain and one load balancer. Each app serves under its own prefix.
- **Isolation per app:** its own Kubernetes namespace and quota, IAM role, secret, container registry, Terraform state and CI/CD workflow.
- **Simple app contract:** a Dockerfile on port 3000, a base path, and a `/<app>/api/health` endpoint. Any framework works.
- **Secure by default:** GitHub Actions authenticates to AWS with OIDC (no stored keys), each app can read only its own secrets, and platform changes need manual approval.
- **Independent delivery:** a push touching one app builds, tests and deploys only that app. Rollback is one manual workflow run.

## Tech stack

| Layer | Technologies |
|---|---|
| Cloud | AWS: EKS, VPC, ALB, CloudFront, ECR, Secrets Manager, SSM Parameter Store, S3, IAM |
| Infrastructure as code | Terraform (S3 backend with native locking), Helm |
| Kubernetes | AWS Load Balancer Controller, Secrets Store CSI Driver, EBS CSI, IRSA |
| CI/CD | GitHub Actions with OIDC, reusable build and deploy workflows |
| Apps | Next.js, React, TypeScript, Tailwind CSS, MongoDB, Auth.js, Express, nginx |

## Apps

| App | Path | Description |
|---|---|---|
| [simple-cms](apps/simple-cms) | `/simple-cms` | Marketing site with an authenticated admin area for content management |
| [empty-login](apps/empty-login) | `/empty-login` | Minimal Express login page, the simplest template for new apps |
| [index-app](apps/index-app) | `/` | Landing page linking to every app |

## Repository layout

| Path | Contents |
|---|---|
| [`apps/`](apps) | Application source, one folder per app |
| [`terraform/s3-state/`](terraform/s3-state) | Bootstrap: Terraform state bucket and GitHub OIDC roles |
| [`terraform/eks/`](terraform/eks) | Shared platform: network, cluster, load balancer, CDN, registries |
| [`terraform/modules/`](terraform/modules) | Reusable modules: `web-app` (everything one app needs), `mongodb` |
| [`terraform/apps/`](terraform/apps) | One small Terraform root per app |
| [`.github/workflows/`](.github/workflows) | Per-app pipelines and the platform pipeline |
| [`doc/`](doc) | Architecture and operations guides |

## Documentation

| Guide | |
|---|---|
| [Architecture](doc/architecture.md) | Design, naming, route registry, app contract, CI/CD |
| [First deployment](doc/first-deployment.md) | Step-by-step from an empty AWS account to running apps |
| [Runbook](doc/readme.md) | Day-to-day commands, working from another machine, teardown |
| [CI/CD setup](doc/github-readme.md) | GitHub Actions configuration and troubleshooting |
| [Adding an app](apps/new-app/README.md) | Full guide to putting a new app on the platform |

## License

[MIT](LICENSE)
