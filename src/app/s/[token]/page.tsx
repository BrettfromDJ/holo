import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { AllocationShowcase } from "@/components/portfolio/allocation-showcase";
import { Delta, DeltaPill } from "@/components/product/delta";
import { ProductImage } from "@/components/product/product-image";
import { Logo } from "@/components/shell/logo";
import { categoryOf } from "@/lib/catalog";
import { todayISO } from "@/lib/finance/dates";
import { computeHoldings, summarize, type HoldingView } from "@/lib/finance/portfolio";
import { formatDate, money } from "@/lib/format";
import { loadCollection } from "@/lib/supabase/load";
import { getAdminSupabase } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

/**
 * Public, read-only view of a collection behind an unguessable share token.
 * Rendered on the server with the service role; only aggregate values and
 * product holdings are sent to the browser. Costs and gains appear only when
 * the owner enabled "show gains". No transactions, sources, notes or email.
 */
async function loadShare(token: string) {
  const admin = getAdminSupabase();
  if (!admin || !/^[A-Za-z0-9_-]{20,64}$/.test(token)) return null;
  const { data: link } = await admin.from("share_links").select("*").eq("token", token).is("revoked_at", null).maybeSingle();
  if (!link) return null;
  const data = await loadCollection(admin, link.user_id);
  const today = todayISO();
  const holdings = computeHoldings(data, today).sort((a, b) => (b.value ?? -1) - (a.value ?? -1));
  return { link, holdings, summary: summarize(holdings, 0), today };
}

export async function generateMetadata({ params }: { params: Promise<{ token: string }> }): Promise<Metadata> {
  const { token } = await params;
  const share = await loadShare(token);
  return {
    title: share?.link.title || "Shared collection",
    robots: { index: false, follow: false },
  };
}

export default async function SharedCollectionPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const share = await loadShare(token);
  if (!share) notFound();
  const { link, holdings, summary, today } = share;
  const showGains = link.show_gains;

  return (
    <main className="mx-auto w-full max-w-[1100px] px-4 pb-24 pt-8 sm:px-8 sm:pt-12">
      <div className="flex items-center justify-between">
        <Logo />
        <span className="rounded-full bg-surface-2 px-3 py-1 text-[12px] text-muted">Read-only</span>
      </div>

      <header className="mt-12">
        <p className="text-[14px] font-medium text-muted">{link.title || "Collection"}</p>
        <p className="tabular mt-2 font-display text-[52px] leading-none text-lime sm:text-[72px]">{money(summary.marketValue)}</p>
        <p className="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1 text-[14px] text-muted">
          <span>
            {summary.unitCount} item{summary.unitCount === 1 ? "" : "s"} · {summary.holdingsCount} product{summary.holdingsCount === 1 ? "" : "s"}
          </span>
          {showGains && (
            <span className="flex items-center gap-1.5">
              · <Delta value={summary.unrealized} ratio={summary.unrealizedPct} /> unrealized gain
            </span>
          )}
        </p>
      </header>

      {holdings.length > 0 && (
        <section className="mt-10 rounded-[var(--radius-card)] border border-border bg-surface p-5 sm:p-6">
          <h2 className="mb-4 text-[15px] font-semibold">What&apos;s in it</h2>
          <AllocationShowcase holdings={holdings} showGains={showGains} linkTiles={false} />
        </section>
      )}

      <section className="mt-10">
        {holdings.length ? (
          <div className="grid grid-cols-2 gap-x-4 gap-y-8 sm:grid-cols-3 lg:grid-cols-4">
            {holdings.map((h) => (
              <SharedTile key={h.key} h={h} showGains={showGains} />
            ))}
          </div>
        ) : (
          <p className="py-16 text-center text-[15px] text-muted">This collection is empty.</p>
        )}
      </section>

      <footer className="mt-16 border-t border-border pt-6 text-[12px] text-subtle">
        Values are market prices as of {formatDate(today)}{summary.unpricedCount > 0 ? `; ${summary.unpricedCount} item${summary.unpricedCount === 1 ? " has" : "s have"} no market price and ${summary.unpricedCount === 1 ? "isn't" : "aren't"} counted` : ""}. Shared with Holo.
      </footer>
    </main>
  );
}

function SharedTile({ h, showGains }: { h: HoldingView; showGains: boolean }) {
  const grade = h.identity.grade ? `${h.identity.grade.company} ${h.identity.grade.grade}` : null;
  return (
    <div className="flex flex-col">
      <div className="relative">
        <ProductImage product={h.product} grade={h.identity.grade} className="aspect-square w-full" />
        <span className="tabular absolute left-2.5 top-2.5 rounded-full bg-background/80 px-2 py-0.5 text-[11px] font-semibold backdrop-blur">×{h.quantity}</span>
        {grade && <span className="absolute right-2.5 top-2.5 rounded-full bg-background/80 px-2 py-0.5 text-[11px] font-medium text-muted backdrop-blur">{grade}</span>}
      </div>
      <p className="mt-3 truncate text-[14px] font-medium">{h.product?.name ?? "Unknown product"}</p>
      <p className="truncate text-[12px] text-muted">{[h.product?.setName, h.product ? categoryOf(h.product) : null].filter(Boolean).join(" · ")}</p>
      <div className="mt-2 flex items-end justify-between gap-2">
        <div>
          <p className="tabular text-[15px] font-semibold">{money(h.value)}</p>
          {h.quantity > 1 && <p className="tabular text-[12px] text-muted">{money(h.price)} ea</p>}
        </div>
        {showGains && <DeltaPill ratio={h.unrealizedPct} />}
      </div>
    </div>
  );
}
