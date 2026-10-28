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
import { NAV_GROUPS, SETTINGS, isActive, type NavItem } from "./nav";

export function Sidebar() {
  const pathname = usePathname();
  const { openAdd } = useStore();
  return (
    <aside className="sticky top-0 hidden h-dvh w-[248px] shrink-0 flex-col border-r border-border px-4 py-6 lg:flex">
      <Link href="/" className="px-2.5">
        <Logo />
      </Link>
      <Button variant="lime" size="lg" className="mt-8 w-full" onClick={() => openAdd()}>
        <Plus /> Add to Collection
      </Button>
      <nav className="scrollbar-none -mx-1 mt-6 flex min-h-0 flex-col gap-5 overflow-y-auto px-1 pb-4" aria-label="Primary">
        {NAV_GROUPS.map((group) => (
          <div key={group.label ?? "main"} className="flex flex-col gap-0.5">
            {group.label && <p className="mb-1 px-3 text-[11px] font-medium font-mono uppercase tracking-[0.06em] text-subtle">{group.label}</p>}
            {group.items.map((item) => (
              <NavLink key={item.href} item={item} active={isActive(pathname, item.href)} />
            ))}
          </div>
        ))}
        <NavLink item={SETTINGS} active={isActive(pathname, SETTINGS.href)} />
      </nav>
      <div className="mt-auto shrink-0 space-y-2 pt-2">
        <PortfolioSwitcher />
        <ModeSwitcher />
      </div>
    </aside>
  );
}

function NavLink({ item: { href, label, icon: Icon }, active }: { item: NavItem; active: boolean }) {
  return (
    <Link
      href={href}
      aria-current={active ? "page" : undefined}
      className={cn("flex h-9 items-center gap-3 rounded-xl px-3 text-[14px] font-medium transition-colors", active ? "nav-active text-foreground" : "text-muted hover:bg-surface hover:text-foreground")}
    >
      <Icon className={cn("size-[18px]", active && "text-lime drop-shadow-[0_0_6px_var(--lime)]")} strokeWidth={active ? 2.2 : 1.8} />
      {label}
    </Link>
  );
}
