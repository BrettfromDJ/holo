import { Compass, Eye, Handshake, Heart, House, LayoutGrid, Search, Settings } from "lucide-react";

/**
 * The five tabs, as in the app: Home, Collection, Search, Explore, Deal. Gains, Analytics,
 * Activity, Master sets, Grading and Your week live in Collection → Summary's places menu.
 */
export const NAV = [
  { href: "/", label: "Home", icon: House },
  { href: "/collection", label: "Collection", icon: LayoutGrid },
  { href: "/search", label: "Search", icon: Search },
  { href: "/explore", label: "Explore", icon: Compass },
  { href: "/deal", label: "Deal", icon: Handshake },
  { href: "/watchlist", label: "Watchlist", icon: Eye },
  { href: "/wishlist", label: "Wishlist", icon: Heart },
  { href: "/settings", label: "Settings", icon: Settings },
] as const;

export type NavItem = (typeof NAV)[number];

const byHref = (href: string) => NAV.find((n) => n.href === href)!;

/** The sidebar: the five tabs, then Settings on its own. */
export const TABS: NavItem[] = ["/", "/collection", "/search", "/explore", "/deal"].map(byHref);

export const SETTINGS = byHref("/settings");

/** Phone bottom tabs (left pair, Search in the middle, right pair). */
export const MOBILE_TABS = { left: ["/", "/collection"].map(byHref), right: ["/explore", "/deal"].map(byHref) };

/** The phone top bar's short menu: your lists (everything else is in Summary's places menu). */
export const MOBILE_MENU = ["/watchlist", "/wishlist"].map(byHref);

export function isActive(pathname: string, href: string) {
  if (href === "/") return pathname === "/";
  if (href.includes("?")) return false;
  return pathname === href || pathname.startsWith(`${href}/`);
}
