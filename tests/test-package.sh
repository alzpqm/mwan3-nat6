#!/bin/sh

set -eu

PROJECT_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
PACKAGE_DIR="$PROJECT_ROOT/openwrt/mwan3-nat6"
PACKAGE_MAKEFILE="$PACKAGE_DIR/Makefile"
SCRIPT="$PACKAGE_DIR/files/usr/nft-nat6.sh"
WATCHER="$PACKAGE_DIR/files/usr/sbin/mwan3-nat6-watch"
INIT_SCRIPT="$PACKAGE_DIR/files/etc/init.d/mwan3-nat6"
CONFIG="$PACKAGE_DIR/files/etc/config/mwan3-nat6"
LUCI_DIR="$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6"
LUCI_MAKEFILE="$LUCI_DIR/Makefile"
LUCI_BACKEND="$LUCI_DIR/root/usr/libexec/rpcd/luci.mwan3-nat6"
LUCI_ACL="$LUCI_DIR/root/usr/share/rpcd/acl.d/luci-app-mwan3-nat6.json"
LUCI_MENU="$LUCI_DIR/root/usr/share/luci/menu.d/luci-app-mwan3-nat6.json"
LUCI_VIEW="$LUCI_DIR/htdocs/luci-static/resources/view/mwan3-nat6/status.js"
LUCI_SETTINGS="$LUCI_DIR/htdocs/luci-static/resources/view/mwan3-nat6/settings.js"
SDK_BUILD="$PROJECT_ROOT/scripts/build-apk-on-sdk.sh"
SDK_VERIFY="$PROJECT_ROOT/scripts/verify-apk-artifacts.sh"
SOURCE_MANIFEST="$PROJECT_ROOT/scripts/source-manifest.sh"
OPENWRT_INSTALL_GATE="$PROJECT_ROOT/scripts/openwrt-install-gate.sh"
INSTALLED_PAYLOADS="$PROJECT_ROOT/scripts/expected-installed-payloads.sh"
OPENWRT_POST_REBOOT_GATE="$PROJECT_ROOT/scripts/openwrt-post-reboot-gate.sh"

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
[ -x "$WATCHER" ] || fail 'renewal watcher is missing or not executable'
[ -x "$INIT_SCRIPT" ] || fail 'procd init script is missing or not executable'
sh -n "$WATCHER" || fail 'renewal watcher has invalid shell syntax'
sh -n "$INIT_SCRIPT" || fail 'procd init script has invalid shell syntax'
[ ! -e "$PACKAGE_DIR/files/usr/sbin/nft-nat6.sh" ] ||
	fail 'obsolete /usr/sbin package path still exists'
grep -Fq '$(1)/usr/nft-nat6.sh' "$PACKAGE_MAKEFILE" ||
	fail 'package does not install the canonical /usr/nft-nat6.sh path'
sed -n '/^define Package\/mwan3-nat6$/,/^endef$/p' "$PACKAGE_MAKEFILE" |
	grep -Fq 'PKGARCH:=all' ||
	fail 'package definition is not architecture-independent'

for dependency in jsonfilter netifd nftables kmod-nft-nat uci mwan3; do
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
grep -Eq "^[[:space:]]*option[[:space:]]+monitor[[:space:]]+'0'" "$CONFIG" ||
	fail 'automatic renewal monitor is not disabled in the default configuration'
grep -Eq "^[[:space:]]*option[[:space:]]+refresh_mwan3_after_nat[[:space:]]+'0'" "$CONFIG" ||
	fail 'mwan3 compatibility refresh is not disabled under its new option name'
grep -Eq "^[[:space:]]*option[[:space:]]+pin_local_icmp[[:space:]]+'0'" "$CONFIG" ||
	fail 'router-local ICMP pinning is not disabled by default'
if grep -Eq "^[[:space:]]*option[[:space:]]+refresh_mwan3[[:space:]]" "$CONFIG"; then
	fail 'legacy default-on mwan3 refresh option remains in package configuration'
fi
[ ! -e "$PACKAGE_DIR/files/etc/hotplug.d" ] ||
	fail 'package must not install hotplug hooks'
