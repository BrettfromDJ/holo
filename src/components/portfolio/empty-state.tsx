"use client";

import { Search, type LucideIcon } from "lucide-react";
import Link from "next/link";

/**
 * Every empty page looks the same (the app's `EmptyPage`): an icon in a glass circle, a display
 * heading, one muted balanced line, one flat lime 44px pill button, and an optional quiet link.
 * No pictures, no demo button.
 */
export function EmptyPage({
  title,
  line,
  icon: Icon = Search,
  symbol: Symbol,
  action,
  href,
  onAction,
  link,
  linkHref,
  onLink,
}: {
  title: string;
  line: string;
  /** The button's icon, and the big icon on top unless `symbol` is given. */
  icon?: LucideIcon;
  symbol?: LucideIcon;
  action?: string;
  href?: string;
  onAction?: () => void;
  link?: string;
  linkHref?: string;
  onLink?: () => void;
}) {
  const Big = Symbol ?? Icon;
  const button = "mt-2 inline-flex h-11 items-center justify-center gap-2 rounded-full bg-lime px-[22px] text-[15px] font-semibold text-[#0b0b0c] transition-transform active:scale-[0.97]";
  const quiet = "text-[14px] font-medium text-muted hover:text-foreground";
  return (
    <div className="flex flex-col items-center gap-2.5 px-8 py-12 text-center animate-fade-in">
      <span className="glass mb-1 flex size-[72px] items-center justify-center rounded-full">
        <Big className="size-[26px] text-foreground" strokeWidth={1.9} />
      </span>
      <h2 className="text-balance font-display text-[24px] leading-tight">{title}</h2>
      <p className="max-w-[300px] text-balance text-[15px] text-muted">{line}</p>
      {action &&
        (href ? (
          <Link href={href} className={button}>
            <Icon className="size-4" strokeWidth={2.2} /> {action}
          </Link>
        ) : (
          <button type="button" onClick={onAction} className={button}>
            <Icon className="size-4" strokeWidth={2.2} /> {action}
          </button>
        ))}
      {link &&
        (linkHref ? (
          <Link href={linkHref} className={quiet}>
            {link}
          </Link>
        ) : (
          <button type="button" onClick={onLink} className={quiet}>
            {link}
          </button>
        ))}
    </div>
  );
}

/** An empty collection on other pages (Gains, Analytics…): the same empty page, pointing to search. */
export function EmptyCollection({ title = "Nothing here yet", body, action = "Search cards" }: { title?: string; body?: string; action?: string }) {
  return <EmptyPage title={title} line={body ?? "Scan a card to see what it's worth."} action={action} href="/explore?search=1" />;
}
