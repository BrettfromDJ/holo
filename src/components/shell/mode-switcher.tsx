"use client";

import { Check, ChevronsUpDown, Cloud, FlaskConical, HardDrive } from "lucide-react";
import Link from "next/link";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { useStore } from "@/lib/store/collection-store";

export function ModeSwitcher() {
  const { mode, repoKind, user, integrations, setMode, signOut } = useStore();
  const current =
    mode === "demo"
      ? { icon: FlaskConical, title: "Demo collection", sub: "Sample data" }
      : repoKind === "cloud"
        ? { icon: Cloud, title: "My collection", sub: user?.email ?? "Synced" }
        : { icon: HardDrive, title: "My collection", sub: "Saved in this browser" };
  const Icon = current.icon;
  return (
    <DropdownMenu>
      <DropdownMenuTrigger className="flex w-full items-center gap-3 rounded-xl border border-border bg-surface px-3 py-2.5 text-left transition-colors hover:bg-surface-2">
        <span className="flex size-8 items-center justify-center rounded-lg bg-surface-2">
          <Icon className="size-4 text-muted" />
        </span>
        <span className="min-w-0 flex-1">
          <span className="block truncate text-[13px] font-medium">{current.title}</span>
          <span className="block truncate text-[12px] text-muted">{current.sub}</span>
        </span>
        <ChevronsUpDown className="size-4 text-subtle" />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="w-[216px]">
        <DropdownMenuLabel>Viewing</DropdownMenuLabel>
        <DropdownMenuItem onSelect={() => setMode("personal")}>
          {repoKind === "cloud" || user ? <Cloud /> : <HardDrive />} My collection
          {mode === "personal" && <Check className="ml-auto !text-foreground" />}
        </DropdownMenuItem>
        <DropdownMenuItem onSelect={() => setMode("demo")}>
          <FlaskConical /> Demo collection
          {mode === "demo" && <Check className="ml-auto !text-foreground" />}
        </DropdownMenuItem>
        {integrations.supabase && (
          <>
            <DropdownMenuSeparator />
            {user ? (
              <DropdownMenuItem onSelect={() => void signOut()}>Sign out</DropdownMenuItem>
            ) : (
              <DropdownMenuItem asChild>
                <Link href="/login">Sign in to sync</Link>
              </DropdownMenuItem>
            )}
          </>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
