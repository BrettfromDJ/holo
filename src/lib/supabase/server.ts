import "server-only";
import { createServerClient } from "@supabase/ssr";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
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

/** Who is asking: enough to key their data and allowances by. */
export interface RequestUser {
  id: string;
  email?: string;
}

/**
 * One stateless client, kept across requests on a warm server, for checking the app's tokens.
 * With asymmetric signing keys the check is done here, against the project's public keys
 * (fetched once and remembered), so a scan no longer waits on a round trip to Supabase Auth.
 * Projects still on the legacy shared secret are checked with Supabase as before.
 */
let verifier: SupabaseClient<Database> | null = null;
function tokenVerifier(): SupabaseClient<Database> {
  verifier ??= createClient<Database>(SUPABASE_URL, SUPABASE_ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  return verifier;
}

/**
 * The signed-in user for this request, or null. The website signs in with
 * cookies; the iOS app sends its Supabase access token as
 * `Authorization: Bearer <token>`, which is verified here.
 */
export async function getRequestUser(): Promise<RequestUser | null> {
  if (!isSupabaseConfigured()) return null;
  const auth = (await headers()).get("authorization");
  const token = auth?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (token) {
    const { data, error } = await tokenVerifier().auth.getClaims(token);
    const claims = error ? null : data?.claims;
    if (!claims?.sub) return null;
    return { id: claims.sub, email: typeof claims.email === "string" ? claims.email : undefined };
  }
  const supabase = await getServerSupabase();
  const user = supabase ? ((await supabase.auth.getUser()).data.user ?? null) : null;
  return user ? { id: user.id, email: user.email } : null;
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
