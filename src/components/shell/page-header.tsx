import { cn } from "@/lib/utils";

export interface HeaderStat {
  label: string;
  value: React.ReactNode;
  /** Colors the value: gains lime, losses pink. Text otherwise stays white. */
  tone?: "up" | "down";
}

/**
 * A page's top, like the app's: a small mono label, then (optionally) one big Anton figure
 * with a muted unit, a line under it and a row of glass stat pills, over a field of fine dots
 * lit by lime, pink and blue glows. Without a figure the title itself is the big Anton line.
 */
export function PageHeader({
  title,
  subtitle,
  actions,
  className,
  figure,
  unit,
  note,
  stats,
  children,
}: {
  title: string;
  subtitle?: React.ReactNode;
  actions?: React.ReactNode;
  className?: string;
  /** The page's headline number (e.g. 128 entries). */
  figure?: React.ReactNode;
  /** Muted word after the figure ("ENTRIES"). */
  unit?: string;
  /** A line under the figure. */
  note?: React.ReactNode;
  stats?: HeaderStat[];
  /** Extra content under the figure, above the stats (e.g. a bar). */
  children?: React.ReactNode;
}) {
  return (
    <header className={cn("relative isolate mb-8", className)}>
      {/* Dots and glows behind the top; they fade out before the content below. */}
      <div aria-hidden className="page-dots pointer-events-none absolute -inset-x-4 -bottom-8 -top-10 -z-10 sm:-inset-x-8 sm:-top-14" />
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div className="min-w-0">
          {figure !== undefined ? (
            <>
              <h1 className="font-mono text-[11px] font-medium uppercase tracking-[0.14em] text-muted">{title}</h1>
              <p className="mt-2 flex items-baseline gap-2.5 font-display uppercase leading-none">
                <span className="tabular text-[48px] sm:text-[56px]">{figure}</span>
                {unit && <span className="text-[22px] text-muted sm:text-[24px]">{unit}</span>}
              </p>
              {(note ?? subtitle) && <div className="mt-2 text-[13px] text-muted">{note ?? subtitle}</div>}
            </>
          ) : (
            <>
              <h1 className="text-balance font-display text-[30px] uppercase leading-none tracking-[0.01em] sm:text-[36px]">{title}</h1>
              {subtitle && <p className="mt-1.5 text-[14px] text-muted">{subtitle}</p>}
            </>
          )}
        </div>
        {actions && <div className="flex items-center gap-2">{actions}</div>}
      </div>
      {children && <div className="mt-5 max-w-[560px]">{children}</div>}
      {stats && stats.length > 0 && (
        <div className="mt-5 grid max-w-[560px] gap-2" style={{ gridTemplateColumns: `repeat(${stats.length}, minmax(0, 1fr))` }}>
          {stats.map((s) => (
            <div key={s.label} className="glass-stat rounded-[14px] px-3 py-2.5">
              <p className="truncate font-mono text-[10px] uppercase tracking-[0.1em] text-muted">{s.label}</p>
              <p className={cn("tabular mt-1 truncate text-[15px] font-semibold", s.tone === "up" && "text-up", s.tone === "down" && "text-down")}>{s.value}</p>
            </div>
          ))}
        </div>
      )}
    </header>
  );
}
