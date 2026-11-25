# Holo (the app is now called Corodex; it was Dexora before)

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
  lime charts). Master Sets also uses the pieces in
  `Components/Glow.swift` (the set deck's `SetGlow`, the `GlowPie` dial, ring and ticks; no
  dot-matrix digits: numbers use `Font.display`). The iridescent and glow-card experiments were removed; don't bring them back.
- **Tapping a card:** opens its card page everywhere (app: owned or not, no Owned sheet in
  between; "Your position" sits right under the name, and a copy's row there opens `HoldingSheet`
  for its actions). Use `CardLink(productId:identity:)` in the app; it opens on the tapped copy's printing. Gains lives inside
  Analytics; Analytics, Grading, Master sets and Activity open from the top-right menu of
  Collection's Summary (what Overview was; the shortcut tiles were removed).
- **Tabs:** Home (`MarketHomeView`: the hobby, not your collection: card of the day, hot and cold,
  top 10, newest set showcase, hot sealed, sets), Collection (Summary and Cards as two big titles in
  the page, like Home's title, no bar (`CollectionTitles`; the one you're on white, the other faded;
  Summary's places menu on the right): Summary is `HomeView`, Cards is `CollectionView`; `CollectionMode`), Search, Explore, Deal.
  `Router.tabRequest` "collection" opens Cards, "collection-summary" opens Summary.
  Cards gets to the cards fast: nothing above the search (only the portfolio's name when not
  All; the "Worth" line was removed), then search (one glass family: the search box, a round glass filter button with a lime dot when
  something is set, and one round glass button flipping grid/list; no lime toggle), chips (no All tab, the owner's call: Singles, Sealed, Graded, then Pulls and lists; it opens on Singles, or Sealed when that's all you have: `activeCategory`; no kind banner above the cards) and the cards; the value, chart, stat tiles and mix bar live only on
  Summary. The portfolio switcher (`PortfolioSwitcher`, our action sheet) sits on Summary centred just
  above "Your collection's worth" and the big value (in `Hero`); Cards follows the pick.
- **Home's risers** (card of the day, hot/cold, top 10, eras, hot sealed) read stored 24-hour and
  7-day changes from `product_prices`, from $20 (`MOVER_MIN_PRICE`). The catalog sync's set pages
  have no changes from TCG API, so it keeps each Pokémon card's daily price in `catalog_price_days`
  (from $5, 9 days) and fills the changes itself (`src/lib/explore/price-days.ts`); TCG API's own
  changes win when it sends them.
- Home's top is in the page (no bar): "Home" big on the left (`header` in `MarketHomeView`), a bell
  (watchlist / price alerts) and the menu on the right; the places menu drops from there.
- Home opens with a search box (`SearchFieldButton`, opens `SearchScreen`), not the old Your
  collection strip (removed).
- Home's tabs under the search box (`HomeFilter` in `Themes.swift`: All · Modern · Mid era ·
  Vintage by each card's set date, a `ChipPicker`): All is the normal Home; a tab shows `filteredSections`, every piece cut to
  that kind (Card of the day, Heating up / Cooling off, Top 10 from trending + hot sealed, and collections
  via `ThemesModel.filtered`, rows with 4+ matching cards, up to 14). Sets, For you and lists: All only.
- **Card of the day** leads Home as a clean poster like a streaming app's featured title
  (`CardOfTheDay`): the card big on its own blurred art with a soft glow (pink when down), its
  name, one line ("Card of the day • set • +12%", only the number colored), and two buttons:
  View card (light) and + Wishlist (dark). No stats, chart, fun fact, countdown, rays or electric
  border (the owner wanted it simple). Collection of the Day follows, then Heating up / Cooling off.
- **By era on Home:** removed (the owner's call). `/api/eras` and `src/lib/server/era-summary.ts` still exist
  on the server but the app no longer shows or loads them.
- **Eras** (Home's Rising by era): vintage before Diamond & Pearl (WotC and EX, to early 2007),
  mid-era Diamond & Pearl through XY (2007–2016), modern Sun & Moon on (2017–). `eraOf` in
  `src/lib/explore/movers.ts` and `MarketEras.era` in the app (same cut-off dates).
- **Launch:** the Corodex mark (`LaunchLogo`, the icon's cards cut out of their black, 150pt) centred on `LaunchBackground` (= `Theme.background`); `RootView` covers the app with the same mark (`LaunchCover`, same size and place, so nothing jumps) and a thin lime loading bar under it (the owner asked for it: the one loading bar allowed) that always runs about a second (creeps to 85% in 0.6 s even when the app is ready sooner, waits there if it is slower), fills, then the cover fades. Not in demos.
- **Loading:** no spinners (the launch bar is the one exception). The app opens on the collection saved on the phone at the last load
  (`SnapshotFile`, per account, deleted on sign-out; never in a demo) and refreshes it in place;
  only a first launch with nothing saved shows dim, still placeholders (`LoadingPlaceholder`; Home's are still shapes and `PlaceholderRow`s, and Home fills in piece by piece as each part arrives). Home's themed collections are built ahead overnight (`/api/cron/warm-home`, fired from the catalog sync: today's and tomorrow's, plus explore and insights) so a first open doesn't wait on them.
  The web keeps skeleton placeholders. No loading animations.
- **One remove/delete look** (`.dangerStyle(shape)` in `Design.swift`): pink label on a soft pink tint (14%) with a faint pink edge, everywhere we draw our own remove button in a sheet (action sheets, scan Remove). Bars floating over the page (the Watchlist/Wishlist select bar) use `dangerStyle(shape, solid: true)`: filled pink, white text, so it holds up over the rows behind it.
- **Never red or pink text on lime.** If a card's figure is down, the whole card goes pink.
- **Oversized (jumbo) cards are never shown** anywhere people browse: search, set pages, Home's
  lists and collections. One rule on both sides: `isOversized` (`src/lib/explore/movers.ts`) and
  `Product.isOversized` / `isHiddenFromBrowsing` (with code cards) in the app. Your own holdings
  still show if you own one.
- **Cards never grow or step in size, and no price bars over cards** (the owner hated "Every
  price of Gengar" with growing cards, then with rising bars): rows of cards are one size.
- **Adding cards happens on the card page** ("Add to Collection"), reached through Search or
  Explore (or a scan). No add buttons on Summary, Collection or elsewhere; empty states may still
  point to Scan / Search.
- **The card page's TCGplayer panel** (app `WorthPanel`, web `WhatsItWorth`) is just one quiet
  Liquid Glass button, text only ("View on TCGplayer ↗", no logo), right under Add to Collection,
  linking to the card's TCGplayer page (printing + Near Mint). No figures: our source can't say
  which condition TCGplayer's market price is for, and its played-copy prices are asking prices.
- Watchlist / Wishlist (`ListsView`): prices via `store.listPrice` (the watched printing, else the default, else any printing) and `loadListPrices` fetches `product_prices` for cards added since the load (our DB, not TCG API). No Apple swipe actions or context menus on rows: hold a watch row for our sheet (Set/Edit target, Stop watching); wishlist rows are `CardLink`s (hold = quick actions). Select mode on both (Select / Done top right): rows get round checks, the tab bar gives way to a glass bar with Select all and a pink Stop watching N / Remove N (`removeWatches` / `removeWishes`, one request). Rows (`ListRow`): 48pt art, the name without a repeated " - 116/084", set · number, price, today's pill only when it moved (≥0.05%), and one line: "Target $X · N% away" (lime check + "reached" when hit) or, on the wishlist, "+$40 since added" (`WishItem.addedPrice`, saved on add by app and web). Newest first, no sort control (removed, the owner's call). Empty lists: `emptyState`, centred on the page: an icon (eye / heart) in a glass circle, a `Font.display` heading, one muted line, and a lime "Explore cards" button (every empty page's one button is lime, 44pt capsule).
- Lists of cards show their actions with a ⋯ at the end of each row (`RowMoreButton`, instead of a › arrow), opening the same sheet as holding the row, so actions never hide behind a long press: Collection's list view, Watchlist (target, stop watching), Wishlist (quick actions). Tapping the row still opens the card. Use it on any new list of cards.
- A list's page (`ListDetailView`): empty, it's like an empty Watchlist: the list's name in the bar with a ⋯ (rename, delete) at the top right, and a centred `emptyPage` (a stack icon in a glass circle, a display heading, one line, a lime Add cards button); no Add/Share row or For sale panel. Otherwise: no bar title (the list's name is the big heading); rows show the short name, set · condition, and "Owned ×N" as one quiet line with a small lime check (nothing when not owned; the big lime OWNED tags were too loud); the row's ⋯ is a small drop-down `Menu` (Set its price when for sale, Remove from list; the owner's call, no sheet for two actions). Its price sheet (`ListItemPriceSheet`) fits its content (one height): title + round close, the card beside the asking price ("90% of market" under it), % chips (no "List 90%" chip: the list's own % is simply selected, and picking it goes back to following the list, said in one quiet line), a set-price field, and a full-width lime Save.
- Master Sets list (`MasterSetsList`): straight to the sets: "Master Sets" in the bar, then the games as big titles like Summary | Cards (`gameTitles`: short names via `shortName`: in the owner's order: Pokémon, One Piece, Lorcana, Magic, then other games by set count, Pokémon Japan last; the one shown white, the rest faded, scrolling sideways with the right edge fading, the one you're on always scrolled into view; names tidied by hand: Yu-Gi-Oh!, Pokémon Japan), the top-right search swaps the game titles for a search field in the same 48pt slot (a quick cross-fade; ✕ closes it; nothing below moves, results swap without animation), no totals line, then straight into the sets in two groups, each under a `SectionTitle` with its count beside it (quiet), close under the game names: Sets started (most complete first) and All sets (the game's other sets, newest first); no Your sets / All sets chips and no sort button (removed, the owner's call); each group a two-column grid of `MasterSetTile`s like Explore's brand page (`SetArt` banner in a 3:2 frame, the name without "Unlimited" / "1st Edition" (shown instead as a small painted tag on the art's bottom left), "8 of 102" (no %), thin lime bar; a lime Complete tag when done; the old full-width `SetBannerRow` rows are no longer used here). The summary card (sets started, closest) and the Cards / Complete / Worth tiles were removed (the owner's call). A set's page has search and sort but no All / Owned / Missing chips (removed: noise). Its top is a shorter `SetHero(compact: true)` (logo area 120pt instead of 210).
- Grading (`GradingView`): only sections with something in them (no $0.00 slab hero, empty Your slabs or empty At the grader); costs behind a slider icon at the top right (`CostsSheet`). Worth grading is plain rows on the page (no panel), biggest PSA 10 upside first: 40pt art, name, "$1,064 raw → $26,200 PSA 10", one quiet line ("+$1,024 at a 9 · 10s sell steadily", or "At the grader"), the upside in whole dollars, and a ⋯ (`RowMoreButton`: Send for grading, Grading costs); no Send buttons or tag pills on rows. Its sheets (Grading costs, Send for grading, It's back) fit their content like `ListItemPriceSheet`: `SheetHeader` (title + round close), chips for grader / service / grade, one `SheetPanel` of `SheetMoneyRow`s and dates, a quiet note, and a full-width `SheetLimeButton`; no navigation bar, Cancel/Save capsules or form sections. Use these pieces for new small form sheets. Send for grading's services follow the grader (`Grading.services` in `Domain/Worth.swift`, web `SERVICES` in `grading-items.tsx`, same list, late-2026 public prices): a new grader starts on its cheapest service and picking a service fills in its usual fee. Row thumbnails on Grading use a 3pt corner (5–6 looked too round).
- Analytics (`AnalyticsView`, the owner's redo): seven sections, each figure said once. Top: Total return, then the one chart (`HistorySection`: Value / Return / Drawdown chips above, 1M · 3M · 1Y · All chips under, one quiet caption; no separate Portfolio history, no sparkline), then Market only · Realized (opens Sales & taxes; no separate Sales row) · Invested tiles. Winners & losers (`WinnersLosers`: Gains / Losses and $ / % chips, top 5 + Show all, rows with ⋯ → quick actions; replaces Where it comes from, Best investments and Underperformers). Breakdown (Type · Set · Map chips; `BreakdownRow`: name ×count, value, pill, one quiet line, a thin bar). By month (heatmap, Best day / Worst day / Biggest drop tiles, invested each month). Diversification (plain label, no skew tag). Advanced, folded (Return vs. time held, up days, volatility). No Sealed/Singles bar, no long notes under headings, no drop-down menus or square $/% buttons.
- Deal's add sheet (`DealPickerSheet`): no bar; "Add cards" / "Add from your collection" with a round close (`SheetHeader`), then the search across the full width (camera inside it). The custom way in is no longer a button beside the search: coming in, before you type, the same panel as the end of the results, at the top: "Find their cards", one line, the full-width glass button; once you search (and always going out) the list ends with a small panel: "Can't find it?" (display 20), one muted line, and a full-width glass "Add a custom item or lot" button. No lines between rows, no Catalog title, rows to the search's 16pt margin.
- Explore's landing: "Games" (was Categories), "Coming soon" with Calendar beside it, and "Just released", with no lines of small text under the headings. Game tiles use the short names and the owner's order (`ExploreGame.ordered`, the same as Master Sets: Pokémon, One Piece, Lorcana, Magic, the rest, Pokémon Japan last) and compact counts ("240 sets · 33K cards"); the tiles are plain dark (`Theme.surface`) with a fine light edge, no coloured tints, and show the game's logo big instead of its name (the name only when there's no logo; Pokémon Japan adds a small "Japan" tag), with the counts under it; set lines say the game's short name (`ExploreSet.shortGame`).
- Weekly recap (`WeeklyRecap`, story slides): sealed boxes on the hottest / coldest / best-buy slides stand bare (no dark card-shaped well), the week chart keeps at least an 8% band so a small move doesn't look like a cliff and its date range starts on the chart's first day, a dark fade sits under the bars over the closing slide's picture wall, and the ✕ lines up with the end of the bars. The Shopping slide's fan has no price pills under the cards (the total below says it). A drifting piece's glow is a square around its longer side (a wide box's glow was cut flat), and the closing slide's picture wall shows sealed products as square tiles (cards stay card-shaped; each column loops over its own height).
- Sales & taxes (`SalesView`): year chips (All + each year sold in), the profit with an ⓘ (the fine print in an alert), glass tiles for Gains / Losses (losses pink) and Sold for / They cost / Fees, the held split as the same tiles (a quiet — when nothing), every sale tappable with a ⋯ (Edit sale, Delete sale), and Export as a share icon at the top right. Built for vendors with hundreds of sales: the report is worked out once per log change (`.task(id:)`, kept in @State, not in `body`), sales are grouped by month (title · count · profit) in lazy stacks, a "Find a sale" search shows past 8 sales, and the list starts with the latest 50 (Show all N).
- **Every empty page looks the same** (`EmptyPage` in `Onboarding.swift`, and the Watchlist / list empty states built the same way): an icon in a glass circle, a `Font.display` 24 heading, one muted line, one flat lime 44pt capsule button, an optional quiet link. Used by Summary, Cards, Analytics, Sales and Master Sets.
- Form footnotes under a section (`} footer: {`) are quiet: `.font(.geist(13)).foregroundStyle(Theme.muted)` (they showed bright white).
- No sell-speed meter on the card page's eBay panel (app `EbaySalesPanel`, web `ebay-sales.tsx`): removed, the owner's call.
- No confetti. No emojis. Toasts bottom-right on the web. The "Prices updated" banner is off
  in the app for now; milestone banners are back on (see Open threads).
- On Home, a tapped card grows into its card page (iOS 18+ zoom): `@Namespace cardZoom` in
  `MarketHomeView`, pictures marked with `.cardZoomSource(productId)` (`Poster`, Card of the day).
- Home's Top 10 (`TopTenRow`) is Netflix-style: each card the same size as other rows, in front of
  its rank as a huge outlined numeral, price and 7-day rise on the card's glass pill; no boxes or text under.
- No icons beside Home's section headings, and no crown on Top 10's No. 1 (removed). No lime bar beside section headings (removed). No dots beside card titles (removed).
- Headings wrap balanced (no lone word on the last line): use `DisplayText` for Anton headings.
- Sealed products sit in a dark rounded well shaped like their space (card-shaped in the hero
  fan and collection tiles, square on the star card and card page). On the shelf they stand bare.
- Graded copies render as a `Slab` (port of the web `Slab` in
  `src/components/product/product-image.tsx`).
- Liquid Glass (iOS 26) wherever it fits: tab bar, pills, search field. Use
  `.liquidGlass(in:)`, which falls back to frosted material on older iOS and older Xcode.
  Glass cards always blur what's behind them: use `.liquidGlass(in:)` (never a flat translucent
  fill) for any card, panel or pill that reads as glass.
- Chips and tabs (`Chip`, `ChipPicker`) look like a streaming app's category tabs: separate rounded
  (13pt) Liquid Glass tiles with a faint light edge and white text, the selected one filled white
  with dark text; no track behind them. Rows never bleed off the screen: they scroll inside the margins with the right
  edge fading (`ChipPicker(..., scrolls: true)`).
- Bottom sheets: `.glassSheet()`: `Theme.sheet` (#161618, a touch lighter than the page so the sheet's edge shows; was pure black and blended in; `ActionsSheet` too), pull handle centred at the top, stopping short of
  full height (`.fraction(0.93)`; iOS 26 floats them in from the edges); panels, forms and dark buttons
  turn into a faint white fill on it. No navigation bar in display sheets like Your copy: the bar
  resizes while the sheet rises and slides the content; put the title and Done in the content.
  Content sits still; only figures count and charts draw.
- **No doubled titles:** a page with its own big heading (Lists, Activity, a list, Sales has none) leaves the bar title empty (`.pageTitle("")`), so the name isn't shown twice.
- No black bar behind the navigation: content scrolls up under the status bar.
- Smoothness rules (from the Nov 2026 audit): read saved files once per launch, not in a view's
  `@State` default (views re-init on every tab switch: `ThemesModel.launchSaved`,
  `MarketInsights.launchSaved`); compile regexes once (`Product.oversizedRule`); the drifting
  `HoloCard` rests after 12 s (touch or reappearing restarts it); Summary's fan runs at 30 fps;
  never put a shadow over Liquid Glass (shadow a plain shape behind it); the image cache is capped
  at 150 MB; `CollectionStore.recompute` only assigns holdings/summary when they changed.
  Scrubbable charts (`PriceHistoryCard`, `PerformanceSection`): the series is an Equatable child
  (`HistorySeries`, `PerformanceSeries`) with explicit x/y scales; the finger's rule/point is a
  separate empty-axis Chart overlaid on top that owns `chartXSelection`, so dragging redraws only it.
- No Apple pop-up menus for actions (they lagged and clipped): use our `ActionsSheet`
  (`Components/ActionsSheet.swift`, `.actionsSheet(isPresented:)` / `(item:)` with `[[SheetAction]]`):
  a small black sheet of quiet glass rows, sections, checks, a second page for lists/portfolios/copies
  with a round back button, run after the sheet closes. Any action alone in its section (no subtitle, not a list to pick from) shows as a full-width button with its label centred (`loneButton`): glass, or pink-tinted when it removes something; a destructive tile is tinted pink too. No extra space under the last row. Used by the card page ⋯, Your copy ⋯ and its
  entries, Collection's held tiles and list chips, the set page's sort. Small pickers may stay Menus.
- **Glass speed (Nov 2026):** `LaunchWarmUp` (in the launch cover) draws each glass kind once; the keyboard is warmed (`KeyboardWarmUp`, a hidden text field opened and closed) only once signed in, never on the sign-in page, which has its own `KeyboardWarmer` (both at once froze the email field) so the first search and first glass are as quick as later ones; search screens raise the keyboard after they've slid in (~0.3 s); never wrap rows of glass chips/tiles in a `GlassEffectContainer` (tried: it blurred the unselected chips' labels); price tags on posters in Home's long rows use `.pillOnArt(in:)` (painted, not live glass). Keep live glass to bars, pills and buttons, not on every item of a long list.
- Animations must be cheap: no per-frame layout on many views, no animated shadow radius, no
  per-frame blur. Looping motion uses a `TimelineView` or a single offset animation. Respect
  Reduce Motion everywhere.

## iPhone app (`ios/`)

- XcodeGen project: edit `ios/project.yml`, then run `xcodegen` (new files need it).
  `ios/Config.xcconfig` (git-ignored) holds the hosts and the anon key.
- iOS 17 target, SwiftUI with `@Observable`, supabase-swift, Swift Charts.
- iPhone and iPad (`TARGETED_DEVICE_FAMILY` 1,2). iPhone is portrait only; iPad turns every way and
  keeps the pages to a readable 760pt column (`readableWidth()` on `MainTabView`).
- Press and hold any card (`CardLink` → `CardQuickActions`, our own 0.35s hold, not Apple's context
  menu, which clipped the tile and lagged): a tick, then `QuickActionsSheet` (a small black sheet via
  `Router.quickCard`): three tiles: Add to collection (opens the card page sheet with its add form already up: `Router.addOnOpen`), Watch price, Add to list (opens the lists page); then one row: Add to wishlist, or Remove from wishlist (pink) when it's on it. Undo toasts also follow bulk Move / Copy and adding to a list. Undo toasts are the same small centred glass pill (lime check, message, a hairline, lime Undo). Plain confirmations use the same `Router.undo` with no action (`UndoItem(message:)`): a small centred glass pill with a lime check, gone in ~2 s (Added to / Removed from your watchlist or wishlist, from the store so every entry point shows it; the card page sheet has `.undoToast` too).
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
  all from Overview's top-right menu, shelves (Collection chips, a card's ⋯ menu), portfolios (switcher on
  Summary; `store.holdingFilter` filters holdings, summary and timeline, `allHoldings` is
  unfiltered for deals), show deleted & edit records (card page). Grading state is in
  `user_state` `grading-submissions` / `grading-costs`; shelves and portfolios use the
  `shelves` / `portfolios` tables. Screenshot pages: `-HoloPage analytics|gains|grading|master-sets|activity` (plus `-HoloMasterSet`,
  `-HoloBumper`, `-HoloPull`, `-HoloWhatIf`, `-HoloScan`, `-HoloDealCustomer`). Slab certs and bumpers: `user_state` `slab-certs`,
  `slab-bumpers`, `slab-pristine` (CGC Pristine 10 marks, a list of holding keys; in `GradingStore`).
- Set art: our own art for Pokémon sets in `public/sets/pokemon/<slug>/` and `public/sets/pokemon-japan/<slug>/` (background,
  logo, symbol; lists in `src/lib/set-art-manifest.json` / `-ja.json`), matched in `src/lib/set-art.ts` (Japanese by set code first)
  and sent by `/api/explore` as `iconUrl` (banner) + `logoUrl`; TCG API's art is the fallback.
  New sets: add a folder and a manifest entry.
  Pokémon sets whose banner isn't our own (`/sets/pokemon` in `iconUrl`; TCG API's banner for these is
  a blurry Pokémon logo) show the Pokémon logo (the owner's SVG: app asset `PokemonLogo`,
  web `/brands/pokemon.svg`) small with generous padding, instead of TCG API's blurry copy.
- Sealed photos: our own pictures of sealed products (backgrounds removed) in
  `public/products/pokemon/<set>/<product>.webp`. The owner drops one folder per set in `art-inbox/`
  (folder = set, file = product name) and `python3 scripts/sealed-art.py` converts them and rebuilds
  `src/lib/sealed-art-manifest.json` and the app's generated `Domain/SealedArtList.swift` (never
  edit that by hand); then delete `art-inbox/`. Matching (set named last in the set name, then the
  product name without the set) is in `src/lib/sealed-art.ts` and `Domain/SealedArt.swift`, same
  tests on both. The web `ProductImage` and the app's `Product.imageURL` use them. Done: 33
  modern sets (Sword & Shield era onward).
