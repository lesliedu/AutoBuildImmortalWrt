#!/bin/bash
# Log file for debugging
source shell/custom-packages.sh
source shell/switch_repository.sh
echo "第三方软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE
echo "编译固件大小为: $PROFILE MB"
echo "Include Docker: $INCLUDE_DOCKER"

echo "Create pppoe-settings"
mkdir -p /home/build/immortalwrt/files/etc/config

cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

echo "cat pppoe-settings"
cat /home/build/immortalwrt/files/etc/config/pppoe-settings

# 对齐 192.168.31.1 常用版：这批插件默认补回，统一走第三方包同步链
COMMON_31_PACKAGES="luci-app-adguardhome adguardhome luci-app-tailscale luci-i18n-tailscale-zh-cn tailscale luci-app-netwizard luci-i18n-netwizard-zh-cn luci-app-partexp luci-i18n-partexp-zh-cn luci-app-watchdog luci-i18n-watchdog-zh-cn watchdog luci-app-advancedplus luci-i18n-advancedplus-zh-cn webdav2 luci-app-unishare unishare luci-app-turboacc luci-app-ddns luci-i18n-ddns-zh-cn ddns-scripts ddns-scripts-services ddns-scripts-aliyun mosdns luci-app-arpbind luci-i18n-arpbind-zh-cn luci-app-netdata luci-i18n-netdata-zh-cn netdata luci-app-ramfree luci-i18n-ramfree-zh-cn luci-app-statistics luci-i18n-statistics-zh-cn luci-app-upnp luci-i18n-upnp-zh-cn miniupnpd-nftables luci-app-vlmcsd luci-i18n-vlmcsd-zh-cn vlmcsd luci-app-vsftpd luci-i18n-vsftpd-zh-cn vsftpd luci-app-wol luci-i18n-wol-zh-cn"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES $COMMON_31_PACKAGES"

