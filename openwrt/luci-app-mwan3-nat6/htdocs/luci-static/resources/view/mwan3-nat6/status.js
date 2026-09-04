'use strict';
'require rpc';
'require ui';
'require view';

var callStatus = rpc.declare({
	object: 'luci.mwan3-nat6',
	method: 'status',
	expect: { '': {} }
});

var callApply = rpc.declare({
	object: 'luci.mwan3-nat6',
	method: 'apply',
	expect: { '': {} }
});

function formatBytes(value) {
	var number = Number(value || 0);
	var units = [ 'B', 'KiB', 'MiB', 'GiB', 'TiB' ];
	var unit = 0;

	while (number >= 1024 && unit < units.length - 1) {
		number /= 1024;
		unit++;
	}

	return '%s %s'.format(number.toFixed(unit === 0 ? 0 : 1), units[unit]);
}

function stateLabel(state) {
	var labels = {
		'ready': _('就緒'),
		'down': _('未連線'),
		'unavailable': _('無法使用'),
		'invalid-live-device': _('目前的裝置名稱無效'),
		'unexpected-device': _('送出裝置不符'),
		'invalid-prefix-length': _('前綴長度無效'),
		'unexpected-prefix-length': _('前綴長度不符'),
		'invalid-address': _('WAN IPv6 位址無效'),
		'invalid-prefix': _('委派前綴無效')
	};

	return labels[state] || state || _('未知');
}

function profileLabel(profile) {
	var labels = {
		'managed': _('目前由本套件管理的 N-WAN 規則'),
		'managed-stale': _('本套件規則已過期或含無法使用的 WAN'),
		'unsafe': _('涵蓋範圍過大的不安全前綴規則'),
		'inactive': _('沒有 NAT6 鏈'),
		'unexpected': _('無法辨識的規則組'),
		'unknown': _('未知')
	};

	return labels[profile] || profile || _('未知');
}

function trackerLabel(tracker) {
	if (!tracker || !tracker.tracked)
		return _('未追蹤');
	var labels = {
		'online': _('上線'),
		'offline': _('離線'),
		'connecting': _('連線中'),
		'disconnecting': _('中斷連線中'),
		'unknown': _('未知')
	};
	return '%s (%s: %d)'.format(labels[tracker.state] || tracker.state,
		_('分數'), Number(tracker.score || 0));
}

function errorLabel(error) {
	var labels = {
		'required-command-missing': _('路由器缺少必要指令。'),
		'no-wans': _('尚未設定任何 WAN。'),
		'too-few-wans': _('至少要啟用兩條 WAN。'),
		'too-many-wans': _('啟用的 WAN 數量超過上限。'),
		'invalid-table': _('nftables 資料表名稱無效。'),
		'reserved-table': _('fw4 是 OpenWrt 共用的防火牆資料表，請改用專屬名稱。'),
		'invalid-monitor': _('自動監看設定無效。'),
		'invalid-refresh-mwan3-after-nat': _('mwan3 追蹤器更新設定無效。'),
		'invalid-pin-local-icmp': _('路由器本機的裝置綁定設定無效。'),
		'invalid-mwan3-mask': _('mwan3 標記遮罩無效或為零。'),
		'mwan3-policy-table-missing': _('找不到數字格式的 mwan3 IPv6 路由表。'),
		'mwan3-policy-table-ambiguous': _('同一個 WAN 裝置對應到多個 mwan3 IPv6 路由表。'),
		'invalid-monitor-interval': _('監看間隔必須介於 5 到 3600 秒。'),
		'invalid-monitor-debounce': _('穩定樣本數必須介於 1 到 10。'),
		'invalid-enabled': _('某個 WAN 的啟用狀態無效。'),
		'invalid-interface': _('某個 WAN 的邏輯介面名稱無效。'),
		'invalid-device': _('某個 WAN 的裝置名稱無效。'),
		'invalid-label': _('某個 WAN 的顯示名稱無效。'),
		'duplicate-interface': _('同一個邏輯介面被設定了多次。'),
		'duplicate-device': _('同一個目前使用的裝置被多條 WAN 重複使用。'),
		'invalid-index': _('位址或前綴索引必須介於 0 到 15。'),
		'invalid-expected-prefix-length': _('預期前綴長度必須介於 3 到 64。'),
		'temporary-file-failed': _('路由器無法建立暫存狀態檔。')
	};

	return labels[error] || error || _('未知的狀態錯誤。');
}

