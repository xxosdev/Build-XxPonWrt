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

# 强制重置可能被误杀损坏的 Go 缓存
rm -rf dl/go-mod-cache

# ---------------------------------------------------------
# 0. libffi 兜底
# 2026-10-19 上游把 libffi 从 packages feed 移入核心仓库
#   (openwrt/packages 70ac3a84 "libffi: move to core repo")
# 而 ponwrt 核心树尚未同步该包，feeds 阶段会报
#   WARNING: No feed for source package 'libffi' found
# 进而 python3 编译 _ctypes 时 fatal error: ffi.h: No such file or directory
# 这里从上游核心仓库补回；将来 ponwrt 同步上游后目录已存在，自动跳过
# ---------------------------------------------------------
if [ ! -d package/libs/libffi ]; then
  echo "🔧 补回 libffi -> package/libs/libffi"
  mkdir -p package/libs/libffi
  curl -fsSL --retry 3 --retry-delay 2 \
    https://raw.githubusercontent.com/immortalwrt/immortalwrt/master/package/libs/libffi/Makefile \
    -o package/libs/libffi/Makefile || { echo "::error::libffi Makefile 下载失败"; exit 1; }
  echo "✅ libffi 已补回"
else
  echo "⏩ libffi 已存在于源码树，跳过"
fi

# ---------------------------------------------------------
# 1. 插件开关 (true 为开启拉取，false 为关闭)
# ---------------------------------------------------------
# 系统与硬件状态
ADD_AIROHA_NPU=true    # luci-app-airoha-npu: Airoha SoC 状态页 (NPU/CPU等)

# 科学上网与 DNS
ADD_DAEDE=true         # luci-app-daede & dae/daed 透明代理 (保留界面)
ADD_HONK=false         # luci-app-honk & honk: 上游 10-25 起资产未发布，暂停
ADD_PASSWALL2=true     # luci-app-passwall2: 科学上网
ADD_HOMEPROXY=true     # luci-app-homeproxy: 新增 Homeproxy 面板
ADD_MOSDNS=false       # luci-app-mosdns: DNS 防泄漏 + v2ray-geodata
ADD_SMARTDNS=false     # luci-app-smartdns: DNS 加速

# 网络与组网
ADD_LUCKY=true         # luci-app-lucky: 大吉 (DDNS/端口转发/Socat)
ADD_DDNS_GO=true       # luci-app-ddns-go: DDNS-GO 动态域名解析
ADD_LUCI_MESH=true     # luci-app-mesh: 802.11s Mesh 组网管理界面
ADD_TAILSCALE=false    # luci-app-tailscale: 虚拟局域网
ADD_EASYTIER=true      # luci-app-easytier: EasyTier 组网 (含 easytier 核心)

# 存储与界面
ADD_OPENLIST=false     # luci-app-openlist2: 网盘挂载 (已关闭)
ADD_THEME_AURORA=true  # luci-theme-aurora: Aurora 主题

# FTTR 全家桶（★仅 HM2004-DU / airoha_an7581 有意义；公开仓库 xxosdev，分支均为 main）
ADD_FTTR=true
ADD_FMCS=true          # h3c-fmcs 内核驱动 (kmod-h3c-fmcs)
ADD_FTTR_TOOLS=true    # openwrt-fttr 用户态工具 (Rust 包)
ADD_FMCS_FW=true       # h3c-fmcs-firmware 固件
ADD_FTTR_LUCI=true     # luci-app-fttr 管理界面
FTTR_PROFILE="${PROFILE:-h3c_hm2004-du}"

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

if [ "$ADD_DAEDE" = "true" ]; then
  clone https://github.com/kenzok8/openwrt-daede "$PKG_DIR/openwrt-daede" main
  find "$PKG_DIR/openwrt-daede" -name "Makefile" | while read -r mk; do
    sed -i 's/+dae//g' "$mk"
    sed -i 's/+daed//g' "$mk"
  done
  echo "✅ 已剔除 daede 界面对 dae/daed Go核心的编译依赖"
fi

