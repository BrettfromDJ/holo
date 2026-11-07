import "server-only";
import { createPrivateKey, createSign } from "node:crypto";
import { connect } from "node:http2";

/**
 * Apple Push Notification service, token-based auth (a .p8 key from the Apple
 * Developer account). Configure APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID and
 * APNS_PRIVATE_KEY (the .p8 file's contents) on the server only.
 */

export interface PushMessage {
  title: string;
  body: string;
  /** Extra data for the app, e.g. which card to open. */
  data?: Record<string, string>;
}

export interface PushResult {
  token: string;
  ok: boolean;
  status: number;
  /** APNs reason, e.g. "BadDeviceToken" or "Unregistered" (the token should be dropped). */
  reason?: string;
}

/** An env value without the spaces, line breaks or quote marks a paste often brings along. */
function env(name: string) {
  return (process.env[name] ?? "").trim().replace(/^["']|["']$/g, "").trim();
}

export function isApnsConfigured() {
  return Boolean(env("APNS_KEY_ID") && env("APNS_TEAM_ID") && env("APNS_BUNDLE_ID") && env("APNS_PRIVATE_KEY"));
}

const b64url = (b: Buffer | string) => Buffer.from(b).toString("base64").replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");

/**
 * The .p8 key as PEM, however it was pasted: with real or literal "\n" line breaks, with the
 * lines run together by spaces, or as just the base64 body without the BEGIN/END lines.
 */
export function readPem(raw: string) {
  const body = raw
    .replace(/\\n/g, "\n")
    .replace(/-----(BEGIN|END) [A-Z ]*PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const lines = body.match(/.{1,64}/g) ?? [];
  return `-----BEGIN PRIVATE KEY-----\n${lines.join("\n")}\n-----END PRIVATE KEY-----\n`;
}

/** Why the Apple key can't be used (nil when it can): checked before sending. */
export function apnsKeyProblem(): string | null {
  const raw = env("APNS_PRIVATE_KEY");
  try {
    const key = createPrivateKey(readPem(raw));
    if (key.asymmetricKeyType !== "ec") return `APNS_PRIVATE_KEY is a ${key.asymmetricKeyType} key, not an Apple push (.p8) key.`;
    return null;
  } catch (e) {
    const chars = raw.replace(/-----(BEGIN|END) [A-Z ]*PRIVATE KEY-----/g, "").replace(/\s+/g, "").length;
    return `APNS_PRIVATE_KEY couldn't be read (${chars} key characters after BEGIN/END; an Apple .p8 has about 200). ${e instanceof Error ? e.message : ""}`.trim();
  }
}

let cached: { token: string; at: number } | null = null;

/** Provider token (ES256 JWT), reused for up to 50 minutes as Apple asks. */
function providerToken(): string {
  const now = Math.floor(Date.now() / 1000);
  if (cached && now - cached.at < 50 * 60) return cached.token;
  const header = b64url(JSON.stringify({ alg: "ES256", kid: env("APNS_KEY_ID") }));
  const claims = b64url(JSON.stringify({ iss: env("APNS_TEAM_ID"), iat: now }));
  // Env vars often store the key with literal "\n"s.
  const pem = readPem(env("APNS_PRIVATE_KEY"));
  const signer = createSign("SHA256");
  signer.update(`${header}.${claims}`);
  const sig = signer.sign({ key: createPrivateKey(pem), dsaEncoding: "ieee-p1363" });
  const token = `${header}.${claims}.${b64url(sig)}`;
  cached = { token, at: now };
  return token;
}

/** Send one message to many devices of the same environment over a single HTTP/2 connection. */
export async function sendPush(tokens: string[], message: PushMessage, environment: "sandbox" | "production"): Promise<PushResult[]> {
  if (!tokens.length || !isApnsConfigured()) return [];
  const host = environment === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  const client = connect(host);
  const auth = providerToken();
  const payload = JSON.stringify({ aps: { alert: { title: message.title, body: message.body }, sound: "default" }, ...message.data });
  try {
    return await Promise.all(
      tokens.map(
        (token) =>
          new Promise<PushResult>((resolve) => {
            const req = client.request({
              ":method": "POST",
              ":path": `/3/device/${token}`,
              authorization: `bearer ${auth}`,
              "apns-topic": env("APNS_BUNDLE_ID"),
              "apns-push-type": "alert",
              "content-type": "application/json",
            });
            let status = 0;
            let body = "";
            req.on("response", (h) => (status = Number(h[":status"])));
            req.on("data", (c) => (body += c));
            req.on("end", () => {
              let reason: string | undefined;
              try {
                reason = body ? (JSON.parse(body) as { reason?: string }).reason : undefined;
              } catch {
                reason = undefined;
              }
              resolve({ token, ok: status === 200, status, reason });
            });
            req.on("error", (e) => resolve({ token, ok: false, status: 0, reason: e.message }));
            req.end(payload);
          }),
      ),
    );
  } finally {
    client.close();
  }
}
