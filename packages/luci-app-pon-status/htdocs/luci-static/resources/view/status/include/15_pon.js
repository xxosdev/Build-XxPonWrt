// SPDX-License-Identifier: Apache-2.0
//

'use strict';
'require baseclass';
'require fs';
'require rpc';
'require uci';


var prevNet = {};

var statsSource = null;

var CONNSTAT = '/usr/sbin/ponstat-conn';

var callDeviceStatus = rpc.declare({
	object: 'network.device',
	method: 'status'
});

function readFrontend(device) {
	var args = (device != null && device !== '')
		? [ '--device', device, 'status', '--json' ]
		: [ 'status', '--json' ];

	return L.resolveDefault(fs.exec_direct('/usr/sbin/ponctl', args), null).then(function(output) {
		if (!output)
			return { error: _('读取失败（设备不可用）') };

		try {
			var snapshot = JSON.parse(output);
			if (snapshot.schema_version !== 1)
				throw new Error('unsupported schema');
			return L.isObject(snapshot.frontend) ? snapshot.frontend : {};
		} catch (e) {
			return { error: _('解析失败') };
		}
	});
}

function sampleSysfs(device) {
	var base = '/sys/class/net/' + device + '/statistics';

	return Promise.all([
		L.resolveDefault(fs.trimmed(base + '/rx_bytes'), null),
		L.resolveDefault(fs.trimmed(base + '/tx_bytes'), null)
	]).then(function(v) {
		var rx = parseInt(v[0]), tx = parseInt(v[1]);

		if (isNaN(rx) || isNaN(tx))
			return null;

		return { rx: rx, tx: tx, t: Date.now() };
	});
}

function sampleUbus(device) {
	return L.resolveDefault(callDeviceStatus(), null).then(function(res) {
		var dev = (L.isObject(res) && L.isObject(res[device]))
			? res[device] : null;
		var st = (dev != null && L.isObject(dev.statistics))
			? dev.statistics : null;
		var rx = (st != null) ? parseInt(st.rx_bytes) : NaN;
		var tx = (st != null) ? parseInt(st.tx_bytes) : NaN;

		if (isNaN(rx) || isNaN(tx))
			return null;

		return { rx: rx, tx: tx, t: Date.now() };
	});
}

function sampleNet(device) {
	if (statsSource == 'sysfs')
		return sampleSysfs(device);

	return sampleUbus(device).then(function(cur) {
		if (cur != null) {
			statsSource = 'ubus';
			return cur;
		}

		return sampleSysfs(device).then(function(cur2) {
			if (cur2 != null)
				statsSource = 'sysfs';

			return cur2;
		});
	});
}

function netRate(from, to) {
	var dt = (to.t - from.t) / 1000.0;

	if (dt <= 0 || to.rx < from.rx || to.tx < from.tx)
		return null;

	return {
		rx: (to.rx - from.rx) * 8 / 1048576 / dt,
		tx: (to.tx - from.tx) * 8 / 1048576 / dt
	};
}

function readConns() {
	return L.resolveDefault(fs.exec('/bin/sh', [ CONNSTAT ]), null).then(function(res) {
		var vals = {},
		    lines = ((res && res.stdout) || '').split('\n'),
		    i, m;

		for (i = 0; i < lines.length; i++) {
			m = lines[i].match(/^([a-z0-9_]+)=(\d+)$/);

			if (m)
				vals[m[1]] = parseInt(m[2]);
		}

		if (typeof(vals.tcp_total) != 'number' &&
		    typeof(vals.udp_total) != 'number')
			return null;

		function pair(total, npu) {
			return (typeof(total) == 'number')
				? { total: total, npu: (typeof(npu) == 'number') ? npu : 0 }
				: null;
		}

		return { tcp: pair(vals.tcp_total, vals.tcp_npu),
		         udp: pair(vals.udp_total, vals.udp_npu) };
	});
}

function readRate(device) {
	return sampleNet(device).then(function(cur) {
		if (cur == null) {

			delete prevNet[device];
			return { error: true };
		}

		var prev = prevNet[device];

		prevNet[device] = cur;

		if (prev != null) {
			var r = netRate(prev, cur);

			if (r != null)
				return r;
		}

		return new Promise(function(resolve) {
			window.setTimeout(function() {
				sampleNet(device).then(function(cur2) {
					if (cur2 == null) {
						delete prevNet[device];
						resolve({ error: true });
						return;
					}

					prevNet[device] = cur2;
					resolve(netRate(cur, cur2));
				});
			}, 500);
		});
	});
}

function metric(frontend, field, unit, digits) {
	if (frontend.error)
		return frontend.error;
	if (!Object.prototype.hasOwnProperty.call(frontend, field))
		return _('不支持');
	return Number(frontend[field]).toFixed(digits) + ' ' + unit;
}

function css(name, fallback) {
	return 'var(--' + name + ', ' + fallback + ')';
}

var cBorder = css('border-color-low', '#eeeeee');
var cMuted  = css('text-color-medium', '#808080');
var cStrong = css('text-color-highest', '#000000');
var cCool   = css('success-color-high', 'rgb(0, 172, 89)');

