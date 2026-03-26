#!/bin/sh
# 在 docker-postmarketos 容器内安装 pmbootstrap
# 镜像基于 postmarketOS edge (Alpine)，无 bash，以 root 运行
set -eu

if command -v pmbootstrap >/dev/null 2>&1; then
  echo "pmbootstrap already installed: $(pmbootstrap --version)"
  exit 0
fi

echo "Installing pmbootstrap via apk..."

# 更新 apk 源（失败时切换到 http）
if ! apk update 2>/dev/null; then
  cp /etc/apk/repositories /etc/apk/repositories.bak || true
  sed -i 's|https://dl-cdn.alpinelinux.org|http://dl-cdn.alpinelinux.org|g' /etc/apk/repositories
  apk update
fi

# 直接从 Alpine edge 仓库安装（postmarketos 镜像已配置 edge/community，有 pmbootstrap 3.9.0）
apk add --no-cache pmbootstrap bash git ccache build-base openssh-client rsync curl sudo

echo "Done: $(pmbootstrap --version)"

# ── 安装 tar wrapper（修复 Docker overlay2 上的 "Directory renamed" 问题） ──
# native chroot 可能尚未创建，故用 inotifywait 或轮询均复杂；
# 改为：创建一个安装辅助脚本，由 patch-kernel-otbr.sh 在构建前调用。
# 同时，若 chroot 已存在则立即安装。
install_tar_wrapper() {
    chroot_tar="/work/pmbootstrap/chroot_native/usr/bin/tar"
    if [ -f "${chroot_tar}" ] && [ ! -f "${chroot_tar}.real" ]; then
        cp "${chroot_tar}" "${chroot_tar}.real"
        cp /scripts/tar-wrapper.sh "${chroot_tar}"
        chmod +x "${chroot_tar}"
        echo "tar wrapper 已安装到 native chroot"
    fi
}
install_tar_wrapper
