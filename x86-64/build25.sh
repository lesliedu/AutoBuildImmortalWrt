#!/bin/bash
# Log file for debugging
# 目前支持少部分第三方软件apk 通过打开shell/apk-custom-packages.sh的注释来集成
source shell/apk-custom-packages.sh
echo "第三方apk软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE
echo "编译固件大小为: $PROFILE MB"
echo "Include Docker: $INCLUDE_DOCKER"

echo "Create pppoe-settings"
mkdir -p  /home/build/immortalwrt/files/etc/config

# 创建pppoe配置文件 yml传入环境变量ENABLE_PPPOE等 写入配置文件 供99-custom.sh读取
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

echo "cat pppoe-settings"
cat /home/build/immortalwrt/files/etc/config/pppoe-settings

if [ -z "$CUSTOM_PACKAGES" ]; then
  echo "⚪️ 未选择 任何第三方软件包"
else
  # ============= 同步第三方插件库==============
  # 同步第三方软件仓库run/apk
  echo "🔄 正在同步第三方软件仓库 Cloning run file repo..."
  git clone --depth=1 https://github.com/wukongdaily/apk.git /tmp/store-apk-repo

  # 拷贝 run/x86 下所有 run 文件和apk文件 到 extra-packages 目录
  mkdir -p /home/build/immortalwrt/extra-packages
  cp -r /tmp/store-apk-repo/run/x86/* /home/build/immortalwrt/extra-packages/

  echo "✅ Run files copied to extra-packages:"
  ls -lh /home/build/immortalwrt/extra-packages/*.run
  # 解压并拷贝apk到packages目录
  sh shell/apk-prepare-packages.sh
  ls -lah /home/build/immortalwrt/packages/
fi


# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建固件..."

# ============= 默认内置插件（全量移植自24.10 custom分支）==============
COMMON_31_PACKAGES="luci-app-adguardhome adguardhome luci-app-tailscale-community luci-i18n-tailscale-community-zh-cn tailscale luci-app-partexp luci-i18n-partexp-zh-cn luci-app-watchcat luci-i18n-watchcat-zh-cn watchcat luci-app-ddns luci-i18n-ddns-zh-cn ddns-scripts ddns-scripts-services mosdns luci-app-arpbind luci-i18n-arpbind-zh-cn luci-app-netdata luci-i18n-netdata-zh-cn netdata luci-app-ramfree luci-i18n-ramfree-zh-cn luci-app-statistics luci-i18n-statistics-zh-cn luci-app-upnp luci-i18n-upnp-zh-cn miniupnpd-nftables luci-app-vlmcsd luci-i18n-vlmcsd-zh-cn vlmcsd luci-app-vsftpd luci-i18n-vsftpd-zh-cn vsftpd luci-app-wol luci-i18n-wol-zh-cn"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES $COMMON_31_PACKAGES"

PACKAGES=""
PACKAGES="$PACKAGES curl openssh-sftp-server qemu-ga unzip sshpass"
PACKAGES="$PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn luci-i18n-package-manager-zh-cn luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn luci-app-samba4 luci-i18n-samba4-zh-cn"
PACKAGES="$PACKAGES xray-core hysteria sing-box chinadns-ng haproxy shellsync geoview dns2socks dns2tcp ipt2socks v2ray-plugin"
PACKAGES="$PACKAGES shadowsocks-rust-sslocal shadowsocks-rust-ssserver simple-obfs-client"
PACKAGES="$PACKAGES luci-app-passwall luci-i18n-passwall-zh-cn"
PACKAGES="$PACKAGES smartdns luci-app-smartdns luci-i18n-smartdns-zh-cn"
PACKAGES="$PACKAGES zerotier luci-app-zerotier luci-i18n-zerotier-zh-cn"
PACKAGES="$PACKAGES bandix luci-app-bandix luci-i18n-bandix-zh-cn"
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"


# 判断是否需要编译 Docker 插件
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    echo "Adding package: luci-i18n-dockerman-zh-cn"
fi

# 若构建openclash 则添加内核
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash，添加 openclash core"
    mkdir -p files/etc/openclash/core
    # Download clash_meta
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-amd64-v1.tar.gz"
    wget -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    # Download GeoIP and GeoSite
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

# 创建对 rust 版 shadowsocks 的软连接，兼容 PassWall 调用要求
echo "✅ 正在创建 ss-local 等软链接兼容..."
mkdir -p files/usr/bin
ln -sf sslocal files/usr/bin/ss-local
ln -sf sslocal files/usr/bin/ss-redir
ln -sf ssserver files/usr/bin/ss-server

# 获取最新的 Bandix apk
if echo "$PACKAGES" | grep -q "luci-app-bandix"; then
    echo "✅ 已选择 luci-app-bandix，从原作者下载最新 apk"
    mkdir -p packages
    BANDIX_LUCI_VER="v0.12.6"
    BANDIX_LUCI_BASE="https://github.com/timsaya/luci-app-bandix/releases/download/${BANDIX_LUCI_VER}"
    wget -q "${BANDIX_LUCI_BASE}/luci-app-bandix-0.12.6-r1_all.apk" -O packages/luci-app-bandix-0.12.6-r1_all.apk
    wget -q "${BANDIX_LUCI_BASE}/luci-i18n-bandix-zh-cn-26.068.39505.1002c41_all.apk" -O packages/luci-i18n-bandix-zh-cn-26.068.39505.1002c41_all.apk

    BANDIX_CORE_VER="v0.12.7"
    BANDIX_CORE_BASE="https://github.com/timsaya/openwrt-bandix/releases/download/${BANDIX_CORE_VER}"
    wget -q "${BANDIX_CORE_BASE}/bandix-0.12.7-r1_x86_64.apk" -O packages/bandix-0.12.7-r1_x86_64.apk
fi

# 获取最新的 Passwall apk
if echo "$PACKAGES" | grep -q "luci-app-passwall"; then
    echo "✅ 已选择 luci-app-passwall，从原作者下载最新 apk"
    mkdir -p packages
    PASSWALL_VER="26.4.15"
    PASSWALL_BASE="https://github.com/Openwrt-Passwall/openwrt-passwall/releases/download/${PASSWALL_VER}-1"
    wget -q "${PASSWALL_BASE}/25.12%2B_luci-app-passwall-${PASSWALL_VER}-r1.apk" -O packages/luci-app-passwall-${PASSWALL_VER}-r1.apk
    wget -q "${PASSWALL_BASE}/25.12%2B_luci-i18n-passwall-zh-cn-${PASSWALL_VER}.apk" -O packages/luci-i18n-passwall-zh-cn-${PASSWALL_VER}.apk
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
