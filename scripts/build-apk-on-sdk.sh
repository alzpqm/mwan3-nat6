#!/bin/sh

set -eu

PROJECT_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
SDK_DIR="${SDK_DIR:?set SDK_DIR to an OpenWrt 25.12+ SDK directory}"
OUTPUT_DIR="${1:?usage: SDK_DIR=/path/to/sdk $0 OUTPUT_DIR}"
APK="$SDK_DIR/staging_dir/host/bin/apk"
PO2LMO="$SDK_DIR/staging_dir/hostpkg/bin/po2lmo"
SIGN_KEY="${SIGN_KEY:-$SDK_DIR/private-key.pem}"
VERSION="$(sed -n '1p' "$PROJECT_ROOT/VERSION")"
CORE_APK="$OUTPUT_DIR/mwan3-nat6-$VERSION-r1.apk"
LUCI_APK="$OUTPUT_DIR/luci-app-mwan3-nat6-$VERSION-r1.apk"
I18N_APK="$OUTPUT_DIR/luci-i18n-mwan3-nat6-en-$VERSION-r1.apk"
BUILD_ROOT=''

cleanup() {
	[ -z "$BUILD_ROOT" ] || rm -rf "$BUILD_ROOT"
}

fail() {
	printf '%s\n' "build-apk-on-sdk: ERROR: $*" >&2
	exit 1
}

[ -x "$APK" ] || fail "SDK apk tool is missing: $APK"
[ -x "$PO2LMO" ] || fail "SDK po2lmo tool is missing: $PO2LMO"
[ -r "$SIGN_KEY" ] || fail "SDK signing key is missing: $SIGN_KEY"
mkdir -p "$OUTPUT_DIR"
[ ! -e "$CORE_APK" ] || fail "output already exists: $CORE_APK"
[ ! -e "$LUCI_APK" ] || fail "output already exists: $LUCI_APK"
[ ! -e "$I18N_APK" ] || fail "output already exists: $I18N_APK"

BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mwan3-nat6-apk.XXXXXX")" ||
	fail 'cannot create build directory'
CORE_ROOT="$BUILD_ROOT/core-root"
LUCI_ROOT="$BUILD_ROOT/luci-root"
I18N_ROOT="$BUILD_ROOT/i18n-root"
SCRIPT_ROOT="$BUILD_ROOT/scripts"

install -d \
	"$CORE_ROOT/etc/config" \
	"$CORE_ROOT/etc/init.d" \
	"$CORE_ROOT/lib/apk/packages" \
	"$CORE_ROOT/usr/sbin" \
	"$CORE_ROOT/usr/share/doc/mwan3-nat6" \
	"$LUCI_ROOT/lib/apk/packages" \
	"$LUCI_ROOT/usr/libexec/rpcd" \
	"$LUCI_ROOT/usr/share/luci/menu.d" \
	"$LUCI_ROOT/usr/share/rpcd/acl.d" \
	"$LUCI_ROOT/www/luci-static/resources/view/mwan3-nat6" \
	"$I18N_ROOT/etc/uci-defaults" \
	"$I18N_ROOT/lib/apk/packages" \
	"$I18N_ROOT/usr/lib/lua/luci/i18n" \
	"$SCRIPT_ROOT"

install -m 0644 "$PROJECT_ROOT/openwrt/mwan3-nat6/files/etc/config/mwan3-nat6" \
	"$CORE_ROOT/etc/config/mwan3-nat6"
install -m 0755 "$PROJECT_ROOT/openwrt/mwan3-nat6/files/etc/init.d/mwan3-nat6" \
	"$CORE_ROOT/etc/init.d/mwan3-nat6"
install -m 0755 "$PROJECT_ROOT/openwrt/mwan3-nat6/files/usr/nft-nat6.sh" \
	"$CORE_ROOT/usr/nft-nat6.sh"
install -m 0755 "$PROJECT_ROOT/openwrt/mwan3-nat6/files/usr/sbin/mwan3-nat6-watch" \
	"$CORE_ROOT/usr/sbin/mwan3-nat6-watch"
install -m 0644 "$PROJECT_ROOT/NAT6_HANDOFF.md" \
	"$CORE_ROOT/usr/share/doc/mwan3-nat6/NAT6_HANDOFF.md"

install -m 0755 \
	"$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6/root/usr/libexec/rpcd/luci.mwan3-nat6" \
	"$LUCI_ROOT/usr/libexec/rpcd/luci.mwan3-nat6"
