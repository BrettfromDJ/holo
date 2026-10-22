import * as React from "react";
import { cn } from "@/lib/utils";

export const Input = React.forwardRef<HTMLInputElement, React.InputHTMLAttributes<HTMLInputElement>>(({ className, ...props }, ref) => (
  <input
    ref={ref}
    className={cn(
      "h-12 w-full rounded-2xl border border-border bg-surface px-4 text-[15px] text-foreground placeholder:text-subtle transition-colors outline-none focus:border-brand/50 focus:ring-4 focus:ring-brand/10 disabled:opacity-50",
      className,
    )}
    {...props}
  />
));
Input.displayName = "Input";

export const Textarea = React.forwardRef<HTMLTextAreaElement, React.TextareaHTMLAttributes<HTMLTextAreaElement>>(({ className, ...props }, ref) => (
  <textarea
    ref={ref}
    className={cn(
      "min-h-20 w-full resize-none rounded-2xl border border-border bg-surface px-4 py-3 text-[15px] text-foreground placeholder:text-subtle outline-none focus:border-brand/50 focus:ring-4 focus:ring-brand/10",
      className,
    )}
    {...props}
  />
));
Textarea.displayName = "Textarea";
