import { NextResponse } from "next/server";
import { getServerSupabase } from "@/lib/supabase/server";

/** Completes the email sign-in flow and returns to the app. */
export async function GET(req: Request) {
  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  if (code) {
    const supabase = await getServerSupabase();
    await supabase?.auth.exchangeCodeForSession(code);
  }
  return NextResponse.redirect(new URL("/", url.origin));
}
