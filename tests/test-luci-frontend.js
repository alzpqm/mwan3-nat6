'use strict';

// Execute the actual LuCI views without a router. Layout is checked separately
// in tests/luci-layout.html using a real browser and the upstream theme CSS.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const viewRoot = path.join(root, 'openwrt/luci-app-mwan3-nat6/htdocs/luci-static/resources/view/mwan3-nat6');
const statusSource = fs.readFileSync(process.env.NAT6_TEST_STATUS || path.join(viewRoot, 'status.js'), 'utf8');
const settingsSource = fs.readFileSync(process.env.NAT6_TEST_SETTINGS || path.join(viewRoot, 'settings.js'), 'utf8');

function element(tag, attrs, children) {
	if (arguments.length === 2 && (typeof attrs !== 'object' || Array.isArray(attrs))) {
		children = attrs;
		attrs = {};
	}
	// LuCI stringifies null children inside arrays; do not hide that behavior.
	return { tag, attrs: attrs || {}, children: children == null ? [] : [].concat(children).map(child => child === null ? 'null' : child) };
}
function nodes(node) {
	return node && typeof node === 'object' ? [node, ...node.children.flatMap(nodes)] : [];
}
function text(node) {
	return node == null ? '' : (typeof node === 'object' ? node.children.map(text).join('') : String(node));
}
function healthyStatus() {
	return {
		ok: true, ready: true, all_ready: true, degraded: false, policy_ready: true,
		interfaces: [{ label: 'WAN 1', logical: 'wan1_6', device: 'pppoe-wan1', state: 'ready',
			prefix: '2001:db8:1::/56', tracker: { tracked: true, state: 'online', score: 10 } }],
		nat: { table: 'mwan3_nat6', wan_count: 2, active_wan_count: 2, rule_count: 4, expected_rule_count: 4, profile: 'managed' },
		local_icmp: { enabled: false, profile: 'disabled', rule_count: 0, routing_rule_count: 0 },
		monitor: { enabled: true, interval: 15, debounce: 2, refresh_mwan3: false }
	};
}
function loadStatus(writable = true) {
	const calls = [], notices = [], timers = [];
	let result = { ok: true }, failure = null;
	const context = vm.createContext({
		E: element, _: value => value, view: { extend: value => value },
		L: { hasViewPermission: () => writable, url: value => value,
			resolveDefault: (promise, fallback) => promise.catch(() => fallback) },
		rpc: { declare: spec => () => {
			calls.push(spec.method);
			return failure ? Promise.reject(failure) : Promise.resolve(result);
		} },
		ui: { addNotification: (...args) => notices.push(args), createHandlerFn: (view, name) => view[name].bind(view) },
		window: { setTimeout: fn => timers.push(fn), location: { reload() {} } }
	});
	vm.runInContext("String.prototype.format = function(...args) { let i = 0; return this.replace(/%[sd]/g, () => String(args[i++])); };", context);
	const view = vm.runInContext('(function() {\n' + statusSource + '\n})()', context);
	return { view, calls, notices, timers, setResult: value => { result = value; }, setFailure: value => { failure = value; } };
}
function applyButton(tree) {
	return nodes(tree).find(n => n.tag === 'button' && text(n) === '套用 N-WAN 規則');
}
function mockButton() {
	const classes = new Set();
	return { disabled: false, classList: { add: value => classes.add(value), remove: value => classes.delete(value) }, classes };
}

