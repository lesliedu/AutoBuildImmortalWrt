#!/bin/bash
# Log file for debugging
source shell/apk-custom-packages.sh
echo "第三方apk软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE
echo "编译固件大小为: $PROFILE MB"
echo "Include Docker: $INCLUDE_DOCKER"

echo "Create pppoe-settings"
mkdir -p /home/build/immortalwrt/files/etc/config

cat << 'SETTINGS_EOF' > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
SETTINGS_EOF

# ============= 始终同步第三方插件库 =============
echo "🔄 正在同步第三方软件仓库 Cloning run file repo..."
rm -rf /tmp/store-apk-repo /home/build/immortalwrt/extra-packages /home/build/immortalwrt/packages
mkdir -p /home/build/immortalwrt/extra-packages /home/build/immortalwrt/packages
git clone --depth=1 https://github.com/wukongdaily/apk.git /tmp/store-apk-repo
cp -r /tmp/store-apk-repo/run/x86/* /home/build/immortalwrt/extra-packages/
sh shell/apk-prepare-packages.sh
ls -lah /home/build/immortalwrt/packages/ || true

echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建 25.12 固件..."

# ============= 基础核心与系统工具 (100% 经过 25.12 官方源验证) =============
PACKAGES=""
PACKAGES="$PACKAGES curl openssh-sftp-server qemu-ga unzip sshpass ethtool"
PACKAGES="$PACKAGES kmod-nft-tproxy kmod-nft-socket"
PACKAGES="$PACKAGES luci-theme-argon luci-app-argon-config"
PACKAGES="$PACKAGES luci-app-ttyd luci-app-diskman luci-app-samba4 luci-app-filemanager"

# ============= Passwall 代理运行栈与核心依赖 =============
PACKAGES="$PACKAGES xray-core hysteria sing-box chinadns-ng haproxy shellsync geoview dns2socks dns2tcp ipt2socks v2ray-plugin"
PACKAGES="$PACKAGES shadowsocks-rust-sslocal shadowsocks-rust-ssserver simple-obfs-client"
PACKAGES="$PACKAGES luci-app-passwall"
PACKAGES="$PACKAGES smartdns luci-app-smartdns"

# ============= 常用服务与系统扩展 =============
PACKAGES="$PACKAGES luci-app-ddns-go ddns-go"
PACKAGES="$PACKAGES luci-app-watchcat watchcat"
PACKAGES="$PACKAGES zerotier luci-app-zerotier"
PACKAGES="$PACKAGES luci-app-tailscale-community tailscale"
PACKAGES="$PACKAGES luci-app-arpbind"
PACKAGES="$PACKAGES luci-app-netdata netdata"
PACKAGES="$PACKAGES luci-app-ramfree"
PACKAGES="$PACKAGES luci-app-statistics"
PACKAGES="$PACKAGES luci-app-upnp miniupnpd-nftables"
PACKAGES="$PACKAGES luci-app-vlmcsd vlmcsd"
PACKAGES="$PACKAGES luci-app-vsftpd vsftpd"
PACKAGES="$PACKAGES luci-app-wol"
PACKAGES="$PACKAGES mosdns"

PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-app-dockerman"
fi

# Passwall 自动拉取原创作者发布的最新版 25.12+ apk，并规范文件名去除 25.12+_ 前缀
if echo "$PACKAGES" | grep -q "luci-app-passwall"; then
    echo "✅ 已选择 luci-app-passwall，自动拉取原创作者最新版 25.12+ apk"
    mkdir -p packages
    PASSWALL_URLS=$(curl -s "https://api.github.com/repos/Openwrt-Passwall/openwrt-passwall/releases/latest" | grep -o "https://[^\"]*25.12[^\"]*\.apk")
    for url in $PASSWALL_URLS; do
        raw_name=$(basename "$url")
        clean_name=$(echo "$raw_name" | sed -E 's/^25\.12(%2B|\+)_//')
        echo "  - 下载 Passwall apk: $clean_name"
        wget -qO "packages/$clean_name" "$url"
    done
fi

if echo "$PACKAGES" | grep -q "tailscale"; then
    echo "✅ 正在获取最新版 Tailscale 二进制"
    mkdir -p files/usr/sbin
    TAILSCALE_URL="https://pkgs.tailscale.com/stable/tailscale_latest_amd64.tgz"
    wget -qO /tmp/tailscale_latest_amd64.tgz $TAILSCALE_URL
    tar xzf /tmp/tailscale_latest_amd64.tgz -C /tmp
    cp /tmp/tailscale_*_amd64/tailscale files/usr/sbin/tailscale
    cp /tmp/tailscale_*_amd64/tailscaled files/usr/sbin/tailscaled
    chmod +x files/usr/sbin/tailscale files/usr/sbin/tailscaled
    rm -rf /tmp/tailscale_*_amd64 /tmp/tailscale_latest_amd64.tgz
fi

echo "✅ 正在获取最新的 GeoIP / GeoSite 数据文件"
mkdir -p files/usr/share/v2ray
wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/usr/share/v2ray/geoip.dat
wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/usr/share/v2ray/geosite.dat

echo "✅ 正在获取 Passwall 核心组件的最新二进制文件"
mkdir -p files/usr/bin

GEOVIEW_URL=$(curl -s https://api.github.com/repos/snowie2000/geoview/releases/latest | grep "browser_download_url" | grep "geoview-linux-amd64" | head -n 1 | cut -d '"' -f 4)
if [ -n "$GEOVIEW_URL" ]; then
    wget -qO files/usr/bin/geoview "$GEOVIEW_URL"
fi

XRAY_URL=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | grep "browser_download_url" | grep "Xray-linux-64.zip" | head -n 1 | cut -d '"' -f 4)
if [ -n "$XRAY_URL" ]; then
    wget -qO /tmp/xray.zip "$XRAY_URL"
    unzip -qo /tmp/xray.zip xray -d files/usr/bin/
    rm -f /tmp/xray.zip
fi

SINGBOX_URL=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep "browser_download_url" | grep "linux-amd64-musl.tar.gz" | head -n 1 | cut -d '"' -f 4)
if [ -n "$SINGBOX_URL" ]; then
    wget -qO /tmp/sing-box.tar.gz "$SINGBOX_URL"
    tar -xzf /tmp/sing-box.tar.gz -C /tmp
    cp /tmp/sing-box-*/sing-box files/usr/bin/
    rm -rf /tmp/sing-box*
fi

HYSTERIA_URL=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep "browser_download_url" | grep "hysteria-linux-amd64" | head -n 1 | cut -d '"' -f 4)
if [ -n "$HYSTERIA_URL" ]; then
    wget -qO files/usr/bin/hysteria "$HYSTERIA_URL"
fi

CHINADNS_URL=$(curl -s https://api.github.com/repos/zfl9/chinadns-ng/releases/latest | grep "browser_download_url" | grep -E 'chinadns-ng%2Bwolfssl%40x86_64-linux-musl%40x86_64%40' | head -n 1 | cut -d '"' -f 4)
if [ -n "$CHINADNS_URL" ]; then
    wget -qO files/usr/bin/chinadns-ng "$CHINADNS_URL"
fi

chmod +x files/usr/bin/geoview files/usr/bin/xray files/usr/bin/sing-box files/usr/bin/hysteria files/usr/bin/chinadns-ng 2>/dev/null || true

echo "✅ 正在创建 ss-local 等软链接兼容..."
mkdir -p files/usr/bin
ln -sf sslocal files/usr/bin/ss-local
ln -sf sslocal files/usr/bin/ss-redir
ln -sf ssserver files/usr/bin/ss-server

echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

make image PROFILE="generic" PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$PROFILE

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
