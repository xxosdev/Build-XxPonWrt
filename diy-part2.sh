#!/bin/bash
# ================================================================
# diy-part2.sh —— 修改源码与追加自定义配置 (时区设置 + 注入公共插件 + 基础系统设置)
# 运行目录: ponwrt 源码根目录（加载 .config 之后，make defconfig 之前）
# ================================================================

echo "=========================================="
echo "执行自定义修改与注入公共配置 (diy-part2.sh)"
echo "=========================================="

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
# 5. 下载预编译二进制核心 (Xray, Geoview, Sing-box, dae, daed)
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

# 5.3 拉取 Sing-box 核心
SINGBOX_URL=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases | grep "browser_download_url.*linux-armv8.tar.gz" | head -n 1 | cut -d '"' -f 4)
[ -z "$SINGBOX_URL" ] && SINGBOX_URL=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases | grep "browser_download_url.*linux-arm64.tar.gz" | head -n 1 | cut -d '"' -f 4)
if [ -n "$SINGBOX_URL" ]; then
  wget -qO /tmp/singbox.tar.gz "$SINGBOX_URL"
  tar -xzf /tmp/singbox.tar.gz -C /tmp/
  mv /tmp/sing-box-*/sing-box files/usr/bin/
  chmod +x files/usr/bin/sing-box
  rm -rf /tmp/singbox* /tmp/sing-box*
  echo "✅ 最新版 Sing-box 核心已就绪"
fi

# 5.4 拉取 dae 和 daed 核心
DAE_URL=$(curl -s https://api.github.com/repos/daeuniverse/dae/releases | grep "browser_download_url.*dae-linux-arm64.zip" | head -n 1 | cut -d '"' -f 4)
if [ -n "$DAE_URL" ]; then
  wget -qO /tmp/dae.zip "$DAE_URL"
  mkdir -p /tmp/dae_ext && unzip -qo /tmp/dae.zip -d /tmp/dae_ext/
  find /tmp/dae_ext -type f -exec mv {} files/usr/bin/dae \;
  chmod +x files/usr/bin/dae
  rm -rf /tmp/dae*
  echo "✅ 最新版 dae 核心已就绪"
fi

DAED_URL=$(curl -s https://api.github.com/repos/daeuniverse/daed/releases | grep "browser_download_url.*daed-linux-arm64.zip" | head -n 1 | cut -d '"' -f 4)
if [ -n "$DAED_URL" ]; then
  wget -qO /tmp/daed.zip "$DAED_URL"
  mkdir -p /tmp/daed_ext && unzip -qo /tmp/daed.zip -d /tmp/daed_ext/
  find /tmp/daed_ext -type f -exec mv {} files/usr/bin/daed \;
  chmod +x files/usr/bin/daed
  rm -rf /tmp/daed*
  echo "✅ 最新版 daed 核心已就绪"
fi

# ---------------------------------------------------------
# 6. 【精细修复】铺路生成 kmod-xdp-sockets-diag 安装包
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

# 内核基础特性开启(=y)，让系统正常打包生成 kmod 安装包
for cfg in target/linux/airoha/config-* target/linux/generic/config-*; do
  if [ -f "$cfg" ]; then
    sed -i '/CONFIG_XDP_SOCKETS/d' "$cfg"
    echo "CONFIG_XDP_SOCKETS=y" >> "$cfg"
  fi
done

# ---------------------------------------------------------
# 7. 向 .config 强制注入公共的软件包配置
# ---------------------------------------------------------
if [ -f .config ]; then
  # 清除干扰
  sed -i '/CONFIG_PACKAGE_geoview/d' .config
  sed -i '/CONFIG_PACKAGE_v2ray-plugin/d' .config
  sed -i '/CONFIG_PACKAGE_xray-core/d' .config
  sed -i '/CONFIG_PACKAGE_sing-box/d' .config
  sed -i '/CONFIG_PACKAGE_dae=/d' .config
  sed -i '/CONFIG_PACKAGE_daed=/d' .config

  cat >> .config <<EOF

# ========================
# 强制注入的公共插件配置
# ========================

CONFIG_PACKAGE_luci-app-easytier=y
CONFIG_PACKAGE_luci-theme-aurora=y
CONFIG_PACKAGE_luci-app-lucky=y
CONFIG_PACKAGE_luci-app-homeproxy=y

# --- 新增: Honk 引擎 ---
CONFIG_PACKAGE_honk=y
CONFIG_PACKAGE_luci-app-honk=y
CONFIG_PACKAGE_ip-full=y

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

# --- Daede (外挂版) ---
CONFIG_PACKAGE_kmod-xdp-sockets-diag=y
CONFIG_PACKAGE_luci-app-daede=y
CONFIG_PACKAGE_ca-bundle=y
CONFIG_PACKAGE_kmod-nft-tproxy=y
CONFIG_PACKAGE_kmod-sched-bpf=y
CONFIG_PACKAGE_kmod-sched-core=y
CONFIG_PACKAGE_kmod-veth=y
CONFIG_KERNEL_BPF_EVENTS=y
CONFIG_BPF_TOOLCHAIN=y
CONFIG_KERNEL_DEBUG_INFO=y
CONFIG_KERNEL_DEBUG_INFO_BTF=y

CONFIG_PACKAGE_samba4-server=y
CONFIG_PACKAGE_samba4-libs=y
CONFIG_PACKAGE_luci-app-samba4=y
CONFIG_PACKAGE_luci-i18n-samba4-zh-cn=y
CONFIG_PACKAGE_wsdd2=y

CONFIG_PACKAGE_miniupnpd=y
CONFIG_PACKAGE_luci-app-upnp=y
CONFIG_PACKAGE_luci-i18n-upnp-zh-cn=y
CONFIG_MINIUPNPD_PCP_PEER=y

CONFIG_PACKAGE_luci-app-passwall2=y
CONFIG_PACKAGE_v2ray-geoip=y
CONFIG_PACKAGE_v2ray-geosite=y

EOF
  echo "✅ 公共软件包及配置已注入 .config"
fi

echo "🎉 diy-part2.sh 执行完毕"
