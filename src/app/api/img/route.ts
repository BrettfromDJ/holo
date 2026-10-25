import sharp from "sharp";
import { NextResponse } from "next/server";
import { cutoutWhiteBackground } from "@/lib/server/cutout";

export const runtime = "nodejs";

/** Image CDNs we fetch from. Anything else is redirected to as-is, never fetched. */
const HOSTS = ["tcgplayer.com", "tcgapi.dev", "tcgapi.com", "pokemontcg.io", ...(process.env.IMAGE_PROXY_HOSTS ?? "").split(",").map((h) => h.trim()).filter(Boolean)];
const MAX_BYTES = 8 * 1024 * 1024;
const CACHE = "public, max-age=604800, s-maxage=31536000, stale-while-revalidate=86400";

function allowed(url: URL) {
  return url.protocol === "https:" && HOSTS.some((h) => url.hostname === h || url.hostname.endsWith(`.${h}`));
}

/**
 * GET /api/img?u=<image url> — a product photo with its white backdrop made
 * transparent. Results are cached by the CDN, so each image is processed
 * once. Anything that can't be processed falls back to the original.
 */
export async function GET(req: Request) {
  const raw = new URL(req.url).searchParams.get("u");
  let src: URL;
  try {
    src = new URL(raw ?? "");
  } catch {
    return NextResponse.json({ error: { message: "Missing or invalid image URL." } }, { status: 400 });
  }
  const original = NextResponse.redirect(src, { status: 302, headers: { "cache-control": "public, max-age=3600" } });
  if (!allowed(src)) return original;

  try {
    const res = await fetch(src, { signal: AbortSignal.timeout(10_000), headers: { "user-agent": "holo-image-proxy" } });
    if (!res.ok || !res.headers.get("content-type")?.startsWith("image/")) return original;
    const bytes = Buffer.from(await res.arrayBuffer());
    if (bytes.length > MAX_BYTES) return original;

    const { data, info } = await sharp(bytes).rotate().resize({ width: 900, height: 900, fit: "inside", withoutEnlargement: true }).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    const cut = cutoutWhiteBackground(data, info.width, info.height);
    const pixels = cut ? Buffer.from(cut.data.buffer, cut.data.byteOffset, cut.data.byteLength) : data;
    const webp = await sharp(pixels, { raw: { width: info.width, height: info.height, channels: 4 } })
      .webp({ quality: 88, alphaQuality: 90, effort: 4 })
      .toBuffer();
    return new NextResponse(new Uint8Array(webp), {
      headers: { "content-type": "image/webp", "cache-control": CACHE, "x-holo-cutout": cut ? `removed=${cut.removed.toFixed(2)}` : "skipped" },
    });
  } catch {
    return original;
  }
}
