# Holo (the app is now called Dexora)

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

- **Check speed on every change.** Each push to `ios/` runs `HoloUITests/PerformanceTests` in CI
  (Owned sheet open/close, a tap inside a sheet, idle CPU on Overview and under a sheet,
  scrolling Overview). Read `perf.txt` in the commit's `ci-screenshots` folder and compare with
  `perf-history.txt` before reporting a change done; call out anything slower.
- **See what you build.** Before saying a visual change is done, build it, run it, take a
  screenshot and look at it (see "Seeing the app" below). Most past mistakes came from not looking.
- **Keep the app and website in step.** New things are often designed in the app first, then
  ported to the website (Master Sets, Your copy, graded lookup). When they differ by accident,
  ask which is right; read the other platform's code before porting.
- Answer questions without building. Only build when asked.
- **End every reply that changed the app with the update commands**, in a code block:
  `cd ~/holo && git pull && cd ios && xcodegen`, then Xcode → Product → Clean Build Folder and ▶.
  (Website changes deploy on their own from the branch.)
- Keep TCG API usage low (it is paid). Never put `TCGAPI_KEY` or the Supabase service-role key
  in the app; the app only has the public anon key.
- Never ask for or repeat secrets. APNs keys live only in Vercel.

## Design rules (both platforms)

- **Fonts:** Geist (body), Geist SemiBold for headings and big numbers (`Font.display` in the
  app, `font-display` on the web), in sentence case with tight tracking (Anton caps are retired;
  never uppercase headings), Geist Mono (small caps labels). The app also bundles Roboto Mono.
- **Colors:** lime `#D4FF3A` (accent, up), plan blue `#2F5BFF`, plan pink `#FF2E9A` (down).
  Color only numbers (gains green/lime, losses pink); text stays white or muted.
- **No grey text.** Quiet text is white made partly see-through (`Theme.muted` = white 60%,
  `Theme.subtle` = white 42%), never a grey color.
- **Dexora (app):** named Dexora, original Holo look everywhere (lime, grid and dot backdrops, glows,
  lime charts, the star card's electric border). Master Sets also uses the pieces in
  `Components/Glow.swift` (the set deck's `SetGlow`, the `GlowPie` dial, ring and ticks; no
  dot-matrix digits: numbers use `Font.display`). The iridescent and glow-card experiments were removed; don't bring them back.
- **Tapping a card:** one you own opens Owned (`HoldingSheet`) everywhere; one you don't opens
  its card page. Use `CardLink(productId:identity:)` in the app; it decides. Gains lives inside
  Analytics; Overview has a shortcut row (Analytics, Grading, Master sets, Activity).
- **Loading:** no spinners. The app opens on the collection saved on the phone at the last load
  (`SnapshotFile`, per account, deleted on sign-out; never in a demo) and refreshes it in place;
  only a first launch with nothing saved shows dim, still placeholders (`LoadingPlaceholder`).
  The web keeps skeleton placeholders. No loading animations.
- **Never red or pink text on lime.** If a card's figure is down, the whole card goes pink.
- No confetti. No emojis. Toasts bottom-right on the web. The "Prices updated" banner is off
  in the app for now; milestone banners are back on (see Open threads).
- No lime bar beside section headings (removed). No dots beside card titles (removed).
- Headings wrap balanced (no lone word on the last line): use `DisplayText` for Anton headings.
- Sealed products sit in a dark rounded well shaped like their space (card-shaped in the hero
  fan and collection tiles, square on the star card and card page). On the shelf they stand bare.
- Graded copies render as a `Slab` (port of the web `Slab` in
  `src/components/product/product-image.tsx`).
- Liquid Glass (iOS 26) wherever it fits: tab bar, pills, chip tracks, search field. Use
  `.liquidGlass(in:)`, which falls back to frosted material on older iOS and older Xcode.
  Glass cards always blur what's behind them: use `.liquidGlass(in:)` (never a flat translucent
  fill) for any card, panel or pill that reads as glass.
- Inactive tabs and chips have no background; only the selected one is filled. Chip tracks never
  bleed off the screen: the track stays inside the margins and the chips scroll inside it
  (`ChipPicker(..., scrolls: true)`).
- Bottom sheets: `.glassSheet()` (Apple's glass under a dark wash; panels, forms and dark buttons
  turn into a faint white fill on it). Stop short of full height (`.fraction(0.93)`) so iOS 26
  keeps it glass. No navigation bar in display sheets like Your copy: the bar resizes while the
  sheet rises and slides the content; put the title and Done in the content. Content sits still;
  only figures count and charts draw.
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
  `milestones-seen`, `grading-submissions`, `grading-costs`, `portfolio-main`, and the
  `shelves` / `portfolios` tables.
- Portfolios: a holding can be in several (`portfolios.holding_keys`); Main is holdings in no
  named portfolio plus the keys in `user_state` `portfolio-main`. Move = only there; Copy = also
  there, nothing duplicated; "All" counts each holding once. Rules in `src/lib/portfolios.ts`
  and `Domain/PortfolioMembership.swift` (same tests on both). Collection has a select mode
  (bulk Move, Copy, Add to shelf, Delete).

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

- Milestone banners: back on (fixed; check on a device). They repeated because the check re-ran
  each time the worth changed while loading, cancelling its `milestones-seen` load, and a failed
  load was read as "nothing seen" (then saved over the list). Now `checkMilestones()` in
  `HomeView.swift` waits for the numbers to settle, stops on a failed load, keeps the seen list on
  the phone too (`UserDefaults` `milestones-seen:<user id>`, marked before showing), merges when
  saving, never shows one at or below a level already seen (`Milestones.pick`), and skips demos
  and a selected portfolio. Same id format as the website (`value:10000`, `items:50`,
  `gain:<holding key>:1`).
- In the app since: Analytics (with Gains inside), Grading, Master Sets (was Binder), Activity —
  all from Overview's shortcut row, shelves (Collection chips, a card's ⋯ menu), portfolios (switcher on
  Collection; `store.holdingFilter` filters holdings, summary and timeline, `allHoldings` is
  unfiltered for deals), show deleted & edit records (card page). Grading state is in
  `user_state` `grading-submissions` / `grading-costs`; shelves and portfolios use the
  `shelves` / `portfolios` tables. Screenshot pages: `-HoloPage analytics|gains|grading|master-sets|activity` (plus `-HoloMasterSet`,
  `-HoloBumper`, `-HoloPull`, `-HoloWhatIf`, `-HoloScan`, `-HoloDealCustomer`, `-HoloOnboarding`). Slab certs and bumpers: `user_state` `slab-certs`,
  `slab-bumpers`, `slab-pristine` (CGC Pristine 10 marks, a list of holding keys; in `GradingStore`).
- Set art: our own art for English Pokémon sets in `public/sets/pokemon/<slug>/` (background,
  logo, symbol; list in `src/lib/set-art-manifest.json`), matched by name in `src/lib/set-art.ts`
  and sent by `/api/explore` as `iconUrl` (banner) + `logoUrl`; TCG API's art is the fallback.
  New sets: add a folder and a manifest entry.
- Not in the app on purpose: the separate trade checker (the Deal tab covers trades).
