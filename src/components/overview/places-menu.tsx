"use client";

import * as DropdownPrimitive from "@radix-ui/react-dropdown-menu";
import { Activity, Award, BarChart3, Compass, Eye, Grid3x3, Handshake, Heart, LayoutGrid, Menu, Play, Settings, type LucideIcon, Receipt } from "lucide-react";
import { useRouter } from "next/navigation";

type Place = { label: string; icon: LucideIcon; href?: string; run?: () => void };

/**
 * Summary's places menu (the app's `PlacesMenu`): a ☰ at the top right opening one glass panel
 * with every main place, in groups. Gains, Analytics, Activity, Master sets, Grading and Your
 * week live here instead of the sidebar.
 */
export function PlacesMenu({ onWeek, onCards }: { onWeek: () => void; onCards: () => void }) {
  const router = useRouter();
  const groups: Place[][] = [
    [
      { label: "Collection", icon: LayoutGrid, run: onCards },
      { label: "Explore", icon: Compass, href: "/explore" },
      { label: "Deal", icon: Handshake, href: "/deal" },
    ],
    [
      { label: "Your week", icon: Play, run: onWeek },
      { label: "Analytics", icon: BarChart3, href: "/analytics" },
      { label: "Grading", icon: Award, href: "/grading" },
      { label: "Master sets", icon: Grid3x3, href: "/master-sets" },
      { label: "Activity", icon: Activity, href: "/activity" },
      { label: "Sales & taxes", icon: Receipt, href: "/sales" },
      { label: "Watchlist", icon: Eye, href: "/watchlist" },
      { label: "Wishlist", icon: Heart, href: "/wishlist" },
    ],
    [{ label: "Account and settings", icon: Settings, href: "/settings" }],
  ];
  return (
    <DropdownPrimitive.Root modal={false}>
      <DropdownPrimitive.Trigger aria-label="Places" className="glass flex size-11 shrink-0 items-center justify-center rounded-full outline-none focus-visible:ring-2 focus-visible:ring-lime">
        <Menu className="size-[18px]" strokeWidth={2} />
      </DropdownPrimitive.Trigger>
      <DropdownPrimitive.Portal>
        <DropdownPrimitive.Content align="end" sideOffset={8} className="glass-panel z-50 w-[260px] rounded-[22px] py-1.5 outline-none data-[state=open]:animate-fade-in">
          {groups.map((items, g) => (
            <div key={g}>
              {g > 0 && <DropdownPrimitive.Separator className="my-1 h-px bg-foreground/10" />}
              {items.map((p) => (
                <DropdownPrimitive.Item
                  key={p.label}
                  onSelect={() => (p.run ? p.run() : p.href && router.push(p.href))}
                  className="flex h-[42px] cursor-default select-none items-center gap-3 px-4 text-[15px] font-medium outline-none data-[highlighted]:bg-foreground/10"
                >
                  <p.icon className="size-[16px] w-[22px] text-lime" strokeWidth={2} />
                  {p.label}
                </DropdownPrimitive.Item>
              ))}
            </div>
          ))}
        </DropdownPrimitive.Content>
      </DropdownPrimitive.Portal>
    </DropdownPrimitive.Root>
  );
}
