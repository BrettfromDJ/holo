"use client";

import { Check, Cloud, Download, FlaskConical, HardDrive, Moon, RefreshCw, Sun, SunMoon, X } from "lucide-react";
import Link from "next/link";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { PageHeader } from "@/components/shell/page-header";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Segmented } from "@/components/ui/segmented";
import { relativeTime } from "@/lib/format";
import { useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";

type Theme = "dark" | "light" | "system";

function applyTheme(t: Theme) {
  const light = t === "light" || (t === "system" && matchMedia("(prefers-color-scheme: light)").matches);
  document.documentElement.classList.toggle("light", light);
  document.documentElement.classList.toggle("dark", !light);
}

export default function SettingsPage() {
  const store = useStore();
  const [theme, setTheme] = useState<Theme>("dark");
  useEffect(() => {
    try {
      setTheme((localStorage.getItem("holo:theme") as Theme) ?? "dark");
    } catch {
      // ignore
    }
  }, []);

  const exportData = () => {
    const blob = new Blob([JSON.stringify({ exportedAt: new Date().toISOString(), mode: store.mode, transactions: store.data.transactions, watchlist: store.data.watchlist, products: store.data.products }, null, 2)], {
      type: "application/json",
    });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `holo-${store.mode}-${store.today}.json`;
    a.click();
    URL.revokeObjectURL(a.href);
  };

  return (
    <div className="max-w-2xl animate-fade-in">
      <PageHeader title="Settings" />

      <Section title="Collection">
        <Row
          title="Viewing"
          body={store.mode === "demo" ? "Sample data for exploring the app. Kept completely separate from your collection." : store.repoKind === "cloud" ? `Synced to your account (${store.user?.email})` : "Saved in this browser only. Sign in to sync across devices."}
        >
          <Segmented
            ariaLabel="Collection"
            value={store.mode}
            onChange={store.setMode}
            options={[
              { value: "personal", label: <>{store.repoKind === "cloud" ? <Cloud /> : <HardDrive />} Mine</> },
              { value: "demo", label: <><FlaskConical /> Demo</> },
            ]}
          />
        </Row>
        {store.integrations.supabase && (
          <Row title="Account" body={store.user ? `Signed in as ${store.user.email}` : "Sign in with email to sync your collection securely."}>
            {store.user ? (
              <Button variant="secondary" size="sm" onClick={() => void store.signOut()}>
                Sign out
              </Button>
            ) : (
              <Button variant="primary" size="sm" asChild>
                <Link href="/login">Sign in</Link>
              </Button>
            )}
          </Row>
        )}
        {store.mode === "demo" && (
          <Row title="Reset demo" body="Discard anything you've added to the demo sandbox.">
            <Button
              variant="secondary"
              size="sm"
              onClick={async () => {
                await store.resetDemo();
                toast.success("Demo reset");
              }}
            >
              Reset
            </Button>
          </Row>
        )}
        <Row title="Export" body="Download transactions, watchlist and catalog as JSON.">
          <Button variant="secondary" size="sm" onClick={exportData}>
            <Download /> Export
          </Button>
        </Row>
      </Section>

      <Section title="Appearance">
        <Row title="Theme" body="Holo is designed dark-first.">
          <Segmented
            ariaLabel="Theme"
            value={theme}
            onChange={(t) => {
              setTheme(t);
              try {
                localStorage.setItem("holo:theme", t);
              } catch {
                // ignore
              }
              applyTheme(t);
            }}
            options={[
              { value: "dark", label: <Moon />, title: "Dark" },
              { value: "light", label: <Sun />, title: "Light" },
              { value: "system", label: <SunMoon />, title: "System" },
            ]}
          />
        </Row>
        <Row title="Collection layout">
          <Segmented
            ariaLabel="Default layout"
            value={store.data.preferences.defaultView}
            onChange={(v) => void store.savePreferences({ defaultView: v })}
            options={[
              { value: "grid", label: "Grid" },
              { value: "list", label: "List" },
            ]}
          />
        </Row>
      </Section>

      <Section title="Integrations">
        <Row title="TCG API" body={store.integrations.tcgapi ? `Live catalog and prices · last refresh ${relativeTime(store.pricesRefreshedAt)}` : "Not configured. Set TCGAPI_KEY on the server to search and price real products."}>
          <span className="flex items-center gap-2">
            <Status ok={store.integrations.tcgapi} />
            {store.integrations.tcgapi && store.mode === "personal" && (
              <Button variant="secondary" size="sm" disabled={store.refreshing} onClick={() => void store.refreshPrices(true)}>
                <RefreshCw className={cn(store.refreshing && "animate-spin")} /> Refresh
              </Button>
            )}
          </span>
        </Row>
        <Row title="Supabase" body={store.integrations.supabase ? "Accounts, sync and daily snapshots enabled." : "Not configured. Your collection is saved in this browser."}>
          <Status ok={store.integrations.supabase} />
        </Row>
      </Section>

      <Section title="How performance is calculated">
        <div className="space-y-3 px-5 py-4 text-[14px] leading-relaxed text-muted">
          <p>
            <span className="font-medium text-foreground">Cost basis</span> is what you actually paid for items you still hold — unit price plus allocated shipping, fees and tax. Sales use first-in, first-out lots.
          </p>
          <p>
            <span className="font-medium text-foreground">Unrealized gain</span> is market value minus cost basis. Items without a market price are excluded rather than counted as $0.
          </p>
          <p>
            <span className="font-medium text-foreground">Daily change</span> only measures price movement on items you held at the previous close. Buying a $1,000 box worth $1,000 adds $1,000 of value and $0 of gain.
          </p>
          <p>
            <span className="font-medium text-foreground">Performance %</span> is a time-weighted return: daily market returns are chained together, so adding or selling inventory never distorts it.
          </p>
        </div>
      </Section>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="mb-8">
      <h2 className="mb-2 px-1 text-[13px] font-semibold text-muted">{title}</h2>
      <Card className="divide-y divide-border">{children}</Card>
    </section>
  );
}

function Row({ title, body, children }: { title: string; body?: string; children?: React.ReactNode }) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 px-5 py-4">
      <div className="min-w-0 flex-1">
        <p className="text-[15px] font-medium">{title}</p>
        {body && <p className="mt-0.5 text-[13px] text-muted">{body}</p>}
      </div>
      {children}
    </div>
  );
}

function Status({ ok }: { ok: boolean }) {
  return (
    <span className={cn("inline-flex items-center gap-1 rounded-full px-2 py-1 text-[12px] font-medium", ok ? "bg-up-soft text-up" : "bg-surface-2 text-muted")}>
      {ok ? <Check className="size-3.5" /> : <X className="size-3.5" />}
      {ok ? "Connected" : "Not set"}
    </span>
  );
}
