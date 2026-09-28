#!/bin/bash
# ================================================================
# diy-part2.sh —— 修改源码与追加自定义配置 (时区设置 + 注入公共插件 + 基础系统设置)
# 运行目录: ponwrt 源码根目录（加载 .config 之后，make defconfig 之前）
# ================================================================

echo "=========================================="
echo "执行自定义修改与注入公共配置 (diy-part2.sh)"
echo "=========================================="

# ---------------------------------------------------------
# 1. 基础系统设置：修改默认主机名、IP 和 WIFI 名称 (如需开启，请取消对应的注释)
# ---------------------------------------------------------
# 修改默认主机名
# sed -i 's/OpenWrt/PONWrt/g' package/base-files/files/bin/config_generate

# 修改默认 IP 地址
# sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate

# 修改默认 WIFI 名称
# sed -i 's/ssid=OpenWrt/ssid=PONWrt_WIFI/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh
# sed -i 's/ssid="OpenWrt"/ssid="PONWrt_WIFI"/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh

# ---------------------------------------------------------
# 2. 修改 config_generate 的默认值（首次开机生成的 /etc/config/system）
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

# 时区设置脚本
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

# 默认关闭 Lucky 自启脚本
cat > files/etc/uci-defaults/99-disable-lucky <<'EOF'
#!/bin/sh
if [ -f "/etc/init.d/lucky" ]; then
    /etc/init.d/lucky disable
    /etc/init.d/lucky stop
fi
exit 0
EOF
chmod +x files/etc/uci-defaults/99-disable-lucky

echo "✅ uci-defaults 初始化脚本已写入 (时区配置 + 默认关闭 Lucky)"

# ---------------------------------------------------------
# 4. 补上亚洲时区数据库包
# ---------------------------------------------------------
if [ -f .config ]; then
  sed -i '/^CONFIG_PACKAGE_zoneinfo-asia=/d; /^# CONFIG_PACKAGE_zoneinfo-asia is not set/d' .config
  echo "CONFIG_PACKAGE_zoneinfo-asia=y    # 亚洲时区数据库（中国时区需要）" >> .config
  echo "✅ zoneinfo-asia 已加入 .config"
fi

# ---------------------------------------------------------
# 5. 下载预编译二进制 (Xray-core、Geo数据、geoview)
# ---------------------------------------------------------
echo "📥 正在拉取官方预编译二进制文件与数据..."
mkdir -p files/usr/bin
mkdir -p files/usr/share/v2ray

# 5.1 【优化点 1】拉取 Xray-core 及 Geo 数据 (使用 /releases 接口提取绝对最新版)
XRAY_URL=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | grep "browser_download_url.*Xray-linux-arm64-v8a.zip" | head -n 1 | cut -d '"' -f 4)
if [ -n "$XRAY_URL" ]; then
  wget -qO /tmp/xray.zip "$XRAY_URL"
  # 提取 xray 本体到 /usr/bin/
  unzip -qo /tmp/xray.zip xray -d files/usr/bin/
  chmod +x files/usr/bin/xray
  # 提取 geoip.dat 和 geosite.dat 到 /usr/share/v2ray/
  unzip -qo /tmp/xray.zip geoip.dat geosite.dat -d files/usr/share/v2ray/
  rm -f /tmp/xray.zip
  echo "✅ 绝对最新版 Xray-core 及 Geo 数据已就绪"
else
  echo "::warning::拉取 Xray-core 失败"
fi

