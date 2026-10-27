"use client";

import { useCallback, useEffect, useState } from "react";
import { getBrowserSupabase } from "../supabase/client";
import { useStore } from "./collection-store";

/**
 * Small per-user values (reminders, the trade in progress, milestones seen…)
 * kept in this browser and, when signed in, in the `user_state` table so they
 * follow you across devices. Every component using the same key shares one
 * value and re-renders when it changes.
 */

interface Entry {
  value: unknown;
  ready: boolean;
  listeners: Set<() => void>;
  timer?: ReturnType<typeof setTimeout>;
}

const entries = new Map<string, Entry>();

function readLocal(key: string): unknown {
  try {
    const raw = localStorage.getItem(key);
    return raw === null ? undefined : JSON.parse(raw);
  } catch {
    return undefined;
  }
}

function writeLocal(key: string, value: unknown) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // Storage full or blocked — keep the value in memory.
  }
}

function notify(e: Entry) {
  for (const fn of e.listeners) fn();
}

/**
 * `legacyKey` is a localStorage key the value used to live under; it's read
 * once when nothing newer exists, so earlier data carries over.
 */
export function useSyncedState<T>(key: string, fallback: T, opts?: { legacyKey?: string }): [T, (next: T | ((prev: T) => T)) => void, boolean] {
  const { status, repoKind, user } = useStore();
  const scope = `${repoKind}:${user?.id ?? "anon"}`;
  const id = `${scope}:${key}`;
  const localKey = `holo:sync:${id}`;
  const cloud = repoKind === "cloud" && user ? getBrowserSupabase() : null;
  const [, rerender] = useState(0);

  useEffect(() => {
    if (status !== "ready") return;
    let entry = entries.get(id);
    if (!entry) {
      const local = readLocal(localKey) ?? (opts?.legacyKey ? readLocal(opts.legacyKey) : undefined);
      entry = { value: local, ready: !cloud, listeners: new Set() };
      entries.set(id, entry);
      if (cloud && user) {
        const e = entry;
        void cloud
          .from("user_state")
          .select("value")
          .eq("key", key)
          .maybeSingle()
          .then(({ data, error }) => {
            if (!error && data) {
              e.value = data.value;
              writeLocal(localKey, data.value);
            } else if (!error && e.value !== undefined) {
              // First time on this account: upload what this browser had.
              void cloud.from("user_state").upsert({ user_id: user.id, key, value: e.value as never, updated_at: new Date().toISOString() });
            }
            e.ready = true;
            notify(e);
          });
      }
    }
    const tick = () => rerender((n) => n + 1);
    entry.listeners.add(tick);
    tick();
    return () => {
      entry.listeners.delete(tick);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- keyed by id; cloud/user are part of it
  }, [status, id]);

  const entry = entries.get(id);
  const value = (entry?.value === undefined ? fallback : entry.value) as T;

  const set = useCallback(
    (next: T | ((prev: T) => T)) => {
      const e = entries.get(id) ?? { value: undefined, ready: true, listeners: new Set<() => void>() };
      entries.set(id, e);
      const prev = (e.value === undefined ? fallback : e.value) as T;
      e.value = typeof next === "function" ? (next as (p: T) => T)(prev) : next;
      writeLocal(localKey, e.value);
      notify(e);
      if (cloud && user) {
        // Coalesce quick edits (typing a trade value) into one write.
        clearTimeout(e.timer);
        e.timer = setTimeout(() => {
          void cloud.from("user_state").upsert({ user_id: user.id, key, value: e.value as never, updated_at: new Date().toISOString() });
        }, 600);
      }
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps -- fallback is a constant per call site
    [id, localKey, cloud, user, key],
  );

  return [value, set, Boolean(entry?.ready)];
}
