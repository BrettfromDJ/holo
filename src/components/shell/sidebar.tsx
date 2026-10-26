"use client";

import { Plus } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { Button } from "@/components/ui/button";
import { useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";
import { Logo } from "./logo";
import { PortfolioSwitcher } from "@/components/portfolio/portfolio-controls";
import { ModeSwitcher } from "./mode-switcher";
import { NAV, isActive } from "./nav";

export function Sidebar() {
  const pathname = usePathname();
  const { openAdd } = useStore();
  return (
    <aside className="sticky top-0 hidden h-dvh w-[248px] shrink-0 flex-col border-r border-border px-4 py-6 lg:flex">
      <Link href="/" className="px-2.5">
        <Logo />
      </Link>
      <Button variant="primary" className="mt-8 w-full" onClick={() => openAdd()}>
        <Plus /> Add to Collection
      </Button>
      <nav className="mt-6 flex flex-col gap-0.5" aria-label="Primary">
        {NAV.map(({ href, label, icon: Icon }) => {
          const active = isActive(pathname, href);
          return (
            <Link
              key={href}
              href={href}
              aria-current={active ? "page" : undefined}
              className={cn(
                "flex h-10 items-center gap-3 rounded-xl px-3 text-[14px] font-medium transition-colors",
                active ? "bg-surface-2 text-foreground" : "text-muted hover:bg-surface hover:text-foreground",
              )}
            >
              <Icon className="size-[18px]" strokeWidth={active ? 2.2 : 1.8} />
              {label}
            </Link>
          );
        })}
      </nav>
      <div className="mt-auto space-y-2">
        <PortfolioSwitcher />
        <ModeSwitcher />
      </div>
    </aside>
  );
}