function dashboardStyles() {
	return E('style', {}, [
		'#mwan3-nat6-dashboard{--nat6-accent:#2563eb;--nat6-accent-2:#0f766e;--nat6-good:#059669;--nat6-warn:#d97706;--nat6-bad:#dc2626;--nat6-line:rgba(127,127,127,.24);--nat6-soft:rgba(127,127,127,.08);max-width:1180px;margin:0 auto}',
		'#mwan3-nat6-dashboard *{box-sizing:border-box}',
		'#mwan3-nat6-dashboard .mwan3-nat6-hero{position:relative;overflow:hidden;margin:0 0 1.25rem;padding:1.5rem;border-radius:1rem;background:linear-gradient(135deg,#173a8a 0%,#146b76 100%);box-shadow:0 12px 32px rgba(15,23,42,.18);color:#fff}',
		'#mwan3-nat6-dashboard .mwan3-nat6-hero:after{content:"";position:absolute;right:-4rem;bottom:-6rem;width:16rem;height:16rem;border:2.5rem solid rgba(255,255,255,.08);border-radius:50%}',
		'#mwan3-nat6-dashboard .mwan3-nat6-hero-content{position:relative;z-index:1;max-width:780px}',
		'#mwan3-nat6-dashboard .mwan3-nat6-eyebrow{margin:0 0 .45rem;font-size:.78rem;font-weight:700;letter-spacing:.08em;text-transform:uppercase;opacity:.82}',
		'#mwan3-nat6-dashboard .mwan3-nat6-title-row{display:flex;align-items:center;gap:.65rem;flex-wrap:wrap}',
		'#mwan3-nat6-dashboard .mwan3-nat6-title-row h2{margin:0;color:#fff;font-size:clamp(1.45rem,3vw,2.15rem);line-height:1.2}',
		'#mwan3-nat6-dashboard .mwan3-nat6-summary{margin:.85rem 0 0;max-width:68ch;font-size:1rem;line-height:1.65;color:rgba(255,255,255,.92)}',
		'#mwan3-nat6-dashboard .mwan3-nat6-error{margin:.65rem 0 0;padding:.6rem .75rem;border-radius:.55rem;background:rgba(127,29,29,.35)}',
		'#mwan3-nat6-dashboard .mwan3-nat6-error a{color:#fff;text-decoration:underline}',
		'#mwan3-nat6-dashboard .mwan3-nat6-badge{display:inline-flex;align-items:center;gap:.38rem;padding:.28rem .58rem;border-radius:999px;font-size:.76rem;font-weight:700;line-height:1.2;white-space:nowrap}',
		'#mwan3-nat6-dashboard .mwan3-nat6-badge:before{content:"";width:.48rem;height:.48rem;border-radius:50%;background:currentColor}',
		'#mwan3-nat6-dashboard .mwan3-nat6-badge.good{color:#047857;background:rgba(16,185,129,.14)}',
		'#mwan3-nat6-dashboard .mwan3-nat6-badge.warning{color:#b45309;background:rgba(245,158,11,.16)}',
		'#mwan3-nat6-dashboard .mwan3-nat6-badge.danger{color:#b91c1c;background:rgba(239,68,68,.14)}',
		'#mwan3-nat6-dashboard .mwan3-nat6-hero .mwan3-nat6-badge{color:#fff;background:rgba(255,255,255,.16);border:1px solid rgba(255,255,255,.28)}',
		'#mwan3-nat6-dashboard .mwan3-nat6-metric-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:.8rem;margin:0 0 1.25rem}',
		'#mwan3-nat6-dashboard .mwan3-nat6-metric{min-width:0;padding:1rem;border:1px solid var(--nat6-line);border-radius:.8rem;background:var(--nat6-soft)}',
		'#mwan3-nat6-dashboard .mwan3-nat6-metric-label{margin:0 0 .35rem;font-size:.78rem;font-weight:700;opacity:.66}',
		'#mwan3-nat6-dashboard .mwan3-nat6-metric-value{display:block;margin:0 0 .28rem;font-size:1.45rem;font-weight:750;line-height:1.2;overflow-wrap:anywhere}',
		'#mwan3-nat6-dashboard .mwan3-nat6-metric-detail{font-size:.78rem;line-height:1.45;opacity:.7}',
		'#mwan3-nat6-dashboard .mwan3-nat6-section{margin:0 0 1.1rem;padding:1.15rem;border:1px solid var(--nat6-line);border-radius:.9rem;background:rgba(127,127,127,.035)}',
		'#mwan3-nat6-dashboard .mwan3-nat6-section-head{display:flex;align-items:flex-start;justify-content:space-between;gap:1rem;margin:0 0 .9rem}',
		'#mwan3-nat6-dashboard .mwan3-nat6-section h3{margin:0 0 .25rem;font-size:1.08rem}',
		'#mwan3-nat6-dashboard .mwan3-nat6-section-intro{margin:0;font-size:.84rem;line-height:1.5;opacity:.68}',
		'#mwan3-nat6-dashboard .mwan3-nat6-wan-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(245px,1fr));gap:.8rem}',
		'#mwan3-nat6-dashboard .mwan3-nat6-wan{min-width:0;padding:1rem;border:1px solid var(--nat6-line);border-top:3px solid var(--nat6-good);border-radius:.75rem;background:var(--nat6-soft)}',
		'#mwan3-nat6-dashboard .mwan3-nat6-wan.warning{border-top-color:var(--nat6-warn)}',
		'#mwan3-nat6-dashboard .mwan3-nat6-wan.danger{border-top-color:var(--nat6-bad)}',
		'#mwan3-nat6-dashboard .mwan3-nat6-wan-head{display:flex;align-items:flex-start;justify-content:space-between;gap:.75rem;margin-bottom:.8rem}',
		'#mwan3-nat6-dashboard .mwan3-nat6-wan h4{margin:0 0 .18rem;font-size:1rem;overflow-wrap:anywhere}',
		'#mwan3-nat6-dashboard .mwan3-nat6-identity{font-size:.75rem;opacity:.62;overflow-wrap:anywhere}',
		'#mwan3-nat6-dashboard .mwan3-nat6-prefix{margin:0 0 .85rem;padding:.58rem .65rem;border-radius:.5rem;background:rgba(127,127,127,.1);font-family:monospace;font-size:.8rem;overflow-wrap:anywhere}',
		'#mwan3-nat6-dashboard .mwan3-nat6-data-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.65rem}',
		'#mwan3-nat6-dashboard .mwan3-nat6-data-label{display:block;margin-bottom:.15rem;font-size:.7rem;font-weight:700;opacity:.58}',
		'#mwan3-nat6-dashboard .mwan3-nat6-data-value{display:block;font-size:.86rem;font-weight:650;overflow-wrap:anywhere}',
		'#mwan3-nat6-dashboard .mwan3-nat6-detail-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:.8rem}',
		'#mwan3-nat6-dashboard .mwan3-nat6-detail{padding:.85rem;border-left:3px solid var(--nat6-accent);border-radius:.3rem .65rem .65rem .3rem;background:var(--nat6-soft)}',
		'#mwan3-nat6-dashboard .mwan3-nat6-detail h4{margin:0 0 .4rem;font-size:.9rem}',
		'#mwan3-nat6-dashboard .mwan3-nat6-detail p{margin:0;font-size:.82rem;line-height:1.55}',
		'#mwan3-nat6-dashboard .mwan3-nat6-comparison{overflow-x:auto}',
		'#mwan3-nat6-dashboard .mwan3-nat6-note{margin:.8rem 0 0;font-size:.8rem;line-height:1.55;opacity:.7}',
		'#mwan3-nat6-dashboard .cbi-page-actions{display:flex;justify-content:flex-end;gap:.5rem;flex-wrap:wrap;margin-top:1rem}',
		'@media (prefers-color-scheme:dark){#mwan3-nat6-dashboard .mwan3-nat6-badge.good{color:#6ee7b7}#mwan3-nat6-dashboard .mwan3-nat6-badge.warning{color:#fbbf24}#mwan3-nat6-dashboard .mwan3-nat6-badge.danger{color:#fca5a5}}',
		'@media (max-width:900px){#mwan3-nat6-dashboard .mwan3-nat6-metric-grid{grid-template-columns:repeat(2,minmax(0,1fr))}#mwan3-nat6-dashboard .mwan3-nat6-detail-grid{grid-template-columns:1fr}}',
		'@media (max-width:520px){#mwan3-nat6-dashboard .mwan3-nat6-hero{padding:1.15rem}#mwan3-nat6-dashboard .mwan3-nat6-metric-grid{grid-template-columns:1fr}#mwan3-nat6-dashboard .mwan3-nat6-section{padding:.9rem}#mwan3-nat6-dashboard .mwan3-nat6-wan-grid{grid-template-columns:1fr}#mwan3-nat6-dashboard .cbi-page-actions .btn{width:100%;text-align:center}}'
	]);
}

