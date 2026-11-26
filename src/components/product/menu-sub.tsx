"use client";

import * as DropdownPrimitive from "@radix-ui/react-dropdown-menu";
import { ChevronRight } from "lucide-react";
import * as React from "react";
import { cn } from "@/lib/utils";

/**
 * A second page inside a ⋯ menu (Lists, Portfolios, picking a copy), styled like the shared
 * dropdown menu. The app's ActionsSheet opens these as a second page; on the web it's a submenu.
 */
export const MenuSub = DropdownPrimitive.Sub;

export function MenuSubTrigger({ className, children, ...props }: React.ComponentPropsWithoutRef<typeof DropdownPrimitive.SubTrigger>) {
  return (
    <DropdownPrimitive.SubTrigger
      className={cn(
        "flex cursor-default select-none items-center gap-2 rounded-lg px-2.5 py-2 text-sm outline-none data-[highlighted]:bg-surface-3 data-[state=open]:bg-surface-3 data-[disabled]:opacity-40 [&_svg]:size-4 [&_svg]:text-muted",
        className,
      )}
      {...props}
    >
      {children}
      <ChevronRight className="ml-auto" />
    </DropdownPrimitive.SubTrigger>
  );
}

export function MenuSubContent({ className, ...props }: React.ComponentPropsWithoutRef<typeof DropdownPrimitive.SubContent>) {
  return (
    <DropdownPrimitive.Portal>
      <DropdownPrimitive.SubContent
        sideOffset={6}
        collisionPadding={12}
        className={cn("z-50 min-w-[12rem] max-w-[18rem] rounded-xl border border-border bg-surface-2 p-1 shadow-xl shadow-black/30 data-[state=open]:animate-fade-in", className)}
        {...props}
      />
    </DropdownPrimitive.Portal>
  );
}
