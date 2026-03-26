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
    # 策略：在 pmbootstrap init 的前两个提示直接输入正确路径，
    # 其余提问全部用 \n 接受默认值，再用 pmbootstrap config 修正设备/UI。
    #
    # 不能事后用 pmbootstrap config work 修改 work dir！
    # 原因：pmbootstrap 会尝试将「无 version 文件的目录」migrate 到 v8 → ERROR
    # 必须在 init 时第一个提示就输入目标路径，pmbootstrap 才会在那里创建正确的 work dir 结构。
    #
    # 实际提示顺序（pmbootstrap 3.9.0，qemu/amd64 默认）：
    #  1.  work path            → /work/pmbootstrap        ★ 显式指定！
    #  2.  pmaports path        → /work/pmbootstrap/cache_git/pmaports  ★ 显式指定！
    #                            (然后 git clone pmaports，约2分钟)
    #  3.  channel              → \n  (默认 edge)
    #  4.  vendor               → \n  (默认 qemu)
    #  5.  device codename      → \n  (默认 amd64)
    #  6.  kernel               → \n  (qemu 专有提示，默认 stable)
    #  7.  username             → \n  (默认 user)
    #  8.  provider audio       → \n  (默认 pulseaudio)
    #  9.  provider wifi        → \n  (默认 wpa_supplicant)
    # 10.  provider usb-moded   → \n  (默认 developer)
    # 11.  UI                   → \n  (默认 console)
    # 12.  systemd?             → \n  (默认)
    # 13.  change extra opts?   → \n  (默认 n)
    # 14.  extra packages       → \n  (默认 none)
    # 15.  locale               → \n  (默认 en_US)
    # 16.  hostname             → \n  (默认)
    # 17.  build outdated?      → \n  (默认 y)
    # 额外 3 个 \n 余量
    printf '/work/pmbootstrap\n/work/pmbootstrap/cache_git/pmaports\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n' | \
        su -s /bin/sh pmbuild -c \
        "export HOME=/work/pmbootstrap; export CCACHE_DIR=/ccache; pmbootstrap init"
    echo "✓ pmbootstrap init 完成（work=/work/pmbootstrap）"

    # 用 config 命令修正目标设备和 UI（不再修改 work，init 时已正确设置）
    echo "=== 配置目标设备 ==="
    su -s /bin/sh pmbuild -c "
        export HOME=/work/pmbootstrap
        pmbootstrap config device google-kukui
        pmbootstrap config ui plasma-mobile
        pmbootstrap config kernel postmarketos-mediatek-mt81
        pmbootstrap config ccache_size 5G
        echo '✓ device=google-kukui, ui=plasma-mobile, work=/work/pmbootstrap'
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
