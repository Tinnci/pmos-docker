#!/bin/sh
# Composable HAOS build controller for local and CI workflows.
set -eu

REPO_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"

slugify() {
    printf '%s' "$1" | sed 's/[^A-Za-z0-9_]/-/g'
}

HAOS_REF="${HAOS_REF:-17.3}"
HAOS_TARGET="${HAOS_TARGET:-google_kukui}"
HAOS_REF_SLUG="${HAOS_REF_SLUG:-$(slugify "$HAOS_REF")}"
HAOS_DIR="${HAOS_DIR:-$REPO_ROOT/work/haos}"
CACHE_DIR="${CACHE_DIR:-$HOME/hassos-cache}"
EXPORT_DIR="${EXPORT_DIR:-$HAOS_DIR/output-volume-images}"
HAOS_OUTPUT_VOLUME="${HAOS_OUTPUT_VOLUME:-haos-${HAOS_TARGET}-${HAOS_REF_SLUG}-output}"
HAOS_CCACHE_VOLUME="${HAOS_CCACHE_VOLUME:-haos-${HAOS_TARGET}-${HAOS_REF_SLUG}-ccache}"
HAOS_CCACHE_DIR="${HAOS_CCACHE_DIR:-}"
HAOS_BUILDER_IMAGE="${HAOS_BUILDER_IMAGE:-hassos:local}"
HAOS_DRY_RUN="${HAOS_DRY_RUN:-0}"
HAOS_CACHE_WARM_TARGETS="${HAOS_CACHE_WARM_TARGETS:-dbus-glib-source os-agent-source tempio-source}"

usage() {
    cat <<'EOF'
Usage: scripts/haos-buildctl.sh <command>

Commands:
  help              Show this help.
  preflight         Check local prerequisites and configured paths.
  bootstrap         Clone/update HAOS upstream and apply patches.
  patch             Apply Kukui board and OTBR patches to HAOS_DIR.
  config            Run make google_kukui-config.
  build             Run make google_kukui.
  resume-build      Resume Buildroot directly without rerunning top-level defconfig.
  export-artifacts  Copy /build/output/images from Docker volume to EXPORT_DIR.
  verify-artifacts  Verify exported image, RAUC bundle, kernel.img, GPT GUIDs, and RAUC backend.
  cache-warm        Prefetch unstable source/vendor tarballs into /cache/dl.
  diagnostics       Print disk, Docker, git, and artifact diagnostics.

Important environment:
  HAOS_REF            Default: 17.3
  HAOS_TARGET         Default: google_kukui
  HAOS_DIR            Default: ./work/haos
  CACHE_DIR           Default: $HOME/hassos-cache
  EXPORT_DIR          Default: $HAOS_DIR/output-volume-images
  HAOS_OUTPUT_VOLUME  Default: haos-$HAOS_TARGET-$HAOS_REF_SLUG-output
  HAOS_CCACHE_VOLUME  Default: haos-$HAOS_TARGET-$HAOS_REF_SLUG-ccache
  HAOS_CCACHE_DIR     Optional host path for CI ccache instead of Docker volume.
  HAOS_BUILDER_IMAGE  Default: hassos:local
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

preflight() {
    log "HAOS_REF=$HAOS_REF"
    log "HAOS_TARGET=$HAOS_TARGET"
    log "HAOS_DIR=$HAOS_DIR"
    log "CACHE_DIR=$CACHE_DIR"
    log "EXPORT_DIR=$EXPORT_DIR"
    log "HAOS_OUTPUT_VOLUME=$HAOS_OUTPUT_VOLUME"
    log "HAOS_CCACHE_VOLUME=$HAOS_CCACHE_VOLUME"
    log "HAOS_CCACHE_DIR=$HAOS_CCACHE_DIR"
    log "HAOS_BUILDER_IMAGE=$HAOS_BUILDER_IMAGE"

    require_haos_dir

    command -v docker >/dev/null 2>&1 || die "docker is not installed or not on PATH"
    command -v git >/dev/null 2>&1 || die "git is not installed or not on PATH"

    mkdir -p "$CACHE_DIR/dl" "$EXPORT_DIR"
    [ -z "$HAOS_CCACHE_DIR" ] || mkdir -p "$HAOS_CCACHE_DIR"
    df -h "$HAOS_DIR" "$CACHE_DIR" "$EXPORT_DIR"
    docker version >/dev/null
}

bootstrap() {
    HAOS_REF="$HAOS_REF" \
    HAOS_TARGET="$HAOS_TARGET" \
    HAOS_DIR="$HAOS_DIR" \
    APPLY_KUKUI=0 \
    APPLY_OTBR=0 \
        sh "$REPO_ROOT/scripts/bootstrap-haos-upstream.sh"
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
        log "docker run -i --rm --privileged -v $HAOS_DIR:/build -v $CACHE_DIR:/cache -v $HAOS_OUTPUT_VOLUME:/build/output -v $ccache_mount -e BR2_DL_DIR=/cache/dl -e CCACHE_DIR=/ccache $HAOS_BUILDER_IMAGE make $target"
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
        log "docker run -i --rm --privileged -v $HAOS_DIR:/build -v $CACHE_DIR:/cache -v $HAOS_OUTPUT_VOLUME:/build/output -v $ccache_mount -e BR2_DL_DIR=/cache/dl -e CCACHE_DIR=/ccache $HAOS_BUILDER_IMAGE make -C /build/buildroot O=/build/output BR2_EXTERNAL=/build/buildroot-external"
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
        log "verify ChromeOS kernel GUIDs with sgdisk"
        log "verify RAUC bootloader=custom and depthcharge-backend"
        return
    fi

    [ -f "$kernel_img" ] || die "missing kernel.img in $EXPORT_DIR"
    set -- $img_xz
    [ -f "$1" ] || die "missing haos_google-kukui-*.img.xz in $EXPORT_DIR"
    image_xz="$1"
    set -- $raucb
    [ -f "$1" ] || die "missing haos_google-kukui-*.raucb in $EXPORT_DIR"

    file "$kernel_img" "$image_xz" "$1"

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
        log "docker run -i --rm --privileged -v $HAOS_DIR:/build -v $CACHE_DIR:/cache -v $HAOS_OUTPUT_VOLUME:/build/output -v $ccache_mount -e BR2_DL_DIR=/cache/dl -e CCACHE_DIR=/ccache $HAOS_BUILDER_IMAGE make -C /build/buildroot O=/build/output BR2_EXTERNAL=/build/buildroot-external $HAOS_CACHE_WARM_TARGETS"
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
        "$HAOS_BUILDER_IMAGE" make -C /build/buildroot O=/build/output BR2_EXTERNAL=/build/buildroot-external $HAOS_CACHE_WARM_TARGETS
}

diagnostics() {
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
    bootstrap) bootstrap ;;
    patch) patch_haos ;;
    config) local_make "${HAOS_TARGET}-config" ;;
    build) local_make "$HAOS_TARGET" ;;
    resume-build) resume_build ;;
    export-artifacts) export_artifacts ;;
    verify-artifacts) verify_artifacts ;;
    cache-warm) cache_warm ;;
    diagnostics) diagnostics ;;
    *)
        usage >&2
        die "unknown command: $command"
        ;;
esac
