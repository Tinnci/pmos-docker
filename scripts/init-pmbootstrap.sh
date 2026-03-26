#!/bin/sh
# pmbootstrap 初始化脚本（sh 兼容，适配 docker-postmarketos 容器）
# 目标设备：google-kukui (Chromebook Crane, MT8183, aarch64)
# 通过 "printf | pmbootstrap init" 非交互式初始化（兼容 pmbootstrap 3.9.0）
set -e

# 确保 pmbootstrap 可用
if ! command -v pmbootstrap >/dev/null 2>&1; then
    echo "pmbootstrap not found. Running bootstrap first..."
    sh /scripts/bootstrap-pmbootstrap.sh
fi

# 创建非 root 构建用户
if ! id pmbuild >/dev/null 2>&1; then
    adduser -D -u 1000 pmbuild 2>/dev/null || true
fi

# 给 pmbuild 用户 passwordless sudo（pmbootstrap 用 sudo 管理 chroot 目录）
echo 'pmbuild ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/pmbuild
chmod 440 /etc/sudoers.d/pmbuild
chmod 777 /work /ccache 2>/dev/null || true
mkdir -p /work/pmbootstrap
chown -R pmbuild:pmbuild /work/pmbootstrap /ccache 2>/dev/null || true

echo "=== pmbootstrap $(pmbootstrap --version) ==="

# ── 初始化 pmbootstrap（若未初始化or格式不兼容）──────────────────────────
# 检查方式：能否正确读取 device 配置（3.9.0 读取旧格式 cfg 会报错退出）
ALREADY_INIT=false
if su -s /bin/sh pmbuild -c \
    "export HOME=/work/pmbootstrap; pmbootstrap config device 2>/dev/null" \
    2>/dev/null | grep -q "google-kukui"; then
    ALREADY_INIT=true
fi

if [ "$ALREADY_INIT" = "false" ]; then
    echo "=== 运行 pmbootstrap init ==="
    # 策略：先用全默认值完成 init（接受所有提问），再用 pmbootstrap config 修正具体设置。
    # 原因：git 克隆 pmaports（约2分钟）期间 pmbootstrap 仍在消耗 stdin，
    # 导致 printf 的定位输入被错误消耗，vendor/device 无法正确传入。
    # 全默认 init 只需 \n 序列，不受克隆耗时影响。
    #
    # 实际提示顺序（pmbootstrap 3.9.0）：
    #  1. work path            → \n (默认)
    #  2. pmaports path        → \n (默认，然后开始 git clone，约2分钟)
    #  3. channel              → \n (默认 edge)
    #  4. vendor               → \n (默认 qemu)
    #  5. device codename      → \n (默认 amd64)
    #  6. provider ×3          → \n\n\n (audio/wifi/usb，各取默认)
    #  7. UI                   → \n (默认 console)
    #  8. systemd?             → \n (默认)
    #  9. change extra opts?   → \n (默认 n)
    # 10. extra packages       → \n (默认 none)
    # 11. locale               → \n (默认 en_US)
    # 12. hostname             → \n (默认)
    # 13. build outdated?      → \n (默认 y)
    printf '\n\n\n\n\n\n\n\n\n\n\n\n\n' | \
        su -s /bin/sh pmbuild -c \
        "export HOME=/work/pmbootstrap; export CCACHE_DIR=/ccache; pmbootstrap init"
    echo "✓ pmbootstrap init 完成（默认配置）"

    # 现在用 config 命令修正目标设备和 UI
    echo "=== 配置目标设备 ==="
    su -s /bin/sh pmbuild -c "
        export HOME=/work/pmbootstrap
        pmbootstrap config device google-kukui
        pmbootstrap config ui plasma-mobile
        pmbootstrap config kernel postmarketos-mediatek-mt81
        pmbootstrap config ccache_size 5G
        echo '✓ device=google-kukui, ui=plasma-mobile'
        pmbootstrap config device
    "
else
    echo "✓ pmbootstrap 已初始化 (device=google-kukui)"
fi

echo ""
echo "=== 检查 pmaports ==="
su -s /bin/sh pmbuild -c "
export HOME=/work/pmbootstrap
APORTS_DIR=\$(pmbootstrap config aports 2>/dev/null || \
    echo /work/pmbootstrap/.local/var/pmbootstrap/cache_git/pmaports)
if [ ! -d \"\$APORTS_DIR/.git\" ]; then
    echo '正在拉取 pmaports...'
    pmbootstrap pull
    echo '✓ pmaports 已拉取'
else
    echo '✓ pmaports 已存在: '\$APORTS_DIR
fi
" 2>&1

echo ""
echo "=== 初始化完成 ==="
su -s /bin/sh pmbuild -c \
    "export HOME=/work/pmbootstrap; pmbootstrap config device" 2>&1 \
    | xargs echo "device:" || true
su -s /bin/sh pmbuild -c \
    "export HOME=/work/pmbootstrap; pmbootstrap config aports" 2>&1 \
    | xargs -I{} echo "pmaports: {}" || true
