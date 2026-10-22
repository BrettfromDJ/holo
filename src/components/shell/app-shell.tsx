"use client";

import { usePathname } from "next/navigation";
import { Toaster } from "sonner";
import { AddProductDialog } from "@/components/flows/add-product-dialog";
import { TooltipProvider } from "@/components/ui/tooltip";
import { CollectionProvider } from "@/lib/store/collection-store";
import { DemoBanner } from "./demo-banner";
import { Dock } from "./dock";
import { TopBar } from "./top-bar";

const BARE_ROUTES = ["/login", "/auth"];

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const bare = BARE_ROUTES.some((r) => pathname.startsWith(r));
  return (
    <CollectionProvider>
      <TooltipProvider delayDuration={200}>
        {bare ? (
          children
        ) : (
          <div className="flex min-h-dvh flex-col">
            <TopBar />
            <div className="mx-auto w-full max-w-[1320px] flex-1 px-0 pb-28 sm:px-6">
              {/* The stage: one lifted panel that holds every page. */}
              <main className="min-h-[calc(100dvh-9rem)] border-y border-border bg-stage px-4 py-5 sm:rounded-[18px] sm:border sm:px-7 sm:py-7">
                <DemoBanner />
                {children}
              </main>
            </div>
            <Dock />
            <AddProductDialog />
          </div>
        )}
        <Toaster
          position="top-center"
          theme="dark"
          toastOptions={{ classNames: { toast: "!rounded-xl !border-border-strong !bg-surface-2 !text-foreground", description: "!text-muted" } }}
        />
      </TooltipProvider>
    </CollectionProvider>
  );
}
