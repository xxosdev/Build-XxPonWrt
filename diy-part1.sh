#!/bin/bash
# ================================================================
# diy-part1.sh —— 只做一件事：拉取可选插件到 package/custom
# 运行目录: ponwrt 源码根目录（feeds 安装之后、加载 .config 之前）
#
# 用法：把需要的插件开关改成 true，再到 configs/<机型>.config 里
#       把对应 "# CONFIG_PACKAGE_xxx is not set" 改成 "=y"
# ================================================================

echo "=========================================="
echo "拉取可选插件 (diy-part1.sh)"
echo "=========================================="

PKG_DIR="package/custom"
mkdir -p "$PKG_DIR"

# ---------------------------------------------------------
# 插件开关
# 默认开启：Airoha SoC 状态页（config 里已 =y，必须拉否则 defconfig 会剔除）
#
# 温度不再用 luci-app-temp-status —— 由 autocore 的 /sbin/tempinfo 提供，
# 见 files/sbin/tempinfo（概览页「温度」行：CPU / WiFi / PON 温度 + 光功率）
# ---------------------------------------------------------
ADD_AIROHA_NPU=true    # luci-app-airoha-npu：Airoha SoC 状态页（NPU/CPU/Frame Engine/PPE）

# ⚠ 上游已迁到 Openwrt-Passwall 组织：xiaorouji/openwrt-passwall 仓库已 404 不存在，
#   passwall2 也独立成仓库。旧 URL 一开就克隆失败，别改回去。
ADD_PASSWALL2=false    # luci-app-passwall2（含依赖源）⚠ aarch64 下默认连带编 Rust + Go
ADD_MOSDNS=false       # luci-app-mosdns + v2ray-geodata
ADD_LUCKY=false        # luci-app-lucky（DDNS + socat）
ADD_TAILSCALE=false    # luci-app-tailscale
ADD_OPENLIST=false     # luci-app-openlist2（alist/openlist 挂载）
ADD_SMARTDNS=false     # luci-app-smartdns

# ---------------------------------------------------------
# 本地包：CI 仓库自带的包（不在任何 feed 里），拷进 package/custom
# 目前有 luci-app-pon-status：把 PON 温度/收发光功率显示在概览页
# ---------------------------------------------------------
LOCAL_PKG_DIR="${GITHUB_WORKSPACE}/packages"
if [ -d "$LOCAL_PKG_DIR" ]; then
  for p in "$LOCAL_PKG_DIR"/*; do
    [ -d "$p" ] || continue
    # 目录名必须等于包名（luci.mk: PKG_NAME ?= $(notdir ${CURDIR})）
    rm -rf "$PKG_DIR/$(basename "$p")"
    cp -r "$p" "$PKG_DIR/"
    echo "✅ 本地包: $(basename "$p")"
  done
fi

clone() {  # clone <url> <dir> [branch]
  local url="$1" dir="$2" br="$3"
  [ -d "$dir" ] && { echo "已存在，跳过: $dir"; return 0; }
  if [ -n "$br" ]; then
    git clone --depth 1 -b "$br" "$url" "$dir"
  else
    git clone --depth 1 "$url" "$dir"
  fi
  [ $? -eq 0 ] && echo "✅ $dir" || echo "::warning::克隆失败 $url"
}

# --- Airoha SoC 状态页（NPU 卸载 / CPU 频率 / Frame Engine / PPE 流表）---
# 包名由目录名决定（luci.mk: PKG_NAME ?= $(notdir ${CURDIR})），
# 目录必须是 luci-app-airoha-npu，否则 config 里的符号对不上。
if [ "$ADD_AIROHA_NPU" = "true" ]; then
  clone https://github.com/luanmuc/luci-app-airoha-npu "$PKG_DIR/luci-app-airoha-npu" main
fi

# --- passwall2 ---
# 直接 clone 到 package/custom/luci-app-passwall2：luci.mk 用 $(notdir ${CURDIR}) 取包名，
# 目录名必须等于包名（拿仓库名当目录名会符号对不上）
# ⚠ aarch64 下 Makefile 的 INCLUDE_Shadowsocks_Rust_Client / Basic_Core_All 都是 default y，
#   会自动带出 Rust 工具链（shadowsocks-rust: rust/host）和 Go 工具链（xray + sing-box）。
#   想省时间在 configs/<机型>.config 里显式写 n：
#     # CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_Shadowsocks_Rust_Client is not set
#     CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_Xray=y
if [ "$ADD_PASSWALL2" = "true" ]; then
  clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages "$PKG_DIR/openwrt-passwall-packages" main
  clone https://github.com/Openwrt-Passwall/openwrt-passwall2 "$PKG_DIR/luci-app-passwall2" main
fi

# --- mosdns ---
if [ "$ADD_MOSDNS" = "true" ]; then
  clone https://github.com/sbwml/luci-app-mosdns "$PKG_DIR/luci-app-mosdns" v5
  clone https://github.com/sbwml/v2ray-geodata "$PKG_DIR/v2ray-geodata" master
fi

# --- lucky ---
if [ "$ADD_LUCKY" = "true" ]; then
  clone https://github.com/sirpdboy/luci-app-lucky "$PKG_DIR/luci-app-lucky" main
fi

# --- tailscale ---
if [ "$ADD_TAILSCALE" = "true" ]; then
  clone https://github.com/asvow/luci-app-tailscale "$PKG_DIR/luci-app-tailscale" main
fi

# --- openlist2 ---
if [ "$ADD_OPENLIST" = "true" ]; then
  clone https://github.com/sbwml/luci-app-openlist2 "$PKG_DIR/luci-app-openlist2" main
fi

# --- smartdns ---
if [ "$ADD_SMARTDNS" = "true" ]; then
  clone https://github.com/pymumu/luci-app-smartdns "$PKG_DIR/luci-app-smartdns" master
  clone https://github.com/pymumu/smartdns "$PKG_DIR/smartdns" master
fi

# ---------------------------------------------------------
# 校验：默认开启的两个插件必须拉到，否则 defconfig 会静默剔除，
#       编出来的固件缺少状态页还不易察觉
# ---------------------------------------------------------
if [ "$ADD_AIROHA_NPU" = "true" ] && [ ! -d "$PKG_DIR/luci-app-airoha-npu" ]; then
  echo "::error::luci-app-airoha-npu 未拉到，config 里的 =y 会被 defconfig 剔除"
  exit 1
fi

# ---------------------------------------------------------
# 让新包进入索引
# ---------------------------------------------------------
if [ -n "$(ls -A "$PKG_DIR" 2>/dev/null)" ]; then
  ./scripts/feeds update -i 2>/dev/null || true
  ./scripts/feeds install -a >/dev/null 2>&1 || true
  echo "✅ package/custom 内容："
  ls -1 "$PKG_DIR"
else
  echo "未启用任何第三方插件"
fi

echo "🎉 diy-part1.sh 执行完毕"
