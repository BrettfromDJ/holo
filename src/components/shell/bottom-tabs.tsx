"use client";

import { Plus } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";
import { NAV, isActive } from "./nav";

const PRIMARY = NAV.filter((n) => ["/", "/collection", "/analytics", "/watchlist"].includes(n.href));

/** Phone tab bar: four labelled tabs around a big coral Add button. */
export function BottomTabs() {
  const pathname = usePathname();
  const { openAdd } = useStore();
  const Tab = ({ href, label, icon: Icon }: (typeof PRIMARY)[number]) => {
    const active = isActive(pathname, href);
    return (
      <Link
        href={href}
        aria-current={active ? "page" : undefined}
        className={cn("flex flex-1 flex-col items-center gap-1 pt-2.5 text-[11px] font-semibold transition-colors", active ? "text-foreground" : "text-subtle")}
      >
        <Icon className="size-[22px]" strokeWidth={active ? 2.3 : 1.8} />
        {label}
      </Link>
    );
  };
  return (
    <nav aria-label="Primary" className="pb-safe fixed inset-x-0 bottom-0 z-40 border-t border-border bg-surface/95 backdrop-blur-xl lg:hidden">
      <div className="mx-auto flex h-[68px] max-w-md items-start px-2">
        {PRIMARY.slice(0, 2).map((n) => (
          <Tab key={n.href} {...n} />
        ))}
        <div className="flex flex-1 justify-center">
          <button
            onClick={() => openAdd()}
            aria-label="Add to collection"
            className="-mt-5 flex size-[58px] items-center justify-center rounded-full bg-brand text-brand-foreground shadow-[0_12px_24px_-8px_var(--brand)] ring-4 ring-background transition-transform active:scale-95"
          >
            <Plus className="size-7" strokeWidth={2.5} />
          </button>
        </div>
        {PRIMARY.slice(2).map((n) => (
          <Tab key={n.href} {...n} />
        ))}
      </div>
    </nav>
  );
}
