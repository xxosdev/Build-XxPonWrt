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
# 4. 补上亚洲时区数据库包 & 完美保留温度 -10°C 修复
# ---------------------------------------------------------
if [ -f .config ]; then
  sed -i '/^CONFIG_PACKAGE_zoneinfo-asia=/d; /^# CONFIG_PACKAGE_zoneinfo-asia is not set/d' .config
  echo "CONFIG_PACKAGE_zoneinfo-asia=y    # 亚洲时区数据库" >> .config
fi

# 修复 cpuinfo 与 tempinfo 的温度计算偏移 (-10°C)
find package/ feeds/ files/ -type f \( -name "cpuinfo" -o -name "tempinfo" \) 2>/dev/null | while read -r f; do
  sed -i 's|printf("%.1f°C", [$]0 / 1000)|printf("%.1f°C", ($0 / 1000) - 10)|g' "$f"
  sed -i 's|printf("%.1f", v)|printf("%.1f", v - 10)|g' "$f"
done
echo "✅ 温度显示偏移已修正 (-10°C)"

# ---------------------------------------------------------
# 5. 下载基础辅助组件 (绝对不下载 sing-box，坚决不下载 dae/daed)
# ---------------------------------------------------------
echo "📥 正在拉取基础数据包..."
mkdir -p files/usr/bin
mkdir -p files/usr/share/v2ray

# 仅拉取 Xray-core 及 Geo 数据 (纯净数据文件无编译冲突)
XRAY_URL=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | grep "browser_download_url.*Xray-linux-arm64-v8a.zip" | head -n 1 | cut -d '"' -f 4)
if [ -n "$XRAY_URL" ]; then
  wget -qO /tmp/xray.zip "$XRAY_URL"
  unzip -qo /tmp/xray.zip xray -d files/usr/bin/
  chmod +x files/usr/bin/xray
  unzip -qo /tmp/xray.zip geoip.dat geosite.dat -d files/usr/share/v2ray/
  rm -f /tmp/xray.zip
  echo "✅ 最新版 Xray-core 及 Geo 数据已就绪"
fi

GEOVIEW_URL=$(curl -s https://api.github.com/repos/snowie2000/geoview/releases | grep "browser_download_url.*geoview-linux-arm64" | head -n 1 | cut -d '"' -f 4)
if [ -n "$GEOVIEW_URL" ]; then
  wget -qO files/usr/bin/geoview "$GEOVIEW_URL"
  chmod +x files/usr/bin/geoview
  echo "✅ geoview 已就绪"
fi

# ---------------------------------------------------------
# 6. 为 Honk 铺路：开启内核 XDP_SOCKETS
# ---------------------------------------------------------
for cfg in target/linux/airoha/config-* target/linux/generic/config-*; do
  if [ -f "$cfg" ]; then
    sed -i '/CONFIG_XDP_SOCKETS/d' "$cfg"
    echo "CONFIG_XDP_SOCKETS=y" >> "$cfg"
  fi
done

# ---------------------------------------------------------
# 7. 向 .config 强制注入公共的软件包配置
# ---------------------------------------------------------
# [强制保护措施] 清理已被污染的 protobuf 缓存，为纯正源码编译 sing-box 扫清障碍
rm -rf dl/go-mod-cache/google.golang.org/protobuf* 2>/dev/null || true
rm -rf tmp/.packageinfo tmp/.targetinfo

if [ -f .config ]; then
  # 彻底清除关于 dae / daed / vmlinux-btf 遗留配置的干扰项
  sed -i '/CONFIG_PACKAGE_geoview/d' .config
  sed -i '/CONFIG_PACKAGE_v2ray-plugin/d' .config
  sed -i '/CONFIG_PACKAGE_xray-core/d' .config
  sed -i '/CONFIG_PACKAGE_dae=/d' .config
  sed -i '/CONFIG_PACKAGE_daed=/d' .config
  sed -i '/CONFIG_PACKAGE_luci-app-daede/d' .config
  sed -i '/CONFIG_PACKAGE_vmlinux-btf/d' .config
  sed -i '/CONFIG_PACKAGE_kmod-xdp-sockets-diag/d' .config

  cat >> .config <<EOF

# ========================
# 强制注入的公共插件配置
# ========================

CONFIG_PACKAGE_luci-app-easytier=y
CONFIG_PACKAGE_luci-theme-aurora=y
CONFIG_PACKAGE_luci-app-lucky=y
CONFIG_PACKAGE_luci-app-homeproxy=y
CONFIG_PACKAGE_sing-box=y

# --- Honk 引擎及其依赖 (全面替代 daed，且无编译报错) ---
CONFIG_PACKAGE_honk=y
CONFIG_PACKAGE_luci-app-honk=y
CONFIG_PACKAGE_ip-full=y
CONFIG_PACKAGE_ca-bundle=y
CONFIG_PACKAGE_kmod-nft-queue=y
CONFIG_PACKAGE_kmod-sched-core=y
CONFIG_PACKAGE_kmod-sched-bpf=y
CONFIG_PACKAGE_kmod-veth=y
CONFIG_PACKAGE_kmod-nft-tproxy=y

# --- 内核 eBPF / BTF 基础能力支持 ---
CONFIG_KERNEL_BPF_EVENTS=y
CONFIG_BPF_TOOLCHAIN=y
CONFIG_KERNEL_DEBUG_INFO=y
CONFIG_KERNEL_DEBUG_INFO_BTF=y

# --- 其他常规功能与依赖 ---
CONFIG_PACKAGE_luci-app-filemanager=y
CONFIG_PACKAGE_pbr=y
CONFIG_PACKAGE_luci-app-pbr=y
CONFIG_PACKAGE_vlmcsd=y
CONFIG_PACKAGE_luci-app-vlmcsd=y
CONFIG_PACKAGE_etherwake=y
CONFIG_PACKAGE_luci-app-wol=y
CONFIG_PACKAGE_ttyd=y
CONFIG_PACKAGE_luci-app-ttyd=y

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
