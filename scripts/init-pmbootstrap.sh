#!/bin/sh
# pmbootstrap 初始化脚本（sh 兼容，适配 docker-postmarketos 容器）
# 目标设备：google-kukui (Chromebook Crane, MT8183, aarch64)
# 使用 scripts/pmbootstrap.cfg 直接部署配置，不需要交互式 pmbootstrap init
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
echo "=== 部署配置文件并初始化 pmaports ==="

# ── 部署 pmbootstrap.cfg（替代交互式 pmbootstrap init）────────────────────
# HOME=/work/pmbootstrap → 配置路径：/work/pmbootstrap/.config/pmbootstrap.cfg
su -s /bin/sh pmbuild -c "
export HOME=/work/pmbootstrap
export CCACHE_DIR=/ccache
mkdir -p \$HOME/.config

# 如果配置文件已存在且不是从脚本部署的，保留现有配置
if [ ! -f \$HOME/.config/pmbootstrap.cfg ]; then
    cp /scripts/pmbootstrap.cfg \$HOME/.config/pmbootstrap.cfg
    echo '✓ pmbootstrap.cfg 已部署'
else
    echo '✓ pmbootstrap.cfg 已存在，跳过'
fi

# 创建 work 目录
WORK_DIR=\$(pmbootstrap config work 2>/dev/null || echo /work/pmbootstrap/.local/var/pmbootstrap)
mkdir -p \"\$WORK_DIR\"

# ── 拉取 pmaports（若未克隆）──────────────────────────────────────────────
APORTS_DIR=\$(pmbootstrap config aports 2>/dev/null || echo \"\$WORK_DIR/cache_git/pmaports\")
if [ ! -d \"\$APORTS_DIR/.git\" ]; then
    echo '正在克隆 pmaports...'
    pmbootstrap pull-aports
    echo '✓ pmaports 已克隆'
else
    echo '✓ pmaports 已存在，跳过克隆'
fi
" 2>&1

echo ""
echo "=== 初始化完成，当前配置 ==="
su -s /bin/sh pmbuild -c "export HOME=/work/pmbootstrap; pmbootstrap config" 2>&1 || true
echo ""
su -s /bin/sh pmbuild -c "export HOME=/work/pmbootstrap; pmbootstrap config aports" 2>&1 | xargs -I{} echo "pmaports: {}" || true
