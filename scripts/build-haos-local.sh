#!/bin/sh
# Run a local HAOS build without requiring a TTY.
#
# On macOS, keep /build/output on a Docker volume. The default APFS volume is
# usually case-insensitive, while Linux kernel headers contain case-distinct
# paths that must coexist during Buildroot extraction.
set -eu

HAOS_DIR="${HAOS_DIR:-$PWD/work/haos}"
HAOS_TARGET="${HAOS_TARGET:-google_kukui}"
CACHE_DIR="${CACHE_DIR:-$HOME/hassos-cache}"
HAOS_BUILDER_IMAGE="${HAOS_BUILDER_IMAGE:-hassos:local}"
HAOS_OUTPUT_VOLUME="${HAOS_OUTPUT_VOLUME:-haos-${HAOS_TARGET}-output}"
MAKE_TARGET="${1:-$HAOS_TARGET}"

if [ ! -d "$HAOS_DIR" ]; then
    echo "ERROR: HAOS_DIR does not exist: $HAOS_DIR" >&2
    exit 1
fi

mkdir -p "$CACHE_DIR"
docker volume create "$HAOS_OUTPUT_VOLUME" >/dev/null

echo "HAOS_DIR=$HAOS_DIR"
echo "HAOS_TARGET=$HAOS_TARGET"
echo "MAKE_TARGET=$MAKE_TARGET"
echo "CACHE_DIR=$CACHE_DIR"
echo "HAOS_OUTPUT_VOLUME=$HAOS_OUTPUT_VOLUME"

docker run -i --rm --privileged \
    -v "$HAOS_DIR:/build" \
    -v "$CACHE_DIR:/cache" \
    -v "$HAOS_OUTPUT_VOLUME:/build/output" \
    -e BUILDER_UID="$(id -u)" \
    -e BUILDER_GID="$(id -g)" \
    "$HAOS_BUILDER_IMAGE" make "$MAKE_TARGET"
