"use client";

import { ExternalLink } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import { Field, MoneyInput, Stepper, parseMoney } from "@/components/flows/fields";
import { FormShell } from "@/components/flows/transaction-dialogs";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, SectionTitle } from "@/components/ui/card";
import { Dialog, DialogContent } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { daysBetween } from "@/lib/finance/dates";
import type { HoldingView } from "@/lib/finance/portfolio";
import { formatDate, money } from "@/lib/format";
import { certLookupUrl, GRADED_SOURCE, gradedLadder, gradeLabel, GRADERS, isStaleValue } from "@/lib/graded";
import { useStore } from "@/lib/store/collection-store";
import { useGradingCosts, useGradingSubmissions, useSlabCerts, type GradingSubmission } from "@/lib/store/grading";
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
          <li key={gradeLabel(r.grade)} className="grid grid-cols-[4.5rem_minmax(0,1fr)_auto_3.25rem] items-center gap-3 py-2.5">
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
            <span className="tabular text-right font-mono text-[12px] text-muted">{multipleLabel(r.multiple)}</span>
          </li>
        ))}
      </ul>
      <p className="mt-3 text-[12px] text-subtle">× is the multiple of the raw price.</p>
    </Card>
  );
}

/** Extra lines under a graded holding: premium over raw, cert, and a stale-value nudge. */
export function SlabDetails({ h, onRevalue, onCert }: { h: HoldingView; onRevalue: () => void; onCert: () => void }) {
  const { today } = useStore();
  const { certs } = useSlabCerts();
  const raw = useRawPrice(h.identity.productId, h.identity.printing);
  const grade = h.identity.grade;
  if (!grade) return null;
  const cert = certs[h.key];
  const manual = h.priceOrigin === "manual";
  const stale = manual && isStaleValue(h.priceUpdatedAt, today);
  return (
    <div className="mt-1 space-y-1 text-[12px] text-muted">
      <p className="tabular">
        {manual ? "Your value" : GRADED_SOURCE === "sample" ? "Graded market (sample)" : "Graded market"} {money(h.price)}
        {raw !== null && h.price !== null && (
          <>
            {" · "}raw {money(raw)} · <span className="font-mono text-foreground/80">{multipleLabel(h.price / raw)}</span> premium
          </>
        )}
      </p>
      {stale && (
        <p>
          Your value is {daysBetween(h.priceUpdatedAt!, today)} days old.{" "}
          <button type="button" onClick={onRevalue} className="font-medium text-foreground underline-offset-2 hover:underline">
            Update it
          </button>
        </p>
      )}
      <p>
        {cert ? (
          <>
            Cert <span className="font-mono text-foreground/80">{cert}</span> ·{" "}
            <a href={certLookupUrl(grade.company, cert)} target="_blank" rel="noreferrer" className="inline-flex items-center gap-0.5 font-medium text-foreground underline-offset-2 hover:underline">
              Verify on {grade.company} <ExternalLink className="size-3" />
            </a>
          </>
        ) : (
          <button type="button" onClick={onCert} className="font-medium text-foreground underline-offset-2 hover:underline">
            Add cert number
          </button>
        )}
      </p>
    </div>
  );
}

/* --------------------------------- Dialogs -------------------------------- */

export function CertDialog({ holding, open, onOpenChange }: { holding: HoldingView; open: boolean; onOpenChange: (o: boolean) => void }) {
  const { certs, setCert } = useSlabCerts();
  const [value, setValue] = useState("");
  useEffect(() => {
    if (open) setValue(certs[holding.key] ?? "");
  }, [open, certs, holding.key]);
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
