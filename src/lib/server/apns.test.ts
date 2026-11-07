import { generateKeyPairSync, createPrivateKey } from "node:crypto";
import { describe, expect, it, vi } from "vitest";
vi.mock("server-only", () => ({}));
import { readPem } from "./apns";

describe("readPem", () => {
  const pem = generateKeyPairSync("ec", { namedCurve: "prime256v1" }).privateKey.export({ type: "pkcs8", format: "pem" }).toString();
  const body = pem.split("\n").filter((l) => l && !l.startsWith("-----")).join("");
  it.each([
    ["as downloaded", pem],
    ["with literal \\n", pem.replace(/\n/g, "\\n")],
    ["run together with spaces", pem.replace(/\n/g, " ")],
    ["just the body", body],
  ])("reads the key %s", (_, raw) => {
    expect(() => createPrivateKey(readPem(raw))).not.toThrow();
  });
});
