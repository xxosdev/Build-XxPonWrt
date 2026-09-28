#!/bin/bash
# ================================================================
# diy-part2.sh —— 修改源码与追加自定义配置 (时区设置 + 注入公共插件 + 基础系统设置)
# 运行目录: ponwrt 源码根目录（加载 .config 之后，make defconfig 之前）
# ================================================================

echo "=========================================="
echo "执行自定义修改与注入公共配置 (diy-part2.sh)"
echo "=========================================="

# ---------------------------------------------------------
# 0. 补全系统编译环境 (安装 pahole 以生成内核 BTF)
# ---------------------------------------------------------
if command -v apt-get &> /dev/null; then
  echo "📦 正在安装 dwarves (pahole) 以确保 Linux 内核成功生成 BTF..."
  sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y dwarves
fi

# ---------------------------------------------------------
# 1. 基础系统设置：修改默认主机名、IP 和 WIFI 名称
# ---------------------------------------------------------
# sed -i 's/OpenWrt/PONWrt/g' package/base-files/files/bin/config_generate
# sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate
# sed -i 's/ssid=OpenWrt/ssid=PONWrt_WIFI/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh
# sed -i 's/ssid="OpenWrt"/ssid="PONWrt_WIFI"/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh

# ---------------------------------------------------------
# 2. 修改 config_generate 的默认值
# ---------------------------------------------------------
CFG="package/base-files/files/bin/config_generate"
if [ -f "$CFG" ]; then
  sed -i "s/option timezone.*/option timezone 'CST-8'/" "$CFG"
  sed -i "s/option zonename.*/option zonename 'Asia\/Shanghai'/" "$CFG"
  echo "✅ config_generate 默认时区 -> CST-8 / Asia/Shanghai"
else
  echo "::warning::未找到 $CFG，跳过默认值修改"
fi

# ---------------------------------------------------------
# 3. uci-defaults：强制刷成中国时区 & 默认关闭 Lucky
# ---------------------------------------------------------
mkdir -p files/etc/uci-defaults

cat > files/etc/uci-defaults/99-timezone-cn <<'EOF'
#!/bin/sh
uci -q batch <<'UCI'
set system.@system[0].zonename='Asia/Shanghai'
set system.@system[0].timezone='CST-8'
commit system
UCI
exit 0
EOF
chmod +x files/etc/uci-defaults/99-timezone-cn

cat > files/etc/uci-defaults/99-disable-lucky <<'EOF'
#!/bin/sh
if [ -f "/etc/init.d/lucky" ]; then
    /etc/init.d/lucky disable
    /etc/init.d/lucky stop
fi
exit 0
EOF
chmod +x files/etc/uci-defaults/99-disable-lucky
echo "✅ uci-defaults 初始化脚本已写入"

# ---------------------------------------------------------
# 4. 补上亚洲时区数据库包
# ---------------------------------------------------------
if [ -f .config ]; then
  sed -i '/^CONFIG_PACKAGE_zoneinfo-asia=/d; /^# CONFIG_PACKAGE_zoneinfo-asia is not set/d' .config
  echo "CONFIG_PACKAGE_zoneinfo-asia=y    # 亚洲时区数据库" >> .config
fi

# ---------------------------------------------------------
# 5. 下载预编译二进制核心 (仅保留 Xray 和 Geoview)
# ---------------------------------------------------------
echo "📥 正在拉取官方预编译二进制文件与数据..."
mkdir -p files/usr/bin
mkdir -p files/usr/share/v2ray

# 5.1 拉取 Xray-core 及 Geo 数据
XRAY_URL=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | grep "browser_download_url.*Xray-linux-arm64-v8a.zip" | head -n 1 | cut -d '"' -f 4)
if [ -n "$XRAY_URL" ]; then
  wget -qO /tmp/xray.zip "$XRAY_URL"
  unzip -qo /tmp/xray.zip xray -d files/usr/bin/
  chmod +x files/usr/bin/xray
  unzip -qo /tmp/xray.zip geoip.dat geosite.dat -d files/usr/share/v2ray/
  rm -f /tmp/xray.zip
  echo "✅ 最新版 Xray-core 及 Geo 数据已就绪"
fi

