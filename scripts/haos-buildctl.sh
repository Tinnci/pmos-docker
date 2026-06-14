#!/bin/sh
# Composable HAOS build controller for local and CI workflows.
set -eu

REPO_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"

slugify() {
    printf '%s' "$1" | sed 's/[^A-Za-z0-9_]/-/g'
}

HAOS_REF="${HAOS_REF:-17.3}"
HAOS_REPO="${HAOS_REPO:-https://github.com/home-assistant/operating-system.git}"
HAOS_TARGET="${HAOS_TARGET:-google_kukui}"
HAOS_REF_SLUG="${HAOS_REF_SLUG:-$(slugify "$HAOS_REF")}"
HAOS_DIR="${HAOS_DIR:-$REPO_ROOT/work/haos}"
CACHE_DIR="${CACHE_DIR:-$HOME/hassos-cache}"
EXPORT_DIR="${EXPORT_DIR:-$HAOS_DIR/output-volume-images}"
HAOS_STATE_DIR="${HAOS_STATE_DIR:-$REPO_ROOT/work/haos-buildctl}"
HAOS_SOURCE_PROBE_STATE="${HAOS_SOURCE_PROBE_STATE:-$HAOS_STATE_DIR/source-probe.env}"
HAOS_OUTPUT_VOLUME="${HAOS_OUTPUT_VOLUME:-haos-${HAOS_TARGET}-${HAOS_REF_SLUG}-output}"
HAOS_CCACHE_VOLUME="${HAOS_CCACHE_VOLUME:-haos-${HAOS_TARGET}-${HAOS_REF_SLUG}-ccache}"
HAOS_CCACHE_DIR="${HAOS_CCACHE_DIR:-}"
HAOS_BUILDER_IMAGE="${HAOS_BUILDER_IMAGE:-ghcr.io/tinnci/haos-builder:kukui-17.3}"
HAOS_BUILDER_IMAGE_DIGEST="${HAOS_BUILDER_IMAGE_DIGEST:-}"
HAOS_DRY_RUN="${HAOS_DRY_RUN:-0}"
HAOS_CACHE_WARM_TARGETS="${HAOS_CACHE_WARM_TARGETS:-dbus-glib-source os-agent-source tempio-source}"
HAOS_REF_RESOLVED_COMMIT="${HAOS_REF_RESOLVED_COMMIT:-}"
HAOS_SOURCE_PROBE_STATUS="${HAOS_SOURCE_PROBE_STATUS:-not-run}"

usage() {
    cat <<'EOF'
Usage: scripts/haos-buildctl.sh <command>

Commands:
  help              Show this help.
  preflight         Check local prerequisites and configured paths.
  source-probe      Validate HAOS_REPO/ref, submodules, critical paths, and patch anchors.
  bootstrap         Clone/update HAOS upstream and apply patches.
  patch             Apply Kukui board and OTBR patches to HAOS_DIR.
  config            Run make google_kukui-config.
  build             Run make google_kukui.
  resume-build      Resume Buildroot directly without rerunning top-level defconfig.
  export-artifacts  Copy /build/output/images from Docker volume to EXPORT_DIR.
  verify-artifacts  Verify exported image, RAUC bundle, kernel.img, GPT GUIDs, and RAUC backend.
  cache-warm        Prefetch unstable source/vendor tarballs into /cache/dl.
  diagnostics       Print disk, Docker, git, and artifact diagnostics.
  layer-source      Prepare HAOS source, Kukui patches, OTBR fragment, and source metadata.
  layer-builder     Smoke-check the HAOS builder image tool contract.
  layer-download    Warm Buildroot and vendored source downloads under /cache/dl.
  layer-compile     Run target config and full target build with output/ccache reuse.
  layer-artifact    Export, checksum, and verify image artifacts.

Important environment:
  HAOS_REF            Default: 17.3
  HAOS_REPO           Default: https://github.com/home-assistant/operating-system.git
  HAOS_TARGET         Default: google_kukui
  HAOS_DIR            Default: ./work/haos
  CACHE_DIR           Default: $HOME/hassos-cache
  EXPORT_DIR          Default: $HAOS_DIR/output-volume-images
  HAOS_OUTPUT_VOLUME  Default: haos-$HAOS_TARGET-$HAOS_REF_SLUG-output
  HAOS_CCACHE_VOLUME  Default: haos-$HAOS_TARGET-$HAOS_REF_SLUG-ccache
  HAOS_CCACHE_DIR     Optional host path for CI ccache instead of Docker volume.
  HAOS_BUILDER_IMAGE  Default: ghcr.io/tinnci/haos-builder:kukui-17.3
  HAOS_BUILDER_IMAGE_DIGEST Optional resolved builder image digest for provenance metadata.
  HAOS_STATE_DIR      Default: ./work/haos-buildctl
  HAOS_DRY_RUN        Set to 1 to print commands without running Docker.
EOF
}

