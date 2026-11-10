import type { Metadata } from "next";
import { Logo } from "@/components/shell/logo";

export const metadata: Metadata = { title: "Terms" };

/** Plain-language terms of use (shown in the app's Account → Terms). */
export default function TermsPage() {
  return (
    <main className="mx-auto w-full max-w-[720px] px-5 pb-24 pt-10">
      <Logo />
      <h1 className="mt-10 font-display text-[34px] leading-tight tracking-tight">Terms</h1>
      <p className="mt-2 text-[14px] text-muted">Last updated November 2026</p>
      <div className="mt-8 space-y-6 text-[15px] leading-relaxed text-white/80">
        <p>Dexora helps you track a trading card collection: what you own, what it&apos;s worth, and what you&apos;ve bought and sold.</p>
        <p>
          <strong className="text-white">Prices are estimates.</strong> Market values come from third-party pricing data and recent
          sales. They can be wrong or out of date. Don&apos;t rely on them as an appraisal, an offer, or financial advice.
        </p>
        <p>
          <strong className="text-white">Sales &amp; taxes is a guide.</strong> The profit figures and export are for your records,
          not tax advice. Check with an accountant.
        </p>
        <p>
          <strong className="text-white">Your content is yours.</strong> You&apos;re responsible for what you add and share, including
          list links you send to others.
        </p>
        <p>
          <strong className="text-white">Fair use.</strong> Don&apos;t misuse the service, such as by automated scraping or overloading
          scanning and price lookups.
        </p>
        <p>We may change these terms or the service; we&apos;ll update the date above when we do. You can delete your account at any time.</p>
      </div>
    </main>
  );
}
