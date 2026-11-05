"use client";

import { Check, FileUp, ScanLine, Search } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { useExploreIndex } from "@/components/explore/explore-items";
import { ScanToCollection } from "@/components/scan/scan-to-collection";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { useStore } from "@/lib/store/collection-store";
import { useSyncedState } from "@/lib/store/synced-state";
import { cn } from "@/lib/utils";
import { ImportCsvDialog } from "./import-csv";

/** The brands offered when the catalog can't be reached. Spelled the way the catalog spells them. */
export const FALLBACK_GAMES = [
  { slug: "pokemon", name: "Pokemon" },
  { slug: "pokemon-japan", name: "Pokemon Japan" },
  { slug: "magic", name: "Magic: The Gathering" },
  { slug: "one-piece", name: "One Piece" },
  { slug: "lorcana", name: "Disney Lorcana" },
  { slug: "yugioh", name: "Yu-Gi-Oh!" },
];

const doneKey = (userId: string) => `holo:onboarding-done:${userId}`;

function isDone(userId: string) {
  try {
    return localStorage.getItem(doneKey(userId)) === "1";
  } catch {
    return true;
  }
}

function markDone(userId: string) {
  try {
    localStorage.setItem(doneKey(userId), "1");
  } catch {
    // ignore
  }
}

/**
 * The two first-run steps on a signed-in account with nothing in it: what you collect
 * (`user_state` "collects", shared with the app; Explore puts those brands first), then the
 * ways to add a first card. Once per account in this browser; Later skips it for good.
 */
export function FirstRun() {
  const { status, repoKind, user, data, openAdd } = useStore();
  const [open, setOpen] = useState(false);
  const [step, setStep] = useState<0 | 1>(0);
  const [scanning, setScanning] = useState(false);
  const [importing, setImporting] = useState(false);
  const [collects, setCollects, , synced] = useSyncedState<string[]>("collects", []);
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const index = useExploreIndex();

  const games = useMemo(() => (index.status === "ready" && index.games.length ? index.games.map((g) => ({ slug: g.slug, name: g.name })) : FALLBACK_GAMES), [index]);

  useEffect(() => {
    if (status !== "ready" || repoKind !== "cloud" || !user) return;
    if (data.transactions.length || isDone(user.id)) return;
    setOpen(true);
  }, [status, repoKind, user, data.transactions.length]);

  // Start from what the account already says (another device may have picked).
  useEffect(() => {
    if (open && synced && collects.length) setPicked(new Set(collects));
    // eslint-disable-next-line react-hooks/exhaustive-deps -- only when the dialog opens
  }, [open, synced]);

  if (!user) return null;

  const finish = (then?: () => void) => {
    markDone(user.id);
    setOpen(false);
    if (then) window.setTimeout(then, 250);
  };

  const toggle = (slug: string) =>
    setPicked((prev) => {
      const next = new Set(prev);
      if (next.has(slug)) next.delete(slug);
      else next.add(slug);
      return next;
    });

  const savePicks = () => {
    // The hook replays this edit on the account's value once that loads, so a failed read
    // never saves over it.
    setCollects(games.filter((g) => picked.has(g.slug)).map((g) => g.slug));
    setStep(1);
  };

  return (
    <>
      <Dialog open={open} onOpenChange={(o) => !o && finish()}>
        <DialogContent className="sm:max-w-[520px]">
          <div className="flex items-center justify-between px-6 pt-6">
            <div className="flex items-center gap-1.5" aria-hidden>
              {[0, 1].map((i) => (
                <span key={i} className={cn("h-1.5 rounded-full transition-all", i === step ? "w-4 bg-lime" : "w-1.5 bg-foreground/20")} />
              ))}
            </div>
            <button type="button" onClick={() => finish()} className="mr-8 text-[13px] font-medium text-muted hover:text-foreground">
              Later
            </button>
          </div>
          {step === 0 ? (
            <div className="px-6 pb-6 pt-4">
              <DialogTitle className="font-display text-[26px] tracking-tight">What do you collect?</DialogTitle>
              <DialogDescription className="text-[15px]">Pick as many as you like. Explore puts them first.</DialogDescription>
              <div className="mt-5 grid grid-cols-2 gap-2.5">
                {games.map((g) => {
                  const on = picked.has(g.slug);
                  return (
                    <button
                      key={g.slug}
                      type="button"
                      aria-pressed={on}
                      onClick={() => toggle(g.slug)}
                      className={cn(
                        "flex h-12 items-center gap-2.5 rounded-2xl border px-3.5 text-left text-[14px] font-semibold transition-colors",
                        on ? "border-lime bg-lime text-[#0b0b0c]" : "border-border bg-surface-2 text-foreground hover:bg-surface-3",
                      )}
                    >
                      <span className={cn("flex size-5 shrink-0 items-center justify-center rounded-full border", on ? "border-[#0b0b0c]/40" : "border-border-strong")}>
                        {on && <Check className="size-3.5" strokeWidth={3} />}
                      </span>
                      <span className="truncate">{g.name}</span>
                    </button>
                  );
                })}
              </div>
              <Button variant="lime" size="lg" className="mt-6 w-full" onClick={savePicks}>
                {picked.size ? "Continue" : "Skip for now"}
              </Button>
            </div>
          ) : (
            <div className="px-6 pb-6 pt-4">
              <DialogTitle className="font-display text-[26px] tracking-tight">Add your first card</DialogTitle>
              <DialogDescription className="text-[15px]">Scan it, look it up, or bring a whole collection over.</DialogDescription>
              <div className="mt-5 flex flex-col gap-2.5">
                <Tile icon={<ScanLine />} title="Scan" line="Use your camera; the card's price appears on it." onClick={() => finish(() => setScanning(true))} />
                <Tile icon={<Search />} title="Search" line="Find any card or sealed product by name." onClick={() => finish(() => openAdd())} />
                <Tile icon={<FileUp />} title="Import" line="Bring purchases in from another tracker or a spreadsheet (CSV)." onClick={() => finish(() => setImporting(true))} />
              </div>
              <button type="button" onClick={() => finish()} className="mt-5 block w-full text-center text-[14px] font-medium text-muted hover:text-foreground">
                Later
              </button>
            </div>
          )}
        </DialogContent>
      </Dialog>
      <ScanToCollection open={scanning} onOpenChange={setScanning} />
      <ImportCsvDialog open={importing} onOpenChange={setImporting} />
    </>
  );
}

function Tile({ icon, title, line, onClick }: { icon: React.ReactNode; title: string; line: string; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex items-center gap-4 rounded-2xl border border-border bg-surface-2 p-4 text-left transition-colors hover:bg-surface-3 [&_svg]:size-5"
    >
      <span className="flex size-11 shrink-0 items-center justify-center rounded-full bg-lime/15 text-lime">{icon}</span>
      <span className="min-w-0">
        <span className="block text-[16px] font-semibold">{title}</span>
        <span className="block text-[13px] text-muted">{line}</span>
      </span>
    </button>
  );
}

/** Picked brands first, then the rest in their original order (shared with Explore). */
export function orderByCollects<T extends { slug: string }>(games: T[], collects: string[]): T[] {
  if (!collects.length) return games;
  const rank = new Map(collects.map((slug, i) => [slug, i]));
  return games
    .map((g, i) => ({ g, i }))
    .sort((a, b) => (rank.get(a.g.slug) ?? Infinity) - (rank.get(b.g.slug) ?? Infinity) || a.i - b.i)
    .map((x) => x.g);
}
