// 地图检查截图（找悬空、陷地、穿插、看加的细节）：照游戏里的真实坐标渲染导出的世界
//   先导出：lune run tools/trailer/export_world.luau <rbxlx> <数据目录> 8
//   再截图：NODE_PATH=$(npm root -g) node tools/map/inspect.mjs <three.js 包目录> <数据目录> <输出.png> <镜头 x,y,z> <看向 x,y,z> [地形半径] [视野角]
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const HERE = path.dirname(fileURLToPath(import.meta.url));
const [threeDir, dataDir, out, eye, at, r, fov] = process.argv.slice(2);
if (!threeDir || !dataDir || !out || !eye || !at) { console.error('用法见文件开头'); process.exit(1); }
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.bin': 'application/octet-stream' };
const server = http.createServer((req, res) => {
  const u = decodeURIComponent(req.url.split('?')[0]);
  let f = null;
  if (u === '/' || u === '/inspect.html') f = path.join(HERE, 'inspect.html');
  else if (u.startsWith('/three/')) f = path.join(threeDir, u.slice(7));
  else if (u.startsWith('/data/')) f = path.join(dataDir, path.basename(u));
  if (!f || !fs.existsSync(f)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' });
  fs.createReadStream(f).pipe(res);
});
await new Promise(r2 => server.listen(0, '127.0.0.1', r2));
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
page.on('pageerror', e => console.error('页面出错：', e.message));
await page.goto(`http://127.0.0.1:${server.address().port}/inspect.html?eye=${eye}&at=${at}&r=${r || 1400}&fov=${fov || 55}`);
await page.waitForFunction(() => window.ready === true, null, { timeout: 180000 });
const info = await page.evaluate(() => window.info);
await page.screenshot({ path: out });
console.log(`${out}：零件 ${info.shown}，地形 ${info.nx}×${info.nz}`);
await browser.close();
server.close();
