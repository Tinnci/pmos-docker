#!/bin/sh
# Copy the Home Assistant kiosk UI package into a local pmaports checkout and
# select it in pmbootstrap.
#   scripts/install-ha-kiosk-ui.sh            # copy + checksum + select UI
# Run as the user that owns the pmbootstrap work directory (HOME must match).
set -eu

HERE="$(cd "$(dirname "$0")/.." && pwd)"
PKG=postmarketos-ui-ha-kiosk
SRC="$HERE/pmaports-overlay/$PKG"

APORTS="$(pmbootstrap config aports)"
[ -d "$APORTS/main" ] || { echo "ERROR: pmaports not found at $APORTS (run pmbootstrap init/pull)"; exit 1; }

rm -rf "$APORTS/main/$PKG"
cp -a "$SRC" "$APORTS/main/$PKG"
echo "copied $PKG into $APORTS/main"

pmbootstrap checksum "$PKG"
pmbootstrap config ui ha-kiosk
echo "ui set to ha-kiosk; build the image with: pmbootstrap install"
