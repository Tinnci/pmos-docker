#!/bin/sh
# Add the MT8183 AFE empty-status IRQ RFC patch to the pmaports kernel package.
#
# This script intentionally only touches the kernel source patch list. Existing
# local kernel config changes remain owned by patch-kernel-otbr.sh.
set -eu

KERNEL_PKG="linux-postmarketos-mediatek-mt81"
PATCH_NAME="mt8183-afe-spurious-irq-rfc.patch"
PATCH_SOURCE="/scripts/$PATCH_NAME"

find_aport_dir() {
	PMAPORTS_DYNAMIC=""
	if command -v pmbootstrap >/dev/null 2>&1; then
		for _home in /work/pmbootstrap /root /home/pmbuild; do
			_ap=$(HOME="$_home" pmbootstrap config aports 2>/dev/null || true)
			if [ -n "$_ap" ] && [ -d "$_ap" ]; then
				PMAPORTS_DYNAMIC="$_ap"
				break
			fi
		done
	fi

	SEARCH_DIRS="
		/work/pmbootstrap/cache_git/pmaports/device/community/$KERNEL_PKG
		/work/pmbootstrap/.local/var/pmbootstrap/cache_git/pmaports/device/community/$KERNEL_PKG
	"
	if [ -n "$PMAPORTS_DYNAMIC" ]; then
		SEARCH_DIRS="$PMAPORTS_DYNAMIC/device/community/$KERNEL_PKG
$SEARCH_DIRS"
	fi

	for d in $SEARCH_DIRS; do
		d=$(echo "$d" | tr -d ' ')
		[ -z "$d" ] && continue
		if [ -f "$d/APKBUILD" ]; then
			echo "$d"
			return 0
		fi
	done
	return 1
}

increment_pkgrel() {
	apkbuild="$1"
	current=$(sed -n 's/^pkgrel=\([0-9][0-9]*\)$/\1/p' "$apkbuild")
	if [ -z "$current" ]; then
		echo "ERROR: unsupported pkgrel format in $apkbuild" >&2
		exit 1
	fi
	next=$((current + 1))
	sed -i "s/^pkgrel=$current$/pkgrel=$next/" "$apkbuild"
	echo "✓ pkgrel: $current -> $next"
}

APORT_DIR="$(find_aport_dir)" || {
	echo "ERROR: could not find $KERNEL_PKG aport. Run pmbootstrap init/pull first." >&2
	exit 1
}

APKBUILD="$APORT_DIR/APKBUILD"
test -f "$PATCH_SOURCE" || {
	echo "ERROR: missing patch source: $PATCH_SOURCE" >&2
	exit 1
}

echo "✓ kernel aport: $APORT_DIR"
cp "$PATCH_SOURCE" "$APORT_DIR/$PATCH_NAME"

if grep -q "^[[:space:]]*$PATCH_NAME$" "$APKBUILD"; then
	echo "✓ $PATCH_NAME already listed in APKBUILD source"
else
	if grep -q "^[[:space:]]*mt8183-fix-bluetooth.patch$" "$APKBUILD"; then
		sed -i "/^[[:space:]]*mt8183-fix-bluetooth\\.patch$/a\\\t$PATCH_NAME" "$APKBUILD"
	else
		sed -i "/linux-\\\$_kernver\\.tar\\.xz$/a\\\t$PATCH_NAME" "$APKBUILD"
	fi
	echo "✓ added $PATCH_NAME to APKBUILD source"
	increment_pkgrel "$APKBUILD"
fi

echo ""
echo "=== MT8183 AFE patch package state ==="
sed -n '1,70p' "$APKBUILD" | grep -E '^pkgver=|^pkgrel=|mt8183|source=' || true
echo ""
echo "Next workflow step must run:"
echo "  pmbootstrap checksum $KERNEL_PKG"
