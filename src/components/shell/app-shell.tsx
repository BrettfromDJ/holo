"use client";

import { usePathname } from "next/navigation";
import { Toaster } from "sonner";
import { MilestoneWatcher } from "@/components/celebrate/milestone-watcher";
import { PullReveal } from "@/components/celebrate/pull-reveal";
import { AddProductDialog } from "@/components/flows/add-product-dialog";
import { FirstRun } from "@/components/flows/first-run";
import { FadeRows } from "@/components/ui/fade-rows";
import { TooltipProvider } from "@/components/ui/tooltip";
import { CollectionProvider } from "@/lib/store/collection-store";
import { PortfoliosProvider } from "@/lib/store/portfolios";
import { ShelvesProvider } from "@/lib/store/shelves";
import { DemoBanner } from "./demo-banner";
import { BottomNav, MobileTopBar } from "./mobile-nav";
import { Sidebar } from "./sidebar";

const BARE_ROUTES = ["/login", "/auth", "/s/", "/w/"];

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const bare = BARE_ROUTES.some((r) => pathname.startsWith(r));
  return (
    <CollectionProvider>
      <PortfoliosProvider>
        <ShelvesProvider>
          <TooltipProvider delayDuration={200}>
            <FadeRows />
            {bare ? (
              children
            ) : (
              <div className="flex min-h-dvh">
                <Sidebar />
                <div className="flex min-w-0 flex-1 flex-col">
                  <MobileTopBar />
                  <DemoBanner />
                  <main className="hype mx-auto w-full max-w-[1200px] flex-1 overflow-x-clip px-4 pb-32 pt-6 sm:px-8 sm:pt-10 lg:pb-16">
                    {children}
                  </main>
                </div>
                <BottomNav />
                <AddProductDialog />
                <FirstRun />
                <PullReveal />
                <MilestoneWatcher />
              </div>
            )}
            <Toaster
              position="bottom-right"
              mobileOffset={{
                bottom: "calc(env(safe-area-inset-bottom) + 96px)",
              }}
              theme="dark"
              // Clickable (Undo) even while a modal sheet has turned off pointer events on the page.
              style={{ pointerEvents: "auto" }}
              toastOptions={{
                classNames: {
                  toast:
                    "!rounded-2xl !border-border !bg-surface-2 !text-foreground",
                  description: "!text-muted",
                  // Undo: plain lime text, no fill (like the app's undo toast).
                  actionButton: "!h-8 !rounded-full !bg-transparent !px-2 !text-[14px] !font-semibold !text-[var(--lime)] hover:!bg-foreground/[0.08]",
                },
              }}
            />
          </TooltipProvider>
        </ShelvesProvider>
      </PortfoliosProvider>
    </CollectionProvider>
  );
}
