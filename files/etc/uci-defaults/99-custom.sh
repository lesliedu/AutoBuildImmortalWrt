#!/bin/sh
# 99-custom.sh 就是immortalwrt固件首次启动时运行的脚本 位于固件内的/etc/uci-defaults/99-custom.sh
# Log file for debugging
LOGFILE="/etc/config/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >>$LOGFILE

# 设置默认防火墙规则，方便单网口虚拟机首次访问 WebUI 
uci set firewall.@zone[1].input='ACCEPT'

# 启用 Linux 内核原生网络流分载 (Flow Offloading)，实现内核级软转发加速 (平替旧版 Turbo ACC)
uci set firewall.@defaults[0].flow_offloading='1'
uci set firewall.@defaults[0].flow_offloading_hw='0'
uci commit firewall

# 设置主机名映射，解决安卓原生 TV 无法联网的问题
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# 升级保留策略：默认不主动强改已有 network 配置。
# 但若检测到是接近出厂默认的首次安装场景，则允许应用 workflow 注入的 custom_router_ip。
IP_VALUE_FILE="/etc/config/custom_router_ip.txt"
CURRENT_LAN_IP="$(uci -q get network.lan.ipaddr)"
CURRENT_LAN_PROTO="$(uci -q get network.lan.proto)"
if [ -f "$IP_VALUE_FILE" ]; then
    CUSTOM_IP=$(cat "$IP_VALUE_FILE")
    case "$CURRENT_LAN_IP" in
        ""|192.168.1.1|192.168.100.1)
            if [ "$CURRENT_LAN_PROTO" = "static" ] || [ -z "$CURRENT_LAN_PROTO" ]; then
                uci set network.lan.ipaddr="$CUSTOM_IP"
                uci set network.lan.netmask='255.255.255.0'
                echo "fresh-install detected, apply custom router ip: $CUSTOM_IP" >>$LOGFILE
                uci commit network
            else
                echo "skip custom router ip because current LAN proto is $CURRENT_LAN_PROTO" >>$LOGFILE
            fi
            ;;
        *)
            echo "upgrade/retained-config detected, keep existing LAN ip: $CURRENT_LAN_IP" >>$LOGFILE
            ;;
    esac
fi

# 若安装了dockerd 则设置docker的防火墙规则
# 扩大docker涵盖的子网范围 '172.16.0.0/12'
# 方便各类docker容器的端口顺利通过防火墙 
if command -v dockerd >/dev/null 2>&1; then
    echo "检测到 Docker，正在配置防火墙规则..."
    FW_FILE="/etc/config/firewall"

    # 删除所有名为 docker 的 zone
    uci delete firewall.docker

    # 先获取所有 forwarding 索引，倒序排列删除
    for idx in $(uci show firewall | grep "=forwarding" | cut -d[ -f2 | cut -d] -f1 | sort -rn); do
        src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
        dest=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
        echo "Checking forwarding index $idx: src=$src dest=$dest"
        if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
            echo "Deleting forwarding @forwarding[$idx]"
            uci delete firewall.@forwarding[$idx]
        fi
    done
    # 提交删除
    uci commit firewall
    # 追加新的 zone + forwarding 配置
    cat <<EOF >>"$FW_FILE"

config zone 'docker'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'
  option name 'docker'
  list subnet '172.16.0.0/12'

config forwarding
  option src 'docker'
  option dest 'lan'

config forwarding
  option src 'docker'
  option dest 'wan'

config forwarding
  option src 'lan'
  option dest 'docker'
EOF

else
    echo "未检测到 Docker，跳过防火墙配置。"
fi

# 设置所有网口可访问网页终端
uci delete ttyd.@ttyd[0].interface

# 设置所有网口可连接 SSH
uci set dropbear.@dropbear[0].Interface=''
uci commit

# 对齐服务启用状态（仅首次安装生效；升级时保留原配置优先）
for svc in qemu-ga passwall smartdns ddns-go tailscale watchdog; do
    if [ -x "/etc/init.d/$svc" ]; then
        /etc/init.d/$svc enable >/dev/null 2>&1 || true
    fi
done
for svc in openclash homeproxy lucky dockerd; do
    if [ -x "/etc/init.d/$svc" ]; then
        /etc/init.d/$svc disable >/dev/null 2>&1 || true
    fi
done

exit 0