# 【提取 Homeproxy 与 Sing-box】从 VIKINGYFY/packages 综合库中精准提取源码编译
if [ "$ADD_HOMEPROXY" = "true" ]; then
  echo "📥 正在拉取 VIKINGYFY 的 luci-app-homeproxy 与 sing-box 源码..."
  git clone --depth 1 https://github.com/VIKINGYFY/packages /tmp/vikingyfy_pkg
  rm -rf "$PKG_DIR/luci-app-homeproxy" "$PKG_DIR/sing-box"
  cp -r /tmp/vikingyfy_pkg/luci-app-homeproxy "$PKG_DIR/"
  cp -r /tmp/vikingyfy_pkg/sing-box "$PKG_DIR/"
  rm -rf /tmp/vikingyfy_pkg
  echo "✅ 已成功提取 luci-app-homeproxy 与 sing-box 源码"
fi

if [ "$ADD_PASSWALL2" = "true" ]; then
  clone https://github.com/Openwrt-Passwall/openwrt-passwall2 "$PKG_DIR/luci-app-passwall2" main

  # 仅针对 passwall2 进行核心依赖清洗，避免破坏 sing-box 和 homeproxy 的 Makefile
  find "$PKG_DIR/luci-app-passwall2" -name "Makefile" | while read -r mk; do
    sed -i 's/+geoview//g' "$mk"
    sed -i 's/+PACKAGE_geoview:geoview//g' "$mk"
    sed -i -E 's/\+PACKAGE_[^:]+:[^ \t\\]+//g' "$mk"
    sed -i 's/+v2ray-plugin//g; s/+xray-core//g; s/+sing-box//g' "$mk"
    sed -i '/define Package.*\/config/,/endef/d' "$mk"
  done
  echo "✅ 已强行清洗 PassWall2 面板的所有 Go 核心依赖"
fi

if [ "$ADD_MOSDNS" = "true" ]; then
  clone https://github.com/sbwml/luci-app-mosdns "$PKG_DIR/luci-app-mosdns" v5
  clone https://github.com/sbwml/v2ray-geodata "$PKG_DIR/v2ray-geodata" master
fi

if [ "$ADD_LUCKY" = "true" ]; then
  clone https://github.com/gdy666/luci-app-lucky "$PKG_DIR/luci-app-lucky" main
fi

if [ "$ADD_DDNS_GO" = "true" ]; then
  clone https://github.com/sirpdboy/luci-app-ddns-go "$PKG_DIR/luci-app-ddns-go" main
fi

# 【拉取 luci-app-mesh】802.11s Mesh 组网管理界面
if [ "$ADD_LUCI_MESH" = "true" ]; then
  clone https://github.com/xxosdev/luci-app-mesh "$PKG_DIR/luci-app-mesh" main
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

