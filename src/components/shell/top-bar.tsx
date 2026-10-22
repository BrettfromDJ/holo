"use client";

import { Activity, Plus, Settings, TrendingUp } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";
import { Logo } from "./logo";
import { ModeSwitcher } from "./mode-switcher";
import { NAV, isActive } from "./nav";

const TABS = NAV.filter((n) => n.href !== "/settings");

/** Airy header: logo, pill tabs in the middle (desktop), account and Add on the right. */
export function TopBar() {
  const pathname = usePathname();
  const { openAdd } = useStore();
  return (
    <header className="sticky top-0 z-30 bg-background/85 backdrop-blur-xl">
      <div className="mx-auto flex h-16 max-w-[1180px] items-center justify-between gap-4 px-5 sm:px-8">
        <Link href="/" aria-label="Holo home" className="shrink-0">
          <Logo />
        </Link>

        <nav aria-label="Primary" className="hidden items-center gap-1 rounded-full bg-surface p-1 shadow-card lg:flex">
          {TABS.map(({ href, label }) => {
            const active = isActive(pathname, href);
            return (
              <Link
                key={href}
                href={href}
                aria-current={active ? "page" : undefined}
                className={cn(
                  "rounded-full px-4 py-2 text-[14px] font-medium transition-colors",
                  active ? "bg-accent text-accent-foreground" : "text-muted hover:bg-surface-2 hover:text-foreground",
                )}
              >
                {label}
              </Link>
            );
          })}
        </nav>

        <div className="flex items-center gap-1.5">
          <div className="flex items-center gap-0.5 lg:hidden">
            {[
              { href: "/gains", label: "Gains", icon: TrendingUp },
              { href: "/activity", label: "Activity", icon: Activity },
            ].map(({ href, label, icon: Icon }) => (
              <Link
                key={href}
                href={href}
                aria-label={label}
                aria-current={isActive(pathname, href) ? "page" : undefined}
                className={cn("flex size-10 items-center justify-center rounded-full", isActive(pathname, href) ? "bg-surface text-foreground shadow-card" : "text-muted")}
              >
                <Icon className="size-5" />
              </Link>
            ))}
          </div>
          <ModeSwitcher />
          <Link
            href="/settings"
            aria-label="Settings"
            aria-current={isActive(pathname, "/settings") ? "page" : undefined}
            className={cn(
              "flex size-10 items-center justify-center rounded-full transition-colors",
              isActive(pathname, "/settings") ? "bg-surface text-foreground shadow-card" : "text-muted hover:bg-surface hover:text-foreground",
            )}
          >
            <Settings className="size-5" />
          </Link>
          <button
            onClick={() => openAdd()}
            className="ml-1 hidden h-10 items-center gap-1.5 rounded-full bg-brand px-4 text-[14px] font-semibold text-brand-foreground shadow-[0_8px_20px_-8px_var(--brand)] transition-transform hover:-translate-y-px active:scale-[0.98] lg:inline-flex"
          >
            <Plus className="size-4" strokeWidth={2.5} /> Add item
          </button>
        </div>
      </div>
    </header>
  );
}
