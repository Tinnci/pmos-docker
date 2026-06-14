#!/usr/bin/env bash
set -e

start_dockerd() {
    command -v dockerd >/dev/null 2>&1 || return 0
    docker info >/dev/null 2>&1 && return 0

    mkdir -p /var/lib/docker /var/run
    dockerd --storage-driver=vfs >/tmp/haos-builder-dockerd.log 2>&1 &
}

configure_builder_user() {
    run_user="root"

    if [ "${BUILDER_GID:-0}" -ne 0 ] && ! getent group "${BUILDER_GID:-0}" >/dev/null 2>&1; then
        groupadd -g "${BUILDER_GID}" builder
    fi

    if [ "${BUILDER_UID:-0}" -ne 0 ]; then
        useradd -m -u "${BUILDER_UID}" -g "${BUILDER_GID:-0}" -G docker,sudo builder
        echo "builder ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder
        chmod 0440 /etc/sudoers.d/builder
        chown "${BUILDER_UID}:${BUILDER_GID:-0}" /cache 2>/dev/null || true
        chown "${BUILDER_UID}:${BUILDER_GID:-0}" /build/output 2>/dev/null || true
        run_user="builder"
    fi

    printf '%s' "$run_user"
}

if [ "$#" -eq 0 ]; then
    set -- bash
fi

start_dockerd
run_user="$(configure_builder_user)"

if cmd="$(command -v "$1")"; then
    shift
    exec sudo -H -u "$run_user" "$cmd" "$@"
fi

echo "Command not found: $1" >&2
exit 1
