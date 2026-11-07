/**
 * Which notifications a person wants (user_state "notification-prefs", set in the app's
 * Account page). Anything missing counts as on.
 */
export interface NotificationPrefs {
  priceTargets: boolean;
  bigMoves: boolean;
  milestones: boolean;
  nearlyDone: boolean;
  weeklyRecap: boolean;
}

export const DEFAULT_NOTIFICATION_PREFS: NotificationPrefs = { priceTargets: true, bigMoves: true, milestones: true, nearlyDone: true, weeklyRecap: true };

export function readNotificationPrefs(value: unknown): NotificationPrefs {
  const v = value && typeof value === "object" ? (value as Partial<Record<keyof NotificationPrefs, unknown>>) : {};
  const on = (k: keyof NotificationPrefs) => v[k] !== false;
  return { priceTargets: on("priceTargets"), bigMoves: on("bigMoves"), milestones: on("milestones"), nearlyDone: on("nearlyDone"), weeklyRecap: on("weeklyRecap") };
}
