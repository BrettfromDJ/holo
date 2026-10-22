"use client";

import { ArrowLeft, Loader2, Mail } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { Logo } from "@/components/shell/logo";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { getBrowserSupabase } from "@/lib/supabase/client";

const RESEND_SECONDS = 60;

/** Supabase's wording for its email cap is cryptic; say what it means. */
function friendly(message: string) {
  if (/rate limit|too many/i.test(message)) return "Too many sign-in emails were sent recently. Wait a little while and try again — or use the code from an email you already have.";
  return message;
}

export default function LoginPage() {
  const supabase = getBrowserSupabase();
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [state, setState] = useState<"idle" | "sending" | "sent" | "verifying">("idle");
  const [error, setError] = useState<string | null>(null);
  const [cooldown, setCooldown] = useState(0);

  // Errors handed back from /auth/callback (expired or already-used links, etc.).
  useEffect(() => {
    const e = new URLSearchParams(window.location.search).get("error");
    if (e) setError(friendly(e));
  }, []);

  useEffect(() => {
    if (cooldown <= 0) return;
    const t = setTimeout(() => setCooldown((c) => c - 1), 1000);
    return () => clearTimeout(t);
  }, [cooldown]);

  const send = async (e?: React.FormEvent) => {
    e?.preventDefault();
    if (!supabase || cooldown > 0) return;
    setState("sending");
    setError(null);
    try {
      localStorage.setItem("holo:mode", "personal");
    } catch {
      // ignore
    }
    const { error } = await supabase.auth.signInWithOtp({ email, options: { emailRedirectTo: `${location.origin}/auth/callback` } });
    if (error) {
      setError(friendly(error.message));
      setState(/rate limit|too many/i.test(error.message) ? "sent" : "idle");
    } else {
      setState("sent");
      setCooldown(RESEND_SECONDS);
    }
  };

  const verify = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!supabase) return;
    setState("verifying");
    setError(null);
    const { error } = await supabase.auth.verifyOtp({ email, token: code.trim(), type: "email" });
    if (error) {
      setError(friendly(error.message));
      setState("sent");
    } else router.replace("/");
  };

  return (
    <main className="flex min-h-dvh flex-col items-center justify-center px-6">
      <div className="w-full max-w-sm animate-rise">
        <Logo className="mb-10" />
        {!supabase ? (
          <>
            <h1 className="text-[24px] font-semibold tracking-tight">Accounts aren&apos;t set up</h1>
            <p className="mt-2 text-[14px] text-muted">Add Supabase environment variables to enable sign-in. Until then, your collection is saved in this browser.</p>
          </>
        ) : state === "sent" || state === "verifying" ? (
          <>
            <div className="flex size-11 items-center justify-center rounded-xl bg-surface-2">
              <Mail className="size-5" />
            </div>
            <h1 className="mt-6 text-[24px] font-semibold tracking-tight">Check your email</h1>
            <p className="mt-2 text-[14px] text-muted">
              We sent a sign-in link to {email}. Open it in this browser — or, if the email has a code, enter it below. You&apos;ll stay signed in on this device.
            </p>
            <form onSubmit={verify} className="mt-6">
              <Input
                inputMode="numeric"
                autoComplete="one-time-code"
                value={code}
                onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 10))}
                placeholder="Code from the email"
                aria-label="Sign-in code"
                className="tabular tracking-[0.2em]"
              />
              {error && <p className="mt-2 text-[13px] text-down">{error}</p>}
              <Button type="submit" variant="primary" size="lg" className="mt-3 w-full" disabled={code.length < 6 || state === "verifying"}>
                {state === "verifying" && <Loader2 className="animate-spin" />}
                Sign in with code
              </Button>
            </form>
            <button onClick={() => void send()} disabled={cooldown > 0} className="mt-4 text-[13px] text-muted hover:text-foreground disabled:opacity-50">
              {cooldown > 0 ? `Resend in ${cooldown}s` : "Resend email"}
            </button>
          </>
        ) : (
          <form onSubmit={send}>
            <h1 className="text-[24px] font-semibold tracking-tight">Sign in</h1>
            <p className="mt-2 text-[14px] text-muted">Sync your collection securely across devices.</p>
            <Input type="email" required autoFocus value={email} onChange={(e) => setEmail(e.target.value)} placeholder="you@example.com" className="mt-8" aria-label="Email" />
            {error && <p className="mt-2 text-[13px] text-down">{error}</p>}
            <Button type="submit" variant="primary" size="lg" className="mt-4 w-full" disabled={state === "sending"}>
              {state === "sending" && <Loader2 className="animate-spin" />}
              Email me a sign-in link
            </Button>
            {email && (
              <button type="button" onClick={() => setState("sent")} className="mt-4 text-[13px] text-muted hover:text-foreground">
                I already have a code
              </button>
            )}
          </form>
        )}
        <Link href="/" className="mt-10 inline-flex items-center gap-1 text-[13px] text-muted hover:text-foreground">
          <ArrowLeft className="size-4" /> Back to Holo
        </Link>
      </div>
    </main>
  );
}
