// 宣传片（微电影）驱动：本地起一个静态服务器，Playwright 打开 film/index.html 逐帧渲染、截图，配乐也在页面里离线合成，最后 ffmpeg 剪成片
// 用法（仓库根目录）：
//   NODE_PATH=$(npm root -g) node tools/trailer/render.cjs <数据目录> <输出目录> <步骤> [参数]
//   数据目录：export_world.luau、export_meta.luau 导出的 height.bin / mat.bin / world.json / meta.json，外加 assets/（特效贴图、海面法线、沙地贴图，见 film/README）
//   步骤：
//     still <镜头号> <秒> [文件名]      渲一张（调画面用）
//     bench <镜头号> [帧数]             量每帧多久
//     frames [镜头号,…]                 逐帧渲染（每个镜头一个目录，已有的帧跳过：中断了接着渲）；PART=i/n 只渲第 i 份（几个进程分头渲）
//     audio                             配乐、音效离线合成 → audio.wav
//     edit                              各镜头的帧 + 声音 → film.mp4
//   环境变量：W、H（画面大小，默认 1920 × 1080；宽银幕黑边在画面里）、SS（内部渲染倍率，默认 1）、FPS（默认 24）
'use strict';
const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path'), { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const [DATA, OUT, STEP, ...ARGS] = process.argv.slice(2);
if (!DATA || !OUT || !STEP) { console.log('用法见文件开头'); process.exit(1); }
const W = +(process.env.W || 1920), H = +(process.env.H || 1080), FPS = +(process.env.FPS || 24);
fs.mkdirSync(OUT, { recursive: true });

