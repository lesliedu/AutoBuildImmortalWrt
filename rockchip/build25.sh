#!/bin/bash
# Log file for debugging
source shell/apk-custom-packages.sh
echo "第三方APK软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE
# yml 传入的路由器型号 PROFILE
echo "Building for profile: $PROFILE"
# yml 传入的固件大小 ROOTFS_PARTSIZE
KERNEL_PARTSIZE=${KERNEL_PARTSIZE:-256}
echo "Building for ROOTFS_PARTSIZE: $ROOTFS_PARTSIZE, KERNEL_PARTSIZE: $KERNEL_PARTSIZE"
echo "Include Docker: $INCLUDE_DOCKER"

echo "Create pppoe-settings"
mkdir -p /home/build/immortalwrt/files/etc/config

# 创建pppoe配置文件 yml传入环境变量ENABLE_PPPOE等 写入配置文件 供99-custom.sh读取
cat << 'SETTINGS_EOF' > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
SETTINGS_EOF

# ============= 始终同步第三方插件库 (ARM64) =============
echo "🔄 正在同步第三方软件仓库 Cloning run file repo..."
rm -rf /tmp/store-apk-repo /home/build/immortalwrt/extra-packages /home/build/immortalwrt/packages
mkdir -p /home/build/immortalwrt/extra-packages /home/build/immortalwrt/packages
git clone --depth=1 https://github.com/wukongdaily/apk.git /tmp/store-apk-repo
cp -r /tmp/store-apk-repo/run/arm64/* /home/build/immortalwrt/extra-packages/
sh shell/apk-prepare-packages.sh
ls -lah /home/build/immortalwrt/packages/ || true

echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建 25.12 Rockchip 固件..."

# ============= 基础核心与界面工具 (带全套中文语言包) =============
PACKAGES=""
PACKAGES="$PACKAGES curl openssh-sftp-server unzip sshpass ethtool"
PACKAGES="$PACKAGES kmod-nft-tproxy kmod-nft-socket"
PACKAGES="$PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-app-ttyd luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES luci-app-diskman luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-app-samba4 luci-i18n-samba4-zh-cn"
PACKAGES="$PACKAGES filebrowser luci-app-filebrowser-go luci-i18n-filebrowser-go-zh-cn"

# ============= Passwall 代理运行栈与核心依赖 (带中文) =============
PACKAGES="$PACKAGES xray-core hysteria sing-box chinadns-ng haproxy shellsync geoview dns2socks dns2tcp ipt2socks v2ray-plugin"
PACKAGES="$PACKAGES shadowsocks-rust-sslocal shadowsocks-rust-ssserver simple-obfs-client"
PACKAGES="$PACKAGES luci-app-passwall luci-i18n-passwall-zh-cn"
PACKAGES="$PACKAGES smartdns luci-app-smartdns luci-i18n-smartdns-zh-cn"

# ============= 常用服务与系统扩展 (全套官方中文) =============
PACKAGES="$PACKAGES luci-app-ddns-go luci-i18n-ddns-go-zh-cn ddns-go"
PACKAGES="$PACKAGES watchdog luci-app-watchdog luci-i18n-watchdog-zh-cn"
PACKAGES="$PACKAGES zerotier luci-app-zerotier luci-i18n-zerotier-zh-cn"
PACKAGES="$PACKAGES luci-app-tailscale-community luci-i18n-tailscale-community-zh-cn tailscale"
PACKAGES="$PACKAGES luci-app-arpbind luci-i18n-arpbind-zh-cn"
PACKAGES="$PACKAGES bandix luci-app-bandix luci-i18n-bandix-zh-cn"
PACKAGES="$PACKAGES luci-app-netdata luci-i18n-netdata-zh-cn netdata"
PACKAGES="$PACKAGES luci-app-ramfree luci-i18n-ramfree-zh-cn"
PACKAGES="$PACKAGES luci-app-statistics luci-i18n-statistics-zh-cn"
PACKAGES="$PACKAGES luci-app-upnp luci-i18n-upnp-zh-cn miniupnpd-nftables"
PACKAGES="$PACKAGES luci-app-vlmcsd luci-i18n-vlmcsd-zh-cn vlmcsd"
PACKAGES="$PACKAGES luci-app-vsftpd luci-i18n-vsftpd-zh-cn vsftpd"
PACKAGES="$PACKAGES luci-app-wol luci-i18n-wol-zh-cn"
PACKAGES="$PACKAGES mosdns"

# ============= Rockchip / ARM64 硬件特性与无线支持 =============
PACKAGES="$PACKAGES luci-app-cpufreq luci-i18n-cpufreq-zh-cn"
PACKAGES="$PACKAGES luci-app-partexp luci-i18n-partexp-zh-cn"
PACKAGES="$PACKAGES wpad-openssl iwinfo"
PACKAGES="$PACKAGES kmod-mt7921e kmod-mt7921-firmware kmod-rtw88-8822ce"

PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-app-dockerman luci-i18n-dockerman-zh-cn"
fi

# sirpdboy 安全看门狗 (Web/SSH 防爆破守护) 自动拉取最新版 ARM64 apk
if echo "$PACKAGES" | grep -q "luci-app-watchdog"; then
    echo "✅ 已选择 luci-app-watchdog，自动拉取 sirpdboy 最新版安全看门狗 apk (ARM64)"
    mkdir -p packages /tmp/watchdog_dl
    WATCHDOG_URL=$(curl -sL "https://api.github.com/repos/sirpdboy/luci-app-watchdog/releases/latest" | grep "browser_download_url" | grep "SNAPSHOT-aarch64_generic.tar.gz" | head -n 1 | cut -d '"' -f 4)
    if [ -n "$WATCHDOG_URL" ]; then
        wget -qO /tmp/watchdog_dl/watchdog.tar.gz "$WATCHDOG_URL"
        tar -xzf /tmp/watchdog_dl/watchdog.tar.gz -C /tmp/watchdog_dl
        cp -v /tmp/watchdog_dl/packages_ci/*.apk packages/
        rm -rf /tmp/watchdog_dl
    fi
fi

# Passwall 自动拉取原创作者发布的最新版 25.12+ apk，并规范文件名去除 25.12+_ 前缀
if echo "$PACKAGES" | grep -q "luci-app-passwall"; then
    echo "✅ 已选择 luci-app-passwall，自动拉取原创作者最新版 25.12+ apk"
    mkdir -p packages
    PASSWALL_URLS=$(curl -sL "https://api.github.com/repos/Openwrt-Passwall/openwrt-passwall/releases/latest" | grep -o "https://[^\"]*25.12[^\"]*\.apk")
    for url in $PASSWALL_URLS; do
        raw_name=$(basename "$url")
        clean_name=$(echo "$raw_name" | sed -E 's/^25\.12(%2B|\+)_//')
        echo "  - 下载 Passwall apk: $clean_name"
        wget -qO "packages/$clean_name" "$url"
    done
fi

if echo "$PACKAGES" | grep -q "tailscale"; then
    echo "✅ 正在获取最新版 Tailscale 二进制 (ARM64)"
    mkdir -p files/usr/sbin
    TAILSCALE_URL="https://pkgs.tailscale.com/stable/tailscale_latest_arm64.tgz"
    wget -qO /tmp/tailscale_latest_arm64.tgz "$TAILSCALE_URL"
    tar xzf /tmp/tailscale_latest_arm64.tgz -C /tmp
    cp /tmp/tailscale_*_arm64/tailscale files/usr/sbin/tailscale
    cp /tmp/tailscale_*_arm64/tailscaled files/usr/sbin/tailscaled
    chmod +x files/usr/sbin/tailscale files/usr/sbin/tailscaled
    rm -rf /tmp/tailscale_*_arm64 /tmp/tailscale_latest_arm64.tgz
fi

echo "✅ 正在获取最新的 GeoIP / GeoSite 数据文件"
mkdir -p files/usr/share/v2ray
wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/usr/share/v2ray/geoip.dat
wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/usr/share/v2ray/geosite.dat

echo "✅ 正在获取 Passwall 核心组件的最新二进制文件 (ARM64)"
mkdir -p files/usr/bin

GEOVIEW_URL=$(curl -sL https://api.github.com/repos/snowie2000/geoview/releases/latest | grep "browser_download_url" | grep "geoview-linux-arm64" | head -n 1 | cut -d '"' -f 4)
if [ -n "$GEOVIEW_URL" ]; then
    wget -qO files/usr/bin/geoview "$GEOVIEW_URL"
fi

XRAY_URL=$(curl -sL https://api.github.com/repos/XTLS/Xray-core/releases | grep "browser_download_url" | grep "Xray-linux-arm64-v8a.zip" | head -n 1 | cut -d '"' -f 4)
if [ -n "$XRAY_URL" ]; then
    wget -qO /tmp/xray.zip "$XRAY_URL"
    unzip -qo /tmp/xray.zip xray -d files/usr/bin/
    rm -f /tmp/xray.zip
fi

SINGBOX_URL=$(curl -sL https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep "browser_download_url" | grep "linux-arm64-musl.tar.gz" | head -n 1 | cut -d '"' -f 4)
if [ -n "$SINGBOX_URL" ]; then
    wget -qO /tmp/sing-box.tar.gz "$SINGBOX_URL"
    tar -xzf /tmp/sing-box.tar.gz -C /tmp
    cp /tmp/sing-box-*/sing-box files/usr/bin/
    rm -rf /tmp/sing-box*
fi

HYSTERIA_URL=$(curl -sL https://api.github.com/repos/apernet/hysteria/releases/latest | grep "browser_download_url" | grep "hysteria-linux-arm64" | head -n 1 | cut -d '"' -f 4)
if [ -n "$HYSTERIA_URL" ]; then
    wget -qO files/usr/bin/hysteria "$HYSTERIA_URL"
fi

CHINADNS_URL=$(curl -sL https://api.github.com/repos/zfl9/chinadns-ng/releases/latest | grep "browser_download_url" | grep -E 'chinadns-ng%2Bwolfssl%40aarch64-linux-musl%40generic%2Bv8a%40' | head -n 1 | cut -d '"' -f 4)
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

make image PROFILE="$PROFILE" PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE KERNEL_PARTSIZE=$KERNEL_PARTSIZE

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
