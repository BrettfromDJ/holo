"use client";
import { createBrowserClient } from "@supabase/ssr";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { SUPABASE_ANON_KEY, SUPABASE_URL, isSupabaseConfigured } from "./config";
import type { Database } from "./database.types";

let browserClient: SupabaseClient<Database> | null = null;

export function getBrowserSupabase(): SupabaseClient<Database> | null {
  if (!isSupabaseConfigured()) return null;
  browserClient ??= createBrowserClient<Database>(SUPABASE_URL, SUPABASE_ANON_KEY);
  return browserClient;
}

let magicLinkClient: SupabaseClient<Database> | null = null;

/**
 * Client used only to *request* email sign-in links. @supabase/ssr always
 * uses PKCE, whose links only work in the browser (and origin) that asked
 * for them. Requesting with the implicit flow puts the session in the link
 * itself, so it completes wherever it's opened; /auth/finish then stores it
 * through the regular cookie-based client.
 */
export function getMagicLinkClient(): SupabaseClient<Database> | null {
  if (!isSupabaseConfigured()) return null;
  magicLinkClient ??= createClient<Database>(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { flowType: "implicit", persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  return magicLinkClient;
}
