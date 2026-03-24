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
COMMON_31_PACKAGES="luci-app-adguardhome adguardhome luci-app-tailscale luci-i18n-tailscale-zh-cn tailscale luci-app-netwizard luci-i18n-netwizard-zh-cn luci-app-partexp luci-i18n-partexp-zh-cn luci-app-watchdog luci-i18n-watchdog-zh-cn watchdog luci-app-advancedplus luci-i18n-advancedplus-zh-cn webdav2 luci-app-unishare unishare luci-app-turboacc luci-app-ddns luci-i18n-ddns-zh-cn ddns-scripts ddns-scripts-services mosdns luci-app-arpbind luci-i18n-arpbind-zh-cn luci-app-netdata luci-i18n-netdata-zh-cn netdata luci-app-ramfree luci-i18n-ramfree-zh-cn luci-app-statistics luci-i18n-statistics-zh-cn luci-app-upnp luci-i18n-upnp-zh-cn miniupnpd-nftables luci-app-vlmcsd luci-i18n-vlmcsd-zh-cn vlmcsd luci-app-vsftpd luci-i18n-vsftpd-zh-cn vsftpd luci-app-wol luci-i18n-wol-zh-cn"
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
PACKAGES="$PACKAGES curl openssh-sftp-server qemu-ga unzip kmod-nft-tproxy kmod-nft-socket"
PACKAGES="$PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn luci-i18n-package-manager-zh-cn luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn luci-app-samba4 luci-i18n-samba4-zh-cn"
# Passwall / SSR Plus 运行栈
PACKAGES="$PACKAGES xray-core hysteria sing-box chinadns-ng haproxy shellsync geoview dns2socks dns2tcp ipt2socks v2ray-plugin"
PACKAGES="$PACKAGES shadowsocks-libev-ss-server shadowsocks-rust-sslocal shadowsocks-rust-ssserver shadowsocksr-libev-ssr-check shadowsocksr-libev-ssr-local shadowsocksr-libev-ssr-redir shadowsocksr-libev-ssr-server simple-obfs-client"
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
    echo "✅ 已选择 luci-app-passwall，下载原创作者最新版 ipk"
    mkdir -p packages
    PASSWALL_VER="26.3.6"
    PASSWALL_BASE="https://github.com/Openwrt-Passwall/openwrt-passwall/releases/download/${PASSWALL_VER}-1"
    wget -q "${PASSWALL_BASE}/23.05-24.10_luci-app-passwall_${PASSWALL_VER}-r1_all.ipk" -O packages/luci-app-passwall_${PASSWALL_VER}-r1_all.ipk
    wget -q "${PASSWALL_BASE}/23.05-24.10_luci-i18n-passwall-zh-cn_${PASSWALL_VER}_all.ipk" -O packages/luci-i18n-passwall-zh-cn_${PASSWALL_VER}_all.ipk
fi

if echo "$PACKAGES" | grep -q "luci-app-bandix"; then
    echo "✅ 已选择 luci-app-bandix，下载原创作者完整依赖链 ipk"
    mkdir -p packages
    BANDIX_LUCI_VER="v0.12.6"
    BANDIX_LUCI_BASE="https://github.com/timsaya/luci-app-bandix/releases/download/${BANDIX_LUCI_VER}"
    wget -q "${BANDIX_LUCI_BASE}/luci-app-bandix_0.12.6-r1_all.ipk" -O packages/luci-app-bandix_0.12.6-r1_all.ipk
    wget -q "${BANDIX_LUCI_BASE}/luci-i18n-bandix-zh-cn_26.068.39505.1002c41_all.ipk" -O packages/luci-i18n-bandix-zh-cn_26.068.39505.1002c41_all.ipk

    BANDIX_CORE_VER="v0.12.7"
    BANDIX_CORE_BASE="https://github.com/timsaya/openwrt-bandix/releases/download/${BANDIX_CORE_VER}"
    wget -q "${BANDIX_CORE_BASE}/bandix_0.12.7-r1_x86_64.ipk" -O packages/bandix_0.12.7-r1_x86_64.ipk
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

