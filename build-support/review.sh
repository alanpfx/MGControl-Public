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
  else echo "::error::Review stage failed: $stage. Owner diagnostics are encrypted."; return 1; fi
}
cd "$SOURCE"
ACTUAL_SHA=$(git rev-parse HEAD)
if [[ ! "$REVIEW_SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || [ "$ACTUAL_SHA" != "$REVIEW_SOURCE_SHA" ]; then
  echo "::error::Immutable private review pin mismatch."; exit 1
fi
quiet metadata python3 "$SUPPORT/review-results.py" metadata --version-file version.json --github-env "$GITHUB_ENV"
quiet public-support-tests python3 -m unittest discover -s "$SUPPORT" -p 'test_*.py' -q
quiet toolchain xcodebuild -version
if ! command -v xcodegen >/dev/null; then quiet dependencies brew install xcodegen; fi
quiet generate python3 scripts/upgrade_v02.py
quiet configuration python3 scripts/validate_v02.py
quiet version python3 scripts/check_version_consistency.py
quiet encoding python3 scripts/check_source_encoding.py
quiet build-support-tests python3 -m unittest discover -s scripts -p 'test_*.py' -q
quiet project xcodegen generate --spec project-v02.json
SIMULATOR_ID=$(python3 scripts/select_simulator.py 2>"$LOGS/simulator.log")
if [[ ! "$SIMULATOR_ID" =~ ^[0-9a-fA-F-]{36}$ ]]; then echo "::error::No valid review simulator."; exit 1; fi
quiet simulator-boot python3 "$SUPPORT/boot-simulator.py" "$SIMULATOR_ID"
quiet tests xcodebuild test -project MGControl.xcodeproj -scheme MGControl -configuration Debug \
  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 90 -maximum-test-execution-time-allowance 180 \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -destination-timeout 120 \
  -resultBundlePath build/Tests.xcresult CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
quiet previews xcrun xcresulttool export attachments --path build/Tests.xcresult --output-path "$LOGS/previews"
quiet summary python3 "$SUPPORT/review-results.py" summary --version-file version.json --log "$LOGS/tests.log" \
  --source-sha "$REVIEW_SOURCE_SHA" --output "$ROOT/public-output/review/summary.json"
echo "Native unit and UI checks passed. No IPA or release was generated."
