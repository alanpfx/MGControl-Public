#!/bin/bash
set -euo pipefail
umask 077
ROOT="$GITHUB_WORKSPACE"
SOURCE="$ROOT/_private/source"
LOGS="$ROOT/_private/logs"
mkdir -p "$LOGS" "$ROOT/public-output/installers" "$SOURCE/build"
cd "$SOURCE"
# Do not stream compiler output: it can include private source excerpts.
quiet() {
  local stage="$1"; shift
  if "$@" >"$LOGS/$stage.log" 2>&1; then
    echo "Completed: $stage"
  else
    echo "::error::Stage failed: $stage. Detailed logs are encrypted for the owner."
    return 1
  fi
}
if ! command -v xcodegen >/dev/null; then quiet dependencies brew install xcodegen; fi
quiet generate python3 scripts/upgrade_v02.py
quiet configuration python3 scripts/validate_v02.py
quiet encoding python3 scripts/check_source_encoding.py
quiet project xcodegen generate --spec project-v02.json
quiet effective-settings bash -c 'xcodebuild -showBuildSettings -json -project MGControl.xcodeproj -alltargets -configuration Release -sdk iphoneos > build-settings.json && python3 scripts/check_v02_settings.py build-settings.json'
SIMULATOR_ID=$(python3 scripts/select_simulator.py 2>"$LOGS/simulator.log")
quiet tests xcodebuild test -project MGControl.xcodeproj -scheme MGControl -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -destination-timeout 120 \
  -resultBundlePath build/Tests.xcresult CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
quiet widget bash scripts/build_v02.sh widget
quiet app-project xcodegen generate --spec project-app-only.json
quiet app-only bash scripts/build_v02.sh app-only
quiet export python3 "$ROOT/public-build/build-support/export-installers.py" "$SOURCE" "$ROOT/public-output/installers"
echo "Tests and both device builds passed; unsigned installers are ready."
