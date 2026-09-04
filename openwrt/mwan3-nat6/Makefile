include $(TOPDIR)/rules.mk

PKG_NAME:=mwan3-nat6
PKG_VERSION:=0.0.47
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-only

include $(INCLUDE_DIR)/package.mk

define Package/mwan3-nat6
  SECTION:=net
  CATEGORY:=Network
  TITLE:=mwan3 IPv6 前綴 NAT 工具
  PKGARCH:=all
  DEPENDS:=+ip-full +jsonfilter +netifd +nftables +kmod-nft-nat +uci +mwan3
endef

define Package/mwan3-nat6/description
  供多 WAN mwan3 連線分流使用的 IPv6 前綴 NAT 工具。
  本套件不會安裝防火牆 include 或 hotplug hook；獨立監看服務與路由器
  本機的裝置綁定相容規則均為選用功能，預設不啟用。
endef

define Build/Compile
endef

define Package/mwan3-nat6/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/usr
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_DIR) $(1)/usr/share/doc/mwan3-nat6
	$(INSTALL_CONF) ./files/etc/config/mwan3-nat6 $(1)/etc/config/mwan3-nat6
	$(INSTALL_BIN) ./files/etc/init.d/mwan3-nat6 $(1)/etc/init.d/mwan3-nat6
	$(INSTALL_BIN) ./files/usr/nft-nat6.sh $(1)/usr/nft-nat6.sh
	$(INSTALL_BIN) ./files/usr/sbin/mwan3-nat6-watch $(1)/usr/sbin/mwan3-nat6-watch
	$(INSTALL_DATA) ./files/usr/share/doc/mwan3-nat6/NAT6_HANDOFF.md \
		$(1)/usr/share/doc/mwan3-nat6/NAT6_HANDOFF.md
endef

define Package/mwan3-nat6/conffiles
/etc/config/mwan3-nat6
endef

define Package/mwan3-nat6/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/mwan3-nat6 enable >/dev/null 2>&1 || :
	/etc/init.d/mwan3-nat6 restart >/dev/null 2>&1 || :
}
exit 0
endef

define Package/mwan3-nat6/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || /usr/nft-nat6.sh cleanup-policy >/dev/null 2>&1 || :
exit 0
endef

$(eval $(call BuildPackage,mwan3-nat6))
