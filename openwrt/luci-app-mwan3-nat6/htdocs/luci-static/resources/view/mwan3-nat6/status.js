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

function errorLabel(error) {
	var labels = {
		'required-command-missing': _('A required router command is missing.'),
		'no-wans': _('No WAN sections are configured.'),
		'too-few-wans': _('At least two WANs must be enabled.'),
		'too-many-wans': _('Too many WANs are enabled.'),
		'invalid-table': _('The nftables table name is invalid.'),
		'invalid-enabled': _('A WAN has an invalid enabled value.'),
		'invalid-interface': _('A WAN has an invalid logical interface.'),
		'invalid-device': _('A WAN has an invalid device.'),
		'invalid-label': _('A WAN has an invalid label.'),
		'duplicate-interface': _('A logical interface is configured more than once.'),
		'duplicate-device': _('A live device is used by more than one WAN.'),
		'invalid-index': _('An address or prefix index is outside 0-15.'),
		'invalid-expected-prefix-length': _('An expected prefix length is outside 1-64.'),
		'temporary-file-failed': _('The router could not create a temporary state file.')
	};

	return labels[error] || error || _('Unknown status error.');
}

function interfaceTable(interfaces) {
	var table = E('table', { 'class': 'table' }, [
		E('tr', { 'class': 'tr table-titles' }, [
			E('th', { 'class': 'th' }, _('WAN')),
			E('th', { 'class': 'th' }, _('State')),
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

function comparisonTable(wanCount) {
	var configured = Number(wanCount || 0);
	var configuredRules = configured * configured;

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
			E('td', { 'class': 'td' }, _('Current configuration')),
			E('td', { 'class': 'td' }, String(configured)),
			E('td', { 'class': 'td' }, String(configuredRules)),
			E('td', { 'class': 'td' }, _('Up to the configured links across independent connections'))
		])
	]);
}

return view.extend({
	load: function() {
		return L.resolveDefault(callStatus(), {
			ok: false,
			ready: false,
			error: 'status-failed',
			interfaces: [],
			nat: { present: false, wan_count: 0, rule_count: 0, expected_rule_count: 0, profile: 'unknown' }
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
		var wanCount = Number(nat.wan_count || 0);
		var healthy = status.ok && status.ready && nat.profile === 'managed';
		var summary = healthy
			? _('%d WANs are ready and the current managed NAT6 rules are active.').format(wanCount)
			: _('NAT6 needs attention. Review the configuration, every WAN, and the active rule profile before applying.');
		var error = status.ok ? null : E('p', {}, [
			errorLabel(status.error),
			' ',
			E('a', { 'href': L.url('admin/network/mwan3-nat6/settings') }, _('Open WAN configuration'))
		]);

		return E('div', {}, [
			E('h2', {}, _('mwan3 N-WAN NAT6')),
			E('div', { 'class': healthy ? 'alert-message success' : 'alert-message warning' }, [ summary, error ]),
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
				E('h3', {}, _('Aggregation model')),
				comparisonTable(wanCount),
				E('p', {}, _('N configured WANs generate N² NAT rules. Prefix NAT does not combine one TCP or QUIC flow; mwan3 distributes separate connections, and this page never changes mwan3 weights.'))
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
					'title': status.ready ? '' : _('At least two configured WANs must all be ready.'),
					'click': ui.createHandlerFn(this, 'handleApply')
				}, _('Apply N-WAN rules'))
			])
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
