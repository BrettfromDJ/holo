"use client";

import { Clock, ExternalLink, Plus } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import { Field, MoneyInput, Stepper, parseMoney } from "@/components/flows/fields";
import { FormShell } from "@/components/flows/transaction-dialogs";
import { Hint } from "@/components/ui/tooltip";
import { ProductImage } from "@/components/product/product-image";
import { Delta } from "@/components/product/delta";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, SectionTitle } from "@/components/ui/card";
import { Dialog, DialogContent } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { daysBetween } from "@/lib/finance/dates";
import type { HoldingView } from "@/lib/finance/portfolio";
import { formatDate, money } from "@/lib/format";
import { certLookupUrl, GRADED_SOURCE, gradeDescriptor, gradedLadder, gradeLabel, GRADERS, isStaleValue, liquidityLabel, liquidityNote, liquidityOf, sampleSalesPerYear } from "@/lib/graded";
import { useStore } from "@/lib/store/collection-store";
import { useGradingCosts, useGradingSubmissions, useSlabBumpers, useSlabCerts, type GradingSubmission } from "@/lib/store/grading";
import { BUMPERS, bumperById, GLITTER_SPECKS } from "@/lib/bumpers";
import { holdingKey, priceKey, type Grade } from "@/lib/types";
import { cn } from "@/lib/utils";

/** A small neutral chip: "PSA 10". */
export function GradeChip({ grade, className }: { grade: Grade; className?: string }) {
  return (
    <span className={cn("inline-flex items-center gap-1 rounded-[5px] bg-surface-2 px-1.5 py-0.5 font-mono text-[11px] font-medium leading-none ring-1 ring-inset ring-border", className)}>
      <span className="text-muted">{grade.company}</span>
      <span className="text-foreground">{grade.grade}</span>
    </span>
  );
}

function multipleLabel(m: number) {
  return `${m >= 10 ? m.toFixed(0) : m.toFixed(1)}×`;
}

/** The raw (ungraded) market price for a holding's card. */
export function useRawPrice(productId: string, printing: string | null): number | null {
  const { data } = useStore();
  return data.prices[priceKey(productId, printing)]?.market ?? null;
}

/* ------------------------------ Product page ------------------------------ */

/** What this card sells for at common grades, next to its raw price. */
export function GradedPrices({ productId, printing, owned }: { productId: string; printing: string | null; owned: Grade[] }) {
  const raw = useRawPrice(productId, printing);
  const rows = gradedLadder(productId, raw);
  if (!rows.length) return null;
  const ownedLabels = new Set(owned.map(gradeLabel));
  const best = Math.max(...rows.map((r) => r.price));
  return (
    <Card className="mt-6 p-5 sm:p-6">
      <SectionTitle
        title="Graded prices"
        subtitle={`Raw ${money(raw)} · what slabs of this card sell for`}
        action={GRADED_SOURCE === "sample" ? <Badge variant="sample">Sample data</Badge> : undefined}
      />
      <ul className="divide-y divide-border">
        {rows.map((r) => (
          <li key={gradeLabel(r.grade)} className="grid grid-cols-[4.5rem_minmax(0,1fr)_auto_3.5rem] items-center gap-x-3 py-2.5 sm:grid-cols-[4.5rem_minmax(0,1fr)_auto_4rem_3.25rem]">
            <GradeChip grade={r.grade} className="justify-self-start" />
            <div className="h-1.5 overflow-hidden rounded-full bg-surface-2" aria-hidden>
              <div
                className="h-full rounded-full"
                style={{
                  width: `${(r.price / best) * 100}%`,
                  background: "linear-gradient(90deg, color-mix(in srgb, var(--foreground) 12%, transparent), color-mix(in srgb, var(--foreground) 55%, transparent))",
                }}
              />
            </div>
            <span className="tabular text-right text-[14px] font-semibold">
              {money(r.price)}
              {ownedLabels.has(gradeLabel(r.grade)) && <span className="ml-1.5 text-[11px] font-normal text-muted">yours</span>}
            </span>
            <SalesCell perYear={sampleSalesPerYear(productId, r.grade, raw)} />
            <span className="tabular hidden text-right font-mono text-[12px] text-muted sm:block">{multipleLabel(r.multiple)}</span>
          </li>
        ))}
      </ul>
      <p className="mt-3 text-[12px] text-subtle">Bars show how easy each grade is to sell. × is the multiple of the raw price.</p>
    </Card>
  );
}

