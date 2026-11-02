"use client";

import { Loader2 } from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { undoToast } from "@/components/ui/undo-toast";
import type { HoldingView } from "@/lib/finance/portfolio";
import { GRADERS } from "@/lib/graded";
import { RAW_CONDITIONS, REMOVE_REASONS, editedIdentity, gradesFor, liveEntries, removalEntry, removedMessage, restoreEntry, voidEntry } from "@/lib/holding-actions";
import { useStore } from "@/lib/store/collection-store";
import { useMoveSlab } from "@/lib/store/grading";
import { holdingKey, type Condition } from "@/lib/types";
import { Field, Stepper } from "./fields";
import { FormShell } from "./transaction-dialogs";

type DialogProps = { holding: HoldingView; open: boolean; onOpenChange: (o: boolean) => void };

function Choose({ label, value, onChange, options }: { label: string; value: string; onChange: (v: string) => void; options: readonly string[] }) {
  return (
    <Field label={label}>
      <Select value={value} onValueChange={onChange}>
        <SelectTrigger aria-label={label}>
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {options.map((o) => (
            <SelectItem key={o} value={o}>
              {o}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </Field>
  );
}

/**
 * Take copies out of your collection without a sale: opened, lost, gave away, damaged or traded
 * away. Their cost is written off (counts as a loss). Port of the app's RemoveSheet; Undo voids it.
 */
export function RemoveDialog({ holding, open, onOpenChange }: DialogProps) {
  const { addTransaction, today } = useStore();
  const [reason, setReason] = useState<string>(REMOVE_REASONS[0]);
  const [qty, setQty] = useState(1);
  const [date, setDate] = useState(today);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (open) {
      setReason(REMOVE_REASONS[0]);
      setQty(1);
      setDate(today);
    }
  }, [open, today]);

  const valid = qty >= 1 && qty <= holding.quantity && date <= today;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!valid) return;
    setSaving(true);
    try {
      const saved = await addTransaction(removalEntry(holding.identity, qty, reason, date));
      onOpenChange(false);
      undoToast(removedMessage(qty, reason), () => addTransaction(voidEntry(saved)));
    } catch (err) {
      toast.error("Couldn't remove", { description: err instanceof Error ? err.message : undefined });
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <FormShell
          title="Remove"
          description={holding.product?.name ?? "This copy"}
          onSubmit={submit}
          footer={
            <Button type="submit" variant="primary" size="lg" className="w-full" disabled={!valid || saving}>
              {saving && <Loader2 className="animate-spin" />}
              {saving ? "Removing…" : "Remove"}
            </Button>
          }
        >
          <Choose label="Why" value={reason} onChange={setReason} options={REMOVE_REASONS} />
          <div className="grid grid-cols-2 gap-3">
            {holding.quantity > 1 && (
              <Field label="Quantity" hint={`of ${holding.quantity}`}>
                <Stepper value={qty} onChange={setQty} max={holding.quantity} label="Quantity removed" />
              </Field>
            )}
            <Field label="Date" htmlFor="remove-date" className={holding.quantity > 1 ? undefined : "col-span-2"}>
              <Input id="remove-date" type="date" value={date} max={today} onChange={(e) => setDate(e.target.value)} className="tabular" />
            </Field>
          </div>
          <p className="text-[13px] text-muted">
            What you paid for {qty === 1 ? "it" : "them"} is written off, so it shows as a loss in your gains. To erase it as if you never had it, use Delete from collection instead.
          </p>
        </FormShell>
      </DialogContent>
    </Dialog>
  );
}

/**
 * Fix a copy's details: its printing, and its condition (or grade, for a slab). Its purchases,
 * sales and edits all stay; only what it is changes. Port of the app's EditDetailsSheet.
 */