var S_RATE_BLOCK = 'margin-top: 8px; padding-top: 8px; border-top: 1px solid ' + cBorder;
var S_TOP        = 'display: flex; align-items: center; justify-content: space-between; gap: 10px; min-width: 0';
var S_RATE_COL   = 'flex: 0 0 auto; display: flex; flex-direction: column; gap: 6px; align-items: flex-end';
var S_RATE_ROW   = 'display: flex; align-items: baseline; gap: 5px; white-space: nowrap';
var S_RATE_LABEL = 'font-size: 12px; color: ' + cMuted + '; white-space: nowrap';
var S_RATE_VALUE = 'font-size: 16px; font-weight: 600; font-variant-numeric: tabular-nums; color: ' + cStrong + '; white-space: nowrap';
var S_RATE_UNIT  = 'font-size: 10px; color: ' + cMuted + '; margin-left: 2px; white-space: nowrap';
var S_EMPTY      = 'font-size: 13px; color: ' + cMuted + '; white-space: nowrap';
var S_CONN_ROW   = 'display: flex; align-items: baseline; gap: 3px; white-space: nowrap';
var S_CONN_LABEL = 'font-size: 11px; font-weight: 600; color: ' + cMuted + '; white-space: nowrap';
var S_CONN_VALUE = 'font-size: 15px; font-weight: 600; font-variant-numeric: tabular-nums; color: ' + cStrong + '; white-space: nowrap';
var S_CONN_NPU   = 'font-size: 10px; color: ' + cMuted + '; white-space: nowrap';
var S_CONN_NPU_V = 'font-size: 12px; font-weight: 600; color: ' + cCool + '; white-space: nowrap';

function rateLine(label, value) {
	return E('div', { 'style': S_RATE_ROW }, [
		E('span', { 'style': S_RATE_LABEL }, [ label ]),
		E('span', { 'style': S_RATE_VALUE }, [ value.toFixed(2) ]),
		E('span', { 'style': S_RATE_UNIT }, [ 'Mibit/s' ])
	]);
}

function connCell(label, c) {
	return E('div', { 'style': S_CONN_ROW }, [
		E('span', { 'style': S_CONN_LABEL }, [ label ]),
		E('span', { 'style': S_CONN_VALUE }, [ String(c.total) ]),
		E('span', { 'style': S_CONN_NPU }, [ _('卸载') ]),
		E('span', { 'style': S_CONN_NPU_V }, [ String(c.npu) ])
	]);
}

function buildRateCol(rate) {
	if (rate && !rate.error)
		return E('div', { 'style': S_RATE_COL }, [
			rateLine(_('上行'), rate.tx),
			rateLine(_('下行'), rate.rx)
		]);

	return E('div', { 'style': S_EMPTY },
		[ rate ? _('读取失败') : _('不可用') ]);
}

function buildConnRow(conns) {
	var cells = [];

	if (conns && (conns.tcp || conns.udp)) {
		if (conns.tcp)
			cells.push(connCell('TCP', conns.tcp));

		if (conns.udp)
			cells.push(connCell('UDP', conns.udp));

		return E('div', {
			'style': 'display: flex; align-items: baseline; justify-content: space-between; gap: 12px; flex-wrap: wrap'
		}, cells);
	}

	return E('div', { 'style': S_EMPTY }, [ _('连接数不可用') ]);
}

function renderBox(item) {
	var frontend = item.frontend || {};

	return E('div', { 'class': 'ifacebox' }, [
		E('div', { 'class': 'ifacebox-head center active' },
			E('strong', item.device)),
		E('div', { 'class': 'ifacebox-body left' }, [
			E('div', { 'style': S_TOP }, [
				L.itemlist(E('span'), [
					_('收光功率'), metric(frontend, 'rx_power_dbm', 'dBm', 2),
					_('发光功率'), metric(frontend, 'tx_power_dbm', 'dBm', 2),
					_('光模块温度'), metric(frontend, 'temperature_celsius', '°C', 2),
					_('偏置电流'), metric(frontend, 'tx_bias_ma', 'mA', 2),
					_('供电电压'), metric(frontend, 'voltage_volts', 'V', 4)
				]),
				buildRateCol(item.rate)
			]),
			E('div', { 'style': S_RATE_BLOCK }, buildConnRow(item.conns))
		])
	]);
}

return baseclass.extend({
	title: _('PON 光模块'),

	load: function() {
		return uci.load('pon').then(function() {
			var sections = uci.sections('pon', 'xpon').filter(function(section) {
				return section.device;
			});

			if (!sections.length)
				return Promise.reject();

			return Promise.all([
				readConns(),
				Promise.all(sections.map(function(section) {
					return Promise.all([
						readFrontend(section.device),
						readRate(section.device)
					]).then(function(res) {
						return {
							device: section.device,
							frontend: res[0],
							rate: res[1]
						};
					});
				}))
			]).then(function(res) {
				var conns = res[0];

				res[1].forEach(function(item) {
					item.conns = conns;
				});

				return res[1];
			});
		});
	},

	render: function(data) {
		if (!data || !data.length)
			return null;

		return E('div', { 'id': 'pon_optics_table', 'class': 'network-status-table' },
			data.map(renderBox));
	}
});
