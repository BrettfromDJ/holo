"use client";

import { Activity, BookOpen, Compass, Plus, Settings } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";
import { Logo } from "./logo";
import { NAV, isActive } from "./nav";

const PRIMARY = NAV.filter((n) => ["/", "/collection", "/analytics", "/watchlist"].includes(n.href));

/** Compact top bar for secondary destinations on small screens. */
export function MobileTopBar() {
  const pathname = usePathname();
  return (
    <header className="sticky top-0 z-30 flex h-14 items-center justify-between border-b border-border bg-background/85 px-4 backdrop-blur-xl lg:hidden">
      <Link href="/" aria-label="Overview">
        <Logo />
      </Link>
      <div className="flex items-center gap-1">
        {[
          { href: "/explore", label: "Explore", icon: Compass },
          { href: "/binder", label: "Binder", icon: BookOpen },
          { href: "/activity", label: "Activity", icon: Activity },
          { href: "/settings", label: "Settings", icon: Settings },
        ].map(({ href, label, icon: Icon }) => (
          <Link
            key={href}
            href={href}
            aria-label={label}
            aria-current={isActive(pathname, href) ? "page" : undefined}
            className={cn("flex size-10 items-center justify-center rounded-full", isActive(pathname, href) ? "bg-surface-2 text-foreground" : "text-muted")}
          >
            <Icon className="size-5" />
          </Link>
        ))}
      </div>
    </header>
  );
}

/** Bottom tab bar with a prominent center add button. */
export function BottomNav() {
  const pathname = usePathname();
  const { openAdd } = useStore();
  const left = PRIMARY.slice(0, 2);
  const right = PRIMARY.slice(2);
  const Tab = ({ href, label, icon: Icon }: (typeof PRIMARY)[number]) => {
    const active = isActive(pathname, href);
    return (
      <Link
        href={href}
        aria-current={active ? "page" : undefined}
        className={cn("flex flex-1 flex-col items-center gap-1 pt-2 text-[10px] font-medium transition-colors", active ? "text-foreground" : "text-subtle")}
      >
        <Icon className="size-[22px]" strokeWidth={active ? 2.2 : 1.7} />
        {label}
      </Link>
    );
  };
  return (
    <nav
      aria-label="Primary"
      className="pb-safe fixed inset-x-0 bottom-0 z-40 border-t border-border bg-background/90 backdrop-blur-xl lg:hidden"
    >
      <div className="mx-auto flex h-16 max-w-md items-start px-2">
        {left.map((n) => (
          <Tab key={n.href} {...n} />
        ))}
        <div className="flex flex-1 justify-center">
          <button
            onClick={() => openAdd()}
            aria-label="Add to collection"
            className="-mt-3 flex size-14 items-center justify-center rounded-full bg-accent text-accent-foreground shadow-lg shadow-black/40 transition-transform active:scale-95"
          >
            <Plus className="size-6" strokeWidth={2.4} />
          </button>
        </div>
        {right.map((n) => (
          <Tab key={n.href} {...n} />
        ))}
      </div>
    </nav>
  );
}