function badge(label, tone) {
	return E('span', { 'class': 'mwan3-nat6-badge ' + tone }, label);
}

function interfaceTone(item) {
	if (item.state === 'ready' && (!item.tracker || !item.tracker.tracked || item.tracker.state === 'online'))
		return 'good';
	if (item.state === 'down' || item.state === 'unavailable' || (item.tracker && item.tracker.state === 'offline'))
		return 'warning';
	return 'danger';
}

function metricCard(label, value, detail) {
	return E('div', { 'class': 'mwan3-nat6-metric' }, [
		E('div', { 'class': 'mwan3-nat6-metric-label' }, label),
		E('strong', { 'class': 'mwan3-nat6-metric-value' }, value),
		E('div', { 'class': 'mwan3-nat6-metric-detail' }, detail)
	]);
}

function interfaceCards(interfaces) {
	if (!interfaces || !interfaces.length)
		return E('p', { 'class': 'mwan3-nat6-note' }, _('目前沒有可顯示的 WAN 狀態。'));

	return E('div', { 'class': 'mwan3-nat6-wan-grid' }, interfaces.map(function(item) {
		var tone = interfaceTone(item);
		var errors = Number(item.rx_errors || 0) + Number(item.tx_errors || 0);
		var dropped = Number(item.rx_dropped || 0) + Number(item.tx_dropped || 0);

		return E('article', { 'class': 'mwan3-nat6-wan ' + tone }, [
			E('div', { 'class': 'mwan3-nat6-wan-head' }, [
				E('div', {}, [
					E('h4', {}, item.label || item.logical || '-'),
					E('div', { 'class': 'mwan3-nat6-identity' },
						'%s · %s'.format(item.logical || '-', item.device || '-'))
				]),
				badge(stateLabel(item.state), tone)
			]),
			E('div', { 'class': 'mwan3-nat6-prefix' }, item.prefix || '-'),
			E('div', { 'class': 'mwan3-nat6-data-grid' }, [
				E('div', {}, [
					E('span', { 'class': 'mwan3-nat6-data-label' }, _('mwan3 追蹤')),
					E('span', { 'class': 'mwan3-nat6-data-value' }, trackerLabel(item.tracker))
				]),
				E('div', {}, [
					E('span', { 'class': 'mwan3-nat6-data-label' }, _('接收 / 傳送')),
					E('span', { 'class': 'mwan3-nat6-data-value' },
						'%s / %s'.format(formatBytes(item.rx_bytes), formatBytes(item.tx_bytes)))
				]),
				E('div', {}, [
					E('span', { 'class': 'mwan3-nat6-data-label' }, _('錯誤')),
					E('span', { 'class': 'mwan3-nat6-data-value' }, String(errors))
				]),
				E('div', {}, [
					E('span', { 'class': 'mwan3-nat6-data-label' }, _('丟棄')),
					E('span', { 'class': 'mwan3-nat6-data-value' }, String(dropped))
				])
			])
		]);
	}));
}

