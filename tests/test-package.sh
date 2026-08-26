#!/bin/sh

set -eu

PROJECT_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
PACKAGE_DIR="$PROJECT_ROOT/openwrt/mwan3-nat6"
PACKAGE_MAKEFILE="$PACKAGE_DIR/Makefile"
SCRIPT="$PACKAGE_DIR/files/usr/nft-nat6.sh"
CONFIG="$PACKAGE_DIR/files/etc/config/mwan3-nat6"
LUCI_DIR="$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6"
LUCI_MAKEFILE="$LUCI_DIR/Makefile"
LUCI_BACKEND="$LUCI_DIR/root/usr/libexec/rpcd/luci.mwan3-nat6"
LUCI_ACL="$LUCI_DIR/root/usr/share/rpcd/acl.d/luci-app-mwan3-nat6.json"
LUCI_MENU="$LUCI_DIR/root/usr/share/luci/menu.d/luci-app-mwan3-nat6.json"
LUCI_VIEW="$LUCI_DIR/htdocs/luci-static/resources/view/mwan3-nat6/status.js"
LUCI_SETTINGS="$LUCI_DIR/htdocs/luci-static/resources/view/mwan3-nat6/settings.js"
SDK_BUILD="$PROJECT_ROOT/scripts/build-apk-on-sdk.sh"

fail() {
	printf '%s\n' "test-package: FAIL: $*" >&2
	exit 1
}

version="$(sed -n '1p' "$PROJECT_ROOT/VERSION")"
package_version="$(sed -n 's/^PKG_VERSION:=//p' "$PACKAGE_MAKEFILE")"
luci_version="$(sed -n 's/^PKG_VERSION:=//p' "$LUCI_MAKEFILE")"
[ -n "$version" ] || fail 'VERSION is empty'
[ "$version" = "$package_version" ] ||
	fail "VERSION $version does not match package $package_version"
[ "$version" = "$luci_version" ] ||
	fail "VERSION $version does not match LuCI package $luci_version"

[ -x "$SCRIPT" ] || fail 'canonical package script is missing or not executable'
[ ! -e "$PACKAGE_DIR/files/usr/sbin/nft-nat6.sh" ] ||
	fail 'obsolete /usr/sbin package path still exists'
grep -Fq '$(1)/usr/nft-nat6.sh' "$PACKAGE_MAKEFILE" ||
	fail 'package does not install the canonical /usr/nft-nat6.sh path'
sed -n '/^define Package\/mwan3-nat6$/,/^endef$/p' "$PACKAGE_MAKEFILE" |
	grep -Fq 'PKGARCH:=all' ||
	fail 'package definition is not architecture-independent'

for dependency in jsonfilter netifd nftables kmod-nft-nat uci; do
	grep -Eq "(^|[+[:space:]])${dependency}([[:space:]]|$)" "$PACKAGE_MAKEFILE" ||
		fail "missing package dependency: $dependency"
done

[ -s "$CONFIG" ] || fail 'package does not install its N-WAN UCI configuration'
grep -Fq '$(INSTALL_CONF) ./files/etc/config/mwan3-nat6' "$PACKAGE_MAKEFILE" ||
	fail 'package does not install the UCI configuration as a conffile'
grep -Fq '/etc/config/mwan3-nat6' "$PACKAGE_MAKEFILE" ||
	fail 'package does not preserve the UCI configuration on upgrade'
grep -Eq '^config[[:space:]]+wan' "$CONFIG" &&
	fail 'default package configuration must not enable or define a live WAN'
[ ! -e "$PACKAGE_DIR/files/etc/hotplug.d" ] ||
	fail 'package must not install hotplug hooks'
[ ! -e "$PACKAGE_DIR/files/etc/config/firewall" ] ||
	fail 'package must not install firewall configuration'
grep -Fq 'expected_rule_count=$((WAN_COUNT * WAN_COUNT))' "$SCRIPT" ||
	fail 'status does not calculate the N-WAN N-squared rule count'
grep -Fq 'ip6 saddr 2000::/3 ip6 saddr != %s snat ip6 prefix to %s' "$SCRIPT" ||
	fail 'dynamic prefix SNAT is not limited to global-unicast sources'
grep -Fq 'MAX_WANS=32' "$SCRIPT" || fail 'N-WAN safety cap is missing'

[ -x "$LUCI_BACKEND" ] || fail 'LuCI rpcd backend is missing or not executable'
[ -s "$LUCI_ACL" ] || fail 'LuCI ACL is missing'
[ -s "$LUCI_MENU" ] || fail 'LuCI menu is missing'
[ -s "$LUCI_VIEW" ] || fail 'LuCI JavaScript view is missing'
[ -s "$LUCI_SETTINGS" ] || fail 'LuCI settings view is missing'
[ -x "$SDK_BUILD" ] || fail 'target-only SDK build helper is missing or not executable'
sh -n "$SDK_BUILD" || fail 'target-only SDK build helper has invalid shell syntax'
grep -Fq 'DEPENDS:=+luci-base +mwan3-nat6' "$LUCI_MAKEFILE" ||
	fail 'LuCI package dependencies are incomplete'
sed -n '/^define Package\/luci-app-mwan3-nat6$/,/^endef$/p' "$LUCI_MAKEFILE" |
	grep -Fq 'PKGARCH:=all' || fail 'LuCI package is not architecture-independent'
grep -Fq '"luci.mwan3-nat6": [ "status" ]' "$LUCI_ACL" ||
	fail 'LuCI read ACL does not grant only the status method'
grep -Fq '"luci.mwan3-nat6": [ "apply" ]' "$LUCI_ACL" ||
	fail 'LuCI write ACL does not grant only the apply method'
grep -Fq '"uci": [ "mwan3-nat6" ]' "$LUCI_ACL" ||
	fail 'LuCI ACL does not grant package-scoped UCI access'
if grep -Eq '"file"|/bin/(a)?sh|"exec"' "$LUCI_ACL"; then
	fail 'LuCI ACL grants generic file or shell execution'
fi
[ ! -e "$LUCI_DIR/root/etc/hotplug.d" ] ||
	fail 'LuCI package must not install hotplug hooks'
[ ! -e "$LUCI_DIR/root/etc/config/firewall" ] ||
	fail 'LuCI package must not install firewall configuration'
sed -n '/^define Package\/luci-app-mwan3-nat6\/postinst$/,/^endef$/p' \
	"$LUCI_MAKEFILE" | grep -Fq '/usr/nft-nat6.sh' &&
	fail 'LuCI post-install must not execute the NAT6 script'
grep -Fq 'settings.js' "$LUCI_MAKEFILE" ||
	fail 'LuCI package does not install the WAN configuration view'
grep -Fq 'mwan3-nat6.conffiles_static' "$SDK_BUILD" ||
	fail 'target-only APK build does not preserve the UCI conffile metadata'
grep -Fq 'depends:jsonfilter kmod-nft-nat libc netifd nftables uci' "$SDK_BUILD" ||
	fail 'target-only core APK dependencies are incomplete'

cmp -s "$PROJECT_ROOT/NAT6_HANDOFF.md" \
	"$PACKAGE_DIR/files/usr/share/doc/mwan3-nat6/NAT6_HANDOFF.md" ||
	fail 'packaged NAT6_HANDOFF.md is out of sync'

printf '%s\n' 'test-package: PASS'
