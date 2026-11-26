# App registry: every app hosted on the platform. Each entry gets an ECR
# repository refplatform/<app>. Routing (path, ALB group.order) is defined in
# terraform/apps/<app>. Keep the route table in doc/multi-app-platform-plan.md
# in sync.
#
# Add an app here (and apply this stack) before its first build, because CI
# pushes to the repository created here.
#
# Removing an app deletes its repository and images (force_delete).

locals {
  apps = [
    "simple-cms",
    "index-app",
    "empty-login",
  ]
}
