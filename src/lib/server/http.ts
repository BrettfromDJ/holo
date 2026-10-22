import "server-only";
import { NextResponse } from "next/server";
import { PricingUnavailableError } from "../pricing/types";

const STATUS: Record<PricingUnavailableError["code"], number> = {
  not_configured: 503,
  rate_limited: 429,
  tier: 402,
  auth: 502,
  not_found: 404,
  upstream: 502,
};

/** Convert pricing errors into a stable JSON shape the UI can render. */
export function errorResponse(err: unknown) {
  if (err instanceof PricingUnavailableError) {
    return NextResponse.json(
      { error: { code: err.code, message: err.message, retryAfter: err.retryAfter ?? null } },
      { status: STATUS[err.code], headers: err.retryAfter ? { "Retry-After": String(err.retryAfter) } : undefined },
    );
  }
  console.error(err);
  return NextResponse.json({ error: { code: "internal", message: "Something went wrong." } }, { status: 500 });
}
