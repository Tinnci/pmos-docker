#!/bin/sh
set -eu

REPO_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
BUILD_WORKFLOW="$REPO_ROOT/.github/workflows/haos-build.yml"
VALIDATE_WORKFLOW="$REPO_ROOT/.github/workflows/haos-validate.yml"
BUILDER_WORKFLOW="$REPO_ROOT/.github/workflows/haos-builder-image.yml"
BUILDER_DOCKERFILE="$REPO_ROOT/docker/haos-builder/Dockerfile"
BUILDER_ENTRYPOINT="$REPO_ROOT/docker/haos-builder/entry.sh"
TMPDIR="${TMPDIR:-/tmp}"
WORKDIR="$(mktemp -d "$TMPDIR/haos-workflow-test.XXXXXX")"

cleanup() {
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

assert_contains() {
    file="$1"
    text="$2"
    if ! grep -F -- "$text" "$file" >/dev/null; then
        echo "expected '$text' in $file" >&2
        echo "--- $file ---" >&2
        cat "$file" >&2
        exit 1
    fi
}

assert_not_contains() {
    file="$1"
    text="$2"
    if grep -F -- "$text" "$file" >/dev/null; then
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
assert_contains "$BUILD_WORKFLOW" "id-token: write"
assert_contains "$BUILD_WORKFLOW" "attestations: write"
assert_contains "$BUILD_WORKFLOW" "artifact-metadata: write"
assert_contains "$BUILD_WORKFLOW" "concurrency:"
assert_contains "$BUILD_WORKFLOW" "cancel-in-progress: false"
assert_contains "$BUILD_WORKFLOW" "upstream_repo:"
assert_contains "$BUILD_WORKFLOW" 'HAOS_REPO: ${{ inputs.upstream_repo }}'
assert_contains "$BUILD_WORKFLOW" "validate-scripts:"
assert_contains "$BUILD_WORKFLOW" "docker/haos-builder/*.sh"
assert_contains "$BUILD_WORKFLOW" "config-google-kukui:"
assert_contains "$BUILD_WORKFLOW" "build-google-kukui:"
assert_contains "$BUILD_WORKFLOW" "verify-artifacts:"
assert_contains "$BUILD_WORKFLOW" "actions/cache@v5"
assert_contains "$BUILD_WORKFLOW" "actions/upload-artifact@v6"
assert_contains "$BUILD_WORKFLOW" "actions/download-artifact@v7"
assert_contains "$BUILD_WORKFLOW" "actions/attest@v4"
assert_contains "$BUILD_WORKFLOW" "/tmp/haos-cache/dl"
assert_contains "$BUILD_WORKFLOW" "/tmp/haos-ccache"
assert_contains "$BUILD_WORKFLOW" "scripts/haos-buildctl.sh diagnostics"
assert_contains "$BUILD_WORKFLOW" "scripts/haos-buildctl.sh layer-source"
assert_contains "$BUILD_WORKFLOW" "scripts/haos-buildctl.sh layer-builder"
assert_contains "$BUILD_WORKFLOW" "scripts/haos-buildctl.sh layer-download"
assert_contains "$BUILD_WORKFLOW" "scripts/haos-buildctl.sh layer-compile"
assert_contains "$BUILD_WORKFLOW" "scripts/haos-buildctl.sh layer-artifact"
assert_contains "$BUILD_WORKFLOW" "Resolve HAOS builder image digest"
assert_contains "$BUILD_WORKFLOW" "HAOS_BUILDER_IMAGE_DIGEST="
assert_contains "$BUILD_WORKFLOW" "Attest HAOS release artifacts"
assert_contains "$BUILD_WORKFLOW" "subject-checksums: work/haos-artifacts/verification/SHA256SUMS"
assert_contains "$BUILD_WORKFLOW" "Attest HAOS build metadata"
assert_contains "$BUILD_WORKFLOW" "work/haos-artifacts/verification/build-metadata.env"
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
assert_contains "$VALIDATE_WORKFLOW" "docker/haos-builder/*.sh"
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
assert_contains "$VALIDATE_WORKFLOW" "docker build -f docker/haos-builder/Dockerfile -t haos-builder:validate ."
assert_contains "$VALIDATE_WORKFLOW" "HAOS_BUILDER_IMAGE=haos-builder:validate"
assert_contains "$VALIDATE_WORKFLOW" "scripts/haos-buildctl.sh layer-builder"
assert_contains "$VALIDATE_WORKFLOW" "scripts/haos-buildctl.sh config"
assert_contains "$VALIDATE_WORKFLOW" "/tmp/haos-cache/dl"
assert_contains "$VALIDATE_WORKFLOW" "/tmp/haos-ccache"

[ -f "$BUILDER_WORKFLOW" ] || {
    echo "missing $BUILDER_WORKFLOW" >&2
    exit 1
}
assert_contains "$BUILDER_WORKFLOW" "haos-builder-image"
assert_contains "$BUILDER_WORKFLOW" "id-token: write"
assert_contains "$BUILDER_WORKFLOW" "attestations: write"
assert_contains "$BUILDER_WORKFLOW" "artifact-metadata: write"
assert_contains "$BUILDER_WORKFLOW" "actions/checkout@v6"
assert_contains "$BUILDER_WORKFLOW" "docker/login-action@v4"
assert_contains "$BUILDER_WORKFLOW" "docker/build-push-action@v7"
assert_contains "$BUILDER_WORKFLOW" "actions/attest@v4"
assert_contains "$BUILDER_WORKFLOW" "docker/haos-builder/Dockerfile"
assert_contains "$BUILDER_WORKFLOW" "docker/haos-builder/entry.sh"
assert_contains "$BUILDER_WORKFLOW" "HAOS_BUILDER_REPOSITORY=ghcr.io/"
assert_contains "$BUILDER_WORKFLOW" "id: build"
assert_contains "$BUILDER_WORKFLOW" "Attest HAOS builder image"
assert_contains "$BUILDER_WORKFLOW" 'subject-name: ${{ env.HAOS_BUILDER_REPOSITORY }}'
assert_contains "$BUILDER_WORKFLOW" 'subject-digest: ${{ steps.build.outputs.digest }}'
assert_contains "$BUILDER_WORKFLOW" "push-to-registry: true"
assert_contains "$BUILDER_WORKFLOW" "Smoke-check pushed HAOS builder image"
assert_contains "$BUILDER_WORKFLOW" "scripts/haos-buildctl.sh layer-builder"
assert_contains "$BUILDER_WORKFLOW" 'ghcr.io/${{ github.repository_owner }}/haos-builder:kukui-17.3'
assert_contains "$BUILDER_WORKFLOW" "tr '[:upper:]' '[:lower:]'"

[ -f "$BUILDER_DOCKERFILE" ] || {
    echo "missing $BUILDER_DOCKERFILE" >&2
    exit 1
}
assert_contains "$BUILDER_DOCKERFILE" "vboot-utils"
assert_contains "$BUILDER_DOCKERFILE" "gdisk"
assert_contains "$BUILDER_DOCKERFILE" "ccache"
assert_contains "$BUILDER_DOCKERFILE" "device-tree-compiler"
assert_contains "$BUILDER_DOCKERFILE" "linux-base"
assert_contains "$BUILDER_DOCKERFILE" "lz4"
assert_contains "$BUILDER_DOCKERFILE" "python3-pkg-resources"
assert_contains "$BUILDER_DOCKERFILE" "u-boot-tools"
assert_contains "$BUILDER_DOCKERFILE" "vboot-kernel-utils"
assert_contains "$BUILDER_DOCKERFILE" "cgpt"
assert_contains "$BUILDER_DOCKERFILE" "depthcharge-tools_0.6.2-2_all.deb"
assert_contains "$BUILDER_DOCKERFILE" "skopeo"
assert_contains "$BUILDER_DOCKERFILE" "download.docker.com/linux/debian"
assert_contains "$BUILDER_DOCKERFILE" "docker-ce"
assert_contains "$BUILDER_DOCKERFILE" "sudo"
assert_contains "$BUILDER_DOCKERFILE" "COPY docker/haos-builder/entry.sh /usr/sbin/haos-builder-entry.sh"
assert_contains "$BUILDER_DOCKERFILE" 'ENTRYPOINT ["/usr/sbin/haos-builder-entry.sh"]'

[ -f "$BUILDER_ENTRYPOINT" ] || {
    echo "missing $BUILDER_ENTRYPOINT" >&2
    exit 1
}
bash -n "$BUILDER_ENTRYPOINT"
assert_contains "$BUILDER_ENTRYPOINT" "dockerd --storage-driver=vfs"
assert_contains "$BUILDER_ENTRYPOINT" "BUILDER_UID"
assert_contains "$BUILDER_ENTRYPOINT" 'if [ "$run_user" = "root" ]; then'
assert_contains "$BUILDER_ENTRYPOINT" "--preserve-env=BR2_DL_DIR,CCACHE_DIR,FORCE_UNSAFE_CONFIGURE"
assert_contains "$BUILDER_ENTRYPOINT" '-H -u "$run_user"'

echo "haos workflow tests passed"