log() {
    printf '%s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_host_tool() {
    tool="$1"
    command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed or not on PATH"
}

run_cmd() {
    if [ "$HAOS_DRY_RUN" = "1" ]; then
        printf '+ %s\n' "$*"
    else
        sh -c "$*"
    fi
}

require_haos_dir() {
    [ -d "$HAOS_DIR" ] || die "HAOS_DIR does not exist: $HAOS_DIR"
}

metadata_dir() {
    printf '%s/verification\n' "$EXPORT_DIR"
}

metadata_file() {
    printf '%s/build-metadata.env\n' "$(metadata_dir)"
}

read_env_value() {
    key="$1"
    file="$2"
    [ -f "$file" ] || return 0
    awk -F= -v key="$key" '
        $1 == key {
            sub(/^[^=]*=/, "")
            print
            exit
        }
    ' "$file"
}

load_source_probe_state() {
    [ -f "$HAOS_SOURCE_PROBE_STATE" ] || return 0

    state_repo="$(read_env_value HAOS_REPO "$HAOS_SOURCE_PROBE_STATE")"
    state_ref="$(read_env_value HAOS_REF "$HAOS_SOURCE_PROBE_STATE")"
    state_target="$(read_env_value HAOS_TARGET "$HAOS_SOURCE_PROBE_STATE")"
    if [ "$state_repo" != "$HAOS_REPO" ] || [ "$state_ref" != "$HAOS_REF" ] || [ "$state_target" != "$HAOS_TARGET" ]; then
        HAOS_REF_RESOLVED_COMMIT=""
        HAOS_SOURCE_PROBE_STATUS="stale"
        return 0
    fi

    value="$(read_env_value HAOS_REF_RESOLVED_COMMIT "$HAOS_SOURCE_PROBE_STATE")"
    [ -z "$value" ] || HAOS_REF_RESOLVED_COMMIT="$value"
    value="$(read_env_value HAOS_SOURCE_PROBE_STATUS "$HAOS_SOURCE_PROBE_STATE")"
    [ -z "$value" ] || HAOS_SOURCE_PROBE_STATUS="$value"
}

write_source_probe_state() {
    if [ "$HAOS_DRY_RUN" = "1" ]; then
        log "write $HAOS_SOURCE_PROBE_STATE"
        return
    fi

    mkdir -p "$(dirname "$HAOS_SOURCE_PROBE_STATE")"
    {
        printf 'HAOS_REPO=%s\n' "$HAOS_REPO"
        printf 'HAOS_REF=%s\n' "$HAOS_REF"
        printf 'HAOS_TARGET=%s\n' "$HAOS_TARGET"
        printf 'HAOS_REF_RESOLVED_COMMIT=%s\n' "${HAOS_REF_RESOLVED_COMMIT:-unknown}"
        printf 'HAOS_SOURCE_PROBE_STATUS=%s\n' "$HAOS_SOURCE_PROBE_STATUS"
    } > "$HAOS_SOURCE_PROBE_STATE"
}

script_sha256() {
    script="$1"
    if [ -f "$REPO_ROOT/$script" ]; then
        shasum -a 256 "$REPO_ROOT/$script" | awk '{ print $1 }'
    else
        printf 'missing'
    fi
}

output_reuse_mode() {
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
        printf 'ephemeral-docker-volume'
    else
        printf 'persistent-docker-volume'
    fi
}

