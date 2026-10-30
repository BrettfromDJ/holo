# Holo for iPhone

A native SwiftUI app that uses the same account and collection as the website. It talks to:

- **Supabase**: sign-in (email + 6-digit code) and your collection, protected per user.
- **The web app's API** (your Vercel deployment): scanning, search and catalog import. It sends your login token, so the TCG API key stays on the server.

## What's in this first version

- Sign in with the same email as the website.
- Collection: total value, today's change, all-time gain, and every item. Played copies are estimated from the Near Mint price (marked ≈), the same as on the web.
- Card page: market price, 24h/7d/30d change, price history chart, your copies.
- Search any card or sealed product and add a purchase (printing, condition or grade, quantity, price, date).
- Scanner: a full-screen camera with rapid shooting, a swipeable strip of scans, and a review step to set what you paid and add them all.

Not yet in the app (still on the website): selling, the deal maker, trades, grading, binder, shelves, portfolios, the watchlist and wishlist. Graded slabs show your own valuation if you've set one on the web. The app doesn't have the website's eBay pricing yet.

The cost basis math is a direct port of the web app's FIFO ledger (`Domain/Ledger.swift` ↔ `src/lib/finance/ledger.ts`), so both show the same numbers. `HoloTests` covers it.

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

For each new build, bump `CURRENT_PROJECT_VERSION` in `project.yml`, run `xcodegen`, then archive again.

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
