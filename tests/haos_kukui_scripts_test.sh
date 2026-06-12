#!/bin/sh
set -eu

REPO_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
TMPDIR="${TMPDIR:-/tmp}"
WORKDIR="$(mktemp -d "$TMPDIR/haos-kukui-test.XXXXXX")"

cleanup() {
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

run_fixture() {
    name="$1"
    external_var="$2"
    external_ref="\$(BR2_EXTERNAL_${external_var}_PATH)"
    haos_dir="$WORKDIR/$name"

    mkdir -p \
        "$haos_dir/buildroot-external/configs" \
        "$haos_dir/buildroot-external/ota" \
        "$haos_dir/buildroot-external/scripts" \
        "$haos_dir/buildroot-external/kernel/v6.12.y" \
        "$haos_dir/buildroot/package/tar"

    cat > "$haos_dir/buildroot-external/configs/generic_aarch64_defconfig" <<EOF
BR2_aarch64=y
BR2_ROOTFS_OVERLAY="${external_ref}/rootfs-overlay"
BR2_ROOTFS_POST_BUILD_SCRIPT="${external_ref}/scripts/post-build.sh"
BR2_ROOTFS_POST_IMAGE_SCRIPT="${external_ref}/scripts/post-image.sh"
BR2_ROOTFS_POST_SCRIPT_ARGS="${external_ref}/board/arm-uefi/generic-aarch64 ${external_ref}/board/arm-uefi/generic-aarch64/haos-hook.sh"
BR2_LINUX_KERNEL=y
BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE="${external_ref}/board/arm-uefi/generic-aarch64/kernel.config"
BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="${external_ref}/kernel/v6.12.y/haos.config ${external_ref}/kernel/v6.12.y/docker.config ${external_ref}/kernel/v6.12.y/device-support.config ${external_ref}/kernel/v6.12.y/device-support-wireless.config ${external_ref}/kernel/v6.12.y/device-support-wireless-pci.config ${external_ref}/board/arm-uefi/generic-aarch64/kernel.config"
BR2_TARGET_GRUB2=y
BR2_TARGET_GRUB2_INSTALL_TOOLS=y
BR2_PACKAGE_BUSYBOX_CONFIG="${external_ref}/busybox.config"
EOF

    cat > "$haos_dir/buildroot/package/tar/tar.mk" <<'EOF'
HOST_TAR_CONF_ENV = \
	CC="$(HOSTCC_NOCCACHE)" \
	CXX="$(HOSTCXX_NOCCACHE)"
EOF

    cat > "$haos_dir/buildroot/package/pkg-autotools.mk" <<'EOF'
define $(2)_CONFIGURE_CMDS
	(cd $$($$(PKG)_SRCDIR) && rm -rf config.cache; \
	$$(HOST_CONFIGURE_OPTS) \
	$$($$(PKG)_CONF_ENV) \
	CONFIG_SITE=/dev/null \
	./configure \
		--prefix="$$(HOST_DIR)" \
	)
endef
EOF

    cat > "$haos_dir/buildroot/Makefile" <<'EOF'
TAR_OPTIONS = $(call qstrip,$(BR2_TAR_OPTIONS)) -xf
EOF

    cat > "$haos_dir/buildroot/package/pkg-generic.mk" <<'EOF'
# default extract command
$(2)_EXTRACT_CMDS ?= \
	$$(if $$($(2)_SOURCE),$$(INFLATE$$(suffix $$($(2)_SOURCE))) $$($(2)_DL_DIR)/$$($(2)_SOURCE) | \
	$$(TAR) --strip-components=$$($(2)_STRIP_COMPONENTS) \
		-C $$($(2)_DIR) \
		$$(foreach x,$$($(2)_EXCLUDES),--exclude='$$(x)' ) \
		$$(TAR_OPTIONS) -)

# pre/post-steps hooks
EOF

    cat > "$haos_dir/Dockerfile" <<'EOF'
FROM debian:trixie
RUN apt-get update && apt-get install -y --no-install-recommends \
        python-is-python3 \
        depthcharge-tools \
        qemu-utils \
    && rm -rf /var/lib/apt/lists/*
EOF

    cat > "$haos_dir/buildroot-external/ota/system.conf.gtpl" <<'EOF'
[system]
compatible={{ env "ota_compatible" }}
mountprefix=/run/rauc
statusfile=/mnt/boot/rauc.db
{{- if eq (env "BOOTLOADER") "tryboot" }}
bootloader=custom
{{- else }}
bootloader={{ env "BOOTLOADER" }}
{{- end }}
{{- if eq (env "BOOTLOADER") "grub" }}
grubenv=/mnt/boot/EFI/BOOT/grubenv
{{- end }}

{{- if eq (env "BOOTLOADER") "tryboot" }}
[handlers]
bootloader-custom-backend=/usr/lib/rauc/rpi-tryboot.sh

{{- end }}
EOF

    cat > "$haos_dir/buildroot-external/scripts/rauc.sh" <<EOF
function write_rauc_config() {
    (
        "\${HOST_DIR}/bin/tempio" \
            -template "\${BR2_EXTERNAL_${external_var}_PATH}/ota/system.conf.gtpl"
    ) > "\${TARGET_DIR}/etc/rauc/system.conf"
}
EOF

    cat > "$haos_dir/buildroot-external/scripts/hdd-image.sh" <<EOF
function create_disk_image() {
    RAUC_MANIFEST=\$(tempio -template "\${BR2_EXTERNAL_${external_var}_PATH}/ota/manifest.raucm.gtpl")
}
EOF

    HAOS_DIR="$haos_dir" sh "$REPO_ROOT/scripts/patch-haos-kukui-board.sh" >/dev/null
    HAOS_DIR="$haos_dir" HAOS_TARGET=google_kukui sh "$REPO_ROOT/scripts/patch-haos-otbr-fragment.sh" >/dev/null
    HAOS_DIR="$haos_dir" sh "$REPO_ROOT/scripts/patch-haos-kukui-board.sh" >/dev/null
    HAOS_DIR="$haos_dir" HAOS_TARGET=google_kukui sh "$REPO_ROOT/scripts/patch-haos-otbr-fragment.sh" >/dev/null

    defconfig="$haos_dir/buildroot-external/configs/google_kukui_defconfig"
    fragment="$haos_dir/buildroot-external/kernel/zm1-otbr.config"
    system_conf="$haos_dir/buildroot-external/ota/system.conf.gtpl"
    rauc_sh="$haos_dir/buildroot-external/scripts/rauc.sh"
    hdd_image_sh="$haos_dir/buildroot-external/scripts/hdd-image.sh"
    tar_mk="$haos_dir/buildroot/package/tar/tar.mk"
    pkg_autotools_mk="$haos_dir/buildroot/package/pkg-autotools.mk"
    buildroot_makefile="$haos_dir/buildroot/Makefile"
    pkg_generic_mk="$haos_dir/buildroot/package/pkg-generic.mk"

    if [ "$external_var" = "HAOS" ]; then
        stale_var="HASSOS"
    else
        stale_var="HAOS"
    fi

    if grep -R "BR2_EXTERNAL_${stale_var}_PATH" "$haos_dir" >/dev/null; then
        echo "$name fixture mixed external path vars" >&2
        exit 1
    fi

    if ! grep -q "BR2_EXTERNAL_${external_var}_PATH" "$defconfig"; then
        echo "$name fixture did not preserve BR2_EXTERNAL_${external_var}_PATH" >&2
        exit 1
    fi

    if grep -q 'kernel/v6.18.y' "$defconfig"; then
        echo "$name fixture hard-coded v6.18.y kernel fragments" >&2
        exit 1
    fi

    if ! grep -q 'kernel/v6.12.y/device-support-wireless-pci.config' "$defconfig"; then
        echo "$name fixture did not preserve upstream kernel fragment list" >&2
        exit 1
    fi

    count="$(grep -o "kernel/zm1-otbr.config" "$defconfig" | wc -l | tr -d ' ')"
    if [ "$count" != "1" ]; then
        echo "$name expected exactly one zm1-otbr.config reference, found $count" >&2
        exit 1
    fi

    for symbol in \
        CONFIG_NF_NAT_IPV4 \
        CONFIG_NF_NAT_IPV6 \
        CONFIG_IP_NF_TARGET_MASQUERADE \
        CONFIG_NF_TABLES_IPV4 \
        CONFIG_NF_TABLES_IPV6 \
        CONFIG_TUN \
        CONFIG_VETH \
        CONFIG_BRIDGE \
        CONFIG_IP_SET \
        CONFIG_BT_BNEP
    do
        if grep -q "^${symbol}=" "$fragment"; then
            echo "$name trimmed fragment still contains ${symbol}" >&2
            exit 1
        fi
    done

    for symbol in \
        CONFIG_IP_MROUTE_MULTIPLE_TABLES \
        CONFIG_IP_PIMSM_V1 \
        CONFIG_IP_PIMSM_V2 \
        CONFIG_IPV6_MROUTE_MULTIPLE_TABLES \
        CONFIG_IPV6_PIMSM_V2 \
        CONFIG_NET_SCH_CAKE
    do
        if ! grep -q "^${symbol}=y" "$fragment"; then
            echo "$name trimmed fragment missing ${symbol}" >&2
            exit 1
        fi
    done

    if [ "$(grep -c 'BOOTLOADER") "depthcharge"' "$system_conf")" != "2" ]; then
        echo "$name depthcharge RAUC snippets were not injected exactly once" >&2
        exit 1
    fi

    if ! grep -q 'bootloader-custom-backend=/usr/lib/rauc/depthcharge-backend' "$system_conf"; then
        echo "$name missing depthcharge RAUC backend" >&2
        exit 1
    fi

    if [ "$(grep -c 'system.conf.gtpl" </dev/null' "$rauc_sh")" != "1" ]; then
        echo "$name tempio stdin EOF workaround was not injected exactly once" >&2
        exit 1
    fi

    if [ "$(grep -c 'manifest.raucm.gtpl" </dev/null' "$hdd_image_sh")" != "1" ]; then
        echo "$name tempio RAUC manifest stdin EOF workaround was not injected exactly once" >&2
        exit 1
    fi

    if [ "$(grep -c 'gl_cv_func_getcwd_path_max=yes' "$tar_mk")" != "1" ]; then
        echo "$name host-tar macOS Docker configure workaround was not injected exactly once" >&2
        exit 1
    fi

    if [ "$(grep -c 'gl_cv_func_getcwd_path_max=yes' "$pkg_autotools_mk")" != "1" ]; then
        echo "$name host-autotools macOS Docker configure workaround was not injected exactly once" >&2
        exit 1
    fi

    if [ "$(grep -c -- '--delay-directory-restore' "$buildroot_makefile")" != "1" ]; then
        echo "$name tar delay-directory-restore workaround was not injected exactly once" >&2
        exit 1
    fi

    if [ "$(grep -c -- '--warning=no-rename-directory' "$buildroot_makefile")" != "1" ]; then
        echo "$name tar rename-directory warning workaround was not injected exactly once" >&2
        exit 1
    fi

    if [ "$(grep -c '/tmp/buildroot-extract.XXXXXX' "$pkg_generic_mk")" != "1" ]; then
        echo "$name pkg-generic /tmp extract workaround was not injected exactly once" >&2
        exit 1
    fi

    if grep -q -- '-C $$($(2)_DIR)' "$pkg_generic_mk"; then
        echo "$name pkg-generic still extracts tar directly into bind-mounted output dir" >&2
        exit 1
    fi

    if grep -q '^[[:space:]]*depthcharge-tools \\' "$haos_dir/Dockerfile"; then
        echo "$name Dockerfile still tries to install unavailable bullseye depthcharge-tools package" >&2
        exit 1
    fi

    if ! grep -q 'depthcharge-tools_0.6.2-2_all.deb' "$haos_dir/Dockerfile"; then
        echo "$name Dockerfile missing compatible depthcharge-tools deb install" >&2
        exit 1
    fi

    for pkg in device-tree-compiler gdisk linux-base lz4 python3-pkg-resources u-boot-tools vboot-kernel-utils vboot-utils xz-utils cgpt
    do
        count="$(grep -c "^[[:space:]]*${pkg} \\\\" "$haos_dir/Dockerfile" || true)"
        if [ "$count" != "1" ]; then
            echo "$name Dockerfile has ${count} ${pkg} package lines" >&2
            exit 1
        fi
    done
}

run_fixture haos-current HAOS
run_fixture hassos-17-3 HASSOS

if ! grep -q 'default: "17.3"' "$REPO_ROOT/.github/workflows/haos-build.yml"; then
    echo "HAOS GitHub Actions default ref is not 17.3" >&2
    exit 1
fi

if ! grep -q 'HAOS_REF="${HAOS_REF:-17.3}"' "$REPO_ROOT/scripts/bootstrap-haos-upstream.sh"; then
    echo "HAOS bootstrap default ref is not 17.3" >&2
    exit 1
fi

if grep -n 'sed -i' "$REPO_ROOT/scripts/patch-haos-kukui-board.sh" "$REPO_ROOT/scripts/patch-haos-otbr-fragment.sh" >/dev/null; then
    echo "HAOS patch scripts still use non-portable sed -i" >&2
    exit 1
fi

echo "haos kukui script tests passed"
