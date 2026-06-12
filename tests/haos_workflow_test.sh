#!/bin/sh
set -eu

REPO_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
BUILD_WORKFLOW="$REPO_ROOT/.github/workflows/haos-build.yml"
BUILDER_WORKFLOW="$REPO_ROOT/.github/workflows/haos-builder-image.yml"
BUILDER_DOCKERFILE="$REPO_ROOT/docker/haos-builder/Dockerfile"
TMPDIR="${TMPDIR:-/tmp}"
WORKDIR="$(mktemp -d "$TMPDIR/haos-workflow-test.XXXXXX")"

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

[ -f "$BUILD_WORKFLOW" ] || {
    echo "missing $BUILD_WORKFLOW" >&2
    exit 1
}

assert_contains "$BUILD_WORKFLOW" "validate-scripts:"
assert_contains "$BUILD_WORKFLOW" "config-google-kukui:"
assert_contains "$BUILD_WORKFLOW" "build-google-kukui:"
assert_contains "$BUILD_WORKFLOW" "verify-artifacts:"
assert_contains "$BUILD_WORKFLOW" "actions/cache@v5"
assert_contains "$BUILD_WORKFLOW" "actions/upload-artifact@v6"
assert_contains "$BUILD_WORKFLOW" "actions/download-artifact@v7"
assert_contains "$BUILD_WORKFLOW" "/tmp/haos-cache/dl"
assert_contains "$BUILD_WORKFLOW" "/tmp/haos-ccache"
assert_contains "$BUILD_WORKFLOW" "scripts/haos-buildctl.sh diagnostics"
assert_contains "$BUILD_WORKFLOW" "scripts/haos-buildctl.sh layer-source"
assert_contains "$BUILD_WORKFLOW" "scripts/haos-buildctl.sh layer-builder"
assert_contains "$BUILD_WORKFLOW" "scripts/haos-buildctl.sh layer-download"
assert_contains "$BUILD_WORKFLOW" "scripts/haos-buildctl.sh layer-compile"
assert_contains "$BUILD_WORKFLOW" "scripts/haos-buildctl.sh layer-artifact"
assert_contains "$BUILD_WORKFLOW" 'ghcr.io/${{ github.repository_owner }}/haos-builder:kukui-17.3'
assert_contains "$BUILD_WORKFLOW" "tr '[:upper:]' '[:lower:]'"

[ -f "$BUILDER_WORKFLOW" ] || {
    echo "missing $BUILDER_WORKFLOW" >&2
    exit 1
}
assert_contains "$BUILDER_WORKFLOW" "haos-builder-image"
assert_contains "$BUILDER_WORKFLOW" "actions/checkout@v6"
assert_contains "$BUILDER_WORKFLOW" "docker/login-action@v4"
assert_contains "$BUILDER_WORKFLOW" "docker/build-push-action@v7"
assert_contains "$BUILDER_WORKFLOW" "docker/haos-builder/Dockerfile"
assert_contains "$BUILDER_WORKFLOW" 'ghcr.io/${{ github.repository_owner }}/haos-builder:kukui-17.3'
assert_contains "$BUILDER_WORKFLOW" "tr '[:upper:]' '[:lower:]'"

[ -f "$BUILDER_DOCKERFILE" ] || {
    echo "missing $BUILDER_DOCKERFILE" >&2
    exit 1
}
assert_contains "$BUILDER_DOCKERFILE" "vboot-utils"
assert_contains "$BUILDER_DOCKERFILE" "gdisk"
assert_contains "$BUILDER_DOCKERFILE" "ccache"

echo "haos workflow tests passed"
