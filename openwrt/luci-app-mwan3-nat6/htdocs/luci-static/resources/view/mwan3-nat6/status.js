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

function interfaceTable(interfaces) {
	var table = E('table', { 'class': 'table' }, [
		E('tr', { 'class': 'tr table-titles' }, [
			E('th', { 'class': 'th' }, _('WAN')),
			E('th', { 'class': 'th' }, _('netifd 狀態')),
			E('th', { 'class': 'th' }, _('mwan3 追蹤')),
			E('th', { 'class': 'th' }, _('委派前綴')),
			E('th', { 'class': 'th' }, _('接收 / 傳送')),
			E('th', { 'class': 'th' }, _('錯誤 / 丟棄'))
		])
	]);

	(interfaces || []).forEach(function(item) {
		table.appendChild(E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td' }, [
				E('strong', {}, item.label || item.logical || '-'),
				E('br'),
				E('small', {}, '%s · %s'.format(item.logical || '-', item.device || '-'))
			]),
			E('td', { 'class': 'td' }, stateLabel(item.state)),
			E('td', { 'class': 'td' }, trackerLabel(item.tracker)),
			E('td', { 'class': 'td' }, item.prefix || '-'),
			E('td', { 'class': 'td' },
				'%s / %s'.format(formatBytes(item.rx_bytes), formatBytes(item.tx_bytes))),
			E('td', { 'class': 'td' },
				'%s / %s'.format(
					Number(item.rx_errors || 0) + Number(item.tx_errors || 0),
					Number(item.rx_dropped || 0) + Number(item.tx_dropped || 0)))
		]));
	});

	return table;
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
		var summary = healthy && degraded
			? _('%d / %d 條已設定的 WAN 已就緒。NAT6 會繼續服務目前就緒的 WAN；無法使用的 WAN 將暫時排除，待恢復後再自動加入。').format(activeWanCount, wanCount)
			: (healthy
			? _('%d 條 WAN 已就緒，對應的 mwan3 追蹤成員均已上線，精確的 NAT6 管理規則也已生效。').format(activeWanCount)
			: (status.ok && status.ready && nat.profile === 'managed' && status.policy_ready === false
				? _('就緒 WAN 的 NAT6 規則已是最新狀態，但其中一個受追蹤的 mwan3 成員目前離線。')
				: _('NAT6 需要處理。套用前請檢查 WAN 設定、安全檢查與目前的規則狀態。')));
		var error = status.ok ? null : E('p', {}, [
			errorLabel(status.error),
			' ',
			E('a', { 'href': L.url('admin/network/mwan3-nat6/settings') }, _('開啟 WAN 設定'))
		]);

		return E('div', {}, [
			E('h2', {}, _('mwan3 多 WAN NAT6')),
			E('div', { 'class': healthy && !degraded ? 'alert-message success' : 'alert-message warning' }, [ summary, error ]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('WAN 與流量計數')),
				E('p', {}, _('計數值會持續累加。比較策略時，請在相同的多連線負載前後記錄差值。')),
				interfaceTable(status.interfaces)
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('已安裝的 NAT6 規則')),
				E('p', {}, [
					_('資料表：'), E('strong', {}, nat.table || '-'), ' — ',
					_('偵測到的規則狀態：'), E('strong', {}, profileLabel(nat.profile)), ' — ',
					_('%d / %d 條預期規則').format(
						Number(nat.rule_count || 0), Number(nat.expected_rule_count || 0))
				])
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('路由器本機的裝置綁定')),
				E('p', {}, localIcmp.enabled
					? _('已啟用：精確 ICMPv6 規則 %d / %d 條、初始路由規則 %d / %d 條；略過標記為 %s，RPDB 優先序為 %d，狀態為 %s。').format(
						Number(localIcmp.rule_count || 0), Number(localIcmp.expected_rule_count || 0),
						Number(localIcmp.routing_rule_count || 0), Number(localIcmp.expected_routing_rule_count || 0),
						localIcmp.mark || '-', Number(localIcmp.routing_priority || 0), localIcmp.profile || 'unknown')
					: _('未啟用。路由器本機的指定裝置診斷仍依照現有 mwan3/OpenClash 策略。'))
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('自動更新監看狀態')),
				E('p', {}, monitor.enabled
					? _('已啟用：每 %d 秒檢查一次，連續 %d 個樣本穩定後動作；mwan3 追蹤器更新為%s。').format(
						Number(monitor.interval || 0), Number(monitor.debounce || 0),
						monitor.refresh_mwan3 ? _('已啟用') : _('已停用'))
					: _('未啟用。在「WAN 設定」中啟用監看前，只能手動套用規則。'))
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('分流方式')),
				comparisonTable(activeWanCount, wanCount),
				E('p', {}, _('N 條就緒的 WAN 會產生 N² 條 NAT 規則。前綴 NAT 無法合併單一 TCP 或 QUIC 連線；mwan3 會分配不同連線，而本頁面絕不變更 mwan3 權重。'))
			]),
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
