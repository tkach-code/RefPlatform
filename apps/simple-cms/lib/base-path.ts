// The app is served under a path prefix on the shared RefPlatform host
// (e.g. https://<cloudfront>/simple-cms). next.config.ts sets basePath and
// inlines NEXT_PUBLIC_BASE_PATH at build time.
//
// Next.js adds the prefix itself for <Link>, redirect(), router.push() and
// _next assets. It does NOT add it for fetch(), string <Image src>, CSS url()
// values or next-auth client callback URLs, so those go through withBasePath().
export const BASE_PATH = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

export function withBasePath(path: string): string {
  if (!BASE_PATH || !path.startsWith("/") || path.startsWith("//")) {
    return path;
  }
  if (path === BASE_PATH || path.startsWith(`${BASE_PATH}/`)) {
    return path;
  }
  return `${BASE_PATH}${path}`;
}
