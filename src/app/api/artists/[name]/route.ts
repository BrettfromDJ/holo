import { NextResponse } from "next/server";
import { artistCards } from "@/lib/server/artist-cards";
import { getAdminSupabase } from "@/lib/supabase/server";

export const maxDuration = 60;

/** GET /api/artists/:name — every card the artist drew, priciest first. */
export async function GET(_req: Request, { params }: { params: Promise<{ name: string }> }) {
  const { name } = await params;
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ name, cards: [] });
  const cards = await artistCards(admin, decodeURIComponent(name));
  return NextResponse.json(
    { name: decodeURIComponent(name), cards },
    { headers: { "cache-control": cards.length ? "public, s-maxage=3600, stale-while-revalidate=86400" : "no-store" } },
  );
}