write_build_metadata() {
    metadata="$(metadata_file)"
    load_source_probe_state
    patch_kukui_sha="$(script_sha256 scripts/patch-haos-kukui-board.sh)"
    patch_otbr_sha="$(script_sha256 scripts/patch-haos-otbr-fragment.sh)"
    output_reuse="$(output_reuse_mode)"
    if [ "$HAOS_DRY_RUN" = "1" ]; then
        log "write $metadata"
        log "HAOS_REPO=$HAOS_REPO"
        log "HAOS_REF=$HAOS_REF"
        log "HAOS_REF_RESOLVED_COMMIT=$HAOS_REF_RESOLVED_COMMIT"
        log "HAOS_SOURCE_PROBE_STATUS=$HAOS_SOURCE_PROBE_STATUS"
        log "HAOS_TARGET=$HAOS_TARGET"
        log "PATCH_SCRIPT_SHA256_KUKUI=$patch_kukui_sha"
        log "PATCH_SCRIPT_SHA256_OTBR=$patch_otbr_sha"
        log "BUILDER_IMAGE=$HAOS_BUILDER_IMAGE"
        log "HAOS_BUILDER_IMAGE_DIGEST=$HAOS_BUILDER_IMAGE_DIGEST"
        log "GITHUB_RUN_ID=${GITHUB_RUN_ID:-}"
        log "GITHUB_RUN_ATTEMPT=${GITHUB_RUN_ATTEMPT:-}"
        log "GITHUB_WORKFLOW=${GITHUB_WORKFLOW:-}"
        log "GITHUB_JOB=${GITHUB_JOB:-}"
        log "GITHUB_REF=${GITHUB_REF:-}"
        log "GITHUB_SHA=${GITHUB_SHA:-}"
        log "RUNNER_OS=${RUNNER_OS:-}"
        log "RUNNER_ARCH=${RUNNER_ARCH:-}"
        log "RUNNER_IMAGE_OS=${ImageOS:-}"
        log "RUNNER_IMAGE_VERSION=${ImageVersion:-}"
        log "CACHE_DL=/cache/dl"
        log "OUTPUT_REUSE_MODE=$output_reuse"
        log 'PATCH_SCRIPTS="scripts/patch-haos-kukui-board.sh scripts/patch-haos-otbr-fragment.sh"'
        return
    fi

    mkdir -p "$(metadata_dir)"
    if [ -d "$HAOS_DIR/.git" ]; then
        haos_commit="$(git -C "$HAOS_DIR" rev-parse HEAD 2>/dev/null || printf 'unknown')"
    else
        haos_commit="unknown"
    fi
    {
        printf 'HAOS_REPO=%s\n' "$HAOS_REPO"
        printf 'HAOS_REF=%s\n' "$HAOS_REF"
        printf 'HAOS_REF_RESOLVED_COMMIT=%s\n' "${HAOS_REF_RESOLVED_COMMIT:-unknown}"
        printf 'HAOS_SOURCE_PROBE_STATUS=%s\n' "$HAOS_SOURCE_PROBE_STATUS"
        printf 'HAOS_TARGET=%s\n' "$HAOS_TARGET"
        printf 'HAOS_COMMIT=%s\n' "$haos_commit"
        printf 'HAOS_BUILDER_IMAGE=%s\n' "$HAOS_BUILDER_IMAGE"
        printf 'BUILDER_IMAGE=%s\n' "$HAOS_BUILDER_IMAGE"
        printf 'HAOS_BUILDER_IMAGE_DIGEST=%s\n' "$HAOS_BUILDER_IMAGE_DIGEST"
        printf 'HAOS_OUTPUT_VOLUME=%s\n' "$HAOS_OUTPUT_VOLUME"
        printf 'HAOS_CCACHE_VOLUME=%s\n' "$HAOS_CCACHE_VOLUME"
        printf 'CACHE_DL=/cache/dl\n'
        printf 'OUTPUT_REUSE_MODE=%s\n' "$output_reuse"
        printf 'PATCH_SCRIPT_SHA256_KUKUI=%s\n' "$patch_kukui_sha"
        printf 'PATCH_SCRIPT_SHA256_OTBR=%s\n' "$patch_otbr_sha"
        printf 'PATCH_SCRIPTS="scripts/patch-haos-kukui-board.sh scripts/patch-haos-otbr-fragment.sh"\n'
        printf 'GITHUB_RUN_ID=%s\n' "${GITHUB_RUN_ID:-}"
        printf 'GITHUB_RUN_ATTEMPT=%s\n' "${GITHUB_RUN_ATTEMPT:-}"
        printf 'GITHUB_WORKFLOW=%s\n' "${GITHUB_WORKFLOW:-}"
        printf 'GITHUB_JOB=%s\n' "${GITHUB_JOB:-}"
        printf 'GITHUB_REF=%s\n' "${GITHUB_REF:-}"
        printf 'GITHUB_SHA=%s\n' "${GITHUB_SHA:-}"
        printf 'RUNNER_OS=%s\n' "${RUNNER_OS:-}"
        printf 'RUNNER_ARCH=%s\n' "${RUNNER_ARCH:-}"
        printf 'RUNNER_IMAGE_OS=%s\n' "${ImageOS:-}"
        printf 'RUNNER_IMAGE_VERSION=%s\n' "${ImageVersion:-}"
    } > "$metadata"
}

write_checksums() {
    checksum_file="$(metadata_dir)/SHA256SUMS"
    if [ "$HAOS_DRY_RUN" = "1" ]; then
        log "write $checksum_file"
        return
    fi

    mkdir -p "$(metadata_dir)"
    checksum_inputs="$(
        find "$EXPORT_DIR" -maxdepth 1 -type f \( \
            -name 'kernel.img' -o \
            -name 'haos_google-kukui-*.img.xz' -o \
            -name 'haos_google-kukui-*.raucb' -o \
            -name '*.dtb' \
        \) -print 2>/dev/null | sort
    )"
    if [ -n "$checksum_inputs" ]; then
        (
            cd "$EXPORT_DIR"
            printf '%s\n' "$checksum_inputs" |
                sed "s|^$EXPORT_DIR/||" |
                xargs shasum -a 256
        ) > "$checksum_file"
    else
        : > "$checksum_file"
    fi
}

