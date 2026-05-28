#!/bin/sh
# Add a Home Assistant OS google-kukui target using the ChromeOS Depthcharge boot flow.
set -eu

HAOS_DIR="${HAOS_DIR:-/work/haos}"
BOARD_DIR="$HAOS_DIR/buildroot-external/board/google/kukui"
DEFCONFIG="$HAOS_DIR/buildroot-external/configs/google_kukui_defconfig"
GENERIC_DEFCONFIG="$HAOS_DIR/buildroot-external/configs/generic_aarch64_defconfig"
DOCKERFILE="$HAOS_DIR/Dockerfile"
SYSTEM_CONF="$HAOS_DIR/buildroot-external/ota/system.conf.gtpl"

if [ ! -f "$GENERIC_DEFCONFIG" ]; then
    echo "ERROR: HAOS generic_aarch64_defconfig not found under $HAOS_DIR"
    exit 1
fi

mkdir -p "$BOARD_DIR/rootfs-overlay/usr/lib/rauc"

cat > "$BOARD_DIR/meta" <<'EOF'
BOARD_ID=google-kukui
BOARD_NAME="Google Kukui Chromebook"
CHASSIS=convertible
BOOTLOADER=depthcharge
KERNEL_FILE=kernel.img
PARTITION_TABLE_TYPE=gpt
BOOT_SIZE=32M
BOOT_SPL=false
DISK_SIZE=6G
SUPERVISOR_MACHINE=qemuarm-64
SUPERVISOR_ARCH=aarch64
EOF

cat > "$BOARD_DIR/cmdline.txt" <<'EOF'
root=PARTUUID=%U/PARTNROFF=1 rootwait zram.enabled=1 zram.num_devices=3 fsck.repair=yes loglevel=2 quiet
EOF

cat > "$BOARD_DIR/kernel.config" <<'EOF'
CONFIG_ARCH_MEDIATEK=y
CONFIG_ARCH_MEDIATEK_MTK=y
CONFIG_COMMON_CLK_MT8183=y
CONFIG_PINCTRL_MT8183=y
CONFIG_I2C_MT65XX=y
CONFIG_MTK_EFUSE=y
CONFIG_MTK_INFRACFG=y
CONFIG_MTK_SCPSYS=y
CONFIG_MTK_SCPSYS_PM_DOMAINS=y
CONFIG_MTK_CMDQ=y
CONFIG_MTK_SCP=y
CONFIG_MTK_SVS=y
CONFIG_MTK_THERMAL=y
CONFIG_MTK_TIMER=y
CONFIG_MTK_UART=y
CONFIG_MMC_MTK=y
CONFIG_PHY_MTK_TPHY=y
CONFIG_PHY_MTK_XSPHY=y
CONFIG_PWM_MTK_DISP=y
CONFIG_PWM_MEDIATEK=y
CONFIG_DRM_MEDIATEK=y
CONFIG_DRM_MEDIATEK_HDMI=y
CONFIG_DRM_PARADE_PS8640=y
CONFIG_DRM_ANALOGIX_ANX7625=y
CONFIG_TYPEC_MT6360=y
CONFIG_MFD_MT6360=y
CONFIG_MFD_MT6397=y
CONFIG_REGULATOR_MT6358=y
CONFIG_CHARGER_MT6360=y
CONFIG_MTK_PMIC_WRAP=y
CONFIG_CROS_EC=y
CONFIG_CROS_EC_I2C=y
CONFIG_CROS_EC_SPI=y
CONFIG_CROS_EC_CHARDEV=y
CONFIG_CROS_EC_LIGHTBAR=y
CONFIG_CROS_EC_SENSORHUB=y
CONFIG_CROS_EC_SYSFS=y
CONFIG_CROS_USBPD_LOGGER=y
CONFIG_CROS_USBPD_NOTIFY=y
CONFIG_CHROME_PLATFORMS=y
CONFIG_KEYBOARD_CROS_EC=y
CONFIG_I2C_HID_OF=y
CONFIG_I2C_HID_OF_ELAN=y
CONFIG_I2C_HID_OF_GOODIX=y
CONFIG_TOUCHSCREEN_ATMEL_MXT=y
CONFIG_TOUCHSCREEN_ELAN=y
CONFIG_TOUCHSCREEN_ELAN_I2C=y
CONFIG_BATTERY_SBS=y
CONFIG_SND_SOC_MT8183=y
CONFIG_SND_SOC_MT8183_DA7219_MAX98357A=y
CONFIG_SND_SOC_MT8183_MT6358_TS3A227E_MAX98357A=y
CONFIG_BT_HCIUART_QCA=y
CONFIG_ATH10K=y
CONFIG_ATH10K_PCI=y
CONFIG_ATH10K_SDIO=y
CONFIG_DEVFREQ_THERMAL=y
EOF

