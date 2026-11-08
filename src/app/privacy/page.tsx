import type { Metadata } from "next";
import { Logo } from "@/components/shell/logo";

export const metadata: Metadata = { title: "Privacy" };

/** Plain-language privacy policy (shown in the app's Account → Privacy). */
export default function PrivacyPage() {
  return (
    <main className="mx-auto w-full max-w-[720px] px-5 pb-24 pt-10">
      <Logo />
      <h1 className="mt-10 font-display text-[34px] leading-tight tracking-tight">Privacy</h1>
      <p className="mt-2 text-[14px] text-muted">Last updated November 2026</p>
      <div className="mt-8 space-y-6 text-[15px] leading-relaxed text-white/80">
        <Section title="What we keep">
          Your account email, and what you add to Lucent: the cards and products you own, what you paid and sold them for,
          your lists, watchlist, wishlist, deals, notes, deal photos and settings. It&apos;s stored with our database provider
          (Supabase) so it syncs between the app and the website.
        </Section>
        <Section title="Scanning">
          When you scan a card, the photo is sent to our card recognition provider to identify it. We don&apos;t keep scan
          photos unless you attach one to a deal.
        </Section>
        <Section title="Prices">
          Market prices come from pricing services. Looking up a price sends the card&apos;s name or ID, never anything about you.
        </Section>
        <Section title="Notifications">
          If you allow notifications, we store your phone&apos;s notification token to send the alerts you&apos;ve switched on.
          Turn them off any time in Account or in your iPhone&apos;s Settings.
        </Section>
        <Section title="Sharing">
          Nothing is public unless you share it. A shared collection or list link shows only what that page says it shows,
          and you can turn a link off at any time.
        </Section>
        <Section title="What we don't do">
          We don&apos;t sell your data, show ads, or share your collection with anyone you haven&apos;t shared it with.
        </Section>
        <Section title="Deleting your data">
          Account → Delete account removes your account and everything in it, permanently. You can also export your data
          first from Account → Export your data.
        </Section>
      </div>
    </main>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section>
      <h2 className="mb-2 font-display text-[19px] tracking-tight text-white">{title}</h2>
      <p>{children}</p>
    </section>
  );
}
