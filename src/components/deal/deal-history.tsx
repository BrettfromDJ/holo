"use client";

import { Banknote, ChevronLeft, Search, Star } from "lucide-react";
import { useMemo, useState } from "react";
import { ProductImage } from "@/components/product/product-image";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { bestDeal, dealDayTotals, dealKind, matchesDealSearch, profitClimb, recordAhead, recordTotals, type DealKind } from "@/lib/deal";
import { money, signedMoney } from "@/lib/format";
import { cn } from "@/lib/utils";
import { DealCard, RoundClose } from "./deal-card";
import { DealPhotos } from "./deal-photos";
import { DealListRow, ParkedMenu, recordNote } from "./deal-start";
import { EMPTY, KIND_NOUN, PATH_TITLE, cardsLabel, recordTitle, type DealRecord, type DealRecordLine, type ParkedDeal } from "./deal-types";

/** The local day a deal closed on, as YYYY-MM-DD. */
const dayOf = (at: string) => new Date(at).toLocaleDateString("en-CA");

function dayTitle(day: string) {
  const today = dayOf(new Date().toISOString());
  const yesterday = dayOf(new Date(Date.now() - 86_400_000).toISOString());
  if (day === today) return "Today";
  if (day === yesterday) return "Yesterday";
  return new Date(`${day}T12:00:00`).toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" });
}

const FILTERS: { kind: DealKind | null; label: string }[] = [
  { kind: null, label: "All" },
  { kind: "buy", label: "Buys" },
  { kind: "sell", label: "Sales" },
  { kind: "trade", label: "Trades" },
];

/** A streaming-app chip: glass, the picked one white (the app's Chip). */
export function Chip({ on, onClick, children }: { on: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button type="button" aria-pressed={on} onClick={onClick} className={cn("h-9 shrink-0 rounded-[13px] px-3.5 text-[14px] font-semibold transition-colors", on ? "bg-white text-[#0b0b0c]" : "glass-stat text-white hover:bg-white/[0.08]")}>
      {children}
    </button>
  );
}

/** How far ahead, adding up deal by deal, in lime (pink when under water). */
function ProfitClimb({ points }: { points: number[] }) {
  if (points.length < 2) return null;
  const w = 600;
  const h = 72;
  const lo = Math.min(0, ...points);
  const hi = Math.max(...points, lo + 1);
  const x = (i: number) => (i / (points.length - 1)) * w;
  const y = (v: number) => h - 3 - ((v - lo) / (hi - lo)) * (h - 6);
  const line = points.map((v, i) => `${i ? "L" : "M"}${x(i).toFixed(1)},${y(v).toFixed(1)}`).join(" ");
  const tint = points[points.length - 1] < 0 ? "var(--plan-pink)" : "var(--lime)";
  return (
    <svg viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" className="h-[72px] w-full" aria-hidden>
      <defs>
        <linearGradient id="deal-climb" x1="0" x2="0" y1="0" y2="1">
          <stop offset="0" stopColor={tint} stopOpacity="0.35" />
          <stop offset="1" stopColor={tint} stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d={`${line} L${w},${y(lo)} L0,${y(lo)} Z`} fill="url(#deal-climb)" />
      <path d={line} fill="none" stroke={tint} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" vectorEffect="non-scaling-stroke" />
    </svg>
  );
}

/**
 * Closed deals (the app's DealHistoryView): search, "Profit from deals" with the big figure and
 * one quiet line, the climb, the best deal, All / Buys / Sales / Trades, then each day's deals.
 * Click a deal for its page. No Saved for later here: it lives on the Deal tab.
 */
