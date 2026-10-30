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
    throw new Error(`Poof ${res.status}: ${body.slice(0, 200)}`);
  }
  return new Uint8Array(await res.arrayBuffer());
}

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
    const bytes = await removeBackground(p.image_url);
    const path = `${p.id.replace(/[^a-zA-Z0-9_-]/g, "_")}.webp`;
    const { error: upErr } = await admin.storage.from("cutouts").upload(path, bytes, { contentType: "image/webp", upsert: true });
    if (upErr) throw new Error(upErr.message);
    // A new version each time, so a redone cut-out isn't hidden behind a cached old one.
    const url = `${admin.storage.from("cutouts").getPublicUrl(path).data.publicUrl}?v=${Date.now()}`;
    const { error: dbErr } = await admin.from("products").update({ cutout_url: url }).eq("id", p.id);
    if (dbErr) throw new Error(dbErr.message);
    return { id: p.id, name: p.name, status: "done", url };
  } catch (e) {
    return { id: p.id, name: p.name, status: "failed", error: (e as Error).message };
  }
}

/** Cut out a list of products a few at a time. */
export async function makeCutouts(admin: SupabaseClient<Database>, rows: ProductRow[], concurrency = 4): Promise<CutoutResult[]> {
  const results: CutoutResult[] = [];
  let next = 0;
  await Promise.all(
    Array.from({ length: Math.min(concurrency, rows.length) }, async () => {
      while (next < rows.length) {
        const row = rows[next++];
        results.push(await makeCutout(admin, row));
      }
    }),
  );
  return results;
}
