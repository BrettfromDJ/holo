import { NextResponse } from "next/server";
import { identifyPhoto, MAX_IMAGE_BYTES, ScanFailure, scanBalance } from "@/lib/pricing/identify";
import { allowRequest, clientKey } from "@/lib/server/rate-limit";
import { getServerSupabase } from "@/lib/supabase/server";

/**
 * Card scanning. Every call spends one prepaid TCG API scan, so when accounts
 * are set up only signed-in users may scan, and each client is rate limited
 * (bursty enough for rapid scanning, not for draining the balance).
 */
async function authorized(): Promise<boolean> {
  const supabase = await getServerSupabase();
  if (!supabase) return true; // No accounts configured (local use).
  const { data } = await supabase.auth.getUser();
  return Boolean(data.user);
}

function fail(code: string, message: string, status: number) {
  return NextResponse.json({ error: { code, message } }, { status });
}

export async function POST(req: Request) {
  if (!(await authorized())) return fail("unauthorized", "Sign in to scan.", 401);
  if (!allowRequest(clientKey(req, "scan"), 20, 40)) return fail("rate_limited", "Scanning too fast. Give it a second.", 429);

  let image: File | null = null;
  try {
    const form = await req.formData();
    const f = form.get("image");
    image = f instanceof File ? f : null;
  } catch {
    return fail("bad_image", "Send the photo as form data.", 400);
  }
  if (!image || !/^image\/(jpeg|png|webp)$/.test(image.type)) return fail("bad_image", "Send a JPEG, PNG or WebP photo.", 400);
  if (image.size > MAX_IMAGE_BYTES) return fail("bad_image", "That photo is over 8 MB.", 400);

  try {
    const game = new URL(req.url).searchParams.get("game") ?? undefined;
    return NextResponse.json(await identifyPhoto(image, { game }));
  } catch (err) {
    if (err instanceof ScanFailure) return fail(err.code, err.message, err.status);
    console.error(err);
    return fail("upstream", "The scanner had a problem. Try again.", 502);
  }
}

/** Scans left on the account. Free to call. */
export async function GET() {
  if (!(await authorized())) return fail("unauthorized", "Sign in to scan.", 401);
  try {
    return NextResponse.json({ scansRemaining: await scanBalance() });
  } catch (err) {
    if (err instanceof ScanFailure) return fail(err.code, err.message, err.status);
    return NextResponse.json({ scansRemaining: null });
  }
}
