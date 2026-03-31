#!/bin/sh
# 在 docker-postmarketos 容器内安装 pmbootstrap
# 镜像基于 postmarketOS edge (Alpine)，无 bash，以 root 运行
set -eu

if command -v pmbootstrap >/dev/null 2>&1; then
  echo "pmbootstrap already installed: $(pmbootstrap --version)"
  touch /tmp/bootstrap-done
  exit 0
fi

echo "Installing pmbootstrap via apk..."

# 更新 apk 源（失败时切换到 http）
if ! apk update --cache-dir /cache/apk 2>/dev/null; then
  cp /etc/apk/repositories /etc/apk/repositories.bak || true
  sed -i 's|https://dl-cdn.alpinelinux.org|http://dl-cdn.alpinelinux.org|g' /etc/apk/repositories
  apk update --cache-dir /cache/apk
fi

# 使用 /cache/apk 作为包缓存目录（由 docker-compose 挂载为持久卷，CI 缓存可命中）
apk add --cache-dir /cache/apk pmbootstrap bash git ccache build-base openssh-client rsync curl sudo

echo "Done: $(pmbootstrap --version)"

# 写入完成标记（CI 轮询用，避免 sleep 浪费）
touch /tmp/bootstrap-done