cat > "$BOARD_DIR/genimage.cfg" <<'EOF'
image overlay.ext4 {
	size = ${OVERLAY_SIZE}
	empty = "yes"

	ext4 {
		use-mke2fs = "yes"
		label = "hassos-overlay"
		extraargs = "-I 256 -E lazy_itable_init=0,lazy_journal_init=0"
	}
}

image "${IMAGE_NAME}.img" {
	size = "${DISK_SIZE:-6G}"

	hdimage {
		partition-table-type = "gpt"
	}

	partition hassos-boot {
		size = ${BOOT_SIZE}
		partition-type-uuid = "linux"
		partition-uuid = "b3dd0952-733c-4c88-8cba-cab9b8b4377f"
		image = "boot.vfat"
	}

	partition hassos-kernel0 {
		partition-type-uuid = "FE3A2A5D-4F32-41A7-B725-ACCC3285A309"
		partition-uuid = "26700fc6-b0bc-4ccf-9837-ea1a4cba3e65"
		size = ${KERNEL_SIZE}
		image = "kernel.img"
	}

	partition hassos-system0 {
		partition-type-uuid = "linux"
		partition-uuid = "8d3d53e3-6d49-4c38-8349-aff6859e82fd"
		size = ${SYSTEM_SIZE}
		image = ${SYSTEM_IMAGE}
	}

	partition hassos-kernel1 {
		partition-type-uuid = "FE3A2A5D-4F32-41A7-B725-ACCC3285A309"
		partition-uuid = "fc02a4f0-5350-406f-93a2-56cbed636b5f"
		size = ${KERNEL_SIZE}
		image = "kernel.img"
	}

	partition hassos-system1 {
		partition-type-uuid = "linux"
		partition-uuid = "a3ec664e-32ce-4665-95ea-7ae90ce9aa20"
		size = ${SYSTEM_SIZE}
	}

	partition hassos-bootstate {
		partition-type-uuid = "linux"
		partition-uuid = "33236519-7f32-4dff-8002-3390b62c309d"
		size = ${BOOTSTATE_SIZE}
	}

	partition hassos-overlay {
		partition-type-uuid = "linux"
		partition-uuid = "f1326040-5236-40eb-b683-aaa100a9afcf"
		size = ${OVERLAY_SIZE}
		image = "overlay.ext4"
	}

	partition hassos-data {
		partition-type-uuid = "linux"
		partition-uuid = "a52a4597-fa3a-4851-aefd-2fbe9f849079"
		size = ${DATA_SIZE}
		image = ${DATA_IMAGE}
	}
}

image "${IMAGE_NAME}.raucb" {
	include("image-raucb-nospl.cfg")
}
EOF

cat > "$BOARD_DIR/hassos-hook.sh" <<'EOF'
#!/bin/bash
# shellcheck disable=SC2155

