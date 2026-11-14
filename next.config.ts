import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Our set art and card photos: kept by browsers, the app and Vercel's CDN for a day, then
  // re-checked in the background (a week's grace), so pages don't ask for each one every visit.
  async headers() {
    const cache = [{ key: "Cache-Control", value: "public, max-age=86400, stale-while-revalidate=604800" }];
    return [
      { source: "/sets/:path*", headers: cache },
      { source: "/cards/:path*", headers: cache },
    ];
  },
};

export default nextConfig;
