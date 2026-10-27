"use client";

import { Check, X } from "lucide-react";
import Link from "next/link";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { useStore } from "@/lib/store/collection-store";
import { useSyncedState } from "@/lib/store/synced-state";
import { cn } from "@/lib/utils";

interface Progress {
  dismissed?: boolean;
  explored?: boolean;
}
const NONE: Progress = {};

/** Checklist progress, synced to the account when signed in. */
export function useGettingStarted() {
  return useSyncedState<Progress>("getting-started", NONE);
}

/**
 * First-run checklist for a personal collection. Shows until every step is
 * done or it's dismissed.
 */
export function GettingStarted({ className }: { className?: string }) {
  const { mode, data, repoKind, integrations, openAdd, savePreferences } = useStore();
  const [progress, setProgress, ready] = useGettingStarted();
  const [budgetDraft, setBudgetDraft] = useState<string | null>(null);
  const explored = Boolean(progress.explored);

  if (mode === "demo" || !ready || progress.dismissed) return null;

  const steps = [
    { key: "add", title: "Add your first card or sealed product", done: data.transactions.length > 0, action: <Button size="sm" variant="primary" onClick={() => openAdd()}>Add</Button> },
    { key: "explore", title: "Browse every set in Explore", done: explored, action: <Button size="sm" variant="secondary" asChild><Link href="/explore">Explore</Link></Button> },
    { key: "watch", title: "Watch something you want to buy", done: data.watchlist.length > 0, action: <Button size="sm" variant="secondary" onClick={() => openAdd({ watch: true })}>Watch</Button> },
    {
      key: "budget",
      title: "Set a monthly spending budget",
      done: data.preferences.monthlyBudget != null,
      action:
        budgetDraft === null ? (
          <Button size="sm" variant="secondary" onClick={() => setBudgetDraft("")}>
            Set
          </Button>
        ) : (
          <form
            className="flex items-center gap-1.5"
            onSubmit={(e) => {
              e.preventDefault();
              const v = Number(budgetDraft.replace(/[^0-9.]/g, ""));
              if (!v) return;
              savePreferences({ monthlyBudget: Math.round(v * 100) / 100 }).catch((err: Error) => toast.error("Budget saved in this browser only", { description: err.message }));
              setBudgetDraft(null);
            }}
          >
            <input autoFocus inputMode="decimal" value={budgetDraft} onChange={(e) => setBudgetDraft(e.target.value)} placeholder="$500" aria-label="Monthly budget" className="tabular h-8 w-24 rounded-full bg-surface-2 px-3 text-[13px] outline-none focus:bg-surface-3" />
            <Button type="submit" size="sm" variant="primary">
              Save
            </Button>
          </form>
        ),
    },
    ...(integrations.supabase
      ? [{ key: "sync", title: "Sign in to sync across your devices", done: repoKind === "cloud", action: <Button size="sm" variant="secondary" asChild><Link href="/login">Sign in</Link></Button> }]
      : []),
  ];
  const done = steps.filter((s) => s.done).length;
  if (done === steps.length) return null;

  return (
    <section aria-label="Getting started" className={cn("rounded-[var(--radius-card)] border border-border bg-surface p-5 sm:p-6", className)}>
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="text-[12px] font-semibold uppercase tracking-[0.12em] text-muted">Getting started</p>
          <p className="tabular mt-1 text-[15px] font-medium">
            {done} of {steps.length} done
          </p>
        </div>
        <button
          aria-label="Hide getting started"
          onClick={() => setProgress((p) => ({ ...p, dismissed: true }))}
          className="rounded-full p-1.5 text-subtle hover:bg-surface-2 hover:text-foreground"
        >
          <X className="size-4" />
        </button>
      </div>
      <div className="mt-3 h-1 overflow-hidden rounded-full bg-surface-2">
        <div className="h-full rounded-full bg-foreground transition-[width] duration-500" style={{ width: `${(done / steps.length) * 100}%` }} />
      </div>
      <ul className="mt-4 divide-y divide-border">
        {steps.map((s) => (
          <li key={s.key} className="flex min-h-[52px] items-center gap-3 py-2">
            <span className={cn("flex size-6 shrink-0 items-center justify-center rounded-full border", s.done ? "border-transparent bg-foreground text-background" : "border-border-strong")}>
              {s.done && <Check className="size-3.5" strokeWidth={3} />}
            </span>
            <span className={cn("min-w-0 flex-1 text-[14px]", s.done && "text-muted line-through decoration-subtle")}>{s.title}</span>
            {!s.done && s.action}
          </li>
        ))}
      </ul>
    </section>
  );
}
