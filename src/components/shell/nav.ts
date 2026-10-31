import { Activity, ArrowLeftRight, Handshake, Award, Heart, BarChart3, Compass, Grid3x3, Eye, LayoutGrid, LineChart, Settings, TrendingUp } from "lucide-react";

export const NAV = [
  { href: "/", label: "Overview", icon: LineChart },
  { href: "/collection", label: "Collection", icon: LayoutGrid },
  { href: "/master-sets", label: "Master Sets", icon: Grid3x3 },
  { href: "/grading", label: "Grading", icon: Award },
  { href: "/explore", label: "Explore", icon: Compass },
  { href: "/watchlist", label: "Watchlist", icon: Eye },
  { href: "/wishlist", label: "Wishlist", icon: Heart },
  { href: "/trade", label: "Trade", icon: ArrowLeftRight },
  { href: "/deal", label: "Deal", icon: Handshake },
  { href: "/gains", label: "Gains", icon: TrendingUp },
  { href: "/analytics", label: "Analytics", icon: BarChart3 },
  { href: "/activity", label: "Activity", icon: Activity },
  { href: "/settings", label: "Settings", icon: Settings },
] as const;

export type NavItem = (typeof NAV)[number];

const byHref = (href: string) => NAV.find((n) => n.href === href)!;

/** Sidebar sections. Settings sits on its own at the bottom. */
export const NAV_GROUPS: { label: string | null; items: NavItem[] }[] = [
  { label: null, items: ["/", "/collection", "/master-sets", "/grading"].map(byHref) },
  { label: "Market", items: ["/explore", "/watchlist", "/wishlist", "/trade", "/deal"].map(byHref) },
  { label: "Insights", items: ["/gains", "/analytics", "/activity"].map(byHref) },
];

export const SETTINGS = byHref("/settings");

/** Phone bottom tabs (left pair, add button, right pair). */
export const MOBILE_TABS = { left: ["/", "/collection"].map(byHref), right: ["/explore", "/trade"].map(byHref) };

/** Everything else on phones, in the top bar's menu. */
export const MOBILE_MENU = NAV_GROUPS.flatMap((g) => g.items.map((item) => ({ ...item, group: g.label }))).filter(
  (n) => ![...MOBILE_TABS.left, ...MOBILE_TABS.right].some((t) => t.href === n.href),
);

export function isActive(pathname: string, href: string) {
  if (href === "/") return pathname === "/";
  return pathname === href || pathname.startsWith(`${href}/`);
}
