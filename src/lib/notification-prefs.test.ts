import { describe, expect, it } from "vitest";
import { DEFAULT_NOTIFICATION_PREFS, readNotificationPrefs } from "./notification-prefs";

describe("readNotificationPrefs", () => {
  it("treats anything missing as on", () => {
    expect(readNotificationPrefs(null)).toEqual(DEFAULT_NOTIFICATION_PREFS);
    expect(readNotificationPrefs({ bigMoves: false })).toEqual({ ...DEFAULT_NOTIFICATION_PREFS, bigMoves: false });
  });
});
