#!/bin/sh
# Add zM1/OTBR kernel requirements to a HAOS Buildroot target.
set -eu

HAOS_DIR="${HAOS_DIR:-/work/haos}"
HAOS_TARGET="${HAOS_TARGET:-generic_aarch64}"

DEFCONFIG="$HAOS_DIR/buildroot-external/configs/${HAOS_TARGET}_defconfig"
FRAGMENT_DIR="$HAOS_DIR/buildroot-external/kernel"
FRAGMENT_FILE="$FRAGMENT_DIR/zm1-otbr.config"

if [ ! -f "$DEFCONFIG" ]; then
    echo "ERROR: HAOS defconfig not found: $DEFCONFIG"
    echo "Set HAOS_DIR and HAOS_TARGET to an existing Home Assistant OS checkout/target."
    exit 1
fi

EXTERNAL_PATH_REF="$(
    awk '
        match($0, /\$\(BR2_EXTERNAL_[A-Z0-9_]*_PATH\)/) {
            print substr($0, RSTART, RLENGTH)
            exit
        }
    ' "$DEFCONFIG"
)"
if [ -z "$EXTERNAL_PATH_REF" ]; then
    echo "ERROR: unable to detect BR2_EXTERNAL path variable from $DEFCONFIG"
    exit 1
fi
FRAGMENT_REF="${EXTERNAL_PATH_REF}/kernel/zm1-otbr.config"

mkdir -p "$FRAGMENT_DIR"
cat > "$FRAGMENT_FILE" <<'KCONFIG'
# zM1 / OTBR / Matter kernel options carried over from the pmOS kukui build.
CONFIG_IPV6_SUBTREES=y
CONFIG_IPV6_ROUTE_INFO=y
CONFIG_IPV6_MROUTE_MULTIPLE_TABLES=y
CONFIG_IPV6_PIMSM_V2=y
CONFIG_IP_MROUTE_MULTIPLE_TABLES=y
CONFIG_IP_PIMSM_V1=y
CONFIG_IP_PIMSM_V2=y
CONFIG_IP6_NF_MANGLE=y
CONFIG_NET_NS=y
CONFIG_NET_SCH_FQ=y
CONFIG_NET_SCH_FQ_CODEL=y
CONFIG_NET_SCH_CAKE=y
CONFIG_ENCRYPTED_KEYS=y
KCONFIG

if grep -q "kernel/zm1-otbr.config" "$DEFCONFIG"; then
    echo "HAOS defconfig already references zm1-otbr.config"
else
    tmp="$(mktemp)"
    if grep -q '^BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES=' "$DEFCONFIG"; then
        awk -v fragment=" $FRAGMENT_REF" '
            /^BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="/ {
                sub(/"$/, fragment "\"")
            }
            { print }
        ' "$DEFCONFIG" > "$tmp"
    else
        cp "$DEFCONFIG" "$tmp"
        printf '\nBR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="%s"\n' "$FRAGMENT_REF" >> "$tmp"
    fi
    mv "$tmp" "$DEFCONFIG"
fi

echo "Wrote HAOS kernel fragment: $FRAGMENT_FILE"
echo "Updated HAOS target defconfig: $DEFCONFIG"
