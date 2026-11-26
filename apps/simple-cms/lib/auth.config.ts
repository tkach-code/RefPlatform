import type { NextAuthConfig } from "next-auth";
import { BASE_PATH } from "@/lib/base-path";

// Several apps share one hostname, so Auth.js cookies get an app-specific
// name and are scoped to this app's path. Otherwise another app using
// Auth.js would overwrite this app's session.
const COOKIE_PREFIX = "simple-cms";
const useSecureCookies = (
  process.env.AUTH_URL ??
  process.env.NEXTAUTH_URL ??
  ""
).startsWith("https://");

function cookie(name: string) {
  return {
    name: `${COOKIE_PREFIX}.${name}`,
    options: {
      httpOnly: true,
      sameSite: "lax" as const,
      path: BASE_PATH || "/",
      secure: useSecureCookies,
    },
  };
}

export const authConfig = {
  // Server side, Next.js strips its basePath before the route handler runs,
  // so Auth.js keeps its default basePath "/api/auth". The browser client
  // uses the prefixed path instead (SessionProvider basePath in
  // components/admin/Providers.tsx). Keep AUTH_URL origin-only: a path there
  // would override this basePath.
  pages: {
    // Next.js adds the basePath to this when redirecting.
    signIn: "/admin/login",
  },
  session: {
    strategy: "jwt",
  },
  cookies: {
    sessionToken: cookie("session-token"),
    callbackUrl: cookie("callback-url"),
    csrfToken: cookie("csrf-token"),
  },
  providers: [],
  callbacks: {
    authorized({ auth, request }) {
      // nextUrl.pathname excludes the Next.js basePath.
      const isAdminRoute = request.nextUrl.pathname.startsWith("/admin");
      const isLogin = request.nextUrl.pathname.startsWith("/admin/login");
      if (isAdminRoute && !isLogin) {
        return !!auth?.user;
      }
      return true;
    },
  },
  trustHost: true,
} satisfies NextAuthConfig;