export function EditDetailsDialog({ holding, open, onOpenChange, onChanged }: DialogProps & { onChanged?: (key: string) => void }) {
  const { changeDetails } = useStore();
  const moveSlab = useMoveSlab();
  const product = holding.product;
  const sealed = product?.kind === "sealed";
  const printings = product?.printings ?? [];
  const old = holding.identity;
  const [printing, setPrinting] = useState<string | null>(old.printing);
  const [graded, setGraded] = useState(false);
  const [company, setCompany] = useState("PSA");
  const [grade, setGrade] = useState("10");
  const [condition, setCondition] = useState<Condition>("Near Mint");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) return;
    setPrinting(old.printing ?? printings[0] ?? null);
    setGraded(Boolean(old.grade));
    setCompany(old.grade?.company ?? "PSA");
    setGrade(old.grade?.grade ?? "10");
    setCondition(RAW_CONDITIONS.includes(old.condition) ? old.condition : "Near Mint");
    // eslint-disable-next-line react-hooks/exhaustive-deps -- reset to the copy each time it opens
  }, [open]);

  const grades = gradesFor(company);
  const edited = editedIdentity(old, { sealed, printing, graded, company, grade: grades.includes(grade) ? grade : grades[0], condition });
  const changed = holdingKey(edited) !== holding.key;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!changed) return;
    setSaving(true);
    try {
      await changeDetails(old, edited);
      moveSlab(old, edited);
      onChanged?.(holdingKey(edited));
      toast.success("Details updated");
      onOpenChange(false);
    } catch (err) {
      toast.error("Couldn't update details", { description: err instanceof Error ? err.message : undefined });
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <FormShell
          title="Edit details"
          description={product?.name ?? "This copy"}
          onSubmit={submit}
          footer={
            <Button type="submit" variant="primary" size="lg" className="w-full" disabled={!changed || saving}>
              {saving && <Loader2 className="animate-spin" />}
              {saving ? "Saving…" : "Save"}
            </Button>
          }
        >
          {printings.length > 1 && <Choose label="Printing" value={printing ?? printings[0]} onChange={setPrinting} options={printings} />}
          {!sealed && (
            <>
              <div className="rounded-2xl border border-border p-4">
                <label className="flex items-center justify-between gap-3">
                  <span className="text-[14px] font-medium">Graded</span>
                  <Switch checked={graded} onCheckedChange={setGraded} aria-label="Graded" />
                </label>
                <div className="mt-4 grid grid-cols-2 gap-3">
                  {graded ? (
                    <>
                      <Choose label="Company" value={company} onChange={setCompany} options={GRADERS} />
                      <Choose label="Grade" value={grades.includes(grade) ? grade : grades[0]} onChange={setGrade} options={grades} />
                    </>
                  ) : (
                    <div className="col-span-2">
                      <Choose label="Condition" value={condition} onChange={(v) => setCondition(v as Condition)} options={RAW_CONDITIONS} />
                    </div>
                  )}
                </div>
              </div>
              <p className="text-[13px] text-muted">
                Your purchases, sales and edits stay as they are; only what this copy is changes. If you already have a copy with these details, the two become one.
              </p>
            </>
          )}
        </FormShell>
      </DialogContent>
    </Dialog>
  );
}

/**
 * Delete a copy as if you'd never added it: every entry is voided (corrections, so the record
 * is kept) and it leaves your value, cost and gains. Undo restores every entry. Same wording as
 * the app's confirmation.
 */
export function DeleteCopyDialog({ holding, open, onOpenChange, onDeleted }: DialogProps & { onDeleted?: () => void }) {
  const { addTransaction, data } = useStore();
  const [saving, setSaving] = useState(false);

  const confirm = async () => {
    setSaving(true);
    const live = liveEntries(data.transactions, holding.key);
    try {
      for (const t of live) await addTransaction(voidEntry(t));
      onOpenChange(false);
      onDeleted?.();
      undoToast("Deleted from your collection", async () => {
        for (const t of live) await addTransaction(restoreEntry(t));
      });
    } catch (err) {
      toast.error("Couldn't delete", { description: err instanceof Error ? err.message : undefined });
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Delete this from your collection?</DialogTitle>
          <DialogDescription>
            It&apos;s removed as if you never added it: it leaves your value, cost and gains. To count it as a loss instead, use Remove.
          </DialogDescription>
        </DialogHeader>
        <div className="flex gap-2 px-6 pb-6 pt-4">
          <Button variant="secondary" size="lg" className="flex-1" onClick={() => onOpenChange(false)} disabled={saving}>
            Cancel
          </Button>
          <Button variant="danger" size="lg" className="flex-1" onClick={() => void confirm()} disabled={saving}>
            {saving && <Loader2 className="animate-spin" />}
            Delete from collection
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