source_probe_fail() {
    stage="$1"
    detail="${2:-}"
    HAOS_SOURCE_PROBE_STATUS="failed:$stage"
    write_source_probe_state || true
    {
        printf 'ERROR: source-probe failed at %s\n' "$stage"
        printf 'HAOS_REPO=%s\n' "$HAOS_REPO"
        printf 'HAOS_REF=%s\n' "$HAOS_REF"
        printf 'HAOS_TARGET=%s\n' "$HAOS_TARGET"
        [ -z "$detail" ] || printf '%s\n' "$detail"
        printf 'Try workflow_dispatch with explicit upstream_repo/upstream_ref inputs, or update the Kukui patch anchors for the new upstream layout.\n'
    } >&2
    [ -z "${SOURCE_PROBE_TMP:-}" ] || rm -rf "$SOURCE_PROBE_TMP"
    exit 1
}

source_probe_check_path() {
    probe_checkout="$1"
    relpath="$2"
    log "check $relpath"
    [ -e "$probe_checkout/$relpath" ] || source_probe_fail "path:$relpath" "Missing required HAOS path: $relpath"
}

source_probe_check_anchor() {
    description="$1"
    pattern="$2"
    file="$3"
    grep -Eq "$pattern" "$file" || source_probe_fail "anchor:$description" "Missing patch anchor in $file: $description"
}

source_probe() {
    log "source-probe: HAOS_REPO=$HAOS_REPO HAOS_REF=$HAOS_REF"
    if [ "$HAOS_DRY_RUN" = "1" ]; then
        log "git ls-remote --exit-code $HAOS_REPO refs/heads/$HAOS_REF refs/tags/$HAOS_REF refs/tags/$HAOS_REF^{}"
        log "probe checkout: git clone --depth 1 --branch $HAOS_REF --recurse-submodules --shallow-submodules $HAOS_REPO \$TMPDIR/haos-source-probe.XXXXXX/haos"
        log "check buildroot-external/configs/generic_aarch64_defconfig"
        log "check buildroot"
        log "check buildroot-external"
        log "check buildroot-external/ota/system.conf.gtpl"
        log "check buildroot-external/scripts/rauc.sh"
        log "check buildroot-external/scripts/hdd-image.sh"
        log "check patch anchors"
        log "SOURCE_PROBE_STATUS=planned"
        return
    fi

    command -v git >/dev/null 2>&1 || source_probe_fail "tool:git" "git is required"

    ref_output="$(
        git ls-remote --exit-code "$HAOS_REPO" \
            "refs/heads/$HAOS_REF" \
            "refs/tags/$HAOS_REF" \
            "refs/tags/$HAOS_REF^{}" 2>&1
    )" || source_probe_fail "ref-resolution" "$ref_output"

    HAOS_REF_RESOLVED_COMMIT="$(
        printf '%s\n' "$ref_output" | awk '
            $2 ~ /\^\{\}$/ { resolved = $1 }
            NR == 1 { first = $1 }
            END {
                if (resolved != "") print resolved
                else print first
            }
        '
    )"
    [ -n "$HAOS_REF_RESOLVED_COMMIT" ] || source_probe_fail "ref-resolution" "Resolved ref was empty."

    SOURCE_PROBE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/haos-source-probe.XXXXXX")"
    probe_checkout="$SOURCE_PROBE_TMP/haos"
    log "probe checkout: $probe_checkout"
    git clone --depth 1 --branch "$HAOS_REF" --recurse-submodules --shallow-submodules "$HAOS_REPO" "$probe_checkout" ||
        source_probe_fail "checkout" "Unable to clone HAOS_REPO=$HAOS_REPO at HAOS_REF=$HAOS_REF"

    source_probe_check_path "$probe_checkout" "buildroot-external/configs/generic_aarch64_defconfig"
    source_probe_check_path "$probe_checkout" "buildroot"
    source_probe_check_path "$probe_checkout" "buildroot-external"
    source_probe_check_path "$probe_checkout" "buildroot-external/ota/system.conf.gtpl"
    source_probe_check_path "$probe_checkout" "buildroot-external/scripts/rauc.sh"
    source_probe_check_path "$probe_checkout" "buildroot-external/scripts/hdd-image.sh"

    log "check patch anchors"
    generic_defconfig="$probe_checkout/buildroot-external/configs/generic_aarch64_defconfig"
    system_conf="$probe_checkout/buildroot-external/ota/system.conf.gtpl"
    rauc_sh="$probe_checkout/buildroot-external/scripts/rauc.sh"
    hdd_image_sh="$probe_checkout/buildroot-external/scripts/hdd-image.sh"
    dockerfile="$probe_checkout/Dockerfile"

    source_probe_check_anchor "BR2_EXTERNAL path variable" '\$\(BR2_EXTERNAL_[A-Z0-9_]*_PATH\)' "$generic_defconfig"
    source_probe_check_anchor "kernel config fragment list" '^BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="' "$generic_defconfig"
    source_probe_check_anchor "RAUC tryboot template branch" 'BOOTLOADER.*tryboot' "$system_conf"
    source_probe_check_anchor "rauc system.conf template" 'system\.conf\.gtpl' "$rauc_sh"
    source_probe_check_anchor "hdd image RAUC manifest template" 'manifest\.raucm\.gtpl' "$hdd_image_sh"
    if [ -f "$dockerfile" ]; then
        source_probe_check_anchor "builder package insertion point" 'python-is-python3' "$dockerfile"
    fi

    rm -rf "$SOURCE_PROBE_TMP"
    SOURCE_PROBE_TMP=""
    HAOS_SOURCE_PROBE_STATUS="ok"
    write_source_probe_state
    log "SOURCE_PROBE_STATUS=$HAOS_SOURCE_PROBE_STATUS"
    log "HAOS_REF_RESOLVED_COMMIT=$HAOS_REF_RESOLVED_COMMIT"
}

