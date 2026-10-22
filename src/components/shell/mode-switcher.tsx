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
        className="flex h-10 max-w-[190px] items-center gap-2 rounded-full bg-surface px-3.5 text-left text-[14px] font-medium shadow-card transition-colors hover:text-foreground data-[state=open]:bg-surface-2"
      >
        <Icon className="size-4 shrink-0 text-muted" />
        <span className="hidden truncate sm:inline">{current.title}</span>
        <ChevronsUpDown className="size-3.5 shrink-0 text-subtle" />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-[216px]">
        <p className="truncate px-3 pb-1.5 pt-2 text-[13px] text-muted">{current.sub}</p>
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