let count = 0;
async function test(name, check) {
	await check();
	count++;
	console.log('PASS ' + name);
}
async function main() {
	await test('dashboard does not inherit theme navigation header styles', () => {
		const tree = loadStatus().view.render(healthyStatus());
		assert.equal(nodes(tree).filter(n => n.tag === 'header').length, 0);
		assert.ok(nodes(tree).some(n => n.attrs.role === 'status' && n.attrs['aria-live'] === 'polite'));
	});
	await test('read-only users cannot submit Apply, including direct handler calls', async () => {
		const app = loadStatus(false), button = mockButton();
		assert.equal(applyButton(app.view.render(healthyStatus())).attrs.disabled, 'disabled');
		await app.view.handleApply({ currentTarget: button });
		assert.deepEqual(app.calls, []);
	});
	await test('healthy dashboard contains no null placeholder text', () => {
		assert.ok(!text(loadStatus().view.render(healthyStatus())).includes('null'));
	});
	await test('Apply eligibility refuses invalid and foreign states; permits repair', () => {
		const app = loadStatus();
		for (const [area, value] of [['ok', false], ['ready', false], ['nat', 'unexpected'], ['local_icmp', 'unexpected']]) {
			const status = healthyStatus();
			if (typeof value === 'boolean') status[area] = value;
			else status[area].profile = value;
			assert.equal(applyButton(app.view.render(status)).attrs.disabled, 'disabled', area);
		}
		for (const profile of ['managed', 'managed-stale', 'inactive', 'unsafe']) {
			const status = healthyStatus();
			status.nat.profile = profile;
			assert.equal(applyButton(app.view.render(status)).attrs.disabled, null, profile);
		}
	});
	await test('disabled local pin with residual rules is not reported healthy', () => {
		for (const profile of ['managed-stale', 'unexpected']) {
			const status = healthyStatus();
			status.local_icmp.profile = profile;
			status.local_icmp.routing_rule_count = 2;
			const tree = loadStatus().view.render(status);
			assert.ok(!text(tree).includes('所有線路皆正常'));
			assert.ok(text(tree).includes('設定已停用，但仍有本機路由規則'));
		}
	});
	await test('monitor config does not claim the service is running', () => {
		const tree = loadStatus().view.render(healthyStatus());
		const metric = nodes(tree).find(n => n.attrs.class === 'mwan3-nat6-metric' && text(n).startsWith('自動監看'));
		assert.ok(text(metric).includes('已啟用'));
		assert.ok(!text(metric).includes('運作中'));
	});
	await test('RPC failure renders an actionable message and disables Apply', async () => {
		const app = loadStatus();
		app.setFailure(new Error('offline'));
		const tree = app.view.render(await app.view.load());
		assert.ok(text(tree).includes('無法取得 NAT6 狀態，請檢查連線後重新整理。'));
		assert.equal(applyButton(tree).attrs.disabled, 'disabled');
	});
	await test('Apply failures release the button and show one notification', async () => {
		for (const transport of [false, true]) {
			const app = loadStatus(), button = mockButton();
			if (transport) app.setFailure(new Error('offline'));
			else app.setResult({ ok: false });
			await app.view.handleApply({ currentTarget: button });
			assert.equal(button.disabled, false);
			assert.equal(button.classes.has('spinning'), false);
			assert.equal(app.notices.length, 1);
			assert.deepEqual(app.calls, ['apply']);
			assert.equal(app.timers.length, 0);
		}
	});
	await test('successful Apply submits exactly once and schedules refresh', async () => {
		const app = loadStatus();
		await app.view.handleApply({ currentTarget: mockButton() });
		assert.deepEqual(app.calls, ['apply']);
		assert.equal(app.notices.length, 1);
		assert.equal(app.timers.length, 1);
	});
	await test('numeric UCI fields require integers and retain range bounds', () => {
		const options = new Map();
		const form = { Map: function() {
			this.section = () => ({ option: (type, name) => {
				const option = { depends() {} };
				options.set(name, option);
				return option;
			} });
			this.render = () => options;
		} };
		const view = vm.runInNewContext('(function() {\n' + settingsSource + '\n})()', {
			form, uci: { load: () => Promise.resolve() }, view: { extend: value => value }, _: value => value
		});
		view.render();
		for (const [name, min, max] of [['interval', 5, 3600], ['debounce', 1, 10], ['expected_prefix_length', 3, 64], ['address_index', 0, 15], ['prefix_index', 0, 15]])
			assert.equal(options.get(name).datatype, `and(uinteger,range(${min},${max}))`, name);
		assert.equal(options.get('table').validate(null, 'fw4') === true, false);
		assert.equal(options.get('table').validate(null, 'mwan3_nat6'), true);
		assert.equal(options.get('device').validate(null, 'device-name-too-long') === true, false);
		assert.equal(options.get('device').validate(null, ''), true);
	});
	console.log(`test-luci-frontend: PASS (${count} behavioral cases)`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