# 仅在确实需要第三方扩展时同步 wukong store；Passwall / Bandix 不走这里
if [ -n "$CUSTOM_PACKAGES" ]; then
  echo "🔄 正在同步第三方软件仓库 wukongdaily/store ..."
  rm -rf /tmp/store-run-repo /home/build/immortalwrt/extra-packages /home/build/immortalwrt/packages
  mkdir -p /home/build/immortalwrt/extra-packages /home/build/immortalwrt/packages
  git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo
  cp -r /tmp/store-run-repo/run/x86/* /home/build/immortalwrt/extra-packages/
  sh shell/prepare-packages.sh
  ls -lah /home/build/immortalwrt/packages/ || true
else
  echo "⚪️ 未选择额外第三方软件包，不同步 wukong store"
fi

# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建固件..."

# ============= 默认内置插件（回归成功版骨架 + 必要修复）==============
PACKAGES=""
PACKAGES="$PACKAGES curl openssh-sftp-server qemu-ga unzip kmod-nft-tproxy kmod-nft-socket sshpass"
PACKAGES="$PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn luci-i18n-package-manager-zh-cn luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn luci-app-samba4 luci-i18n-samba4-zh-cn"
# Passwall / SSR Plus 运行栈
PACKAGES="$PACKAGES xray-core hysteria sing-box chinadns-ng haproxy shellsync geoview dns2socks dns2tcp ipt2socks v2ray-plugin"
PACKAGES="$PACKAGES shadowsocks-rust-sslocal shadowsocks-rust-ssserver shadowsocksr-libev-ssr-check shadowsocksr-libev-ssr-local shadowsocksr-libev-ssr-redir shadowsocksr-libev-ssr-server simple-obfs-client"
PACKAGES="$PACKAGES luci-app-passwall luci-i18n-passwall-zh-cn luci-app-ssr-plus"
PACKAGES="$PACKAGES smartdns luci-app-smartdns luci-i18n-smartdns-zh-cn"
PACKAGES="$PACKAGES zerotier luci-app-zerotier luci-i18n-zerotier-zh-cn"
PACKAGES="$PACKAGES luci-app-bandix luci-i18n-bandix-zh-cn"
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# 判断是否需要编译 Docker 插件
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    echo "Adding package: luci-i18n-dockerman-zh-cn"
fi

# Passwall 由原创作者 release 提供最新 ipk（23.05-24.10 通用包）
if echo "$PACKAGES" | grep -q "luci-app-passwall"; then
    echo "✅ 已选择 luci-app-passwall，自动拉取原创作者最新版 ipk"
    mkdir -p packages
    wget -qO- "https://api.github.com/repos/Openwrt-Passwall/openwrt-passwall/releases/latest" | grep -o "https://.*\.ipk" | grep "23.05-24.10" | xargs -n 1 wget -q -P packages/
fi

if echo "$PACKAGES" | grep -q "luci-app-bandix"; then
    echo "✅ 已选择 luci-app-bandix，自动拉取原创作者完整依赖链 ipk"
    mkdir -p packages
    wget -qO- "https://api.github.com/repos/timsaya/luci-app-bandix/releases/latest" | grep -o "https://.*\.ipk" | grep -E "luci-app-bandix_|luci-i18n-bandix-zh-cn_" | xargs -n 1 wget -q -P packages/
    wget -qO- "https://api.github.com/repos/timsaya/openwrt-bandix/releases/latest" | grep -o "https://.*x86_64\.ipk" | xargs -n 1 wget -q -P packages/
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
# 获取最新版 Tailscale
if echo "$PACKAGES" | grep -q "tailscale"; then
    echo "✅ 正在获取最新版 Tailscale"
    mkdir -p files/usr/sbin
    TAILSCALE_URL="https://pkgs.tailscale.com/stable/tailscale_latest_amd64.tgz"
    wget -qO /tmp/tailscale_latest_amd64.tgz $TAILSCALE_URL
    tar xzf /tmp/tailscale_latest_amd64.tgz -C /tmp
    cp /tmp/tailscale_*_amd64/tailscale files/usr/sbin/tailscale
    cp /tmp/tailscale_*_amd64/tailscaled files/usr/sbin/tailscaled
    chmod +x files/usr/sbin/tailscale files/usr/sbin/tailscaled
    rm -rf /tmp/tailscale_*_amd64 /tmp/tailscale_latest_amd64.tgz
fi

# 获取最新的 GeoIP / GeoSite 数据文件供 Passwall / SSR Plus 使用
echo "✅ 正在获取最新的 GeoIP / GeoSite 数据文件"
mkdir -p files/usr/share/v2ray
wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/usr/share/v2ray/geoip.dat
wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/usr/share/v2ray/geosite.dat

# 获取 Passwall 核心组件的最新二进制文件 (Geoview, Xray, Sing-box, Hysteria, ChinaDNS-NG)
echo "✅ 正在获取 Passwall 核心组件的最新二进制文件"
mkdir -p files/usr/bin

# 0. Geoview
GEOVIEW_URL=$(curl -s https://api.github.com/repos/snowie2000/geoview/releases/latest | grep "browser_download_url" | grep "geoview-linux-amd64" | head -n 1 | cut -d '"' -f 4)
if [ -n "$GEOVIEW_URL" ]; then
    echo "  - 下载 Geoview..."
    wget -qO files/usr/bin/geoview "$GEOVIEW_URL"
fi

# 1. Xray-core
XRAY_URL=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | grep "browser_download_url" | grep "Xray-linux-64.zip" | head -n 1 | cut -d '"' -f 4)
if [ -n "$XRAY_URL" ]; then
    echo "  - 下载 Xray-core..."
    wget -qO /tmp/xray.zip "$XRAY_URL"
    unzip -qo /tmp/xray.zip xray -d files/usr/bin/
    rm -f /tmp/xray.zip
fi

# 2. Sing-box
SINGBOX_URL=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep "browser_download_url" | grep "linux-amd64-musl.tar.gz" | head -n 1 | cut -d '"' -f 4)
if [ -n "$SINGBOX_URL" ]; then
    echo "  - 下载 Sing-box..."
    wget -qO /tmp/sing-box.tar.gz "$SINGBOX_URL"
    tar -xzf /tmp/sing-box.tar.gz -C /tmp
    cp /tmp/sing-box-*/sing-box files/usr/bin/
    rm -rf /tmp/sing-box*
fi

# 3. Hysteria
HYSTERIA_URL=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep "browser_download_url" | grep "hysteria-linux-amd64" | head -n 1 | cut -d '"' -f 4)
if [ -n "$HYSTERIA_URL" ]; then
    echo "  - 下载 Hysteria..."
    wget -qO files/usr/bin/hysteria "$HYSTERIA_URL"
fi

# 4. ChinaDNS-NG
CHINADNS_URL=$(curl -s https://api.github.com/repos/zfl9/chinadns-ng/releases/latest | grep "browser_download_url" | grep -E 'chinadns-ng%2Bwolfssl%40x86_64-linux-musl%40x86_64%40' | head -n 1 | cut -d '"' -f 4)
if [ -n "$CHINADNS_URL" ]; then
    echo "  - 下载 ChinaDNS-NG..."
    wget -qO files/usr/bin/chinadns-ng "$CHINADNS_URL"
fi

chmod +x files/usr/bin/geoview files/usr/bin/xray files/usr/bin/sing-box files/usr/bin/hysteria files/usr/bin/chinadns-ng 2>/dev/null || true

# 创建对 rust 版 shadowsocks 的软连接，兼容 PassWall 调用要求
echo "✅ 正在创建 ss-local 等软链接兼容..."
mkdir -p files/usr/bin
ln -sf sslocal files/usr/bin/ss-local
ln -sf sslocal files/usr/bin/ss-redir
ln -sf ssserver files/usr/bin/ss-server

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

make image PROFILE="generic" PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$PROFILE

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
