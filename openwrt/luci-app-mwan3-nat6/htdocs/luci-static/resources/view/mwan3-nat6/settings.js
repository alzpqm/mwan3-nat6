'use strict';
'require form';
'require uci';
'require view';

function validateName(sectionId, value) {
	if (!value || !/^[A-Za-z0-9_.:@+-]+$/.test(value))
		return _('Use only letters, numbers, dot, underscore, colon, at, plus, and hyphen.');
	return true;
}

function validateOptionalName(sectionId, value) {
	return value ? validateName(sectionId, value) : true;
}

function validateLabel(sectionId, value) {
	if (value && !/^[A-Za-z0-9_.:@+ /-]+$/.test(value))
		return _('Use simple ASCII letters, numbers, spaces, dot, underscore, colon, at, plus, slash, and hyphen.');
	return true;
}

function validateTable(sectionId, value) {
	if (!value || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(value))
		return _('Start with a letter or underscore and use only letters, numbers, and underscores.');
	return true;
}

return view.extend({
	load: function() {
		return uci.load('mwan3-nat6');
	},

	render: function() {
		var map = new form.Map('mwan3-nat6', _('mwan3 N-WAN NAT6'),
			_('Configure two to thirty-two IPv6 WANs. Saving configuration does not change live nftables rules; review Status and apply manually after every enabled WAN is ready.'));
		var globals = map.section(form.NamedSection, 'globals', 'globals', _('Global settings'));
		var option = globals.option(form.Value, 'table', _('nftables table'));
		option.default = 'mwan3_nat6';
		option.rmempty = false;
		option.validate = validateTable;
		option.description = _('Use a dedicated table name. Existing installations may retain a previous validated table name for compatibility.');

		var wans = map.section(form.GridSection, 'wan', _('WANs'));
		wans.anonymous = true;
		wans.addremove = true;
		wans.sortable = true;
		wans.nodescriptions = true;
		wans.description = _('Every enabled entry must expose a global WAN IPv6 address and delegated prefix through ifstatus. Logical interfaces and live devices must be unique.');

		option = wans.option(form.Flag, 'enabled', _('Enabled'));
		option.default = option.enabled;
		option.rmempty = false;

		option = wans.option(form.Value, 'label', _('Label'));
		option.placeholder = _('WAN label');
		option.validate = validateLabel;
		option.description = _('Optional display label using simple ASCII characters.');

		option = wans.option(form.Value, 'interface', _('IPv6 logical interface'));
		option.rmempty = false;
		option.placeholder = 'wan1_6';
		option.validate = validateName;

		option = wans.option(form.Value, 'device', _('Expected egress device'));
		option.optional = true;
		option.placeholder = 'pppoe-provider-a';
		option.validate = validateOptionalName;
		option.description = _('Optional safety check. Leave empty to accept the current netifd l3_device.');

		option = wans.option(form.Value, 'expected_prefix_length', _('Expected PD length'));
		option.optional = true;
		option.datatype = 'range(1,64)';
		option.placeholder = '56';
		option.description = _('Optional safety check. Leave empty to accept the current delegated-prefix length.');

		option = wans.option(form.Value, 'address_index', _('WAN address index'));
		option.default = '0';
		option.datatype = 'range(0,15)';
		option.rmempty = false;

		option = wans.option(form.Value, 'prefix_index', _('Delegated-prefix index'));
		option.default = '0';
		option.datatype = 'range(0,15)';
		option.rmempty = false;

		return map.render();
	}
});
