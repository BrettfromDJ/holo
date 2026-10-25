"use client";

import { Check, Copy, ExternalLink, Link2, Loader2, Trash2 } from "lucide-react";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { formatDate } from "@/lib/format";
import { useStore } from "@/lib/store/collection-store";
import type { ShareLinkRow } from "@/lib/supabase/database.types";
import { getBrowserSupabase } from "@/lib/supabase/client";

/** 24-character URL-safe random token (144 bits). */
function newToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(18));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/**
 * Create, copy and revoke read-only share links. Links are stored with RLS
 * (owner-only); the public page reads them server-side.
 */
export function ShareLinks() {
  const { repoKind, user, mode } = useStore();
  const supabase = getBrowserSupabase();
  const [links, setLinks] = useState<ShareLinkRow[] | null>(null);
  const [title, setTitle] = useState("");
  const [showGains, setShowGains] = useState(false);
  const [busy, setBusy] = useState(false);
  const [copied, setCopied] = useState<string | null>(null);
  const [setupError, setSetupError] = useState<string | null>(null);
  const enabled = mode === "personal" && repoKind === "cloud" && Boolean(user) && Boolean(supabase);

  const refresh = useCallback(async () => {
    if (!enabled || !supabase) return;
    const { data, error } = await supabase.from("share_links").select("*").is("revoked_at", null).order("created_at", { ascending: false });
    if (error) {
      setSetupError(/share_links/.test(error.message) ? "Run supabase/migrations/20261025000000_share_links.sql in Supabase to enable share links." : error.message);
      setLinks([]);
      return;
    }
    setSetupError(null);
    setLinks(data ?? []);
  }, [enabled, supabase]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const urlFor = (token: string) => `${location.origin}/s/${token}`;

  const create = async () => {
    if (!supabase || !user) return;
    setBusy(true);
    const { error } = await supabase.from("share_links").insert({ user_id: user.id, token: newToken(), title: title.trim() || null, show_gains: showGains });
    setBusy(false);
    if (error) return void toast.error("Couldn't create link", { description: error.message });
    setTitle("");
    toast.success("Share link created");
    void refresh();
  };

  const revoke = async (id: string) => {
    if (!supabase) return;
    const { error } = await supabase.from("share_links").update({ revoked_at: new Date().toISOString() }).eq("id", id);
    if (error) return void toast.error("Couldn't revoke link", { description: error.message });
    toast("Link revoked — it no longer works");
    void refresh();
  };

  const copy = async (token: string) => {
    try {
      await navigator.clipboard.writeText(urlFor(token));
      setCopied(token);
      setTimeout(() => setCopied(null), 1500);
    } catch {
      toast.error("Couldn't copy — select the link and copy it manually");
    }
  };

  if (!enabled) {
    return (
      <div className="px-5 py-4 text-[13px] text-muted">
        {mode === "demo" ? (
          "Switch to your collection to share it."
        ) : (
          <>
            Share links need a synced account.{" "}
            {supabase && (
              <Link href="/login" className="font-medium text-foreground underline-offset-4 hover:underline">
                Sign in
              </Link>
            )}
          </>
        )}
      </div>
    );
  }

  return (
    <div className="space-y-4 px-5 py-4">
      <p className="text-[13px] text-muted">
        Anyone with the link can see your collection&apos;s value and what you own. Purchase prices, history, notes and your email are never shown.
      </p>
      {setupError && <p className="rounded-xl bg-down-soft px-3 py-2 text-[13px] text-down">{setupError}</p>}

      <div className="space-y-3 rounded-2xl border border-border p-4">
        <Input value={title} onChange={(e) => setTitle(e.target.value.slice(0, 80))} placeholder="Title, e.g. Brett's sealed collection" aria-label="Share title" />
        <label className="flex items-center justify-between gap-3">
          <span>
            <span className="block text-[14px] font-medium">Show gains</span>
            <span className="block text-[12px] text-muted">Include unrealized gain and per-item % (reveals roughly what you paid).</span>
          </span>
          <Switch checked={showGains} onCheckedChange={setShowGains} aria-label="Show gains" />
        </label>
        <Button variant="primary" className="w-full" onClick={() => void create()} disabled={busy || Boolean(setupError)}>
          {busy ? <Loader2 className="animate-spin" /> : <Link2 />} Create share link
        </Button>
      </div>

      {links === null ? (
        <p className="text-[13px] text-muted">Loading…</p>
      ) : (
        links.map((l) => (
          <div key={l.id} className="flex items-center gap-2 rounded-xl bg-surface-2 px-3 py-2.5">
            <div className="min-w-0 flex-1">
              <p className="truncate text-[14px] font-medium">{l.title || "Collection"}</p>
              <p className="truncate font-mono text-[11px] text-subtle">{urlFor(l.token)}</p>
              <p className="text-[11px] text-subtle">
                Created {formatDate(l.created_at)} · {l.show_gains ? "shows gains" : "values only"}
              </p>
            </div>
            <Button variant="ghost" size="icon-sm" aria-label="Copy link" onClick={() => void copy(l.token)}>
              {copied === l.token ? <Check /> : <Copy />}
            </Button>
            <Button variant="ghost" size="icon-sm" aria-label="Open link" asChild>
              <a href={urlFor(l.token)} target="_blank" rel="noreferrer">
                <ExternalLink />
              </a>
            </Button>
            <Button variant="ghost" size="icon-sm" aria-label="Revoke link" onClick={() => void revoke(l.id)}>
              <Trash2 />
            </Button>
          </div>
        ))
      )}
    </div>
  );
}
