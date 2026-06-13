#!/bin/sh
set -eu

REPO_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
BUILD_WORKFLOW="$REPO_ROOT/.github/workflows/haos-build.yml"
VALIDATE_WORKFLOW="$REPO_ROOT/.github/workflows/haos-validate.yml"
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

assert_not_contains() {
    file="$1"
    text="$2"
    if grep -F "$text" "$file" >/dev/null; then
        echo "did not expect '$text' in $file" >&2
        echo "--- $file ---" >&2
        cat "$file" >&2
        exit 1
    fi
}

[ -f "$BUILD_WORKFLOW" ] || {
    echo "missing $BUILD_WORKFLOW" >&2
    exit 1
}

assert_contains "$BUILD_WORKFLOW" "workflow_dispatch:"
assert_not_contains "$BUILD_WORKFLOW" "  push:"
assert_not_contains "$BUILD_WORKFLOW" "  pull_request:"
assert_contains "$BUILD_WORKFLOW" "permissions:"
assert_contains "$BUILD_WORKFLOW" "contents: read"
assert_contains "$BUILD_WORKFLOW" "packages: read"
assert_contains "$BUILD_WORKFLOW" "concurrency:"
assert_contains "$BUILD_WORKFLOW" "cancel-in-progress: false"
assert_contains "$BUILD_WORKFLOW" "upstream_repo:"
assert_contains "$BUILD_WORKFLOW" 'HAOS_REPO: ${{ inputs.upstream_repo }}'
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

[ -f "$VALIDATE_WORKFLOW" ] || {
    echo "missing $VALIDATE_WORKFLOW" >&2
    exit 1
}
assert_contains "$VALIDATE_WORKFLOW" "name: HAOS validate and upstream probe"
assert_contains "$VALIDATE_WORKFLOW" "push:"
assert_contains "$VALIDATE_WORKFLOW" "pull_request:"
assert_contains "$VALIDATE_WORKFLOW" "schedule:"
assert_contains "$VALIDATE_WORKFLOW" "workflow_dispatch:"
assert_contains "$VALIDATE_WORKFLOW" ".github/workflows/haos-*.yml"
assert_contains "$VALIDATE_WORKFLOW" "scripts/haos-*.sh"
assert_contains "$VALIDATE_WORKFLOW" "scripts/bootstrap-haos-upstream.sh"
assert_contains "$VALIDATE_WORKFLOW" "scripts/patch-haos-*.sh"
assert_contains "$VALIDATE_WORKFLOW" "scripts/build-haos-local.sh"
assert_contains "$VALIDATE_WORKFLOW" "docker/haos-builder/Dockerfile"
assert_contains "$VALIDATE_WORKFLOW" "tests/haos*.sh"
assert_contains "$VALIDATE_WORKFLOW" "tests/actions_node24_test.sh"
assert_contains "$VALIDATE_WORKFLOW" "permissions:"
assert_contains "$VALIDATE_WORKFLOW" "contents: read"
assert_contains "$VALIDATE_WORKFLOW" "packages: read"
assert_contains "$VALIDATE_WORKFLOW" "concurrency:"
assert_contains "$VALIDATE_WORKFLOW" "cancel-in-progress: true"
assert_contains "$VALIDATE_WORKFLOW" "validate-scripts:"
assert_contains "$VALIDATE_WORKFLOW" "source-probe-17-3:"
assert_contains "$VALIDATE_WORKFLOW" "builder-smoke:"
assert_contains "$VALIDATE_WORKFLOW" "config-google-kukui:"
assert_contains "$VALIDATE_WORKFLOW" "scripts/haos-buildctl.sh source-probe"
assert_contains "$VALIDATE_WORKFLOW" "scripts/haos-buildctl.sh layer-builder"
assert_contains "$VALIDATE_WORKFLOW" "scripts/haos-buildctl.sh config"
assert_contains "$VALIDATE_WORKFLOW" "/tmp/haos-cache/dl"
assert_contains "$VALIDATE_WORKFLOW" "/tmp/haos-ccache"

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
assert_contains "$BUILDER_DOCKERFILE" "skopeo"

echo "haos workflow tests passed"
