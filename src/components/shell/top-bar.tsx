"use client";

import { ChevronLeft, Plus } from "lucide-react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { useStore } from "@/lib/store/collection-store";
import { Logo } from "./logo";
import { ModeSwitcher } from "./mode-switcher";
import { sectionLabel } from "./nav";

function greeting(hour: number) {
  if (hour < 5) return "Good evening";
  if (hour < 12) return "Good morning";
  if (hour < 18) return "Good afternoon";
  return "Good evening";
}

/** Fey-style header: brand mark and section name on the left, account and add on the right. */
export function TopBar() {
  const pathname = usePathname();
  const router = useRouter();
  const { openAdd } = useStore();
  // Greeting depends on local time, so it's resolved after hydration.
  const [hello, setHello] = useState<string | null>(null);
  useEffect(() => setHello(greeting(new Date().getHours())), []);

  const isProduct = pathname.startsWith("/product/");
  const label = pathname === "/" && hello ? hello : sectionLabel(pathname);

  return (
    <header className="sticky top-0 z-30 bg-background/80 backdrop-blur-xl">
      <div className="mx-auto flex h-14 max-w-[1320px] items-center justify-between gap-3 px-4 sm:px-6">
        <div className="flex min-w-0 items-center gap-3">
          {isProduct ? (
            <button
              onClick={() => (window.history.length > 1 ? router.back() : router.push("/collection"))}
              aria-label="Back"
              className="flex size-7 items-center justify-center rounded-md text-muted transition-colors hover:bg-surface-2 hover:text-foreground"
            >
              <ChevronLeft className="size-4" />
            </button>
          ) : (
            <Link href="/" aria-label="Holo home">
              <Logo withWordmark={false} />
            </Link>
          )}
          <span className="truncate text-[15px] font-semibold tracking-tight">{label}</span>
        </div>
        <div className="flex items-center gap-2">
          <ModeSwitcher />
          <button
            onClick={() => openAdd()}
            className="hidden h-8 items-center gap-1.5 rounded-lg bg-surface-2 px-3 text-[13px] font-medium text-foreground transition-colors hover:bg-surface-3 sm:inline-flex"
          >
            <Plus className="size-3.5" /> Add
          </button>
        </div>
      </div>
    </header>
  );
}