install -m 0644 \
	"$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6/root/usr/share/luci/menu.d/luci-app-mwan3-nat6.json" \
	"$LUCI_ROOT/usr/share/luci/menu.d/luci-app-mwan3-nat6.json"
install -m 0644 \
	"$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6/root/usr/share/rpcd/acl.d/luci-app-mwan3-nat6.json" \
	"$LUCI_ROOT/usr/share/rpcd/acl.d/luci-app-mwan3-nat6.json"
install -m 0644 \
	"$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6/htdocs/luci-static/resources/view/mwan3-nat6/status.js" \
	"$LUCI_ROOT/www/luci-static/resources/view/mwan3-nat6/status.js"
install -m 0644 \
	"$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6/htdocs/luci-static/resources/view/mwan3-nat6/settings.js" \
	"$LUCI_ROOT/www/luci-static/resources/view/mwan3-nat6/settings.js"
install -m 0755 \
	"$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6/po/en/luci-i18n-mwan3-nat6-en" \
	"$I18N_ROOT/etc/uci-defaults/luci-i18n-mwan3-nat6-en"
"$PO2LMO" \
	"$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6/po/en/mwan3-nat6.po" \
	"$I18N_ROOT/usr/lib/lua/luci/i18n/mwan3-nat6.en.lmo"

(cd "$CORE_ROOT" && find etc usr -type f -printf '/%p\n' | sort) > \
	"$CORE_ROOT/lib/apk/packages/mwan3-nat6.list"
printf '%s\n' '/etc/config/mwan3-nat6' > \
	"$CORE_ROOT/lib/apk/packages/mwan3-nat6.conffiles"
config_hash="$(sha256sum "$CORE_ROOT/etc/config/mwan3-nat6" | awk '{print $1}')"
printf '%s %s\n' '/etc/config/mwan3-nat6' "$config_hash" > \
	"$CORE_ROOT/lib/apk/packages/mwan3-nat6.conffiles_static"
(cd "$LUCI_ROOT" && find usr www -type f -printf '/%p\n' | sort) > \
	"$LUCI_ROOT/lib/apk/packages/luci-app-mwan3-nat6.list"
(cd "$I18N_ROOT" && find etc usr -type f -printf '/%p\n' | sort) > \
	"$I18N_ROOT/lib/apk/packages/luci-i18n-mwan3-nat6-en.list"

cat >"$SCRIPT_ROOT/core-post-install" <<'EOF'
#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
export root="${IPKG_INSTROOT}"
export pkgname="mwan3-nat6"
add_group_and_user
default_postinst
[ -n "${IPKG_INSTROOT}" ] || {
	/etc/init.d/mwan3-nat6 enable >/dev/null 2>&1 || :
	/etc/init.d/mwan3-nat6 restart >/dev/null 2>&1 || :
}
exit 0
EOF
cat >"$SCRIPT_ROOT/core-post-upgrade" <<'EOF'
#!/bin/sh
export PKG_UPGRADE=1
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
export root="${IPKG_INSTROOT}"
export pkgname="mwan3-nat6"
add_group_and_user
default_postinst
[ -n "${IPKG_INSTROOT}" ] || {
	/etc/init.d/mwan3-nat6 enable >/dev/null 2>&1 || :
	/etc/init.d/mwan3-nat6 restart >/dev/null 2>&1 || :
}
exit 0
EOF
cat >"$SCRIPT_ROOT/core-pre-deinstall" <<'EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || /usr/nft-nat6.sh cleanup-policy >/dev/null 2>&1 || :
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
export root="${IPKG_INSTROOT}"
export pkgname="mwan3-nat6"
default_prerm
EOF
cat >"$SCRIPT_ROOT/luci-post-install" <<'EOF'
#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
export root="${IPKG_INSTROOT}"
export pkgname="luci-app-mwan3-nat6"
add_group_and_user
default_postinst
[ -n "${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache
	/etc/init.d/rpcd reload >/dev/null 2>&1 || :
}
exit 0
EOF
cat >"$SCRIPT_ROOT/luci-post-upgrade" <<'EOF'
#!/bin/sh
export PKG_UPGRADE=1
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
export root="${IPKG_INSTROOT}"
export pkgname="luci-app-mwan3-nat6"
add_group_and_user
default_postinst
[ -n "${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache
	/etc/init.d/rpcd reload >/dev/null 2>&1 || :
}
exit 0
EOF
cat >"$SCRIPT_ROOT/luci-pre-deinstall" <<'EOF'
#!/bin/sh
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
export root="${IPKG_INSTROOT}"
export pkgname="luci-app-mwan3-nat6"
default_prerm
EOF
cat >"$SCRIPT_ROOT/i18n-post-install" <<'EOF'
#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
export root="${IPKG_INSTROOT}"
export pkgname="luci-i18n-mwan3-nat6-en"
add_group_and_user
default_postinst
[ -n "${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload >/dev/null 2>&1 || :
}
exit 0
EOF
cat >"$SCRIPT_ROOT/i18n-post-upgrade" <<'EOF'
#!/bin/sh
export PKG_UPGRADE=1
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
export root="${IPKG_INSTROOT}"
export pkgname="luci-i18n-mwan3-nat6-en"
add_group_and_user
default_postinst
[ -n "${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload >/dev/null 2>&1 || :
}
exit 0
EOF
cat >"$SCRIPT_ROOT/i18n-pre-deinstall" <<'EOF'
#!/bin/sh
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
export root="${IPKG_INSTROOT}"
export pkgname="luci-i18n-mwan3-nat6-en"
default_prerm
EOF

