#!/bin/bash
# Run the screenshot UI tests in the simulator: Home, Collection, card pages, Deal and the graded
# demo, each scrolled a screen at a time (the same pictures CI publishes to the ci-screenshots
# branch). They use demo data, so no sign-in is needed. Pictures land in ios/shots/all/.
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${DEVICE:-iPhone 17 Pro}"
command -v xcodegen >/dev/null && xcodegen generate >/dev/null
rm -rf shots/all && mkdir -p shots/all
TEST_RUNNER_SCREENSHOT_DIR="$PWD/shots/all" xcodebuild test \
  -project Holo.xcodeproj -scheme Holo \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -only-testing:HoloUITests -parallel-testing-enabled NO \
  -derivedDataPath build/DerivedData -quiet CODE_SIGNING_ALLOWED=NO || true
ls shots/all
