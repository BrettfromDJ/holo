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
      <DropdownMenuTrigger
        title={current.sub}
        className="flex h-8 max-w-[200px] items-center gap-2 rounded-lg px-2.5 text-left text-[13px] text-muted transition-colors hover:bg-surface-2 hover:text-foreground data-[state=open]:bg-surface-2"
      >
        <Icon className="size-3.5 shrink-0" />
        <span className="truncate">{current.title}</span>
        <ChevronsUpDown className="size-3.5 shrink-0 text-subtle" />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-[216px]">
        <p className="truncate px-2.5 pb-1 pt-1.5 text-[12px] text-muted">{current.sub}</p>
        <DropdownMenuSeparator />
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
