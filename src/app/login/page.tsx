"use client";

import { ArrowLeft, Loader2, Mail } from "lucide-react";
import Link from "next/link";
import { useState } from "react";
import { Logo } from "@/components/shell/logo";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { getBrowserSupabase } from "@/lib/supabase/client";

export default function LoginPage() {
  const supabase = getBrowserSupabase();
  const [email, setEmail] = useState("");
  const [state, setState] = useState<"idle" | "sending" | "sent" | "error">("idle");
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!supabase) return;
    setState("sending");
    try {
      localStorage.setItem("holo:mode", "personal");
    } catch {
      // ignore
    }
    const { error } = await supabase.auth.signInWithOtp({ email, options: { emailRedirectTo: `${location.origin}/auth/callback` } });
    if (error) {
      setError(error.message);
      setState("error");
    } else setState("sent");
  };

  return (
    <main className="flex min-h-dvh flex-col items-center justify-center px-6">
      <div className="w-full max-w-sm animate-rise">
        <Logo className="mb-10" />
        {!supabase ? (
          <>
            <h1 className="text-[28px] font-semibold tracking-tight">Accounts aren&apos;t set up</h1>
            <p className="mt-2 text-[15px] text-muted">Add Supabase environment variables to enable sign-in. Until then, your collection is saved in this browser.</p>
          </>
        ) : state === "sent" ? (
          <>
            <div className="flex size-12 items-center justify-center rounded-2xl bg-surface-2">
              <Mail className="size-5" />
            </div>
            <h1 className="mt-6 text-[28px] font-semibold tracking-tight">Check your email</h1>
            <p className="mt-2 text-[15px] text-muted">We sent a sign-in link to {email}.</p>
          </>
        ) : (
          <form onSubmit={submit}>
            <h1 className="text-[28px] font-semibold tracking-tight">Sign in</h1>
            <p className="mt-2 text-[15px] text-muted">Sync your collection securely across devices.</p>
            <Input type="email" required autoFocus value={email} onChange={(e) => setEmail(e.target.value)} placeholder="you@example.com" className="mt-8" aria-label="Email" />
            {error && <p className="mt-2 text-[13px] text-down">{error}</p>}
            <Button type="submit" variant="primary" size="lg" className="mt-4 w-full" disabled={state === "sending"}>
              {state === "sending" && <Loader2 className="animate-spin" />}
              Email me a sign-in link
            </Button>
          </form>
        )}
        <Link href="/" className="mt-10 inline-flex items-center gap-1 text-[14px] text-muted hover:text-foreground">
          <ArrowLeft className="size-4" /> Back to Holo
        </Link>
      </div>
    </main>
  );
}
