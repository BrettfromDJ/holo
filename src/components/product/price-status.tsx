import { AlertCircle, Clock, PenLine } from "lucide-react";
import { Hint } from "@/components/ui/tooltip";
import { relativeTime } from "@/lib/format";
import type { HoldingView } from "@/lib/finance/portfolio";

/** Small indicator for anything that isn't a fresh live price. */
export function PriceStatus({ holding, className }: { holding: Pick<HoldingView, "priceStatus" | "priceUpdatedAt" | "priceOrigin">; className?: string }) {
  if (holding.priceStatus === "live") return null;
  const map = {
    stale: { icon: Clock, text: `Last known price · updated ${relativeTime(holding.priceUpdatedAt)}` },
    unavailable: { icon: AlertCircle, text: "No market price available. Excluded from value and gains." },
    manual: { icon: PenLine, text: `Manual valuation · ${holding.priceUpdatedAt ?? ""}` },
  } as const;
  const { icon: Icon, text } = map[holding.priceStatus];
  return (
    <Hint content={text}>
      <span className={className} aria-label={text}>
        <Icon className="size-3.5 text-subtle" />
      </span>
    </Hint>
  );
}