# 【拉取 FTTR 后端三件套 + luci-app-fttr】公开仓库 xxosdev（分支均为 main）
if [ "$ADD_FTTR" = "true" ] && [ "$FTTR_PROFILE" = "h3c_hm2004-du" ]; then
  FTTR_FEED_URL="https://github.com/xxosdev/openwrt-fttr"
  FTTR_FEED_BRANCH="${FTTR_FEED_BRANCH:-main}"
  FTTR_FEED_TMP="$(mktemp -d)/openwrt-fttr"

  clone "$FTTR_FEED_URL" "$FTTR_FEED_TMP" "$FTTR_FEED_BRANCH"

  if [ -d "$FTTR_FEED_TMP" ]; then
    FTTR_TOOLS_SRC=""
    for cand in fttr fttr-tools h3c-fttr-tools openwrt-fttr; do
      if [ -f "$FTTR_FEED_TMP/$cand/Makefile" ]; then
        FTTR_TOOLS_SRC="$cand"
        break
      fi
    done

    FTTR_FEED_PKGS=""
    [ "$ADD_FMCS" = "true" ]       && FTTR_FEED_PKGS="$FTTR_FEED_PKGS h3c-fmcs"
    [ "$ADD_FTTR_TOOLS" = "true" ] && [ -n "$FTTR_TOOLS_SRC" ] && FTTR_FEED_PKGS="$FTTR_FEED_PKGS $FTTR_TOOLS_SRC"
    [ "$ADD_FMCS_FW" = "true" ]    && FTTR_FEED_PKGS="$FTTR_FEED_PKGS h3c-fmcs-firmware"

    for p in $FTTR_FEED_PKGS; do
      if [ -f "$FTTR_FEED_TMP/$p/Makefile" ]; then
        case "$p" in
          fttr|fttr-tools|h3c-fttr-tools|openwrt-fttr) dst="openwrt-fttr" ;;
          *) dst="$p" ;;
        esac
        rm -rf "$PKG_DIR/$dst"
        cp -a "$FTTR_FEED_TMP/$p" "$PKG_DIR/$dst"
        echo "✅ 已拷贝 FTTR 后端包: $p -> $dst"
      else
        echo "❌ ::warning::未找到 $FTTR_FEED_TMP/$p/Makefile"
      fi
    done
    rm -rf "$FTTR_FEED_TMP"
  fi

  if [ "$ADD_FTTR_LUCI" = "true" ]; then
    FTTR_LUCI_URL="https://github.com/xxosdev/luci-app-fttr"
    FTTR_LUCI_BRANCH="${FTTR_LUCI_BRANCH:-main}"
    FTTR_TMP="$(mktemp -d)/fttr"

    clone "$FTTR_LUCI_URL" "$FTTR_TMP" "$FTTR_LUCI_BRANCH"
    FTTR_LUCI_SRC=""
    if [ -f "$FTTR_TMP/package/luci-app-fttr/Makefile" ]; then
      FTTR_LUCI_SRC="$FTTR_TMP/package/luci-app-fttr"
    elif [ -f "$FTTR_TMP/Makefile" ]; then
      FTTR_LUCI_SRC="$FTTR_TMP"
    fi

    if [ -n "$FTTR_LUCI_SRC" ]; then
      rm -rf "$PKG_DIR/luci-app-fttr"
      cp -a "$FTTR_LUCI_SRC" "$PKG_DIR/luci-app-fttr"
      rm -rf "$PKG_DIR/luci-app-fttr/.git"

      # ================= 新增：编译 luci-app-fttr 前端 (Rsbuild) =================
      echo "🔨 正在编译 luci-app-fttr 前端界面..."
      FTTR_UI_DIR=""
      for d in "$PKG_DIR/luci-app-fttr" "$PKG_DIR/luci-app-fttr/frontend" "$PKG_DIR/luci-app-fttr/ui" "$FTTR_TMP" "$FTTR_TMP/frontend"; do
        if [ -f "$d/package.json" ]; then
          FTTR_UI_DIR="$d"
          break
        fi
      done

      if [ -n "$FTTR_UI_DIR" ]; then
        pushd "$FTTR_UI_DIR" >/dev/null
        npm ci --no-audit --no-fund || npm install --no-audit --no-fund || { echo "❌ ::error::luci-app-fttr 前端依赖安装失败"; exit 1; }
        npm run build || { echo "❌ ::error::luci-app-fttr 前端 Rsbuild 编译失败"; exit 1; }
        rm -rf node_modules
        popd >/dev/null

        # 校验产物是否已生成到 htdocs 目录下，防止打包漏收
        if [ ! -f "$PKG_DIR/luci-app-fttr/htdocs/luci-static/resources/view/fttr/index.js" ]; then
          echo "❌ ::error::前端编译完成，但未在 htdocs/luci-static/resources/view/fttr/index.js 找到产物！"
          exit 1
        fi
        echo "✅ luci-app-fttr 前端编译完成，已确认生成 index.js"
      else
        echo "❌ ::error::未找到 package.json，无法编译前端"
        exit 1
      fi
      # =========================================================================

      # 补 BuildPackage 扫描标记，防止 scan.mk 漏收 Makefile
      FTTR_MK="$PKG_DIR/luci-app-fttr/Makefile"
      if ! grep -qE 'call[[:space:]]+(Build/DefaultTargets|BuildPackage|BuildContainer|BuildCompose|KernelPackage)' "$FTTR_MK"; then
        printf '\n# call BuildPackage - OpenWrt buildroot signature\n' >> "$FTTR_MK"
        echo "⚠️ 已补 luci-app-fttr Makefile BuildPackage 扫描标记"
      fi
      echo "✅ 已拷贝 luci-app-fttr"
    else
      echo "❌ ::warning::luci-app-fttr 拉取失败或缺少 Makefile"
    fi
    rm -rf "$FTTR_TMP"
  fi
