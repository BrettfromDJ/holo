import { cn } from "@/lib/utils";

export function PageHeader({ title, subtitle, actions, className }: { title: string; subtitle?: React.ReactNode; actions?: React.ReactNode; className?: string }) {
  return (
    <header className={cn("relative isolate mb-8 flex flex-wrap items-end justify-between gap-4", className)}>
      {/* Lit grid and a drifting glow behind every page title. It stops in the gap below the header:
          the header paints above the content that follows, so a taller glow would show through the cards. */}
      <div aria-hidden className="page-glow pointer-events-none absolute -inset-x-4 -bottom-6 -top-6 -z-10 sm:-inset-x-8 sm:-top-10" />
      <div className="min-w-0">
        {/* Same size as the Overview section headings (e.g. "Your shelf"). */}
        <h1 className="flex items-center gap-2.5 font-display text-[26px] uppercase leading-none tracking-[0.01em] sm:text-[32px]">
          <span aria-hidden className="h-[0.7em] w-1.5 shrink-0 rounded-full bg-lime shadow-[0_0_12px_var(--lime)]" />
          {title}
        </h1>
        {subtitle && <p className="mt-1.5 text-[14px] text-muted">{subtitle}</p>}
      </div>
      {actions && <div className="flex items-center gap-2">{actions}</div>}
    </header>
  );
}