# 提取、过滤冗余底部栏 HTML 并利用 files overlay 覆盖（安全修改，避免破坏 IPK 格式）
echo "🔄 正在提取相关插件的 HTML 以覆盖底部状态栏..."
for ipk in $(find /home/build/immortalwrt/packages /home/build/immortalwrt/extra-packages /tmp/store-run-repo -name "*.ipk" 2>/dev/null | grep -iE 'advancedplus|ssr-plus|passwall'); do
    echo "静态提取并 patching: $ipk"
    TMP_DIR="/tmp/extract_$(basename "$ipk")"
    rm -rf "$TMP_DIR" && mkdir -p "$TMP_DIR"
    cp "$ipk" "$TMP_DIR/"
    cd "$TMP_DIR"
    
    # 解压 ipk 到临时目录
    ar x "$(basename "$ipk")" 2>/dev/null || tar -xzf "$(basename "$ipk")" 2>/dev/null
    
    DATA_ARCHIVE=""
    if [ -f "data.tar.gz" ]; then DATA_ARCHIVE="data.tar.gz"; fi
    if [ -f "data.tar.zst" ]; then DATA_ARCHIVE="data.tar.zst"; fi
    if [ -f "data.tar.xz" ]; then DATA_ARCHIVE="data.tar.xz"; fi
    
    if [ -n "$DATA_ARCHIVE" ]; then
        mkdir -p data_ext
        # 解压数据包
        if [ "$DATA_ARCHIVE" = "data.tar.gz" ]; then tar -xzf data.tar.gz -C data_ext; fi
        if [ "$DATA_ARCHIVE" = "data.tar.zst" ]; then tar -I zstd -xf data.tar.zst -C data_ext; fi
        if [ "$DATA_ARCHIVE" = "data.tar.xz" ]; then tar -xJf data.tar.xz -C data_ext; fi
        
        # 将插件所有解包的系统文件直接覆盖到 OPENWRT FILES 里
        if [ -d "data_ext/usr" ] || [ -d "data_ext/www" ]; then
            cp -ra data_ext/* /home/build/immortalwrt/files/ 2>/dev/null || true
        fi
    fi
    cd /home/build/immortalwrt
    rm -rf "$TMP_DIR"
done

# 全局深度清理：对所有已经覆盖过去的 JS, Lua, HTM 文件进行清理。
# 无论是通过 cbi.template 还是 JS AJAX 动态写入的底部测试图标栏，均截断其输出。
if [ -d "/home/build/immortalwrt/files" ]; then
    echo "🧹 正在全局深度清理底部状态图标及文本..."
    find /home/build/immortalwrt/files -type f \( -name "*.htm" -o -name "*.js" -o -name "*.lua" \) 2>/dev/null | while read target_file; do
        # 匹配各种可能含底部强弹状态的标识，将其替换或删除
        sed -i 's/获取中//g' "$target_file" 2>/dev/null
        sed -i 's/Collecting data//g' "$target_file" 2>/dev/null
        sed -i '/fa-google/I d' "$target_file" 2>/dev/null
        sed -i '/fa-github/I d' "$target_file" 2>/dev/null
        sed -i '/fa-baidu/I d' "$target_file" 2>/dev/null
        sed -i '/fa-taobao/I d' "$target_file" 2>/dev/null
        sed -i 's/icon-google//g' "$target_file" 2>/dev/null
        sed -i 's/icon-github//g' "$target_file" 2>/dev/null
        
        # 针对于有些插件强行以 div append 给页脚的形式的破坏：
        sed -i '/shadowsocksr_status/I d' "$target_file" 2>/dev/null
        sed -i '/advancedplus_status/I d' "$target_file" 2>/dev/null
        sed -i '/global-status-bar/I d' "$target_file" 2>/dev/null
    done
    
    # 追加一段极强的全局 CSS，通过后台的通用主题文件 (若是 Argon 等)，彻底隐藏所有这些状态框
    mkdir -p /home/build/immortalwrt/files/www/luci-static/resources
    echo "
    document.addEventListener('DOMContentLoaded', function() {
        var style = document.createElement('style');
        style.type = 'text/css';
        style.innerHTML = '.global-status-bar, #advancedplus_status, .footer-status, [id*=\"status-bar\"], [class*=\"status-bar\"] { display: none !important; }';
        document.head.appendChild(style);
        setTimeout(function(){
            document.querySelectorAll('div, p, span, fieldset').forEach(function(el){
               if(el.innerText && (el.innerText.includes('获取中') || el.innerText.includes('Fetching'))){
                  let p = el;
                  while(p && p.tagName !== 'BODY') {
                     if(p.style.position==='fixed' || p.innerHTML.includes('github') || p.innerHTML.includes('google')){ 
                         p.style.display='none'; break; 
                     }
                     p = p.parentElement;
                  }
               }
            });
        }, 1500);
    });" > /home/build/immortalwrt/files/www/luci-static/resources/kill_footer.js
    
    # 尝试把这段清理脚本挂载到所有的底栏文件（如果有）
    find /home/build/immortalwrt/files/usr/lib/lua/luci/view/ -type f \( -name "footer.htm" -o -name "sysauth.htm" \) 2>/dev/null | while read foot; do
        echo "<script src=\"/luci-static/resources/kill_footer.js\"></script>" >> "$foot"
    done
    # 针对ssr-plus的界面，挂载到 cbi 的挂载点
    find /home/build/immortalwrt/files/usr/lib/lua/luci/view/shadowsocksr/ -type f -name "optimize_cbi_ui.htm" 2>/dev/null | while read ssrcbi; do
        echo "<script src=\"/luci-static/resources/kill_footer.js\"></script>" >> "$ssrcbi"
    done
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
