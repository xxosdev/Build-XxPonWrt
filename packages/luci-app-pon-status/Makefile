# SPDX-License-Identifier: Apache-2.0

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI PON optics, port rate and connection counters (overview card)
LUCI_URL:=https://github.com/pbs05/openwrt-pon-userspace
LUCI_DEPENDS:=+luci-base +luci-mod-status +airoha-ponctl +jsonfilter +rpcd-mod-file
PKG_VERSION:=0.4.6
PKG_RELEASE:=4

PKG_LICENSE:=Apache-2.0

# ponstat-conn 在 git 里已是 0755，luci.mk 用 cp -pR 装到 root/ 会保留权限；
# 这里再兜一次，防止某些检出方式丢了执行位。
define Package/luci-app-pon-status/postinst
[ -n "$${IPKG_INSTROOT}" ] || { \
	chmod 0755 /usr/sbin/ponstat-conn 2>/dev/null; \
	rm -f /tmp/luci-indexcache.*; \
	rm -rf /tmp/luci-modulecache/; \
	/etc/init.d/rpcd reload 2>/dev/null; \
	exit 0; \
}
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage: feed scanner marker; luci.mk generates the package rules.
