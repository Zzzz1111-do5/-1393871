// 载具内饰预览图：NODE_PATH=$(npm root -g) node tools/mock/interior_view.cjs <interior_xxx.json> <输出前缀> [models/veh/xxx.glb]
//   先跑 python3 tools/mock/run.py tools/mock/interior.lua dump=<目录> 写出 JSON；three.js 用 tools/trailer 的（cd tools/trailer && npm ci）
//   画：各乘员位的镜头（JSON 里的 cams）、剖开的侧视 / 俯视（可叠半透明的外模型看装不装得下）
'use strict';
const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..', '..');
const [json, outp, glb] = process.argv.slice(2);
if (!json || !outp) { console.log('用法见文件开头'); process.exit(1); }
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
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  p.on('pageerror', e => console.log('页面出错', e.message));
  let url = `http://127.0.0.1:${port}/interior_view.html?json=/data.json${process.env.DAY ? '&day=1' : ''}`;   // DAY=1：白天的光（看车外）
  if (glb) url += `&glb=/repo/${glb}&glbop=${process.env.GLBOP || 0.18}${process.env.CARVE ? '&carve=1' : ''}${process.env.GLBOFF ? '&glboff=' + process.env.GLBOFF : ''}`;   // GLBOP=1：原模型不透明（看车外加装的零件）；CARVE=1：挖了内腔的原车，坐在车里看到的样子
  await p.goto(url);
  await p.waitForFunction('window.ready === true', null, { timeout: 180000 });
  const D = await p.evaluate('window.D');
  const shots = [];
  for (const c of D.cams || []) shots.push({ name: c.name, c: c.c, fov: D.kind === 'air' ? 85 : 75, amb: process.env.AMB ? +process.env.AMB : undefined });   // AMB=0.9：镜头图亮一点（看清部件）
  if (D.kind === 'air') {   // 座舱：原点在飞行员眼位（格），座舱只有两三米大
    shots.push({ name: 'cut_side', pos: [9, -0.8, -0.6], look: [0, -1.2, -0.8], fov: 50, clip: [{ n: [-1, 0, 0], d: 0.25 }], amb: 0.9 });
    shots.push({ name: 'cut_top', pos: [0, 9, -0.8], look: [0, -1, -0.9], fov: 50, clip: [{ n: [0, -1, 0], d: 0.3 }], amb: 0.9 });
    shots.push({ name: 'cut_3q', pos: [3.2, 2.4, 2.6], look: [0, -1.0, -1.2], fov: 55, clip: [{ n: [0, -1, 0], d: 0.9 }], amb: 0.7 });
  } else {
    shots.push({ name: 'cut_side', pos: [26, 6, 0], look: [0, 4.5, -1], fov: 42, clip: [{ n: [-1, 0, 0], d: 0.02 }], amb: 0.9 });
    shots.push({ name: 'cut_left', pos: [-26, 6, 0], look: [0, 4.5, -1], fov: 42, clip: [{ n: [1, 0, 0], d: 0.02 }], amb: 0.9 });
    shots.push({ name: 'cut_top', pos: [0, 30, -1.2], look: [0, 0, -1.25], fov: 40, clip: [{ n: [0, -1, 0], d: 6.4 }], amb: 0.9 });
    shots.push({ name: 'cut_3q', pos: [10, 12, 8], look: [0, 4, -1], fov: 50, clip: [{ n: [0, -1, 0], d: 6.6 }], amb: 0.7 });
  }
  for (const s of shots) {
    await p.evaluate(o => window.shot(o), s);
    await p.screenshot({ path: `${outp}_${s.name}.png` });
  }
  console.log(`画了 ${shots.length} 张：${outp}_*.png`);
  await b.close(); srv.close();
});