/** Three rising bars: one for hard to sell, three for easy. */
export function LiquidityMeter({ perYear, className }: { perYear: number; className?: string }) {
  const level = liquidityOf(perYear);
  const filled = level === "often" ? 3 : level === "regular" ? 2 : 1;
  return (
    <span className={cn("inline-flex items-end gap-[3px]", className)} role="img" aria-label={liquidityLabel(perYear)}>
      {[0, 1, 2].map((i) => (
        <span key={i} className={cn("w-[4px] rounded-full", i < filled ? "bg-foreground/80" : "bg-foreground/15")} style={{ height: `${7 + i * 4}px` }} />
      ))}
    </span>
  );
}

/** How easy a grade is to sell, as a meter with the label on hover. */
export function SalesCell({ perYear, className }: { perYear: number; className?: string }) {
  return (
    <Hint content={liquidityNote(perYear)}>
      <span className={cn("flex justify-end", className)}>
        <LiquidityMeter perYear={perYear} />
      </span>
    </Hint>
  );
}

/** A graded holding on its product page: the slab, its value, and tiles for premium, sales and cert. */
/** `showBumper` adds the bumper control here; off when it sits under the page's slab photo instead. */
export function SlabCard({ h, actions, onRevalue, onCert, showBumper = true }: { h: HoldingView; actions: React.ReactNode; onRevalue: () => void; onCert: () => void; showBumper?: boolean }) {
  const { today } = useStore();
  const { certs } = useSlabCerts();
  const raw = useRawPrice(h.identity.productId, h.identity.printing);
  const grade = h.identity.grade;
  if (!grade) return null;
  const cert = certs[h.key];
  const manual = h.priceOrigin === "manual";
  const stale = manual && isStaleValue(h.priceUpdatedAt, today);
  const sales = raw !== null ? sampleSalesPerYear(h.identity.productId, grade, raw) : null;

  return (
    <div className="flex gap-4 sm:gap-5">
      <ProductImage product={h.product} grade={grade} slabKey={h.key} size="md" className="h-[124px] w-[78px] shrink-0 sm:h-[176px] sm:w-[110px]" />
      <div className="min-w-0 flex-1">
        <div className="flex items-start justify-between gap-2">
          <div className="min-w-0">
            <p className="flex items-center gap-2">
              <span className="font-mono text-[11px] font-medium uppercase tracking-[0.06em] text-subtle">
                {h.quantity > 1 ? `${h.quantity} × ` : ""}
                {gradeLabel(grade)} · {gradeDescriptor(grade)}
              </span>
            </p>
            <p className="tabular mt-1 text-[26px] font-semibold leading-none tracking-[-0.02em]">{money(h.value)}</p>
            <p className="tabular mt-1.5 text-[12px] text-muted">
              <Delta value={h.unrealized} ratio={h.unrealizedPct} className="text-[12px]" /> <span className="text-subtle">on {money(h.costBasis)} cost</span>
            </p>
          </div>
          <div className="flex shrink-0 items-center gap-1">{actions}</div>
        </div>

        <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-3">
          <Tile label="Premium">
            {raw !== null && h.price !== null ? (
              <>
                <span className="font-mono text-[17px] font-semibold">{multipleLabel(h.price / raw)}</span>
                <span className="mt-0.5 block text-[11px] text-subtle">over raw {money(raw)}</span>
              </>
            ) : (
              <span className="text-muted">—</span>
            )}
          </Tile>
          <Tile label="Sells">
            {sales !== null ? (
              <Hint content={liquidityNote(sales)}>
                <span className="flex items-center gap-2.5">
                  <span className="text-[15px] font-semibold">{liquidityLabel(sales)}</span>
                  <LiquidityMeter perYear={sales} />
                </span>
              </Hint>
            ) : (
              <span className="text-muted">—</span>
            )}
          </Tile>
          <Tile label="Cert" className="col-span-2 sm:col-span-1">
            {cert ? (
              <>
                <span className="block truncate font-mono text-[15px] font-semibold">{cert}</span>
                <a href={certLookupUrl(grade.company, cert)} target="_blank" rel="noreferrer" className="mt-0.5 inline-flex items-center gap-0.5 text-[11px] font-medium text-muted hover:text-foreground">
                  Verify on {grade.company} <ExternalLink className="size-3" />
                </a>
              </>
            ) : (
              <button type="button" onClick={onCert} className="flex items-center gap-1 text-[13px] font-medium text-muted hover:text-foreground">
                <Plus className="size-3.5" /> Add cert number
              </button>
            )}
          </Tile>
        </div>

        <div className="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1.5 text-[12px] text-subtle">
          {showBumper && <BumperButton h={h} />}
          <span>{manual ? "Your value" : GRADED_SOURCE === "sample" ? "Graded market · sample" : "Graded market"}</span>
          <span>
            {h.lots.length} lot{h.lots.length === 1 ? "" : "s"} · avg {money(h.avgCost)}
          </span>
          {stale && (
            <button type="button" onClick={onRevalue} className="inline-flex items-center gap-1.5 whitespace-nowrap rounded-full bg-surface-2 px-2.5 py-1 font-medium text-foreground/85 ring-1 ring-inset ring-border hover:bg-surface-3">
              <Clock className="size-3" /> Value {daysBetween(h.priceUpdatedAt!, today)}d old · Update
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

/** Opens the bumper picker; shows the current bumper as a swatch. */
export function BumperButton({ h, className }: { h: HoldingView; className?: string }) {
  const { bumpers } = useSlabBumpers();
  const [open, setOpen] = useState(false);
  const current = bumperById(bumpers[h.key]);
  return (
    <>
      <button type="button" onClick={() => setOpen(true)} className={cn("inline-flex items-center gap-1.5 whitespace-nowrap rounded-full bg-surface-2 py-1 pl-1 pr-2.5 font-medium text-foreground/85 ring-1 ring-inset ring-border hover:bg-surface-3", className)}>
        <span className="size-4 rounded-full ring-1 ring-inset ring-white/20" style={{ background: current?.background ?? "transparent" }}>
          {!current && <Plus className="m-0.5 size-3 text-muted" />}
        </span>
        {current ? current.name : "Add bumper"}
      </button>
      <BumperDialog h={h} open={open} onOpenChange={setOpen} />
    </>
  );
}

/** Pick a bumper guard for a slab, with a live preview. */
export function BumperDialog({ h, open, onOpenChange }: { h: HoldingView; open: boolean; onOpenChange: (o: boolean) => void }) {
  const { bumpers, setBumper } = useSlabBumpers();
  const [pick, setPick] = useState<string | null>(null);
  // Start from the saved bumper each time the picker opens (not on every render).
  useEffect(() => {
    if (open) setPick(bumpers[h.key] ?? null);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- only when opened
  }, [open, h.key]);
  const preview = bumperById(pick);
  const group = (kind: "glitter" | "solid", title: string) => (
    <div>
      <p className="mb-2 font-mono text-[10px] font-medium uppercase tracking-[0.06em] text-subtle">{title}</p>
      <div className="grid grid-cols-6 gap-2">
        {BUMPERS.filter((b) => b.kind === kind).map((b) => (
          <Hint key={b.id} content={b.name}>
            <button
              type="button"
              aria-label={b.name}
              aria-pressed={pick === b.id}
              onClick={() => setPick(b.id)}
              className={cn("aspect-square rounded-xl ring-1 ring-inset ring-white/15 transition-transform hover:scale-105", pick === b.id && "ring-2 ring-foreground ring-offset-2 ring-offset-[var(--surface)]")}
              style={{ background: b.kind === "glitter" ? `${GLITTER_SPECKS} 0 0 / 34px 34px, ${b.background}` : b.background }}
            />
          </Hint>
        ))}
      </div>
    </div>
  );
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[520px]">
        <FormShell
          title="Bumper"
          description="Snap a bumper guard around this slab. It shows everywhere the slab appears."
          onSubmit={(e) => {
            e.preventDefault();
            setBumper(h.key, pick);
            toast.success(pick ? `${bumperById(pick)?.name} bumper on` : "Bumper removed");
            onOpenChange(false);
          }}
          footer={
            <Button type="submit" variant="primary" size="lg" className="w-full">
              {pick ? "Save bumper" : "No bumper"}
            </Button>
          }
        >
          <div className="flex justify-center rounded-2xl bg-surface-2/60 py-5">
            <ProductImage product={h.product} grade={h.identity.grade} bumper={preview} size="md" className="h-[220px] w-[140px]" />
          </div>
          {group("glitter", "Glitter")}
          {group("solid", "Solid")}
          <button type="button" onClick={() => setPick(null)} className={cn("text-[13px] font-medium", pick ? "text-muted hover:text-foreground" : "text-foreground")}>
            {pick ? "Remove bumper" : "No bumper selected"}
          </button>
        </FormShell>
      </DialogContent>
    </Dialog>
  );
}

function Tile({ label, children, className }: { label: string; children: React.ReactNode; className?: string }) {
  return (
    <div className={cn("min-w-0 rounded-xl bg-surface-2/60 px-3 py-2.5 ring-1 ring-inset ring-border", className)}>
      <p className="font-mono text-[10px] font-medium uppercase tracking-[0.06em] text-subtle">{label}</p>
      <div className="tabular mt-1 leading-tight">{children}</div>
    </div>
  );
}

/* --------------------------------- Dialogs -------------------------------- */

export function CertDialog({ holding, open, onOpenChange }: { holding: HoldingView; open: boolean; onOpenChange: (o: boolean) => void }) {
  const { certs, setCert } = useSlabCerts();
  const [value, setValue] = useState("");
  useEffect(() => {
    // Only when opened: re-running on every render would wipe what's being typed.
    if (open) setValue(certs[holding.key] ?? "");
    // eslint-disable-next-line react-hooks/exhaustive-deps -- only when opened
  }, [open, holding.key]);
  const grade = holding.identity.grade;
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <FormShell
          title="Cert number"
          description={`The certification number printed on the ${grade?.company ?? ""} label. Used to verify the slab.`}
          onSubmit={(e) => {
            e.preventDefault();
            setCert(holding.key, value);
            toast.success(value.trim() ? "Cert number saved" : "Cert number removed");
            onOpenChange(false);
          }}
          footer={
            <Button type="submit" variant="primary" size="lg" className="w-full">
              Save
            </Button>
          }
        >
          <Field label="Cert number" htmlFor="cert-number">
            <Input id="cert-number" value={value} onChange={(e) => setValue(e.target.value.slice(0, 20))} inputMode="numeric" autoFocus />
          </Field>
        </FormShell>
      </DialogContent>
    </Dialog>
  );
}

const SERVICES = ["Value", "Regular", "Express", "Super Express"];

/** Record raw copies of a card as sent off for grading. */
export function SendToGraderDialog({ holding, open, onOpenChange }: { holding: HoldingView; open: boolean; onOpenChange: (o: boolean) => void }) {
  const { today } = useStore();
  const { costs } = useGradingCosts();
  const { send } = useGradingSubmissions();
  const [company, setCompany] = useState("PSA");
  const [service, setService] = useState("Value");
  const [qty, setQty] = useState(1);
  const [fee, setFee] = useState("");
  const [shipping, setShipping] = useState("");
  const [date, setDate] = useState(today);
  useEffect(() => {
    if (!open) return;
    setQty(1);
    setFee(costs.fee.toFixed(2));
    setShipping(costs.shipping.toFixed(2));
    setDate(today);
  }, [open, costs, today]);
  const f = parseMoney(fee) ?? 0;
  const sh = parseMoney(shipping) ?? 0;
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <FormShell
          title="Send for grading"
          description={`${holding.product?.name ?? "This card"} stays in your collection as a raw card until it comes back.`}
          onSubmit={(e) => {
            e.preventDefault();
            send({ productId: holding.identity.productId, printing: holding.identity.printing, condition: holding.identity.condition, company, service, quantity: qty, fee: f, shipping: sh, sentOn: date });
            toast.success(`Marked as sent to ${company}`, { description: "Track it on the Grading page." });
            onOpenChange(false);
          }}
          footer={
            <Button type="submit" variant="primary" size="lg" className="w-full" disabled={date > today}>
              Mark as sent
            </Button>
          }
        >
          <div className="grid grid-cols-2 gap-3">
            <Field label="Company">
              <Select value={company} onValueChange={setCompany}>
                <SelectTrigger aria-label="Grading company">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {GRADERS.map((g) => (
                    <SelectItem key={g} value={g}>
                      {g}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field label="Service">
              <Select value={service} onValueChange={setService}>
                <SelectTrigger aria-label="Service level">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {SERVICES.map((s) => (
                    <SelectItem key={s} value={s}>
                      {s}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
          </div>
          {holding.quantity > 1 && (
            <Field label="Copies">
              <Stepper value={qty} onChange={setQty} max={holding.quantity} label="Copies" />
            </Field>
          )}
          <div className="grid grid-cols-2 gap-3">
            <Field label="Fee per card" htmlFor="grade-fee">
              <MoneyInput id="grade-fee" value={fee} onChange={setFee} />
            </Field>
            <Field label="Shipping per card" htmlFor="grade-shipping">
              <MoneyInput id="grade-shipping" value={shipping} onChange={setShipping} />
            </Field>
          </div>
          <Field label="Sent on" htmlFor="grade-date">
            <Input id="grade-date" type="date" value={date} max={today} onChange={(e) => setDate(e.target.value)} />
          </Field>
        </FormShell>
      </DialogContent>
    </Dialog>
  );
}

/** A submission came back: enter the grade and turn the raw card into a slab. */
export function ReturnDialog({ submission, holding, open, onOpenChange }: { submission: GradingSubmission; holding: HoldingView | undefined; open: boolean; onOpenChange: (o: boolean) => void }) {
  const { today, data } = useStore();
  const { complete } = useGradingSubmissions();
  const [grade, setGrade] = useState("10");
  const [date, setDate] = useState(today);
  const [saving, setSaving] = useState(false);
  useEffect(() => {
    if (open) setDate(today);
  }, [open, today]);
  const product = data.products[submission.productId];
  const valid = grade.trim() !== "" && date <= today && date >= submission.sentOn;
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <FormShell
          title="Back from grading"
          description={`${product?.name ?? "This card"} becomes a ${submission.company} slab. Its cost carries over, plus ${money(submission.fee + submission.shipping)} per card in grading costs.`}
          onSubmit={async (e) => {
            e.preventDefault();
            if (!valid) return;
            setSaving(true);
            try {
              await complete(submission, { company: submission.company, grade: grade.trim() }, holding, date);
              toast.success(`${submission.company} ${grade.trim()} added to your collection`);
              onOpenChange(false);
            } catch (err) {
              toast.error("Couldn't save", { description: err instanceof Error ? err.message : undefined });
            } finally {
              setSaving(false);
            }
          }}
          footer={
            <Button type="submit" variant="primary" size="lg" className="w-full" disabled={!valid || saving}>
              Add the slab
            </Button>
          }
        >
          <div className="grid grid-cols-2 gap-3">
            <Field label={`${submission.company} grade`} htmlFor="return-grade">
              <Input id="return-grade" value={grade} onChange={(e) => setGrade(e.target.value.slice(0, 6))} inputMode="decimal" autoFocus />
            </Field>
            <Field label="Returned on" htmlFor="return-date">
              <Input id="return-date" type="date" value={date} min={submission.sentOn} max={today} onChange={(e) => setDate(e.target.value)} />
            </Field>
          </div>
          {!holding && <p className="text-[12px] text-muted">The raw card is no longer in your collection, so the slab is added at the grading cost only.</p>}
        </FormShell>
      </DialogContent>
    </Dialog>
  );
}

/** Raw holdings currently at a grader, keyed by holding key. */
export function useAtGrader() {
  const { submissions } = useGradingSubmissions();
  return useMemo(() => {
    const m = new Map<string, number>();
    for (const s of submissions) {
      if (s.status !== "sent") continue;
      const key = holdingKey({ productId: s.productId, printing: s.printing, condition: s.condition, grade: null });
      m.set(key, (m.get(key) ?? 0) + s.quantity);
    }
    return m;
  }, [submissions]);
}

export function formatSent(s: GradingSubmission, today: string) {
  const days = daysBetween(s.sentOn, today);
  return `${s.company} ${s.service} · sent ${formatDate(s.sentOn)}${days > 0 ? ` · ${days} day${days === 1 ? "" : "s"} ago` : ""}`;
}
