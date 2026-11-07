import { NextResponse } from "next/server";
import { apnsKeyProblem, isApnsConfigured, sendPush } from "@/lib/server/apns";
import { allowRequest, clientKey } from "@/lib/server/rate-limit";
import { getAdminSupabase, getRequestUser } from "@/lib/supabase/server";

/**
 * POST /api/push/test — send a test notification to the signed-in user's
 * phones, to check push works end to end (token saved, Apple key, server).
 */
export async function POST(req: Request) {
  if (!allowRequest(clientKey(req, "push-test"), 3, 5)) {
    return NextResponse.json({ error: { code: "rate_limited", message: "Give it a minute between tests." } }, { status: 429 });
  }
  const user = await getRequestUser();
  if (!user) return NextResponse.json({ error: { code: "unauthorized", message: "Sign in first." } }, { status: 401 });
  if (!isApnsConfigured()) {
    return NextResponse.json({ error: { code: "not_configured", message: "The server is missing its Apple push key (APNS_… variables), or hasn't been redeployed since they were added." } }, { status: 503 });
  }
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ error: { code: "not_configured", message: "Supabase service role isn't configured." } }, { status: 503 });

  const { data: devices, error } = await admin.from("device_tokens").select("token, environment").eq("user_id", user.id);
  if (error) {
    const missing = /device_tokens/.test(error.message);
    return NextResponse.json({ error: { code: "not_configured", message: missing ? "Run the push notifications migration in Supabase." : error.message } }, { status: 503 });
  }
  if (!devices?.length) {
    return NextResponse.json({ error: { code: "no_devices", message: "No phone is registered yet. Allow notifications in the app first." } }, { status: 404 });
  }

  const message = { title: "Lucent notifications work", body: "You'll get an alert like this when a watched card hits your target price." };
  const results = [];
  const keyProblem = apnsKeyProblem();
  if (keyProblem) {
    return NextResponse.json({ error: { code: "bad_key", message: keyProblem } }, { status: 500 });
  }
  try {
    for (const env of ["production", "sandbox"] as const) {
      results.push(...(await sendPush(devices.filter((d) => d.environment === env).map((d) => d.token), message, env)));
    }
  } catch (e) {
    // The key reads fine, so this is the connection to Apple.
    const detail = e instanceof Error ? e.message : String(e);
    return NextResponse.json({ error: { code: "send_failed", message: `Couldn't reach Apple's push service: ${detail}` } }, { status: 502 });
  }
  const sent = results.filter((r) => r.ok).length;
  // Only ever echo values shaped like Apple's 10-character IDs: anything else (say, the key itself
  // pasted into the wrong box) is described, never shown.
  const id = (name: string) => {
    const v = (process.env[name] ?? "").trim().replace(/^["']|["']$/g, "");
    return /^[A-Z0-9]{10}$/.test(v) ? v : `not a 10-character ID (${v.length} characters${/PRIVATE KEY|^MI/.test(v) ? ", looks like the private key" : ""})`;
  };
  const ids = `Key ID ${id("APNS_KEY_ID")}, Team ID ${id("APNS_TEAM_ID")}`;
  // A token Apple turns down names the IDs in use, to check against the key's page (they aren't secret).
  const reasons = [...new Set(results.filter((r) => !r.ok).map((r) => r.reason ?? `HTTP ${r.status}`))].map((r) =>
    /ProviderToken|TopicDisallowed|BadEnvironmentKeyInToken/.test(r) ? `${r} (${ids}, app ${(process.env.APNS_BUNDLE_ID ?? "").trim()})` : r,
  );
  return NextResponse.json({ sent, failed: results.length - sent, reasons });
}
