"use client";

import { usePathname } from "next/navigation";
import { Toaster } from "sonner";
import { ConfettiLayer } from "@/components/celebrate/confetti";
import { MilestoneWatcher } from "@/components/celebrate/milestone-watcher";
import { PullReveal } from "@/components/celebrate/pull-reveal";
import { AddProductDialog } from "@/components/flows/add-product-dialog";
import { TooltipProvider } from "@/components/ui/tooltip";
import { CollectionProvider } from "@/lib/store/collection-store";
import { ShelvesProvider } from "@/lib/store/shelves";
import { DemoBanner } from "./demo-banner";
import { BottomNav, MobileTopBar } from "./mobile-nav";
import { Sidebar } from "./sidebar";

const BARE_ROUTES = ["/login", "/auth", "/s/"];

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const bare = BARE_ROUTES.some((r) => pathname.startsWith(r));
  return (
    <CollectionProvider>
      <ShelvesProvider>
        <TooltipProvider delayDuration={200}>
          {bare ? (
            children
          ) : (
            <div className="flex min-h-dvh">
              <Sidebar />
              <div className="flex min-w-0 flex-1 flex-col">
                <MobileTopBar />
                <DemoBanner />
                <main className="mx-auto w-full max-w-[1200px] flex-1 overflow-x-clip px-4 pb-32 pt-6 sm:px-8 sm:pt-10 lg:pb-16">
                  {children}
                </main>
              </div>
              <BottomNav />
              <AddProductDialog />
              <PullReveal />
              <MilestoneWatcher />
            </div>
          )}
          <ConfettiLayer />
          <Toaster
            position="top-center"
            theme="dark"
            toastOptions={{
              classNames: {
                toast:
                  "!rounded-2xl !border-border !bg-surface-2 !text-foreground",
                description: "!text-muted",
              },
            }}
          />
        </TooltipProvider>
      </ShelvesProvider>
    </CollectionProvider>
  );
}
