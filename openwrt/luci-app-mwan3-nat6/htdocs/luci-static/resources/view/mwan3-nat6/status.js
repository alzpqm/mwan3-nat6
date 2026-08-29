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
		'ready': _('Ready'),
		'down': _('Down'),
		'unavailable': _('Unavailable'),
		'invalid-live-device': _('Invalid live device'),
		'unexpected-device': _('Unexpected device'),
		'invalid-prefix-length': _('Invalid prefix length'),
		'unexpected-prefix-length': _('Unexpected prefix length'),
		'invalid-address': _('Invalid WAN IPv6 address'),
		'invalid-prefix': _('Invalid delegated prefix')
	};

	return labels[state] || state || _('Unknown');
}

function profileLabel(profile) {
	var labels = {
		'managed': _('Current managed N-WAN rules'),
		'managed-stale': _('Managed rules with stale or unavailable WAN data'),
		'unsafe': _('Unsafe broad prefix rules'),
		'inactive': _('No NAT6 chain'),
		'unexpected': _('Unexpected rule set'),
		'unknown': _('Unknown')
	};

	return labels[profile] || profile || _('Unknown');
}

function trackerLabel(tracker) {
	if (!tracker || !tracker.tracked)
		return _('Not tracked');
	var labels = {
		'online': _('Online'),
		'offline': _('Offline'),
		'connecting': _('Connecting'),
		'disconnecting': _('Disconnecting'),
		'unknown': _('Unknown')
	};
	return '%s (%s: %d)'.format(labels[tracker.state] || tracker.state,
		_('score'), Number(tracker.score || 0));
}

function errorLabel(error) {
	var labels = {
		'required-command-missing': _('A required router command is missing.'),
		'no-wans': _('No WAN sections are configured.'),
		'too-few-wans': _('At least two WANs must be enabled.'),
		'too-many-wans': _('Too many WANs are enabled.'),
		'invalid-table': _('The nftables table name is invalid.'),
		'invalid-monitor': _('The automatic monitor setting is invalid.'),
		'invalid-refresh-mwan3-after-nat': _('The optional mwan3 refresh setting is invalid.'),
		'invalid-pin-local-icmp': _('The router-local ICMPv6 pin setting is invalid.'),
		'invalid-mwan3-mask': _('The mwan3 mark mask is invalid or zero.'),
		'mwan3-policy-table-missing': _('No numeric mwan3 IPv6 policy table was found.'),
		'mwan3-policy-table-ambiguous': _('A WAN device maps to more than one mwan3 IPv6 policy table.'),
		'invalid-monitor-interval': _('The monitor interval is outside 5-3600 seconds.'),
		'invalid-monitor-debounce': _('The monitor debounce is outside 1-10 samples.'),
		'invalid-enabled': _('A WAN has an invalid enabled value.'),
		'invalid-interface': _('A WAN has an invalid logical interface.'),
		'invalid-device': _('A WAN has an invalid device.'),
		'invalid-label': _('A WAN has an invalid label.'),
		'duplicate-interface': _('A logical interface is configured more than once.'),
		'duplicate-device': _('A live device is used by more than one WAN.'),
		'invalid-index': _('An address or prefix index is outside 0-15.'),
		'invalid-expected-prefix-length': _('An expected prefix length is outside 3-64.'),
		'temporary-file-failed': _('The router could not create a temporary state file.')
	};

	return labels[error] || error || _('Unknown status error.');
}

