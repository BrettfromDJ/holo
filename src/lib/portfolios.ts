/**
 * Which portfolios a holding is in, and what Move and Copy write. The app's
 * `PortfolioMembership` (ios/Holo/Domain/PortfolioMembership.swift) is a port; keep both in step.
 *
 * A holding may be listed in several portfolios' `holding_keys`. "Main" is every holding in no
 * named portfolio, plus the ones kept in Main too: their keys are in user_state
 * `portfolio-main`. Copying never duplicates a holding; it only shows in more places, and
 * "All portfolios" counts each holding once.
 */

export const MAIN_ID = "main";
export const ALL_ID = "all";

export interface Membership<P extends { id: string; holdingKeys: string[] } = { id: string; holdingKeys: string[] }> {
  /** Named portfolios and the keys listed in each. */
  portfolios: P[];
  /** user_state `portfolio-main`: keys kept in Main as well as in a named portfolio. */
  main: string[];
}

/** The portfolios a holding shows in, "main" first when it's in Main. */
export function membersOf(m: Membership, key: string): string[] {
  const named = m.portfolios.filter((p) => p.holdingKeys.includes(key)).map((p) => p.id);
  const inMain = named.length === 0 || m.main.includes(key);
  return inMain ? [MAIN_ID, ...named] : named;
}

/** Whether a holding shows in a portfolio ("all" holds everything). */
export function isIn(m: Membership, key: string, portfolioId: string): boolean {
  if (portfolioId === ALL_ID) return true;
  if (portfolioId === MAIN_ID) return m.main.includes(key) || !m.portfolios.some((p) => p.holdingKeys.includes(key));
  return m.portfolios.some((p) => p.id === portfolioId && p.holdingKeys.includes(key));
}

/** A filter for the selected portfolio, by holding key; null shows everything. */
export function filterFor(m: Membership, selected: string): ((key: string) => boolean) | null {
  if (selected === ALL_ID) return null;
  if (selected === MAIN_ID) {
    const named = new Set(m.portfolios.flatMap((p) => p.holdingKeys));
    const main = new Set(m.main);
    return (key) => main.has(key) || !named.has(key);
  }
  const keys = new Set(m.portfolios.find((p) => p.id === selected)?.holdingKeys ?? []);
  return (key) => keys.has(key);
}

/** What a change writes: the named portfolios whose keys changed, and keys to add to or drop from `portfolio-main`. */
export interface MembershipChange<P extends { id: string; holdingKeys: string[] }> {
  next: Membership<P>;
  changed: string[];
  mainAdd: string[];
  mainRemove: string[];
}

/**
 * Puts each holding in exactly these portfolios. A key is listed in `portfolio-main` only when
 * it's in Main and in a named portfolio too (in no named one, it's in Main anyway).
 */
export function place<P extends { id: string; holdingKeys: string[] }>(m: Membership<P>, targets: Map<string, string[]>): MembershipChange<P> {
  const changed = new Set<string>();
  const portfolios = m.portfolios.map((p) => {
    let keys = p.holdingKeys;
    for (const [key, ids] of targets) {
      const has = keys.includes(key);
      const should = ids.includes(p.id);
      if (has === should) continue;
      keys = should ? [...keys, key] : keys.filter((k) => k !== key);
      changed.add(p.id);
    }
    return keys === p.holdingKeys ? p : { ...p, holdingKeys: keys };
  });
  const known = new Set(m.portfolios.map((p) => p.id));
  const mainSet = new Set(m.main);
  const mainAdd: string[] = [];
  const mainRemove: string[] = [];
  for (const [key, ids] of targets) {
    const listed = ids.includes(MAIN_ID) && ids.some((id) => known.has(id));
    if (listed && !mainSet.has(key)) {
      mainSet.add(key);
      mainAdd.push(key);
    } else if (!listed && mainSet.has(key)) {
      mainSet.delete(key);
      mainRemove.push(key);
    }
  }
  const main = mainAdd.length || mainRemove.length ? m.main.filter((k) => mainSet.has(k)).concat(mainAdd) : m.main;
  return { next: { portfolios, main }, changed: [...changed], mainAdd, mainRemove };
}

/** Move: the holdings end up only in `to` ("main" or a portfolio id). */
export function moveTo<P extends { id: string; holdingKeys: string[] }>(m: Membership<P>, keys: string[], to: string): MembershipChange<P> {
  return place(m, new Map(keys.map((k) => [k, [to]])));
}

/** Copy: the holdings also show in `to`, staying where they are. */
export function copyTo<P extends { id: string; holdingKeys: string[] }>(m: Membership<P>, keys: string[], to: string): MembershipChange<P> {
  return place(m, new Map(keys.map((k) => [k, [...new Set([...membersOf(m, k), to])]])));
}

/** Applies `portfolio-main` adds and drops to a list (the account's, which may have changed since loading). */
export function applyMainChange(list: string[], add: string[], remove: string[]): string[] {
  const drop = new Set(remove);
  const kept = list.filter((k) => !drop.has(k));
  const have = new Set(kept);
  return kept.concat(add.filter((k) => !have.has(k)));
}
