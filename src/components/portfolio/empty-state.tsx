"use client";

import { FlaskConical, Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useStore } from "@/lib/store/collection-store";

/** An empty collection, on each page: a short title, one line and one action (like the app). */
export function EmptyCollection({ title = "Nothing here yet", body, action = "Add a card" }: { title?: string; body?: string; action?: string }) {
  const { openAdd, setMode } = useStore();
  return (
    <div className="flex flex-col items-center px-6 py-20 text-center animate-rise">
      <div className="relative mb-8 h-36 w-56">
        <div className="absolute left-4 top-6 h-28 w-20 -rotate-12 rounded-xl border border-border bg-surface-2" />
        <div className="absolute right-4 top-6 h-28 w-20 rotate-12 rounded-xl border border-border bg-surface-2" />
        <div className="absolute left-1/2 top-0 flex h-32 w-24 -translate-x-1/2 items-center justify-center rounded-xl border border-border-strong bg-surface-3 shadow-2xl shadow-black/40">
          <Plus className="size-7 text-muted" />
        </div>
      </div>
      <h2 className="text-[22px] font-semibold tracking-tight">{title}</h2>
      <p className="mt-2 max-w-sm text-[15px] text-muted">{body ?? "Add a card or sealed product to see what it's worth."}</p>
      <div className="mt-8 flex flex-wrap justify-center gap-3">
        <Button variant="lime" size="lg" onClick={() => openAdd()}>
          <Plus /> {action}
        </Button>
        <Button variant="secondary" size="lg" onClick={() => setMode("demo")}>
          <FlaskConical /> Explore the demo
        </Button>
      </div>
    </div>
  );
}
