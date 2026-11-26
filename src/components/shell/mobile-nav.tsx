"use client";

import { Menu, Search, Settings } from "lucide-react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";
import { Logo } from "./logo";
import { MOBILE_MENU, MOBILE_TABS, SETTINGS, isActive, type NavItem } from "./nav";

/** Top bar on small screens: logo, a short menu (your lists) and settings. Everything else is in Summary's places menu. */
export function MobileTopBar() {
  const pathname = usePathname();
  const inMenu = MOBILE_MENU.some((n) => isActive(pathname, n.href));
  return (
    <header className="sticky top-0 z-30 flex h-[calc(3.5rem+env(safe-area-inset-top))] items-center pt-[env(safe-area-inset-top)] justify-between border-b border-border bg-background/85 px-4 backdrop-blur-xl lg:hidden">
      <Link href="/" aria-label="Home">
        <Logo />
      </Link>
      <div className="flex items-center gap-1">
        <DropdownMenu>
          <DropdownMenuTrigger
            aria-label="Your lists"
            className={cn("flex h-10 items-center gap-1.5 rounded-full px-3 text-[13px] font-medium", inMenu ? "bg-surface-2 text-foreground" : "text-muted")}
          >
            <Menu className="size-5" />
            {inMenu ? MOBILE_MENU.find((n) => isActive(pathname, n.href))?.label : "Lists"}
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-48">
            {MOBILE_MENU.map((n) => (
              <DropdownMenuItem key={n.href} asChild>
                <Link href={n.href} className={cn(isActive(pathname, n.href) && "bg-surface-2")}>
                  <n.icon className="size-4" /> {n.label}
                </Link>
              </DropdownMenuItem>
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

/** Bottom tab bar, as in the app: Home, Collection, Search, Explore, Deal. */
export function BottomNav() {
  const pathname = usePathname();
  const router = useRouter();
  const { left, right } = MOBILE_TABS;
  const Tab = ({ href, label, icon: Icon }: NavItem) => {
    const active = isActive(pathname, href);
    return (
      <Link
        href={href}
        aria-current={active ? "page" : undefined}
        className={cn("flex flex-1 flex-col items-center gap-1 pt-2 text-[10px] font-medium transition-colors", active ? "text-foreground" : "text-subtle")}
      >
        <Icon className={cn("size-[22px]", active && "text-lime drop-shadow-[0_0_8px_var(--lime)]")} strokeWidth={active ? 2.2 : 1.7} />
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
        <div className="flex flex-1">
          <button
            type="button"
            onClick={() => {
              // Search everything (its own page, as in the app).
              router.push("/search");
            }}
            className="flex w-full flex-col items-center gap-1 pt-2 text-[10px] font-medium text-subtle transition-colors"
          >
            <Search className="size-[22px]" strokeWidth={1.7} />
            Search
          </button>
        </div>
        {right.map((n) => (
          <Tab key={n.href} {...n} />
        ))}
      </div>
    </nav>
  );
}
