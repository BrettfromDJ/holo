"use client";

import { ArrowRight, X } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { AnimatedNumber } from "@/components/motion/animated-number";
import { HoloTilt } from "@/components/motion/holo-tilt";
import { ProductImage } from "@/components/product/product-image";
import { Button } from "@/components/ui/button";
import { onPull, type PullEvent } from "@/lib/celebrate";
import { money, signedMoney } from "@/lib/format";
import { usePortfolio } from "@/lib/store/collection-store";

/**
 * Full-screen "pack pull" moment after a purchase is saved: the product
 * flips in with a foil sweep and the portfolio total counts up to its new
 * value. Click anywhere or press Escape to dismiss.
 */
export function PullReveal() {
  const [event, setEvent] = useState<PullEvent | null>(null);
  const { summary } = usePortfolio();
  const router = useRouter();

  useEffect(() => onPull(setEvent), []);

  useEffect(() => {
    if (!event) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setEvent(null);
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [event]);

  if (!event || typeof document === "undefined") return null;
  const added = summary.marketValue - event.before;

  return createPortal(
    <div
      role="dialog"
      aria-modal="true"
      aria-label={`Added ${event.product.name}`}
      className="fixed inset-0 z-[150] flex animate-fade-in items-center justify-center bg-background/80 p-6 backdrop-blur-xl"
      onClick={() => setEvent(null)}
    >
      <button aria-label="Close" className="absolute right-5 top-5 rounded-full p-2 text-muted hover:bg-surface-2 hover:text-foreground">
        <X className="size-5" />
      </button>
      <div className="flex w-full max-w-sm flex-col items-center text-center" onClick={(e) => e.stopPropagation()}>
        <div
          aria-hidden
          className="pointer-events-none absolute size-[520px] rounded-full opacity-60 blur-3xl"
          style={{ background: "radial-gradient(closest-side, rgb(160 120 255 / 0.25), rgb(80 200 255 / 0.12), transparent)" }}
        />
        <div className="animate-pull-in relative w-[240px] sm:w-[280px]">
          <HoloTilt max={16} radius="1.5rem" className="aspect-square w-full">
            <ProductImage product={event.product} size="xl" priority className="h-full w-full rounded-3xl shadow-2xl shadow-black/60 ring-1 ring-white/10" />
            <span
              aria-hidden
              className="animate-foil-sweep pointer-events-none absolute inset-0 rounded-3xl mix-blend-color-dodge"
              style={{
                background: "linear-gradient(110deg, transparent 20%, rgb(255 120 200 / 0.6) 35%, rgb(120 220 255 / 0.6) 50%, rgb(255 230 120 / 0.6) 65%, transparent 80%)",
                backgroundSize: "250% 100%",
              }}
            />
          </HoloTilt>
        </div>

        <p className="relative mt-8 animate-rise text-[12px] font-semibold uppercase tracking-[0.16em] text-muted" style={{ animationDelay: "500ms" }}>
          Added to your collection
        </p>
        <h2 className="relative mt-2 animate-rise text-balance text-[22px] font-semibold leading-tight" style={{ animationDelay: "600ms" }}>
          {event.quantity > 1 && <span className="text-muted">{event.quantity} × </span>}
          {event.product.name}
        </h2>

        <div className="relative mt-6 animate-rise" style={{ animationDelay: "750ms" }}>
          <p className="text-[12px] text-muted">Collection value</p>
          <p className="tabular mt-1 text-[40px] font-semibold leading-none tracking-[-0.03em]">
            <AnimatedNumber value={summary.marketValue} from={event.before} format={money} duration={1600} />
          </p>
          {Math.abs(added) >= 0.01 && <p className="tabular mt-1.5 text-[13px] text-up">{signedMoney(added)} at today&apos;s price</p>}
        </div>

        <div className="relative mt-8 flex animate-rise gap-2" style={{ animationDelay: "900ms" }}>
          <Button variant="secondary" onClick={() => setEvent(null)}>
            Done
          </Button>
          <Button
            variant="primary"
            onClick={() => {
              setEvent(null);
              router.push(`/product/${encodeURIComponent(event.product.id)}`);
            }}
          >
            View product <ArrowRight />
          </Button>
        </div>
      </div>
    </div>,
    document.body,
  );
}
