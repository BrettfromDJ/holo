import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database, ProductRow } from "../supabase/database.types";

/**
 * Sealed product photos come on white. Poof (poof.bg) cuts the product out once; the result
 * is stored in the public `cutouts` bucket and its address saved on the product, so the
 * website and the app show it from then on. Each cut-out costs one Poof credit.
 */

const POOF_URL = "https://api.poof.bg/v1/remove";

export function isPoofConfigured(): boolean {
  return Boolean(process.env.POOF_API_KEY);
}

/** Online game code cards aren't shown anywhere, so they're never worth a credit. */
export function isCodeCard(p: Pick<ProductRow, "name" | "product_type" | "rarity">): boolean {
  return /\bcode\s*card\b|\bonline code\b/i.test(`${p.name} ${p.product_type ?? ""} ${p.rarity ?? ""}`);
}

class RateLimited extends Error {}

/** Ask Poof for the product without its background: a WebP cropped to the product with a little room around it. */
async function removeBackground(imageUrl: string): Promise<Uint8Array> {
  const form = new FormData();
  form.set("url", imageUrl);
  form.set("format", "webp");
  form.set("crop", "true");
  form.set("padding", "0.03");
  const res = await fetch(POOF_URL, { method: "POST", headers: { "x-api-key": process.env.POOF_API_KEY! }, body: form });
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    if (res.status === 429) throw new RateLimited(body.slice(0, 200));
    throw new Error(`Poof ${res.status}: ${body.slice(0, 200)}`);
  }
  return new Uint8Array(await res.arrayBuffer());
}

/** TCGplayer serves its product photos at 400px; ask for a bigger copy so cut-outs stay sharp on phones. */
function largerImage(url: string): string {
  return url.replace("/fit-in/400x400/", "/fit-in/1000x1000/");
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export interface CutoutResult {
  id: string;
  name: string;
  status: "done" | "skipped" | "failed";
  url?: string;
  error?: string;
}

/** Cut out one sealed product and save it. */
export async function makeCutout(admin: SupabaseClient<Database>, p: ProductRow): Promise<CutoutResult> {
  if (!p.image_url) return { id: p.id, name: p.name, status: "skipped", error: "no image" };
  try {
    let bytes: Uint8Array;
    try {
      bytes = await removeBackground(largerImage(p.image_url));
    } catch (e) {
      // Too many requests is for the caller to wait out; anything else, try the original picture.
      if (e instanceof RateLimited || largerImage(p.image_url) === p.image_url) throw e;
      bytes = await removeBackground(p.image_url);
    }
    const path = `${p.id.replace(/[^a-zA-Z0-9_-]/g, "_")}.webp`;
    const { error: upErr } = await admin.storage.from("cutouts").upload(path, bytes, { contentType: "image/webp", upsert: true });
    if (upErr) throw new Error(upErr.message);
    // A new version each time, so a redone cut-out isn't hidden behind a cached old one.
    const url = `${admin.storage.from("cutouts").getPublicUrl(path).data.publicUrl}?v=${Date.now()}`;
    const { error: dbErr } = await admin.from("products").update({ cutout_url: url }).eq("id", p.id);
    if (dbErr) throw new Error(dbErr.message);
    return { id: p.id, name: p.name, status: "done", url };
  } catch (e) {
    if (e instanceof RateLimited) throw e;
    return { id: p.id, name: p.name, status: "failed", error: (e as Error).message };
  }
}

/**
 * Cut out a list of products one at a time, paced to Poof's per-minute limit (POOF_PER_MINUTE,
 * 4 on the free plan), stopping before the request runs out of time. Run it again to carry on:
 * finished products are skipped.
 */
export async function makeCutouts(
  admin: SupabaseClient<Database>,
  rows: ProductRow[],
  { budgetMs = 270_000 }: { budgetMs?: number } = {},
): Promise<{ results: CutoutResult[]; remaining: number }> {
  const perMinute = Number(process.env.POOF_PER_MINUTE) || 4;
  const gap = Math.ceil(60_000 / perMinute) + 500;
  const started = Date.now();
  const results: CutoutResult[] = [];
  let i = 0;
  while (i < rows.length) {
    const t = Date.now();
    try {
      results.push(await makeCutout(admin, rows[i]));
      i++;
    } catch {
      // Rate limited: wait a whole minute and try the same product again.
      if (Date.now() - started + 61_000 > budgetMs) break;
      await sleep(61_000);
      continue;
    }
    if (i < rows.length) {
      const wait = Math.max(0, gap - (Date.now() - t));
      if (Date.now() - started + wait + 20_000 > budgetMs) break;
      await sleep(wait);
    }
  }
  return { results, remaining: rows.length - i };
}
