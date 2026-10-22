import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const badgeVariants = cva("inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[12px] font-semibold leading-4 [&_svg]:size-3", {
  variants: {
    variant: {
      neutral: "bg-surface-2 text-muted",
      up: "bg-up-soft text-up",
      down: "bg-down-soft text-down",
      sample: "bg-amber-100 text-amber-800 dark:bg-amber-400/12 dark:text-amber-300",
      outline: "text-muted ring-1 ring-inset ring-border-strong",
    },
  },
  defaultVariants: { variant: "neutral" },
});

export function Badge({ className, variant, ...props }: React.HTMLAttributes<HTMLSpanElement> & VariantProps<typeof badgeVariants>) {
  return <span className={cn(badgeVariants({ variant }), className)} {...props} />;
}
