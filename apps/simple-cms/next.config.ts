import type { NextConfig } from "next";

// Path prefix on the shared RefPlatform host. Must match the Ingress path in
// terraform/apps/simple-cms. Changing it requires a rebuild.
const basePath = "/simple-cms";

const nextConfig: NextConfig = {
  output: "standalone",
  basePath,
  env: {
    NEXT_PUBLIC_BASE_PATH: basePath,
  },
};

export default nextConfig;
