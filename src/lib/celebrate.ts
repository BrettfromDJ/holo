import type { Product } from "./types";

/** A newly added purchase, shown as a "pull" reveal. */
export interface PullEvent {
  product: Product;
  quantity: number;
  /** Portfolio market value just before the purchase was saved. */
  before: number;
}

type Listener = (e: PullEvent) => void;
const listeners = new Set<Listener>();

export function onPull(fn: Listener) {
  listeners.add(fn);
  return () => {
    listeners.delete(fn);
  };
}

export function celebratePull(e: PullEvent) {
  for (const fn of listeners) fn(e);
}
