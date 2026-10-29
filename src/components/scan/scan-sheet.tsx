"use client";

import { AlertTriangle, Camera, Check, ChevronDown, ChevronUp, ImagePlus, Loader2, RotateCcw, ScanLine, X } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { ProductImage } from "@/components/product/product-image";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { money } from "@/lib/format";
import { scanValue, type ScanCandidate, type ScanResult } from "@/lib/scan-types";
import { cn } from "@/lib/utils";

/** A confirmed scan: the product, its printing and price, and what the photo showed. */
export interface ScanPick {
  entryId: string;
  candidate: ScanCandidate;
  read: ScanResult["read"];
}

/** What the screen did with a pick, shown on its row (e.g. "Not in your inventory"). */
export interface ScanOutcome {
  ok: boolean;
  note?: string;
}

interface Entry {
  id: string;
  thumb: string;
  blob: Blob;
  state: "queued" | "reading" | "done" | "error";
  result?: ScanResult;
  error?: string;
  picked?: ScanCandidate;
  outcome?: ScanOutcome;
}

/** Photos read at once; more taps just queue, so you never wait to take the next one. */
const PARALLEL = 2;
/** Longest edge sent to the scanner. Plenty for a card, and quick to upload. */
const MAX_EDGE = 1400;

/**
 * Rapid card scanning. Tap the shutter (or press space) as fast as you like:
 * each photo goes to the scanner in the background and lands in the tray.
 * Clear matches are handed to `onPick` straight away; when a photo fits
 * several cards you pick one. Falls back to photo upload without a camera.
 */