[ ! -e "$PACKAGE_DIR/files/etc/config/firewall" ] ||
	fail 'package must not install firewall configuration'
grep -Fq 'expected_rule_count=$((READY_WAN_COUNT * READY_WAN_COUNT))' "$SCRIPT" ||
	fail 'status does not calculate the N-WAN N-squared rule count'
grep -Fq '"active_wan_count":%s' "$SCRIPT" ||
	fail 'status does not expose the active ready-WAN subset'
grep -Fq '[ "$destination_state" = ready ] || continue' "$SCRIPT" ||
	fail 'rule generation does not exclude unavailable WANs'
grep -Fq 'ip6 saddr 2000::/3 ip6 saddr != %s snat ip6 prefix to %s' "$SCRIPT" ||
	fail 'dynamic prefix SNAT is not limited to global-unicast sources'
grep -Fq 'MAX_WANS=32' "$SCRIPT" || fail 'N-WAN safety cap is missing'
grep -Fq 'type route hook output priority -140' "$SCRIPT" ||
	fail 'router-local ICMP pin chain does not run after competing mangle marks'
grep -Fq 'ip6 saddr %s meta l4proto ipv6-icmp icmpv6 type echo-request meta mark set %s' "$SCRIPT" ||
	fail 'router-local ICMP pin is not limited to exact WAN GUA echo requests'
grep -Fq 'nft -c -f "$RULE_FILE"' "$SCRIPT" ||
	fail 'core does not validate its complete atomic batch'
grep -Fq "procd_add_reload_trigger 'mwan3-nat6'" "$INIT_SCRIPT" ||
	fail 'renewal service does not limit its reload trigger to its own UCI package'
if grep -Eq 'firewall|fw4' "$INIT_SCRIPT"; then
	fail 'renewal service is coupled to firewall reload'
fi
if grep -Eq 'kill|service[[:space:]]+signal|mwan3[[:space:]]+restart' "$WATCHER"; then
	fail 'renewal watcher broadly restarts or directly signals tracker processes'
fi
grep -Fq 'mwan3 ifup "$logical"' "$WATCHER" ||
	fail 'renewal watcher does not use the supported narrow mwan3 ifup path'
grep -Fq 'uci_get refresh_mwan3_after_nat' "$WATCHER" ||
	fail 'renewal watcher does not use the renamed opt-in refresh control'
grep -Fq 'is_enabled "${refresh:-0}"' "$WATCHER" ||
	fail 'renewal watcher compatibility refresh is not default-off'
sed -n '/^define Package\/mwan3-nat6\/postinst$/,/^endef$/p' "$PACKAGE_MAKEFILE" |
	grep -Fq '/etc/init.d/mwan3-nat6 enable' ||
	fail 'package post-install does not enable the newly introduced service on upgrade'
sed -n '/^define Package\/mwan3-nat6\/postinst$/,/^endef$/p' "$PACKAGE_MAKEFILE" |
	grep -Fq '/etc/init.d/mwan3-nat6 restart' ||
	fail 'package post-install does not register/restart the inert service'

[ -x "$LUCI_BACKEND" ] || fail 'LuCI rpcd backend is missing or not executable'
[ -s "$LUCI_ACL" ] || fail 'LuCI ACL is missing'
[ -s "$LUCI_MENU" ] || fail 'LuCI menu is missing'
[ -s "$LUCI_VIEW" ] || fail 'LuCI JavaScript view is missing'
[ -s "$LUCI_SETTINGS" ] || fail 'LuCI settings view is missing'
[ -x "$SDK_BUILD" ] || fail 'target-only SDK build helper is missing or not executable'
sh -n "$SDK_BUILD" || fail 'target-only SDK build helper has invalid shell syntax'
grep -Fq 'SDK_DIR="${SDK_DIR:?' "$SDK_BUILD" ||
	fail 'SDK build helper no longer requires SDK_DIR as an environment variable'
grep -Fq 'OUTPUT_DIR="${1:?' "$SDK_BUILD" ||
	fail 'SDK build helper no longer accepts only the output positional argument'
