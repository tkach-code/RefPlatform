'use strict';

const express = require('express');

// The ALB forwards /hello-app/* unchanged, so everything is served under this
// prefix. Keep in sync with terraform/apps/hello-app (locals.path).
const BASE_PATH = '/hello-app';

const app = express();
app.disable('x-powered-by');

const site = express.Router();

// Platform health check (k8s probes, ALB health check, CI smoke test).
site.get('/api/health', (req, res) => {
  res.json({ status: 'ok' });
});

site.get('/', (req, res) => {
  res.type('html').send(
    `<h1>Hello from RefPlatform</h1><p>Served at ${BASE_PATH}, pod ${process.env.HOSTNAME || 'local'}</p>`
  );
});

app.use(BASE_PATH, site);

// Local dev convenience. On the platform, "/" belongs to index-app.
app.get('/', (req, res) => {
  res.redirect(302, `${BASE_PATH}/`);
});

const port = Number(process.env.PORT) || 3000;
const host = process.env.HOST || '0.0.0.0';

app.listen(port, host, () => {
  console.log(`Serving at http://${host}:${port}${BASE_PATH}/`);
});
