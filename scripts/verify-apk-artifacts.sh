#!/bin/sh

set -eu

PROJECT_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
SDK_DIR="${1:?usage: $0 SDK_DIR OUTPUT_DIR}"
OUTPUT_DIR="${2:?usage: $0 SDK_DIR OUTPUT_DIR}"
APK="$SDK_DIR/staging_dir/host/bin/apk"
PUBLIC_KEY="$SDK_DIR/public-key.pem"
VERSION="$(sed -n '1p' "$PROJECT_ROOT/VERSION")"
CORE_APK="$OUTPUT_DIR/mwan3-nat6-$VERSION-r1.apk"
LUCI_APK="$OUTPUT_DIR/luci-app-mwan3-nat6-$VERSION-r1.apk"
VERIFY_ROOT=''
LAST_OUT=''

cleanup() {
	[ -z "$VERIFY_ROOT" ] || rm -rf "$VERIFY_ROOT"
}

fail() {
	printf '%s\n' "verify-apk-artifacts: ERROR: $*" >&2
	exit 1
}

run_apk() {
	label="$1"
	shift
	LAST_OUT="$VERIFY_ROOT/$label.stdout"
	last_err="$VERIFY_ROOT/$label.stderr"
	if "$APK" "$@" >"$LAST_OUT" 2>"$last_err"; then
		return 0
	else
		rc=$?
		sed -n '1,120p' "$last_err" >&2
		fail "apk $label failed with rc=$rc"
	fi
}

require_line() {
	needle="$1"
	file="$2"
	grep -Fqx "$needle" "$file" || fail "missing metadata line: $needle"
}

require_count() {
	expected="$1"
	needle="$2"
	file="$3"
	actual="$(grep -Fc "$needle" "$file" || true)"
	[ "$actual" -eq "$expected" ] ||
		fail "expected $expected occurrences of '$needle', found $actual"
}

verify_file() {
	extracted="$1"
	source="$2"
	expected_mode="$3"
	[ -f "$extracted" ] || fail "missing extracted payload: $extracted"
	cmp -s "$extracted" "$source" || fail "payload differs from source: $extracted"
	actual_mode="$(stat -c '%a' "$extracted")"
	[ "$actual_mode" = "$expected_mode" ] ||
		fail "mode $actual_mode != $expected_mode: $extracted"
}

verify_file_list() {
	root="$1"
	expected="$2"
	actual="$3"
	find "$root" -type f -printf '%P\n' | LC_ALL=C sort >"$actual"
	if ! cmp -s "$actual" "$expected"; then
		printf '%s\n' 'expected files:' >&2
		sed -n '1,160p' "$expected" >&2
		printf '%s\n' 'actual files:' >&2
		sed -n '1,160p' "$actual" >&2
		fail 'extracted package file set differs'
	fi
}

[ -x "$APK" ] || fail "SDK apk tool is missing: $APK"
[ -r "$PUBLIC_KEY" ] || fail "SDK public key is missing: $PUBLIC_KEY"
[ -s "$CORE_APK" ] || fail "core APK is missing: $CORE_APK"
[ -s "$LUCI_APK" ] || fail "LuCI APK is missing: $LUCI_APK"

VERIFY_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mwan3-nat6-apk-verify.XXXXXX")" ||
	fail 'cannot create verification directory'
trap cleanup EXIT HUP INT TERM

run_apk core-signature verify --keys-dir "$SDK_DIR" "$CORE_APK"
grep -Fq "$CORE_APK: OK" "$LAST_OUT" || fail 'core signature output is not OK'
run_apk luci-signature verify --keys-dir "$SDK_DIR" "$LUCI_APK"
grep -Fq "$LUCI_APK: OK" "$LAST_OUT" || fail 'LuCI signature output is not OK'

run_apk core-metadata adbdump --keys-dir "$SDK_DIR" "$CORE_APK"
core_metadata="$LAST_OUT"
require_line '  name: mwan3-nat6' "$core_metadata"
require_line "  version: $VERSION-r1" "$core_metadata"
require_line '  arch: noarch' "$core_metadata"
require_line '  license: GPL-3.0-only' "$core_metadata"
for dependency in ip-full jsonfilter kmod-nft-nat libc mwan3 netifd nftables uci; do
	require_line "    - $dependency" "$core_metadata"
done
require_line '    - mwan3-nat6-any' "$core_metadata"
require_line '  post-install: |' "$core_metadata"
require_line '  pre-deinstall: |' "$core_metadata"
require_line '  post-upgrade: |' "$core_metadata"
require_count 2 '/etc/init.d/mwan3-nat6 enable' "$core_metadata"
require_count 2 '/etc/init.d/mwan3-nat6 restart' "$core_metadata"
require_count 1 '/usr/nft-nat6.sh cleanup-policy' "$core_metadata"

run_apk luci-metadata adbdump --keys-dir "$SDK_DIR" "$LUCI_APK"
luci_metadata="$LAST_OUT"
require_line '  name: luci-app-mwan3-nat6' "$luci_metadata"
require_line "  version: $VERSION-r1" "$luci_metadata"
require_line '  arch: noarch' "$luci_metadata"
require_line '  license: GPL-3.0-only' "$luci_metadata"
for dependency in libc luci-base mwan3-nat6; do
	require_line "    - $dependency" "$luci_metadata"
done
require_line '    - luci-app-mwan3-nat6-any' "$luci_metadata"
require_line '  post-install: |' "$luci_metadata"
require_line '  pre-deinstall: |' "$luci_metadata"
require_line '  post-upgrade: |' "$luci_metadata"
require_count 2 'rm -f /tmp/luci-indexcache' "$luci_metadata"
require_count 2 '/etc/init.d/rpcd reload' "$luci_metadata"

