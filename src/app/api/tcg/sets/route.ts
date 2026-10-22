import { NextResponse } from "next/server";
import { tcgApiProvider } from "@/lib/pricing";
import { errorResponse } from "@/lib/server/http";

/** Pokémon sets, newest first. Cached server-side for a day. */
export async function GET() {
  try {
    return NextResponse.json({ sets: await tcgApiProvider.listSets() }, { headers: { "Cache-Control": "private, max-age=3600" } });
  } catch (err) {
    return errorResponse(err);
  }
}
