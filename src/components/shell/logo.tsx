import { cn } from "@/lib/utils";

export function Logo({ className, withWordmark = true }: { className?: string; withWordmark?: boolean }) {
  return (
    <span className={cn("inline-flex items-center gap-2.5", className)}>
      <svg viewBox="0 0 32 32" className="size-8" aria-hidden>
        <rect width="32" height="32" rx="10" fill="var(--brand)" />
        <circle cx="16" cy="16" r="7.5" fill="none" stroke="#fff" strokeWidth="2.5" />
        <path d="M8.5 16h15" stroke="#fff" strokeWidth="2.5" />
        <circle cx="16" cy="16" r="2.6" fill="var(--brand)" stroke="#fff" strokeWidth="2" />
      </svg>
      {withWordmark && <span className="text-[19px] font-bold tracking-[-0.02em]">Holo</span>}
    </span>
  );
}
