#!/usr/bin/env bash
# Usage: check_signing.sh <phone.apk> <wear.apk>
# Prints the signing certificate SHA-256 of both APKs; exits 1 if they differ.
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 <phone.apk> <wear.apk>" >&2
  exit 2
fi

APKSIGNER="$(command -v apksigner || true)"
if [ -z "$APKSIGNER" ]; then
  SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  APKSIGNER="$(ls -d "$SDK"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1 || true)"
fi
if [ -z "$APKSIGNER" ]; then
  echo "apksigner not found (set ANDROID_HOME)" >&2
  exit 2
fi

cert() {
  "$APKSIGNER" verify --print-certs "$1" | sed -n 's/.*certificate SHA-256 digest: //p' | head -1
}

phone="$(cert "$1")"
wear="$(cert "$2")"
echo "phone: $phone"
echo "wear:  $wear"

if [ -z "$phone" ] || [ "$phone" != "$wear" ]; then
  echo "ERROR: signing certificates differ" >&2
  exit 1
fi
echo "OK: signing certificates match"
