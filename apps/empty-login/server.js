'use strict';

const path = require('node:path');
const express = require('express');
const routes = require('./routes');

// The ALB forwards /empty-login/* unchanged, so everything is served under this
// prefix. Keep in sync with terraform/apps/empty-login (locals.path) and the
// asset/form URLs in public/*.html.
const BASE_PATH = '/empty-login';

const app = express();
const publicDir = path.join(__dirname, 'public');

app.disable('x-powered-by');
app.use(express.json());
app.use(express.urlencoded({ extended: false }));

const site = express.Router();

// Platform health check (k8s probes, ALB health check, CI smoke test).
site.get('/api/health', (req, res) => {
  res.json({ status: 'ok' });
});
site.use(routes);
site.use(express.static(publicDir, {
  extensions: ['html'],
  index: 'index.html',
}));

app.use(BASE_PATH, site);

// Local dev convenience. On the platform, "/" belongs to index-app.
app.get('/', (req, res) => {
  res.redirect(302, `${BASE_PATH}/`);
});

app.use((req, res) => {
  res.status(404).type('text/plain').send('Not Found');
});

const port = Number(process.env.PORT) || 3000;
const host = process.env.HOST || '0.0.0.0';

app.listen(port, host, () => {
  console.log(`Serving at http://${host}:${port}${BASE_PATH}/`);
});