function hassos_pre_image() {
    local BOOT_DATA="$(path_boot_dir)"
    local cmdline
    local -a dtbs=()

    cp "${BOARD_DIR}/cmdline.txt" "${BOOT_DATA}/cmdline.txt"
    mkdir -p "${BOOT_DATA}/dtbs/mediatek"

    while IFS= read -r dtb; do
        dtbs+=("${dtb}")
        cp "${dtb}" "${BOOT_DATA}/dtbs/mediatek/"
    done < <(find "${BINARIES_DIR}" -type f -path "*/mt8183-kukui*.dtb" | sort)

    if [ "${#dtbs[@]}" -eq 0 ]; then
        echo "ERROR: no mt8183-kukui DTBs were built"
        exit 1
    fi

    if ! command -v mkdepthcharge >/dev/null 2>&1; then
        echo "ERROR: mkdepthcharge is required for google-kukui HAOS images"
        echo "       The patched HAOS Dockerfile installs depthcharge-tools."
        exit 1
    fi

    cmdline="$(tr '\n' ' ' < "${BOARD_DIR}/cmdline.txt")"
    mkdepthcharge \
        -o "${BINARIES_DIR}/kernel.img" \
        --arch arm64 \
        --compress lzma \
        --cmdline "${cmdline}" \
        -- \
        "${BINARIES_DIR}/Image" \
        "${dtbs[@]}"
}

function hassos_post_image() {
    local image
    image="$(hassos_image_name img)"

    # Make Depthcharge prefer slot A on fresh images while keeping slot B valid
    # for RAUC updates. ChromeOS GPT attrs: priority=bits 48-51,
    # tries=bits 52-55, successful=bit 56.
    sgdisk \
        --attributes=2:set:48 --attributes=2:set:49 --attributes=2:set:50 --attributes=2:set:51 \
        --attributes=2:clear:52 --attributes=2:clear:53 --attributes=2:clear:54 --attributes=2:clear:55 \
        --attributes=2:set:56 \
        --attributes=4:set:48 --attributes=4:clear:49 --attributes=4:clear:50 --attributes=4:clear:51 \
        --attributes=4:clear:52 --attributes=4:clear:53 --attributes=4:clear:54 --attributes=4:clear:55 \
        --attributes=4:clear:56 \
        "${image}"

    convert_disk_image_xz
}
EOF

cat > "$BOARD_DIR/rootfs-overlay/usr/lib/rauc/depthcharge-backend" <<'EOF'
#!/bin/sh
set -eu

DISK=""

disk_for_partlabel() {
    local label="$1" dev base diskbase
    dev="$(readlink -f "/dev/disk/by-partlabel/${label}")"
    base="$(basename "$dev")"
    case "$base" in
        nvme*n*p[0-9]*|mmcblk*p[0-9]*|loop*p[0-9]*) diskbase="${base%p[0-9]*}" ;;
        *[0-9]) diskbase="${base%[0-9]*}" ;;
        *) diskbase="" ;;
    esac
    if [ -z "$diskbase" ]; then
        echo "Unable to resolve disk for ${label}" >&2
        exit 1
    fi
    echo "/dev/${diskbase}"
}

disk() {
    if [ -z "$DISK" ]; then
        DISK="$(disk_for_partlabel hassos-kernel0)"
    fi
    echo "$DISK"
}

partnum() {
    case "$1" in
        A) echo 2 ;;
        B) echo 4 ;;
        *) echo "Unknown slot $1" >&2; exit 1 ;;
    esac
}

guid_for_partnum() {
    sgdisk -i "$1" "$(disk)" | awk -F': ' '/Partition unique GUID/ {print tolower($2)}'
}

attr_hex() {
    sgdisk -i "$(partnum "$1")" "$(disk)" | awk -F': ' '/Attribute flags/ {print $2}'
}

bit_set() {
    local hex="$1" bit="$2"
    [ $(( (0x$hex >> bit) & 1 )) -eq 1 ]
}

priority() {
    local hex="$1"
    echo $(( (0x$hex >> 48) & 15 ))
}

set_range() {
    local part="$1" start="$2" width="$3" value="$4" i mask
    i=0
    while [ "$i" -lt "$width" ]; do
        mask=$((1 << i))
        if [ $((value & mask)) -ne 0 ]; then
            sgdisk --attributes="${part}:set:$((start + i))" "$(disk)" >/dev/null
        else
            sgdisk --attributes="${part}:clear:$((start + i))" "$(disk)" >/dev/null
        fi
        i=$((i + 1))
    done
}

set_slot_boot_attrs() {
    local slot="$1" priority="$2" tries="$3" successful="$4" part
    part="$(partnum "$slot")"
    set_range "$part" 48 4 "$priority"
    set_range "$part" 52 4 "$tries"
    if [ "$successful" = "1" ]; then
        sgdisk --attributes="${part}:set:56" "$(disk)" >/dev/null
    else
        sgdisk --attributes="${part}:clear:56" "$(disk)" >/dev/null
    fi
}

