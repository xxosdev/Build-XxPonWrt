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
# 3. uci-defaults：即使保留了旧配置也强制刷成中国时区
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
echo "✅ uci-defaults 时区脚本已写入"

# ---------------------------------------------------------
# 4. 补上亚洲时区数据库包
# ---------------------------------------------------------
if [ -f .config ]; then
  sed -i '/^CONFIG_PACKAGE_zoneinfo-asia=/d; /^# CONFIG_PACKAGE_zoneinfo-asia is not set/d' .config
  echo "CONFIG_PACKAGE_zoneinfo-asia=y    # 亚洲时区数据库（中国时区需要）" >> .config
  echo "✅ zoneinfo-asia 已加入 .config"
fi

# ---------------------------------------------------------
# 5. 向 .config 强制注入公共的软件包配置 (严禁修改下方格式缩进)
# ---------------------------------------------------------
if [ -f .config ]; then
  cat >> .config <<EOF

# ========================
# 强制注入的公共插件配置
# ========================

# --- 由 diy-part1.sh 拉取的第三方插件 ---
CONFIG_PACKAGE_luci-app-easytier=y
CONFIG_PACKAGE_luci-theme-aurora=y

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

# --- Passwall 2 主程序与精确核心配置 ---
CONFIG_PACKAGE_luci-app-passwall2=y

# 强制关闭全量核心 (防止带出所有依赖)
# CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_All is not set

# 开启 Xray 和 Sing-box 核心
CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_Xray=y
CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_Sing_Box=y

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
