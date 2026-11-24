// 主基地预览图：NODE_PATH=$(npm root -g) node tools/mock/fob_view.cjs <fob.json> <输出目录> [night]
//   先跑 python3 tools/mock/run.py tools/mock/fob_dump.lua out=<fob.json>；three.js 用 tools/trailer 的（cd tools/trailer && npm ci）
//   画几张：整个基地俯视、营区斜看、正门检查站、生活区、指挥中心和直升机坪、车场、机场
'use strict';
const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..', '..');
const [json, outDir, mode] = process.argv.slice(2);
if (!json || !outDir) { console.log('用法见文件开头'); process.exit(1); }
fs.mkdirSync(outDir, { recursive: true });
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json' };
const srv = http.createServer((q, r) => {
  const u = decodeURIComponent(q.url.split('?')[0]);
  let f;
  if (u.startsWith('/three/')) f = path.join(ROOT, 'tools/trailer/node_modules', u);
  else if (u === '/data.json') f = path.resolve(json);
  else f = path.join(__dirname, 'fob_view.html');
  fs.readFile(f, (e, b) => {
    if (e) { r.writeHead(404); r.end(); return; }
    r.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' });
    r.end(b);
  });
});
const SHOTS = [
  { name: '01_overview', pos: [-1500, 1500, -1900], look: [0, 0, 250], fov: 55, span: 2600 },
  { name: '02_camp', pos: [-760, 360, -820], look: [0, 0, 0], fov: 55, span: 1100 },
  { name: '03_gate', pos: [-120, 60, -720], look: [0, 6, -420], fov: 55, span: 500 },
  { name: '04_living', pos: [-600, 110, 40], look: [-330, 0, 230], fov: 55, span: 500 },
  { name: '05_command', pos: [330, 90, -330], look: [140, 0, -100], fov: 55, span: 500 },
  { name: '06_motorpool', pos: [-360, 70, -520], look: [-300, 0, -250], fov: 60, span: 500 },
  { name: '07_airfield', pos: [-1700, 180, 600], look: [-400, 0, 1050], fov: 55, span: 1600 },
  { name: '08_ground', pos: [30, 6, -330], look: [10, 8, -120], fov: 70, span: 400 },
];
if (process.env.SHOTS) SHOTS.splice(0, SHOTS.length, ...JSON.parse(process.env.SHOTS));   // 自定义镜头（区域预览）
srv.listen(0, async () => {
  const port = srv.address().port;
  const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'] });
  const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
  page.on('console', m => { if (m.type() === 'error') console.log('页面：', m.text()); });
  await page.goto(`http://localhost:${port}/?w=1600&h=900${mode === 'night' ? '&night=1' : ''}`);
  await page.waitForFunction(() => window.ready === true, null, { timeout: 180000 });
  for (const s of SHOTS) {
    await page.evaluate((o) => window.shot(o), s);
    const f = path.join(outDir, s.name + (mode === 'night' ? '_night' : '') + '.png');
    await page.screenshot({ path: f });
    console.log('写了', f);
  }
  await browser.close();
  srv.close();
});
