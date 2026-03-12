#!/bin/bash
# Log file for debugging
source shell/custom-packages.sh
source shell/switch_repository.sh
echo "第三方软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE
echo "编译固件大小为: $PROFILE MB"
echo "Include Docker: $INCLUDE_DOCKER"

if [ -z "$CUSTOM_PACKAGES" ]; then
  echo "⚪️ 未选择任何额外软件包"
else
  echo "✅ 使用原仓库/本仓库可用的软件包配置"
fi

# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建固件..."

# ============= 默认内置插件（按 192.168.31.1 当前在用配置收敛）==============
PACKAGES=""
PACKAGES="$PACKAGES curl openssh-sftp-server qemu-ga"
PACKAGES="$PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn luci-i18n-package-manager-zh-cn luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn luci-app-samba4 luci-i18n-samba4-zh-cn"
# Passwall 由原创作者 release 提供最新 ipk（23.05-24.10 通用包）
PACKAGES="$PACKAGES xray-core hysteria luci-app-passwall luci-i18n-passwall-zh-cn"
PACKAGES="$PACKAGES smartdns luci-app-smartdns luci-i18n-smartdns-zh-cn"
PACKAGES="$PACKAGES luci-app-adguardhome luci-app-tailscale luci-i18n-tailscale-zh-cn"
PACKAGES="$PACKAGES luci-app-netwizard luci-i18n-netwizard-zh-cn"
PACKAGES="$PACKAGES luci-app-partexp luci-i18n-partexp-zh-cn"
PACKAGES="$PACKAGES luci-app-watchdog luci-i18n-watchdog-zh-cn"
PACKAGES="$PACKAGES luci-app-bandix luci-i18n-bandix-zh-cn"
PACKAGES="$PACKAGES luci-app-advancedplus luci-i18n-advancedplus-zh-cn"
PACKAGES="$PACKAGES webdav2 luci-app-unishare"
PACKAGES="$PACKAGES luci-app-turboacc"
# 不默认集成：openclash / homeproxy / ddns-go / lucky / docker
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# 判断是否需要编译 Docker 插件
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    echo "Adding package: luci-i18n-dockerman-zh-cn"
fi

# 若构建 passwall，则优先使用原创作者 release 中适配 23.05-24.10 的最新版 ipk
if echo "$PACKAGES" | grep -q "luci-app-passwall"; then
    echo "✅ 已选择 luci-app-passwall，下载原创作者最新版 ipk"
    mkdir -p packages
    PASSWALL_VER="26.3.6"
    PASSWALL_BASE="https://github.com/Openwrt-Passwall/openwrt-passwall/releases/download/${PASSWALL_VER}-1"
    wget -q "${PASSWALL_BASE}/23.05-24.10_luci-app-passwall_${PASSWALL_VER}-r1_all.ipk" -O packages/luci-app-passwall_${PASSWALL_VER}-r1_all.ipk
    wget -q "${PASSWALL_BASE}/23.05-24.10_luci-i18n-passwall-zh-cn_${PASSWALL_VER}_all.ipk" -O packages/luci-i18n-passwall-zh-cn_${PASSWALL_VER}_all.ipk
fi

# 若构建openclash 则添加内核
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash，添加 openclash core"
    mkdir -p files/etc/openclash/core
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-amd64.tar.gz"
    wget -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
else
    echo "⚪️ 未选择 luci-app-openclash"
fi

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

make image PROFILE="generic" PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$PROFILE

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