case "${1:-}" in
    get-primary)
        pa="$(priority "$(attr_hex A)")"
        pb="$(priority "$(attr_hex B)")"
        if [ "$pb" -gt "$pa" ]; then echo B; else echo A; fi
        ;;
    set-primary)
        slot="${2:?slot required}"
        if [ "$slot" = "A" ]; then
            set_slot_boot_attrs A 15 3 0
            set_slot_boot_attrs B 1 0 0
        else
            set_slot_boot_attrs B 15 3 0
            set_slot_boot_attrs A 1 0 0
        fi
        ;;
    get-state)
        slot="${2:?slot required}"
        if bit_set "$(attr_hex "$slot")" 56; then echo good; else echo bad; fi
        ;;
    set-state)
        slot="${2:?slot required}"
        state="${3:?state required}"
        case "$state" in
            good) set_slot_boot_attrs "$slot" 15 0 1 ;;
            bad) set_slot_boot_attrs "$slot" 0 0 0 ;;
            *) echo "Unknown state $state" >&2; exit 1 ;;
        esac
        ;;
    get-current)
        guid="$(sed -n 's/.*kern_guid=\([0-9A-Fa-f-]*\).*/\1/p' /proc/cmdline | tr 'A-F' 'a-f')"
        [ -n "$guid" ] || guid="$(sed -n 's/.*root=PARTUUID=\([0-9A-Fa-f-]*\)\/PARTNROFF=.*/\1/p' /proc/cmdline | tr 'A-F' 'a-f')"
        [ -n "$guid" ] || exit 1
        if [ "$guid" = "$(guid_for_partnum 2)" ]; then
            echo A
        elif [ "$guid" = "$(guid_for_partnum 4)" ]; then
            echo B
        else
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 get-primary|set-primary <A|B>|get-state <A|B>|set-state <A|B> <good|bad>|get-current" >&2
        exit 1
        ;;
esac
EOF
chmod +x "$BOARD_DIR/hassos-hook.sh" "$BOARD_DIR/rootfs-overlay/usr/lib/rauc/depthcharge-backend"

cp "$GENERIC_DEFCONFIG" "$DEFCONFIG"

set_config() {
    key="$1"
    value="$2"
    if grep -q "^${key}=" "$DEFCONFIG"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$DEFCONFIG"
    else
        echo "${key}=${value}" >> "$DEFCONFIG"
    fi
}

remove_config() {
    key="$1"
    sed -i "/^${key}=/d" "$DEFCONFIG"
}

