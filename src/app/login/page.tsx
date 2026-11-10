"use client";

import { ArrowLeft, ArrowLeftRight, Loader2, Mail, ScanLine, TrendingUp } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { Logo } from "@/components/shell/logo";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { getBrowserSupabase, getMagicLinkClient } from "@/lib/supabase/client";

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
  // Codes only appear if the Supabase email template includes {{ .Token }}, so keep the entry tucked away.
  const [showCode, setShowCode] = useState(false);

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
    const { error } = await (getMagicLinkClient() ?? supabase).auth.signInWithOtp({ email, options: { emailRedirectTo: `${location.origin}/auth/callback` } });
    if (error) {
      setError(friendly(error.message));
      setState(/rate limit|too many/i.test(error.message) ? "sent" : "idle");
    } else {
      setState("sent");
      setCooldown(RESEND_SECONDS);
    }
  };

  // Sign in with Apple: Apple → Supabase → /auth/callback (which exchanges the code for a session).
  const apple = async () => {
    if (!supabase) return;
    setError(null);
    try {
      localStorage.setItem("holo:mode", "personal");
    } catch {
      // ignore
    }
    const { error } = await supabase.auth.signInWithOAuth({ provider: "apple", options: { redirectTo: `${location.origin}/auth/callback` } });
    if (error) setError(/provider|not enabled|unsupported/i.test(error.message) ? "Sign in with Apple isn't set up yet. Use email." : friendly(error.message));
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
    <main className="flex min-h-dvh flex-col items-center justify-center px-6 py-10">
      <div className="flex w-full max-w-4xl flex-col gap-10 lg:flex-row lg:items-center lg:gap-20">
      <ValueProps />
      <div className="w-full max-w-sm animate-rise lg:mx-0">
        <Logo className="mb-10" />
        {!supabase ? (
          <>
            <h1 className="text-[28px] font-semibold tracking-tight">Accounts aren&apos;t set up</h1>
            <p className="mt-2 text-[15px] text-muted">Add Supabase environment variables to enable sign-in. Until then, your collection is saved in this browser.</p>
          </>
        ) : state === "sent" || state === "verifying" ? (
          <>
            <div className="flex size-12 items-center justify-center rounded-2xl bg-surface-2">
              <Mail className="size-5" />
            </div>
            <h1 className="mt-6 text-[28px] font-semibold tracking-tight">Check your email</h1>
            <p className="mt-2 text-[15px] text-muted">
              We sent a sign-in link to {email}. Click <span className="text-foreground">Sign in</span> in that email — open it in this same browser and you&apos;ll stay signed in on this device.
            </p>
            {error && !showCode && <p className="mt-4 text-[13px] text-down">{error}</p>}
            {showCode ? (
              <form onSubmit={verify} className="mt-6">
                <Input
                  autoFocus
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
            ) : (
              <button onClick={() => setShowCode(true)} className="mt-6 block text-[13px] text-muted hover:text-foreground">
                Email has a code instead?
              </button>
            )}
            <button onClick={() => void send()} disabled={cooldown > 0} className="mt-3 block text-[13px] text-muted hover:text-foreground disabled:opacity-50">
              {cooldown > 0 ? `Resend in ${cooldown}s` : "Resend email"}
            </button>
          </>
        ) : (
          <form onSubmit={send}>
            <h1 className="text-[28px] font-semibold tracking-tight">Sign in</h1>
            <p className="mt-2 text-[15px] text-muted">Sync your collection securely across devices.</p>
            <Input type="email" required autoFocus value={email} onChange={(e) => setEmail(e.target.value)} placeholder="you@example.com" className="mt-8" aria-label="Email" />
            {error && <p className="mt-2 text-[13px] text-down">{error}</p>}
            <Button type="submit" variant="primary" size="lg" className="mt-4 w-full" disabled={state === "sending"}>
              {state === "sending" && <Loader2 className="animate-spin" />}
              Email me a sign-in link
            </Button>
            <div className="my-4 flex items-center gap-3 text-[12px] text-subtle">
              <span className="h-px flex-1 bg-border" />
              or
              <span className="h-px flex-1 bg-border" />
            </div>
            <Button type="button" variant="secondary" size="lg" className="w-full" onClick={() => void apple()}>
              <AppleMark /> Continue with Apple
            </Button>
            {email && (
              <button
                type="button"
                onClick={() => {
                  setShowCode(true);
                  setState("sent");
                }}
                className="mt-4 text-[13px] text-muted hover:text-foreground"
              >
                I already have a code
              </button>
            )}
          </form>
        )}
        <Link href="/" className="mt-10 inline-flex items-center gap-1 text-[14px] text-muted hover:text-foreground">
          <ArrowLeft className="size-4" /> Back to Dexora
        </Link>
      </div>
      </div>
    </main>
  );
}

/** What the app does, in three lines: beside the form on wide screens, above it on phones. */
function ValueProps() {
  const items = [
    { icon: <TrendingUp />, title: "See what your collection is worth", line: "Every card and box, priced daily, with how it has moved." },
    { icon: <ScanLine />, title: "Scan a card, know its price", line: "Point the camera at a card and its name and price appear on it." },
    { icon: <ArrowLeftRight />, title: "Deals, made easier", line: "Add what's coming in and going out; the cash and your profit are worked out for you." },
  ];
  return (
    <section aria-label="What Dexora does" className="w-full max-w-sm animate-rise lg:max-w-md">
      <h2 className="font-display text-[26px] font-semibold tracking-tight">Track what your cards are worth</h2>
      <ul className="mt-6 flex flex-col gap-3">
        {items.map((it) => (
          <li key={it.title} className="flex items-start gap-4 rounded-2xl border border-border bg-surface p-4 [&_svg]:size-5">
            <span className="flex size-10 shrink-0 items-center justify-center rounded-full bg-lime/15 text-lime">{it.icon}</span>
            <span>
              <span className="block text-[15px] font-semibold">{it.title}</span>
              <span className="mt-0.5 block text-[13px] text-muted">{it.line}</span>
            </span>
          </li>
        ))}
      </ul>
    </section>
  );
}

function AppleMark() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden className="fill-current">
      <path d="M16.37 12.73c-.02-2.3 1.88-3.4 1.96-3.45-1.07-1.56-2.73-1.78-3.32-1.8-1.41-.14-2.76.83-3.48.83-.72 0-1.83-.81-3-.79-1.54.02-2.97.9-3.76 2.28-1.61 2.79-.41 6.92 1.15 9.18.77 1.11 1.68 2.35 2.87 2.3 1.15-.04 1.59-.74 2.98-.74 1.39 0 1.78.74 3 .72 1.24-.02 2.03-1.13 2.79-2.24.88-1.29 1.24-2.54 1.26-2.6-.03-.01-2.42-.93-2.45-3.69ZM14.09 6c.63-.77 1.06-1.84.94-2.9-.91.04-2.01.6-2.66 1.37-.58.68-1.1 1.77-.96 2.81 1.01.08 2.05-.52 2.68-1.28Z" />
    </svg>
  );
}
