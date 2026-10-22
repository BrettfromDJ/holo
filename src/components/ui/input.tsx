import * as React from "react";
import { cn } from "@/lib/utils";

export const Input = React.forwardRef<HTMLInputElement, React.InputHTMLAttributes<HTMLInputElement>>(({ className, ...props }, ref) => (
  <input
    ref={ref}
    className={cn(
      "h-10 w-full rounded-lg border border-border bg-surface-2 px-3 text-[14px] text-foreground placeholder:text-subtle transition-colors outline-none focus:border-border-strong focus:bg-surface-3 disabled:opacity-50",
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
      "min-h-20 w-full resize-none rounded-lg border border-border bg-surface-2 px-3 py-2.5 text-[14px] text-foreground placeholder:text-subtle outline-none focus:border-border-strong focus:bg-surface-3",
      className,
    )}
    {...props}
  />
));
Textarea.displayName = "Textarea";
