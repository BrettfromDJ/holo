"use client";
/* eslint-disable @next/next/no-img-element -- images come from arbitrary pricing-source CDNs */
import { useEffect, useRef, useState } from "react";
import { categoryOf } from "@/lib/catalog";
import { isFoilCard } from "@/components/motion/holo-tilt";
import { bumperById, GLITTER_SPECKS, type Bumper } from "@/lib/bumpers";
import { gradeDescriptor, slabStyle } from "@/lib/graded";
import { useSlabBumpers, useSlabCerts } from "@/lib/store/grading";
import type { Grade, Product } from "@/lib/types";
import { cn } from "@/lib/utils";
import { ProductSilhouette } from "./product-silhouette";

/**
 * Product photography in a neutral "well". When a product has no image (or
 * it fails to load) we render a restrained, clearly-generic placeholder —
 * never a stand-in photo of a different product.
 */
export function ProductImage({
  product,
  className,
  size = "md",
  priority,
  frame = true,
  grade,
  slabKey,
  bumper,
}: {
  product:
    | (Pick<Product, "name" | "imageUrl" | "kind" | "setName" | "productType"> & Partial<Pick<Product, "number" | "rarity" | "cutoutUrl">>)
    | undefined;
  className?: string;
  size?: "xs" | "sm" | "md" | "lg" | "xl";
  priority?: boolean;
  /** False draws the image edge to edge with no well behind it (e.g. a bare card). */
  frame?: boolean;
  /** A graded card is drawn inside a slab with its grading label. */
  grade?: Grade | null;
  /** The holding this slab is, so it wears the bumper chosen for it. */
  slabKey?: string;
  /** Draw this bumper (e.g. a preview), overriding the saved one. */
  bumper?: Bumper | null;
}) {
  if (grade && slabKey && bumper === undefined) return <SavedBumperSlab slabKey={slabKey} product={product} grade={grade} size={size} priority={priority} className={className} />;
  if (grade) return <Slab product={product} grade={grade} size={size} priority={priority} className={className} bumper={bumper ?? null} />;
  return <ProductPhoto product={product} size={size} priority={priority} frame={frame} className={className} />;
}

function ProductPhoto({
  product,
  className,
  size,
  priority,
  frame,
}: {
  product: Parameters<typeof ProductImage>[0]["product"];
  className?: string;
  size: NonNullable<Parameters<typeof ProductImage>[0]["size"]>;
  priority?: boolean;
  frame: boolean;
}) {
  const [failed, setFailed] = useState(false);
  const imgRef = useRef<HTMLImageElement>(null);
  // Server-rendered images can fail before React attaches onError; catch that on mount.
  useEffect(() => {
    const img = imgRef.current;
    if (img && img.complete && img.naturalWidth === 0) setFailed(true);
  }, []);
  const pad = { xs: "p-1", sm: "p-1.5", md: "p-3", lg: "p-5", xl: "p-8" }[size];
  const showImage = product?.imageUrl && !failed;
  // Single cards are never framed: just the card, at its own shape, with rounded corners.
  const bare = Boolean(showImage) && (!frame || product?.kind === "single");

  return (
    <div
      className={cn(
        "relative flex items-center justify-center overflow-hidden",
        // A bare card keeps a real card's corner (a small share of its size); a fixed radius over-rounds small cards.
        bare ? "rounded-[4.5%/3.2%]" : "rounded-2xl bg-image-well",
        className,
      )}
    >
      {showImage && bare && product.kind === "single" ? (
        // A bare card gets a printed-card finish: grain, a fine print pattern, a sheen and an edge.
        <span className="relative inline-flex h-full max-w-full">
          <img
            ref={imgRef}
            src={product.imageUrl!}
            alt={product.name}
            loading={priority ? "eager" : "lazy"}
            decoding="async"
            onError={() => setFailed(true)}
            // Cover, not contain: scans are a hair wider than the card frame, and
            // letterboxing them would leave the texture and shine overhanging.
            className="h-full w-auto max-w-full rounded-[4.5%/3.2%] object-cover shadow-[0_8px_24px_rgba(0,0,0,0.45)] transition-transform duration-500 ease-[var(--ease-apple)]"
          />
          <span aria-hidden className={cn("card-texture pointer-events-none absolute inset-0 rounded-[4.5%/3.2%]", isFoilCard(product) && "is-foil")} />
        </span>
      ) : showImage ? (
        <img
          ref={imgRef}
          src={(product.kind === "sealed" && product.cutoutUrl) || product.imageUrl!}
          alt={product.name}
          loading={priority ? "eager" : "lazy"}
          decoding="async"
          onError={() => setFailed(true)}
          className={cn(
            "transition-transform duration-500 ease-[var(--ease-apple)]",
            bare
              ? "h-full w-auto max-w-full rounded-[4.5%/3.2%] object-contain shadow-[0_8px_24px_rgba(0,0,0,0.45)]"
              : cn(
                  "h-full w-full object-contain drop-shadow-[0_8px_16px_rgba(0,0,0,0.35)]",
                  pad,
                ),
          )}
        />
      ) : (
        <Placeholder product={product} size={size} />
      )}
    </div>
  );
}

