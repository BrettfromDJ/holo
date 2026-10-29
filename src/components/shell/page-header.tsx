import { cn } from "@/lib/utils";

export function PageHeader({ title, subtitle, actions, className }: { title: string; subtitle?: React.ReactNode; actions?: React.ReactNode; className?: string }) {
  return (
    <header className={cn("relative isolate mb-8 flex flex-wrap items-end justify-between gap-4", className)}>
      {/* Lit grid and a drifting glow behind every page title. It stops in the gap below the header:
          the header paints above the content that follows, so a taller glow would show through the cards. */}
      <div aria-hidden className="page-glow pointer-events-none absolute -inset-x-4 -bottom-6 -top-6 -z-10 sm:-inset-x-8 sm:-top-10" />
      <div className="min-w-0">
        <h1 className="flex items-center gap-3 font-display text-[40px] uppercase leading-[0.95] tracking-[0.005em] sm:text-[56px]">
          <span aria-hidden className="h-[0.62em] w-2 shrink-0 rounded-full bg-lime shadow-[0_0_16px_var(--lime)]" />
          {title}
        </h1>
        {subtitle && <p className="mt-2 text-[15px] text-muted">{subtitle}</p>}
      </div>
      {actions && <div className="flex items-center gap-2">{actions}</div>}
    </header>
  );
}