function detailCard(title, content) {
	return E('div', { 'class': 'mwan3-nat6-detail' }, [
		E('h4', {}, title),
		E('p', {}, content)
	]);
}

function sectionCard(title, description, content) {
	return E('section', { 'class': 'mwan3-nat6-section' }, [
		E('div', { 'class': 'mwan3-nat6-section-head' }, [
			E('div', {}, [
				E('h3', {}, title),
				E('p', { 'class': 'mwan3-nat6-section-intro' }, description)
			])
		]),
		content
	]);
}

function comparisonTable(activeWanCount, configuredWanCount) {
	var active = Number(activeWanCount || 0);
	var configured = Number(configuredWanCount || 0);
	var activeRules = active * active;

	return E('table', { 'class': 'table' }, [
		E('tr', { 'class': 'tr table-titles' }, [
			E('th', { 'class': 'th' }, _('模式')),
			E('th', { 'class': 'th' }, _('可用 WAN')),
			E('th', { 'class': 'th' }, _('產生的 NAT 規則')),
			E('th', { 'class': 'th' }, _('分流能力'))
		]),
		E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td' }, _('雙 WAN 範例')),
			E('td', { 'class': 'td' }, '2'),
			E('td', { 'class': 'td' }, '4'),
			E('td', { 'class': 'td' }, _('多條獨立連線最多可使用兩條線路'))
		]),
		E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td' }, _('目前就緒的 WAN')),
			E('td', { 'class': 'td' }, '%d / %d'.format(active, configured)),
			E('td', { 'class': 'td' }, String(activeRules)),
			E('td', { 'class': 'td' }, _('多條獨立連線最多可使用所有已就緒線路'))
		])
	]);
}

