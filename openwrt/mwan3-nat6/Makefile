include $(TOPDIR)/rules.mk

PKG_NAME:=mwan3-nat6
PKG_VERSION:=0.0.1
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-only

include $(INCLUDE_DIR)/package.mk

define Package/mwan3-nat6
  SECTION:=net
  CATEGORY:=Network
  TITLE:=mwan3 IPv6 prefix NAT helper
  PKGARCH:=all
  DEPENDS:=+jsonfilter +netifd +nftables +kmod-nft-nat +uci
endef

define Package/mwan3-nat6/description
  IPv6 prefix NAT helper for multi-WAN mwan3 connection aggregation.
  The package does not install firewall includes, routes, marks, or hotplug
  hooks. Apply the script manually after all configured IPv6 WANs are ready.
endef

define Build/Compile
endef

define Package/mwan3-nat6/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/usr
	$(INSTALL_DIR) $(1)/usr/share/doc/mwan3-nat6
	$(INSTALL_CONF) ./files/etc/config/mwan3-nat6 $(1)/etc/config/mwan3-nat6
	$(INSTALL_BIN) ./files/usr/nft-nat6.sh $(1)/usr/nft-nat6.sh
	$(INSTALL_DATA) ./files/usr/share/doc/mwan3-nat6/NAT6_HANDOFF.md \
		$(1)/usr/share/doc/mwan3-nat6/NAT6_HANDOFF.md
endef

define Package/mwan3-nat6/conffiles
/etc/config/mwan3-nat6
endef

$(eval $(call BuildPackage,mwan3-nat6))
