include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-mwan3-nat6
PKG_VERSION:=0.0.28
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-only

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-mwan3-nat6
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for mwan3 IPv6 prefix NAT
  PKGARCH:=all
  DEPENDS:=+luci-base +mwan3-nat6
endef

define Package/luci-app-mwan3-nat6/description
  Configure WAN membership, renewal monitoring, tracker status, and guarded
  manual apply. The page does not change mwan3 policies or use firewall hooks.
endef

define Build/Compile
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
