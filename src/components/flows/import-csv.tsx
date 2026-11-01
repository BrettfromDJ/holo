"use client";

import { AlertTriangle, ArrowLeft, Check, ChevronsUpDown, Download, FileUp, Loader2, Undo2, X } from "lucide-react";
import { useCallback, useMemo, useRef, useState } from "react";
import { toast } from "sonner";
import { ProductImage } from "@/components/product/product-image";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Textarea } from "@/components/ui/input";
import {
  TEMPLATE_CSV,
  isConfident,
  matchPrinting,
  parseImport,
  rankCandidates,
  searchQueries,
  type CandidateScore,
  type ImportRow,
  type SkippedLine,
} from "@/lib/csv-import";
import { SAMPLE_PRODUCTS } from "@/lib/demo/catalog";
import { formatDate, money } from "@/lib/format";
import { mapLimit } from "@/lib/pricing/cache";
import type { SearchHit } from "@/lib/pricing/types";
import { useStore } from "@/lib/store/collection-store";
import { priceKey, type Condition } from "@/lib/types";
import { cn } from "@/lib/utils";

type Candidate = SearchHit & { fit: CandidateScore };

interface Match {
  row: ImportRow;
  candidates: Candidate[];
  /** Index into candidates; null skips the row. */
  choice: number | null;
}

type Step =
  | { kind: "pick" }
  | { kind: "matching"; done: number; total: number }
  | { kind: "review" }
  | { kind: "importing"; done: number; total: number };

/** Searches running at once against the stored catalog. */
const CONCURRENCY = 3;
const MAX_CANDIDATES = 6;
const MAX_ROWS = 2000;

const rowKey = (r: ImportRow) => `${r.name.toLowerCase()}|${(r.set ?? "").toLowerCase()}|${(r.number ?? "").toLowerCase()}`;

/**
 * Import purchases from a CSV (another tracker's export or a spreadsheet).
 * Rows are matched against the stored catalog only (free; never the live TCG
 * API), reviewed, then added with the same store action as Add to collection.
 */
