import { NextResponse } from "next/server";
import { isApnsConfigured, sendPush } from "@/lib/server/apns";
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

  const message = { title: "Holo notifications work", body: "You'll get an alert like this when a watched card hits your target price." };
  const results = [];
  for (const env of ["production", "sandbox"] as const) {
    results.push(...(await sendPush(devices.filter((d) => d.environment === env).map((d) => d.token), message, env)));
  }
  const sent = results.filter((r) => r.ok).length;
  const reasons = [...new Set(results.filter((r) => !r.ok).map((r) => r.reason ?? `HTTP ${r.status}`))];
  return NextResponse.json({ sent, failed: results.length - sent, reasons });
}
