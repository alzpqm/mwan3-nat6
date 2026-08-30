'use strict';
'require form';
'require uci';
'require view';

function validateName(sectionId, value) {
	if (!value || !/^[A-Za-z0-9_.:@+-]+$/.test(value))
		return _('只能使用英文字母、數字及 . _ : @ + -。');
	return true;
}

function validateOptionalName(sectionId, value) {
	return value ? validateName(sectionId, value) : true;
}

function validateOptionalDevice(sectionId, value) {
	if (!value)
		return true;
	if (value.length > 15)
		return _('Linux 網路裝置名稱不得超過 15 個字元。');
	return validateName(sectionId, value);
}

function validateLabel(sectionId, value) {
	if (value && !/^[A-Za-z0-9_.:@+ /-]+$/.test(value))
		return _('只能使用英文字母、數字、空格及 . _ : @ + / -。');
	return true;
}

function validateTable(sectionId, value) {
	if (!value || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(value))
		return _('名稱須以英文字母或底線開頭，且只能包含英文字母、數字與底線。');
	return true;
}

return view.extend({
	load: function() {
		return uci.load('mwan3-nat6');
	},

	render: function() {
		var map = new form.Map('mwan3-nat6', _('mwan3 多 WAN NAT6'),
			_('可設定 2 至 32 條 IPv6 WAN。自動更新監看程式獨立於 fw4 運作，必須由您手動啟用。'));
		var globals = map.section(form.NamedSection, 'globals', 'globals', _('全域設定'));
		var option = globals.option(form.Value, 'table', _('nftables 資料表'));
		option.default = 'mwan3_nat6';
		option.rmempty = false;
		option.validate = validateTable;
		option.description = _('請使用專屬的資料表名稱。既有安裝可保留先前通過驗證的名稱，以維持相容性。');

		option = globals.option(form.Flag, 'pin_local_icmp', _('支援路由器本機的指定 WAN 診斷'));
		option.default = '0';
		option.rmempty = false;
		option.description = _('供 NextTrace 等工具使用的選用相容功能。當程式明確綁定至已就緒的 PPP 裝置時，會先查詢該裝置通過驗證的 mwan3 路由表；使用精確來源位址的 ICMPv6 Echo Request 也會套用略過標記。轉送的 LAN 流量、未綁定裝置的連線及 mwan3 權重都不受影響。');

		option = globals.option(form.Flag, 'monitor', _('自動更新監看'));
		option.default = '0';
		option.rmempty = false;
		option.description = _('啟用後，獨立的 procd 服務會等待 WAN 資料穩定，再修復未啟用、已過期或已知不安全的 NAT6 規則；絕不重新載入 fw4。');

		option = globals.option(form.Value, 'interval', _('檢查間隔'));
		option.default = '15';
		option.datatype = 'range(5,3600)';
		option.rmempty = false;
		option.depends('monitor', '1');
		option.description = _('每次唯讀檢查 netifd 與 nftables 之間的間隔秒數。');

		option = globals.option(form.Value, 'debounce', _('穩定樣本數'));
		option.default = '2';
		option.datatype = 'range(1,10)';
		option.rmempty = false;
		option.depends('monitor', '1');
		option.description = _('連續取得指定數量且內容相同的就緒狀態後，才會更新規則。');

		option = globals.option(form.Flag, 'refresh_mwan3_after_nat', _('更新已變更的 mwan3 追蹤器'));
		option.default = '0';
		option.rmempty = false;
		option.depends('monitor', '1');
		option.description = _('進階相容選項，預設停用。NAT 規則成功更新後，只對位址或前綴有變動的 IPv6 介面執行 mwan3 ifup。除非已確認必須更新追蹤器，否則請維持停用。');

		var wans = map.section(form.GridSection, 'wan', _('WAN 連線'));
		wans.anonymous = true;
		wans.addremove = true;
		wans.sortable = true;
		wans.nodescriptions = true;
		wans.description = _('每個已啟用項目都必須能由 ifstatus 取得 WAN 的全域 IPv6 位址與委派前綴。邏輯介面及目前使用的裝置不得重複。');

		option = wans.option(form.Flag, 'enabled', _('啟用'));
		option.default = option.enabled;
		option.rmempty = false;

		option = wans.option(form.Value, 'label', _('顯示名稱'));
		option.placeholder = _('WAN 顯示名稱');
		option.validate = validateLabel;
		option.description = _('選用的顯示名稱，請使用簡單的 ASCII 字元。');

		option = wans.option(form.Value, 'interface', _('IPv6 邏輯介面'));
		option.rmempty = false;
		option.placeholder = 'wan1_6';
		option.validate = validateName;

		option = wans.option(form.Value, 'device', _('預期送出裝置'));
		option.optional = true;
		option.placeholder = 'pppoe-wan1';
		option.validate = validateOptionalDevice;
		option.description = _('選用的安全檢查；留空時接受 netifd 目前回報的 l3_device。');

		option = wans.option(form.Value, 'expected_prefix_length', _('預期的 PD 長度'));
		option.optional = true;
		option.datatype = 'range(3,64)';
		option.placeholder = '56';
		option.description = _('選用的安全檢查；留空時接受目前委派前綴的長度。');

		option = wans.option(form.Value, 'address_index', _('WAN 位址索引'));
		option.default = '0';
		option.datatype = 'range(0,15)';
		option.rmempty = false;

		option = wans.option(form.Value, 'prefix_index', _('委派前綴索引'));
		option.default = '0';
		option.datatype = 'range(0,15)';
		option.rmempty = false;

		return map.render();
	}
});
