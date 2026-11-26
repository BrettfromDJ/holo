import type { Metadata } from "next";
import { MarketHome } from "@/components/home/market-home";

export const metadata: Metadata = { title: "Home" };

export default function HomePage() {
  return <MarketHome />;
}
