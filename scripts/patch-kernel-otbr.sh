#!/bin/sh
# 为 google-kukui 内核添加 OTBR / OpenThread 多播路由支持
#
# 硬件背景：
#   - Thread radio: ESP32-C6（USB 直连，CDC-ACM → /dev/ttyACM0，USB 驱动已正常工作）
#   - OTBR 运行方式：Docker 容器运行在 kukui 本机
#   - 问题：内核缺少多播路由支持，导致 Home Assistant Thread 包转发失败
#
# 使用方式（在容器内运行）：
#   1. 确保已 pmbootstrap init + pmbootstrap pull-aports
#   2. 运行本脚本：bash /scripts/patch-kernel-otbr.sh
#   3. 构建内核：pmbootstrap build linux-google-kukui
#   4. 刷入：pmbootstrap flasher flash_kernel --device google-kukui
#
set -eu

# ────────────────────────────────────────────────────────────
# 探测 kukui 内核配置文件路径（sh 兼容，不用数组）
# ────────────────────────────────────────────────────────────
find_config() {
    # ── 动态读取 pmbootstrap aports 路径 ────────────────────
    PMAPORTS_DYNAMIC=""
    if command -v pmbootstrap >/dev/null 2>&1; then
        # 尝试以 pmbuild 用户读取（需要 HOME 正确）
        for _home in /work/pmbootstrap /root /home/pmbuild; do
            _ap=$(HOME="$_home" pmbootstrap config aports 2>/dev/null || true)
            if [ -n "$_ap" ] && [ -d "$_ap" ]; then
                PMAPORTS_DYNAMIC="$_ap"
                break
            fi
        done
    fi

    # ── 候选路径列表（优先级从高到低） ──────────────────────
    SEARCH_DIRS="
        /work/edge/device/community/linux-postmarketos-mediatek-mt81
        /work/edge/device/community/linux-postmarketos-mediatek-mt81xx
        /work/pmbootstrap/.local/var/pmbootstrap/cache_git/pmaports/device/community/linux-postmarketos-mediatek-mt81
        /work/pmbootstrap/.local/var/pmbootstrap/cache_git/pmaports/device/community/linux-postmarketos-mediatek-mt81xx
        /work/pmbootstrap/cache_git/pmaports/device/community/linux-postmarketos-mediatek-mt81
    "
    if [ -n "$PMAPORTS_DYNAMIC" ]; then
        SEARCH_DIRS="$PMAPORTS_DYNAMIC/device/community/linux-postmarketos-mediatek-mt81
$SEARCH_DIRS"
    fi

    for d in $SEARCH_DIRS; do
        d=$(echo "$d" | tr -d ' ')
        [ -z "$d" ] && continue
        cfg="$d/config-postmarketos-mediatek-mt81.aarch64"
        if [ -f "$cfg" ]; then
            echo "$cfg"
            return 0
        fi
    done
    return 1
}

CONFIG_FILE="$(find_config)" || {
    echo "ERROR: 未找到 google-kukui 内核配置文件。"
    echo "请先运行：pmbootstrap pull-aports"
    exit 1
}

echo "✓ 内核配置文件: $CONFIG_FILE"
cp "$CONFIG_FILE" "/tmp/kconfig-backup-$(date +%Y%m%d%H%M%S).aarch64"
echo "✓ 已备份到 /tmp/"

# ────────────────────────────────────────────────────────────
# 工具函数
# ────────────────────────────────────────────────────────────
kset_y() {
    local key="$1"
    if grep -q "^${key}=" "$CONFIG_FILE"; then
        sed -i "s|^${key}=.*|${key}=y|" "$CONFIG_FILE"
    elif grep -q "^# ${key} is not set" "$CONFIG_FILE"; then
        sed -i "s|^# ${key} is not set|${key}=y|" "$CONFIG_FILE"
    else
        echo "${key}=y" >> "$CONFIG_FILE"
    fi
}

# pmaports 策略要求部分项以模块形式存在（=m），用于 Waydroid/containers/nftables 类别
kset_m() {
    local key="$1"
    if grep -q "^${key}=y" "$CONFIG_FILE"; then
        sed -i "s|^${key}=y|${key}=m|" "$CONFIG_FILE"
    elif grep -q "^# ${key} is not set" "$CONFIG_FILE"; then
        sed -i "s|^# ${key} is not set|${key}=m|" "$CONFIG_FILE"
    elif ! grep -q "^${key}=" "$CONFIG_FILE"; then
        echo "${key}=m" >> "$CONFIG_FILE"
    fi
    # 若已经是 =m，不需要改动
}