grep -Fq 'SDK_DIR=/path/to/openwrt-sdk scripts/build-apk-on-sdk.sh /path/to/output' \
	"$PROJECT_ROOT/README.md" || fail 'README does not document the exact SDK builder interface'
[ -x "$SDK_VERIFY" ] || fail 'APK artifact verifier is missing or not executable'
sh -n "$SDK_VERIFY" || fail 'APK artifact verifier has invalid shell syntax'
[ -x "$SOURCE_MANIFEST" ] || fail 'source manifest helper is missing or not executable'
sh -n "$SOURCE_MANIFEST" || fail 'source manifest helper has invalid shell syntax'
[ -x "$OPENWRT_INSTALL_GATE" ] || fail 'OpenWrt install gate is missing or not executable'
sh -n "$OPENWRT_INSTALL_GATE" || fail 'OpenWrt install gate has invalid shell syntax'
[ -x "$INSTALLED_PAYLOADS" ] || fail 'installed-payload helper is missing or not executable'
sh -n "$INSTALLED_PAYLOADS" || fail 'installed-payload helper has invalid shell syntax'
[ -x "$OPENWRT_POST_REBOOT_GATE" ] || fail 'OpenWrt post-reboot gate is missing or not executable'
sh -n "$OPENWRT_POST_REBOOT_GATE" || fail 'OpenWrt post-reboot gate has invalid shell syntax'
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
grep -Fq 'depends:ip-full jsonfilter kmod-nft-nat libc mwan3 netifd nftables uci' "$SDK_BUILD" ||
	fail 'target-only core APK dependencies are incomplete'
grep -Fq 'DEPENDS:=+ip-full +jsonfilter' "$PACKAGE_MAKEFILE" ||
	fail 'OpenWrt package does not directly depend on ip-full'
sed -n '/^define Package\/mwan3-nat6\/prerm$/,/^endef$/p' "$PACKAGE_MAKEFILE" |
	grep -Fq '/usr/nft-nat6.sh cleanup-policy' ||
	fail 'package removal does not clean its tagged RPDB rules'
grep -Fq '/usr/nft-nat6.sh cleanup-policy' "$SDK_BUILD" ||
	fail 'target-only APK pre-deinstall does not clean tagged RPDB rules'
grep -Fq 'mwan3-nat6-watch' "$SDK_BUILD" ||
	fail 'target-only APK build omits the renewal watcher'
grep -Fq 'files/etc/init.d/mwan3-nat6' "$SDK_BUILD" ||
	fail 'target-only APK build omits the procd service'
[ "$(grep -c '/etc/init.d/mwan3-nat6 enable' "$SDK_BUILD")" -eq 2 ] ||
	fail 'target-only APK scripts do not enable the service on install and upgrade'
grep -Fq 'scripts/verify-apk-artifacts.sh' "$SDK_BUILD" ||
	fail 'target-only APK build does not invoke artifact verification'
grep -Fq 'run_apk core-signature verify --keys-dir' "$SDK_VERIFY" ||
	fail 'artifact verifier does not validate the core signature directly'
grep -Fq 'run_apk core-metadata adbdump --keys-dir' "$SDK_VERIFY" ||
	fail 'artifact verifier does not inspect v3 metadata directly'
grep -Fq 'run_apk core-extract extract --keys-dir' "$SDK_VERIFY" ||
	fail 'artifact verifier does not extract the core payload directly'
grep -Fq 'cmp -s "$extracted" "$source"' "$SDK_VERIFY" ||
	fail 'artifact verifier does not byte-compare extracted payloads'
grep -Fq "stat -c '%a'" "$SDK_VERIFY" ||
	fail 'artifact verifier does not check extracted payload modes'

cmp -s "$PROJECT_ROOT/NAT6_HANDOFF.md" \
	"$PACKAGE_DIR/files/usr/share/doc/mwan3-nat6/NAT6_HANDOFF.md" ||
	fail 'packaged NAT6_HANDOFF.md is out of sync'

printf '%s\n' 'test-package: PASS'