preflight() {
    log "HAOS_REPO=$HAOS_REPO"
    log "HAOS_REF=$HAOS_REF"
    log "HAOS_TARGET=$HAOS_TARGET"
    log "HAOS_DIR=$HAOS_DIR"
    log "CACHE_DIR=$CACHE_DIR"
    log "EXPORT_DIR=$EXPORT_DIR"
    log "HAOS_OUTPUT_VOLUME=$HAOS_OUTPUT_VOLUME"
    log "HAOS_CCACHE_VOLUME=$HAOS_CCACHE_VOLUME"
    log "HAOS_CCACHE_DIR=$HAOS_CCACHE_DIR"
    log "HAOS_BUILDER_IMAGE=$HAOS_BUILDER_IMAGE"
    log "HAOS_BUILDER_IMAGE_DIGEST=$HAOS_BUILDER_IMAGE_DIGEST"

    require_haos_dir

    require_host_tool docker
    require_host_tool git

    mkdir -p "$CACHE_DIR/dl" "$EXPORT_DIR"
    [ -z "$HAOS_CCACHE_DIR" ] || mkdir -p "$HAOS_CCACHE_DIR"
    df -h "$HAOS_DIR" "$CACHE_DIR" "$EXPORT_DIR"
    docker version >/dev/null
}

bootstrap() {
    HAOS_REPO="$HAOS_REPO" \
    HAOS_REF="$HAOS_REF" \
    HAOS_TARGET="$HAOS_TARGET" \
    HAOS_DIR="$HAOS_DIR" \
    APPLY_KUKUI=0 \
    APPLY_OTBR=0 \
        sh "$REPO_ROOT/scripts/bootstrap-haos-upstream.sh"
}

dry_run_source() {
    log "layer-source: bootstrap HAOS_REF=$HAOS_REF HAOS_TARGET=$HAOS_TARGET"
    log "HAOS_REPO=$HAOS_REPO HAOS_REF=$HAOS_REF HAOS_TARGET=$HAOS_TARGET HAOS_DIR=$HAOS_DIR APPLY_KUKUI=0 APPLY_OTBR=0 sh $REPO_ROOT/scripts/bootstrap-haos-upstream.sh"
    log "HAOS_DIR=$HAOS_DIR sh $REPO_ROOT/scripts/patch-haos-kukui-board.sh"
    log "HAOS_DIR=$HAOS_DIR HAOS_TARGET=$HAOS_TARGET sh $REPO_ROOT/scripts/patch-haos-otbr-fragment.sh"
    write_build_metadata
}

layer_source() {
    if [ "$HAOS_DRY_RUN" = "1" ]; then
        source_probe
        dry_run_source
        return
    fi
    source_probe
    log "layer-source: bootstrap HAOS_REF=$HAOS_REF HAOS_TARGET=$HAOS_TARGET"
    bootstrap
    patch_haos
    write_build_metadata
}

patch_haos() {
    require_haos_dir
    HAOS_DIR="$HAOS_DIR" sh "$REPO_ROOT/scripts/patch-haos-kukui-board.sh"
    HAOS_DIR="$HAOS_DIR" HAOS_TARGET="$HAOS_TARGET" sh "$REPO_ROOT/scripts/patch-haos-otbr-fragment.sh"
}

local_make() {
    target="$1"
    require_haos_dir
    mkdir -p "$CACHE_DIR/dl"
    if [ -n "$HAOS_CCACHE_DIR" ]; then
        mkdir -p "$HAOS_CCACHE_DIR"
        ccache_mount="$HAOS_CCACHE_DIR:/ccache"
    else
        ccache_mount="$HAOS_CCACHE_VOLUME:/ccache"
    fi
    if [ "$HAOS_DRY_RUN" = "1" ]; then
        log "docker run -i --rm --privileged -v $HAOS_DIR:/build -v $CACHE_DIR:/cache -v $HAOS_OUTPUT_VOLUME:/build/output -v $ccache_mount -e BR2_DL_DIR=/cache/dl -e CCACHE_DIR=/ccache -e FORCE_UNSAFE_CONFIGURE=1 -e BUILDER_UID=$(id -u) -e BUILDER_GID=$(id -g) $HAOS_BUILDER_IMAGE make $target"
        return
    fi
    HAOS_DIR="$HAOS_DIR" \
    HAOS_TARGET="$HAOS_TARGET" \
    CACHE_DIR="$CACHE_DIR" \
    HAOS_OUTPUT_VOLUME="$HAOS_OUTPUT_VOLUME" \
    HAOS_CCACHE_VOLUME="$HAOS_CCACHE_VOLUME" \
    HAOS_CCACHE_DIR="$HAOS_CCACHE_DIR" \
    HAOS_BUILDER_IMAGE="$HAOS_BUILDER_IMAGE" \
        sh "$REPO_ROOT/scripts/build-haos-local.sh" "$target"
}

