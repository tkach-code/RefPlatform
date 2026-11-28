
# RefPlatform 

I Built My Own App Platform on AWS EKS — New App Live in 15 Minutes.
From Empty Folder to Live URL.

## Intro

I recently joined a frontend education course, and as any good frontend engineer, I brought my own production platform with me.

Every time I have an idea for a small app, it takes a day to build and a then another one to host. New domain, new load balancer, new certificate, new pipeline, new secrets. 

So I built the boring part once: AWS, Kubernetes, Terraform, GitHub Actions. Then adding an app is just a checklist. Stack is Kubernetes and AWS. Very practical. Very educational. Very normal.

This is RefPlatform. It's one EKS cluster in AWS. In front of it there's one Application Load Balancer and one CloudFront distribution. Every app gets its own path: slash simple-cms, slash empty-login, slash whatever I build next.

Everything is Terraform, and everything is deployed by GitHub Actions.

And every app is isolated. Its own Kubernetes namespace with a resource quota, its own IAM role, its own secret in Secrets Manager, its own container registry, its own Terraform state, and its own workflow. If I break one app, the others don't notice.

```mermaid
flowchart TB
    B[Browser] --> CF["CloudFront · refplatform-cdn<br/>forwards every path"]
    CF --> ALB["ALB · refplatform-alb<br/>one rule per app Ingress"]
    GH["Delivery · GitHub Actions<br/>push: lint, build, smoke test<br/>image to ECR, one repo per app"]
    subgraph EKS["EKS cluster refplatform-eks · one namespace per app"]
        CMS["simple-cms<br/>/simple-cms<br/>Next.js + MongoDB"]
        LOGIN["empty-login<br/>/empty-login<br/>Express"]
        HELLO["hello-app<br/>/hello-app<br/>new in this demo"]
        IDX["index-app<br/>/ (landing page)<br/>static nginx"]
    end
    ALB -- "path prefix" --> CMS & LOGIN & HELLO & IDX
    GH -. "deploys each app" .-> EKS
    style HELLO stroke-width:3px
```

Every request takes the same path down. The ALB picks the app by path prefix and order, and GitHub Actions deploys each app into its own namespace.



## Live platform

https://d1vqcl59m25vz.cloudfront.net

This is the landing page. It's just static HTML on nginx, and it owns slash. It's also the only place that knows the other apps exist: a list of links."


Demo app already on the platform:
https://d1vqcl59m25vz.cloudfront.net/simple-cms

Terminal:
```bash
kubectl get ns -l app.kubernetes.io/part-of=refplatform
kubectl -n simple-cms get deploy,pods,ingress
```

Under the hood, each app is a namespace. Simple CMS has its app pod and its MongoDB pod.

It's one repo, and it has three parts. apps, terraform, .github

## Demo new app

The demo app is `hello-app`, an Express server at `/hello-app`.

The folder name is the identity, so step zero is picking one. I'll call it hello-app. That gives me the path slash hello-app, a namespace, an image repo and an IAM role, all called hello-app.

Create `server.js`:

```js
const express = require('express');

const BASE_PATH = '/hello-app';
const app = express();
const site = express.Router();

site.get('/api/health', (req, res) => res.json({ status: 'ok' }));
site.get('/', (req, res) => {
  res.send(`<h1>Hello from RefPlatform</h1><p>Served at ${BASE_PATH}, pod ${process.env.HOSTNAME}</p>`);
});

app.use(BASE_PATH, site);
app.listen(3000, '0.0.0.0', () => console.log(`Listening on :3000${BASE_PATH}`));
```


Create `Dockerfile` and `.dockerignore` (`node_modules`, `.git`, `.env*`):

```dockerfile
FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY server.js ./
USER node
EXPOSE 3000
CMD ["node", "server.js"]
```

Terminal:
```bash
docker build -t hello-app-local .
docker run --rm -d -p 3000:3000 --name hello-app-local hello-app-local
curl -i http://localhost:3000/hello-app/api/health
docker rm -f hello-app-local
```

Add a link to the landing page in `apps/index-app/public/index.html`:

```html
<li><a href="/hello-app/">Hello App</a>: demo app shipped live in the intro video</li>
```

Push to main

```bash
kubectl -n hello-app get deploy,pods,ingress
curl -s https://https://d1vqcl59m25vz.cloudfront.net/hello-app/api/health
```

The pod is up. The Ingress joined the load balancer group. 

That's RefPlatform: one cluster, one URL, as many apps as I want, each shipping on its own. 