echo ""
echo "=== 添加 OTBR / Matter / Docker / BLE 内核配置 ==="

# ────────────────────────────────────────────────────────────
# 1. IPv6 多播路由（OTBR backbone multicast routing 核心缺失项）
#    症状：Home Assistant Thread 网络包转发失败，MLD proxy 不可用
# ────────────────────────────────────────────────────────────
echo "[1/7] IPv6 多播路由（核心修复）..."
kset_y CONFIG_IPV6
kset_y CONFIG_IPV6_MULTIPLE_TABLES     # 多路由表（OTBR 策略路由依赖）
kset_y CONFIG_IPV6_SUBTREES
kset_y CONFIG_IPV6_ROUTER_PREF        # RA 路由器偏好
kset_y CONFIG_IPV6_ROUTE_INFO
kset_y CONFIG_IPV6_MROUTE              # ★ IPv6 多播路由基础
kset_y CONFIG_IPV6_MROUTE_MULTIPLE_TABLES   # ★ 多播多路由表
kset_y CONFIG_IPV6_PIMSM_V2            # ★ PIM-SM v2（OTBR backbone multicast）

# ────────────────────────────────────────────────────────────
# 2. IPv4 多播路由（MLD proxy 的 IPv4 侧，及 mDNS/CoAP 转发）
# ────────────────────────────────────────────────────────────
echo "[2/7] IPv4 多播路由..."
kset_y CONFIG_IP_MROUTE
kset_y CONFIG_IP_MROUTE_MULTIPLE_TABLES
kset_y CONFIG_IP_PIMSM_V1
kset_y CONFIG_IP_PIMSM_V2

# ────────────────────────────────────────────────────────────
# 3. TUN 设备（OTBR 创建 wpan0 / tun0 Thread 网络接口）
# ────────────────────────────────────────────────────────────
echo "[3/7] TUN 虚拟网络接口..."
kset_y CONFIG_TUN

# ────────────────────────────────────────────────────────────
# 4. Netfilter（OTBR Docker 容器需要 NAT64 / iptables）
# ────────────────────────────────────────────────────────────
echo "[4/8] Netfilter / iptables（pmaports 策略：nftables 类 =m）..."
kset_y CONFIG_NETFILTER
kset_y CONFIG_NF_CONNTRACK             # containers: 已启用，策略偏好 =m，保持 =y（container 功能需要）
kset_y CONFIG_NF_NAT
kset_y CONFIG_NF_NAT_IPV4
kset_y CONFIG_NF_NAT_IPV6
kset_m CONFIG_IP_NF_IPTABLES           # pmaports nftables/containers 类：prefer =m
kset_m CONFIG_IP_NF_FILTER             # prefer =m
kset_y CONFIG_IP_NF_TARGET_MASQUERADE  # Docker 出口 NAT（=y）
kset_m CONFIG_IP_NF_RAW                # containers 类 WARNING：must be enabled as =m
kset_m CONFIG_IP6_NF_IPTABLES          # prefer =m
kset_m CONFIG_IP6_NF_FILTER            # prefer =m
kset_y CONFIG_IP6_NF_MANGLE
kset_m CONFIG_IP6_NF_RAW               # containers 类 WARNING：must be enabled as =m
# nftables（Docker 新版本，pmaports 策略：prefer =m）
kset_m CONFIG_NF_TABLES
kset_m CONFIG_NF_TABLES_IPV4
kset_m CONFIG_NF_TABLES_IPV6
kset_m CONFIG_NFT_NAT
kset_m CONFIG_NFT_MASQ

# ────────────────────────────────────────────────────────────
# 5. 容器网络（OTBR 跑在 kukui 本机的 Docker 里需要）
#    注：ESP32-C6 USB CDC-ACM 驱动 (USB_ACM) 已正常工作，无需修改
# ────────────────────────────────────────────────────────────
echo "[5/8] 容器网络（pmaports 策略：Waydroid/containers 类 =m）..."
kset_m CONFIG_VETH                     # Waydroid/containers: prefer =m
kset_m CONFIG_BRIDGE                   # prefer =m
kset_m CONFIG_BRIDGE_NETFILTER         # prefer =m
kset_y CONFIG_NET_NS

