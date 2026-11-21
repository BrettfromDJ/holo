import { setNameKey } from "./set-art";

// Matching pokemontcg.io's sets and card numbers to ours (for card artists; see server/artists.ts).

/** "Base Set (Shadowless)", "Base Set 1st Edition" → the set's own name. */
export function artistSetKey(name: string): string {
  return setNameKey(name.replace(/\(?\b(1st edition|shadowless|unlimited)\b\)?/gi, " "));
}

/** A card number reduced for matching: "118/162" → "118", "TG05" → "tg5", "SWSH001" → "swsh1". */
export function numberKey(n: string | null | undefined): string | null {
  if (!n) return null;
  const head = n.split("/")[0].trim().toLowerCase();
  const m = head.match(/^([a-z]*)0*(\d+)([a-z]*)$/);
  return m ? `${m[1]}${m[2]}${m[3]}` : head || null;
}
