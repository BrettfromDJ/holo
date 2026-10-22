"use client";

import { usePathname } from "next/navigation";
import { Toaster } from "sonner";
import { AddProductDialog } from "@/components/flows/add-product-dialog";
import { TooltipProvider } from "@/components/ui/tooltip";
import { CollectionProvider } from "@/lib/store/collection-store";
import { DemoBanner } from "./demo-banner";
import { BottomTabs } from "./bottom-tabs";
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
            <main className="mx-auto w-full max-w-[1180px] flex-1 px-5 pb-32 pt-6 sm:px-8 sm:pt-10 lg:pb-20">
              <DemoBanner />
              {children}
            </main>
            <BottomTabs />
            <AddProductDialog />
          </div>
        )}
        <Toaster
          position="top-center"
          theme="system"
          toastOptions={{ classNames: { toast: "!rounded-2xl !border-border !bg-surface !text-foreground !shadow-lift", description: "!text-muted" } }}
        />
      </TooltipProvider>
    </CollectionProvider>
  );
}