# ────────────────────────────────────────────────────────────
# 6. BLE：Matter 设备配网（commissioning）必须用 BLE
#    CONFIG_BT_LE 默认未启用，导致 Matter 完全无法工作！
# ────────────────────────────────────────────────────────────
echo "[6/8] BLE（Matter commissioning 必须）..."
kset_y CONFIG_BT_LE                    # ★ BLE 核心支持（当前 not set，严重缺失）
kset_y CONFIG_BT_BNEP                  # BT 网络配置（蓝牙 PAN）

echo "[7/8] 网络队列调度器（FQ/FQ-CoDel/CAKE）..."
kset_y CONFIG_NET_SCH_FQ
kset_y CONFIG_NET_SCH_FQ_CODEL
kset_y CONFIG_NET_SCH_CAKE
kset_y CONFIG_ENCRYPTED_KEYS

echo "[8/8] pmaports kconfig check 要求的缺失项..."
# category:default
kset_y CONFIG_BPF_LSM                  # BPF 安全模块
kset_y CONFIG_KPROBES                  # Kernel probes（eBPF/perf 依赖）
kset_y CONFIG_KPROBE_EVENTS            # Kprobe trace events
# category:filesystems - EROFS 压缩支持
kset_y CONFIG_EROFS_FS_ZIP_LZMA
kset_y CONFIG_EROFS_FS_ZIP_DEFLATE
kset_y CONFIG_EROFS_FS_ZIP_ZSTD
# category:netboot
kset_m CONFIG_BLK_DEV_UBLK            # UBLK 用户态块设备（netboot）

echo ""
echo "=== 配置完成 ==="
echo ""
echo "关键配置项验证："
for key in \
    CONFIG_IPV6_MROUTE \
    CONFIG_IPV6_MROUTE_MULTIPLE_TABLES \
    CONFIG_IPV6_PIMSM_V2 \
    CONFIG_IP_MROUTE \
    CONFIG_IP_PIMSM_V2 \
    CONFIG_TUN \
    CONFIG_NF_NAT \
    CONFIG_VETH \
    CONFIG_BRIDGE \
    CONFIG_BT_LE \
    CONFIG_NET_SCH_FQ_CODEL; do
    val=$(grep "^${key}=" "$CONFIG_FILE" 2>/dev/null || echo "(未设置)")
    printf "  %-45s %s\n" "$key" "$val"
done

# ── 更新 APKBUILD checksum（配置文件已修改，必须更新否则构建失败） ──────
echo "=== 更新 APKBUILD checksum ==="
if command -v pmbootstrap >/dev/null 2>&1; then
    pmbootstrap checksum linux-postmarketos-mediatek-mt81 \
        && echo "✓ checksum 已更新" \
        || echo "⚠ checksum 更新失败，请手动运行: pmbootstrap checksum linux-postmarketos-mediatek-mt81"
else
    echo "⚠ pmbootstrap 未在 PATH 中，跳过 checksum 更新"
    echo "  请手动运行: pmbootstrap checksum linux-postmarketos-mediatek-mt81"
fi

# ── 安装 tar wrapper（Docker overlay2 解压修复） ────────────────────────
echo "=== 安装 tar wrapper（overlay2 修复） ==="
CHROOT_TAR="/work/pmbootstrap/chroot_native/usr/bin/tar"
if [ -f "$CHROOT_TAR" ] && [ ! -f "${CHROOT_TAR}.real" ]; then
    cp "$CHROOT_TAR" "${CHROOT_TAR}.real"
    cp /scripts/tar-wrapper.sh "$CHROOT_TAR"
    chmod +x "$CHROOT_TAR"
    echo "✓ tar wrapper 已安装"
elif [ ! -f "$CHROOT_TAR" ]; then
    echo "  native chroot 尚未创建，构建完成第一阶段后会自动需要安装"
    echo "  若构建中途因 'Directory renamed' 报错，请运行:"
    echo "  bash /scripts/patch-kernel-otbr.sh  （会重新安装 wrapper）"
fi

echo ""
echo "下一步："
echo "  # 以 pmbuild 用户运行构建："
echo "  su -s /bin/sh pmbuild -c 'export HOME=/work/pmbootstrap; pmbootstrap build linux-postmarketos-mediatek-mt81'"
echo "  su -s /bin/sh pmbuild -c 'export HOME=/work/pmbootstrap; pmbootstrap flasher flash_kernel --device google-kukui'"
echo ""
echo "刷入后验证："
echo "  cat /proc/net/ip6_mr_vif      # IPv6 多播路由接口（OTBR）"
echo "  hciconfig -a                  # 蓝牙接口（BLE/Matter）"
echo "  tc qdisc show                 # 队列调度器（应看到 fq_codel）"
