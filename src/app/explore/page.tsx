import { redirect } from "next/navigation";
import { ExploreLanding } from "@/components/explore/explore-landing";

/** Explore's landing. Searching moved to /search: old links ("/explore?q=…", "?search=1") go there. */
export default async function ExplorePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const q = typeof params.q === "string" ? params.q.trim() : "";
  if (q) redirect(`/search?q=${encodeURIComponent(q)}`);
  if (params.search === "1") redirect("/search");
  return <ExploreLanding />;
}
