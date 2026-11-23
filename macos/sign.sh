#!/bin/sh
# Re-signs a built Segue.app with the project's own certificate ("Segue",
# self-signed), so macOS sees every build as the same app: microphone and
# screen & system audio permissions then survive updates (an ad-hoc
# signature is new each build, and macOS quietly drops them).
#
#   macos/sign.sh path/to/Segue.app [keychain]
#
# The identity must be in the keychain given (or the default ones).
set -e
APP="$1"
KC="$2"
ID="${SEGUE_SIGN_IDENTITY:-Segue}"
[ -d "$APP" ] || { echo "no app at $APP" >&2; exit 1; }

sign() {
  if [ -n "$KC" ]; then
    codesign --force --sign "$ID" --keychain "$KC" --timestamp=none "$@"
  else
    codesign --force --sign "$ID" --timestamp=none "$@"
  fi
}

# Keep the app's entitlements exactly as the build made them.
ENT=$(mktemp -t segue-ent).plist
codesign -d --entitlements :- "$APP" > "$ENT" 2>/dev/null

# Inside out: frameworks and helpers first, the app last.
for f in "$APP"/Contents/Frameworks/*.framework "$APP"/Contents/Frameworks/*.dylib; do
  [ -e "$f" ] && sign "$f"
done
for h in "$APP"/Contents/Helpers/*.app; do
  [ -e "$h" ] && sign "$h"
done
sign --entitlements "$ENT" "$APP"
rm -f "$ENT"

codesign --verify --deep --strict "$APP"
codesign -d -r- "$APP" 2>&1 | grep designated
