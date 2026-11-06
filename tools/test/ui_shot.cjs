// 界面预览截图：用 ui_view.html 把 ui_export.luau 导出的场合一个个画出来、截图，并打印检查结果
// 用法：NODE_PATH=$(npm root -g) node ui_shot.cjs <数据目录（放 ui_pc.js / ui_phone.js）> <输出目录> [场合 ...] [--bg 基地背景图] [--bg2 战场背景图] [--dsf 2]
'use strict';
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const args = process.argv.slice(2);
const opt = {};
const pos = [];
for (let i = 0; i < args.length; i++) {
  if (args[i].startsWith('--')) { opt[args[i].slice(2)] = args[i + 1]; i++; } else pos.push(args[i]);
}
const [dataDir, outDir, ...names] = pos;
const ALL = ['join', 'base', 'missions', 'deploy', 'battle', 'drive', 'result'];
const list = names.length ? names : ['pc', 'phone'].flatMap(d => ALL.map(s => d + '_' + s));
const fileUrl = p => 'file://' + path.resolve(p);

(async () => {
  fs.mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ deviceScaleFactor: +(opt.dsf || 1) });
  const page = await ctx.newPage();
  page.on('pageerror', e => console.log('页面出错：', e.message));
  let bad = 0;
  for (const s of list) {
    const dev = s.split('_')[0];
    const scene = s.slice(dev.length + 1);
    const vw = dev === 'phone' ? 844 : 1280, vh = dev === 'phone' ? 390 : 720;
    await page.setViewportSize({ width: vw, height: vh });
    const bg = ['battle', 'drive', 'result'].includes(scene) ? opt.bg2 : opt.bg;
    const url = fileUrl(path.join(__dirname, 'ui_view.html')) + '?data=' + encodeURIComponent(fileUrl(path.join(dataDir, `ui_${dev}.js`))) +
      '&s=' + encodeURIComponent(s) + (bg ? '&bg=' + encodeURIComponent(fileUrl(bg)) : '') + (opt.core ? '&core=' + opt.core : '');
    await page.goto(url);
    await page.waitForFunction(() => document.title === 'ok', null, { timeout: 20000 });
    await page.screenshot({ path: path.join(outDir, s + '.png') });
    const rep = await page.evaluate(() => window.REPORT || []);
    console.log(`—— ${s}：${rep.length} 条`);
    for (const r of rep) console.log('   ', JSON.stringify(r));
    bad += rep.length;
  }
  await browser.close();
  console.log(`一共 ${bad} 条`);
})();
