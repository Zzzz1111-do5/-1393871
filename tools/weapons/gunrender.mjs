// 改枪核对图：python3 tools/mock/run.py tools/mock/gunmount.lua out=<mount.json> 导出配件位置，再
//   NODE_PATH=$(npm root -g) node tools/weapons/gunrender.mjs <three.js 包目录> <mount.json> <输出目录>
//   每套配件拍 4 张：left（左侧，枪口朝右）、right（右侧，看得见战术件）、top（斜上方）、sight（开镜：眼睛在瞄具光轴上）
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const [threeDir, mountJson, outDir] = process.argv.slice(2);
if (!threeDir || !mountJson || !outDir) { console.error('用法：node tools/weapons/gunrender.mjs <three.js 包目录> <mount.json> <输出目录>'); process.exit(1); }
fs.mkdirSync(outDir, { recursive: true });
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.glb': 'model/gltf-binary' };
const server = http.createServer((req, res) => {
  const u = decodeURIComponent(req.url.split('?')[0]);
  let f = null;
  if (u === '/' || u === '/render.html') f = path.join(HERE, 'gunrender.html');
  else if (u === '/ads.html') f = path.join(HERE, 'adsrender.html');
  else if (u.startsWith('/three/')) f = path.join(threeDir, u.slice('/three/'.length));
  else if (u.startsWith('/models/')) f = path.join(ROOT, 'models', path.normalize(u.slice('/models/'.length)).replace(/^(\.\.[/\\])+/, ''));
  if (!f || !fs.existsSync(f)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' });
  fs.createReadStream(f).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage();
page.on('pageerror', e => console.error('页面出错：', e.message));
await page.goto(`http://127.0.0.1:${server.address().port}/render.html`);
await page.waitForFunction(() => window.ready === true, null, { timeout: 60000 });
const D = JSON.parse(fs.readFileSync(mountJson, 'utf8'));
// 开镜画面核对：ads=<JSON 选项>（每套配件拍一张：hideInner 藏镜筒里面的块、overlay 叠 2D 层、K 目镜占屏高、zoom 倍率）
const adsArg = process.argv.find(a => a.startsWith('ads='));
if (adsArg) {
  const opts = JSON.parse(adsArg.slice(4));
  await page.goto(`http://127.0.0.1:${server.address().port}/ads.html`);
  await page.waitForFunction(() => window.ready === true, null, { timeout: 60000 });
  for (let i = 0; i < D.builds.length; i++) {
    const png = await page.evaluate(([d, i, o]) => window.renderAds(d, i, o), [D, i, opts]);
    fs.writeFileSync(path.join(outDir, `${D.builds[i].name}_ads${opts.tag || ''}.png`), Buffer.from(png.split(',')[1], 'base64'));
    console.log(D.builds[i].name);
  }
  await browser.close();
  server.close();
  process.exit(0);
}
const camArg = process.argv.find(a => a.startsWith('cam='));
if (camArg) {   // 照改枪界面的镜头拍一张（透明底）：cam=<cam.json> [size=宽x高]
  const cam = JSON.parse(fs.readFileSync(camArg.slice(4), 'utf8'));
  const sz = (process.argv.find(a => a.startsWith('size=')) || 'size=1280x864').slice(5).split('x').map(Number);
  const png = await page.evaluate(([d, c, w, h]) => window.renderCam(d, c, w, h), [D, cam, sz[0], sz[1]]);
  fs.writeFileSync(path.join(outDir, 'cam.png'), Buffer.from(png.split(',')[1], 'base64'));
  console.log('cam.png');
  await browser.close();
  server.close();
  process.exit(0);
}
for (let i = 0; i < D.builds.length; i++) {
  for (const view of ['left', 'right', 'top', 'sight']) {
    const png = await page.evaluate(([d, i, v]) => window.renderBuild(d, i, v), [D, i, view]);
    const f = path.join(outDir, `${D.builds[i].name}_${view}.png`);
    fs.writeFileSync(f, Buffer.from(png.split(',')[1], 'base64'));
  }
  console.log(D.builds[i].name);
}
await browser.close();
server.close();
