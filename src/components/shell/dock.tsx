"use client";

import { Plus } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { Hint } from "@/components/ui/tooltip";
import { useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";
import { NAV, isActive } from "./nav";

/** Floating bottom dock — the app's primary navigation on every screen size. */
export function Dock() {
  const pathname = usePathname();
  const { openAdd } = useStore();
  return (
    <nav aria-label="Primary" className="pb-safe pointer-events-none fixed inset-x-0 bottom-0 z-40 flex justify-center px-3">
      <div className="pointer-events-auto mb-4 flex items-center gap-2">
        <div className="flex items-center gap-0.5 rounded-2xl border border-border-strong bg-dock p-1 shadow-2xl shadow-black/50 backdrop-blur-xl">
          {NAV.map(({ href, label, icon: Icon }) => {
            const active = isActive(pathname, href);
            return (
              <Hint key={href} content={label}>
                <Link
                  href={href}
                  aria-label={label}
                  aria-current={active ? "page" : undefined}
                  className={cn(
                    "flex size-9 items-center justify-center rounded-xl transition-colors",
                    active ? "bg-surface-3 text-foreground" : "text-muted hover:bg-surface-2 hover:text-foreground",
                  )}
                >
                  <Icon className="size-[17px]" strokeWidth={active ? 2.1 : 1.8} />
                </Link>
              </Hint>
            );
          })}
        </div>
        <Hint content="Add to collection">
          <button
            onClick={() => openAdd()}
            aria-label="Add to collection"
            className="flex size-11 items-center justify-center rounded-2xl border border-border-strong bg-dock text-foreground shadow-2xl shadow-black/50 backdrop-blur-xl transition-colors hover:bg-surface-3"
          >
            <Plus className="size-[18px]" />
          </button>
        </Hint>
      </div>
    </nav>
  );
}
