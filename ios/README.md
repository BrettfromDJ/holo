# Holo for iPhone

A native SwiftUI app that uses the same account and collection as the website. It talks to:

- **Supabase**: sign-in (email + 6-digit code) and your collection, protected per user.
- **The web app's API** (your Vercel deployment): scanning, search and catalog import. It sends your login token, so the TCG API key stays on the server.

## What's in it

- **Sign in** with the same email as the website (6-digit code).
- **Home:** value with a chart you can scrub (1W to All), today's change, all-time gain, what's moving today, recently added.
- **Collection:** everything you hold. Played copies are estimated from the Near Mint price (marked ≈), as on the web.
- **Card page:** market price and changes, price history, your copies, Add, Watch price, Wishlist.
- **Your copy:** sell (fees, shipping, profit from your oldest copies first), set a graded slab's value, and edit or delete past purchases and sales. Edits and deletes are saved as corrections, the same as on the web.
- **Scan:** full-screen camera, rapid shooting, a swipeable strip of scans, and a review step to set conditions and prices before adding.
- **Deal:** the card-show deal maker. Coming in / going out, rates as a share of market (adjustable per deal and per item), cash balance, profit and equity, scanning into either side, closing records it all, and a history of closed deals. The deal in progress syncs with the website's Deal page.
- **Explore:** brands, sets, set pages, upcoming releases and a release calendar with reminders (a notification at 9am on release day), and search with filters (type, language, brand, owned, watchlist, price) and sorting.
- **Card pages** for anything in the catalog: "What's it worth?" (TCGplayer prices per condition, eBay medians per grade, estimates marked ≈), recent eBay sales linking to the listings.
- **Slabs** are priced from recent eBay sales for their exact grade, unless you set your own value.
- **Watchlist and Wishlist** (from Home's toolbar): targets and priorities, shared with the website. A watch with a target sends a **push notification** when the daily price check finds it at or below the target.

Still website-only: trade checker, grading, binder, shelves, portfolios, analytics.

The cost basis math is a direct port of the web app's FIFO ledger (`Domain/Ledger.swift` ↔ `src/lib/finance/ledger.ts`), and the deal math of `src/lib/deal.ts` (`Domain/Deal.swift`), so both show the same numbers. `HoloTests` covers them.

## Build it

You need a Mac with **Xcode 16** and an Apple Developer account.

1. Install XcodeGen, which generates the Xcode project from `project.yml`:
   ```sh
   brew install xcodegen
   ```
2. Fill in the config:
   ```sh
   cd ios
   cp Config.xcconfig.example Config.xcconfig
   open -e Config.xcconfig
   ```
   - `HOLO_API_HOST`: your Vercel domain, e.g. `holo-bay.vercel.app`. Write it without `https://`.
   - `SUPABASE_HOST` and `SUPABASE_ANON_KEY`: the same values as `NEXT_PUBLIC_SUPABASE_URL` (minus `https://`) and `NEXT_PUBLIC_SUPABASE_ANON_KEY` in Vercel. The anon key is public by design.
   - `HOLO_BUNDLE_ID`: a reverse-domain id you own, e.g. `co.designjoy.holo`.
   - `HOLO_TEAM_ID`: Xcode → Settings → Accounts → your team → Team ID.

   `Config.xcconfig` is git-ignored.
3. Generate and open the project:
   ```sh
   xcodegen
   open Holo.xcodeproj
   ```
   Re-run `xcodegen` whenever files are added or removed. Xcode fetches the Supabase Swift package the first time.
4. Pick your iPhone (or a simulator) and press **Run**. The camera needs a real device.

The web app must be deployed with the change that accepts the app's login token (`getRequestUser` in `src/lib/supabase/server.ts`). Otherwise scanning will say "Sign in to scan."

## Ship to TestFlight

1. In [App Store Connect](https://appstoreconnect.apple.com) → Apps → **+** → New App. Choose iOS, name it "Holo", and pick the same bundle id as `HOLO_BUNDLE_ID`.
2. In Xcode, set the run destination to **Any iOS Device (arm64)**, then **Product → Archive**.
3. When the Organizer opens, choose **Distribute App → App Store Connect → Upload**. Keep automatic signing.
4. After processing (about 10–30 minutes), the build appears under TestFlight in App Store Connect. Add yourself as an internal tester and install with the TestFlight app.

For each new build: `git pull`, run `xcodegen`, then archive and upload again. The build number is set automatically from the date and time (a build step in `project.yml`), so it always goes up. To change the version people see (0.1.0), edit `MARKETING_VERSION` in `project.yml`.

## Push notifications (one-time setup)

Price alerts are sent by the website's daily price sync, so the server needs an Apple push key:

1. In Supabase → SQL Editor, run `supabase/migrations/20261031000000_push_notifications.sql`.
2. At [developer.apple.com](https://developer.apple.com/account/resources/authkeys/list) → Certificates, IDs & Profiles → **Keys** → **+**. Name it "Holo push", tick **Apple Push Notifications service (APNs)**, then Continue → Register → **Download** the `.p8` file (you can only download it once). Note the **Key ID**.
3. In Vercel → Settings → Environment Variables, add:
   - `APNS_KEY_ID`: the Key ID
   - `APNS_TEAM_ID`: your Team ID (the same one as in `Config.xcconfig`)
   - `APNS_BUNDLE_ID`: your bundle id, e.g. `co.designjoy.holo`
   - `APNS_PRIVATE_KEY`: open the `.p8` file in TextEdit and paste its whole contents, including the BEGIN/END lines
   
   Then redeploy.
4. In Xcode, the app's **Signing & Capabilities** should list **Push Notifications** (it comes from `Holo.entitlements`). If Xcode shows a signing error after `xcodegen`, click **Try Again**.

The phone asks for permission the first time you set a watch target or a release reminder. Builds run from Xcode use Apple's sandbox, and TestFlight builds use production. The app records which one, so both work. Release reminders don't need any of this; they're scheduled on the phone.

## Continuous build

`.github/workflows/ios.yml` builds the app and runs the tests on a GitHub-hosted Mac whenever `ios/` changes. It doesn't sign or upload anything.

## Layout

```
ios/
  project.yml            XcodeGen project definition
  Config.xcconfig        your settings (from Config.xcconfig.example)
  Holo/
    App/                 entry point, tabs
    Core/                config, theme, formatting
    Data/                API and database models, Supabase + web API clients
    Domain/              ledger (cost basis) and portfolio valuation
    Store/               session and collection state
    Features/            Auth, Collection, Product, Search, Scan, Settings
    Components/          shared views
    Resources/           asset catalog (icon, accent color)
  HoloTests/             ledger and valuation tests
```
