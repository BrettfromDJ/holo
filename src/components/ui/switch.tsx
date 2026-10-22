"use client";
import * as SwitchPrimitive from "@radix-ui/react-switch";
import * as React from "react";
import { cn } from "@/lib/utils";

export function Switch({ className, ...props }: React.ComponentPropsWithoutRef<typeof SwitchPrimitive.Root>) {
  return (
    <SwitchPrimitive.Root
      className={cn(
        "peer inline-flex h-[26px] w-[44px] shrink-0 cursor-pointer items-center rounded-full bg-surface-3 p-[2px] transition-colors data-[state=checked]:bg-up",
        className,
      )}
      {...props}
    >
      <SwitchPrimitive.Thumb className="block size-[22px] rounded-full bg-white shadow transition-transform duration-200 ease-[var(--ease-apple)] data-[state=checked]:translate-x-[18px]" />
    </SwitchPrimitive.Root>
  );
}
