"use client";

import { FlaskConical, Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useStore } from "@/lib/store/collection-store";

/** First-run state for an empty personal collection. */
export function EmptyCollection({ title = "Start your collection", body }: { title?: string; body?: string }) {
  const { openAdd, setMode } = useStore();
  return (
    <div className="flex flex-col items-center px-6 py-20 text-center animate-rise">
      <div className="relative mb-8 h-36 w-56">
        <div className="absolute left-4 top-6 h-28 w-20 -rotate-12 rounded-2xl bg-lilac shadow-card" />
        <div className="absolute right-4 top-6 h-28 w-20 rotate-12 rounded-2xl bg-peach shadow-card" />
        <div className="absolute left-1/2 top-0 flex h-32 w-24 -translate-x-1/2 items-center justify-center rounded-2xl bg-surface shadow-lift">
          <Plus className="size-8 text-brand" strokeWidth={2.5} />
        </div>
      </div>
      <h2 className="text-[28px] font-bold tracking-tight">{title}</h2>
      <p className="mt-2 max-w-sm text-[16px] text-muted">
        {body ?? "Add your first Pokémon card or sealed product. Holo tracks its market value and your true investment performance."}
      </p>
      <div className="mt-8 flex flex-wrap justify-center gap-3">
        <Button variant="brand" size="lg" onClick={() => openAdd()}>
          <Plus /> Add first product
        </Button>
        <Button variant="secondary" size="lg" onClick={() => setMode("demo")}>
          <FlaskConical /> Explore the demo
        </Button>
      </div>
    </div>
  );
}
