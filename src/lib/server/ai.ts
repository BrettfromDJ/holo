import "server-only";

/**
 * The AI behind Home's daily notes and the weekly new collections: OpenAI, with the key in
 * Vercel only (`OPENAI_API_KEY`, never in the app). `OPENAI_MODEL` picks the model (a small,
 * cheap one by default). Every answer is JSON in the given shape; without a key there are none.
 */
const MODEL = process.env.OPENAI_MODEL || "gpt-5-mini";

export function aiEnabled(): boolean {
  return Boolean(process.env.OPENAI_API_KEY);
}

/** One request, answered as JSON matching `schema` (null if it can't be). */
export async function aiJson<T>(name: string, system: string, user: string, schema: object): Promise<T | null> {
  const key = process.env.OPENAI_API_KEY;
  if (!key) return null;
  // Reasoning models think briefly: these are short notes from given figures.
  const reasoning = /^(gpt-5|o\d)/.test(MODEL) ? { reasoning_effort: "low" } : {};
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model: MODEL,
      ...reasoning,
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
      response_format: { type: "json_schema", json_schema: { name, strict: true, schema } },
    }),
    signal: AbortSignal.timeout(60_000),
  });
  if (!res.ok) throw new Error(`OpenAI ${res.status}: ${(await res.text()).slice(0, 300)}`);
  const body = (await res.json()) as { choices?: { message?: { content?: string | null; refusal?: string | null } }[] };
  const message = body.choices?.[0]?.message;
  if (!message?.content || message.refusal) return null;
  return JSON.parse(message.content) as T;
}
