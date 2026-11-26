import type { Metadata } from "next";
import { SalesView } from "@/components/sales/sales-view";

export const metadata: Metadata = { title: "Sales & taxes" };

/** Sales & taxes: every sale with its profit, by year, ready for an accountant. */
export default function SalesPage() {
  return <SalesView />;
}
