"use client";

import { Loader2 } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect } from "react";
import { Logo } from "@/components/shell/logo";
import { getBrowserSupabase } from "@/lib/supabase/client";

/**
 * Lands implicit-flow sign-in links: the session arrives in the URL fragment
 * (#access_token=…&refresh_token=…). Store it through the cookie-based client
 * so the server and every page see the user as signed in, then go home.
 */
export default function FinishSignIn() {
  const router = useRouter();

  useEffect(() => {
    const params = new URLSearchParams(window.location.hash.slice(1));
    const fail = (message: string) => router.replace(`/login?error=${encodeURIComponent(message)}`);
    const error = params.get("error_description") ?? params.get("error");
    if (error) return void fail(error);

    const access_token = params.get("access_token");
    const refresh_token = params.get("refresh_token");
    const supabase = getBrowserSupabase();
    if (!supabase) return void fail("Accounts aren't configured on this deployment.");
    if (!access_token || !refresh_token) return void fail("The sign-in link was incomplete. Request a new one.");

    supabase.auth.setSession({ access_token, refresh_token }).then(({ error: e }) => {
      if (e) return fail(e.message);
      try {
        localStorage.setItem("holo:mode", "personal");
      } catch {
        // ignore
      }
      history.replaceState(null, "", "/auth/finish");
      // Full navigation so the app loads fresh with the new session.
      window.location.replace("/");
    });
  }, [router]);

  return (
    <main className="flex min-h-dvh flex-col items-center justify-center gap-6 px-6">
      <Logo />
      <p className="flex items-center gap-2 text-[15px] text-muted">
        <Loader2 className="size-4 animate-spin" /> Signing you in…
      </p>
    </main>
  );
}
