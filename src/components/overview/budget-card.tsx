"use client";

import { Pencil, Wallet } from "lucide-react";
import { useMemo, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { budgetStatus } from "@/lib/budget";
import { money } from "@/lib/format";
import { useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";

/** This month's spending against an optional monthly budget, editable in place. */
export function BudgetCard() {
  const { data, today, savePreferences } = useStore();
  const budget = data.preferences.monthlyBudget ?? null;
  const status = useMemo(() => budgetStatus(data.transactions, today, budget), [data.transactions, today, budget]);
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState("");
  const monthName = new Date(`${status.month}-01T00:00:00Z`).toLocaleString("en-US", { month: "long", timeZone: "UTC" });

  const save = async (value: number | null) => {
    setEditing(false);
    try {
      await savePreferences({ monthlyBudget: value });
      toast(value === null ? "Budget removed" : `Monthly budget set to ${money(value)}`);
    } catch (e) {
      toast.error("Budget saved in this browser only", { description: (e as Error).message });
    }
  };

  const over = status.remaining !== null && status.remaining < 0;
  const near = !over && status.used !== null && status.used >= 0.85;
  const tone = over ? "var(--down)" : near ? "#f5b544" : "var(--foreground)";

  return (
    <section aria-label="Monthly budget" className="hype-surface mt-3 rounded-[var(--radius-card)] border border-border bg-surface px-5 py-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex min-w-0 items-center gap-3">
          <span className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-surface-2">
            <Wallet className="size-4 text-muted" />
          </span>
          <div className="min-w-0">
            <p className="text-[12px] font-medium text-muted">Spent in {monthName}</p>
            <p className="tabular text-[15px] font-semibold">
              {money(status.spent)}
              {budget !== null && <span className="font-normal text-muted"> of {money(budget)}</span>}
            </p>
          </div>
        </div>

        {editing ? (
          <form
            className="flex items-center gap-2"
            onSubmit={(e) => {
              e.preventDefault();
              const v = Number(draft.replace(/[^0-9.]/g, ""));
              void save(draft.trim() === "" || !v ? null : Math.round(v * 100) / 100);
            }}
          >
            <span className="relative">
              <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[13px] text-subtle">$</span>
              <input
                autoFocus
                inputMode="decimal"
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
                placeholder="500"
                aria-label="Monthly budget"
                className="tabular h-9 w-28 rounded-full bg-surface-2 pl-6 pr-3 text-[14px] outline-none focus:bg-surface-3"
              />
            </span>
            <Button type="submit" size="sm" variant="primary">
              Save
            </Button>
            {budget !== null && (
              <Button type="button" size="sm" variant="ghost" onClick={() => void save(null)}>
                Remove
              </Button>
            )}
          </form>
        ) : (
          <div className="flex items-center gap-3 text-right">
            {budget !== null && (
              <p className="tabular text-[13px] text-muted">
                <span className={cn("font-medium", over ? "text-down" : near ? "text-[#f5b544]" : "text-foreground")}>{money(Math.abs(status.remaining!))}</span>
                {over ? " over budget" : " left"}
              </p>
            )}
            <Button
              size="sm"
              variant="secondary"
              onClick={() => {
                setDraft(budget !== null ? String(budget) : "");
                setEditing(true);
              }}
            >
              {budget !== null ? <Pencil /> : null}
              {budget !== null ? "Edit" : "Set a monthly budget"}
            </Button>
          </div>
        )}
      </div>

      {budget !== null && (
        <>
          <div className="mt-3 h-1.5 overflow-hidden rounded-full bg-surface-2">
            <div className="h-full origin-left animate-grow-x rounded-full" style={{ width: `${Math.min(1, status.used ?? 0) * 100}%`, background: tone }} />
          </div>
          {!over && status.spent > 0 && status.projected > budget && (
            <p className="tabular mt-2 text-[12px] text-subtle">At this pace you&apos;ll spend about {money(status.projected)} this month.</p>
          )}
        </>
      )}
    </section>
  );
}