return view.extend({
	load: function() {
		return L.resolveDefault(callStatus(), {
			ok: false,
			ready: false,
			all_ready: false,
			degraded: false,
			policy_ready: false,
			error: 'status-failed',
			interfaces: [],
			nat: { present: false, wan_count: 0, active_wan_count: 0, inactive_wan_count: 0, rule_count: 0, expected_rule_count: 0, profile: 'unknown' },
			local_icmp: { enabled: false, present: false, rule_count: 0, expected_rule_count: 0, mark: '', routing_rule_count: 0, expected_routing_rule_count: 0, routing_priority: 1500, profile: 'disabled' }
		});
	},

	handleApply: function(ev) {
		var button = ev.currentTarget;
		button.disabled = true;
		button.classList.add('spinning');

		return callApply().then(function(result) {
			if (!result || !result.ok)
				throw new Error(_('套用失敗，請執行 logread -e nft-nat6 查看記錄。'));

			ui.addNotification(null, E('p', _('N-WAN NAT6 規則已成功套用。')), 'info');
			window.setTimeout(function() { window.location.reload(); }, 500);
		}, function(error) {
			button.disabled = false;
			button.classList.remove('spinning');
			ui.addNotification(null, E('p', error.message), 'error');
		}).catch(function(error) {
			button.disabled = false;
			button.classList.remove('spinning');
			ui.addNotification(null, E('p', error.message), 'error');
		});
	},

	render: function(status) {
		var nat = status.nat || {};
		var localIcmp = status.local_icmp || {};
		var monitor = status.monitor || {};
		var wanCount = Number(nat.wan_count || 0);
		var activeWanCount = Number(nat.active_wan_count || 0);
		var degraded = status.degraded === true || activeWanCount < wanCount;
		var localIcmpHealthy = !localIcmp.enabled || localIcmp.profile === 'managed';
		var applyAllowed = status.ready && nat.profile !== 'unexpected' && localIcmp.profile !== 'unexpected';
		var healthy = status.ok && status.ready && status.policy_ready !== false && nat.profile === 'managed' && localIcmpHealthy;
		var tone = healthy && !degraded ? 'good' : (status.ok && status.ready ? 'warning' : 'danger');
		var headline = healthy && !degraded
			? _('所有線路皆正常')
			: (healthy ? _('部分線路暫時排除') : _('NAT6 需要檢查'));
		var heroBadge = healthy && !degraded
			? _('運作正常')
			: (healthy ? _('部分可用') : _('需要處理'));
		var summary = healthy && degraded
			? _('%d / %d 條已設定的 WAN 已就緒。NAT6 會繼續服務目前就緒的 WAN；無法使用的 WAN 將暫時排除，待恢復後再自動加入。').format(activeWanCount, wanCount)
			: (healthy
			? _('%d 條 WAN 已就緒，對應的 mwan3 追蹤成員均已上線，精確的 NAT6 管理規則也已生效。').format(activeWanCount)
			: (status.ok && status.ready && nat.profile === 'managed' && status.policy_ready === false
				? _('就緒 WAN 的 NAT6 規則已是最新狀態，但其中一個受追蹤的 mwan3 成員目前離線。')
				: _('NAT6 需要處理。套用前請檢查 WAN 設定、安全檢查與目前的規則狀態。')));
		var error = status.ok ? null : E('p', { 'class': 'mwan3-nat6-error' }, [
			errorLabel(status.error),
			' ',
			E('a', { 'href': L.url('admin/network/mwan3-nat6/settings') }, _('開啟 WAN 設定'))
		]);

		return E('div', { 'id': 'mwan3-nat6-dashboard' }, [
			dashboardStyles(),
			E('header', { 'class': 'mwan3-nat6-hero ' + tone, 'role': 'status', 'aria-live': 'polite' }, [
				E('div', { 'class': 'mwan3-nat6-hero-content' }, [
					E('p', { 'class': 'mwan3-nat6-eyebrow' }, _('IPv6 多 WAN 前綴轉換')),
					E('div', { 'class': 'mwan3-nat6-title-row' }, [
						E('h2', {}, headline),
						badge(heroBadge, tone)
					]),
					E('p', { 'class': 'mwan3-nat6-summary' }, summary),
					error
				])
			]),
			E('div', { 'class': 'mwan3-nat6-metric-grid', 'aria-label': _('運作概況') }, [
				metricCard(_('就緒 WAN'), '%d / %d'.format(activeWanCount, wanCount),
					activeWanCount === wanCount ? _('全部已設定線路均可用') : _('%d 條線路暫時排除').format(wanCount - activeWanCount)),
				metricCard(_('NAT6 規則'), '%d / %d'.format(Number(nat.rule_count || 0), Number(nat.expected_rule_count || 0)),
					profileLabel(nat.profile)),
				metricCard(_('本機路由'), localIcmp.enabled ? _('已啟用') : _('未啟用'),
					localIcmp.enabled ? _('%d / %d 條路由規則').format(
						Number(localIcmp.routing_rule_count || 0), Number(localIcmp.expected_routing_rule_count || 0)) : _('依照現有 mwan3 策略')),
				metricCard(_('自動監看'), monitor.enabled ? _('運作中') : _('未啟用'),
					monitor.enabled ? _('每 %d 秒 · %d 個穩定樣本').format(
						Number(monitor.interval || 0), Number(monitor.debounce || 0)) : _('規則只會手動更新'))
			]),
			sectionCard(_('WAN 與流量計數'),
				_('快速查看每條線路的連線、追蹤、前綴與累計流量。比較策略時，請記錄相同多連線負載前後的差值。'),
				interfaceCards(status.interfaces)),
			sectionCard(_('規則與自動化'),
				_('這些功能只管理本套件的專屬規則，不會變更 mwan3 權重。'),
				E('div', { 'class': 'mwan3-nat6-detail-grid' }, [
					detailCard(_('已安裝的 NAT6 規則'), [
						_('資料表：'), E('strong', {}, nat.table || '-'), E('br'),
						_('偵測到的規則狀態：'), E('strong', {}, profileLabel(nat.profile)), E('br'),
						_('%d / %d 條預期規則').format(Number(nat.rule_count || 0), Number(nat.expected_rule_count || 0))
					]),
					detailCard(_('路由器本機的裝置綁定'), localIcmp.enabled
						? _('已啟用：精確 ICMPv6 規則 %d / %d 條、初始路由規則 %d / %d 條；略過標記為 %s，RPDB 優先序為 %d，狀態為 %s。').format(
							Number(localIcmp.rule_count || 0), Number(localIcmp.expected_rule_count || 0),
							Number(localIcmp.routing_rule_count || 0), Number(localIcmp.expected_routing_rule_count || 0),
							localIcmp.mark || '-', Number(localIcmp.routing_priority || 0), localIcmp.profile || 'unknown')
						: _('未啟用。路由器本機的指定裝置診斷仍依照現有 mwan3/OpenClash 策略。')),
					detailCard(_('自動更新監看狀態'), monitor.enabled
						? _('已啟用：每 %d 秒檢查一次，連續 %d 個樣本穩定後動作；mwan3 追蹤器更新為%s。').format(
							Number(monitor.interval || 0), Number(monitor.debounce || 0),
							monitor.refresh_mwan3 ? _('已啟用') : _('已停用'))
						: _('未啟用。在「WAN 設定」中啟用監看前，只能手動套用規則。'))
				])),
			sectionCard(_('分流方式'),
				_('多條獨立連線可以分散到不同 WAN；單一連線仍只會使用一條線路。'),
				E('div', { 'class': 'mwan3-nat6-comparison' }, [
					comparisonTable(activeWanCount, wanCount),
					E('p', { 'class': 'mwan3-nat6-note' }, _('N 條就緒的 WAN 會產生 N² 條 NAT 規則。前綴 NAT 無法合併單一 TCP 或 QUIC 連線；mwan3 會分配不同連線，而本頁面絕不變更 mwan3 權重。'))
				])),
			E('div', { 'class': 'cbi-page-actions' }, [
				E('a', { 'class': 'btn cbi-button-neutral', 'href': L.url('admin/network/mwan3-nat6/settings') }, _('設定 WAN')),
				' ',
				E('button', {
					'class': 'btn cbi-button-neutral',
					'click': function() { window.location.reload(); }
				}, _('重新整理')),
				' ',
				E('button', {
					'class': 'btn cbi-button-action important',
					'disabled': applyAllowed ? null : 'disabled',
					'title': applyAllowed ? '' : _('至少要有一條 WAN 就緒，而且現有規則鏈必須能安全辨識，才可套用。'),
					'click': ui.createHandlerFn(this, 'handleApply')
				}, _('套用 N-WAN 規則'))
			])
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
