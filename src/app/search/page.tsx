import type { Metadata } from "next";
import { SearchScreen } from "@/components/search/search-screen";

export const metadata: Metadata = { title: "Search" };

/** Search every card and sealed product (the app's SearchScreen). `?q=` starts with that search. */
export default async function SearchPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const q = typeof params.q === "string" ? params.q : "";
  return <SearchScreen key={q} initialQuery={q} />;
}
