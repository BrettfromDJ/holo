import { cn } from "@/lib/utils";

export function Card({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("hype-surface rounded-[var(--radius-card)] border border-border bg-surface", className)} {...props} />;
}

export function SectionTitle({ title, action, className, subtitle }: { title: string; subtitle?: string; action?: React.ReactNode; className?: string }) {
  return (
    <div className={cn("mb-4 flex items-end justify-between gap-4", className)}>
      <div>
        <h2 className="flex items-center gap-2 font-display text-[22px] uppercase leading-none tracking-[0.01em] sm:text-[24px]">
          <span aria-hidden className="h-[0.7em] w-1 rounded-full bg-lime shadow-[0_0_10px_var(--lime)]" />
          {title}
        </h2>
        {subtitle && <p className="mt-1.5 text-[13px] text-muted">{subtitle}</p>}
      </div>
      {action}
    </div>
  );
}
