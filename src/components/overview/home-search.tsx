"use client";

import { ArrowRight, Check, Loader2, Search, X } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { useOwnedIds } from "@/components/explore/explore-items";
import { ProductImage } from "@/components/product/product-image";
import { useCatalogSearch } from "@/lib/explore/use-catalog-search";
import { money } from "@/lib/format";
import { cn } from "@/lib/utils";

const PREVIEW = 6;

/**
 * The big search on the home screen. Typing shows the top matches right
 * under it; Enter (or "See all") opens Explore with every result and its
 * filters. Press "/" anywhere on the page to jump into it.
 */
export function HomeSearch({ className }: { className?: string }) {
  const router = useRouter();
  const input = useRef<HTMLInputElement>(null);
  const box = useRef<HTMLDivElement>(null);
  const [query, setQuery] = useState("");
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(-1);
  const results = useCatalogSearch(query);
  const owned = useOwnedIds();
  const items = results?.status === "ready" ? results.data.slice(0, PREVIEW) : [];
  const all = `/explore?q=${encodeURIComponent(query.trim())}`;

  useEffect(() => setActive(-1), [results]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement;
      if (e.key === "/" && !t.closest("input, textarea, [contenteditable]")) {
        e.preventDefault();
        input.current?.focus();
      }
    };
    const onDown = (e: PointerEvent) => !box.current?.contains(e.target as Node) && setOpen(false);
    window.addEventListener("keydown", onKey);
    window.addEventListener("pointerdown", onDown);
    return () => {
      window.removeEventListener("keydown", onKey);
      window.removeEventListener("pointerdown", onDown);
    };
  }, []);

  const go = (href: string) => {
    setOpen(false);
    router.push(href);
  };

  return (
    <div ref={box} className={cn("relative z-30", className)}>
      <form
        role="search"
        onSubmit={(e) => {
          e.preventDefault();
          if (active >= 0 && items[active]) go(`/product/${encodeURIComponent(items[active].product.id)}`);
          else if (query.trim().length >= 2) go(all);
        }}
      >
        <Search className="pointer-events-none absolute left-5 top-[28px] size-5 -translate-y-1/2 text-subtle" />
        <input
          ref={input}
          value={query}
          onChange={(e) => {
            setQuery(e.target.value);
            setOpen(true);
          }}
          onFocus={() => setOpen(true)}
          onKeyDown={(e) => {
            if (e.key === "Escape") {
              setOpen(false);
              input.current?.blur();
            } else if (e.key === "ArrowDown" && items.length) {
              e.preventDefault();
              setActive((i) => Math.min(items.length - 1, i + 1));
            } else if (e.key === "ArrowUp" && items.length) {
              e.preventDefault();
              setActive((i) => Math.max(-1, i - 1));
            }
          }}
          enterKeyHint="search"
          placeholder="Search any card or sealed product"
          aria-label="Search cards and sealed products"
          aria-expanded={open && Boolean(results)}
          aria-controls="home-search-results"
          aria-activedescendant={active >= 0 ? `home-search-${active}` : undefined}
          role="combobox"
          autoComplete="off"
          className="h-14 w-full rounded-2xl border border-border bg-surface pl-[52px] pr-12 text-[16px] outline-none transition-colors placeholder:text-subtle focus:border-border-strong focus:bg-surface-2"
        />
        {query ? (
          <button
            type="button"
            onClick={() => {
              setQuery("");
              input.current?.focus();
            }}
            aria-label="Clear search"
            className="absolute right-4 top-[28px] -translate-y-1/2 rounded-full p-1 text-subtle hover:text-foreground"
          >
            <X className="size-4" />
          </button>
        ) : (
          <kbd className="pointer-events-none absolute right-4 top-[28px] hidden -translate-y-1/2 rounded-md border border-border px-1.5 font-mono text-[11px] text-subtle sm:block">/</kbd>
        )}
      </form>

      {open && results && (
        <div id="home-search-results" role="listbox" className="absolute inset-x-0 top-[calc(100%+6px)] overflow-hidden rounded-2xl border border-border bg-surface-2 shadow-2xl shadow-black/40 animate-fade-in">
          {results.status === "loading" && !items.length ? (
            <p className="flex items-center gap-2 px-4 py-4 text-[14px] text-muted">
              <Loader2 className="size-4 animate-spin" /> Searching…
            </p>
          ) : results.status === "error" ? (
            <p className="px-4 py-4 text-[14px] text-down">{results.message}</p>
          ) : !items.length ? (
            <p className="px-4 py-4 text-[14px] text-muted">Nothing in the catalog matches that yet.</p>
          ) : (
            <>
              <ul className="p-1.5">
                {items.map((item, i) => {
                  const p = item.product;
                  return (
                    <li key={p.id} id={`home-search-${i}`} role="option" aria-selected={active === i}>
                      <Link
                        href={`/product/${encodeURIComponent(p.id)}`}
                        onClick={() => setOpen(false)}
                        onMouseEnter={() => setActive(i)}
                        className={cn("flex items-center gap-3 rounded-xl px-2.5 py-2", active === i && "bg-surface-3")}
                      >
                        <ProductImage product={p} size="xs" className="h-12 w-9 shrink-0 rounded-md" />
                        <span className="min-w-0 flex-1">
                          <span className="block truncate text-[14px] font-medium">{p.name}</span>
                          <span className="block truncate text-[12px] text-muted">{[item.gameName, p.setName, p.number && `#${p.number}`].filter(Boolean).join(" · ")}</span>
                        </span>
                        {owned.has(p.id) && <Check className="size-3.5 shrink-0 text-muted" aria-label="Owned" />}
                        <span className="tabular shrink-0 text-[14px] font-semibold">{item.market === null ? <span className="font-normal text-subtle">No price</span> : money(item.market)}</span>
                      </Link>
                    </li>
                  );
                })}
              </ul>
              <Link href={all} onClick={() => setOpen(false)} className="flex items-center justify-between border-t border-border px-4 py-3 text-[13px] font-medium text-muted hover:text-foreground">
                <span className="tabular">{results.status === "ready" && results.data.length > PREVIEW ? `See all ${results.data.length} results with filters` : "Open in Explore with filters"}</span>
                <ArrowRight className="size-4" />
              </Link>
            </>
          )}
        </div>
      )}
    </div>
  );
}