builder_smoke_script() {
    cat <<'EOF'
set -eu
command -v make
command -v git
command -v ccache
command -v skopeo
command -v sudo
command -v docker
command -v dockerd
command -v mkdepthcharge
command -v sgdisk
command -v xz
command -v zstd
command -v mkfs.erofs
command -v mksquashfs
command -v mkfs.ext4
command -v mkfs.vfat
if command -v vbutil_kernel >/dev/null 2>&1; then
    command -v vbutil_kernel
elif command -v futility >/dev/null 2>&1; then
    command -v futility
elif command -v cgpt >/dev/null 2>&1; then
    command -v cgpt
else
    echo "missing vboot utility: expected vbutil_kernel, futility, or cgpt" >&2
    exit 1
fi
EOF
}

layer_builder() {
    log "layer-builder: smoke-check $HAOS_BUILDER_IMAGE"
    smoke_script="$(builder_smoke_script)"
    if [ "$HAOS_DRY_RUN" = "1" ]; then
        log "docker run --rm $HAOS_BUILDER_IMAGE sh -lc '$smoke_script'"
        return
    fi
    docker run --rm "$HAOS_BUILDER_IMAGE" sh -lc "$smoke_script"
}

layer_download() {
    log "layer-download: config $HAOS_TARGET before source target warm-up"
    local_make "${HAOS_TARGET}-config"
    log "layer-download: warm $CACHE_DIR/dl as /cache/dl"
    cache_warm
}

layer_compile() {
    log "layer-compile: config $HAOS_TARGET"
    local_make "${HAOS_TARGET}-config"
    log "layer-compile: build $HAOS_TARGET"
    local_make "$HAOS_TARGET"
}

layer_artifact() {
    log "layer-artifact: export artifacts to $EXPORT_DIR"
    export_artifacts
    write_build_metadata
    write_checksums
    verify_artifacts
}

resume_build() {
    require_haos_dir
    mkdir -p "$CACHE_DIR/dl"
    if [ -n "$HAOS_CCACHE_DIR" ]; then
        mkdir -p "$HAOS_CCACHE_DIR"
        ccache_mount="$HAOS_CCACHE_DIR:/ccache"
    else
        ccache_mount="$HAOS_CCACHE_VOLUME:/ccache"
    fi
    if [ "$HAOS_DRY_RUN" = "1" ]; then
        log "docker run -i --rm --privileged -v $HAOS_DIR:/build -v $CACHE_DIR:/cache -v $HAOS_OUTPUT_VOLUME:/build/output -v $ccache_mount -e BR2_DL_DIR=/cache/dl -e CCACHE_DIR=/ccache -e FORCE_UNSAFE_CONFIGURE=1 -e BUILDER_UID=$(id -u) -e BUILDER_GID=$(id -g) $HAOS_BUILDER_IMAGE make -C /build/buildroot O=/build/output BR2_EXTERNAL=/build/buildroot-external"
        return
    fi
    docker volume create "$HAOS_OUTPUT_VOLUME" >/dev/null
    if [ -z "$HAOS_CCACHE_DIR" ]; then
        docker volume create "$HAOS_CCACHE_VOLUME" >/dev/null
    fi
    docker run -i --rm --privileged \
        -v "$HAOS_DIR:/build" \
        -v "$CACHE_DIR:/cache" \
        -v "$HAOS_OUTPUT_VOLUME:/build/output" \
        -v "$ccache_mount" \
        -e BR2_DL_DIR=/cache/dl \
        -e CCACHE_DIR=/ccache \
        -e FORCE_UNSAFE_CONFIGURE=1 \
        -e BUILDER_UID="$(id -u)" \
        -e BUILDER_GID="$(id -g)" \
        "$HAOS_BUILDER_IMAGE" make -C /build/buildroot O=/build/output BR2_EXTERNAL=/build/buildroot-external
}

