import { NextResponse } from "next/server";
import { tcgApiProvider } from "@/lib/pricing";
import { errorResponse } from "@/lib/server/http";

export async function GET(req: Request) {
  const url = new URL(req.url);
  const direction = url.searchParams.get("direction") === "down" ? "down" : "up";
  const period = (["24h", "7d", "30d"].includes(url.searchParams.get("period") ?? "") ? url.searchParams.get("period") : "7d") as "24h" | "7d" | "30d";
  const type = url.searchParams.get("type") === "sealed" ? "sealed" : url.searchParams.get("type") === "cards" ? "cards" : "all";
  try {
    return NextResponse.json({ movers: await tcgApiProvider.topMovers({ direction, period, type, limit: 10 }) });
  } catch (err) {
    return errorResponse(err);
  }
}
