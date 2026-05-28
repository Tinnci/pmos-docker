#!/bin/sh
# Clone/update Home Assistant Operating System upstream and apply local OTBR kernel options.
set -eu

HAOS_REPO="${HAOS_REPO:-https://github.com/home-assistant/operating-system.git}"
HAOS_REF="${HAOS_REF:-dev}"
HAOS_DIR="${HAOS_DIR:-/work/haos}"
HAOS_TARGET="${HAOS_TARGET:-generic_aarch64}"
APPLY_OTBR="${APPLY_OTBR:-1}"
SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"

if ! command -v git >/dev/null 2>&1; then
    echo "ERROR: git is required"
    exit 1
fi

if [ ! -d "$HAOS_DIR/.git" ]; then
    echo "Cloning HAOS upstream: $HAOS_REPO ($HAOS_REF)"
    mkdir -p "$(dirname "$HAOS_DIR")"
    git clone --depth 1 --branch "$HAOS_REF" --recurse-submodules "$HAOS_REPO" "$HAOS_DIR"
else
    echo "Updating HAOS upstream: $HAOS_DIR ($HAOS_REF)"
    git -C "$HAOS_DIR" fetch --depth 1 origin "$HAOS_REF"
    git -C "$HAOS_DIR" checkout FETCH_HEAD
    git -C "$HAOS_DIR" submodule update --init --depth 1
fi

if [ "$APPLY_OTBR" = "1" ]; then
    HAOS_DIR="$HAOS_DIR" HAOS_TARGET="$HAOS_TARGET" sh "$SCRIPT_DIR/patch-haos-otbr-fragment.sh"
fi

echo "HAOS source ready: $HAOS_DIR"
echo "Build target: $HAOS_TARGET"
