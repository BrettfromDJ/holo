/** Words in set names that don't help find a card on eBay. */
const FILLER = new Set(["pokemon", "pokémon", "tcg", "the", "and", "&", "of", "-"]);

/**
 * The set as sellers write it in titles: its name without the code prefix ("SV05:", "ME:") or
 * the series before a dash ("Scarlet & Violet—"), keeping "Base Set" whole ("Obsidian Flames",
 * "Crown Zenith", "Base Set"); a numbered set's number alone ("151"). Up to two words, plus
 * "1st Edition" for a 1st Edition half. Same as the app.
 */
export function ebaySetWords(setName: string | null | undefined): string {
  if (!setName) return "";
  const first = /1st edition/i.test(setName);
  let rest = setName.replace(/^[A-Za-z]{1,6}\d*(\.\d+)?\s*:\s*/, "");
  const dash = rest.lastIndexOf("—");
  if (dash >= 0) rest = rest.slice(dash + 1);
  rest = rest.replace(/\([^)]*\)/g, " ").replace(/[:,]/g, " ");
  const words = rest.split(/\s+/).filter((w) => w && !FILLER.has(w.toLowerCase()));
  const numbered = words.find((w) => /^\d{2,3}$/.test(w));
  if (numbered) return numbered;
  const set = words.slice(0, 2).join(" ");
  return first ? `${set} 1st Edition` : set;
}

/**
 * A link to eBay's sold listings for a product, optionally for one grade ("PSA 10"): the name
 * without bracketed variant notes, the set's words (so other printings of the card don't fill
 * it), and the card number as sellers write it (the part before "/", which titles carry as "#4"
 * or "4/102"). Ungraded singles leave out slabs. Opens eBay's own search, so it shows every
 * recent sale, not just ours.
 */
export function ebaySoldUrl(p: { name: string; number?: string | null; kind?: string | null; setName?: string | null }, grade?: string | null): string {
  const params = new URLSearchParams({ _nkw: ebayQuery(p, grade), LH_Sold: "1", LH_Complete: "1", _sacat: "0" });
  return `https://www.ebay.com/sch/i.html?${params.toString()}`;
}

/** The same search for what's for sale right now: Buy It Now, cheapest first (price plus shipping). */
export function ebayListingsUrl(p: { name: string; number?: string | null; kind?: string | null; setName?: string | null }, grade?: string | null): string {
  // Buy It Now only (LH_BIN): a price you can pay today, not an auction that may climb.
  const params = new URLSearchParams({ _nkw: ebayQuery(p, grade), _sop: "15", LH_BIN: "1", _sacat: "0" });
  return `https://www.ebay.com/sch/i.html?${params.toString()}`;
}

function ebayQuery(p: { name: string; number?: string | null; kind?: string | null; setName?: string | null }, grade?: string | null): string {
  let q = p.name.replace(/\([^)]*\)/g, " ").replace(/\s+-\s+\S*\d+\/\d+\S*/g, " ").replace(/\s+-\s+/g, " ").replace(/\s+/g, " ").trim();
  if (p.kind === "single") {
    const set = ebaySetWords(p.setName);
    if (set && !q.toLowerCase().includes(set.toLowerCase())) q += ` ${set}`;
    const head = p.number?.trim().split("/")[0]?.replace(/^#/, "");
    if (head) q += ` ${head}`;
  }
  if (grade) q += ` ${grade}`;
  else if (p.kind === "single") q += " -psa -bgs -cgc -sgc";
  return q;
}
