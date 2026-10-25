import { Activity, BarChart3, BookOpen, Eye, LayoutGrid, LineChart, Settings, TrendingUp } from "lucide-react";

export const NAV = [
  { href: "/", label: "Overview", icon: LineChart },
  { href: "/collection", label: "Collection", icon: LayoutGrid },
  { href: "/binder", label: "Binder", icon: BookOpen },
  { href: "/gains", label: "Gains", icon: TrendingUp },
  { href: "/analytics", label: "Analytics", icon: BarChart3 },
  { href: "/watchlist", label: "Watchlist", icon: Eye },
  { href: "/activity", label: "Activity", icon: Activity },
  { href: "/settings", label: "Settings", icon: Settings },
] as const;

export function isActive(pathname: string, href: string) {
  if (href === "/") return pathname === "/";
  return pathname === href || pathname.startsWith(`${href}/`);
}