function SavedBumperSlab({ slabKey, ...props }: { slabKey: string } & Omit<Parameters<typeof Slab>[0], "bumper" | "cert">) {
  const { bumpers } = useSlabBumpers();
  const { certs } = useSlabCerts();
  return <Slab {...props} bumper={bumperById(bumpers[slabKey])} cert={certs[slabKey]} />;
}

/** Faint wavy security print, like the fugitive-ink pattern on a PSA label. */
const SECURITY_INK =
  "url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='60' height='14'><path d='M0 7 Q7.5 1 15 7 T30 7 T45 7 T60 7' fill='none' stroke='%2378b6e0' stroke-opacity='0.35' stroke-width='0.7'/><path d='M0 11 Q7.5 5 15 11 T30 11 T45 11 T60 11' fill='none' stroke='%2378b6e0' stroke-opacity='0.2' stroke-width='0.6'/></svg>\")";

/** A PSA label: red trim, three uppercase lines on the left, number, grade and cert on the right, the PSA logo between. */
function PsaLabel({ product, grade, cert, tiny }: { product: Parameters<typeof ProductImage>[0]["product"]; grade: Grade; cert?: string; tiny: boolean }) {
  const lines = [product?.setName, product?.name, product?.rarity ?? (product?.kind === "single" ? "Holo" : null)].filter(Boolean) as string[];
  return (
    <div
      className={cn("relative shrink-0 overflow-hidden", tiny ? "h-[16cqw] rounded-[1.6cqw] p-[1.6cqw]" : "h-[29cqw] rounded-[1.8cqw] p-[1.5cqw]")}
      style={{ background: "linear-gradient(180deg, #e3262f, #c8141f)", boxShadow: "0 0.5cqw 1.5cqw rgb(0 0 0 / 0.35)" }}
    >
      <div
        className="relative h-full overflow-hidden rounded-[0.7cqw] text-[#161616]"
        style={{ background: `${SECURITY_INK} 0 0 / 14cqw 3.3cqw, linear-gradient(180deg, #fbfcfd, #eef3f6)` }}
      >
        {!tiny && (
          <div className="grid h-full grid-cols-[minmax(0,1fr)_auto] gap-x-[2cqw] px-[2.4cqw] pb-[1.2cqw] pt-[1.4cqw] font-sans font-medium uppercase leading-[1.08] tracking-[0.005em]">
            <div className="flex min-w-0 flex-col text-[4.2cqw]">
              {lines.map((l, i) => (
                <span key={i} className="truncate">
                  {l}
                </span>
              ))}
              <span
                aria-hidden
                className="mt-auto block h-[3.2cqw] w-[36%]"
                style={{ background: "repeating-linear-gradient(90deg, #161616 0 0.3cqw, transparent 0.3cqw 0.6cqw, #161616 0.6cqw 1.2cqw, transparent 1.2cqw 1.5cqw, #161616 1.5cqw 1.7cqw, transparent 1.7cqw 2.3cqw)" }}
              />
            </div>
            <div className="flex flex-col items-end text-right text-[4.2cqw]">
              {product?.number && <span className="truncate">#{product.number.split("/")[0]}</span>}
              <span>{gradeDescriptor(grade)}</span>
              <span>{grade.grade}</span>
              <span className="mt-auto tabular-nums">{cert ?? ""}</span>
            </div>
          </div>
        )}
        {/* The PSA logo, joined to the red trim below. */}
        {!tiny && (
          <span className="absolute bottom-0 left-1/2 flex h-[5.8cqw] w-[11cqw] -translate-x-1/2 items-center justify-center rounded-t-[0.6cqw] bg-gradient-to-b from-[#c9ced6] to-[#9aa3ae]">
            <span className="text-[3.8cqw] font-black italic leading-none tracking-[-0.04em] text-[#1d3f8f]">PSA</span>
          </span>
        )}
      </div>
    </div>
  );
}

/** The bumper around a slab: molded plastic (solid) or clear glitter (gradient). */
function BumperFrame({ bumper }: { bumper: Bumper }) {
  return (
    <div
      aria-hidden
      className="absolute inset-0 overflow-hidden rounded-[10cqw]"
      style={{
        background: bumper.background,
        opacity: bumper.kind === "glitter" ? 0.94 : 1,
        boxShadow: "inset 0 1.2cqw 1.6cqw rgb(255 255 255 / 0.45), inset 0 -1.6cqw 2.6cqw rgb(0 0 0 / 0.3), 0 4cqw 9cqw -2cqw rgb(0 0 0 / 0.7), 0 1cqw 2cqw rgb(0 0 0 / 0.35)",
      }}
    >
      {bumper.kind === "glitter" && <span className="absolute inset-0 mix-blend-screen" style={{ backgroundImage: GLITTER_SPECKS, backgroundSize: "34cqw 34cqw" }} />}
      {/* The lip the slab sits in. */}
      <span className="absolute inset-[4.2cqw] rounded-[7.5cqw] shadow-[inset_0_0_0_0.6cqw_rgb(0_0_0/0.25),0_0_1.5cqw_rgb(0_0_0/0.35)]" />
    </div>
  );
}

/**
 * A grading slab, drawn to scale with its own width (container units): a
 * thick clear case with a bevel and glare, a printed label (company, card,
 * grade and its wording, barcode) and the card in a recessed window.
 */
function Slab({
  product,
  grade,
  size,
  priority,
  className,
  bumper,
  cert,
}: {
  product: Parameters<typeof ProductImage>[0]["product"];
  grade: Grade;
  size: NonNullable<Parameters<typeof ProductImage>[0]["size"]>;
  priority?: boolean;
  className?: string;
  bumper: Bumper | null;
  /** Cert number printed on the label, when known. */
  cert?: string;
}) {
  const style = slabStyle(grade);
  const tiny = size === "xs" || size === "sm";
  const details = [product?.setName, product?.number ? `#${product.number}` : null].filter(Boolean).join(" · ");
  return (
    <div className={cn("relative flex items-center justify-center", className)} role="img" aria-label={`${product?.name ?? "Card"}, ${grade.company} ${grade.grade}`}>
      <div className="group/slab relative aspect-[5/8] h-full max-w-full [container-type:inline-size]">
        {bumper && <BumperFrame bumper={bumper} />}
        {/* With a bumper, the slab sits inside it and sizes to its own width. */}
        <div className={cn("absolute [container-type:inline-size]", bumper ? "inset-[5cqw]" : "inset-0")}>
        {/* The case: clear acrylic with a lit top edge and a darker base. */}
        <div
          className="absolute inset-0 rounded-[7cqw]"
          style={{
            background: "linear-gradient(155deg, rgb(255 255 255 / 0.26), rgb(255 255 255 / 0.08) 22%, rgb(255 255 255 / 0.04) 55%, rgb(255 255 255 / 0.14))",
            boxShadow:
              "inset 0 0 0 1px rgb(255 255 255 / 0.22), inset 0 1.5px 0 rgb(255 255 255 / 0.45), inset 0 -1.2cqw 3cqw rgb(0 0 0 / 0.35), 0 4cqw 9cqw -2cqw rgb(0 0 0 / 0.7), 0 1cqw 2cqw rgb(0 0 0 / 0.35)",
          }}
        />
        {/* The inner step where the insert sits. */}
        <div className="absolute inset-[2.2cqw] rounded-[5cqw] ring-1 ring-inset ring-white/10" />

        <div className={cn("absolute flex flex-col", tiny ? "inset-[6cqw] gap-[5cqw]" : "inset-[4.5cqw] gap-[3.5cqw]")}>
          {/* Label */}
          {grade.company.toUpperCase() === "PSA" ? (
            <PsaLabel product={product} grade={grade} cert={cert} tiny={tiny} />
          ) : (
            <div
              className={cn("relative shrink-0 overflow-hidden rounded-[2.4cqw]", tiny ? "h-[16cqw]" : "h-[27cqw]")}
              style={{ background: style.label, color: style.text, boxShadow: `inset 0 ${tiny ? "2.5cqw" : "1.1cqw"} 0 ${style.accent}, 0 0.5cqw 1.5cqw rgb(0 0 0 / 0.35)` }}
            >
              {!tiny && (
                <div className="flex h-full items-stretch gap-[3cqw] px-[4cqw] pb-[2.6cqw] pt-[3.4cqw]">
                  <div className="flex min-w-0 flex-1 flex-col">
                    <span className="text-[6.4cqw] font-black leading-none tracking-[-0.02em]" style={{ color: style.accent }}>
                      {grade.company}
                    </span>
                    <span className="mt-[1.6cqw] truncate text-[3.3cqw] font-bold uppercase leading-tight">{product?.name ?? "Card"}</span>
                    {details && <span className="truncate text-[2.8cqw] font-medium uppercase leading-tight opacity-60">{details}</span>}
                    {/* Barcode */}
                    <span
                      aria-hidden
                      className="mt-auto block h-[3cqw] w-[55%] opacity-70"
                      style={{ background: `repeating-linear-gradient(90deg, currentColor 0 0.35cqw, transparent 0.35cqw 0.7cqw, currentColor 0.7cqw 1.4cqw, transparent 1.4cqw 1.75cqw, currentColor 1.75cqw 1.95cqw, transparent 1.95cqw 2.6cqw)` }}
                    />
                  </div>
                  <div className="flex shrink-0 flex-col items-end justify-center text-right">
                    <span className="text-[2.9cqw] font-bold uppercase leading-none tracking-[0.04em] opacity-75">{gradeDescriptor(grade)}</span>
                    <span className="mt-[1cqw] text-[12cqw] font-black leading-[0.85] tracking-[-0.04em]">{grade.grade}</span>
                  </div>
                </div>
              )}
            </div>
          )}

          {/* Card window */}
          <div
            className="relative min-h-0 flex-1 rounded-[3cqw] p-[3.5cqw]"
            style={{ background: "linear-gradient(180deg, rgb(0 0 0 / 0.45), rgb(0 0 0 / 0.3))", boxShadow: "inset 0 0.8cqw 2.5cqw rgb(0 0 0 / 0.6), inset 0 0 0 1px rgb(255 255 255 / 0.06)" }}
          >
            <ProductPhoto product={product} size={size} priority={priority} frame={false} className="h-full w-full rounded-[2cqw]" />
          </div>
        </div>

        {/* Glare across the acrylic; drifts on hover. */}
        <div aria-hidden className="pointer-events-none absolute inset-0 overflow-hidden rounded-[7cqw]">
          <div
            className="absolute -inset-[40%] translate-x-[-12%] transition-transform duration-700 ease-[var(--ease-apple)] group-hover/slab:translate-x-[12%]"
            style={{ background: "linear-gradient(115deg, transparent 40%, rgb(255 255 255 / 0.13) 47%, rgb(255 255 255 / 0.04) 52%, transparent 58%)" }}
          />
        </div>
        </div>
      </div>
    </div>
  );
}

/** No image: a lime line drawing of what the product is, with the type and set underneath at larger sizes. */
function Placeholder({
  product,
  size,
}: {
  product: Parameters<typeof ProductImage>[0]["product"];
  size: string;
}) {
  const name = product?.name ?? "Product";
  const category = product
    ? categoryOf({
        name,
        productType: product.productType ?? null,
        kind: product.kind,
      })
    : "Card";
  if (size === "xs" || size === "sm") {
    return (
      <div className="flex h-full w-full items-center justify-center p-[18%]" role="img" aria-label={`${name} (no image available)`}>
        <div className="flex h-full w-full items-center justify-center">
          <ProductSilhouette category={category} />
        </div>
      </div>
    );
  }
  return (
    <div className="flex h-full w-full flex-col items-center justify-center gap-[7%] p-[12%]" role="img" aria-label={`${name} (no image available)`}>
      <div className="flex h-[46%] w-[72%] items-center justify-center">
        <ProductSilhouette category={category} />
      </div>
      <div className="max-w-full text-center">
        <p className="truncate text-[10px] font-medium font-mono uppercase tracking-[0.06em] text-subtle">{category}</p>
        <p className="mt-0.5 truncate text-[11px] text-muted">{product?.setName ?? name}</p>
      </div>
    </div>
  );
}
