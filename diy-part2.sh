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
# 修改默认主机名 (例如从 OpenWrt 改为 PONWrt)
# sed -i 's/OpenWrt/PONWrt/g' package/base-files/files/bin/config_generate

# 修改默认 IP 地址 (例如从 192.168.1.1 改为 192.168.2.1)
# sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate

# 修改默认 WIFI 名称 (将 OpenWrt 修改为你想要的名称，针对大部分无线驱动有效)
# sed -i 's/ssid=OpenWrt/ssid=PONWrt_WIFI/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh
# sed -i 's/ssid="OpenWrt"/ssid="PONWrt_WIFI"/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh


# ---------------------------------------------------------
# 2. 修改 config_generate 的默认值（首次开机生成的 /etc/config/system）
# ---------------------------------------------------------
CFG="package/base-files/files/bin/config_generate"

if [ -f "$CFG" ]; then
  # 原值形如：set system.@system[-1].timezone='UTC'
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
# 4. 补上亚洲时区数据库包（LuCI 显示与时区切换需要）
# ---------------------------------------------------------
if [ -f .config ]; then
  sed -i '/^CONFIG_PACKAGE_zoneinfo-asia=/d; /^# CONFIG_PACKAGE_zoneinfo-asia is not set/d' .config
  echo "CONFIG_PACKAGE_zoneinfo-asia=y    # 亚洲时区数据库（中国时区需要）" >> .config
  echo "✅ zoneinfo-asia 已加入 .config"
fi

# ---------------------------------------------------------
# 5. 向 .config 强制注入公共的软件包配置
# ---------------------------------------------------------
if [ -f .config ]; then
  cat >> .config <<EOF

# ========================
# 强制注入的公共插件配置
# ========================

# --- 1. 由 diy-part1.sh 拉取的第三方插件 ---
# EasyTier 组网
CONFIG_PACKAGE_luci-app-easytier=y
# Aurora 主题
CONFIG_PACKAGE_luci-theme-aurora=y

# --- 2. 官方 feeds 源自带的插件 (无需拉取，直接开启) ---
# 官方源文件管理器
CONFIG_PACKAGE_luci-app-filemanager=y

# 策略路由 (多线分流 / PBR)
CONFIG_PACKAGE_pbr=y
CONFIG_PACKAGE_luci-app-pbr=y

# KMS 激活服务
CONFIG_PACKAGE_vlmcsd=y
CONFIG_PACKAGE_luci-app-vlmcsd=y

# 网络唤醒 (WOL)
CONFIG_PACKAGE_etherwake=y
CONFIG_PACKAGE_luci-app-wol=y

# TTYD 网页终端
CONFIG_PACKAGE_ttyd=y
CONFIG_PACKAGE_luci-app-ttyd=y
EOF
  echo "✅ 公共软件包配置已注入 .config"
else
  echo "::warning::未找到 .config 文件，跳过公共软件包注入"
fi

echo "🎉 diy-part2.sh 执行完毕"