export function ImportCsvDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) {
  const store = useStore();
  const demo = store.mode === "demo";
  const [step, setStep] = useState<Step>({ kind: "pick" });
  const [pasted, setPasted] = useState("");
  const [fileName, setFileName] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [matches, setMatches] = useState<Match[]>([]);
  const [skipped, setSkipped] = useState<SkippedLine[]>([]);
  const [dragging, setDragging] = useState(false);
  const runRef = useRef(0);
  const fileRef = useRef<HTMLInputElement>(null);
  // Printings per catalog product, fetched only when a row asks for a specific one.
  const printingsRef = useRef(new Map<string, string[]>());

  const reset = useCallback(() => {
    runRef.current++;
    setStep({ kind: "pick" });
    setMatches([]);
    setSkipped([]);
    setError(null);
  }, []);

  const close = (o: boolean) => {
    if (step.kind === "importing") return;
    onOpenChange(o);
    if (!o) {
      setTimeout(() => {
        reset();
        setPasted("");
        setFileName(null);
      }, 250);
    }
  };

  const sampleHits = useMemo<SearchHit[]>(
    () =>
      SAMPLE_PRODUCTS.map((p) => {
        const printing = p.printings?.[0] ?? null;
        return { product: store.data.products[p.id] ?? p, printing, market: store.data.prices[priceKey(p.id, printing)]?.market ?? null, priceUpdatedAt: null };
      }),
    [store.data.products, store.data.prices],
  );

  const findCandidates = useCallback(
    async (row: ImportRow): Promise<Candidate[]> => {
      if (demo) return rankCandidates(row, sampleHits).slice(0, MAX_CANDIDATES);
      const seen = new Map<string, SearchHit>();
      let ranked: Candidate[] = [];
      for (const q of searchQueries(row)) {
        const res = await fetch(`/api/explore/search?q=${encodeURIComponent(q)}&limit=40`);
        if (res.status === 503) throw new Error("Catalog search isn't available on this server.");
        if (!res.ok) continue;
        const body = (await res.json()) as { products?: SearchHit[] };
        for (const h of body.products ?? []) if (!seen.has(h.product.id)) seen.set(h.product.id, h);
        ranked = rankCandidates(row, [...seen.values()]);
        if (ranked[0] && isConfident(ranked[0].fit)) break;
      }
      return ranked.slice(0, MAX_CANDIDATES);
    },
    [demo, sampleHits],
  );

  const start = async (text: string) => {
    setError(null);
    const parsed = parseImport(text, store.today);
    if (parsed.error) {
      setError(parsed.error);
      return;
    }
    if (!parsed.rows.length) {
      setError("None of the rows could be read.");
      return;
    }
    if (parsed.rows.length > MAX_ROWS) {
      setError(`That's ${parsed.rows.length.toLocaleString()} rows. Import up to ${MAX_ROWS.toLocaleString()} at a time — split the file and import each part.`);
      return;
    }
    const run = ++runRef.current;
    // Rows naming the same card share one search.
    const keys = [...new Set(parsed.rows.map(rowKey))];
    const byKey = new Map(parsed.rows.map((r) => [rowKey(r), r]));
    const found = new Map<string, Candidate[]>();
    setStep({ kind: "matching", done: 0, total: keys.length });
    let done = 0;
    try {
      await mapLimit(keys, CONCURRENCY, async (k) => {
        if (run !== runRef.current) return;
        found.set(k, await findCandidates(byKey.get(k)!).catch((e: Error) => {
          if (/isn't available/.test(e.message)) throw e;
          return [];
        }));
        done++;
        if (run === runRef.current) setStep({ kind: "matching", done, total: keys.length });
      });
    } catch (e) {
      if (run !== runRef.current) return;
      setStep({ kind: "pick" });
      setError((e as Error).message);
      return;
    }
    if (run !== runRef.current) return;

    // Rows asking for a specific printing need the product's printings (stored catalog, free).
    if (!demo) {
      const need = new Set<string>();
      for (const r of parsed.rows) {
        const best = found.get(rowKey(r))?.[0];
        if (r.printing && best && best.printing?.toLowerCase() !== r.printing.toLowerCase() && !printingsRef.current.has(best.product.id)) need.add(best.product.id);
      }
      await mapLimit([...need], CONCURRENCY, async (id) => {
        const res = await fetch(`/api/explore/products/${encodeURIComponent(id)}`).catch(() => null);
        const body = res?.ok ? ((await res.json()) as { product?: { printings?: string[] } }) : null;
        printingsRef.current.set(id, body?.product?.printings ?? []);
      });
      if (run !== runRef.current) return;
    }

    setMatches(parsed.rows.map((row) => {
      const candidates = found.get(rowKey(row)) ?? [];
      return { row, candidates, choice: candidates.length ? 0 : null };
    }));
    setSkipped(parsed.skipped);
    setStep({ kind: "review" });
  };

  const readFile = async (file: File) => {
    setFileName(file.name);
    if (file.size > 5 * 1024 * 1024) {
      setError("That file is over 5 MB. Split it into smaller files.");
      return;
    }
    await start(await file.text());
  };

  const printingsOf = useCallback(
    (hit: SearchHit) => {
      const known = hit.product.printings?.length ? hit.product.printings : printingsRef.current.get(hit.product.id);
      return known?.length ? known : hit.printing ? [hit.printing] : [];
    },
    [],
  );

  /** What will be saved for a row with its current choice. */
  const resolve = useCallback(
    (m: Match) => {
      if (m.choice === null) return null;
      const hit = m.candidates[m.choice];
      const sealed = hit.product.kind === "sealed";
      const p = matchPrinting(m.row.printing, printingsOf(hit), hit.printing);
      const condition: Condition = m.row.grade ? "Near Mint" : sealed ? "Sealed" : (m.row.condition === "Sealed" ? "Near Mint" : (m.row.condition ?? "Near Mint"));
      const market = store.data.prices[priceKey(hit.product.id, p.printing)]?.market ?? hit.market;
      const unitPrice = m.row.unitPrice ?? market ?? 0;
      return { hit, printing: p.printing, printingMatched: p.matched, condition, grade: sealed ? null : m.row.grade, unitPrice, fromMarket: m.row.unitPrice === null };
    },
    [printingsOf, store.data.prices],
  );

  const ready = matches.filter((m) => m.choice !== null);
  const notFound = matches.filter((m) => !m.candidates.length);
  const totalPaid = ready.reduce((s, m) => s + (resolve(m)?.unitPrice ?? 0) * m.row.quantity, 0);
  const rowCount = matches.length + skipped.length;

  const runImport = async () => {
    const todo = matches.filter((m) => m.choice !== null);
    if (!todo.length) return;
    setStep({ kind: "importing", done: 0, total: todo.length });
    let failed = 0;
    let firstError: string | null = null;
    // Make sure each product is in the collection's catalog first, once per product.
    const prepared = new Map<string, boolean>();
    for (const [i, m] of todo.entries()) {
      const r = resolve(m)!;
      const id = r.hit.product.id;
      try {
        if (!prepared.has(id)) {
          if (store.repoKind === "cloud") {
            // Already in the shared catalog: load it from there (no TCG API).
            prepared.set(id, await store.showCatalogProduct(id));
          } else if (store.repoKind === "local") {
            // Saved in this browser only: store the product locally, as Add to collection does.
            await store.importProduct(id, r.printing, r.hit.product.kind);
            prepared.set(id, true);
          } else prepared.set(id, true);
        }
        await store.addTransaction({
          productId: id,
          printing: r.printing,
          condition: r.condition,
          grade: r.grade,
          type: "purchase",
          date: m.row.date,
          quantity: m.row.quantity,
          unitPrice: r.unitPrice,
          shipping: 0,
          fees: 0,
          tax: 0,
          source: m.row.source,
          notes: m.row.notes,
        });
      } catch (e) {
        failed++;
        firstError ??= e instanceof Error ? e.message : "Unknown error";
      }
      setStep({ kind: "importing", done: i + 1, total: todo.length });
    }
    const added = todo.length - failed;
    const left = rowCount - added;
    if (added) {
      toast.success(`Imported ${added} ${added === 1 ? "purchase" : "purchases"}`, {
        description: [left ? `${left} ${left === 1 ? "row" : "rows"} skipped.` : null, demo ? "Added to the demo. Nothing is saved to your collection." : null].filter(Boolean).join(" ") || undefined,
      });
    }
    if (failed) toast.error(`${failed} ${failed === 1 ? "row" : "rows"} couldn't be saved`, { description: firstError ?? undefined });
    if (added) close(false);
    else setStep({ kind: "review" });
  };

  const downloadTemplate = () => {
    const a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob([TEMPLATE_CSV], { type: "text/csv" }));
    a.download = "lucent-import-template.csv";
    a.click();
    URL.revokeObjectURL(a.href);
  };

  const wide = step.kind === "review";

  return (
    <Dialog open={open} onOpenChange={close}>
      <DialogContent
        className={cn(wide ? "h-[92dvh] sm:h-[min(720px,84vh)] sm:max-w-[940px]" : "sm:max-w-[560px]", "sm:top-[8vh]")}
        hideClose={step.kind === "importing"}
        onInteractOutside={(e) => step.kind !== "pick" && e.preventDefault()}
      >
        <div className="px-6 pr-14 pt-6">
          <DialogTitle className="text-balance font-display text-[22px] font-medium leading-tight tracking-tight">
            {step.kind === "review" ? "Check your import" : "Import a collection"}
          </DialogTitle>
          <DialogDescription>
            {step.kind === "review"
              ? "Each row is matched to a product in the catalog. Change a match or skip a row before importing."
              : "Bring in cards and sealed products from another tracker or a spreadsheet."}
          </DialogDescription>
        </div>

        {step.kind === "pick" && (
          <div className="space-y-4 overflow-y-auto px-6 pb-6 pt-5">
            <div
              onDragOver={(e) => {
                e.preventDefault();
                setDragging(true);
              }}
              onDragLeave={() => setDragging(false)}
              onDrop={(e) => {
                e.preventDefault();
                setDragging(false);
                const f = e.dataTransfer.files?.[0];
                if (f) void readFile(f);
              }}
              className={cn(
                "flex flex-col items-center gap-3 rounded-2xl border border-dashed px-4 py-7 text-center transition-colors",
                dragging ? "border-lime bg-lime/5" : "border-border-strong bg-surface-2/40",
              )}
            >
              <span className="grid size-11 place-items-center rounded-xl bg-surface-2 text-muted">
                <FileUp className="size-5" />
              </span>
              <div>
                <p className="text-[15px] font-medium">{fileName ?? "Drop a CSV file here"}</p>
                <p className="mt-0.5 text-[13px] text-muted">Exports from other trackers, Excel or Google Sheets (File → Download → CSV).</p>
              </div>
              <Button variant="lime" size="md" onClick={() => fileRef.current?.click()}>
                Choose a file
              </Button>
              <input
                ref={fileRef}
                type="file"
                accept=".csv,.tsv,.txt,text/csv,text/plain"
                className="sr-only"
                tabIndex={-1}
                onChange={(e) => {
                  const f = e.target.files?.[0];
                  e.target.value = "";
                  if (f) void readFile(f);
                }}
              />
            </div>

            <div>
              <label htmlFor="csv-paste" className="mb-1.5 block text-[13px] font-medium text-muted">
                Or paste CSV
              </label>
              <Textarea
                id="csv-paste"
                value={pasted}
                onChange={(e) => setPasted(e.target.value)}
                placeholder={"Name,Set,Number,Condition,Quantity,Price paid,Purchase date\nCharizard ex,Obsidian Flames,223/197,NM,1,72.00,2024-03-14"}
                className="h-28 resize-none font-mono text-[12px] leading-relaxed"
                spellCheck={false}
              />
            </div>

            {error && (
              <p role="alert" className="flex items-start gap-2 rounded-xl bg-surface-2 px-3 py-2.5 text-[13px] text-foreground">
                <AlertTriangle className="mt-0.5 size-4 shrink-0 text-muted" />
                {error}
              </p>
            )}

            <p className="text-[12px] leading-relaxed text-subtle">
              Only a name column is needed. Also read: set, number, printing, condition, grading company and grade (or “PSA 10”), quantity, price paid (or total), purchase date, notes.
              {demo && " You're in the demo: imports go into the demo sandbox and nothing is saved to your collection."}
            </p>

            <div className="flex flex-wrap items-center justify-between gap-3">
              <button type="button" onClick={downloadTemplate} className="inline-flex items-center gap-1.5 text-[13px] font-medium text-muted underline-offset-4 hover:text-foreground hover:underline">
                <Download className="size-4" /> Download a template
              </button>
              <Button variant="secondary" disabled={!pasted.trim()} onClick={() => void start(pasted)}>
                Match pasted rows
              </Button>
            </div>
          </div>
        )}

        {(step.kind === "matching" || step.kind === "importing") && (
          <div className="flex flex-col items-center gap-4 px-6 pb-8 pt-10 text-center">
            <Loader2 className="size-6 animate-spin text-muted" />
            <p className="tabular text-[15px] font-medium">
              {step.kind === "matching" ? `Matching ${step.done} of ${step.total} ${step.total === 1 ? "product" : "products"}` : `Importing ${step.done} of ${step.total}`}
            </p>
            <div className="h-1.5 w-full max-w-sm overflow-hidden rounded-full bg-surface-2">
              <div className="h-full rounded-full bg-lime transition-[width] duration-300" style={{ width: `${step.total ? (step.done / step.total) * 100 : 0}%` }} />
            </div>
            <p className="text-[13px] text-muted">{step.kind === "matching" ? "Searching the catalog. Big files take a minute." : "Keep this open until it finishes."}</p>
            {step.kind === "matching" && (
              <Button variant="ghost" size="sm" onClick={reset}>
                Cancel
              </Button>
            )}
          </div>
        )}

        {step.kind === "review" && (
          <>
            <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1 px-6 pb-3 pt-4">
              <p className="tabular font-display text-[17px] font-medium">
                {ready.length} of {rowCount} {rowCount === 1 ? "row" : "rows"} ready
                <span className="text-muted"> · total paid </span>
                {money(totalPaid)}
              </p>
              {demo && <Badge variant="sample">Demo — nothing is saved</Badge>}
            </div>
            <div className="min-h-0 flex-1 overflow-y-auto border-t border-border">
              <div className="sticky top-0 z-10 hidden grid-cols-[minmax(0,1fr)_128px_112px_44px_96px_100px_40px] gap-3 border-b border-border bg-surface px-6 py-2 text-[11px] font-medium uppercase tracking-wide text-subtle md:grid">
                <span>Product</span>
                <span>Printing</span>
                <span>Condition</span>
                <span className="text-right">Qty</span>
                <span className="text-right">Paid each</span>
                <span>Date</span>
                <span />
              </div>
              <ul className="divide-y divide-border">
                {matches.map((m, i) =>
                  m.candidates.length ? (
                    <ReviewRow
                      key={i}
                      match={m}
                      resolved={resolve(m)}
                      onChoose={(choice) => setMatches((all) => all.map((x, j) => (j === i ? { ...x, choice } : x)))}
                    />
                  ) : null,
                )}
              </ul>
              {(notFound.length > 0 || skipped.length > 0) && (
                <div className="border-t border-border px-6 py-4">
                  <p className="text-[13px] font-medium">Not imported</p>
                  <ul className="mt-2 space-y-1.5">
                    {notFound.map((m) => (
                      <li key={`n${m.row.line}`} className="flex gap-3 text-[13px]">
                        <span className="tabular w-14 shrink-0 text-subtle">Line {m.row.line}</span>
                        <span className="min-w-0 flex-1 truncate">{[m.row.name, m.row.set, m.row.number].filter(Boolean).join(" · ")}</span>
                        <span className="shrink-0 text-muted">Not found</span>
                      </li>
                    ))}
                    {skipped.map((s) => (
                      <li key={`s${s.line}`} className="flex gap-3 text-[13px]">
                        <span className="tabular w-14 shrink-0 text-subtle">Line {s.line}</span>
                        <span className="min-w-0 flex-1 truncate text-muted">{s.reason}</span>
                        <span className="shrink-0 text-muted">Skipped</span>
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
            <div className="flex items-center justify-between gap-3 border-t border-border px-6 py-4 pb-[max(1rem,env(safe-area-inset-bottom))]">
              <Button variant="ghost" onClick={reset}>
                <ArrowLeft /> Start over
              </Button>
              <Button variant="lime" disabled={!ready.length} onClick={() => void runImport()}>
                Import {ready.length} {ready.length === 1 ? "row" : "rows"}
              </Button>
            </div>
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}

function ReviewRow({
  match,
  resolved,
  onChoose,
}: {
  match: Match;
  resolved: { hit: SearchHit; printing: string | null; printingMatched: boolean; condition: Condition; grade: ImportRow["grade"]; unitPrice: number; fromMarket: boolean } | null;
  onChoose: (choice: number | null) => void;
}) {
  const { row, candidates, choice } = match;
  const skippedRow = resolved === null;
  const hit = resolved?.hit ?? candidates[0];
  const unsure = !skippedRow && choice !== null && !isConfident(candidates[choice].fit);
  const conditionLabel = resolved?.grade ? `${resolved.grade.company} ${resolved.grade.grade}` : resolved?.condition;
  const notes = [
    ...row.warnings,
    resolved && !resolved.printingMatched && row.printing ? `No ${row.printing} printing, used ${resolved.printing ?? "the default"}` : null,
    resolved?.fromMarket ? (resolved.unitPrice ? "No price in the file, used market price" : "No price in the file") : null,
  ].filter((x): x is string => Boolean(x));

  return (
    <li className={cn("grid grid-cols-[minmax(0,1fr)_40px] items-center gap-x-3 gap-y-1 px-6 py-3 md:grid-cols-[minmax(0,1fr)_128px_112px_44px_96px_100px_40px]", skippedRow && "opacity-45")}>
      <div className="flex min-w-0 items-center gap-3">
        <ProductImage product={hit.product} size="xs" className="size-12 shrink-0 rounded-lg" />
        <div className="min-w-0">
          <p className="truncate text-[14px] font-medium">{hit.product.name}</p>
          <p className="truncate text-[12px] text-muted">{[hit.product.setName, hit.product.number ? `#${hit.product.number}` : null].filter(Boolean).join(" · ")}</p>
          <p className="line-clamp-2 text-[12px] text-subtle md:line-clamp-none md:truncate">
            Line {row.line} · {row.name}
            {unsure && <span className="text-muted"> · check this match</span>}
          </p>
          {/* Phone: the details sit under the name. */}
          <p className="tabular mt-0.5 text-[12px] text-muted md:hidden">
            {skippedRow ? "Skipped" : [resolved.printing, conditionLabel, `×${row.quantity}`, money(resolved.unitPrice), formatDate(row.date)].filter(Boolean).join(" · ")}
          </p>
        </div>
      </div>
      <span className="hidden truncate text-[13px] md:block">{skippedRow ? "—" : (resolved.printing ?? "—")}</span>
      <span className="hidden truncate text-[13px] md:block">{skippedRow ? "Skipped" : conditionLabel}</span>
      <span className="tabular hidden text-right text-[13px] md:block">{row.quantity}</span>
      <span className="tabular hidden text-right text-[13px] md:block">{skippedRow ? "—" : money(resolved.unitPrice)}</span>
      <span className="tabular hidden truncate text-[13px] md:block">{formatDate(row.date)}</span>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="ghost" size="icon-sm" aria-label={`Change the match for line ${row.line}`} className="justify-self-end">
            <ChevronsUpDown />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-[min(340px,calc(100vw-32px))]">
          <DropdownMenuLabel>Match for “{row.name}”</DropdownMenuLabel>
          {candidates.map((c, i) => (
            <DropdownMenuItem key={c.product.id} onSelect={() => onChoose(i)} className="gap-3">
              <ProductImage product={c.product} size="xs" className="size-9 shrink-0 rounded-md" />
              <span className="min-w-0 flex-1">
                <span className="block truncate">{c.product.name}</span>
                <span className="block truncate text-[12px] text-muted">{[c.product.setName, c.product.number ? `#${c.product.number}` : null].filter(Boolean).join(" · ")}</span>
              </span>
              {choice === i && <Check className="shrink-0" />}
            </DropdownMenuItem>
          ))}
          <DropdownMenuSeparator />
          {skippedRow ? (
            <DropdownMenuItem onSelect={() => onChoose(0)}>
              <Undo2 /> Include this row
            </DropdownMenuItem>
          ) : (
            <DropdownMenuItem onSelect={() => onChoose(null)}>
              <X /> Skip this row
            </DropdownMenuItem>
          )}
        </DropdownMenuContent>
      </DropdownMenu>
      {notes.length > 0 && !skippedRow && (
        <p className="col-span-full flex items-start gap-1.5 pl-[60px] text-[12px] text-muted">
          <AlertTriangle className="mt-px size-3.5 shrink-0" />
          {notes.join(" · ")}
        </p>
      )}
    </li>
  );
}
