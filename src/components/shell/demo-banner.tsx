"use client";

import { FlaskConical } from "lucide-react";
import { useStore } from "@/lib/store/collection-store";

/** Persistent reminder that everything on screen is sample data. */
export function DemoBanner() {
  const { mode, status, setMode } = useStore();
  if (mode !== "demo" || status === "loading") return null;
  return (
    <div className="mb-8 flex items-center gap-3 rounded-2xl bg-amber-100/70 px-4 py-3 text-[14px] dark:bg-amber-400/10">
      <FlaskConical className="size-4 shrink-0 text-amber-600 dark:text-amber-300" aria-hidden />
      <p className="min-w-0 flex-1 text-amber-900/80 dark:text-amber-100/75">
        <span className="font-semibold text-amber-900 dark:text-amber-200">Demo mode.</span> Products, prices and history are sample data — not live market prices.
      </p>
      <button onClick={() => setMode("personal")} className="shrink-0 rounded-full bg-white/80 px-3 py-1 font-semibold text-amber-900 hover:bg-white dark:bg-white/10 dark:text-amber-200">
        Use my collection
      </button>
    </div>
  );
}
