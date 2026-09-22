'use strict';

// Local browser fixture, not a router or a full LuCI emulator. Serve only these
// explicit public assets, on loopback. Optional argument: a pre-fix status.js.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const before = process.argv[2] ? path.resolve(process.argv[2]) : null;
const port = Number(process.env.NAT6_PREVIEW_PORT || 18763);
const theme = 'https://raw.githubusercontent.com/openwrt/luci/openwrt-25.12/themes/luci-theme-bootstrap/htdocs/luci-static/bootstrap/cascade.css';
const routes = new Map([
	['/layout', [path.join(__dirname, 'luci-layout.html'), 'text/html']],
	['/status.js', [path.join(root, 'openwrt/luci-app-mwan3-nat6/htdocs/luci-static/resources/view/mwan3-nat6/status.js'), 'text/javascript']]
]);
if (before) routes.set('/before.js', [before, 'text/javascript']);
const frames = [1100, 360].flatMap(width => (before ? ['before', 'after'] : ['after']).map(source =>
	`<h2>${source} · ${width}px</h2><iframe title="${source} ${width}px" width="${width}" src="/layout?source=${source}"></iframe>`)).join('\n');
const index = `<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><title>NAT6 layout matrix</title>
<style>body{font:16px system-ui}iframe{height:470px;display:block;border:1px solid #999}pre{white-space:pre-wrap}</style>
<h1>LuCI Bootstrap 選單回歸測試</h1><p>真實狀態頁來源與官方主題 CSS；RPC 使用固定測試資料。</p><pre id="results">載入中…</pre>
<script>const results=[];onmessage=e=>{if(e.origin===location.origin&&e.data.nat6LayoutResult){results.push(e.data.nat6LayoutResult);document.getElementById('results').textContent=JSON.stringify(results,null,2);}};</script>
${frames}</html>`;

async function main() {
	for (const [file] of routes.values()) fs.accessSync(file, fs.constants.R_OK);
	const response = await fetch(theme);
	if (!response.ok) throw new Error('Could not load upstream theme: HTTP ' + response.status);
	const css = await response.text();
	http.createServer((req, res) => {
		const pathname = new URL(req.url, 'http://127.0.0.1').pathname;
		let type, body;
		if (pathname === '/') { type = 'text/html'; body = index; }
		else if (pathname === '/upstream/bootstrap.css') { type = 'text/css'; body = css; }
		else if (routes.has(pathname)) {
			const [file, mime] = routes.get(pathname);
			type = mime;
			body = fs.readFileSync(file);
		}
		else { res.writeHead(404); res.end(); return; }
		res.writeHead(200, { 'Content-Type': type + '; charset=utf-8', 'Cache-Control': 'no-store' });
		res.end(body);
	}).listen(port, '127.0.0.1', () => console.log(`Open http://127.0.0.1:${port}/ in a real browser; Ctrl-C stops the fixture.`));
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