export function ScanSheet({
  open,
  onOpenChange,
  title,
  description,
  onPick,
  extra,
  footer,
  disabled,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  title: string;
  description?: string;
  onPick: (pick: ScanPick) => ScanOutcome | void;
  /** Extra controls on a confirmed row (e.g. a cost field). */
  extra?: (pick: ScanPick) => React.ReactNode;
  footer?: (picks: ScanPick[]) => React.ReactNode;
  /** Stops new scans (and spending them), e.g. when the result couldn't be kept. */
  disabled?: boolean;
}) {
  const video = useRef<HTMLVideoElement>(null);
  const stream = useRef<MediaStream | null>(null);
  const file = useRef<HTMLInputElement>(null);
  const [camera, setCamera] = useState<"starting" | "on" | "off">("starting");
  const [entries, setEntries] = useState<Entry[]>([]);
  const [flash, setFlash] = useState(0);
  const [left, setLeft] = useState<number | null>(null);
  const [blocked, setBlocked] = useState<string | null>(null);
  // On a phone the camera fills the screen and the tray shows the latest scan; expanding it trades camera for the full list.
  const [expanded, setExpanded] = useState(false);
  const onPickRef = useRef(onPick);
  onPickRef.current = onPick;

  // Camera on while open; off (and the tray cleared) when closed.
  useEffect(() => {
    if (!open) return;
    let cancelled = false;
    setCamera("starting");
    setBlocked(null);
    fetch("/api/scan")
      .then((r) => (r.ok ? r.json() : null))
      .then((b) => !cancelled && b && setLeft(b.scansRemaining ?? null))
      .catch(() => undefined);
    if (!navigator.mediaDevices?.getUserMedia) {
      setCamera("off");
    } else {
      navigator.mediaDevices
        .getUserMedia({ video: { facingMode: { ideal: "environment" }, width: { ideal: 1920 }, height: { ideal: 1440 } }, audio: false })
        .then((s) => {
          if (cancelled) return s.getTracks().forEach((t) => t.stop());
          stream.current = s;
          if (video.current) {
            video.current.srcObject = s;
            void video.current.play().catch(() => undefined);
          }
          setCamera("on");
        })
        .catch(() => !cancelled && setCamera("off"));
    }
    return () => {
      cancelled = true;
      stream.current?.getTracks().forEach((t) => t.stop());
      stream.current = null;
      setExpanded(false);
      setEntries((list) => {
        list.forEach((e) => URL.revokeObjectURL(e.thumb));
        return [];
      });
    };
  }, [open]);

  const enqueue = useCallback((blob: Blob) => {
    const id = crypto.randomUUID();
    setEntries((list) => [{ id, blob, thumb: URL.createObjectURL(blob), state: "queued" }, ...list]);
  }, []);

  const capture = useCallback(() => {
    const v = video.current;
    if (disabled || !v || camera !== "on" || !v.videoWidth) return;
    const scale = Math.min(1, MAX_EDGE / Math.max(v.videoWidth, v.videoHeight));
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(v.videoWidth * scale);
    canvas.height = Math.round(v.videoHeight * scale);
    canvas.getContext("2d")!.drawImage(v, 0, 0, canvas.width, canvas.height);
    canvas.toBlob((b) => b && enqueue(b), "image/jpeg", 0.85);
    setFlash((n) => n + 1);
    setExpanded(false);
    navigator.vibrate?.(12);
  }, [camera, enqueue, disabled]);

  // Space or Enter takes a photo on a laptop.
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if ((e.key === " " || e.key === "Enter") && !(e.target as HTMLElement)?.closest("input, textarea, button")) {
        e.preventDefault();
        capture();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, capture]);

  const confirm = useCallback((entry: Entry, candidate: ScanCandidate) => {
    const outcome = onPickRef.current({ entryId: entry.id, candidate, read: entry.result?.read ?? null }) ?? { ok: true };
    setEntries((list) => list.map((e) => (e.id === entry.id ? { ...e, picked: candidate, outcome } : e)));
  }, []);

  // Work through the queue, a couple at a time.
  useEffect(() => {
    if (blocked) return;
    const reading = entries.filter((e) => e.state === "reading").length;
    const next = entries.filter((e) => e.state === "queued").slice(-Math.max(0, PARALLEL - reading));
    for (const entry of next) {
      setEntries((list) => list.map((e) => (e.id === entry.id ? { ...e, state: "reading" } : e)));
      const form = new FormData();
      form.append("image", entry.blob, "scan.jpg");
      fetch("/api/scan", { method: "POST", body: form })
        .then(async (r) => {
          const body = await r.json().catch(() => null);
          if (!r.ok) {
            const code = body?.error?.code;
            if (code === "scan_balance_empty" || code === "unauthorized" || code === "not_configured") setBlocked(body.error.message);
            throw new Error(body?.error?.message ?? "Couldn't read that one.");
          }
          return body as ScanResult;
        })
        .then((result) => {
          if (result.scansRemaining !== null) setLeft(result.scansRemaining);
          const done = { ...entry, state: "done" as const, result };
          setEntries((list) => list.map((e) => (e.id === entry.id ? done : e)));
          if (result.status === "matched" && result.candidates[0]) confirm(done, result.candidates[0]);
        })
        .catch((err: Error) => setEntries((list) => list.map((e) => (e.id === entry.id ? { ...e, state: "error", error: err.message } : e))));
    }
  }, [entries, blocked, confirm]);

  const retry = (id: string) => setEntries((list) => list.map((e) => (e.id === id ? { ...e, state: "queued", error: undefined } : e)));
  const picks: ScanPick[] = entries.filter((e) => e.picked && e.outcome?.ok).map((e) => ({ entryId: e.id, candidate: e.picked!, read: e.result?.read ?? null }));
  const busy = entries.filter((e) => e.state === "queued" || e.state === "reading").length;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="top-0 h-dvh max-h-none rounded-none border-0 sm:top-[6vh] sm:h-[760px] sm:max-h-[88dvh] sm:max-w-[560px] sm:rounded-[1.5rem] sm:border">
        <div className="flex items-start justify-between gap-3 px-5 pt-[max(1.25rem,env(safe-area-inset-top))]">
          <div className="min-w-0">
            <DialogTitle className="flex items-center gap-2">
              <ScanLine className="size-5" /> {title}
            </DialogTitle>
            <DialogDescription className="mt-0.5">{description ?? "Tap the shutter for each card. Keep going, they scan in the background."}</DialogDescription>
          </div>
          {left !== null && <span className="tabular mr-8 shrink-0 rounded-full bg-surface-2 px-2.5 py-1 text-[12px] text-muted">{left.toLocaleString()} scans left</span>}
        </div>

        {/* Viewfinder */}
        <div
          className={cn(
            "relative mx-3 mt-3 min-h-0 flex-1 overflow-hidden rounded-2xl bg-black transition-[height] sm:mx-5 sm:mt-4 sm:aspect-[4/3] sm:flex-none",
            expanded && "max-sm:h-[22dvh] max-sm:flex-none",
          )}
          // A size container, so the card guide fits whichever way the viewfinder is stretched.
          style={{ containerType: "size" }}
        >
          <video ref={video} playsInline muted className={cn("absolute inset-0 size-full object-cover", camera !== "on" && "hidden")} />
          {camera === "on" && <span aria-hidden className="scan-guide pointer-events-none absolute left-1/2 top-1/2 aspect-[63/88] h-[min(82cqh,120cqw)] -translate-x-1/2 -translate-y-1/2 rounded-xl" />}
          {camera === "on" && flash > 0 && <span key={flash} aria-hidden className="scan-flash pointer-events-none absolute inset-0 bg-white" />}
          {camera === "starting" && (
            <p className="absolute inset-0 flex items-center justify-center gap-2 text-[13px] text-white/70">
              <Loader2 className="size-4 animate-spin" /> Starting camera…
            </p>
          )}
          {camera === "off" && (
            <button type="button" onClick={() => file.current?.click()} className="absolute inset-0 flex flex-col items-center justify-center gap-2 text-white/80">
              <Camera className="size-7" />
              <span className="text-[14px] font-medium">Take or choose photos</span>
              <span className="text-[12px] text-white/50">Camera isn&apos;t available here, so photos open instead</span>
            </button>
          )}
          {busy > 0 && (
            <span className="tabular absolute left-3 top-3 flex items-center gap-1.5 rounded-full bg-black/60 px-2.5 py-1 text-[12px] text-white backdrop-blur">
              <Loader2 className="size-3 animate-spin" /> {busy} scanning
            </span>
          )}
        </div>

        <div className="mt-3 flex items-center justify-center gap-6 px-5">
          <button type="button" onClick={() => file.current?.click()} disabled={disabled} aria-label="Choose photos" className="grid size-11 disabled:opacity-40 place-items-center rounded-full bg-surface-2 text-muted hover:text-foreground">
            <ImagePlus className="size-5" />
          </button>
          <button
            type="button"
            // While the camera is starting, a tap does nothing rather than opening the photo picker.
            onClick={() => (camera === "on" ? capture() : camera === "off" ? file.current?.click() : undefined)}
            disabled={Boolean(blocked) || disabled}
            aria-label="Scan"
            className="grid size-[70px] place-items-center rounded-full bg-[var(--lime)] shadow-[0_0_0_5px_color-mix(in_srgb,var(--lime)_25%,transparent)] transition-transform active:scale-90 disabled:opacity-40"
          >
            <span className="size-[56px] rounded-full border-[3px] border-[#0b0b0c]/80" />
          </button>
          <span className="size-11" />
          <input
            ref={file}
            type="file"
            accept="image/jpeg,image/png,image/webp"
            capture="environment"
            multiple
            className="hidden"
            onChange={(e) => {
              for (const f of Array.from(e.target.files ?? [])) enqueue(f);
              e.target.value = "";
            }}
          />
        </div>

        {blocked && (
          <p className="mx-5 mt-3 flex items-center gap-2 rounded-xl bg-[color-mix(in_srgb,var(--down)_14%,transparent)] px-3 py-2 text-[13px]">
            <AlertTriangle className="size-4 shrink-0 text-down" /> {blocked}
          </p>
        )}

        {/* Tray. On a phone it shows the latest scan until you open the full list. */}
        {entries.length > 1 && (
          <button
            type="button"
            onClick={() => setExpanded((v) => !v)}
            aria-expanded={expanded}
            className="mx-5 mt-3 flex items-center justify-between rounded-xl bg-surface-2 px-3 py-2 text-[13px] font-medium sm:hidden"
          >
            <span className="tabular">{entries.length} scanned</span>
            <span className="flex items-center gap-1 text-muted">
              {expanded ? "Back to camera" : "Show all"} {expanded ? <ChevronDown className="size-4" /> : <ChevronUp className="size-4" />}
            </span>
          </button>
        )}
        <ul className={cn("mt-2 space-y-2 overflow-y-auto overscroll-contain px-5 pb-[max(1rem,env(safe-area-inset-bottom))] sm:mt-3 sm:min-h-0 sm:flex-1", expanded ? "min-h-0 flex-1" : "max-sm:max-h-[40dvh] max-sm:shrink-0")}>
          {!entries.length && <li className="py-4 text-center text-[13px] text-muted sm:py-6">Scanned cards show up here.</li>}
          {entries.map((e, i) => (
            <TrayRow key={e.id} entry={e} onConfirm={(c) => confirm(e, c)} onRetry={() => retry(e.id)} extra={extra} className={cn(i > 0 && !expanded && "max-sm:hidden")} />
          ))}
        </ul>

        {footer && picks.length > 0 && <div className="border-t border-border px-5 pb-[max(1.25rem,env(safe-area-inset-bottom))] pt-3">{footer(picks)}</div>}
      </DialogContent>
    </Dialog>
  );
}

