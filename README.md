# pmos-docker — google-kukui OTBR 内核构建环境

基于官方 `docker-postmarketos:edge` 镜像，为 google-kukui (Chromebook Crane, MT8183, aarch64)
构建支持 OTBR / OpenThread 多播路由的 postmarketOS 内核。

## 快速启动

```bash
cd ~/pmos-docker
/usr/local/bin/docker compose up -d
/usr/local/bin/docker exec -it pmos-builder sh
```

## 完整构建流程（容器内逐步执行，不要粘贴为一个代码块）

```sh
# 1. 安装 pmbootstrap（容器重启后需重新运行，因为容器不持久化 apk 包）
sh /scripts/bootstrap-pmbootstrap.sh

# 2. 初始化（首次运行，或 work 目录被清空后）
sh /scripts/init-pmbootstrap.sh
# 设置 UI（plasma-mobile）
su -s /bin/sh pmbuild -c "export HOME=/work/pmbootstrap; pmbootstrap config ui plasma-mobile"

# 3. 添加 OTBR 内核配置（多播路由 + TUN + iptables + 容器网络）
sh /scripts/patch-kernel-otbr.sh

# 4. 构建内核（kukui 使用共享内核 linux-postmarketos-mediatek-mt81）
su -s /bin/sh pmbuild -c "export HOME=/work/pmbootstrap; pmbootstrap build linux-postmarketos-mediatek-mt81"

# 5. 刷入内核
su -s /bin/sh pmbuild -c "export HOME=/work/pmbootstrap; pmbootstrap flasher flash_kernel --device google-kukui"
```

> **注意**：容器重启后需要重新执行步骤 1（安装 pmbootstrap），
> `work/` 目录已挂载到宿主机，pmaports 和构建缓存不会丢失。

## OTBR 内核配置说明

`patch-kernel-otbr.sh` 会自动在 kukui 内核配置中启用：

| 类别 | 配置项 | 用途 |
|---|---|---|
| IPv6 多播路由 | `IPV6_MROUTE`, `IPV6_PIMSM_V2` | backbone multicast routing |
| IPv4 多播路由 | `IP_MROUTE`, `IP_PIMSM_V1/V2` | MLD proxy 回退路径 |
| TUN 设备 | `TUN` | wpan0/tun0 Thread 接口 |
| Netfilter | `NF_NAT`, `NFT_MASQ` 等 | NAT64 / iptables 防火墙 |
| USB Serial | `USB_SERIAL_CP210X`, `USB_ACM` | Thread NCP/RCP 串口通信 |

# 方案A：设备已运行pmOS（USB连接，172.16.42.1）
scp artifacts/linux-postmarketos-mediatek-mt81-6.18.13-r0.apk user@172.16.42.1:
ssh user@172.16.42.1 "sudo apk add --allow-untrusted ~/linux-postmarketos-mediatek-mt81-6.18.13-r0.apk && sudo reboot"

# 方案B：通过pmbootstrap flasher（Fastboot模式）
docker exec pmos-builder sh -c \
  'su -s /bin/sh pmbuild -c "export HOME=/work/pmbootstrap; pmbootstrap flasher flash_kernel"'
