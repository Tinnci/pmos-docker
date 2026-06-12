#!/bin/sh
set -eu

REPO_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
WORKFLOWS_DIR="$REPO_ROOT/.github/workflows"
TMPDIR="${TMPDIR:-/tmp}"
WORKDIR="$(mktemp -d "$TMPDIR/actions-node24-test.XXXXXX")"

cleanup() {
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

fail() {
    echo "$*" >&2
    exit 1
}

assert_contains() {
    file="$1"
    text="$2"
    grep -F "$text" "$file" >/dev/null || fail "expected '$text' in $file"
}

for file in "$WORKFLOWS_DIR"/*.yml; do
    assert_contains "$file" 'FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: "true"'
done

if rg -n \
    -e 'actions/checkout@v4' \
    -e 'docker/login-action@v3' \
    -e 'docker/build-push-action@v6' \
    -e 'actions/cache(@|/(restore|save)@)v4' \
    -e 'actions/upload-artifact@v4' \
    -e 'actions/download-artifact@v4' \
    "$WORKFLOWS_DIR" >"$WORKDIR/deprecated-actions.txt"; then
    cat "$WORKDIR/deprecated-actions.txt" >&2
    fail "deprecated Node.js 20 GitHub action pins remain"
fi

assert_contains "$WORKFLOWS_DIR/haos-builder-image.yml" "actions/checkout@v6"
assert_contains "$WORKFLOWS_DIR/haos-builder-image.yml" "docker/login-action@v4"
assert_contains "$WORKFLOWS_DIR/haos-builder-image.yml" "docker/build-push-action@v7"

assert_contains "$WORKFLOWS_DIR/haos-build.yml" "actions/cache@v5"
assert_contains "$WORKFLOWS_DIR/haos-build.yml" "actions/upload-artifact@v6"
assert_contains "$WORKFLOWS_DIR/haos-build.yml" "actions/download-artifact@v7"

echo "actions node24 tests passed"