function TrayRow({ entry, onConfirm, onRetry, extra, className }: { entry: Entry; onConfirm: (c: ScanCandidate) => void; onRetry: () => void; extra?: (pick: ScanPick) => React.ReactNode; className?: string }) {
  const r = entry.result;
  const thumb = (
    // eslint-disable-next-line @next/next/no-img-element -- local object URL of the photo just taken
    <img src={entry.thumb} alt="" className="h-14 w-11 shrink-0 rounded-md object-cover" />
  );
  if (entry.state === "queued" || entry.state === "reading") {
    return (
      <li className={cn("flex items-center gap-3 rounded-2xl bg-surface-2 p-2.5", className)}>
        {thumb}
        <span className="flex items-center gap-2 text-[13px] text-muted">
          <Loader2 className="size-3.5 animate-spin" /> {entry.state === "reading" ? "Reading…" : "Waiting…"}
        </span>
      </li>
    );
  }
  if (entry.state === "error") {
    return (
      <li className={cn("flex items-center gap-3 rounded-2xl bg-surface-2 p-2.5", className)}>
        {thumb}
        <span className="min-w-0 flex-1 text-[13px] text-muted">{entry.error}</span>
        <button onClick={onRetry} aria-label="Try again" className="grid size-8 shrink-0 place-items-center rounded-full bg-surface-3 text-muted hover:text-foreground">
          <RotateCcw className="size-3.5" />
        </button>
      </li>
    );
  }
  if (entry.picked) {
    const c = entry.picked;
    const ok = entry.outcome?.ok !== false;
    const grade = entry.result?.read?.grade;
    return (
      <li className={cn("rounded-2xl p-2.5", className, ok ? "bg-surface-2" : "bg-[color-mix(in_srgb,var(--down)_10%,var(--surface-2))]")}>
        <div className="flex items-center gap-3">
          <ProductImage product={c.product} size="xs" className="h-14 w-11 shrink-0 rounded-md" />
          <span className="min-w-0 flex-1">
            <span className="block truncate text-[14px] font-medium">{c.product.name}</span>
            <span className="block truncate text-[12px] text-muted">
              {[c.product.setName, c.product.number && `#${c.product.number}`, c.printing, grade && `${grade.company} ${grade.grade}`].filter(Boolean).join(" · ")}
            </span>
            {entry.outcome?.note && <span className={cn("block text-[12px]", ok ? "text-muted" : "text-down")}>{entry.outcome.note}</span>}
          </span>
          <span className="shrink-0 text-right">
            <span className="tabular block text-[14px] font-semibold">{money(scanValue(c, entry.result?.read ?? null))}</span>
            {ok && <Check className="ml-auto mt-0.5 size-3.5 text-up" />}
          </span>
        </div>
        {ok && extra?.({ entryId: entry.id, candidate: c, read: entry.result?.read ?? null })}
      </li>
    );
  }
  // Ambiguous, retake, not found: say so, and offer whatever the scanner suggested.
  const label = r?.status === "ambiguous" ? "Which one is it?" : r?.status === "retake" ? (r.message ?? "Couldn't read it clearly. Try again.") : r?.status === "unsupported" ? "That game or language isn't supported." : "No match found.";
  return (
    <li className={cn("rounded-2xl bg-surface-2 p-2.5", className)}>
      <div className="flex items-center gap-3">
        {thumb}
        <span className={cn("min-w-0 flex-1 text-[13px]", r?.status === "ambiguous" ? "font-medium" : "text-muted")}>{label}</span>
        {r?.status !== "ambiguous" && <X className="size-4 shrink-0 text-subtle" />}
      </div>
      {r && r.candidates.length > 0 && (
        <div className="mt-2 flex gap-2 overflow-x-auto pb-1">
          {r.candidates.slice(0, 5).map((c) => (
            <button key={`${c.product.id}-${c.printing}`} onClick={() => onConfirm(c)} className="w-[92px] shrink-0 rounded-xl bg-surface-3 p-1.5 text-left hover:ring-2 hover:ring-[var(--lime)]">
              <ProductImage product={c.product} size="xs" className="aspect-[5/7] w-full rounded-md" />
              <span className="mt-1 block truncate text-[11px] font-medium">{c.product.name}</span>
              <span className="block truncate text-[10px] text-muted">{[c.product.setName, c.product.number && `#${c.product.number}`].filter(Boolean).join(" · ")}</span>
            </button>
          ))}
        </div>
      )}
    </li>
  );
}
