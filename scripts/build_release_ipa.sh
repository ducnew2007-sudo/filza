#!/bin/bash
set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "usage: $0 <base-unsigned.ipa> <output.ipa> [MCMIdentifiers.plist]" >&2
  exit 64
fi

BASE_IPA="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUTPUT_IPA="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
CATALOG="${3:-}"
if [ -n "$CATALOG" ]; then
  CATALOG="$(cd "$(dirname "$CATALOG")" && pwd)/$(basename "$CATALOG")"
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
THEOS="${THEOS:-$HOME/theos}"
export THEOS

[ -f "$BASE_IPA" ] || { echo "base IPA not found: $BASE_IPA" >&2; exit 66; }
if [ -n "$CATALOG" ]; then
  [ -f "$CATALOG" ] || { echo "catalog not found: $CATALOG" >&2; exit 66; }
  plutil -lint "$CATALOG" >/dev/null
  plutil -extract AppData xml1 -o /dev/null "$CATALOG"
fi

cd "$REPO_ROOT"
make clean
make package FINALPACKAGE=1

DYLIB="$REPO_ROOT/.theos/obj/FilzaApplySandboxExt.dylib"
[ -f "$DYLIB" ] || { echo "built dylib not found: $DYLIB" >&2; exit 70; }

STAGE_ROOT="$(mktemp -d /tmp/FilzaSlop-release.XXXXXX)"
trap 'rm -rf "$STAGE_ROOT"' EXIT
unzip -q "$BASE_IPA" -d "$STAGE_ROOT/stage"

APP="$(find "$STAGE_ROOT/stage/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
[ -n "$APP" ] || { echo "Payload app not found" >&2; exit 65; }

BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP/Info.plist")"
if [ "$BUNDLE_ID" != "com.apple.mobile.MobileHouseArrest" ]; then
  echo "warning: bundle identifier is $BUNDLE_ID" >&2
fi

if codesign -d "$APP" >/dev/null 2>&1; then
  echo "base app is signed; use an unsigned base IPA" >&2
  exit 65
fi

mkdir -p "$APP/Frameworks"
cp "$DYLIB" "$APP/Frameworks/FilzaApplySandboxExt.dylib"
codesign --remove-signature "$APP/Frameworks/FilzaApplySandboxExt.dylib" 2>/dev/null || true

if [ -n "$CATALOG" ]; then
  cp "$CATALOG" "$APP/MCMIdentifiers.plist"
elif [ -e "$APP/MCMIdentifiers.plist" ]; then
  rm -f "$APP/MCMIdentifiers.plist"
fi

if [ -e "$OUTPUT_IPA" ]; then
  rm -f "$OUTPUT_IPA"
fi
(
  cd "$STAGE_ROOT/stage"
  zip -qry "$OUTPUT_IPA" Payload
)

shasum -a 256 "$OUTPUT_IPA"
