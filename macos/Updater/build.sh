#!/bin/sh
# Builds SegueUpdater.app into Segue.app/Contents/Helpers (Xcode build
# phase). Universal, ad-hoc signed unless Xcode signs with an identity.
set -e
OUT="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Helpers/SegueUpdater.app"
SRC="$SRCROOT/Updater"
mkdir -p "$OUT/Contents/MacOS"
TMP="$TARGET_TEMP_DIR/segue-updater"
mkdir -p "$TMP"
BINS=""
for ARCH in $ARCHS; do
  xcrun swiftc -O -target "$ARCH-apple-macos11.0" \
    -sdk "$SDKROOT" -o "$TMP/SegueUpdater-$ARCH" "$SRC/main.swift"
  BINS="$BINS $TMP/SegueUpdater-$ARCH"
done
xcrun lipo -create $BINS -output "$OUT/Contents/MacOS/SegueUpdater"
cp "$SRC/Info.plist" "$OUT/Contents/Info.plist"
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
[ -z "$IDENTITY" ] && IDENTITY="-"
codesign --force --sign "$IDENTITY" --timestamp=none "$OUT"
