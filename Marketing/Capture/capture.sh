#!/bin/zsh
# Films the app screens for the App Store preview videos and cuts them
# into named clips under Marketing/Captures/<lang>/.
#
#   Marketing/Capture/capture.sh tr            # every take, Turkish
#   Marketing/Capture/capture.sh en test2Break # one take, English
#
# Env: CAPTURE_UDID (default: first booted iPhone 17 Pro Max),
#      SKIP_BUILD=1 to reuse the last build.
set -euo pipefail
cd "$(dirname "$0")/../.."

lang=${1:?usage: capture.sh <tr|en> [test ...]}; shift
case $lang in
  tr) region=TR ;;
  en) region=US ;;
  *) echo "language must be tr or en"; exit 1 ;;
esac
tests=(test1Journey test2Break test3Tasks test4SkyAndInsights test5YearsOfSky test6OdysseySky test7FinishedUniverse test8SurfaceVisit test9RareEvent test10Together test11YearInReview)
(( $# )) && tests=($@)

udid=${CAPTURE_UDID:-$(xcrun simctl list devices booted | grep -m1 "iPhone 17 Pro Max" | grep -oE '[0-9A-F-]{36}')}
[[ -n $udid ]] || { echo "Boot an iPhone 17 Pro Max simulator or set CAPTURE_UDID"; exit 1; }
derived=$HOME/Library/Developer/Xcode/DerivedData/LumoraCapture
out=Marketing/Captures/$lang
raw=$out/raw
mkdir -p $raw $derived

cutter=$derived/cutclips
if [[ ! -x $cutter || Marketing/Capture/cutclips.swift -nt $cutter ]]; then
  swiftc -O -swift-version 5 Marketing/Capture/cutclips.swift -o $cutter
fi

if [[ -z ${SKIP_BUILD:-} ]]; then
  echo "Building…"
  xcodebuild build-for-testing -project Lumora.xcodeproj -scheme Lumora \
    -destination "id=$udid" -derivedDataPath $derived -quiet
fi

xcrun simctl ui $udid appearance dark
xcrun simctl status_bar $udid override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

for t in $tests; do
  echo "Filming $t ($lang)…"
  rm -f $raw/$t.*(N)
  # A session left running by the previous take must not leak into this one.
  xcrun simctl terminate $udid com.mobapptech.lumora 2>/dev/null || true
  xcrun simctl io $udid recordVideo --codec h264 --force $raw/$t.mp4 2> $raw/$t.rec.log &
  recorder=$!
  for _ in {1..100}; do grep -q "Recording started" $raw/$t.rec.log 2>/dev/null && break; sleep 0.1; done
  started=$(python3 -c 'import time; print(time.time())')

  TEST_RUNNER_LUMORA_CAPTURE=1 TEST_RUNNER_CAPTURE_LANG=$lang \
    xcodebuild test-without-building -project Lumora.xcodeproj -scheme Lumora \
    -destination "id=$udid" -derivedDataPath $derived \
    -only-testing:LumoraUITests/MarketingCaptureTests/$t \
    -testLanguage $lang -testRegion $region > $raw/$t.log 2>&1 \
    || echo "  $t did not finish cleanly; see $raw/$t.log"

  kill -INT $recorder; wait $recorder || true
  $cutter $raw/$t.mp4 $started $raw/$t.log $out | sed 's/^/  /' || true
done

xcrun simctl status_bar $udid clear
echo "Clips: $out"