function interfaceTable(interfaces) {
	var table = E('table', { 'class': 'table' }, [
		E('tr', { 'class': 'tr table-titles' }, [
			E('th', { 'class': 'th' }, _('WAN')),
			E('th', { 'class': 'th' }, _('netifd state')),
			E('th', { 'class': 'th' }, _('mwan3 tracker')),
			E('th', { 'class': 'th' }, _('Delegated prefix')),
			E('th', { 'class': 'th' }, _('RX / TX')),
			E('th', { 'class': 'th' }, _('Errors / drops'))
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
			E('th', { 'class': 'th' }, _('Profile')),
			E('th', { 'class': 'th' }, _('Eligible WANs')),
			E('th', { 'class': 'th' }, _('Generated NAT rules')),
			E('th', { 'class': 'th' }, _('Aggregate behavior'))
		]),
		E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td' }, _('Two-WAN example')),
			E('td', { 'class': 'td' }, '2'),
			E('td', { 'class': 'td' }, '4'),
			E('td', { 'class': 'td' }, _('Up to two links across independent connections'))
		]),
		E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td' }, _('Current ready subset')),
			E('td', { 'class': 'td' }, '%d / %d'.format(active, configured)),
			E('td', { 'class': 'td' }, String(activeRules)),
			E('td', { 'class': 'td' }, _('Up to the ready links across independent connections'))
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
				throw new Error(_('Apply failed. Check logread -e nft-nat6.'));

			ui.addNotification(null, E('p', _('N-WAN NAT6 rules were applied successfully.')), 'info');
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
		var healthy = status.ok && status.ready && status.policy_ready !== false && nat.profile === 'managed' && localIcmpHealthy;
		var summary = healthy && degraded
			? _('%d of %d configured WANs are ready. NAT6 remains active for the ready subset; unavailable WANs are excluded until they recover.').format(activeWanCount, wanCount)
			: (healthy
			? _('%d WANs are ready, their tracked mwan3 members are online, and the exact managed NAT6 rules are active.').format(activeWanCount)
			: (status.ok && status.ready && nat.profile === 'managed' && status.policy_ready === false
				? _('NAT6 is current for the ready subset, but one of its tracked mwan3 members is offline.')
				: _('NAT6 needs attention. Review the configuration, WAN safety checks, and the active rule profile before applying.')));
		var error = status.ok ? null : E('p', {}, [
			errorLabel(status.error),
			' ',
			E('a', { 'href': L.url('admin/network/mwan3-nat6/settings') }, _('Open WAN configuration'))
		]);

		return E('div', {}, [
			E('h2', {}, _('mwan3 N-WAN NAT6')),
			E('div', { 'class': healthy && !degraded ? 'alert-message success' : 'alert-message warning' }, [ summary, error ]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('WAN and traffic counters')),
				E('p', {}, _('Counters are cumulative. Record deltas around the same multi-connection workload when comparing policies.')),
				interfaceTable(status.interfaces)
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Installed NAT6 rules')),
				E('p', {}, [
					_('Table: '), E('strong', {}, nat.table || '-'), ' — ',
					_('Detected profile: '), E('strong', {}, profileLabel(nat.profile)), ' — ',
					_('%d of %d expected rules').format(
						Number(nat.rule_count || 0), Number(nat.expected_rule_count || 0))
				])
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Router-local device binding')),
				E('p', {}, localIcmp.enabled
					? _('Enabled: %d of %d exact ICMPv6 rules and %d of %d initial-route rules are active with bypass mark %s at RPDB priority %d; profile is %s.').format(
						Number(localIcmp.rule_count || 0), Number(localIcmp.expected_rule_count || 0),
						Number(localIcmp.routing_rule_count || 0), Number(localIcmp.expected_routing_rule_count || 0),
						localIcmp.mark || '-', Number(localIcmp.routing_priority || 0), localIcmp.profile || 'unknown')
					: _('Disabled. Router-local device-bound diagnostics remain subject to the existing mwan3/OpenClash policy.'))
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Renewal monitor')),
				E('p', {}, monitor.enabled
					? _('Enabled: every %d seconds, after %d stable samples; changed mwan3 tracker refresh is %s.').format(
						Number(monitor.interval || 0), Number(monitor.debounce || 0),
						monitor.refresh_mwan3 ? _('enabled') : _('disabled'))
					: _('Disabled. Live rules change only through manual Apply until monitoring is enabled in Settings.'))
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Aggregation model')),
				comparisonTable(activeWanCount, wanCount),
				E('p', {}, _('N ready WANs generate N² NAT rules. Prefix NAT does not combine one TCP or QUIC flow; mwan3 distributes separate connections, and this page never changes mwan3 weights.'))
			]),
			E('div', { 'class': 'cbi-page-actions' }, [
				E('a', { 'class': 'btn cbi-button-neutral', 'href': L.url('admin/network/mwan3-nat6/settings') }, _('Configure WANs')),
				' ',
				E('button', {
					'class': 'btn cbi-button-neutral',
					'click': function() { window.location.reload(); }
				}, _('Refresh')),
				' ',
				E('button', {
					'class': 'btn cbi-button-action important',
					'disabled': status.ready ? null : 'disabled',
					'title': status.ready ? '' : _('At least one configured WAN must be ready and every safety check must pass.'),
					'click': ui.createHandlerFn(this, 'handleApply')
				}, _('Apply N-WAN rules'))
			])
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
