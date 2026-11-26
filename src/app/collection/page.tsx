"use client";

import { Suspense, useCallback, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { CollectionSummary, RecapOpener } from "@/components/overview/collection-summary";
import { PlacesMenu } from "@/components/overview/places-menu";
import { WeeklyRecap } from "@/components/overview/weekly-recap";
import { CollectionCards } from "@/components/portfolio/collection-cards";
import { cn } from "@/lib/utils";

type Mode = "summary" | "cards";
const MODE_KEY = "collection-mode";

export default function CollectionPage() {
  return (
    <Suspense fallback={null}>
      <Collection />
    </Suspense>
  );
}

/**
 * Collection: Summary and Cards as two big titles in the page (the app's `CollectionTitles`):
 * the one you're on white, the other faded, remembered in this browser. `?view=summary` opens
 * Summary; a plain /collection opens Cards (the app's Router "collection").
 */
function Collection() {
  const params = useSearchParams();
  const router = useRouter();
  const asked = params.get("view") === "summary" || params.get("week") === "1" ? "summary" : params.get("view") === "cards" ? "cards" : null;
  const [mode, setModeState] = useState<Mode>(asked ?? "cards");
  const [recapOpen, setRecapOpen] = useState(false);
  const openRecap = useCallback(() => setRecapOpen(true), []);

  // A link that names a view wins; otherwise the one you were last on.
  useEffect(() => {
    if (asked) {
      setModeState(asked);
      return;
    }
    try {
      const saved = localStorage.getItem(MODE_KEY);
      if (saved === "summary" && !params.get("cat") && !params.get("kind") && !params.get("list") && !params.get("shelf") && !params.get("sort")) setModeState("summary");
    } catch {
      // Storage blocked: stay on Cards.
    }
    // Only when the link changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [asked]);

  const setMode = useCallback(
    (m: Mode) => {
      setModeState(m);
      try {
        localStorage.setItem(MODE_KEY, m);
      } catch {
        // Fine: it just won't be remembered.
      }
      window.scrollTo({ top: 0 });
      router.replace(m === "summary" ? "/collection?view=summary" : "/collection", { scroll: false });
    },
    [router],
  );
  const toCards = useCallback(() => setMode("cards"), [setMode]);

  return (
    <div>
      <div className="mb-4 flex min-h-11 items-center gap-[18px]">
        {(
          [
            ["summary", "Summary"],
            ["cards", "Cards"],
          ] as const
        ).map(([value, title]) => (
          <button
            key={value}
            type="button"
            aria-pressed={mode === value}
            onClick={() => mode !== value && setMode(value)}
            className={cn("font-display text-[32px] leading-none tracking-[-0.03em] transition-colors", mode === value ? "text-foreground" : "text-subtle hover:text-muted")}
          >
            {title}
          </button>
        ))}
        <span className="flex-1" />
        {mode === "summary" && <PlacesMenu onWeek={openRecap} onCards={toCards} />}
      </div>

      {mode === "summary" ? (
        <>
          <CollectionSummary onViewCards={toCards} />
          <RecapOpener onOpen={openRecap} />
        </>
      ) : (
        <CollectionCards />
      )}
      <WeeklyRecap open={recapOpen} onClose={() => setRecapOpen(false)} />
    </div>
  );
}
