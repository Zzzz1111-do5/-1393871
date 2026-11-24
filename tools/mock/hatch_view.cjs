// 舱盖预览图：NODE_PATH=$(npm root -g) node tools/mock/hatch_view.cjs <hatch.json> <输出目录> [键 ...]
//   先跑 lune run tools/mock/hatch_dump.luau <hatch.json>；three.js 用 tools/trailer 的（cd tools/trailer && npm ci）
//   每辆车两张：<键>.png（关着的位置 / 全开后上方 / 全开前上方 / 俯视）、<键>_mid.png（开到 1/4、1/2、3/4、艾布拉姆斯打开保护位）；
//   ZOOM=1 再给每块舱盖一张近看的 <键>_zoom<n>.png（关着 / 半开 / 全开 / 换个角度）
'use strict';
const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..', '..');
const [json, outd, ...keys0] = process.argv.slice(2);
if (!json || !outd) { console.log('用法见文件开头'); process.exit(1); }
const D = JSON.parse(fs.readFileSync(json, 'utf8'));
const keys = keys0.length ? keys0 : Object.keys(D);
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.glb': 'model/gltf-binary' };
const srv = http.createServer((q, r) => {
  const u = decodeURIComponent(q.url.split('?')[0]);
  let f;
  if (u.startsWith('/three/')) f = path.join(ROOT, 'tools/trailer/node_modules', u);
  else if (u === '/data.json') f = path.resolve(json);
  else if (u.startsWith('/repo/')) f = path.join(ROOT, u.slice(6));
  else f = path.join(__dirname, u);
  if (!fs.existsSync(f) || fs.statSync(f).isDirectory()) { r.writeHead(404); r.end(); return; }
  r.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' });
  fs.createReadStream(f).pipe(r);
});
srv.listen(0, '127.0.0.1', async () => {
  const port = srv.address().port;
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const p = await b.newPage({ viewport: { width: 1600, height: 1000 } });
  p.on('pageerror', e => console.log('页面出错', e.message));
  fs.mkdirSync(outd, { recursive: true });
  for (const k of keys) {
    const modes = ['main', 'mid'];
    if (process.env.ZOOM) for (let i = 0; i < D[k].hatches.length; i++) modes.push('zoom' + i);   // ZOOM=1：每块舱盖近看一张
    if (process.env.TOP) for (let i = 0; i < D[k].hatches.length; i++) modes.push('top' + i);     // TOP=1：每块舱盖正上方看一张（原模型 / 叠舱盖 / 全开 / 侧面）
    if (process.env.ONLY) modes.splice(0, modes.length, ...process.env.ONLY.split(','));
    for (const mode of modes) {
      await p.goto(`http://127.0.0.1:${port}/hatch_view.html?key=${k}&mode=${mode}${process.env.Q ? '&' + process.env.Q : ''}`);   // Q：额外参数（grid 的 cx、cz、d、gy、tur、lids）
      await p.waitForFunction('window.ready === true', null, { timeout: 120000 });
      const f = path.join(outd, k + (mode === 'main' ? '' : '_' + mode) + (process.env.TAG ? '_' + process.env.TAG : '') + '.png');
      await p.screenshot({ path: f });
      console.log('写好', f);
    }
  }
  await b.close();
  srv.close();
});
