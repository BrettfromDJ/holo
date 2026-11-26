"use client";

import { ArrowDownToLine, ArrowLeftRight, ArrowUpFromLine, ChevronRight, MoreHorizontal, Play, Trash2 } from "lucide-react";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { dealKind, recordAhead, type DealKind } from "@/lib/deal";
import { money, signedMoney } from "@/lib/format";
import { cn } from "@/lib/utils";
import { alpha } from "./deal-card";
import { EMPTY, KIND_COLOR, PATH_TITLE, cardsLabel, recordTitle, type DealPath, type DealRecord, type ParkedDeal } from "./deal-types";

export function KindIcon({ kind, className }: { kind: DealKind; className?: string }) {
  const Icon = kind === "buy" ? ArrowDownToLine : kind === "sell" ? ArrowUpFromLine : ArrowLeftRight;
  return <Icon className={className} strokeWidth={2.4} />;
}

/** "Today", "Yesterday" or "Nov 24". */
export function whenLabel(at: string) {
  const d = new Date(at);
  const day = (x: Date) => x.toLocaleDateString("en-CA");
  const now = new Date();
  const yesterday = new Date(now.getTime() - 86_400_000);
  if (day(d) === day(now)) return "Today";
  if (day(d) === day(yesterday)) return "Yesterday";
  return d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

/** A closed deal's note: "+$33.61 profit", "−$5.00 loss", "Even", or "Completed" when unknown. */
export function recordNote(r: DealRecord): { text: string; tone: string | null } {
  const a = recordAhead(r);
  if (a === null) return { text: "Completed", tone: null };
  if (Math.abs(a) < 0.005) return { text: "Even", tone: "text-muted" };
  return { text: `${signedMoney(a)} ${a > 0 ? "profit" : "loss"}`, tone: a > 0 ? "text-up" : "text-down" };
}

/** A parked or closed deal (the app's DealListRow): its kind's icon on a soft tile, name, one line, the cash and a quiet note. */
export function DealListRow({ kind, title, line, amount, note, noteTone, divider, onClick, trailing }: { kind: DealKind; title: string; line: string; amount: number; note: string; noteTone?: string | null; divider?: boolean; onClick: () => void; trailing?: React.ReactNode }) {
  const tint = KIND_COLOR[kind].tint;
  const word = PATH_TITLE[kind];
  return (
    <div className="relative flex items-center">
      {divider && <span aria-hidden className="absolute left-[54px] right-0 top-0 h-px bg-border" />}
      <button type="button" onClick={onClick} className="flex min-w-0 flex-1 items-center gap-3.5 py-3 text-left">
        <span className="flex size-10 shrink-0 items-center justify-center rounded-[11px]" style={{ background: alpha(tint, 0.16), color: tint }}>
          <KindIcon kind={kind} className="size-[15px]" />
        </span>
        <span className="min-w-0 flex-1">
          <span className="block truncate text-[16px] font-medium">{title}</span>
          <span className="block truncate text-[13px] text-muted">
            {line.startsWith(word) ? (
              <>
                <span style={{ color: tint }}>{word}</span>
                {line.slice(word.length)}
              </>
            ) : (
              line
            )}
          </span>
        </span>
        <span className="tabular shrink-0 text-right">
          <span className="block text-[16px] font-semibold">{money(amount)}</span>
          <span className={cn("block text-[13px]", noteTone ? cn("font-semibold", noteTone) : "text-subtle")}>{note}</span>
        </span>
      </button>
      {trailing}
    </div>
  );
}

/** A saved deal's ⋯: Resume deal, Delete deal (so deleting never hides). */
export function ParkedMenu({ name, onResume, onDelete }: { name: string; onResume: () => void; onDelete: () => void }) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger aria-label={`${name} actions`} className="-mr-2 ml-1 flex size-9 shrink-0 items-center justify-center rounded-full text-muted hover:bg-white/[0.06] hover:text-foreground">
        <MoreHorizontal className="size-4" />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem onSelect={onResume}>
          <Play className="size-4" /> Resume deal
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem onSelect={onDelete} className="text-[var(--plan-pink)] focus:text-[var(--plan-pink)]">
          <Trash2 className="size-4" /> Delete deal
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

/** "What's the deal?": Buy, Sell or Trade, then your saved and closed deals (the app's DealStartPage). */
export function DealStartPage({
  parked,
  log,
  parkedBalance,
  onPick,
  onResume,
  onDeleteParked,
  onParkedAll,
  onHistory,
  onRecord,
}: {
  parked: ParkedDeal[];
  log: DealRecord[];
  /** A parked deal's cash, at its rates. */
  parkedBalance: (p: ParkedDeal) => number;
  onPick: (k: DealPath) => void;
  onResume: (p: ParkedDeal) => void;
  onDeleteParked: (p: ParkedDeal) => void;
  onParkedAll: () => void;
  onHistory: () => void;
  onRecord: (r: DealRecord) => void;
}) {
  const choice = (k: DealPath, title: string, line: string) => {
    const c = KIND_COLOR[k];
    return (
      <button
        key={k}
        type="button"
        onClick={() => onPick(k)}
        className="glass-stat flex w-full items-center gap-3.5 rounded-[20px] p-3.5 text-left transition-transform active:scale-[0.99]"
        style={{ backgroundImage: `linear-gradient(90deg, ${alpha(c.tint, 0.22)}, ${alpha(c.tint, 0.05)})`, borderColor: alpha(c.tint, 0.4) }}
      >
        <span className="flex size-[46px] shrink-0 items-center justify-center rounded-[13px]" style={{ background: `linear-gradient(180deg, ${c.tint}, ${c.deep})`, color: c.onTint }}>
          <KindIcon kind={k} className="size-[18px]" />
        </span>
        <span className="min-w-0 flex-1">
          <span className="block text-[17px] font-semibold">{title}</span>
          <span className="block text-[13px] text-muted">{line}</span>
        </span>
        <ChevronRight className="size-4 shrink-0" strokeWidth={2.6} style={{ color: c.tint }} />
      </button>
    );
  };
  const list = (title: string, count: number, onAll: () => void, rows: React.ReactNode) => (
    <section>
      <div className="flex items-baseline gap-2">
        <h2 className="font-display text-[20px] leading-tight tracking-[-0.02em]">{title}</h2>
        <span className="text-[14px] text-subtle">{count}</span>
        <button type="button" onClick={onAll} className="ml-auto text-[14px] font-medium text-muted hover:text-foreground">
          View all
        </button>
      </div>
      <div className="mt-2">{rows}</div>
    </section>
  );
  return (
    <div className="mx-auto max-w-[640px] space-y-[30px]">
      <div className="space-y-[18px]">
        <div className="space-y-1.5">
          <p className="font-mono text-[11px] font-medium uppercase tracking-[0.14em] text-muted">New deal</p>
          <h1 className="text-balance font-display text-[32px] leading-none tracking-[-0.03em]">What&apos;s the deal?</h1>
          <p className="text-[15px] text-muted">Choose what you&apos;re doing today.</p>
        </div>
        <div className="space-y-2.5">
          {choice("buy", "Buy cards", "Pay for cards at your rate.")}
          {choice("sell", "Sell cards", "Price out cards for a buyer.")}
          {choice("trade", "Trade cards", "Swap cards and balance the difference.")}
        </div>
      </div>
      {parked.length > 0 &&
        list(
          "Saved for later",
          parked.length,
          onParkedAll,
          parked.slice(0, 3).map((p, i) => {
            const state = { ...EMPTY, ...p.state };
            const kind = dealKind(state.in.length, state.out.length);
            return (
              <DealListRow
                key={p.id}
                kind={kind}
                title={p.name}
                line={`${PATH_TITLE[kind]} · ${cardsLabel(state.in.length + state.out.length)}`}
                amount={Math.abs(parkedBalance(p))}
                note="Saved"
                divider={i > 0}
                onClick={() => onResume(p)}
                trailing={<ParkedMenu name={p.name} onResume={() => onResume(p)} onDelete={() => onDeleteParked(p)} />}
              />
            );
          }),
        )}
      {log.length > 0 &&
        list(
          "Closed deals",
          log.length,
          onHistory,
          log.slice(0, 3).map((r, i) => {
            const note = recordNote(r);
            return <DealListRow key={r.id} kind={r.kind} title={recordTitle(r)} line={`${PATH_TITLE[r.kind]} · ${cardsLabel(r.items)} · ${whenLabel(r.at)}`} amount={Math.abs(r.balance)} note={note.text} noteTone={note.tone} divider={i > 0} onClick={() => onRecord(r)} />;
          }),
        )}
    </div>
  );
}
