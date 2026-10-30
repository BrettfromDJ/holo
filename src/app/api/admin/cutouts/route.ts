import { NextResponse } from "next/server";
import { isCodeCard, isPoofConfigured, makeCutouts } from "@/lib/server/cutouts";
import { getAdminSupabase } from "@/lib/supabase/server";
import type { ProductRow } from "@/lib/supabase/database.types";

export const dynamic = "force-dynamic";
export const maxDuration = 300;

/**
 * POST /api/admin/cutouts?set=<slug or part of a name>[&limit=N][&redo=1][&dry=1]
 * Removes the white background from a set's sealed product photos with Poof (one credit
 * each). Products that already have a cut-out are left alone unless `redo=1`. `dry=1` only
 * lists what would be done. Needs `Authorization: Bearer <CRON_SECRET>`.
 */
export async function POST(req: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret || req.headers.get("authorization") !== `Bearer ${secret}`) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ error: "Supabase service role is not configured." }, { status: 503 });

  const params = new URL(req.url).searchParams;
  const query = params.get("set")?.trim();
  if (!query) return NextResponse.json({ error: "Add ?set=<set slug or name>." }, { status: 400 });
  const limit = Math.min(Number(params.get("limit")) || 50, 200);
  const redo = params.get("redo") === "1";
  const dry = params.get("dry") === "1";

  // The set: an exact slug, else a single set whose name contains the words.
  let { data: sets } = await admin.from("catalog_sets").select("slug, name, game_name").eq("slug", query);
  if (!sets?.length) ({ data: sets } = await admin.from("catalog_sets").select("slug, name, game_name").ilike("name", `%${query}%`).limit(20));
  if (!sets?.length) return NextResponse.json({ error: `No set matches "${query}".` }, { status: 404 });
  if (sets.length > 1) {
    return NextResponse.json({ error: "More than one set matches; use one of these slugs.", sets }, { status: 409 });
  }
  const set = sets[0];

  const { data: rows, error } = await admin.from("products").select("*").eq("set_id", set.slug).eq("kind", "sealed").order("name");
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  const todo = (rows as ProductRow[]).filter((p) => p.image_url && !isCodeCard(p) && (redo || !p.cutout_url)).slice(0, limit);

  if (dry) return NextResponse.json({ set, wouldProcess: todo.map((p) => ({ id: p.id, name: p.name, image: p.image_url })) });
  if (!isPoofConfigured()) return NextResponse.json({ error: "POOF_API_KEY is not set in Vercel." }, { status: 503 });

  const results = await makeCutouts(admin, todo);
  return NextResponse.json({
    set,
    done: results.filter((r) => r.status === "done").length,
    failed: results.filter((r) => r.status === "failed").length,
    results,
  });
}
