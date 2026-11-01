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
  /** The account's value has been requested (cloud only). */
  fetching?: boolean;
  /** Changed locally since loading. */
  dirty?: boolean;
  /** The account's value has been read successfully (a missing row counts). */
  synced?: boolean;
  /**
   * Edits made before the account's value was read. They're replayed on top of
   * it once it loads, so a failed or slow read never saves a stale or empty
   * value over the account.
   */
  pending?: unknown[];
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

type Cloud = NonNullable<ReturnType<typeof getBrowserSupabase>>;

/** Supabase queries only run once awaited, so always await the write. */
async function upload(cloud: Cloud, userId: string, key: string, value: unknown) {
  const { error } = await cloud.from("user_state").upsert({ user_id: userId, key, value: value as never, updated_at: new Date().toISOString() });
  if (error && !/user_state/.test(error.message)) console.warn(`Couldn't sync ${key}:`, error.message);
}

function apply<T>(prev: T, next: unknown): T {
  return typeof next === "function" ? (next as (p: T) => T)(prev) : (next as T);
}

/**
 * Reads the account's value. Only a successful read marks the entry synced;
 * edits made meanwhile are replayed on top of the account's value and then
 * saved. A failed read saves nothing (the next mount or edit tries again).
 */
async function pull(e: Entry, cloud: Cloud, userId: string, key: string, localKey: string, fallback: unknown) {
  e.fetching = true;
  const { data, error } = await cloud.from("user_state").select("value").eq("key", key).maybeSingle();
  if (error) {
    e.fetching = false;
    e.ready = true;
    notify(e);
    return;
  }
  const pending = e.pending ?? [];
  e.pending = [];
  e.synced = true;
  if (data) {
    let value: unknown = data.value;
    for (const op of pending) value = apply(value === undefined || value === null ? fallback : value, op);
    e.value = value;
    writeLocal(localKey, value);
    if (pending.length) await upload(cloud, userId, key, value);
  } else if (e.value !== undefined) {
    // Nothing on the account yet: this browser's value (edits included) carries over.
    await upload(cloud, userId, key, e.value);
  }
  e.ready = true;
  notify(e);
}

/**
 * `legacyKey` is a localStorage key the value used to live under; it's read
 * once when nothing newer exists, so earlier data carries over.
 */
export function useSyncedState<T>(
  key: string,
  fallback: T,
  opts?: { legacyKey?: string },
): [T, (next: T | ((prev: T) => T)) => void, boolean, boolean] {
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
    }
    if (cloud && user && !entry.fetching && !entry.synced) {
      void pull(entry, cloud, user.id, key, localKey, fallback);
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
      let e = entries.get(id);
      if (!e) {
        // Set before the hook loaded: start from this browser's value; the
        // effect still reads the account and pushes this edit up.
        e = { value: readLocal(localKey) ?? (opts?.legacyKey ? readLocal(opts.legacyKey) : undefined), ready: !cloud, listeners: new Set<() => void>() };
        entries.set(id, e);
      }
      e.dirty = true;
      const prev = (e.value === undefined ? fallback : e.value) as T;
      e.value = apply(prev, next);
      writeLocal(localKey, e.value);
      notify(e);
      if (cloud && user && !e.synced) {
        // The account hasn't been read yet (or the read failed): keep the edit
        // and replay it on the account's value once that loads.
        (e.pending ??= []).push(next);
        if (!e.fetching) void pull(e, cloud, user.id, key, localKey, fallback);
      } else if (cloud && user) {
        // Coalesce quick edits (typing a trade value) into one write.
        clearTimeout(e.timer);
        const entry = e;
        entry.timer = setTimeout(() => void upload(cloud, user.id, key, entry.value), 600);
      }
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps -- fallback is a constant per call site
    [id, localKey, cloud, user, key],
  );

  // `ready`: loaded (or the read finished, even if it failed); `synced`: the
  // account's value was actually read (always true when not signed in).
  return [value, set, Boolean(entry?.ready), Boolean(entry?.synced || (entry?.ready && !cloud))];
}
