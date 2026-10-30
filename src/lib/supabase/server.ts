import "server-only";
import { createServerClient } from "@supabase/ssr";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { User } from "@supabase/supabase-js";
import { cookies, headers } from "next/headers";
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
 * The signed-in user for this request, or null. The website signs in with
 * cookies; the iOS app sends its Supabase access token as
 * `Authorization: Bearer <token>`, which is verified with Supabase.
 */
export async function getRequestUser(): Promise<User | null> {
  if (!isSupabaseConfigured()) return null;
  const auth = (await headers()).get("authorization");
  const token = auth?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (token) {
    const client = createClient<Database>(SUPABASE_URL, SUPABASE_ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data } = await client.auth.getUser(token);
    return data.user ?? null;
  }
  const supabase = await getServerSupabase();
  return supabase ? ((await supabase.auth.getUser()).data.user ?? null) : null;
}

/**
 * Service-role client for trusted server jobs (catalog writes, price sync).
 * Bypasses RLS — never import from client code.
 */
export function getAdminSupabase(): SupabaseClient<Database> | null {
  // "service_role" (classic) or "secret" (newer) key — both bypass RLS.
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SECRET_KEY;
  if (!isSupabaseConfigured() || !key) return null;
  return createClient<Database>(SUPABASE_URL, key, { auth: { persistSession: false, autoRefreshToken: false } });
}