// 静态服务器：/repo/ → 仓库根目录，/data/ → 数据目录
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json', '.glb': 'model/gltf-binary', '.bin': 'application/octet-stream',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.webp': 'image/webp', '.css': 'text/css', '.woff2': 'font/woff2', '.woff': 'font/woff' };
function serve() {
  return new Promise(res => {
    const srv = http.createServer((q, r) => {
      const u = decodeURIComponent(q.url.split('?')[0]);
      let f = null;
      if (u.startsWith('/repo/')) f = path.join(ROOT, u.slice(6));
      else if (u.startsWith('/data/')) f = path.join(path.resolve(DATA), u.slice(6));
      if (!f || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { r.writeHead(404); r.end(); return; }
      r.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
      fs.createReadStream(f).pipe(r);
    });
    srv.listen(0, '127.0.0.1', () => res(srv));
  });
}

async function open(b, port) {
  const p = await b.newPage({ viewport: { width: W, height: H } });
  p.on('pageerror', e => console.log('页面出错：', e.message));
  p.on('console', m => { if (m.type() === 'error' || m.type() === 'warning' || /^\[film\]/.test(m.text())) console.log('[页面]', m.text()); });
  await p.goto(`http://127.0.0.1:${port}/repo/tools/trailer/film/index.html?w=${W}&h=${H}&fps=${FPS}&ss=${process.env.SS || 1}`);
  await p.waitForFunction(() => window.FILM && window.FILM.ready, null, { timeout: 600000 });
  return p;
}
async function grab(p, file) {   // 渲完一帧从画布取出来（JPEG 质量高、比 PNG 快得多）
  const url = await p.evaluate(() => window.FILM.canvas.toDataURL(window.FILM.jpg ? 'image/jpeg' : 'image/png', 0.95));
  fs.writeFileSync(file, Buffer.from(url.slice(url.indexOf(',') + 1), 'base64'));
}

(async () => {
  const srv = await serve();
  const port = srv.address().port;
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--disable-gpu-sandbox'] });
  try {
    if (STEP === 'still') {
      const p = await open(b, port);
      const [id, t, name] = ARGS;
      const ms = await p.evaluate(([id, t]) => window.FILM.renderAt(id, +t), [id, t]);
      await p.evaluate(() => { window.FILM.jpg = false; });
      const f = path.join(OUT, name || `${id}_${t}.png`);
      await grab(p, f);
      console.log(`${f}：${ms.toFixed(0)} 毫秒`);
    } else if (STEP === 'stills') {   // 每个镜头渲一张（看分镜）：stills S01:2.5,S02:3 …；不给就每个镜头取中间
      const p = await open(b, port);
      const list = await p.evaluate(() => window.FILM.shots.map(s => ({ id: s.id, dur: s.dur })));
      const want = ARGS[0] ? ARGS[0].split(',').map(a => a.split(':')) : list.map(s => [s.id, (s.dur / 2).toFixed(2)]);
      await p.evaluate(() => { window.FILM.jpg = true; });
      for (const [id, t] of want) {
        const t0 = Date.now();
        await p.evaluate(([id, t]) => window.FILM.renderAt(id, +t), [id, t]);
        const f = path.join(OUT, `still_${id}_${t}.jpg`);
        await grab(p, f);
        console.log(`${f}：${Date.now() - t0} 毫秒`);
      }
    } else if (STEP === 'bench') {
      const p = await open(b, port);
      const [id, n] = ARGS;
      const info = await p.evaluate(() => window.FILM.info());
      console.log(info);
      for (let i = 0; i < (+n || 6); i++) {
        const t0 = Date.now();
        const ms = await p.evaluate(([id, t]) => window.FILM.renderAt(id, t), [id, i / FPS]);
        await grab(p, path.join(OUT, `bench_${i}.jpg`));
        console.log(`第 ${i} 帧：提交 ${ms.toFixed(0)} 毫秒，连画完、取图 ${Date.now() - t0} 毫秒`);
      }
    } else if (STEP === 'frames') {
      const p = await open(b, port);
      const list = await p.evaluate(() => window.FILM.shots.map(s => ({ id: s.id, dur: s.dur })));
      const only = ARGS[0] ? ARGS[0].split(',') : null;
      const [pi, pn] = (process.env.PART || '0/1').split('/').map(Number);
      await p.evaluate(() => { window.FILM.jpg = true; });
      for (const s of list) {
        if (only && !only.includes(s.id)) continue;
        const dir = path.join(OUT, 'frames', s.id);
        fs.mkdirSync(dir, { recursive: true });
        const n = Math.round(s.dur * FPS);
        const t0 = Date.now();
        let done = 0;
        for (let i = 0; i < n; i++) {
          if (i % pn !== pi) continue;
          const f = path.join(dir, String(i).padStart(4, '0') + '.jpg');
          if (fs.existsSync(f)) continue;
          await p.evaluate(([id, t]) => window.FILM.renderAt(id, t), [s.id, (i + 0.5) / FPS]);
          await grab(p, f);
          done++;
          if (done % 24 === 0) console.log(`  ${s.id} ${i + 1}/${n}（每帧 ${((Date.now() - t0) / done / 1000).toFixed(2)} 秒）`);
        }
        console.log(`镜头 ${s.id}：${n} 帧，新渲 ${done} 帧，${((Date.now() - t0) / 1000).toFixed(0)} 秒`);
      }
    } else if (STEP === 'audio') {
      const p = await open(b, port);
      const b64 = await p.evaluate(() => window.FILM.renderAudio());
      fs.writeFileSync(path.join(OUT, 'audio.wav'), Buffer.from(b64, 'base64'));
      console.log('写好了 audio.wav');
    } else if (STEP === 'edit') {
      const p = await open(b, port);
      const list = await p.evaluate(() => window.FILM.shots.map(s => ({ id: s.id, dur: s.dur })));
      // 每个镜头的帧连起来（帧号连续），交给 ffmpeg
      const all = path.join(OUT, 'all');
      fs.rmSync(all, { recursive: true, force: true });
      fs.mkdirSync(all);
      let k = 0;
      for (const s of list) {
        const n = Math.round(s.dur * FPS);
        for (let i = 0; i < n; i++) {
          const src = path.join(OUT, 'frames', s.id, String(i).padStart(4, '0') + '.jpg');
          if (!fs.existsSync(src)) throw new Error('少一帧：' + src);
          fs.symlinkSync(src, path.join(all, String(k++).padStart(5, '0') + '.jpg'));
        }
      }
      const total = k / FPS;
      const audio = path.join(OUT, 'audio.wav');
      const args = ['-y', '-loglevel', 'error', '-framerate', String(FPS), '-i', path.join(all, '%05d.jpg')];
      if (fs.existsSync(audio)) args.push('-i', audio);
      args.push('-c:v', 'libx264', '-preset', 'slow', '-crf', '17', '-pix_fmt', 'yuv420p', '-movflags', '+faststart');
      if (fs.existsSync(audio)) args.push('-af', 'highpass=f=28,equalizer=f=70:t=q:w=1.2:g=-3,equalizer=f=2800:t=q:w=1:g=2,loudnorm=I=-15:TP=-1.5:LRA=12', '-c:a', 'aac', '-b:a', '256k', '-ar', '48000');
      args.push('-t', total.toFixed(3), path.join(OUT, 'film.mp4'));
      execFileSync('ffmpeg', args, { stdio: 'inherit' });
      console.log(`写好了 film.mp4（${total.toFixed(1)} 秒，${k} 帧）`);
    }
  } finally {
    await b.close();
    srv.close();
  }
})();
