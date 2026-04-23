#!/bin/bash
# =================================================================
# ImmortalWrt 25.12.x 纯净构建脚本 (原生官方源方案)
# =================================================================

# 1. 设置基础目录
mkdir -p files/usr/bin files/usr/sbin files/etc/config files/usr/share/v2ray

# 2. 从上游默认仓库获取必要的纯净配置 (保留Wukong的默认源支持)
if [ -f "shell/apk-prepare-packages.sh" ]; then
  # 我们摒弃了第三方库 clone 和 wget apk 行为
  echo "✅ Skipping third-party APK fetching to ensure 100% build stability."
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建固件..."

# =================================================================
# 3. 软件包列表配置 (仅限 25.12 官方源存在的包)
# =================================================================

PACKAGES=""
# 基础核心工具
PACKAGES="$PACKAGES curl openssh-sftp-server qemu-ga unzip sshpass ethtool"

# 主题与界面
PACKAGES="$PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn luci-i18n-package-manager-zh-cn luci-i18n-ttyd-zh-cn"

# 磁盘管理 (替代原先的 partexp) 与 文件共享 (Samba4, 替代 unishare/webdav2)
PACKAGES="$PACKAGES luci-app-diskman luci-i18n-diskman-zh-cn luci-app-samba4 luci-i18n-samba4-zh-cn"

# 科学上网核心组件 (Passwall 及相关依赖)
PACKAGES="$PACKAGES luci-app-passwall luci-i18n-passwall-zh-cn"
PACKAGES="$PACKAGES xray-core hysteria sing-box chinadns-ng haproxy shellsync geoview dns2socks dns2tcp ipt2socks v2ray-plugin"
PACKAGES="$PACKAGES shadowsocks-rust-sslocal shadowsocks-rust-ssserver simple-obfs-client"

# 常用服务 (DNS, VPN)
PACKAGES="$PACKAGES smartdns luci-app-smartdns luci-i18n-smartdns-zh-cn"
PACKAGES="$PACKAGES zerotier luci-app-zerotier luci-i18n-zerotier-zh-cn"

# 原 COMMON_31_PACKAGES 中的遗留有效插件 (经过筛选)
PACKAGES="$PACKAGES luci-app-adguardhome adguardhome"
PACKAGES="$PACKAGES luci-app-tailscale-community luci-i18n-tailscale-community-zh-cn tailscale"
PACKAGES="$PACKAGES luci-app-watchcat luci-i18n-watchcat-zh-cn watchcat"
PACKAGES="$PACKAGES luci-app-ddns luci-i18n-ddns-zh-cn ddns-scripts ddns-scripts-services mosdns"
PACKAGES="$PACKAGES luci-app-arpbind luci-i18n-arpbind-zh-cn"
PACKAGES="$PACKAGES luci-app-netdata luci-i18n-netdata-zh-cn netdata"
PACKAGES="$PACKAGES luci-app-ramfree luci-i18n-ramfree-zh-cn"
PACKAGES="$PACKAGES luci-app-statistics luci-i18n-statistics-zh-cn"
PACKAGES="$PACKAGES luci-app-upnp luci-i18n-upnp-zh-cn miniupnpd-nftables"
PACKAGES="$PACKAGES luci-app-vlmcsd luci-i18n-vlmcsd-zh-cn vlmcsd"
PACKAGES="$PACKAGES luci-app-vsftpd luci-i18n-vsftpd-zh-cn vsftpd"
PACKAGES="$PACKAGES luci-app-wol luci-i18n-wol-zh-cn wakeonlan"

# 流量监控 (官方原生 Nlbwmon，替代存在冲突的 Bandix)
PACKAGES="$PACKAGES luci-app-nlbwmon luci-i18n-nlbwmon-zh-cn"

# =================================================================
# 4. 根据输入参数动态调整
# =================================================================

# 判断是否需要编译 Docker 插件
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    echo "Adding package: luci-i18n-dockerman-zh-cn"
fi

# =================================================================
# 5. 注入定制静态文件
# =================================================================

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

# 获取最新的 GeoIP / GeoSite 数据文件
echo "✅ 正在获取最新的 GeoIP / GeoSite 数据文件"
mkdir -p files/usr/share/v2ray
wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/usr/share/v2ray/geoip.dat
wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/usr/share/v2ray/geosite.dat

# 创建对 rust 版 shadowsocks 的软连接，兼容旧配置
echo "✅ 正在创建 ss-local 等软链接兼容..."
mkdir -p files/usr/bin
ln -sf sslocal files/usr/bin/ss-local
ln -sf ssredir files/usr/bin/ss-redir
ln -sf ssserver files/usr/bin/ss-server

# =================================================================
# 6. 构建镜像
# =================================================================
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

make image PROFILE="generic" PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$PROFILE

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
