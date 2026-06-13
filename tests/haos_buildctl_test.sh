#!/bin/sh
set -eu

REPO_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
BUILDCTL="$REPO_ROOT/scripts/haos-buildctl.sh"
TMPDIR="${TMPDIR:-/tmp}"
WORKDIR="$(mktemp -d "$TMPDIR/haos-buildctl-test.XXXXXX")"

unset HAOS_BUILDER_IMAGE
unset HAOS_CCACHE_DIR
unset HAOS_CCACHE_VOLUME
unset HAOS_OUTPUT_VOLUME
unset HAOS_REF
unset HAOS_REPO
unset HAOS_STATE_DIR
unset HAOS_TARGET

cleanup() {
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

assert_contains() {
    file="$1"
    text="$2"
    if ! grep -F "$text" "$file" >/dev/null; then
        echo "expected '$text' in $file" >&2
        echo "--- $file ---" >&2
        cat "$file" >&2
        exit 1
    fi
}

if sh "$BUILDCTL" help >"$WORKDIR/help.out" 2>"$WORKDIR/help.err"; then
    :
else
    echo "help command failed" >&2
    cat "$WORKDIR/help.err" >&2
    exit 1
fi
assert_contains "$WORKDIR/help.out" "preflight"
assert_contains "$WORKDIR/help.out" "bootstrap"
assert_contains "$WORKDIR/help.out" "verify-artifacts"
assert_contains "$WORKDIR/help.out" "resume-build"
assert_contains "$WORKDIR/help.out" "source-probe"
assert_contains "$WORKDIR/help.out" "layer-source"
assert_contains "$WORKDIR/help.out" "layer-builder"
assert_contains "$WORKDIR/help.out" "layer-download"
assert_contains "$WORKDIR/help.out" "layer-compile"
assert_contains "$WORKDIR/help.out" "layer-artifact"
assert_contains "$WORKDIR/help.out" "HAOS_REPO"
assert_contains "$WORKDIR/help.out" "HAOS_CCACHE_VOLUME"

if HAOS_DIR="$WORKDIR/missing" sh "$BUILDCTL" preflight >"$WORKDIR/preflight.out" 2>"$WORKDIR/preflight.err"; then
    echo "preflight unexpectedly succeeded for missing HAOS_DIR" >&2
    exit 1
fi
assert_contains "$WORKDIR/preflight.err" "HAOS_DIR does not exist"

mkdir -p "$WORKDIR/haos" "$WORKDIR/cache" "$WORKDIR/export"

HAOS_DIR="$WORKDIR/haos" \
CACHE_DIR="$WORKDIR/cache" \
EXPORT_DIR="$WORKDIR/export" \
HAOS_DRY_RUN=1 \
    sh "$BUILDCTL" source-probe >"$WORKDIR/source-probe.out"
assert_contains "$WORKDIR/source-probe.out" "source-probe: HAOS_REPO=https://github.com/home-assistant/operating-system.git HAOS_REF=17.3"
assert_contains "$WORKDIR/source-probe.out" "git ls-remote --exit-code"
assert_contains "$WORKDIR/source-probe.out" "probe checkout"
assert_contains "$WORKDIR/source-probe.out" "check buildroot-external/configs/generic_aarch64_defconfig"
assert_contains "$WORKDIR/source-probe.out" "check buildroot"
assert_contains "$WORKDIR/source-probe.out" "check buildroot-external"
assert_contains "$WORKDIR/source-probe.out" "check buildroot-external/ota/system.conf.gtpl"
assert_contains "$WORKDIR/source-probe.out" "check buildroot-external/scripts/hdd-image.sh"
assert_contains "$WORKDIR/source-probe.out" "check patch anchors"
assert_contains "$WORKDIR/source-probe.out" "SOURCE_PROBE_STATUS=planned"

HAOS_DIR="$WORKDIR/haos" \
CACHE_DIR="$WORKDIR/cache" \
EXPORT_DIR="$WORKDIR/export" \
HAOS_DRY_RUN=1 \
    sh "$BUILDCTL" layer-source >"$WORKDIR/layer-source.out"
assert_contains "$WORKDIR/layer-source.out" "source-probe: HAOS_REPO=https://github.com/home-assistant/operating-system.git HAOS_REF=17.3"
assert_contains "$WORKDIR/layer-source.out" "layer-source: bootstrap HAOS_REF=17.3 HAOS_TARGET=google_kukui"
assert_contains "$WORKDIR/layer-source.out" "scripts/bootstrap-haos-upstream.sh"
assert_contains "$WORKDIR/layer-source.out" "scripts/patch-haos-kukui-board.sh"
assert_contains "$WORKDIR/layer-source.out" "scripts/patch-haos-otbr-fragment.sh"
assert_contains "$WORKDIR/layer-source.out" "verification/build-metadata.env"
assert_contains "$WORKDIR/layer-source.out" "HAOS_REPO=https://github.com/home-assistant/operating-system.git"
assert_contains "$WORKDIR/layer-source.out" "HAOS_REF_RESOLVED_COMMIT="
assert_contains "$WORKDIR/layer-source.out" "HAOS_SOURCE_PROBE_STATUS="
assert_contains "$WORKDIR/layer-source.out" "PATCH_SCRIPT_SHA256_KUKUI="
assert_contains "$WORKDIR/layer-source.out" "PATCH_SCRIPT_SHA256_OTBR="
assert_contains "$WORKDIR/layer-source.out" "OUTPUT_REUSE_MODE="

HAOS_DIR="$WORKDIR/haos" \
CACHE_DIR="$WORKDIR/cache" \
EXPORT_DIR="$WORKDIR/export" \
HAOS_DRY_RUN=1 \
    sh "$BUILDCTL" layer-builder >"$WORKDIR/layer-builder.out"
assert_contains "$WORKDIR/layer-builder.out" "layer-builder: smoke-check"
assert_contains "$WORKDIR/layer-builder.out" "command -v make"
assert_contains "$WORKDIR/layer-builder.out" "command -v git"
assert_contains "$WORKDIR/layer-builder.out" "command -v ccache"
assert_contains "$WORKDIR/layer-builder.out" "command -v sgdisk"
assert_contains "$WORKDIR/layer-builder.out" "vbutil_kernel"

HAOS_DIR="$WORKDIR/haos" \
CACHE_DIR="$WORKDIR/cache" \
EXPORT_DIR="$WORKDIR/export" \
HAOS_DRY_RUN=1 \
    sh "$BUILDCTL" layer-download >"$WORKDIR/layer-download.out"
assert_contains "$WORKDIR/layer-download.out" "/cache/dl"
assert_contains "$WORKDIR/layer-download.out" "make google_kukui-config"
assert_contains "$WORKDIR/layer-download.out" "dbus-glib-source os-agent-source tempio-source"
assert_contains "$WORKDIR/layer-download.out" "FORCE_UNSAFE_CONFIGURE=1"

HAOS_DIR="$WORKDIR/haos" \
CACHE_DIR="$WORKDIR/cache" \
EXPORT_DIR="$WORKDIR/export" \
HAOS_DRY_RUN=1 \
    sh "$BUILDCTL" layer-compile >"$WORKDIR/layer-compile.out"
assert_contains "$WORKDIR/layer-compile.out" "make google_kukui-config"
assert_contains "$WORKDIR/layer-compile.out" "make google_kukui"
assert_contains "$WORKDIR/layer-compile.out" "/build/output"
assert_contains "$WORKDIR/layer-compile.out" "/ccache"
assert_contains "$WORKDIR/layer-compile.out" "FORCE_UNSAFE_CONFIGURE=1"

HAOS_DIR="$WORKDIR/haos" \
CACHE_DIR="$WORKDIR/cache" \
EXPORT_DIR="$WORKDIR/export" \
HAOS_DRY_RUN=1 \
    sh "$BUILDCTL" layer-artifact >"$WORKDIR/layer-artifact.out"
assert_contains "$WORKDIR/layer-artifact.out" "cp -av /out/images/. /export/"
assert_contains "$WORKDIR/layer-artifact.out" "verification/SHA256SUMS"
assert_contains "$WORKDIR/layer-artifact.out" "verification/build-metadata.env"
assert_contains "$WORKDIR/layer-artifact.out" "verify kernel.img"
assert_contains "$WORKDIR/layer-artifact.out" "verify mt8183-kukui*.dtb"
assert_contains "$WORKDIR/layer-artifact.out" "verify ChromeOS kernel GUIDs"

HAOS_DIR="$WORKDIR/haos" \
CACHE_DIR="$WORKDIR/cache" \
EXPORT_DIR="$WORKDIR/export" \
HAOS_DRY_RUN=1 \
    sh "$BUILDCTL" config >"$WORKDIR/config.out"
assert_contains "$WORKDIR/config.out" "make google_kukui-config"
assert_contains "$WORKDIR/config.out" "haos-google_kukui-17-3-output:/build/output"
assert_contains "$WORKDIR/config.out" "haos-google_kukui-17-3-ccache:/ccache"
assert_contains "$WORKDIR/config.out" "BR2_DL_DIR=/cache/dl"
assert_contains "$WORKDIR/config.out" "FORCE_UNSAFE_CONFIGURE=1"

HAOS_DIR="$WORKDIR/haos" \
CACHE_DIR="$WORKDIR/cache" \
EXPORT_DIR="$WORKDIR/export" \
HAOS_DRY_RUN=1 \
    sh "$BUILDCTL" build >"$WORKDIR/build.out"
assert_contains "$WORKDIR/build.out" "make google_kukui"
assert_contains "$WORKDIR/build.out" "CCACHE_DIR=/ccache"

HAOS_DIR="$WORKDIR/haos" \
CACHE_DIR="$WORKDIR/cache" \
EXPORT_DIR="$WORKDIR/export" \
HAOS_DRY_RUN=1 \
    sh "$BUILDCTL" cache-warm >"$WORKDIR/cache-warm.out"
assert_contains "$WORKDIR/cache-warm.out" "dbus-glib-source os-agent-source tempio-source"
assert_contains "$WORKDIR/cache-warm.out" "BR2_DL_DIR=/cache/dl"

HAOS_DIR="$WORKDIR/haos" \
CACHE_DIR="$WORKDIR/cache" \
EXPORT_DIR="$WORKDIR/export" \
HAOS_DRY_RUN=1 \
    sh "$BUILDCTL" export-artifacts >"$WORKDIR/export.out"
assert_contains "$WORKDIR/export.out" "cp -av /out/images/. /export/"

HAOS_DIR="$WORKDIR/haos" \
CACHE_DIR="$WORKDIR/cache" \
EXPORT_DIR="$WORKDIR/export" \
HAOS_DRY_RUN=1 \
    sh "$BUILDCTL" verify-artifacts >"$WORKDIR/verify.out"
assert_contains "$WORKDIR/verify.out" "kernel.img"
assert_contains "$WORKDIR/verify.out" "haos_google-kukui-*.img.xz"

HAOS_DIR="$WORKDIR/haos" \
CACHE_DIR="$WORKDIR/cache" \
EXPORT_DIR="$WORKDIR/export" \
HAOS_DRY_RUN=1 \
    sh "$BUILDCTL" diagnostics >"$WORKDIR/diagnostics.out"
assert_contains "$WORKDIR/diagnostics.out" "== failed Buildroot stamps =="
assert_contains "$WORKDIR/diagnostics.out" "== HAOS checkout diff =="
assert_contains "$WORKDIR/diagnostics.out" "HAOS_REPO=https://github.com/home-assistant/operating-system.git"
assert_contains "$WORKDIR/diagnostics.out" "HAOS_SOURCE_PROBE_STATUS="
assert_contains "$WORKDIR/diagnostics.out" "output_reuse="

echo "haos buildctl tests passed"