core_root="$VERIFY_ROOT/core-root"
luci_root="$VERIFY_ROOT/luci-root"
mkdir "$core_root" "$luci_root"
run_apk core-extract extract --keys-dir "$SDK_DIR" --destination "$core_root" "$CORE_APK"
run_apk luci-extract extract --keys-dir "$SDK_DIR" --destination "$luci_root" "$LUCI_APK"

cat >"$VERIFY_ROOT/core-files.expected" <<'EOF'
etc/config/mwan3-nat6
etc/init.d/mwan3-nat6
lib/apk/packages/mwan3-nat6.conffiles
lib/apk/packages/mwan3-nat6.conffiles_static
lib/apk/packages/mwan3-nat6.list
usr/nft-nat6.sh
usr/sbin/mwan3-nat6-watch
usr/share/doc/mwan3-nat6/NAT6_HANDOFF.md
EOF
cat >"$VERIFY_ROOT/luci-files.expected" <<'EOF'
lib/apk/packages/luci-app-mwan3-nat6.list
usr/libexec/rpcd/luci.mwan3-nat6
usr/share/luci/menu.d/luci-app-mwan3-nat6.json
usr/share/rpcd/acl.d/luci-app-mwan3-nat6.json
www/luci-static/resources/view/mwan3-nat6/settings.js
www/luci-static/resources/view/mwan3-nat6/status.js
EOF
verify_file_list "$core_root" "$VERIFY_ROOT/core-files.expected" "$VERIFY_ROOT/core-files.actual"
verify_file_list "$luci_root" "$VERIFY_ROOT/luci-files.expected" "$VERIFY_ROOT/luci-files.actual"

verify_file "$core_root/etc/config/mwan3-nat6" \
	"$PROJECT_ROOT/openwrt/mwan3-nat6/files/etc/config/mwan3-nat6" 644
verify_file "$core_root/etc/init.d/mwan3-nat6" \
	"$PROJECT_ROOT/openwrt/mwan3-nat6/files/etc/init.d/mwan3-nat6" 755
verify_file "$core_root/usr/nft-nat6.sh" \
	"$PROJECT_ROOT/openwrt/mwan3-nat6/files/usr/nft-nat6.sh" 755
verify_file "$core_root/usr/sbin/mwan3-nat6-watch" \
	"$PROJECT_ROOT/openwrt/mwan3-nat6/files/usr/sbin/mwan3-nat6-watch" 755
verify_file "$core_root/usr/share/doc/mwan3-nat6/NAT6_HANDOFF.md" \
	"$PROJECT_ROOT/NAT6_HANDOFF.md" 644

verify_file "$luci_root/usr/libexec/rpcd/luci.mwan3-nat6" \
	"$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6/root/usr/libexec/rpcd/luci.mwan3-nat6" 755
verify_file "$luci_root/usr/share/luci/menu.d/luci-app-mwan3-nat6.json" \
	"$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6/root/usr/share/luci/menu.d/luci-app-mwan3-nat6.json" 644
verify_file "$luci_root/usr/share/rpcd/acl.d/luci-app-mwan3-nat6.json" \
	"$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6/root/usr/share/rpcd/acl.d/luci-app-mwan3-nat6.json" 644
verify_file "$luci_root/www/luci-static/resources/view/mwan3-nat6/settings.js" \
	"$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6/htdocs/luci-static/resources/view/mwan3-nat6/settings.js" 644
verify_file "$luci_root/www/luci-static/resources/view/mwan3-nat6/status.js" \
	"$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6/htdocs/luci-static/resources/view/mwan3-nat6/status.js" 644

cat >"$VERIFY_ROOT/core-package-list.expected" <<'EOF'
/etc/config/mwan3-nat6
/etc/init.d/mwan3-nat6
/usr/nft-nat6.sh
/usr/sbin/mwan3-nat6-watch
/usr/share/doc/mwan3-nat6/NAT6_HANDOFF.md
EOF
cat >"$VERIFY_ROOT/luci-package-list.expected" <<'EOF'
/usr/libexec/rpcd/luci.mwan3-nat6
/usr/share/luci/menu.d/luci-app-mwan3-nat6.json
/usr/share/rpcd/acl.d/luci-app-mwan3-nat6.json
/www/luci-static/resources/view/mwan3-nat6/settings.js
/www/luci-static/resources/view/mwan3-nat6/status.js
EOF
cmp -s "$core_root/lib/apk/packages/mwan3-nat6.list" \
	"$VERIFY_ROOT/core-package-list.expected" || fail 'core APK package list differs'
cmp -s "$luci_root/lib/apk/packages/luci-app-mwan3-nat6.list" \
	"$VERIFY_ROOT/luci-package-list.expected" || fail 'LuCI APK package list differs'
printf '%s\n' '/etc/config/mwan3-nat6' >"$VERIFY_ROOT/conffiles.expected"
cmp -s "$core_root/lib/apk/packages/mwan3-nat6.conffiles" \
	"$VERIFY_ROOT/conffiles.expected" || fail 'core conffiles metadata differs'
config_hash="$(sha256sum "$PROJECT_ROOT/openwrt/mwan3-nat6/files/etc/config/mwan3-nat6" | awk '{print $1}')"
printf '%s %s\n' '/etc/config/mwan3-nat6' "$config_hash" >"$VERIFY_ROOT/conffiles-static.expected"
cmp -s "$core_root/lib/apk/packages/mwan3-nat6.conffiles_static" \
	"$VERIFY_ROOT/conffiles-static.expected" || fail 'core static conffile metadata differs'

sha256sum "$CORE_APK" "$LUCI_APK"
printf '%s\n' "verify-apk-artifacts: PASS ($VERSION)"