export_artifacts() {
    mkdir -p "$EXPORT_DIR"
    if [ "$HAOS_DRY_RUN" = "1" ]; then
        log "docker run --rm -v $HAOS_OUTPUT_VOLUME:/out:ro -v $EXPORT_DIR:/export $HAOS_BUILDER_IMAGE sh -lc 'cp -av /out/images/. /export/'"
        return
    fi
    docker run --rm \
        -v "$HAOS_OUTPUT_VOLUME:/out:ro" \
        -v "$EXPORT_DIR:/export" \
        "$HAOS_BUILDER_IMAGE" sh -lc '
            cp -av /out/images/. /export/
            mkdir -p /export/verification-root/etc/rauc /export/verification-root/usr/lib/rauc
            cp -av /out/target/etc/rauc/system.conf /export/verification-root/etc/rauc/system.conf
            cp -av /out/target/usr/lib/rauc/depthcharge-backend /export/verification-root/usr/lib/rauc/depthcharge-backend
        '
}

verify_artifacts() {
    img_xz="$EXPORT_DIR/haos_google-kukui-*.img.xz"
    raucb="$EXPORT_DIR/haos_google-kukui-*.raucb"
    kernel_img="$EXPORT_DIR/kernel.img"

    if [ "$HAOS_DRY_RUN" = "1" ]; then
        log "verify kernel.img at $kernel_img"
        log "verify haos_google-kukui-*.img.xz at $img_xz"
        log "verify haos_google-kukui-*.raucb at $raucb"
        log "verify mt8183-kukui*.dtb at $EXPORT_DIR"
        log "verify ChromeOS kernel GUIDs with sgdisk"
        log "verify RAUC bootloader=custom and depthcharge-backend"
        return
    fi

    require_host_tool file
    require_host_tool xz

    [ -f "$kernel_img" ] || die "missing kernel.img in $EXPORT_DIR"
    set -- $img_xz
    [ -f "$1" ] || die "missing haos_google-kukui-*.img.xz in $EXPORT_DIR"
    image_xz="$1"
    set -- $raucb
    [ -f "$1" ] || die "missing haos_google-kukui-*.raucb in $EXPORT_DIR"
    bundle="$1"
    set -- "$EXPORT_DIR"/mt8183-kukui*.dtb
    [ -f "$1" ] || die "missing mt8183-kukui*.dtb in $EXPORT_DIR"

    file "$kernel_img" "$image_xz" "$bundle" "$EXPORT_DIR"/mt8183-kukui*.dtb

    if docker volume inspect "$HAOS_OUTPUT_VOLUME" >/dev/null 2>&1; then
        docker run --rm -v "$HAOS_OUTPUT_VOLUME:/out:ro" "$HAOS_BUILDER_IMAGE" sh -lc '
            grep -nE "bootloader=custom|bootloader-custom-backend=/usr/lib/rauc/depthcharge-backend" /out/target/etc/rauc/system.conf
            test -x /out/target/usr/lib/rauc/depthcharge-backend
        '
    else
        grep -nE "bootloader=custom|bootloader-custom-backend=/usr/lib/rauc/depthcharge-backend" "$EXPORT_DIR/verification-root/etc/rauc/system.conf"
        test -x "$EXPORT_DIR/verification-root/usr/lib/rauc/depthcharge-backend"
    fi

    raw_img="$EXPORT_DIR/.verify-${HAOS_TARGET}.img"
    rm -f "$raw_img"
    xz -dc "$image_xz" > "$raw_img"
    docker run --rm -v "$EXPORT_DIR:/export:ro" "$HAOS_BUILDER_IMAGE" sh -lc "
        sgdisk -i 2 /export/$(basename "$raw_img") | grep -F 'FE3A2A5D-4F32-41A7-B725-ACCC3285A309'
        sgdisk -i 4 /export/$(basename "$raw_img") | grep -F 'FE3A2A5D-4F32-41A7-B725-ACCC3285A309'
    "
    rm -f "$raw_img"
}

cache_warm() {
    require_haos_dir
    mkdir -p "$CACHE_DIR/dl"
    if [ -n "$HAOS_CCACHE_DIR" ]; then
        mkdir -p "$HAOS_CCACHE_DIR"
        ccache_mount="$HAOS_CCACHE_DIR:/ccache"
    else
        ccache_mount="$HAOS_CCACHE_VOLUME:/ccache"
    fi
    if [ "$HAOS_DRY_RUN" = "1" ]; then
        log "docker run -i --rm --privileged -v $HAOS_DIR:/build -v $CACHE_DIR:/cache -v $HAOS_OUTPUT_VOLUME:/build/output -v $ccache_mount -e BR2_DL_DIR=/cache/dl -e CCACHE_DIR=/ccache -e FORCE_UNSAFE_CONFIGURE=1 -e BUILDER_UID=$(id -u) -e BUILDER_GID=$(id -g) $HAOS_BUILDER_IMAGE make -C /build/buildroot O=/build/output BR2_EXTERNAL=/build/buildroot-external $HAOS_CACHE_WARM_TARGETS"
        return
    fi
    docker volume create "$HAOS_OUTPUT_VOLUME" >/dev/null
    if [ -z "$HAOS_CCACHE_DIR" ]; then
        docker volume create "$HAOS_CCACHE_VOLUME" >/dev/null
    fi
    docker run -i --rm --privileged \
        -v "$HAOS_DIR:/build" \
        -v "$CACHE_DIR:/cache" \
        -v "$HAOS_OUTPUT_VOLUME:/build/output" \
        -v "$ccache_mount" \
        -e BR2_DL_DIR=/cache/dl \
        -e CCACHE_DIR=/ccache \
        -e FORCE_UNSAFE_CONFIGURE=1 \
        -e BUILDER_UID="$(id -u)" \
        -e BUILDER_GID="$(id -g)" \
        "$HAOS_BUILDER_IMAGE" make -C /build/buildroot O=/build/output BR2_EXTERNAL=/build/buildroot-external $HAOS_CACHE_WARM_TARGETS
}

