import { NextResponse } from "next/server";
import { cardSightConfigured, identifyWithCardSight } from "@/lib/pricing/cardsight";
import { identifyPhoto, MAX_IMAGE_BYTES, ScanFailure, scanBalance } from "@/lib/pricing/identify";
import { overLimit, takeQuota } from "@/lib/server/api-cache";
import { allowRequest, clientKey } from "@/lib/server/rate-limit";
import { Stopwatch } from "@/lib/server/timing";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { getRequestUser } from "@/lib/supabase/server";

/**
 * Card scanning (CardSight AI when CARDSIGHT_API_KEY is set, else TCG API). Every call is paid
 * for, so when accounts
 * are set up only signed-in users may scan, and each client is rate limited
 * (bursty enough for rapid scanning, not for draining the balance).
 */
async function authorized(): Promise<boolean> {
  if (!isSupabaseConfigured()) return true; // No accounts configured (local use).
  return Boolean(await getRequestUser());
}

function fail(code: string, message: string, status: number) {
  return NextResponse.json({ error: { code, message } }, { status });
}

export async function POST(req: Request) {
  // Each step is timed; the laps come back with the result so a slow scan says where its
  // seconds went (and the Vercel log keeps a line per scan).
  const clock = new Stopwatch();
  // Who is asking (checked on this server, no round trip) while the photo is read in.
  const [user, formResult] = await Promise.all([
    isSupabaseConfigured() ? getRequestUser() : ({ id: "local" } as const),
    req.formData().then(
      (form) => ({ form, error: null }),
      () => ({ form: null, error: "Send the photo as form data." }),
    ),
  ]);
  clock.lap("auth");
  if (!user) return fail("unauthorized", "Sign in to scan.", 401);
  if (!allowRequest(clientKey(req, "scan"), 20, 40)) return fail("rate_limited", "Scanning too fast. Give it a second.", 429);
  if (!formResult.form) return fail("bad_image", formResult.error ?? "Send the photo as form data.", 400);
  const f = formResult.form.get("image");
  const image = f instanceof File ? f : null;
  if (!image || !/^image\/(jpeg|png|webp)$/.test(image.type)) return fail("bad_image", "Send a JPEG, PNG or WebP photo.", 400);
  if (image.size > MAX_IMAGE_BYTES) return fail("bad_image", "That photo is over 8 MB.", 400);
  // Each scan is paid for, so each person has a daily allowance. It's counted while the
  // scanner works rather than before (a database trip off the wait); someone over the limit
  // gets their answer refused after one more paid call, which is the cheaper trade.
  const quota = takeQuota(req, "scan", isSupabaseConfigured() ? user : null);

  try {
    const game = new URL(req.url).searchParams.get("game") ?? undefined;
    // CardSight AI when its key is set on the server; otherwise TCG API's scanner.
    const result = cardSightConfigured() ? await identifyWithCardSight(image, { game, clock }) : await identifyPhoto(image, { game });
    if (!cardSightConfigured()) clock.lap("identify");
    const withinQuota = await quota;
    clock.lap("quota");
    if (!withinQuota) return NextResponse.json(overLimit("scans"), { status: 429 });
    const timing = clock.report();
    console.log("scan timing", JSON.stringify({ ...timing, bytes: image.size, status: result.status }));
    return NextResponse.json({ ...result, timing }, { headers: { "Server-Timing": clock.header() } });
  } catch (err) {
    if (err instanceof ScanFailure) {
      console.error("scan failed", err.code, err.status, err.message);
      return fail(err.code, err.message, err.status);
    }
    console.error(err);
    return fail("upstream", "The scanner had a problem. Try again.", 502);
  }
}

/** Scans left on the account. Free to call. (CardSight doesn't report a balance.) */
export async function GET() {
  if (!(await authorized())) return fail("unauthorized", "Sign in to scan.", 401);
  // Which scanner answers, so the app skips its own on-phone read when CardSight does it all.
  if (cardSightConfigured()) return NextResponse.json({ scansRemaining: null, provider: "cardsight" });
  try {
    return NextResponse.json({ scansRemaining: await scanBalance(), provider: "tcgapi" });
  } catch (err) {
    if (err instanceof ScanFailure) return fail(err.code, err.message, err.status);
    return NextResponse.json({ scansRemaining: null });
  }
}