SOURCE_DATE_EPOCH=0 "$APK" mkpkg \
	--info 'name:mwan3-nat6' \
	--info "version:$VERSION-r1" \
	--info 'description:供兩條以上 mwan3 WAN 使用的 IPv6 前綴 NAT 工具；獨立更新監看預設停用。' \
	--info 'arch:noarch' \
	--info 'license:GPL-3.0-only' \
	--info 'origin:mwan3-nat6' \
	--info 'provides:mwan3-nat6-any' \
	--info 'depends:ip-full jsonfilter kmod-nft-nat libc mwan3 netifd nftables uci' \
	--script "post-install:$SCRIPT_ROOT/core-post-install" \
	--script "post-upgrade:$SCRIPT_ROOT/core-post-upgrade" \
	--script "pre-deinstall:$SCRIPT_ROOT/core-pre-deinstall" \
	--files "$CORE_ROOT" \
	--sign-key "$SIGN_KEY" \
	--output "$CORE_APK"

SOURCE_DATE_EPOCH=0 "$APK" mkpkg \
	--info 'name:luci-app-mwan3-nat6' \
	--info "version:$VERSION-r1" \
	--info 'description:mwan3 多 WAN IPv6 前綴 NAT 的正體中文設定、狀態與受保護手動套用介面。' \
	--info 'arch:noarch' \
	--info 'license:GPL-3.0-only' \
	--info 'origin:luci-app-mwan3-nat6' \
	--info 'provides:luci-app-mwan3-nat6-any' \
	--info 'depends:libc luci-base mwan3-nat6' \
	--script "post-install:$SCRIPT_ROOT/luci-post-install" \
	--script "post-upgrade:$SCRIPT_ROOT/luci-post-upgrade" \
	--script "pre-deinstall:$SCRIPT_ROOT/luci-pre-deinstall" \
	--files "$LUCI_ROOT" \
	--sign-key "$SIGN_KEY" \
	--output "$LUCI_APK"

SOURCE_DATE_EPOCH=0 "$APK" mkpkg \
	--info 'name:luci-i18n-mwan3-nat6-en' \
	--info "version:$VERSION-r1" \
	--info 'description:mwan3 NAT6 LuCI 介面的選用英文語言包。' \
	--info 'arch:noarch' \
	--info 'license:GPL-3.0-only' \
	--info 'origin:luci-i18n-mwan3-nat6-en' \
	--info 'provides:luci-i18n-mwan3-nat6-en-any' \
	--info 'depends:libc luci-app-mwan3-nat6' \
	--script "post-install:$SCRIPT_ROOT/i18n-post-install" \
	--script "post-upgrade:$SCRIPT_ROOT/i18n-post-upgrade" \
	--script "pre-deinstall:$SCRIPT_ROOT/i18n-pre-deinstall" \
	--files "$I18N_ROOT" \
	--sign-key "$SIGN_KEY" \
	--output "$I18N_APK"

"$PROJECT_ROOT/scripts/verify-apk-artifacts.sh" "$SDK_DIR" "$OUTPUT_DIR"
sha256sum "$CORE_APK" "$LUCI_APK" "$I18N_APK"
