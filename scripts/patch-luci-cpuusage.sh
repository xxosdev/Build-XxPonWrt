#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
set -uo pipefail

PONWRT_DIR="${PONWRT_DIR:-.}"

OLD_FIX="popen('top -n1"
NEW_FIX="popen('sh /sbin/cpuusage')"
NEW_CALL="${NEW_FIX};"

if ! cd "$PONWRT_DIR" 2>/dev/null; then
	echo "::warning::PONWRT_DIR 无效（$PONWRT_DIR），跳过 CPU 使用率行定制"
	exit 0
fi

echo "=========================================="
echo "概览页 CPU 使用率行：改指 /sbin/cpuusage"
echo "=========================================="

if [ ! -f files/sbin/cpuusage ]; then
	echo "::warning::files/sbin/cpuusage 不存在（files/ 还没被拷进源码树？）"
	echo "::warning::跳过补丁，概览页「CPU 使用率（%）」维持原始显示"
	exit 0
fi
echo "✅ 数据源: files/sbin/cpuusage  ->  /sbin/cpuusage"

TARGETS=()
while IFS= read -r f; do
	[ -n "$f" ] && TARGETS+=("$f")
done < <(find -L feeds -type f -path '*rpcd/ucode/luci' 2>/dev/null | sort)

if [ "${#TARGETS[@]}" -eq 0 ]; then
	echo "::warning::feeds/ 下找不到 *rpcd/ucode/luci（LuCI 版本 / fork 不同？）"
	echo "::warning::概览页「CPU 使用率（%）」维持原始显示（单个总占用率）"
	exit 0
fi

patched=0

for f in "${TARGETS[@]}"; do

	if ! grep -q 'getCPUUsage' "$f" 2>/dev/null; then
		echo "  -  跳过（无 getCPUUsage）: $f"
		continue
	fi

	if grep -qF "$NEW_FIX" "$f"; then
		echo "  =  已是目标状态，跳过: $f"
		patched=$((patched + 1))
		continue
	fi

	if ! grep -qF "$OLD_FIX" "$f"; then
		echo "::warning::$f 里有 getCPUUsage，但没有预期的 top 命令行，未改动"
		echo "          （上游改了实现？请同步本脚本的 OLD_FIX/NEW_FIX）"
		continue
	fi

	echo "  目标: $f"
	echo "  修改前: $(grep -m1 -nF "$OLD_FIX" "$f" | sed 's/^[[:space:]]*//')"

	sed -i "s@popen('top -n1[^;]*;@${NEW_CALL}@" "$f"

	if grep -qF "$NEW_FIX" "$f"; then
		echo "  修改后: $(grep -m1 -nF "$NEW_FIX" "$f" | sed 's/^[[:space:]]*//')"
		echo "  ✅ 已改指"
		patched=$((patched + 1))
	else
		echo "::warning::替换没有生效: $f"
	fi
done

if [ "$patched" -eq 0 ]; then
	echo "::warning::没有任何目标被改动，概览页 CPU 行维持原始显示"
	exit 0
fi

echo "------------------------------------------"
echo "共处理 $patched 处；概览页「CPU 使用率（%）」将显示："
echo "  USR: x% SYS: y% · C0 u%/s% C1 u%/s% ..."
echo "------------------------------------------"
echo "🎉 patch-luci-cpuusage.sh 执行完毕"

exit 0