# 5.2 拉取 geoview
GEOVIEW_URL=$(curl -s https://api.github.com/repos/snowie2000/geoview/releases | grep "browser_download_url.*geoview-linux-arm64" | head -n 1 | cut -d '"' -f 4)
if [ -n "$GEOVIEW_URL" ]; then
  wget -qO files/usr/bin/geoview "$GEOVIEW_URL"
  chmod +x files/usr/bin/geoview
  echo "✅ geoview 已就绪"
fi

# ---------------------------------------------------------
# 6. 【精细修复】铺路生成 kmod-xdp-sockets-diag + 强开 BTF 内核模块
# ---------------------------------------------------------
NETSUPPORT_MK="package/kernel/linux/modules/netsupport.mk"
if [ -f "$NETSUPPORT_MK" ] && ! grep -q "xdp-sockets-diag" "$NETSUPPORT_MK"; then
  cat >> "$NETSUPPORT_MK" << 'EOF'

define KernelPackage/xdp-sockets-diag
  SUBMENU:=$(NETWORK_SUPPORT_MENU)
  TITLE:=PF_XDP sockets monitoring interface support
  KCONFIG:=CONFIG_XDP_SOCKETS_DIAG
  FILES:=$(LINUX_DIR)/net/xdp/xsk_diag.ko
  AUTOLOAD:=$(call AutoLoad,31,xsk_diag)
endef

define KernelPackage/xdp-sockets-diag/description
 Support for PF_XDP sockets monitoring interface used by the ss tool and daed.
endef

$(eval $(call KernelPackage,xdp-sockets-diag))
EOF
fi

# 【关键改动】：修改内核配置，坚决禁用精简模式，确保 BTF 完整生成
for cfg in target/linux/airoha/config-* target/linux/generic/config-*; do
  if [ -f "$cfg" ]; then
    # XDP Sockets
    sed -i '/CONFIG_XDP_SOCKETS/d' "$cfg"
    echo "CONFIG_XDP_SOCKETS=y" >> "$cfg"
    
    # 强制开启完整调试与 BTF，并禁止内核精简调试信息
    sed -i '/CONFIG_DEBUG_INFO_REDUCED/d' "$cfg"
    sed -i '/CONFIG_DEBUG_INFO_BTF/d' "$cfg"
    sed -i '/CONFIG_DEBUG_INFO/d' "$cfg"
    sed -i '/CONFIG_BPF_SYSCALL/d' "$cfg"
    echo "# CONFIG_DEBUG_INFO_REDUCED is not set" >> "$cfg"
    echo "CONFIG_DEBUG_INFO=y" >> "$cfg"
    echo "CONFIG_DEBUG_INFO_BTF=y" >> "$cfg"
    echo "CONFIG_BPF_SYSCALL=y" >> "$cfg"
  fi
done
echo "✅ 已向底层内核强制注入 BTF 支持，解决透明代理无法读取内核态的问题！"

# ---------------------------------------------------------
# 7. 向 .config 强制注入公共的软件包配置
# ---------------------------------------------------------
if [ -f .config ]; then
  # 彻底清除干扰项
  sed -i '/CONFIG_PACKAGE_geoview/d' .config
  sed -i '/CONFIG_PACKAGE_v2ray-plugin/d' .config
  sed -i '/CONFIG_PACKAGE_xray-core/d' .config
  sed -i '/CONFIG_PACKAGE_sing-box/d' .config
  sed -i '/CONFIG_PACKAGE_luci-app-homeproxy/d' .config
  sed -i '/CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_/d' .config
  sed -i '/CONFIG_PACKAGE_openlist/d' .config
  sed -i '/CONFIG_PACKAGE_luci-app-openlist/d' .config
  sed -i '/CONFIG_PACKAGE_dae=/d' .config
  sed -i '/CONFIG_PACKAGE_daed=/d' .config
  
  # 在 OpenWrt 主配置层面也要强行剥离精简模式
  sed -i '/CONFIG_KERNEL_DEBUG_INFO_REDUCED/d' .config
  echo "# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set" >> .config

  cat >> .config <<EOF

# ========================
# 强制注入的公共插件配置
# ========================

CONFIG_PACKAGE_luci-app-easytier=y
CONFIG_PACKAGE_luci-theme-aurora=y
CONFIG_PACKAGE_luci-app-lucky=y

# --- Honk 引擎 ---
CONFIG_PACKAGE_honk=y
CONFIG_PACKAGE_luci-app-honk=y
CONFIG_PACKAGE_ip-full=y

# --- 官方 feeds 源自带的插件 ---
CONFIG_PACKAGE_luci-app-filemanager=y
CONFIG_PACKAGE_pbr=y
CONFIG_PACKAGE_luci-app-pbr=y
CONFIG_PACKAGE_vlmcsd=y
CONFIG_PACKAGE_luci-app-vlmcsd=y
CONFIG_PACKAGE_etherwake=y
CONFIG_PACKAGE_luci-app-wol=y
CONFIG_PACKAGE_ttyd=y
CONFIG_PACKAGE_luci-app-ttyd=y
CONFIG_PACKAGE_kmod-nft-queue=y

# --- Daed库 ---
CONFIG_PACKAGE_kmod-xdp-sockets-diag=y

# --- Daede (外挂版 - 后台自行手动安装核心) ---
CONFIG_PACKAGE_luci-app-daede=y
CONFIG_PACKAGE_ca-bundle=y
CONFIG_PACKAGE_kmod-nft-tproxy=y
CONFIG_PACKAGE_kmod-sched-bpf=y
CONFIG_PACKAGE_kmod-sched-core=y
CONFIG_PACKAGE_kmod-veth=y

# BTF 与 eBPF 特性 (坚决开启)
CONFIG_KERNEL_DEBUG_INFO=y
CONFIG_KERNEL_DEBUG_INFO_BTF=y
CONFIG_KERNEL_BPF_EVENTS=y
CONFIG_BPF_TOOLCHAIN=y

# --- 网络共享: Samba4 服务端及 LuCI 界面 ---
CONFIG_PACKAGE_samba4-server=y
CONFIG_PACKAGE_samba4-libs=y
CONFIG_PACKAGE_luci-app-samba4=y
CONFIG_PACKAGE_luci-i18n-samba4-zh-cn=y
CONFIG_PACKAGE_wsdd2=y

# --- 端口映射: UPnP IGD 与 PCP/NAT-PMP 服务 ---
CONFIG_PACKAGE_miniupnpd=y
CONFIG_PACKAGE_luci-app-upnp=y
CONFIG_PACKAGE_luci-i18n-upnp-zh-cn=y
CONFIG_MINIUPNPD_PCP_PEER=y

# --- Passwall 2 纯界面面板 ---
CONFIG_PACKAGE_luci-app-passwall2=y
CONFIG_PACKAGE_v2ray-geoip=y
CONFIG_PACKAGE_v2ray-geosite=y

EOF
  echo "✅ 公共软件包及配置已注入 .config"
else
  echo "::warning::未找到 .config 文件，跳过公共软件包注入"
fi

echo "🎉 diy-part2.sh 执行完毕"
