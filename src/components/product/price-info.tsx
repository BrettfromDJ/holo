"use client";

import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { money } from "@/lib/format";
import { cn } from "@/lib/utils";
import { useEbayData } from "./ebay-sales";

/** What a price is and where it comes from, for a click on a headline figure. Same as the app's `PriceInfoSheet`. */
export interface PriceInfoData {
  /** What the figure is: "Near Mint · ungraded", "Your PSA 10", "Your collection". */
  title: string;
  value: number | null;
  rows: [string, string][];
  /** Cross-checked against eBay's recent sold prices (cards only). */
  ebay?: { productId: string; printing: string | null; grade: string | null } | null;
  note?: string | null;
  stale?: boolean;
  /** One copy's price for the eBay comparison, when `value` is several copies. */
  each?: number | null;
}

export function PriceInfoDialog({ info, onOpenChange }: { info: PriceInfoData | null; onOpenChange: (open: boolean) => void }) {
  return (
    <Dialog open={info !== null} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[440px]">{info && <Body info={info} />}</DialogContent>
    </Dialog>
  );
}

function Body({ info }: { info: PriceInfoData }) {
  const e = info.ebay;
  const checkable = Boolean(e && e.productId.startsWith("tcgapi:") || e?.productId.startsWith("sample:"));
  const { load } = useEbayData(e?.productId ?? "", e?.printing ?? null, { market: info.each ?? info.value, active: checkable });
  const rows = [...info.rows];
  if (e && checkable) {
    if (load.state !== "ready") rows.push(["eBay sold, 30 days", load.state === "error" ? "Unavailable" : "Checking…"]);
    else {
      const data = load.data;
      const stats = e.grade ? data?.graded[e.grade] : data?.ungraded;
      if (!stats || stats.median === null || !stats.count) rows.push(["eBay sold, 30 days", "No sales"]);
      else {
        rows.push(["eBay sold, 30 days", `${money(stats.median)} median · ${stats.count} sale${stats.count === 1 ? "" : "s"}`]);
        const prices = (data?.sales ?? []).filter((s) => (s.grade ?? null) === (e.grade ?? null)).map((s) => s.price);
        if (prices.length >= 3) rows.push(["Recent sales range", `${money(Math.min(...prices))} – ${money(Math.max(...prices))}`]);
        const v = info.each ?? info.value;
        if (v !== null && stats.median > 0 && stats.count >= 3) {
          const off = v / stats.median - 1;
          rows.push(["Against eBay", Math.abs(off) <= 0.15 ? "Agrees" : `${off > 0 ? "+" : ""}${(off * 100).toFixed(1)}% vs median`]);
        }
      }
    }
  }
  return (
    <div className="p-6">
      <p className="font-mono text-[11px] uppercase tracking-[0.08em] text-subtle">Where this price comes from</p>
      <DialogTitle className="mt-3 text-[14px] font-normal text-muted">{info.title}</DialogTitle>
      <p className={cn("tabular mt-1 font-display text-[38px] leading-none tracking-[-0.03em]", info.stale && "opacity-60")}>{money(info.value)}</p>
      <div className="mt-5 divide-y divide-white/[0.08] rounded-2xl border border-white/10 bg-white/[0.04] px-4">
        {rows.map(([label, value]) => (
          <div key={label} className="flex items-baseline justify-between gap-4 py-2.5 text-[14px]">
            <span className="text-muted">{label}</span>
            <span className="tabular text-right font-medium">{value}</span>
          </div>
        ))}
      </div>
      {info.note && <p className="mt-4 text-[13px] text-muted text-pretty">{info.note}</p>}
    </div>
  );
}
