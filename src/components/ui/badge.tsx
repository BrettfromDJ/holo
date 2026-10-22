import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const badgeVariants = cva("inline-flex items-center gap-1 rounded-[5px] px-1.5 py-0.5 text-[11px] font-medium leading-4 [&_svg]:size-3", {
  variants: {
    variant: {
      neutral: "bg-surface-2 text-muted",
      up: "bg-up-soft text-up",
      down: "bg-down-soft text-down",
      sample: "bg-amber-400/12 text-amber-300 ring-1 ring-inset ring-amber-300/20",
      outline: "text-muted ring-1 ring-inset ring-border-strong",
    },
  },
  defaultVariants: { variant: "neutral" },
});

export function Badge({ className, variant, ...props }: React.HTMLAttributes<HTMLSpanElement> & VariantProps<typeof badgeVariants>) {
  return <span className={cn(badgeVariants({ variant }), className)} {...props} />;
}
