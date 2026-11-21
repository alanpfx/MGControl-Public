#!/bin/bash
set -euo pipefail
umask 077
ROOT="$GITHUB_WORKSPACE"
SOURCE="$ROOT/_private/source"
LOGS="$ROOT/_private/logs"
SUPPORT="$ROOT/public-build/build-support"
mkdir -p "$LOGS" "$SOURCE/build" "$ROOT/public-output/review"
quiet() {
  local stage="$1"; shift
  if "$@" >"$LOGS/$stage.log" 2>&1; then echo "Completed: $stage";
  else echo "::error::Preview stage failed: $stage. Owner diagnostics are encrypted."; return 1; fi
}
cd "$SOURCE"
test "$(git rev-parse HEAD)" = "$REVIEW_SOURCE_SHA"
quiet metadata python3 "$SUPPORT/review-results.py" metadata --version-file version.json --github-env "$GITHUB_ENV"
quiet toolchain xcodebuild -version
if ! command -v xcodegen >/dev/null; then quiet dependencies brew install xcodegen; fi
quiet generate python3 scripts/upgrade_v02.py
quiet configuration python3 scripts/validate_v02.py
quiet version python3 scripts/check_version_consistency.py
quiet encoding python3 scripts/check_source_encoding.py
quiet project xcodegen generate --spec project-v02.json
SIMULATOR_ID=$(python3 scripts/select_simulator.py 2>"$LOGS/simulator.log")
[[ "$SIMULATOR_ID" =~ ^[0-9a-fA-F-]{36}$ ]]
quiet simulator-boot python3 "$SUPPORT/boot-simulator.py" "$SIMULATOR_ID"
export_previews() {
  if [ -d build/Tests.xcresult ]; then
    xcrun xcresulttool export attachments --path build/Tests.xcresult --output-path "$LOGS/previews" >"$LOGS/previews.log" 2>&1 || true
  fi
}
trap export_previews EXIT
quiet tests xcodebuild test -project MGControl.xcodeproj -scheme MGControl -configuration Debug \
  -only-testing:MGControlTests/VehicleAppearanceTests \
  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -destination-timeout 120 \
  -resultBundlePath build/Tests.xcresult CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
quiet previews xcrun xcresulttool export attachments --path build/Tests.xcresult --output-path "$LOGS/previews"
trap - EXIT
quiet summary python3 "$SUPPORT/preview-results.py" --log "$LOGS/tests.log" --source-sha "$REVIEW_SOURCE_SHA" --output "$ROOT/public-output/review/summary.json"
echo "Focused native appearance previews passed; no full UI regression, IPA or release."
