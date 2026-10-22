import type { EmailOtpType } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { getServerSupabase } from "@/lib/supabase/server";

/**
 * Completes the email sign-in flow and returns to the app. Handles both link
 * styles: `?code=` (PKCE — must open in the browser that asked for the link)
 * and `?token_hash=&type=` (works from any browser or device). Failures go
 * back to /login with the reason instead of silently landing signed-out.
 */
export async function GET(req: Request) {
  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  const tokenHash = url.searchParams.get("token_hash");
  const type = url.searchParams.get("type") as EmailOtpType | null;
  const linkError = url.searchParams.get("error_description");

  const supabase = await getServerSupabase();
  let error: string | null = linkError;
  if (!error && supabase) {
    if (code) error = (await supabase.auth.exchangeCodeForSession(code)).error?.message ?? null;
    else if (tokenHash && type) error = (await supabase.auth.verifyOtp({ token_hash: tokenHash, type })).error?.message ?? null;
    else error = "The sign-in link is missing its code.";
  }
  if (error) return NextResponse.redirect(new URL(`/login?error=${encodeURIComponent(error)}`, url.origin));
  return NextResponse.redirect(new URL("/", url.origin));
}