fi

# ---------------------------------------------------------
# 5. 校验与全局依赖死刑清洗（关键防报错）
# ---------------------------------------------------------
if [ "$ADD_AIROHA_NPU" = "true" ] && [ ! -d "$PKG_DIR/luci-app-airoha-npu" ]; then
  echo "❌ ::error::luci-app-airoha-npu 源码未拉取成功，将导致配置被剔除！"
  exit 1
fi

if [ "$ADD_FTTR" = "true" ] && [ "$FTTR_PROFILE" = "h3c_hm2004-du" ]; then
  if [ "$ADD_FTTR_TOOLS" = "true" ] && [ ! -f feeds/packages/lang/rust/rust-package.mk ]; then
    echo "❌ ::error::缺少 feeds/packages/lang/rust/rust-package.mk，openwrt-fttr 无法编译/索引"
    exit 1
  fi
  if [ "$ADD_FTTR_LUCI" = "true" ] && [ ! -d "$PKG_DIR/luci-app-fttr" ]; then
    echo "❌ ::error::luci-app-fttr 未拉取成功，defconfig 会剔除配置！"
    exit 1
  fi
fi

# 物理删除官方源中会冲突报错的核心源码包（确保使用 custom 下编译的 sing-box 与 honk）
rm -rf feeds/packages/net/geoview
rm -rf feeds/packages/net/v2ray-plugin
rm -rf feeds/packages/net/xray-core
rm -rf feeds/packages/net/sing-box
rm -rf feeds/packages/net/openlist
rm -rf feeds/packages/net/dae
rm -rf feeds/packages/net/daed
rm -rf feeds/packages/net/honk
rm -rf package/feeds/packages/geoview
rm -rf package/feeds/packages/v2ray-plugin
rm -rf package/feeds/packages/xray-core
rm -rf package/feeds/packages/sing-box
rm -rf package/feeds/packages/openlist
rm -rf package/feeds/packages/dae
rm -rf package/feeds/packages/daed
rm -rf package/feeds/packages/honk

# 删除官方自带的重名面板，强迫系统使用我们在 custom 中清洗过的版本
rm -rf feeds/luci/applications/luci-app-homeproxy
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf package/feeds/luci/luci-app-homeproxy
rm -rf package/feeds/luci/luci-app-passwall

# 全局扫描清洗 Go 核心打包依赖（放行 honk 与 sing-box，因为它们作为源码正常编译打包）
echo "🔍 正在进行全局依赖强行清洗..."
find package/ feeds/ -name "Makefile" | xargs sed -i 's/+xray-core//g; s/+v2ray-plugin//g; s/+geoview//g; s/+dae//g; s/+daed//g; s/+PACKAGE_geoview:geoview//g' 2>/dev/null

if [ -n "$(ls -A "$PKG_DIR" 2>/dev/null)" ]; then
  ./scripts/feeds update -i 2>/dev/null || true
  ./scripts/feeds install -a >/dev/null 2>&1 || true

  if [ "$ADD_FTTR" = "true" ] && [ "$FTTR_PROFILE" = "h3c_hm2004-du" ] && [ -f tmp/.packageinfo ]; then
    for pkg in kmod-h3c-fmcs h3c-fmcs-firmware openwrt-fttr luci-app-fttr; do
      grep -qx "Package: $pkg" tmp/.packageinfo || echo "⚠️ 注意: $pkg 未出现在 tmp/.packageinfo 中"
    done
  fi

  echo "=========================================="
  echo "✅ package/custom 拉取清单："
  ls -1 "$PKG_DIR"
else
  echo "ℹ️ 未启用任何第三方插件"
fi

echo "=========================================="
echo "🎉 diy-part1.sh 执行完毕"
