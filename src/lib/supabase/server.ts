import "server-only";
import { createServerClient } from "@supabase/ssr";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { cookies } from "next/headers";
import { SUPABASE_ANON_KEY, SUPABASE_URL, isSupabaseConfigured } from "./config";
import type { Database } from "./database.types";

/** Supabase client bound to the signed-in user's session (RLS applies). */
export async function getServerSupabase(): Promise<SupabaseClient<Database> | null> {
  if (!isSupabaseConfigured()) return null;
  const store = await cookies();
  return createServerClient<Database>(SUPABASE_URL, SUPABASE_ANON_KEY, {
    cookies: {
      getAll: () => store.getAll(),
      setAll: (list) => {
        try {
          for (const { name, value, options } of list) store.set(name, value, options);
        } catch {
          // Called from a Server Component; middleware refreshes the session.
        }
      },
    },
  });
}

/**
 * Service-role client for trusted server jobs (catalog writes, price sync).
 * Bypasses RLS — never import from client code.
 */
export function getAdminSupabase(): SupabaseClient<Database> | null {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!isSupabaseConfigured() || !key) return null;
  return createClient<Database>(SUPABASE_URL, key, { auth: { persistSession: false, autoRefreshToken: false } });
}
