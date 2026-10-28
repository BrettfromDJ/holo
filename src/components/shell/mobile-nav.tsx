"use client";

import { Menu, Plus, Settings } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";
import { Logo } from "./logo";
import { MOBILE_MENU, MOBILE_TABS, SETTINGS, isActive, type NavItem } from "./nav";

/** Top bar on small screens: logo, settings, and a menu with every other destination. */
export function MobileTopBar() {
  const pathname = usePathname();
  const inMenu = MOBILE_MENU.some((n) => isActive(pathname, n.href));
  return (
    <header className="sticky top-0 z-30 flex h-[calc(3.5rem+env(safe-area-inset-top))] items-center pt-[env(safe-area-inset-top)] justify-between border-b border-border bg-background/85 px-4 backdrop-blur-xl lg:hidden">
      <Link href="/" aria-label="Overview">
        <Logo />
      </Link>
      <div className="flex items-center gap-1">
        <DropdownMenu>
          <DropdownMenuTrigger
            aria-label="More pages"
            className={cn("flex h-10 items-center gap-1.5 rounded-full px-3 text-[13px] font-medium", inMenu ? "bg-surface-2 text-foreground" : "text-muted")}
          >
            <Menu className="size-5" />
            {inMenu ? MOBILE_MENU.find((n) => isActive(pathname, n.href))?.label : "More"}
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-56">
            {MOBILE_MENU.map((n, i) => (
              <div key={n.href}>
                {n.group !== (MOBILE_MENU[i - 1]?.group ?? undefined) && (
                  <>
                    {i > 0 && <DropdownMenuSeparator />}
                    {n.group && <DropdownMenuLabel>{n.group}</DropdownMenuLabel>}
                  </>
                )}
                <DropdownMenuItem asChild>
                  <Link href={n.href} className={cn(isActive(pathname, n.href) && "bg-surface-2")}>
                    <n.icon className="size-4" /> {n.label}
                  </Link>
                </DropdownMenuItem>
              </div>
            ))}
          </DropdownMenuContent>
        </DropdownMenu>
        <Link
          href={SETTINGS.href}
          aria-label="Settings"
          aria-current={isActive(pathname, SETTINGS.href) ? "page" : undefined}
          className={cn("flex size-10 items-center justify-center rounded-full", isActive(pathname, SETTINGS.href) ? "bg-surface-2 text-foreground" : "text-muted")}
        >
          <Settings className="size-5" />
        </Link>
      </div>
    </header>
  );
}

/** Bottom tab bar with a prominent center add button. */
export function BottomNav() {
  const pathname = usePathname();
  const { openAdd } = useStore();
  const { left, right } = MOBILE_TABS;
  const Tab = ({ href, label, icon: Icon }: NavItem) => {
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