export function ClosedDealsDialog({ open, onOpenChange, deals, openId, onOpenId, onPhotos, onNotes }: { open: boolean; onOpenChange: (o: boolean) => void; deals: DealRecord[]; openId: string | null; onOpenId: (id: string | null) => void; onPhotos: (id: string, photos: string[]) => void; onNotes: (id: string, notes: string) => void }) {
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState<DealKind | null>(null);
  const shown = useMemo(() => deals.filter((d) => (filter === null || d.kind === filter) && matchesDealSearch(d, query)), [deals, query, filter]);
  const days = useMemo(() => {
    const map = new Map<string, DealRecord[]>();
    for (const d of shown) map.set(dayOf(d.at), [...(map.get(dayOf(d.at)) ?? []), d]);
    return [...map.entries()].sort((a, b) => (a[0] < b[0] ? 1 : -1));
  }, [shown]);
  const ahead = shown.reduce((s, d) => s + (recordAhead(d) ?? 0), 0);
  const cash = shown.reduce((s, d) => s + d.balance, 0);
  const best = shown.length > 1 ? bestDeal(shown) : null;
  const record = openId ? deals.find((d) => d.id === openId) ?? null : null;
  const what = filter ? `${KIND_NOUN[filter].toLowerCase()}s` : "deals";
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent hideClose className="h-[92dvh] bg-[#0b0b0c] sm:top-[4vh] sm:h-[88dvh] sm:max-w-[600px]">
        {record ? (
          <RecordDetail record={record} onBack={() => onOpenId(null)} onClose={() => onOpenChange(false)} onPhotos={(p) => onPhotos(record.id, p)} onNotes={(n) => onNotes(record.id, n)} />
        ) : (
          <div className="min-h-0 flex-1 overflow-y-auto px-4 pb-8 pt-5">
            <div className="flex items-center justify-between">
              <DialogTitle className="font-display text-[24px] tracking-[-0.02em]">Closed deals</DialogTitle>
              <RoundClose onClick={() => onOpenChange(false)} />
            </div>
            <DialogDescription className="sr-only">Every deal you&apos;ve closed here or in the app.</DialogDescription>
            {!deals.length ? (
              <div className="flex flex-col items-center px-6 pt-20 text-center">
                <span className="glass-stat flex size-[76px] items-center justify-center rounded-full text-[var(--lime)]">
                  <Banknote className="size-7" />
                </span>
                <p className="mt-4 font-display text-[24px] tracking-[-0.02em]">No closed deals yet</p>
                <p className="mt-1 max-w-[320px] text-[14px] text-muted">Every buy, sale and trade you close lands here, with what changed hands, your profit and your photos.</p>
              </div>
            ) : (
              <div className="mt-4 space-y-[22px]">
                <label className="relative block">
                  <Search className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-subtle" />
                  <input type="search" value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search cards, notes, buy, sale, trade" aria-label="Search closed deals" className="glass-stat h-11 w-full rounded-full pl-10 pr-4 text-[15px] outline-none placeholder:text-subtle focus:ring-1 focus:ring-white/25" />
                </label>
                <div>
                  <p className="text-[14px] text-muted">
                    {ahead < 0 ? "Loss from " : "Profit from "}
                    {what}
                  </p>
                  <p className={cn("tabular mt-1 font-display text-[52px] leading-none tracking-[-0.04em]", ahead < 0 ? "text-[var(--plan-pink)]" : "text-[var(--lime)]")}>{signedMoney(ahead)}</p>
                  <p className="tabular mt-2 text-[15px] text-muted">
                    {shown.length} deal{shown.length === 1 ? "" : "s"} · <span className={cash >= 0 ? "text-up" : "text-down"}>{signedMoney(cash)} cash</span>
                  </p>
                  <div className="mt-2">
                    <ProfitClimb points={profitClimb(shown)} />
                  </div>
                </div>
                {best && (
                  <button type="button" onClick={() => onOpenId(best.id)} className="glass-stat flex w-full items-center gap-3 rounded-[22px] px-4 py-3.5 text-left hover:bg-white/[0.06]">
                    <span className="min-w-0 flex-1">
                      <span className="tag-skew tag-lime">
                        <Star className="size-3 fill-current" /> Best deal
                      </span>
                      <span className="mt-1.5 block text-[15px] font-semibold">
                        {KIND_NOUN[best.kind]} · {new Date(best.at).toLocaleDateString("en-US", { month: "short", day: "numeric" })}
                      </span>
                      <span className="tabular block font-display text-[30px] leading-none tracking-[-0.04em] text-[var(--lime)]">{signedMoney(recordAhead(best))}</span>
                    </span>
                    <Fan lines={(best.lines ?? []).slice(0, 4)} />
                  </button>
                )}
                <div className="space-y-[18px]">
                  <div className="flex gap-1.5 overflow-x-auto">
                    {FILTERS.map((f) => (
                      <Chip key={f.label} on={filter === f.kind} onClick={() => setFilter(f.kind)}>
                        {f.label}
                      </Chip>
                    ))}
                  </div>
                  {!days.length && <p className="text-[14px] text-muted">{query.trim() ? `No deals match “${query.trim()}”.` : `No ${what} yet.`}</p>}
                  {days.map(([day, list]) => {
                    const t = dealDayTotals(list);
                    return (
                      <section key={day}>
                        <div className="flex items-baseline gap-2 pb-1">
                          <h3 className="font-display text-[22px] tracking-[-0.02em]">{dayTitle(day)}</h3>
                          <span className="text-[14px] text-subtle">{t.deals}</span>
                          {t.ahead !== null && <span className={cn("tabular ml-auto text-[15px] font-semibold", t.ahead >= 0 ? "text-up" : "text-down")}>{signedMoney(t.ahead)}</span>}
                        </div>
                        {list.map((r, i) => {
                          const note = recordNote(r);
                          return <DealListRow key={r.id} kind={r.kind} title={recordTitle(r)} line={`${PATH_TITLE[r.kind]} · ${cardsLabel(r.items)} · ${new Date(r.at).toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" })}`} amount={Math.abs(r.balance)} note={note.text} noteTone={note.tone} divider={i > 0} onClick={() => onOpenId(r.id)} />;
                        })}
                      </section>
                    );
                  })}
                </div>
              </div>
            )}
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

/** A few cards fanned like a hand. */
function Fan({ lines }: { lines: DealRecordLine[] }) {
  return (
    <span className="relative block h-[76px] w-[100px] shrink-0">
      {lines.map((l, i) => {
        const off = i - (lines.length - 1) / 2;
        return (
          <span key={i} className="absolute left-1/2 top-1 origin-bottom" style={{ transform: `translateX(calc(-50% + ${off * 17}px)) translateY(${Math.abs(off) * 4}px) rotate(${off * 9}deg)` }}>
            <ProductImage product={l.product} size="xs" className="h-[62px] w-[44px] rounded-[4px] shadow-lg shadow-black/50" />
          </span>
        );
      })}
    </span>
  );
}

/** A closed deal's page (the app's DealRecordDetail): the date, the same read-only card, what came in and went out (cash as a line), notes and photos. */
function RecordDetail({ record: r, onBack, onClose, onPhotos, onNotes }: { record: DealRecord; onBack: () => void; onClose: () => void; onPhotos: (p: string[]) => void; onNotes: (n: string) => void }) {
  const lines = r.lines ?? [];
  const section = (side: "in" | "out", cash: number | null) => {
    const rows = lines.filter((l) => l.side === side);
    if (!rows.length && cash === null) return null;
    const incoming = side === "in";
    const title = r.kind === "buy" ? (incoming ? "Bought" : "Paid") : r.kind === "sell" ? (incoming ? "Received" : "Sold") : incoming ? "Came in" : "Went out";
    const total = rows.length ? (incoming ? r.inValue : r.outValue) : (cash ?? 0);
    return (
      <section>
        <div className="flex items-baseline justify-between">
          <h3 className="font-display text-[22px] tracking-[-0.02em]">{title}</h3>
          <span className="tabular font-display text-[22px] tracking-[-0.02em]">{money(total)}</span>
        </div>
        <div className="mt-2.5 rounded-[18px] bg-surface ring-1 ring-inset ring-border">
          {rows.map((l, i) => (
            <div key={i} className={cn("flex items-center gap-3 px-3 py-2.5", (i > 0) && "border-t border-border")}>
              <ProductImage product={l.product} size="xs" className="h-14 w-10 shrink-0 rounded-[4px]" />
              <span className="min-w-0 flex-1">
                <span className="line-clamp-2 text-[14px] font-medium">{l.product.name}</span>
                <span className="tabular block truncate text-[12px] text-muted">
                  {l.qty} × {money(l.price)}
                  {l.untracked ? " · not tracked" : l.product.setName ? ` · ${l.product.setName}` : ""}
                </span>
              </span>
              <span className="tabular shrink-0 text-[15px] font-semibold">{money(l.price * l.qty)}</span>
            </div>
          ))}
          {cash !== null && (
            <div className={cn("flex items-center gap-3 px-3 py-2.5", rows.length > 0 && "border-t border-border")}>
              <span className="flex h-14 w-10 shrink-0 items-center justify-center rounded-[4px] bg-[color-mix(in_srgb,var(--lime)_12%,transparent)] text-[var(--lime)]">
                <Banknote className="size-4" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block text-[14px] font-medium">Cash</span>
                <span className="block text-[12px] text-muted">{incoming ? "They paid you" : "You paid them"}</span>
              </span>
              <span className="tabular shrink-0 text-[15px] font-semibold">{money(cash)}</span>
            </div>
          )}
        </div>
      </section>
    );
  };
  return (
    <div className="min-h-0 flex-1 overflow-y-auto px-4 pb-8 pt-5">
      <div className="flex items-center gap-2">
        <button type="button" onClick={onBack} aria-label="Back to closed deals" className="glass-stat flex size-9 items-center justify-center rounded-full hover:bg-white/[0.1]">
          <ChevronLeft className="size-4" />
        </button>
        <DialogTitle className="flex-1 text-center text-[16px] font-semibold">{KIND_NOUN[r.kind]}</DialogTitle>
        <RoundClose onClick={onClose} />
      </div>
      <DialogDescription className="sr-only">A closed deal</DialogDescription>
      <div className="mt-4 space-y-7">
        <div className="space-y-2.5">
          <p className="text-[13px] text-muted">{new Date(r.at).toLocaleString("en-US", { weekday: "long", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })}</p>
          <DealCard totals={recordTotals(r)} readOnly past />
        </div>
        {lines.length ? (
          <>
            {section("in", r.balance > 0.005 ? r.balance : null)}
            {section("out", r.balance < -0.005 ? -r.balance : null)}
          </>
        ) : (
          <p className="text-[13px] text-muted">
            Came in {money(r.inValue)} · went out {money(r.outValue)}. Item details weren&apos;t kept for deals closed before they were recorded.
          </p>
        )}
        <section>
          <h3 className="font-display text-[22px] tracking-[-0.02em]">Notes</h3>
          <RecordNotes key={r.id} notes={r.notes ?? ""} onSave={onNotes} />
        </section>
        <section>
          <h3 className="flex items-baseline gap-2.5 font-display text-[22px] tracking-[-0.02em]">
            Photos <span className="font-mono text-[12px] text-subtle">{r.photos?.length ?? 0}</span>
          </h3>
          <DealPhotos photos={r.photos ?? []} onChange={onPhotos} className="mt-3" />
        </section>
      </div>
    </div>
  );
}

/** A notes field that grows when focused (the open deal's and a closed deal's). */
export function NotesField({ value, onChange, placeholder, className, onCommit }: { value: string; onChange: (v: string) => void; placeholder?: string; className?: string; onCommit?: () => void }) {
  const [focused, setFocused] = useState(false);
  const tall = focused || value.includes("\n") || value.length > 60;
  return (
    <textarea
      value={value}
      rows={tall ? 4 : 1}
      placeholder={placeholder}
      aria-label="Notes"
      onFocus={() => setFocused(true)}
      onBlur={() => {
        setFocused(false);
        onCommit?.();
      }}
      onChange={(e) => onChange(e.target.value)}
      className={cn("block w-full resize-none rounded-2xl bg-surface px-3.5 py-2.5 text-[14px] leading-snug outline-none ring-1 ring-inset ring-border placeholder:text-subtle focus:ring-white/25", className)}
    />
  );
}

/** A closed deal's notes, edited in place and saved when you click away. */
function RecordNotes({ notes, onSave }: { notes: string; onSave: (notes: string) => void }) {
  const [text, setText] = useState(notes);
  return (
    <NotesField
      className="mt-3"
      value={text}
      onChange={setText}
      placeholder="Add a note"
      onCommit={() => {
        if (text.trim() !== notes.trim()) onSave(text);
      }}
    />
  );
}

/** Saved for later, all of them (View all): resume one (an open deal is saved first) or delete it. */
export function ParkedDialog({ open, onOpenChange, parked, balanceOf, onResume, onDelete }: { open: boolean; onOpenChange: (o: boolean) => void; parked: ParkedDeal[]; balanceOf: (p: ParkedDeal) => number; onResume: (p: ParkedDeal) => void; onDelete: (p: ParkedDeal) => void }) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent hideClose className="bg-[#161618] sm:max-w-[520px]">
        <div className="min-h-0 overflow-y-auto px-4 pb-6 pt-5">
          <div className="flex items-center justify-between">
            <DialogTitle className="font-display text-[22px] tracking-[-0.02em]">Saved for later</DialogTitle>
            <RoundClose onClick={() => onOpenChange(false)} />
          </div>
          <DialogDescription className="mt-1 text-[13px] text-muted">Deals you set aside to finish later, here or in the app.</DialogDescription>
          <div className="mt-3">
            {!parked.length && <p className="py-12 text-center text-[14px] text-muted">Nothing saved for later.</p>}
            {parked.map((p, i) => {
              const state = { ...EMPTY, ...p.state };
              const kind = dealKind(state.in.length, state.out.length);
              return (
                <DealListRow
                  key={p.id}
                  kind={kind}
                  title={p.name}
                  line={`${PATH_TITLE[kind]} · ${cardsLabel(state.in.length + state.out.length)} · ${new Date(p.savedAt).toLocaleString("en-US", { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })}`}
                  amount={Math.abs(balanceOf(p))}
                  note="Saved"
                  divider={i > 0}
                  onClick={() => onResume(p)}
                  trailing={<ParkedMenu name={p.name} onResume={() => onResume(p)} onDelete={() => onDelete(p)} />}
                />
              );
            })}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
