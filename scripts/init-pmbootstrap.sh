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
    # 18 个输入覆盖所有交互提示（使用默认值或指定值）：
    #   \n\n\n  = work path, alpine mirror, pmaports mirror（取默认）
    #   google  = vendor
    #   kukui   = codename
    #   \n×13   = kernel, user, password×2, UI, UI extras, packages,
    #             hostname, timezone, locale, SSH，以及其余默认提示
    printf '\n\n\ngoogle\nkukui\n\n\n\n\n\n\n\n\n\n\n\n\n\n' | \
        su -s /bin/sh pmbuild -c \
        "export HOME=/work/pmbootstrap; export CCACHE_DIR=/ccache; pmbootstrap init"
    echo "✓ pmbootstrap init 完成"
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
