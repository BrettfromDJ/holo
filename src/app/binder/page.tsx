import { redirect } from "next/navigation";

/** The Binder is now Master Sets. Old links (including `?set=`) land on the same set. */
export default async function BinderRedirect({ searchParams }: { searchParams: Promise<{ set?: string | string[] }> }) {
  const set = (await searchParams).set;
  const id = Array.isArray(set) ? set[0] : set;
  redirect(id ? `/master-sets/${encodeURIComponent(id)}` : "/master-sets");
}