- Old sets split by edition (Base Set, Jungle, Fossil, Team Rocket, Gym, Neo): `src/lib/editions.ts`
  and `Domain/Editions.swift` (slugs `<set>--1st-edition` / `--unlimited`). The catalog's card
  pictures are 1st Edition scans; the owner supplies Unlimited photos per set in
  `public/cards/pokemon/<dir>/<number>.webp`, listed in `src/lib/unlimited-art-manifest.json`
  and the same list in `Editions.unlimitedArt` (keep both in step). Done: Base Set (no #8), Jungle, Fossil, Team Rocket, Gym Heroes, Gym Challenge, Neo Genesis, Neo Discovery, Neo Revelation, Neo Destiny.
- Dexora Pro (test mode, app only so far): `Features/Pro/Pro.swift`. Free: whole collection, 20 scans a month, 30 days of price history, 2 lists, 1 portfolio (Main), 3 alerts, 2 master sets; Pro unlocks the rest plus eBay comps, Grading and Analytics. Pro page `ProSheet` (a full-screen takeover, X at the top right), locks `ProOnly` / `EbayLockedPanel` / `.proPaywall`. "Start free trial" only turns `Pro.shared.isPro` on for the phone; real purchases (Apple + Stripe, one Pro for app and website) come later. Demos count as Pro.
- Home insights (AI, OpenAI by the owner's choice): `src/lib/server/ai.ts` is the one place that
  calls it (`aiJson`, Chat Completions with a strict JSON schema; `OPENAI_API_KEY` in Vercel only,
  never in the app; `OPENAI_MODEL` optional, default `gpt-5-mini`). `insights.ts` writes "Today in
  the hobby" (no longer shown in the app: removed from Home by the owner; three stories: headline, one figure, a card id; shown as `HobbyStories`, a stack of
  notification-style glass cards that cycle round and round, swipe to step) and a line per highlighted card once a day from `exploreMarket`
  (saved in `api_cache` as `insights-v5:<day>`), served at `/api/insights`; the app shows them on Home (`HobbyBriefing`,
  Card of the day's line; `MarketInsights`, kept on the phone). Without the key Home shows none.
- Home's themed collections (the owner's playbook "The Art of Card Discovery", ~70): rules in
  `src/lib/explore/themes.ts` (price finds, grails, art, vintage, Pokémon, changing over time),
  filled by `src/lib/server/themes.ts` by `source`: rule (name/set/rarity/number/price/era), price
  (priciest down in a band), ai (art themes: the AI picks from our illustration cards weekly,
  `theme-ai:<id>:<monday>`), market (trending/today/drops/rediscovered), fresh (sets out in 90
  days), popular (kept or watched by 2+ collectors). Japanese cards only in `japanese` themes.
  Saved a day per theme in `api_cache`; `/api/themes`. AI proposes 5 more weekly (via `ai.ts`). No "Every price of <Pokémon>" collections (removed; the AI can't propose them).
  The app (`Features/Home/Themes.swift`): Collection of the Day (`DailyDiscovery`, the same row with a "Today's discovery" label) leads Home,
  then ~14 per launch between Home's lists, Netflix-style: one look for all (`PosterRow`: title
  only, no arrow, not tappable, no line under it; every card of the collection in the row, big
  150×209 with a price tag; no separate page from Home's rows; no spotlight or other layouts, every row the same); new mix each open, weighted to your Pokémon, era and the `featured` lineup, and
  collections shown on the last two opens are much less likely (`themes-recent` on the phone).
  Your lists come last as the same rows (`HomeListRows`). Home's other sections have no subtitle
  either. Plus "Your next favorite" (For you's
  picks of your favourite Pokémon) in the last slot on about one open in three; each opens `ThemePage`. For you keeps only
  Finish your sets (50%+) and Your week's budget.
- Card artists: `products.artist` (migration `20261121000000_card_artists.sql`), filled from the
  free pokemontcg.io API once per set (`src/lib/server/artists.ts`, matched by set name/code and
  card number in `src/lib/artists.ts`; `catalog_sets.artists_synced_at`), run nightly from the
  catalog cron via `/api/cron/sync-artists`. Card page: "Illustrated by <name>" (app
  `ProductDetailView`, web product page) opens the artist's page (app `Features/Artist/ArtistPage.swift`,
  web `/artist/<name>`), every card they drew, priciest first, from `/api/artists/<name>`.
- Scanner: the phone reads first (`OnDeviceScan`: Apple's text recognition for name + number, then
  the card list kept on the phone (`ScanCatalog`: every English Pokémon single from `/api/scan/index`, packed with string tables, cached a day at the edge, saved in Caches, read at launch after the collection and on opening the scanner, refreshed when 20 h old; no prices: a scan's price fills in after, and a deal waits for it before adding the card, `ScanModel.handLater`), else one quick lookup (`/api/scan/lookup`: singles with that number, total as read or one off, plus names starting with what was read; the general search only if it fails; `searches`); one clear match (a small total like 09/30 also needs the name read to fit: `numberIsEnough` / `nameAgrees`) or it falls back; indexes for speed in migration `20261125000000_scan_speed.sql` (trigram on `products.number`, IVFFlat (100 lists, 10 probes set on `match_card_prints`; HNSW took too long to build in the SQL editor) on `card_prints.print`, now `vector(768)`); a set total read one off (021/130 for 021/131) still matches (`closeNumber`); with a total read, a card must print one too (`strictNumber`); several cards with the number: the name read picks one; a card's pattern versions (Poké Ball / Master Ball, same set and number) count as one, the plainest name wins (`oneCard`); a name read that fits no card with the number but fits one card in a set of the same size wins over the number (a misread digit), while a name that's no card's (an attack) lets a full number stand; misread BASIC / STAGE labels aren't names (`looksLikeStage`); photos are taken at 3200 px and read from a 2000 px crop of the tracked card, or of the guide's middle when none is tracked (`Camera.guideCrop`, so thumbnails are framed alike); the card is found by Apple's learned document finder (`VNDetectDocumentSegmentationRequest`, good on busy backgrounds) plus the edge finder (`VNDetectRectanglesRequest`, loosened: size 0.15, confidence 0.5); the tracker keeps only upright card-shaped outlines (`CardQuad.isCardShaped`, w/h 0.58–0.85) and switches to a bigger outline around the one it follows (it locked onto the art or attack box and cropped into the card); a small subset number beside the real one (30th Celebration's "09/30") is dropped; test scans' notes carry each step's seconds), live (`CardTracker`) and on the shutter
  (a crop of the tracked card); CardSight (server) gets the whole photo only when the phone isn't sure,
  or several cards are in it. Camera: combined camera (macro up close), 4K frames, a real photo per scan. A lime outline hugs the tracked card's edge (`CardTrackingOverlay`, back by the owner's call; the still lime guide frame was removed, the owner's call: only the reading pill stays where it sat). The scanner closes on a swipe down over the camera only (not on the tray: `trayTop`); pulling the tray's header down folds its list, up opens it; the list is clipped to the tray.
  Test-photo mode (Settings → Scanner, `ScanTestLog`): saves each scan's photo + both scanners'
  answers to Files → Corodex → Scan tests and keeps a running agree/disagree and speed summary;
  both scanners run on every scan while it's on. Picture matching (`CardFingerprint`, Vision feature
  prints, on the phone): when text narrows it to several cards or only a name was read, the
  candidates are compared on the server against their stored fingerprints (`/api/scan/match` with `ids`, no downloads; only cards with none stored, or pictured differently like Unlimited photos, are fingerprinted on the phone, cached in Caches/card-prints; the scan's own fingerprint is made once, alongside the text reading) and the closest wins
  only if 20% nearer than the runner-up. Whole catalog: the "Card fingerprints" GitHub workflow
  (nightly on a Mac, `ios/scripts/fingerprints.swift`, needs `FINGERPRINTS_SECRET`, the same value in Vercel and as a GitHub Actions secret, and
  optionally the variable `SITE_URL`) fingerprints every Pokémon single (Vision revision 2; done Nov 25 2026: the ~3,360 left have no picture at TCGplayer (404), retried nightly in about a minute) via
  `/api/fingerprints` into `card_prints` (pgvector; migration `20261122000000_card_prints.sql`);
  the app's last on-phone try sends the scan's fingerprint to `/api/scan/match` (nearest 5) before
  CardSight.
- Deal tab (the owner's recorded flow, Nov 2026; `Features/Deal/DealFlow.swift`): always from your side (no vendor/collector wording on the page). Start (`DealStartPage`): "New deal", "What's the deal?", Buy cards / Sell cards / Trade cards glass rows, each in its kind's colour (the owner's mockup; `DealKind.tint`: blue buy, lime sell, purple trade): a filled gradient icon tile, a faint tint and edge on the glass, a coloured chevron; the saved and closed rows (`DealListRow`) use a soft tile in that colour and the kind word ("Trading") in it, dividers starting at the text, and each deal's page follows its colour (the owner's call): the top glow, the deal card's glow and tag (`BalanceCard`, `DealKind.tintBase`; pink still when behind), Add cards and Review deal (`tintButton`, white text on blue/purple), and the review's Complete deal (`Button3D` `.blue` / `.lime` / `.purple`); "Make it a trade" is purple, then Saved for later (parked deals, renamed by the owner: "Park" is "Save for later" everywhere, app and web, with no line under it; resume on tap, a ⋯ on each row: Resume deal / Delete deal, View all = `ParkedDealsSheet`) and Closed deals (opens the record, View all = Closed deals; was Recent deals). Closed deals (`DealHistoryView`, cleaned up and tightened by the owner's ask; no Saved for later section, it lives on the Deal tab): search, "Profit from deals" + the big number + one quiet line ("2 deals · +$778.29 cash"; no pills, no separate sale profit), the climb chart, Best deal on a plain glass card (no electric border), All / Buys / Sales / Trades, then each day as a heading (name, quiet count, profit) over the same `DealListRow` rows as the Deal tab's Closed deals ("Trading · 3 cards · 1:47 PM", cash, "+$33.61 profit"); no Cash in / Cash out lines, no big deal cards. A deal (`DealEditorPage`, bar title "Buying cards" / "Selling cards" / "Trading cards", back = leave sheet: Park deal / Discard deal): "New purchase / sale / trade" with a glass ⋯ (Name / Rename deal, Change deal type (Buying / Selling / Trading, a second page; dropping a side with cards asks first in a centred alert (attached to the editor page, raised 0.4 s after the sheet closes): "Remove the 2 cards you're selling?" Cancel / Remove and switch), Park deal, Delete deal) beside it; a buy or sale ends its card list with "Also selling cards? / Also buying cards? Make it a trade" (turns it into a trade on that side and opens the add sheet); the type never switches by itself (`@AppStorage("deal-name")`, used when parking), "Untitled deal · N cards"; on a trade a "Coming in · $X | Going out · $Y" switch (the owner's wording; the lists under it and the rate say Coming in / Going out; a plain buy or sale keeps Buying / Selling rate); the rate card ("Buying / Selling / Receiving / Giving rate · Default for all cards", big %, 75 · 80 · 85 · 90 · 100% and ⋯ → `DealRateSheet` "Set default rate"); a glass Scan card and a lime Add cards; "Cards N · $X market" rows (name, set · number, market, price and a small % pill with a pencil when the card has its own price); tap a card → `DealCardSheet` (Percentage / Fixed price, big field, the line under it (price per card on a %, share of market on a fixed price), market price (changed by hand: "Reset to catalog price ($X)", the catalog price kept as `DealItem.catalogMarket`, and the card row reads "$18.00 market (was $20.89)"), quantity, Reset to deal rate, Save changes, Remove card). A total rounded on the review screen (`agreedCash`) shows above the total as "Rounded −$4.00 · Reset" (`DealStore.clearAgreedTotal`, also puts the side's % back on a whole number), and a card moved off a whole % by it shows its true share ("99.6%") with the pencil. Pinned at the bottom: Market value (or I receive / I give on a trade), one big white line, "You pay $X" / "You receive $X" / "Even trade" (with "% of market" on a buy or sale), a park button and a lime Review deal (opens `DealCloseSheet`). What you paid counts when selling or trading cards away: each card going out shows "Paid $X" (from your collection's FIFO cost via `deals.cost`, or typed: "Add what you paid" in lime) and its profit under the price; the bottom shows Cost basis and Profit · margin ("Profit on what I sell" on a trade) once every card going out has a cost; `DealCardSheet` shows You paid (read-only from the collection, else a You paid each field saved to `DealItem.cost`) and the profit. The old lime deal card (`BalanceCard` in `DealView.swift`: kind tag, verdict pill, "You pay them / They pay you" with the big cash (tap to type an agreed cash), then the side's rate inside the same card (the owner's call: one card): "Buying / Selling rate · Default for all cards", the %, a Round up chip beside it (next $5; Undo round once rounded), and the 75–100% chips + ⋯ (dark on lime, the picked one white); the separate rate card and the round pills are gone from the deal page, and its figures with ⓘ behind Details (folded by default), the original names, per deal kind (`DealFigures`, the owner's pick): Market value · Buying rate ("Paid at" on a past deal) · Profit (buy, three across); You paid · Market value · Profit (sell, three across; a past sale's market value isn't recorded, so —); Coming in · Going out · Sale profit · Trade-in value (trade, two by two). Profit reads "Loss" by itself when negative. On the deal page Market value has a pencil: type the market value you agreed on (`DealStore.setAgreedMarket`, shared across the side's cards in proportion, each keeping its catalog price; the label reads "Agreed market"; "Back to catalog prices" in the same box). Every ⓘ opens a small fitted sheet (`TermSheet`: name + one line + round close), not a speech-bubble tip.) is back at the top of the deal page, under the title (the owner's call, passed in as `DealEditorPage.card`); the pinned bottom is just park and Review deal. The review screen (`DealCloseSheet`) shows the deal card as a read-only summary (`dealSummaryCard`: verdict, amount, figures open; no pencil, chips or pills), then the Buying / Selling rows and "Complete deal · $X"; rounding happens on the deal page's card. A past deal's page (`DealRecordDetail` in `DealHistory.swift`) shows the same read-only card (`dealSummaryCard(..., past: true)`, built from the record with `DealTotals(record:)`; "You made a profit"), under the date as a quiet line; then the Came in / Went out sections with cash as a line. One way to show a deal everywhere (the owner's call: deal page, review, past deal). The Deal tab opens on a copy kept on the phone (`DealSnapshotFile`: the open deal, rates, past and parked deals, per account in Caches, deleted on sign-out) and refreshes it; the four lists load together and alongside the collection, not after it. The pick is `@AppStorage("deal-path")`. The older pieces in `DealView.swift` (receipt bar, `DealRow`, `RateChips`, `DealPathChooser`, `BalanceCard`…) are no longer shown.
- Not in the app on purpose: the separate trade checker (the Deal tab covers trades), and the welcome pages (removed; signed out opens straight on Sign in, its card wall is `Features/Auth/CardWall.swift`).
