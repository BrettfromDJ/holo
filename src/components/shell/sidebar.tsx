"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import { Logo } from "./logo";
import { ModeSwitcher } from "./mode-switcher";
import { SETTINGS, TABS, isActive, type NavItem } from "./nav";

/**
 * Wide screens: a slim list of the app's five tabs plus Settings. No add button (adding happens
 * on a card's page) and no portfolio switcher (it sits on Collection's Summary).
 */
export function Sidebar() {
  const pathname = usePathname();
  return (
    <aside className="sticky top-0 hidden h-dvh w-[232px] shrink-0 flex-col border-r border-border px-4 py-6 lg:flex">
      <Link href="/" className="px-2.5">
        <Logo />
      </Link>
      <nav className="scrollbar-none -mx-1 mt-8 flex min-h-0 flex-col gap-0.5 overflow-y-auto px-1 pb-4" aria-label="Primary">
        {TABS.map((item) => (
          <NavLink key={item.href} item={item} active={isActive(pathname, item.href)} />
        ))}
        <div className="my-3 h-px bg-border" />
        <NavLink item={SETTINGS} active={isActive(pathname, SETTINGS.href)} />
      </nav>
      <div className="mt-auto shrink-0 pt-2">
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
      className={cn("flex h-10 items-center gap-3 rounded-xl px-3 text-[15px] font-medium transition-colors", active ? "nav-active text-foreground" : "text-muted hover:bg-surface hover:text-foreground")}
    >
      <Icon className={cn("size-[18px]", active && "text-lime drop-shadow-[0_0_6px_var(--lime)]")} strokeWidth={active ? 2.2 : 1.8} />
      {label}
    </Link>
  );
}
