#!/bin/sh
# Cross-build a minimal mainline kernel for google-kukui / Krane (MT8183).
#   KERNEL_VERSION=6.18.13 JOBS=$(nproc) scripts/build-krane-kernel.sh
# Output: $WORK/linux-$KERNEL_VERSION/arch/arm64/boot/{Image,dts/mediatek/*.dtb}
# Needs: gcc-aarch64-linux-gnu, make, flex, bison, bc, libssl-dev, libelf-dev (ccache optional).
set -eu

KERNEL_VERSION="${KERNEL_VERSION:-6.18.13}"
JOBS="${JOBS:-$(nproc)}"
WORK="${WORK:-$PWD/work/krane-kernel}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$WORK/linux-$KERNEL_VERSION"

mkdir -p "$WORK"
if [ ! -d "$SRC" ]; then
    major="${KERNEL_VERSION%%.*}"
    curl -fL -o "$WORK/linux.tar.xz" \
        "https://cdn.kernel.org/pub/linux/kernel/v${major}.x/linux-${KERNEL_VERSION}.tar.xz"
    tar -C "$WORK" -xf "$WORK/linux.tar.xz"
fi

# Apply local kernel patches (idempotent: skipped if already applied).
cd "$SRC"
for p in "$HERE"/kernel/patches/*.patch; do
    [ -f "$p" ] || continue
    if patch -p1 -R --dry-run -s < "$p" >/dev/null 2>&1; then
        echo "patch already applied: $(basename "$p")"
    else
        patch -p1 -N < "$p"
    fi
done

CROSS="aarch64-linux-gnu-"
command -v ccache >/dev/null 2>&1 && CROSS="ccache $CROSS"
export ARCH=arm64
make CROSS_COMPILE="$CROSS" allnoconfig
scripts/kconfig/merge_config.sh -m .config "$HERE/kernel/krane.config"
make CROSS_COMPILE="$CROSS" olddefconfig

# Report fragment options the kernel dropped (unmet dependencies).
for k in $(grep -oE '^CONFIG_[A-Za-z0-9_]+=[ym]' "$HERE/kernel/krane.config" | cut -d= -f1 | sort -u); do
    grep -q "^$k=" .config || echo "WARN: dropped $k"
done

make -j"$JOBS" CROSS_COMPILE="$CROSS" Image modules \
    mediatek/mt8183-kukui-krane-sku0.dtb mediatek/mt8183-kukui-krane-sku176.dtb
