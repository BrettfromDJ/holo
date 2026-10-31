# Holo

A TCG collection tracker (Pokémon first): a Next.js 15 website (`src/`, Supabase, deployed on
Vercel) and a native SwiftUI iPhone app (`ios/`) on the same account and data.

The owner is a designer, not a developer. Explain things in plain language, keep replies short,
and say exactly what to run or click.

## Git

- Work on and push to `claude/vibrant-hamilton-vsyz5z`. It is the default branch and Vercel
  production deploys from it. There is no `main`; never tell the owner to "merge".
- Commit and push after each change. Never open a pull request unless asked.
- End commit messages with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```

## Standing rules from the owner

- **See what you build.** Before saying a visual change is done, build it, run it, take a
  screenshot and look at it (see "Seeing the app" below). Most past mistakes came from not looking.
- **The website is the reference.** When the app and the website differ, match the website:
  layout, sizes, spacing, fonts, colors, copy. Read the web component before porting it.
- Answer questions without building. Only build when asked.
- Keep TCG API usage low (it is paid). Never put `TCGAPI_KEY` or the Supabase service-role key
  in the app; the app only has the public anon key.
- Never ask for or repeat secrets. APNs keys live only in Vercel.

## Design rules (both platforms)

- **Fonts:** Geist (body), Anton (display: titles and big numbers, uppercase), Geist Mono
  (small caps labels). The app also bundles Roboto Mono.
- **Colors:** lime `#D4FF3A` (accent, up), plan blue `#2F5BFF`, plan pink `#FF2E9A` (down).
  Color only numbers (gains green/lime, losses pink); text stays white or muted.
- **Never red or pink text on lime.** If a card's figure is down, the whole card goes pink.
- No confetti. No emojis. Toasts bottom-right on the web. Milestone and "Prices updated"
  banners are off in the app for now (they repeated).
- No lime bar beside section headings (removed). No dots beside card titles (removed).
- Headings wrap balanced (no lone word on the last line): use `DisplayText` for Anton headings.
- Sealed products sit in a dark rounded well shaped like their space (card-shaped in the hero
  fan and collection tiles, square on the star card and card page). On the shelf they stand bare.
- Graded copies render as a `Slab` (port of the web `Slab` in
  `src/components/product/product-image.tsx`).
- Liquid Glass (iOS 26) wherever it fits: tab bar, pills, chip tracks, search field. Use
  `.liquidGlass(in:)`, which falls back to frosted material on older iOS and older Xcode.
- Inactive tabs and chips have no background; only the selected one is filled.
- No black bar behind the navigation: content scrolls up under the status bar.
- Animations must be cheap: no per-frame layout on many views, no animated shadow radius, no
  per-frame blur. Looping motion uses a `TimelineView` or a single offset animation. Respect
  Reduce Motion everywhere.

## iPhone app (`ios/`)

- XcodeGen project: edit `ios/project.yml`, then run `xcodegen` (new files need it).
  `ios/Config.xcconfig` (git-ignored) holds the hosts and the anon key.
- iOS 17 target, SwiftUI with `@Observable`, supabase-swift, Swift Charts.
- Layout: `App/` (entry, tabs, router), `Core/` (design system in `Design.swift`, motion in
  `Motion.swift`, formatting), `Components/` (tab bar, product image, `Slab`), `Domain/` (FIFO
  ledger, timeline, deal math, worth, all ported from `src/lib`), `Store/` (collection store,
  demo data), `Data/` (models, Supabase and web API), `Features/` (one folder per screen).
- The math is ported from the web; `HoloTests` checks it. Keep both in step.
- Performance: `CollectionStore` caches the corrected log, sparklines and recent buys (cleared
  when transactions change) and rebuilds the timeline off the main thread. Keep heavy math out of
  `body`; give scrubbable charts their own view so dragging doesn't redraw the page.
- Shared data with the website: `holdings`, `transactions` (edits are corrections: `corrects_id`,
  quantity 0 deletes), `watchlist_items`, `device_tokens`, `user_preferences.monthly_budget`, and
  `user_state` keys `wishlist`, `deal`, `deal-rates`, `deals`, `release-reminders`,
  `milestones-seen`, `grading-submissions`, `grading-costs`, and the `shelves` / `portfolios`
  tables.

### Demo mode

- In the app: Account → Demo collection → Sealed only, Singles only, Singles + graded, or Mixed
  (stored on the phone; "My collection" switches back). Nothing is saved in a demo.
- Launch arguments: `-HoloDemo` (no sign-in), `-HoloDemoKind sealed|singles|graded|mixed`,
  `-HoloTab collection|explore|deal`, `-HoloProduct sample:<slug>` (e.g. `sample:es-bb`,
  `sample:pikachu-ex-ss`). Demo products are in `Store/DemoData.swift`; sealed box art is
  generated and bundled in `Resources/Demo/`.

## Seeing the app

- **On this Mac:** `ios/scripts/shot.sh [launch args]` builds, runs the simulator and saves a
  screenshot to `ios/shots/`. With no arguments it shows the real collection (sign in once in
  the simulator); add `-HoloDemo …` for demo data. `ios/scripts/shots-all.sh` runs the screenshot
  UI tests (every main screen scrolled top to bottom, plus the graded demo) into
  `ios/shots/all/`. Open the PNGs and look at them before reporting.
- **In CI:** every push to `ios/` builds, tests, runs the same screenshot tests and publishes the
  pictures to the `ci-screenshots` branch (`git fetch origin ci-screenshots`; one folder per
  commit). Screenshots are stills: they show layout and clipping, not motion.

## Website

- `npm run dev`, `npm test` (Vitest), `npm run lint`. Supabase migrations in `supabase/`.
- The daily price sync cron also sends watch-price push notifications (`src/lib/server/apns.ts`,
  `price-alerts.ts`).

## Open threads

- Milestone banners: off because they repeated; `checkMilestones()` in `HomeView.swift` is kept.
  Find why `milestones-seen` didn't stop repeats before turning it back on.
- In the app since: Gains (Home's Unrealized card and Home → More), Analytics, Grading, Master Sets
  (Home → More; was Binder), shelves (Collection chips, a card's ⋯ menu), portfolios (switcher on
  Collection; `store.holdingFilter` filters holdings, summary and timeline, `allHoldings` is
  unfiltered for deals), show deleted & edit records (card page). Grading state is in
  `user_state` `grading-submissions` / `grading-costs`; shelves and portfolios use the
  `shelves` / `portfolios` tables. Screenshot pages: `-HoloPage analytics|gains|grading|master-sets`.
- Not in the app on purpose: the separate trade checker (the Deal tab covers trades).
