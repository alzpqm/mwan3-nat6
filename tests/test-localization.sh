#!/bin/sh

set -eu

PROJECT_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
LUCI_DIR="$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6"
SETTINGS="$LUCI_DIR/htdocs/luci-static/resources/view/mwan3-nat6/settings.js"
STATUS="$LUCI_DIR/htdocs/luci-static/resources/view/mwan3-nat6/status.js"
MENU="$LUCI_DIR/root/usr/share/luci/menu.d/luci-app-mwan3-nat6.json"
PO="$LUCI_DIR/po/en/mwan3-nat6.po"
DEFAULTS="$LUCI_DIR/po/en/luci-i18n-mwan3-nat6-en"
MAKEFILE="$LUCI_DIR/Makefile"
README="$PROJECT_ROOT/README.md"
GUIDE="$PROJECT_ROOT/NAT6_HANDOFF.md"
PACKAGED_GUIDE="$PROJECT_ROOT/openwrt/mwan3-nat6/files/usr/share/doc/mwan3-nat6/NAT6_HANDOFF.md"
VERSION="$(sed -n '1p' "$PROJECT_ROOT/VERSION")"

fail() {
	printf '%s\n' "test-localization: FAIL: $*" >&2
	exit 1
}

[ -s "$PO" ] || fail 'English PO catalog is missing'
[ -x "$DEFAULTS" ] || fail 'English language registration script is not executable'
sh -n "$DEFAULTS" || fail 'English language registration script has invalid syntax'
grep -Fq "luci.languages.en='English'" "$DEFAULTS" ||
	fail 'English language registration is missing'
if grep -Fq 'luci.main.lang' "$DEFAULTS"; then
	fail 'installing the optional English package must not force the active LuCI language'
fi

grep -Fq 'define Package/luci-i18n-mwan3-nat6-en' "$MAKEFILE" ||
	fail 'English language package definition is missing'
grep -Fq 'DEPENDS:=+luci-app-mwan3-nat6' "$MAKEFILE" ||
	fail 'English language package does not depend on the LuCI app'
grep -Fq '$(STAGING_DIR_HOSTPKG)/bin/po2lmo ./po/en/mwan3-nat6.po' "$MAKEFILE" ||
	fail 'English PO is not compiled with the matching LuCI host tool'
sed -n '/^define Package\/luci-app-mwan3-nat6$/,/^endef$/p' "$MAKEFILE" |
	grep -Fq 'luci-i18n-mwan3-nat6-en' &&
	fail 'the Traditional Chinese base app must not depend on the optional English pack'

grep -Fq '# mwan3 多 WAN NAT6' "$README" ||
	fail 'README is not Traditional Chinese by default'
grep -Fq '## 語言' "$README" || fail 'README does not explain the language split'
grep -Fq "luci-i18n-mwan3-nat6-en-$VERSION-r1.apk" "$README" ||
	fail 'README does not document the separate English package'
grep -Fq '# mwan3 多 WAN NAT6 操作指南' "$GUIDE" ||
	fail 'operations guide is not Traditional Chinese'
cmp -s "$GUIDE" "$PACKAGED_GUIDE" ||
	fail 'packaged Traditional Chinese operations guide is out of sync'

if command -v msgfmt >/dev/null 2>&1; then
	msgfmt --check --check-format -o /dev/null "$PO" ||
		fail 'English PO catalog failed gettext validation'
fi

node - "$SETTINGS" "$STATUS" "$MENU" "$PO" <<'NODE' || exit 1
const fs = require('fs');
const [settingsPath, statusPath, menuPath, poPath] = process.argv.slice(2);
const callPattern = /_\('((?:[^'\\]|\\.)*)'\)/g;
const decode = value => JSON.parse(`"${value}"`);
const required = new Set();

for (const path of [settingsPath, statusPath]) {
	const source = fs.readFileSync(path, 'utf8');
	for (const match of source.matchAll(callPattern)) {
		const msgid = match[1];
		if (msgid !== 'WAN' && !/[\u3400-\u9fff]/u.test(msgid))
			throw new Error(`base UI msgid is not Traditional Chinese: ${msgid}`);
		required.add(msgid);
	}
	if (/(?:配置|日志|链路|聚合带宽|啟用值)/u.test(source))
		throw new Error(`stiff or non-Traditional wording found in ${path}`);
}

const menu = JSON.parse(fs.readFileSync(menuPath, 'utf8'));
for (const key of ['admin/network/mwan3-nat6/status', 'admin/network/mwan3-nat6/settings'])
	required.add(menu[key].title);
if (menu['admin/network/mwan3-nat6/status'].title !== '狀態')
	throw new Error('status menu is not Traditional Chinese');
if (menu['admin/network/mwan3-nat6/settings'].title !== 'WAN 設定')
	throw new Error('settings menu is not natural Traditional Chinese');

const po = fs.readFileSync(poPath, 'utf8');
if (!po.includes('"Language: en\\n"'))
	throw new Error('PO Language header is not en');
const translations = new Map();
const entryPattern = /^msgid "((?:[^"\\]|\\.)*)"\nmsgstr "((?:[^"\\]|\\.)*)"/gm;
for (const match of po.matchAll(entryPattern)) {
	const msgid = decode(match[1]);
	const msgstr = decode(match[2]);
	if (!msgid)
		continue;
	if (!msgstr)
		throw new Error(`empty English translation: ${msgid}`);
	if (translations.has(msgid))
		throw new Error(`duplicate English msgid: ${msgid}`);
	translations.set(msgid, msgstr);
}
for (const msgid of required) {
	if (msgid === 'WAN')
		continue;
	if (!translations.has(msgid))
		throw new Error(`English pack is missing: ${msgid}`);
}
const expected = new Map([
	['全域設定', 'Global settings'],
	['WAN 設定', 'WAN Configuration'],
	['自動更新監看', 'Automatic renewal monitor'],
	['分流方式', 'Aggregation model'],
	['設定 WAN', 'Configure WANs'],
	['套用 N-WAN 規則', 'Apply N-WAN rules']
]);
for (const [msgid, msgstr] of expected) {
	if (translations.get(msgid) !== msgstr)
		throw new Error(`unexpected English translation for ${msgid}`);
}
process.stdout.write(`test-localization: ${required.size} UI msgids, ${translations.size} English entries PASS\n`);
NODE

printf '%s\n' 'test-localization: PASS'
