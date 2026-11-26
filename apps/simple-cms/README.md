# simple-cms

RefPlatform demo app: a Next.js (App Router) + TypeScript + Tailwind CSS marketing site backed by MongoDB, with an authenticated admin area for content CRUD.

On the platform it's served at **`https://<cloudfront>/simple-cms/`** (Next.js `basePath: "/simple-cms"`). Infrastructure: [terraform/apps/simple-cms](../../terraform/apps/simple-cms). CI: [app-simple-cms.yml](../../.github/workflows/app-simple-cms.yml).

## Local setup

1. Install dependencies:
   ```bash
   npm install
   ```
2. Copy the env template (the file name contains a space):
   ```bash
   cp ".env example" .env.local
   ```
   - `MONGODB_URI`: MongoDB connection string. The database name comes from the URI path.
   - `AUTH_SECRET`: session secret. Generate your own: `openssl rand -hex 32` (or `npx auth secret`).
   - `AUTH_URL`: origin only (`http://localhost:3000`), **no path**. Auth.js keeps its default `/api/auth` base path.
   - `ADMIN_EMAIL` / `ADMIN_PASSWORD`: the admin user created by the seed.
3. Start MongoDB on the URI from `.env.local`:
   ```bash
   docker run -d --name simple-cms-mongo -p 27017:27017 mongo:latest
   # or, without Docker:
   npm run mongo:memory
   ```
4. Seed content and the admin user (**wipes** all collections):
   ```bash
   npm run seed
   ```
5. Run:
   ```bash
   npm run dev
   ```
   - Site: <http://localhost:3000/simple-cms>
   - Admin: <http://localhost:3000/simple-cms/admin/login>

## Base path rules

Next.js adds `/simple-cms` to `<Link>`, `redirect()`, `router.push()`, `_next` assets and fonts automatically. It does **not** add it for these, so wrap them with `withBasePath()` from `lib/base-path.ts`:
- `fetch("/api/...")` calls
- string `<Image src="/images/...">` values (image paths are stored in MongoDB without the prefix)
- CSS `url()` values
- next-auth client callback URLs

Auth.js cookies are named `simple-cms.*` and scoped to `Path=/simple-cms`, so other apps on the same host can't overwrite them.

## Routes (relative to `/simple-cms`)

| Path | Description |
|---|---|
| `/` | Home |
| `/our-story` | Our Story |
| `/products` | Products |
| `/media` | Media |
| `/admin` | Admin dashboard (login at `/admin/login`) |
| `/api/health` | Health check, no auth (probes, ALB, CI smoke test) |
| `/api/*` | CRUD handlers (admin session required). `POST /api/registrations` is public |