set_config BR2_ROOTFS_POST_SCRIPT_ARGS '"$(BR2_EXTERNAL_HASSOS_PATH)/board/google/kukui $(BR2_EXTERNAL_HASSOS_PATH)/board/google/kukui/hassos-hook.sh"'
set_config BR2_ROOTFS_OVERLAY '"$(BR2_EXTERNAL_HASSOS_PATH)/rootfs-overlay $(BR2_EXTERNAL_HASSOS_PATH)/board/google/kukui/rootfs-overlay"'
set_config BR2_LINUX_KERNEL_USE_ARCH_DEFAULT_CONFIG y
remove_config BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG
remove_config BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE
set_config BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES '"$(BR2_EXTERNAL_HASSOS_PATH)/kernel/v6.18.y/hassos.config $(BR2_EXTERNAL_HASSOS_PATH)/kernel/v6.18.y/docker.config $(BR2_EXTERNAL_HASSOS_PATH)/kernel/v6.18.y/device-support.config $(BR2_EXTERNAL_HASSOS_PATH)/kernel/v6.18.y/device-support-wireless.config $(BR2_EXTERNAL_HASSOS_PATH)/board/google/kukui/kernel.config"'
set_config BR2_LINUX_KERNEL_DTS_SUPPORT y
set_config BR2_LINUX_KERNEL_INTREE_DTS_NAME '"mediatek/mt8183-kukui-jacuzzi-burnet mediatek/mt8183-kukui-jacuzzi-cozmo mediatek/mt8183-kukui-jacuzzi-damu mediatek/mt8183-kukui-jacuzzi-fennel-sku1 mediatek/mt8183-kukui-jacuzzi-fennel-sku6 mediatek/mt8183-kukui-jacuzzi-fennel-sku7 mediatek/mt8183-kukui-jacuzzi-fennel14 mediatek/mt8183-kukui-jacuzzi-fennel14-sku2 mediatek/mt8183-kukui-jacuzzi-juniper-sku16 mediatek/mt8183-kukui-jacuzzi-kappa mediatek/mt8183-kukui-jacuzzi-kenzo mediatek/mt8183-kukui-jacuzzi-makomo-sku0 mediatek/mt8183-kukui-jacuzzi-makomo-sku1 mediatek/mt8183-kukui-jacuzzi-pico mediatek/mt8183-kukui-jacuzzi-pico6 mediatek/mt8183-kukui-jacuzzi-willow-sku0 mediatek/mt8183-kukui-jacuzzi-willow-sku1 mediatek/mt8183-kukui-kakadu mediatek/mt8183-kukui-kakadu-sku22 mediatek/mt8183-kukui-katsu-sku32 mediatek/mt8183-kukui-katsu-sku38 mediatek/mt8183-kukui-kodama-sku16 mediatek/mt8183-kukui-kodama-sku272 mediatek/mt8183-kukui-kodama-sku288 mediatek/mt8183-kukui-kodama-sku32 mediatek/mt8183-kukui-krane-sku0 mediatek/mt8183-kukui-krane-sku176"'
set_config BR2_PACKAGE_LINUX_FIRMWARE_ATHEROS_10K_QCA9377 y
set_config BR2_PACKAGE_LINUX_FIRMWARE_QUALCOMM_6174 y
set_config BR2_PACKAGE_LINUX_FIRMWARE_QUALCOMM_6174A_BT y
remove_config BR2_TARGET_GRUB2
remove_config BR2_TARGET_GRUB2_BUILTIN_MODULES_EFI
remove_config BR2_TARGET_GRUB2_INSTALL_TOOLS
set_config BR2_PACKAGE_GPTFDISK y
set_config BR2_PACKAGE_GPTFDISK_SGDISK y
set_config BR2_PACKAGE_HASSIO_MACHINE '"qemuarm-64"'
set_config BR2_PACKAGE_OS_AGENT_BOARD '"GoogleKukui"'

if [ -f "$DOCKERFILE" ] && ! grep -q "depthcharge-tools" "$DOCKERFILE"; then
    tmp="$(mktemp)"
    awk '
        /python-is-python3 \\/ {
            print
            print "        depthcharge-tools \\"
            print "        device-tree-compiler \\"
            print "        gdisk \\"
            print "        lz4 \\"
            print "        u-boot-tools \\"
            print "        vboot-utils \\"
            next
        }
        { print }
    ' "$DOCKERFILE" > "$tmp"
    mv "$tmp" "$DOCKERFILE"
fi

if ! grep -q 'BOOTLOADER") "depthcharge"' "$SYSTEM_CONF"; then
    tmp="$(mktemp)"
    awk '
        /if eq \(env "BOOTLOADER"\) "tryboot"/ && !done_system {
            print "{{- if eq (env \"BOOTLOADER\") \"depthcharge\" }}"
            print "bootloader=custom"
            print "{{- else if eq (env \"BOOTLOADER\") \"tryboot\" }}"
            done_system=1
            next
        }
        /\{\{- if eq \(env "BOOTLOADER"\) "tryboot" \}\}/ && !done_handlers {
            print "{{- if eq (env \"BOOTLOADER\") \"depthcharge\" }}"
            print "[handlers]"
            print "bootloader-custom-backend=/usr/lib/rauc/depthcharge-backend"
            print ""
            print "{{- else if eq (env \"BOOTLOADER\") \"tryboot\" }}"
            done_handlers=1
            next
        }
        { print }
    ' "$SYSTEM_CONF" > "$tmp"
    mv "$tmp" "$SYSTEM_CONF"
fi

echo "Wrote HAOS google-kukui board support into $HAOS_DIR"
