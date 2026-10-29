"use client";

import { OptionAddPhoto, OptionCardBack, OptionCardOutline, OptionMonogram, OptionShape, OptionTitleCard, type PlaceholderProduct } from "@/components/lab/placeholder-options";
import { PageHeader } from "@/components/shell/page-header";

/** Prototype page: options for the image placeholder, each at list, grid and product-page sizes. */
const SAMPLES: PlaceholderProduct[] = [
  { name: "Prismatic Evolutions Elite Trainer Box", kind: "sealed", setName: "Prismatic Evolutions", productType: "Elite Trainer Box" },
  { name: "Surging Sparks Booster Box", kind: "sealed", setName: "Surging Sparks", productType: "Booster Box" },
  { name: "Paldean Fates Tin", kind: "sealed", setName: "Paldean Fates", productType: null },
  { name: "Umbreon VMAX (Alternate Full Art)", kind: "single", setName: "Evolving Skies", productType: "Cards" },
];

const OPTIONS = [
  { id: "A", name: "Card outline", note: "What's live now: one lime card shape for everything.", C: OptionCardOutline },
  { id: "B", name: "Shape by type", note: "A lime line drawing of what it is: card, ETB, booster box, tin, pack or bundle.", C: OptionShape },
  { id: "C", name: "Holo card back", note: "A branded card back, like flipping over a real card.", C: OptionCardBack },
  { id: "D", name: "Title card", note: "A lime proxy card with the product's name printed on it.", C: OptionTitleCard },
  { id: "E", name: "Monogram", note: "The set's initials in big display type.", C: OptionMonogram },
  { id: "F", name: "Add photo", note: "Says what's missing; would open a photo picker (not built yet).", C: OptionAddPhoto },
];

export default function PlaceholderLabPage() {
  return (
    <div>
      <PageHeader title="Placeholder lab" subtitle="Options for items without a photo, at list, grid and product-page sizes" />
      <div className="space-y-14">
        {OPTIONS.map(({ id, name, note, C }) => (
          <section key={id}>
            <p className="mb-4 flex flex-wrap items-baseline gap-x-3 gap-y-1">
              <span className="tag-skew tag-lime">{id}</span>
              <span className="font-display text-[20px] uppercase tracking-[0.01em]">{name}</span>
              <span className="text-[13px] text-muted">{note}</span>
            </p>
            <div className="flex flex-col gap-6 lg:flex-row lg:items-start">
              {/* List rows */}
              <ul className="w-full shrink-0 divide-y divide-white/[0.06] lg:w-[300px]">
                {SAMPLES.map((p) => (
                  <li key={p.name} className="flex items-center gap-3 py-2.5">
                    <div className="size-12 shrink-0 overflow-hidden rounded-xl bg-image-well">
                      <C product={p} compact />
                    </div>
                    <div className="min-w-0">
                      <p className="truncate text-[14px] font-medium">{p.name}</p>
                      <p className="truncate text-[12px] text-muted">{p.setName}</p>
                    </div>
                  </li>
                ))}
              </ul>
              {/* Grid tiles */}
              <div className="grid flex-1 grid-cols-2 gap-3 sm:grid-cols-4">
                {SAMPLES.map((p) => (
                  <div key={p.name} className="aspect-[5/7] overflow-hidden rounded-2xl bg-image-well">
                    <C product={p} />
                  </div>
                ))}
              </div>
              {/* Product page */}
              <div className="mx-auto aspect-square w-[220px] shrink-0 overflow-hidden rounded-3xl bg-image-well">
                <C product={SAMPLES[0]} />
              </div>
            </div>
          </section>
        ))}
      </div>
    </div>
  );
}
