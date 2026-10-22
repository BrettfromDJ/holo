# Holo — Pokémon Collection & Investment Tracker

A premium, dark-first web app for tracking the market value and **true investment performance** of a Pokémon collection — singles, sealed product and graded cards.

Built with Next.js (App Router) · TypeScript · Tailwind CSS v4 · shadcn/ui-style Radix primitives · Supabase · [TCG API](https://tcgapi.dev) via the official `tcgapi` SDK · Recharts · Lucide.

> The app runs immediately in **demo mode** with zero configuration. Demo data is sample data, clearly labeled everywhere, and is never mixed into a real collection.

---

## Quick start

```bash
npm install
npm run dev          # http://localhost:3000 — demo mode
npm test             # investment-calculation unit tests
npm run typecheck && npm run lint
```

## Modes

| Mode | When | Storage |
|---|---|---|
| **Demo** | Default for signed-out visitors | Sample dataset regenerated relative to today + sandbox edits in `localStorage` (`holo:demo:v1`). Product ids use the `sample:` namespace. |
| **My collection — browser** | "Use my collection" without Supabase / sign-in | `localStorage` (`holo:local:v1`). Real TCG API products. |
| **My collection — synced** | Supabase configured and signed in | Supabase Postgres with row-level security. |

Switch modes from the sidebar (desktop) or Settings.

## Configuration

Copy `.env.example` to `.env.local`.

| Variable | Scope | Purpose |
|---|---|---|
| `TCGAPI_KEY` | server | TCG API key. Enables live search, prices and history. Never sent to the browser. |
| `TCGAPI_GAMES` | server | Optional comma-separated game slugs to search. By default every Pokémon catalog (English, Japanese, …) found via `GET /games` is searched. |
| `TCGAPI_GAME` | server | Game slug for top movers, default `pokemon`. |
| `TCGAPI_DAILY_RESERVE` | server | Daily requests held back for the scheduled sync (default 10 when `CRON_SECRET` is set, otherwise 0). |
| `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY` | public | Supabase project. Data is protected by RLS. |
| `SUPABASE_SERVICE_ROLE_KEY` | server | Writes to the shared catalog/price tables and runs the daily sync. |
| `CRON_SECRET` | server | Authenticates the Vercel Cron call to `/api/cron/sync-prices`. |

### Supabase

1. Create a project, then apply `supabase/migrations/20261022000000_initial_schema.sql` (`supabase db push` or paste into the SQL editor).
2. Authentication → URL configuration: add `https://<your-domain>/auth/callback` (and `http://localhost:3000/auth/callback`) as redirect URLs. Sign-in uses email magic links.
3. Set the env vars above. Regenerate `src/lib/supabase/database.types.ts` with `npx supabase gen types typescript` if you change the schema.

### Vercel

Import the repo, add the env vars, deploy. `vercel.json` schedules the daily price sync (`17 9 * * *` UTC); Vercel sends `Authorization: Bearer $CRON_SECRET` automatically.

---

## Investment math (the important part)

All calculations live in `src/lib/finance` as pure, tested functions.

- **Portfolio market value** — Σ quantity × current market price, for holdings that *have* a price. A missing price is `null`, shown as "—", excluded from value and gains, and called out in the UI. It is never treated as $0.
- **Cost basis / Total invested** — what you actually paid for units you still hold: unit price + allocated shipping, fees and tax. Each purchase is a separate **lot**; sales and removals consume lots **FIFO**.
- **Unrealized gain** — market value − cost basis of the priced holdings.
- **Realized gain** — per sale: net proceeds (price − selling fees − shipping) − FIFO cost of the units sold. Negative adjustments (opened, lost) write off their cost basis as a realized loss.
- **Daily market change (cash-flow adjusted)** — Σ q₍t−1₎ × (p₍t₎ − p₍t−1₎): only price movement on units held at the previous close. Buying a $1,000 box worth $1,000 adds $1,000 of value and **$0** of gain.
- **Performance % (time-weighted return)** — daily returns r₍t₎ = market gain ÷ prior value of those same units are chained: TWR = Π(1 + r₍t₎) − 1. Contributions and withdrawals never move it. Range dollar performance is the sum of daily market gains.

**Audit trail.** Transactions are append-only. A *correction* is a new row pointing at the original (`correctsId`) with replacement values; quantity 0 voids. Supabase RLS has no update/delete policies on `transactions`.

**Prices over time.** `PriceResolver` uses only real observations: the current quote for today, stored daily snapshots (carried forward at most 10 days, then treated as unknown), yesterday's price recovered from the source's own 24h change, or a manual valuation for graded cards. It never interpolates or back-fills history.

Unit tests: `src/lib/finance/__tests__/finance.test.ts` covers the "$1,000 box at market = $0 gain" case, FIFO partial sales, fee loading, corrections/voids, missing prices, TWR with large mid-period purchases, sales, and newly-priced items.

---

## Pricing integration

- `src/lib/pricing/types.ts` — `PricingProvider` interface (search, product, prices per printing, history, top movers) and normalized `NormalizedPrice` (market, low, 24h/7d/30d %, source update time, fetch time, source, `live | stale | unavailable`).
- `src/lib/pricing/tcgapi.ts` — TCG API implementation using the official SDK (`GET /v1/search`, `/v1/cards/:id`, `/v1/cards/:id/prices`, `/v1/cards/:id/history`, `/v1/prices/top-movers`, Pro-only `/v1/bulk/prices` with automatic fallback). Sealed vs. singles uses `type=Sealed Products` / `Cards`.
  - In-process TTL cache + in-flight request deduplication.
  - Reads the live `rate_limit` budget from responses, keeps a reserve for the cron, and honors `Retry-After` after a 429.
  - Tier errors (403) make history/bulk degrade gracefully instead of failing.
- Products are stored as `${source}:${externalId}` with the exact printing; nothing is matched by name. Another source plugs in by implementing `PricingProvider` and registering it in `src/lib/pricing/index.ts` — the collection tables don't change.
- Per-client token buckets protect the API routes that spend upstream quota.

### Daily sync (`/api/cron/sync-prices`)

1. Collects products owned or watched by any user.
2. Fetches prices (bulk on Pro+, otherwise per product at low concurrency, stopping on rate limits).
3. Upserts `product_prices` and today's `price_snapshots` (unknown prices are never written).
4. Rebuilds each user's `portfolio_snapshots` from stored data.

## Database (Supabase)

`profiles`, `user_preferences`, `products` (catalog cache), `product_prices` (latest), `price_snapshots` (daily history), `holdings` (product + printing + condition + grade), `transactions` (append-only: purchase / sale / adjustment / correction), `purchase_lots` (view over purchase transactions; remaining quantity derived by FIFO replay so it can't drift), `portfolio_snapshots`, `watchlist_items`. RLS restricts every user table to `auth.uid()`; the shared catalog is read-only to clients and written by the server with the service role.

## Project layout

```
src/app                 routes: overview, collection, product/[id], analytics, watchlist, activity, settings, login, api/*
src/components/ui       shadcn-style primitives (Button, Dialog, Select, Segmented, …)
src/components/flows    add-to-collection search + purchase form, sale / adjust / correction dialogs
src/components/portfolio, product, charts, shell
src/lib/finance         ledger (FIFO), price resolver, timeline & analytics + tests
src/lib/pricing         provider interface, TCG API provider, cache
src/lib/store           repositories (demo / local / Supabase) and the React store
src/lib/supabase        clients, typed schema, mappers, loader
supabase/migrations     schema + RLS
```

## Known limitations / next steps

- **TCG API docs**: implementation follows the official `tcgapi` SDK's typed endpoints. TCG API's `price_change_*` fields are treated as percentages (as in the SDK's top-movers example); verify against your account.
- **Card scanning** is not included: the official SDK exposes no identification endpoint, so it wasn't invented. The add flow is search-first; a scan step can be added behind `PricingProvider` once an endpoint is confirmed.
- **Graded pricing** is manual (TCG API prices raw printings). The resolver already supports a separate graded source.
- **Intraday** data isn't available; the 1D range shows yesterday's close vs. today.
- Demo sealed products use neutral placeholders rather than photos; demo card images load from `images.pokemontcg.io`. Live mode uses TCG API's `image_url`.
- A browser-only collection isn't migrated automatically when you later sign in (use Settings → Export).
