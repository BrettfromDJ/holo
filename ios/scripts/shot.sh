#!/bin/bash
# Build the iPhone app, run it in the simulator and save screenshots, so a Claude Code session
# on this Mac can look at what it built.
#
#   ios/scripts/shot.sh                      # your real collection (sign in once in the simulator)
#   ios/scripts/shot.sh -HoloDemo            # the made-up mixed collection, no sign-in
#   ios/scripts/shot.sh -HoloDemo -HoloDemoKind graded -HoloTab collection
#   ios/scripts/shot.sh -HoloDemo -HoloProduct sample:es-bb
#
# The screenshot lands in ios/shots/ (git-ignored). For every screen scrolled top to bottom
# (demo data), use scripts/shots-all.sh instead.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${DEVICE:-iPhone 17 Pro}"
OUT="shots"
mkdir -p "$OUT"

command -v xcodegen >/dev/null && xcodegen generate >/dev/null

UDID=$(xcrun simctl list devices available -j | python3 -c "
import json,sys
want=sys.argv[1]
devs=[d for k,v in json.load(sys.stdin)['devices'].items() if 'iOS' in k for d in v]
pick=next((d for d in devs if d['name']==want), None) or next(d for d in devs if d['name'].startswith('iPhone'))
print(pick['udid'])" "$DEVICE")
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator

echo "Building…"
xcodebuild build -project Holo.xcodeproj -scheme Holo -destination "id=$UDID" \
  -derivedDataPath build/DerivedData -quiet CODE_SIGNING_ALLOWED=NO
APP=$(find build/DerivedData/Build/Products -name "Holo.app" -path "*iphonesimulator*" | head -1)
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")

xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
sleep 5

STAMP=$(date +%H%M%S)
xcrun simctl io "$UDID" screenshot "$OUT/$STAMP-0.png" >/dev/null
echo "$OUT/$STAMP-0.png"
