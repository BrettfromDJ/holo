import { NextResponse } from "next/server";
import { isTcgApiConfigured, rateLimitStatus } from "@/lib/pricing/tcgapi";
import { isSupabaseConfigured } from "@/lib/supabase/config";

export const dynamic = "force-dynamic";

/** Which integrations are configured. Never returns secrets. */
export async function GET() {
  return NextResponse.json({
    tcgapi: { configured: isTcgApiConfigured(), ...rateLimitStatus() },
    supabase: { configured: isSupabaseConfigured() },
  });
}