# 5.2 【优化点 1】拉取 geoview (使用 /releases API)
GEOVIEW_URL=$(curl -s https://api.github.com/repos/snowie2000/geoview/releases | grep "browser_download_url.*geoview-linux-arm64" | head -n 1 | cut -d '"' -f 4)
if [ -n "$GEOVIEW_URL" ]; then
  wget -qO files/usr/bin/geoview "$GEOVIEW_URL"
  chmod +x files/usr/bin/geoview
  echo "✅ geoview 预编译二进制已就绪"
else
  echo "::warning::拉取 geoview 失败"
  rm -f files/usr/bin/geoview
fi

# ---------------------------------------------------------
# 6. 【关键修复】补齐 OpenWrt 缺失的 kmod-xdp-sockets-diag 内核模块定义 (daed 刚需)
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
  echo "✅ 已向 netsupport.mk 成功注入 kmod-xdp-sockets-diag 模块定义"
fi

# 强制内核开启 XDP_SOCKETS 特性 (强烈建议内建设为 y)
for cfg in target/linux/airoha/config-* target/linux/generic/config-*; do
  if [ -f "$cfg" ]; then
    sed -i '/CONFIG_XDP_SOCKETS/d' "$cfg"
    echo "CONFIG_XDP_SOCKETS=y" >> "$cfg"
    echo "CONFIG_XDP_SOCKETS_DIAG=y" >> "$cfg"
  fi
done

# 全局剔除官方 feeds 包可能带来的 xdp 依赖链，防止打包报错
find package/ feeds/ -name "Makefile" | xargs sed -i 's/+kmod-xdp-sockets-diag//g' 2>/dev/null
echo "✅ XDP Sockets 诊断支持已直接内建至内核配置"

# ---------------------------------------------------------
# 7. 向 .config 强制注入公共的软件包配置 (严禁修改下方格式缩进)
# ---------------------------------------------------------
if [ -f .config ]; then
  # 彻底清除所有可能被自动勾选的 Go 核心和 openlist 干扰
  sed -i '/CONFIG_PACKAGE_geoview/d' .config
  sed -i '/CONFIG_PACKAGE_v2ray-plugin/d' .config
  sed -i '/CONFIG_PACKAGE_xray-core/d' .config
  sed -i '/CONFIG_PACKAGE_sing-box/d' .config
  sed -i '/CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_/d' .config
  sed -i '/CONFIG_PACKAGE_openlist/d' .config
  sed -i '/CONFIG_PACKAGE_luci-app-openlist/d' .config

  cat >> .config <<EOF

# ========================
# 强制注入的公共插件配置
# ========================

# --- 由 diy-part1.sh 拉取的第三方插件 ---
CONFIG_PACKAGE_luci-app-easytier=y
CONFIG_PACKAGE_luci-theme-aurora=y
CONFIG_PACKAGE_luci-app-lucky=y

# 【优化点 2】：移除 Openlist2 的注入

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
# --- kmod-nft-queue主要用于fakehttp ---
CONFIG_PACKAGE_kmod-nft-queue=y

# --- Daed库 ---
# 1. 对应 kmod-sched-bpf
#CONFIG_PACKAGE_kmod-sched-bpf=y
# 2. 对应 kmod-veth
#CONFIG_PACKAGE_kmod-veth=y
# 【优化点 3】：kmod-xdp-sockets-diag 已内建到系统内核中，严禁此处再次勾选打包！
#CONFIG_PACKAGE_kmod-xdp-sockets-diag=y
# dae / eBPF 运行必须的底层依赖（务必一并开启）
#CONFIG_KERNEL_BPF_EVENTS=y
#CONFIG_BPF_TOOLCHAIN=y

# --- Daede (dae / daed + luci-app-daede) 完整支持 ---
# 1. 前端与核心
CONFIG_PACKAGE_luci-app-daede=y
CONFIG_PACKAGE_dae=y
CONFIG_PACKAGE_daed=y

# 2. 证书与网络依赖
CONFIG_PACKAGE_ca-bundle=y
CONFIG_PACKAGE_kmod-nft-tproxy=y

# 3. eBPF 内核底层模块依赖
CONFIG_PACKAGE_kmod-sched-bpf=y
CONFIG_PACKAGE_kmod-sched-core=y
CONFIG_PACKAGE_kmod-veth=y

# 4. 内核 eBPF / BTF 特性支持 (dae 核心必需)
CONFIG_KERNEL_BPF_EVENTS=y
CONFIG_BPF_TOOLCHAIN=y
CONFIG_KERNEL_DEBUG_INFO=y
CONFIG_KERNEL_DEBUG_INFO_BTF=y

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

# --- Passwall 2 纯界面面板 (零 Go 核心编译) ---
CONFIG_PACKAGE_luci-app-passwall2=y
CONFIG_PACKAGE_v2ray-geoip=y
CONFIG_PACKAGE_v2ray-geosite=y

# --- Passwall 2 主程序与精确核心配置 ---
#CONFIG_PACKAGE_luci-app-passwall2=y

# 强制关闭全量核心 (防止带出所有依赖)
# CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_All is not set

# 开启 Xray 和 Sing-box 核心
#CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_Xray=y
#CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_Sing_Box=y

# 强制关闭 Rust 核心及其他不必要组件，极大缩短编译时间
# CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_Shadowsocks_Rust_Client is not set
# CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_Shadowsocks_Rust_Server is not set
# CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_Hysteria is not set
# CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_Tuic is not set
# CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_NaiveProxy is not set

EOF
  echo "✅ 公共软件包及 Passwall2 核心配置已注入 .config"
else
  echo "::warning::未找到 .config 文件，跳过公共软件包注入"
fi

echo "🎉 diy-part2.sh 执行完毕"
