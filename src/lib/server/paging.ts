import "server-only";

const PAGE = 1000;

/**
 * Read every row of a query in pages. Supabase returns at most 1,000 rows per
 * request (the project's max-rows setting), and a larger `.limit()` is
 * silently capped, so long lists must be paged with `.range()`.
 */
export async function selectAll<T>(page: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: { message: string } | null }>, max = 50_000): Promise<T[]> {
  const out: T[] = [];
  for (let from = 0; from < max; from += PAGE) {
    const { data, error } = await page(from, Math.min(from + PAGE, max) - 1);
    if (error) throw new Error(error.message);
    out.push(...(data ?? []));
    if (!data || data.length < PAGE) break;
  }
  return out;
}
