"use client";

import { SessionProvider } from "next-auth/react";
import type { Session } from "next-auth";
import { withBasePath } from "@/lib/base-path";

export default function Providers({
  children,
  session,
}: {
  children: React.ReactNode;
  session: Session | null;
}) {
  // Client-side signIn/signOut/useSession call the Auth.js API under the app's base path.
  return (
    <SessionProvider session={session} basePath={withBasePath("/api/auth")}>
      {children}
    </SessionProvider>
  );
}
