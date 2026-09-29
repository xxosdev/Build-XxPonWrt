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
ADD_DAEDE=false        # 【彻底关闭】放弃 daed 避免汇编编译报错，全面改用 honk
ADD_HONK=true          # luci-app-honk & honk: dae的下一代演进版 (已证实可成功编译)
ADD_PASSWALL2=true     # luci-app-passwall2: 科学上网
ADD_HOMEPROXY=true     # luci-app-homeproxy: 新增 Homeproxy 面板
ADD_MOSDNS=false       # luci-app-mosdns: DNS 防泄漏 + v2ray-geodata
ADD_SMARTDNS=false     # luci-app-smartdns: DNS 加速

# 网络与组网
ADD_LUCKY=true         # luci-app-lucky: 大吉 (DDNS/端口转发/Socat)
ADD_TAILSCALE=false    # luci-app-tailscale: 虚拟局域网
ADD_EASYTIER=true      # luci-app-easytier: EasyTier 组网

# 存储与界面
ADD_OPENLIST=false     # luci-app-openlist2: 网盘挂载 (已关闭)
ADD_THEME_AURORA=true  # luci-theme-aurora: Aurora 主题

# ---------------------------------------------------------
# 2. 复制本地自带包
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

# 【提取 Honk】从 small 综合库中单独精准提取 honk 源码
if [ "$ADD_HONK" = "true" ]; then
  echo "📥 正在拉取 honk 与 luci-app-honk..."
  git clone --depth 1 https://github.com/kenzok8/small /tmp/small_pkg
  cp -r /tmp/small_pkg/honk "$PKG_DIR/"
  cp -r /tmp/small_pkg/luci-app-honk "$PKG_DIR/"
  rm -rf /tmp/small_pkg
  echo "✅ 已成功提取 honk 与 luci-app-honk"
fi

# 【提取 Homeproxy 与配套的 sing-box 源码】
if [ "$ADD_HOMEPROXY" = "true" ]; then
    git clone --depth=1 --filter=blob:none --sparse https://github.com/VIKINGYFY/packages "$PKG_DIR/temp-packages"
    (
        cd "$PKG_DIR/temp-packages" || exit 1
        git sparse-checkout set luci-app-homeproxy sing-box
    )
    mv "$PKG_DIR/temp-packages/luci-app-homeproxy" "$PKG_DIR/luci-app-homeproxy"
    mv "$PKG_DIR/temp-packages/sing-box" "$PKG_DIR/sing-box"
    rm -rf "$PKG_DIR/temp-packages"

    # [纯源码编译核心修复] 彻底剔除 sing-box 中导致 Go Protobuf 报错的 with_tailscale
    if [ -f "$PKG_DIR/sing-box/Makefile" ]; then
        sed -i 's/,with_tailscale//g' "$PKG_DIR/sing-box/Makefile"
        sed -i 's/with_tailscale,//g' "$PKG_DIR/sing-box/Makefile"
        sed -i 's/with_tailscale//g' "$PKG_DIR/sing-box/Makefile"
        echo "✅ 已剔除 sing-box 中冲突的 with_tailscale 编译标签，确保顺利源码编译"
    fi
    echo "✅ 已拉取 VIKINGYFY 的 luci-app-homeproxy 与配套 sing-box 源码"
fi

if [ "$ADD_PASSWALL2" = "true" ]; then
  clone https://github.com/Openwrt-Passwall/openwrt-passwall2 "$PKG_DIR/luci-app-passwall2" main

  find "$PKG_DIR/luci-app-passwall2" -name "Makefile" | while read -r mk; do
    sed -i 's/+geoview//g' "$mk"
    sed -i 's/+PACKAGE_geoview:geoview//g' "$mk"
    sed -i -E 's/\+PACKAGE_[^:]+:[^ \t\\]+//g' "$mk"
    sed -i 's/+v2ray-plugin//g; s/+xray-core//g' "$mk"
    sed -i '/define Package.*\/config/,/endef/d' "$mk"
  done
  echo "✅ 已清洗 passwall2 面板的 Go 核心依赖"
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
# 5. 校验与全局依赖死刑清洗
# ---------------------------------------------------------
if [ "$ADD_AIROHA_NPU" = "true" ] && [ ! -d "$PKG_DIR/luci-app-airoha-npu" ]; then
  echo "❌ ::error::luci-app-airoha-npu 源码未拉取成功，将导致配置被剔除！"
  exit 1
fi

# 物理删除系统中一切可能引发冲突和错误的老旧源码
rm -rf "$PKG_DIR/openwrt-daede"
rm -rf feeds/packages/net/geoview feeds/packages/net/v2ray-plugin feeds/packages/net/xray-core feeds/packages/net/sing-box feeds/packages/net/dae feeds/packages/net/daed feeds/packages/net/honk
rm -rf package/feeds/packages/geoview package/feeds/packages/v2ray-plugin package/feeds/packages/xray-core package/feeds/packages/sing-box package/feeds/packages/dae package/feeds/packages/daed package/feeds/packages/honk

# 删除官方自带的重名面板
rm -rf feeds/luci/applications/luci-app-homeproxy feeds/luci/applications/luci-app-passwall
rm -rf package/feeds/luci/luci-app-homeproxy package/feeds/luci/luci-app-passwall

# 全局扫描清洗 Go 核心打包依赖（完全保留 sing-box 和 honk，因为要源码编译）
echo "🔍 正在进行全局依赖强行清洗..."
find package/ feeds/ -name "Makefile" 2>/dev/null | xargs sed -i 's/+xray-core//g; s/+v2ray-plugin//g; s/+geoview//g; s/+dae//g; s/+daed//g; s/+PACKAGE_geoview:geoview//g' 2>/dev/null || true

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
