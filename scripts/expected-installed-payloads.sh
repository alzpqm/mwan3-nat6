#!/bin/sh

set -eu

PROJECT_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"

emit_hash() {
	source="$1"
	target="$2"
	line="$(sha256sum "$source")"
	hash="${line%% *}"
	printf '%s  %s\n' "$hash" "$target"
}

emit_hash "$PROJECT_ROOT/openwrt/mwan3-nat6/files/etc/init.d/mwan3-nat6" \
	/etc/init.d/mwan3-nat6
emit_hash "$PROJECT_ROOT/openwrt/mwan3-nat6/files/usr/nft-nat6.sh" \
	/usr/nft-nat6.sh
emit_hash "$PROJECT_ROOT/openwrt/mwan3-nat6/files/usr/sbin/mwan3-nat6-watch" \
	/usr/sbin/mwan3-nat6-watch
emit_hash "$PROJECT_ROOT/NAT6_HANDOFF.md" \
	/usr/share/doc/mwan3-nat6/NAT6_HANDOFF.md
emit_hash "$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6/root/usr/libexec/rpcd/luci.mwan3-nat6" \
	/usr/libexec/rpcd/luci.mwan3-nat6
emit_hash "$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6/root/usr/share/luci/menu.d/luci-app-mwan3-nat6.json" \
	/usr/share/luci/menu.d/luci-app-mwan3-nat6.json
emit_hash "$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6/root/usr/share/rpcd/acl.d/luci-app-mwan3-nat6.json" \
	/usr/share/rpcd/acl.d/luci-app-mwan3-nat6.json
emit_hash "$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6/htdocs/luci-static/resources/view/mwan3-nat6/settings.js" \
	/www/luci-static/resources/view/mwan3-nat6/settings.js
emit_hash "$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6/htdocs/luci-static/resources/view/mwan3-nat6/status.js" \
	/www/luci-static/resources/view/mwan3-nat6/status.js
