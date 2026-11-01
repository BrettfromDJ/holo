/**
 * A link to eBay's sold listings for a product, optionally for one grade ("PSA 10"): the name
 * without bracketed variant notes, plus the card number when the name lacks it. Ungraded singles
 * leave out slabs. Opens eBay's own search, so it shows every recent sale, not just ours.
 */
export function ebaySoldUrl(p: { name: string; number?: string | null; kind?: string | null }, grade?: string | null): string {
  let q = p.name.replace(/\([^)]*\)/g, " ").replace(/\s+-\s+/g, " ").replace(/\s+/g, " ").trim();
  const num = p.number?.trim();
  if (num && !q.includes(num.split("/")[0])) q += ` ${num}`;
  if (grade) q += ` ${grade}`;
  else if (p.kind === "single") q += " -psa -bgs -cgc -sgc";
  const params = new URLSearchParams({ _nkw: q, LH_Sold: "1", LH_Complete: "1", _sacat: "0" });
  return `https://www.ebay.com/sch/i.html?${params.toString()}`;
}