diagnostics() {
    load_source_probe_state
    output_reuse="$(output_reuse_mode)"
    log "== layer status =="
    log "source: HAOS_REPO=$HAOS_REPO HAOS_REF=$HAOS_REF HAOS_TARGET=$HAOS_TARGET HAOS_DIR=$HAOS_DIR"
    log "source_probe: HAOS_SOURCE_PROBE_STATUS=$HAOS_SOURCE_PROBE_STATUS HAOS_REF_RESOLVED_COMMIT=${HAOS_REF_RESOLVED_COMMIT:-unknown}"
    log "builder: HAOS_BUILDER_IMAGE=$HAOS_BUILDER_IMAGE HAOS_BUILDER_IMAGE_DIGEST=$HAOS_BUILDER_IMAGE_DIGEST"
    log "download: $CACHE_DIR/dl -> /cache/dl"
    log "compile: output=$HAOS_OUTPUT_VOLUME ccache=${HAOS_CCACHE_DIR:-$HAOS_CCACHE_VOLUME} output_reuse=$output_reuse"
    log "artifact: EXPORT_DIR=$EXPORT_DIR metadata=$(metadata_dir)"
    log "source_probe_state: $HAOS_SOURCE_PROBE_STATE"
    log "== disk =="
    df -h "$REPO_ROOT" "$HAOS_DIR" "$CACHE_DIR" "$EXPORT_DIR" 2>/dev/null || true
    log "== git =="
    git -C "$REPO_ROOT" status --short --branch || true
    log "== HAOS checkout diff =="
    if [ -d "$HAOS_DIR/.git" ]; then
        git -C "$HAOS_DIR" status --short --branch || true
        git -C "$HAOS_DIR" diff --stat || true
    else
        log "HAOS checkout not present at $HAOS_DIR"
    fi
    log "== docker =="
    docker ps --format 'table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}' 2>/dev/null || true
    docker volume ls 2>/dev/null | grep "$HAOS_TARGET" || true
    log "== artifacts =="
    find "$EXPORT_DIR" -maxdepth 1 -type f -print 2>/dev/null | sort || true
    log "== failed Buildroot stamps =="
    if [ "$HAOS_DRY_RUN" = "1" ]; then
        log "dry run: skipped output volume scan for $HAOS_OUTPUT_VOLUME"
    elif docker volume inspect "$HAOS_OUTPUT_VOLUME" >/dev/null 2>&1; then
        docker run --rm -v "$HAOS_OUTPUT_VOLUME:/out:ro" "$HAOS_BUILDER_IMAGE" sh -lc '
            find /out/build -name ".stamp_*_failed" -print 2>/dev/null | sort || true
        ' || true
    else
        log "output volume not present: $HAOS_OUTPUT_VOLUME"
    fi
    log "== recent Buildroot logs =="
    if [ "$HAOS_DRY_RUN" = "1" ]; then
        log "dry run: skipped output volume scan for $HAOS_OUTPUT_VOLUME"
    elif docker volume inspect "$HAOS_OUTPUT_VOLUME" >/dev/null 2>&1; then
        docker run --rm -v "$HAOS_OUTPUT_VOLUME:/out:ro" "$HAOS_BUILDER_IMAGE" sh -lc '
            find /out/build -type f \( -name "*.log" -o -name "build.log" \) -print 2>/dev/null |
                sort |
                tail -20
        ' || true
    else
        log "output volume not present: $HAOS_OUTPUT_VOLUME"
    fi
}

command="${1:-help}"
case "$command" in
    help|-h|--help) usage ;;
    preflight) preflight ;;
    source-probe) source_probe ;;
    bootstrap) bootstrap ;;
    patch) patch_haos ;;
    config) local_make "${HAOS_TARGET}-config" ;;
    build) local_make "$HAOS_TARGET" ;;
    resume-build) resume_build ;;
    export-artifacts) export_artifacts ;;
    verify-artifacts) verify_artifacts ;;
    cache-warm) cache_warm ;;
    diagnostics) diagnostics ;;
    layer-source) layer_source ;;
    layer-builder) layer_builder ;;
    layer-download) layer_download ;;
    layer-compile) layer_compile ;;
    layer-artifact) layer_artifact ;;
    *)
        usage >&2
        die "unknown command: $command"
        ;;
esac
