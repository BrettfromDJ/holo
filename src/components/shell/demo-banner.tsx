"use client";

import { FlaskConical } from "lucide-react";
import { useStore } from "@/lib/store/collection-store";

/** Persistent reminder that everything on screen is sample data. */
export function DemoBanner() {
  const { mode, status, setMode } = useStore();
  if (mode !== "demo" || status === "loading") return null;
  return (
    <div className="mb-5 flex items-center gap-2.5 rounded-lg border border-amber-300/10 bg-amber-400/[0.05] px-3 py-2 text-[12px]">
      <FlaskConical className="size-3.5 shrink-0 text-amber-300" aria-hidden />
      <p className="min-w-0 flex-1 text-amber-100/70">
        <span className="font-medium text-amber-200">Demo mode.</span> Products, prices and history are sample data — not live market prices.
      </p>
      <button onClick={() => setMode("personal")} className="shrink-0 font-medium text-amber-200 underline-offset-4 hover:underline">
        Use my collection
      </button>
    </div>
  );
}
