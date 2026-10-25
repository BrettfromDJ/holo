import { NextResponse } from "next/server";
import { setChecklist } from "@/lib/pricing/tcgapi";
import { errorResponse } from "@/lib/server/http";

/** GET /api/sets/<set slug> — the set's singles in collector-number order. */
export async function GET(_req: Request, { params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  try {
    return NextResponse.json({ checklist: await setChecklist(decodeURIComponent(slug)) }, { headers: { "cache-control": "private, max-age=3600" } });
  } catch (err) {
    return errorResponse(err);
  }
}
