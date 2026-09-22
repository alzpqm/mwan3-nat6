include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-mwan3-nat6
PKG_VERSION:=0.0.49
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-only
PKG_BUILD_DEPENDS:=luci-base/host

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-mwan3-nat6
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=mwan3 IPv6 前綴 NAT 管理介面
  PKGARCH:=all
  DEPENDS:=+luci-base +mwan3-nat6
endef

define Package/luci-app-mwan3-nat6/description
  設定 WAN、更新監看、追蹤狀態及受保護的手動套用功能。
  本介面不會變更 mwan3 策略，也不使用防火牆 hook。
endef

define Package/luci-i18n-mwan3-nat6-en
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=mwan3 NAT6 英文語言包
  PKGARCH:=all
  DEPENDS:=+luci-app-mwan3-nat6
endef

define Package/luci-i18n-mwan3-nat6-en/description
  將預設正體中文的 mwan3 NAT6 LuCI 介面切換為英文。
endef

define Build/Compile
endef

define Package/luci-i18n-mwan3-nat6-en/install
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	$(INSTALL_BIN) ./po/en/luci-i18n-mwan3-nat6-en \
		$(1)/etc/uci-defaults/luci-i18n-mwan3-nat6-en
	$(STAGING_DIR_HOSTPKG)/bin/po2lmo ./po/en/mwan3-nat6.po \
		$(1)/usr/lib/lua/luci/i18n/mwan3-nat6.en.lmo
endef

define Package/luci-app-mwan3-nat6/install
	$(INSTALL_DIR) $(1)/usr/libexec/rpcd
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/mwan3-nat6
	$(INSTALL_BIN) ./root/usr/libexec/rpcd/luci.mwan3-nat6 \
		$(1)/usr/libexec/rpcd/luci.mwan3-nat6
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-mwan3-nat6.json \
		$(1)/usr/share/luci/menu.d/luci-app-mwan3-nat6.json
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-mwan3-nat6.json \
		$(1)/usr/share/rpcd/acl.d/luci-app-mwan3-nat6.json
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/mwan3-nat6/status.js \
		$(1)/www/luci-static/resources/view/mwan3-nat6/status.js
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/mwan3-nat6/settings.js \
		$(1)/www/luci-static/resources/view/mwan3-nat6/settings.js
endef

define Package/luci-app-mwan3-nat6/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache
	/etc/init.d/rpcd reload >/dev/null 2>&1 || :
}
exit 0
endef

$(eval $(call BuildPackage,luci-app-mwan3-nat6))
$(eval $(call BuildPackage,luci-i18n-mwan3-nat6-en))
