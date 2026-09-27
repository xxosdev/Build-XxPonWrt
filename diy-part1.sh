#!/bin/bash
# ================================================================
# diy-part1.sh —— 拉取可选插件源码到 package/custom
# 运行阶段: feeds 安装之后、加载 .config 之前
# ================================================================

echo "=========================================="
echo "🚀 开始拉取可选插件源码 (diy-part1.sh)"
echo "=========================================="

PKG_DIR="package/custom"
mkdir -p "$PKG_DIR"

# ---------------------------------------------------------
# 1. 插件开关 (true 为开启拉取，false 为关闭)
# ---------------------------------------------------------
# 系统与硬件状态
ADD_AIROHA_NPU=true    # luci-app-airoha-npu: Airoha SoC 状态页 (NPU/CPU等)

# 科学上网与 DNS
ADD_DAEDE=true        # luci-app-daede & dae/daed 透明代理
ADD_PASSWALL2=true     # luci-app-passwall2: 科学上网 (核心精简请在 diy-part2.sh 配置)
ADD_MOSDNS=false       # luci-app-mosdns: DNS 防泄漏 + v2ray-geodata
ADD_SMARTDNS=false     # luci-app-smartdns: DNS 加速

# 网络与组网
ADD_LUCKY=true        # luci-app-lucky: 大吉 (DDNS/端口转发/Socat)
ADD_TAILSCALE=false    # luci-app-tailscale: 虚拟局域网
ADD_EASYTIER=true      # luci-app-easytier: EasyTier 组网 (第三方源)

# 存储与界面
ADD_OPENLIST=false     # luci-app-openlist2: 网盘挂载
ADD_THEME_AURORA=true  # luci-theme-aurora: Aurora 主题 (第三方源)

# 注: luci-app-filemanager 等官方源已有的包，无需在此拉取，直接在 diy-part2.sh 启用即可。

# ---------------------------------------------------------
# 2. 复制本地自带包
# 说明: 将 CI 仓库自带的包（如 luci-app-pon-status）拷贝进编译目录
# ---------------------------------------------------------
LOCAL_PKG_DIR="${GITHUB_WORKSPACE}/packages"
if [ -d "$LOCAL_PKG_DIR" ]; then
  for p in "$LOCAL_PKG_DIR"/*; do
    [ -d "$p" ] || continue
    rm -rf "$PKG_DIR/$(basename "$p")"
    cp -r "$p" "$PKG_DIR/"
    echo "✅ 本地包已载入: $(basename "$p")"
  done
fi

# ---------------------------------------------------------
# 3. 源码拉取函数
# ---------------------------------------------------------
clone() {
  local url="$1" dir="$2" br="$3"
  [ -d "$dir" ] && { echo "⏩ 已存在，跳过: $dir"; return 0; }
  if [ -n "$br" ]; then
    git clone --depth 1 -b "$br" "$url" "$dir"
  else
    git clone --depth 1 "$url" "$dir"
  fi
  [ $? -eq 0 ] && echo "✅ 克隆成功: $dir" || echo "❌ ::warning::克隆失败 $url"
}

# ---------------------------------------------------------
# 4. 执行克隆任务
# ---------------------------------------------------------
if [ "$ADD_AIROHA_NPU" = "true" ]; then
  clone https://github.com/luanmuc/luci-app-airoha-npu "$PKG_DIR/luci-app-airoha-npu" main
fi

if [ "$ADD_DAEDE" = "true" ]; then
  clone https://github.com/kenzok8/openwrt-daede "$PKG_DIR/openwrt-daede" main
fi

if [ "$ADD_PASSWALL2" = "true" ]; then
  clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages "$PKG_DIR/openwrt-passwall-packages" main
  clone https://github.com/Openwrt-Passwall/openwrt-passwall2 "$PKG_DIR/luci-app-passwall2" main
fi

if [ "$ADD_MOSDNS" = "true" ]; then
  clone https://github.com/sbwml/luci-app-mosdns "$PKG_DIR/luci-app-mosdns" v5
  clone https://github.com/sbwml/v2ray-geodata "$PKG_DIR/v2ray-geodata" master
fi

if [ "$ADD_LUCKY" = "true" ]; then
  clone https://github.com/gdy666/luci-app-lucky "$PKG_DIR/luci-app-lucky" main
fi

if [ "$ADD_TAILSCALE" = "true" ]; then
  clone https://github.com/asvow/luci-app-tailscale "$PKG_DIR/luci-app-tailscale" main
fi

if [ "$ADD_OPENLIST" = "true" ]; then
  clone https://github.com/sbwml/luci-app-openlist2 "$PKG_DIR/luci-app-openlist2" main
fi

if [ "$ADD_SMARTDNS" = "true" ]; then
  clone https://github.com/pymumu/luci-app-smartdns "$PKG_DIR/luci-app-smartdns" master
  clone https://github.com/pymumu/smartdns "$PKG_DIR/smartdns" master
fi

if [ "$ADD_EASYTIER" = "true" ]; then
  clone https://github.com/EasyTier/luci-app-easytier "$PKG_DIR/luci-app-easytier" main
fi

if [ "$ADD_THEME_AURORA" = "true" ]; then
  clone https://github.com/eamonxg/luci-theme-aurora "$PKG_DIR/luci-theme-aurora" master
fi

# ---------------------------------------------------------
# 5. 校验与更新索引
# ---------------------------------------------------------
# 校验默认必须开启的包（防止 defconfig 剔除依赖）
if [ "$ADD_AIROHA_NPU" = "true" ] && [ ! -d "$PKG_DIR/luci-app-airoha-npu" ]; then
  echo "❌ ::error::luci-app-airoha-npu 源码未拉取成功，将导致配置被剔除！"
  exit 1
fi

# 更新环境包索引，使新克隆的包能被 make menuconfig 读取
if [ -n "$(ls -A "$PKG_DIR" 2>/dev/null)" ]; then
  ./scripts/feeds update -i 2>/dev/null || true
  ./scripts/feeds install -a >/dev/null 2>&1 || true
  echo "=========================================="
  echo "✅ package/custom 拉取清单："
  ls -1 "$PKG_DIR"
else
  echo "ℹ️ 未启用任何第三方插件"
fi

echo "=========================================="
echo "🎉 diy-part1.sh 执行完毕"
