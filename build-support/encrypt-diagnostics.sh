#!/bin/bash
set -euo pipefail
umask 077
ROOT="$GITHUB_WORKSPACE"
CERT="$ROOT/public-build/build-support/diagnostics-certificate.pem"
LOGS="$ROOT/_private/logs"
if [ ! -d "$LOGS" ] || [ ! -f "$CERT" ]; then exit 0; fi
mkdir -p "$ROOT/public-output/diagnostics"
# No source archive, xcresult or raw diagnostic log is published.
tar -czf "$ROOT/_private/build-logs.tar.gz" -C "$LOGS" .
openssl cms -encrypt -binary -aes-256-cbc -outform DER \
  -in "$ROOT/_private/build-logs.tar.gz" \
  -out "$ROOT/public-output/diagnostics/build-logs.p7m" "$CERT" >/dev/null 2>&1
echo "Encrypted diagnostics prepared; the decryption key is not stored in GitHub."
