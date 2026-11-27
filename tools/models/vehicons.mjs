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
  // 科技树暂用车换的真模型（用户 11-25）：同族的老 / 新型号拍同一个模型
  t80u: 't80u', t80b: 't80u', t80bvm: 't80u', bmp1: 'bmp1', leo2a6: 'leo2a6', leo2a4: 'leo2a6', leo1: 'leo1', leo1a5: 'leo1', m60a3: 'm60a3', m60a1: 'm60a3',
  t64a: 't64', t64b: 't64', type74: 'type74', type74g: 'type74', gepard1a1: 'gepard', gepard1a2: 'gepard', bmp2: 'bmp2', bmp2m: 'bmp2',   // 11-25 D 第二批
  m551: 'm551', leo2a7v: 'leo2a7v', type10: 'type10', leclerc: 'leclerc', t72b3: 't72b3', t72ural: 't72b3', t72a: 't72b3', t72b: 't72b3',   // E、C 的（11-24 / 11-25）
  type59: 'type59', type69: 'type59',   // 11-26 E：59 式（69-II 借它的模型）
  type87rcv: 'type87rcv', brdm2: 'brdm2', strela1: 'strela1',   // 11-27：87 式侦察警戒车、BRDM-2、箭-1
  // 11-27 拆开重叠的版本（同族的老 / 新型号拍同一个模型）：M1 一族
  m1: 'm1a1', m1ip: 'm1a1', m1a1hc: 'm1a1', m1a2base: 'm1a2dc', m1a2sep: 'm1a2dc', m1a2sep3: 'm1a2dc',
  m60: 'm60a3', m60a1rise: 'm60a3', leo1a1a1: 'leo1', leo2a0: 'leo2a6', leo2a5: 'leo2a6',   // M60、豹
};
// 飞机、直升机（AirDefs 的型号）→ models/air 的原模型（ImportedAir.alias 去掉版本后缀和 ~）；没有原模型的 gj11 是 X-47B 的模型、gj2 / z20 借 MQ-9 / UH-60
const AIR = {
  j20: 'j20', j35: 'j31', j15t: 'j15t', j16: 'j16', h6k: 'h6k', gj11: 'x47b', gj2: 'mq9', a10c: 'a10', f35: 'f35', f22: 'f22a',
  mq9: 'mq9', b2: 'b2', ah64e: 'ah64', z20: 'uh60', uh60: 'uh60', ch47: 'ch47',
  j10: 'j10', j11: 'j11', j36: 'j36',   // 11-22 加的歼-10C、歼-11B、歼-36（sf_air.py 转的）
  j8: 'j8', f16: 'f16', j6: 'j6',   // 11-23 的歼-8II、F-16C，11-25 的歼-6（科技树里原来借歼-8II 的模型）
  f15: 'f15', f14: 'f14',   // 11-25 的 F-15C、F-14A
  su57: 'su57', t50: 't50', mig29: 'mig29', su35: 'su35', su27: 'su35', su25: 'su25',   // 11-26 用户给的俄系（苏-27 借苏-35S 的模型）
  mi24: 'mi24', mi28: 'mi28', ka52: 'ka52', mi8: 'mi8', tiger: 'tiger', nh90: 'nh90', ah1w: 'ah1w', ah1s: 'ah1s', uh1n: 'uh1n', z8: 'z8',   // 11-25 各国直升机
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
    const hide = '';   // 起落架照拍（MWT 的侧影带着起落架）；原来直-10 的尾桨是一大块方片不拍（直-10 11-27 删了）
    const r = await page.evaluate(async ([u, fl, hd]) => window.renderGLB(u, fl, hd), [`/air/${key}.glb`, FLIP.has(id), hide]);
    save('air_' + id, r);
  }
}
// SET=photo：写实图（用户 11-25「主页和科技树的载具图用实拍图吧 然后角度要像战雷那样」）——地面车按 GLB、飞机按 AIR 各拍一张，
//   存成 pic_veh_<型号>.png / pic_air_<型号>.png（960 × 480，透明背景），tools/models/vehpics.py 缩小、压进 src/ReplicatedStorage/VehPics.lua
//   TINT=<json>：没贴图的模型按真车涂装上色 { 型号: "#rrggbb" }
if (SET === 'photo') {
  const TINT = process.env.TINT ? JSON.parse(fs.readFileSync(process.env.TINT, 'utf8')) : {};
  const done = new Set();
  for (const [id, key] of Object.entries(GLB)) {
    if (!want(id) || done.has('veh/' + key)) continue;
    done.add('veh/' + key);
    if (!fs.existsSync(path.join(ROOT, 'models', 'veh', key + '.glb'))) continue;   // 删掉的、没在仓库里的模型
    if (fs.existsSync(path.join(outDir, 'pic_veh_' + key + '.png')) && process.env.REDO !== '1') continue;
    const r = await page.evaluate(async ([u, o]) => window.renderPhoto(u, o), [`/veh/${key}.glb`, { flip: FLIP.has(id), tint: TINT[key] }]);
    save('pic_veh_' + key, r);
  }
  for (const [id, key] of Object.entries(AIR)) {
    if (!want(id) || done.has('air/' + key)) continue;
    done.add('air/' + key);
    if (!fs.existsSync(path.join(ROOT, 'models', 'air', key + '.glb'))) continue;
    if (fs.existsSync(path.join(outDir, 'pic_air_' + key + '.png')) && process.env.REDO !== '1') continue;
    // 两套起落架网格的（sf_gear.py：苏-57、苏-35、米格-29）：拍收起落架的样子——放下的腿、打开的舱门、舱里的东西不拍，关好的门板（GearUp）照拍
    const TWO = new Set(['su57', 't50', 'mig29', 'su35']);
    const hide = TWO.has(key) ? '__(Gear[NLRXB]|GDoor)' : '';
    const r = await page.evaluate(async ([u, o]) => window.renderPhoto(u, o), [`/air/${key}.glb`, { flip: FLIP.has(id), hide, pitch: 18, yaw: 38, tint: TINT[key] }]);
    save('pic_air_' + key, r);
  }
}
if (SET === 'ship') {
  for (const [id, key] of Object.entries(SHIP)) {
    if (!want(id)) continue;
    const r = await page.evaluate(async ([u, fl]) => window.renderGLB(u, fl), [`/ship/${key}.glb`, FLIP.has(id)]);
    save('ship_' + id, r);
  }
}
for (const [id, key] of Object.entries((SET === 'air' || SET === 'ship' || SET === 'photo') ? {} : GLB)) {
  if (!want(id)) continue;
  const r = await page.evaluate(async ([u, fl]) => window.renderGLB(u, fl), [`/veh/${key}.glb`, FLIP.has(id)]);
  save(id, r);
}
if (partsJson && SET !== 'air' && SET !== 'photo') {
  const all = JSON.parse(fs.readFileSync(partsJson, 'utf8'));
  for (const [id, v] of Object.entries(all)) {
    if (GLB[id] || !want(id)) continue;
    const r = await page.evaluate(([p, fl]) => window.renderParts(p, fl), [v.parts, FLIP.has(id) !== !!v.flip]);
    save(id, r);
  }
}
await browser.close();
server.close();
