// 载具侧面图标（用户 11-19：「给每个坦克侧面都截个图，做成全息颜色的 icon，下面显示血量，全息微微带着光晕」）
//   用 Playwright 打开 vehicons_render.html，逐个把原模型 GLB（models/veh）从右侧正对着拍成白色明暗图（透明背景），存 PNG；
//   没有原模型、零件拼的车：传一个 JSON（tools/mock/vehparts.lua 导出：{ 车型: { flip, parts: [...] } }）照零件画
//   再用 tools/models/hudicons.py 做成全息图标、压进 src/ReplicatedStorage/HudIcons.lua
//   用法：NODE_PATH=$(npm root -g) node tools/models/vehicons.mjs <three.js 包目录> <输出目录> [零件车.json]
//   SET=air：拍飞机、直升机（models/air，存成 air_<型号>.png；开飞机的界面右上角那张全息侧影，用户 11-19：飞机操作界面也照 MWT 改）
//   SET=ship：拍舰艇（models/ship，存成 ship_<型号>.png；用户 11-23：「召唤坦克和飞机、舰船的界面，选择的界面名字下面要带图标」——码位牌子上的侧影）
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const [threeDir, outDir, partsJson] = process.argv.slice(2);
if (!threeDir || !outDir) { console.error('用法：node tools/models/vehicons.mjs <three.js 包目录> <输出目录> [零件车.json]'); process.exit(1); }
fs.mkdirSync(outDir, { recursive: true });

// 车型（VehDefs 的 id）→ 原模型文件（ImportedMeta.alias 一样）；flip：模型车头朝 +Z 的（拍完炮口朝左的）反过来拍
const GLB = {
  ztz96: 'ztz96', ztz99a: 'ztz99a2', m1a1: 'm1a1', m1a2: 'm1a2dc', zbd05: 'zbd97', zsl92b: 'lav25', ptl02: 'ptl02', pgl625: 't625',
  plz07: 'pzh2000', m1117: 'matv', hmmwv: 'hmmwv', jltv: 'jltv', m2a3: 'm2a3', stryker: 'stryker', mshorad: 'stryker', m1150: 'm1150',
  m163: 'm163', cram: 'cram', patriot: 'patriot', m109a7: 'm109', m270: 'm270',
  t90m: 't90m', bmp3: 'bmp3', pantsir: 'pantsir',   // 俄系（用户 11-24）：blveh.py 转的原模型
};
// 飞机、直升机（AirDefs 的型号）→ models/air 的原模型（ImportedAir.alias 去掉版本后缀和 ~）；没有原模型的 gj11 是 X-47B 的模型、gj2 / z20 借 MQ-9 / UH-60
const AIR = {
  j20: 'j20', j35: 'j31', j15t: 'j15t', j16: 'j16', j50: 'j50', h6k: 'h6k', gj11: 'x47b', gj2: 'mq9', a10c: 'a10', f35: 'f35', f22: 'f22a',
  mq9: 'mq9', b2: 'b2', z10: 'z10w', ah64e: 'ah64', z20: 'uh60', uh60: 'uh60', ch47: 'ch47',
  j10: 'j10', j11: 'j11', j36: 'j36',   // 11-22 加的歼-10C、歼-11B、歼-36（sf_air.py 转的）
};
// 舰艇（ShipDefs 的型号）→ models/ship 的原模型（文件名同型号）
const SHIP = { t055: 't055', t054a: 't054a', t022: 't022', ddg125: 'ddg125', cg47: 'cg47', lcs2: 'lcs2', pbr: 'pbr' };
const SET = process.env.SET || 'veh';
const FLIP = new Set((process.env.FLIP || '').split(',').filter(Boolean));
const ONLY = new Set((process.env.ONLY || '').split(',').filter(Boolean));   // 只重拍这几辆（空 = 全部）
const want = id => ONLY.size === 0 || ONLY.has(id);

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.glb': 'model/gltf-binary', '.json': 'application/json' };
const server = http.createServer((req, res) => {
  const u = decodeURIComponent(req.url.split('?')[0]);
  let f = null;
  if (u === '/' || u === '/render.html') f = path.join(HERE, 'vehicons_render.html');
  else if (u.startsWith('/three/')) f = path.join(threeDir, u.slice('/three/'.length));
  else if (u.startsWith('/veh/')) f = path.join(ROOT, 'models', 'veh', path.basename(u));
  else if (u.startsWith('/air/')) f = path.join(ROOT, 'models', 'air', path.basename(u));
  else if (u.startsWith('/ship/')) f = path.join(ROOT, 'models', 'ship', path.basename(u));
  if (!f || !fs.existsSync(f)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' });
  fs.createReadStream(f).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const port = server.address().port;

const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage();
page.on('pageerror', e => console.error('页面出错：', e.message));
await page.goto(`http://127.0.0.1:${port}/render.html`);
await page.waitForFunction(() => window.ready === true, null, { timeout: 60000 });

const save = (id, r) => {
  fs.writeFileSync(path.join(outDir, id + '.png'), Buffer.from(r.png.split(',')[1], 'base64'));
  console.log(`${id}：模型 ${r.size.map(v => v.toFixed(1)).join(' × ')}`);
};
if (SET === 'air') {
  for (const [id, key] of Object.entries(AIR)) {
    if (!want(id)) continue;
    const hide = (id === 'z10') ? '__TRotor' : '';   // 起落架照拍（MWT 的侧影带着起落架）；直-10 的尾桨是一大块方片（转起来才像），不要
    const r = await page.evaluate(async ([u, fl, hd]) => window.renderGLB(u, fl, hd), [`/air/${key}.glb`, FLIP.has(id), hide]);
    save('air_' + id, r);
  }
}
if (SET === 'ship') {
  for (const [id, key] of Object.entries(SHIP)) {
    if (!want(id)) continue;
    const r = await page.evaluate(async ([u, fl]) => window.renderGLB(u, fl), [`/ship/${key}.glb`, FLIP.has(id)]);
    save('ship_' + id, r);
  }
}
for (const [id, key] of Object.entries((SET === 'air' || SET === 'ship') ? {} : GLB)) {
  if (!want(id)) continue;
  const r = await page.evaluate(async ([u, fl]) => window.renderGLB(u, fl), [`/veh/${key}.glb`, FLIP.has(id)]);
  save(id, r);
}
if (partsJson && SET !== 'air') {
  const all = JSON.parse(fs.readFileSync(partsJson, 'utf8'));
  for (const [id, v] of Object.entries(all)) {
    if (GLB[id] || !want(id)) continue;
    const r = await page.evaluate(([p, fl]) => window.renderParts(p, fl), [v.parts, FLIP.has(id) !== !!v.flip]);
    save(id, r);
  }
}
await browser.close();
server.close();
