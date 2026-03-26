#!/bin/sh
# pmbootstrap 初始化脚本（sh 兼容，适配 docker-postmarketos 容器）
# 目标设备：google-kukui (Chromebook Crane, MT8183, aarch64)
# 容器以 root 运行，pmbootstrap 3.x 禁止 root → 用 su -s /bin/sh pmbuild 运行
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
chown -R pmbuild:pmbuild /work/pmbootstrap /ccache 2>/dev/null || true

echo "=== pmbootstrap $(pmbootstrap --version) ==="
echo "=== 初始化 google-kukui / edge ==="

# 以 pmbuild 用户运行 pmbootstrap init（管道方式，无需 TTY）
# pmbootstrap 3.9 init 交互顺序：
#   1. work path      → 默认回车
#   2. pmaports path  → 默认回车
#   3. channel        → 默认回车（默认 edge）
#   4. vendor         → google
#   5. device         → kukui
#   6. kernel         → 默认回车
#   7. username       → 默认回车
#   8+. providers     → 默认回车 × N
su -s /bin/sh pmbuild -c "
export CCACHE_DIR=/ccache
export HOME=/work/pmbootstrap
mkdir -p \$HOME
printf '\n\n\ngoogle\nkukui\n\n\n\n\n\n\n\n\n\n\n\n\n\n' | pmbootstrap init
" 2>&1

echo ""
echo "=== 初始化完成，当前配置 ==="
su -s /bin/sh pmbuild -c "export HOME=/work/pmbootstrap; pmbootstrap config" 2>&1 || true
