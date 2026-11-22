// 微电影主程序：载入数据、搭世界，按分镜（shots.js）把任意镜头的任意时刻渲出来；配乐（audio.js）也从这里离线合成
import * as THREE from 'three';
import { patchFog, makeSky, makeSea, terrainMaterial, makeParts, makeNoiseTex, makeGrimeTex } from './world.js';
import { BIG, bigConfig, initBigMap, heightAt, bigTerrainGeo, seaHeightTex, relocateParts } from './bigmap.js';
import { Post } from './post.js';
import { FX } from './fx.js';
import { setMeta, loadGLB } from './models.js';
import { SHOTS as FILM_SHOTS, setupShot } from './shots.js';
import { Titles } from './titles.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

const Q = new URLSearchParams(location.search);
const W = +(Q.get('w') || 1920), H = +(Q.get('h') || 1080), FPS = +(Q.get('fps') || 24), SS = +(Q.get('ss') || 1);
// 剪辑版本：film（微电影《黎明之前》，宽银幕）/ promo（时代广场宣传片：3 分钟、整幅 16:9、英文字幕，promo.js）/
//   v3（第三版微电影：游戏现在的地图和模型，v3/shots.js）
const CUT = Q.get('cut') || 'film', ASP = +(Q.get('asp') || 0);
const DATA = '/data', REPO = '/repo';
const log = (...a) => console.log('[film]', ...a);

async function bin(url, T) { return new T(await (await fetch(url)).arrayBuffer()); }
function tex(url, srgb = true) {
  return new Promise((res, rej) => new THREE.TextureLoader().load(url, t => { t.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace; res(t); }, undefined, rej));
}
// 可缺的旧贴图（网页版仓库的沙地、岩石、海面法线）：没有就给一张纯色的（沙漠版地表、天空都换成 Poly Haven 的了，海也不画）
function texOr(url, srgb, rgb) {
  return tex(url, srgb).catch(() => {
    console.log('[film] 没有', url, '，用纯色代替');
    const t = new THREE.DataTexture(new Uint8Array([rgb[0], rgb[1], rgb[2], 255]), 1, 1); t.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace; t.needsUpdate = true;
    return t;
  });
}

(async () => {
  try {
    patchFog(260);
    const renderer = new THREE.WebGLRenderer({ antialias: false, preserveDrawingBuffer: true, logarithmicDepthBuffer: true, powerPreference: 'high-performance' });
    renderer.setPixelRatio(1);
    renderer.setSize(W, H);
    renderer.autoClear = true;
    renderer.toneMapping = THREE.NoToneMapping;
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    renderer.shadowMap.autoUpdate = true;
    document.body.appendChild(renderer.domElement);

    // 数据
    const world = await (await fetch(`${DATA}/world.json`)).json();
    const meta = await (await fetch(`${DATA}/meta.json`)).json();
    setMeta(meta);
    // 第三版：地图按游戏原样（bigConfig），世界里的零件先过一遍（福建舰换成原模型，零件拼的那艘不要）
    //   gulf：海湾战争版（沙漠地图，gulf/shots.js）：没有海，高度两级网格
    const V3MOD = CUT === 'v3' ? await import('./v3/shots.js') : (CUT === 'gulf' ? await import('./gulf/shots.js') : null);
    const DESERT = CUT === 'gulf';
    if (V3MOD && V3MOD.BIGCFG) bigConfig(V3MOD.BIGCFG);
    if (V3MOD && V3MOD.prepWorld) V3MOD.prepWorld(world);
    const D = { ...world, world, height: await bin(`${DATA}/height.bin`, Float32Array), mat: await bin(`${DATA}/mat.bin`, Uint8Array) };
    if (world.coarse) { D.height2 = await bin(`${DATA}/height2.bin`, Float32Array); D.mat2 = await bin(`${DATA}/mat2.bin`, Uint8Array); }
    // 片子里放大的地图（bigmap.js）：游戏的高度、材质按离抢滩点的远近放大；地图零件挪到放大后的位置
    initBigMap(D);
    world.parts = relocateParts(world.parts);
    const T = {
      noise: makeNoiseTex(256, 3), sand: await texOr(`${DATA}/assets/terrain/sand.jpg`, true, [158, 140, 110]), water: await texOr(`${DATA}/assets/water/normals.jpg`, false, [128, 128, 255]),
      rock: await texOr(`${DATA}/assets/terrain/rock.jpg`, true, [95, 90, 86]),
      expl: await tex(`${DATA}/assets/vfx/expl.webp`, false), fire: await tex(`${DATA}/assets/vfx/fire.webp`, false), mzl: await tex(`${DATA}/assets/vfx/mzl.webp`, false),
      mzla: await tex(`${DATA}/assets/vfx/mzla.webp`, false), puff: await tex(`${DATA}/assets/vfx/puff.webp`),
    };
    T.sand.wrapS = T.sand.wrapT = THREE.RepeatWrapping; T.sand.anisotropy = 8;
    T.rock.wrapS = T.rock.wrapT = THREE.RepeatWrapping; T.rock.anisotropy = 8;
    T.desert = DESERT;
    // 写实化（gulf/real.js）：沙漠版用真实天空 HDRI（天穹 + 环境光照）、扫描的地表贴图；素材没下载（fetch_cc0.sh）就照旧
    let REAL = null;
    if (DESERT) {
      const R = await import('./gulf/real.js');
      T.pbr = await R.loadGround(DATA, tex);
      REAL = await R.loadSkies(renderer, DATA);
      log('写实素材', T.pbr ? '地表好' : '地表缺', Object.keys(R.SKY_FILES).map(k => REAL.has(k) ? k : '缺' + k).join(' '));
    }
    T.grime = makeGrimeTex(T.noise);
    for (const k of ['expl', 'fire', 'mzl', 'mzla', 'puff']) { T[k].generateMipmaps = true; T[k].minFilter = THREE.LinearMipmapLinearFilter; }
    // 彩色烟团（sRGB 带透明）不用 mipmap：新版 SwiftShader 对这种贴图按 mipmap 采样会坏（烟团一大就一片片黑条），只采原图
    T.puff.generateMipmaps = false; T.puff.minFilter = THREE.LinearFilter;

    const SHOTS = CUT === 'promo' ? (await import('./promo.js')).PROMO : (V3MOD ? V3MOD.SHOTS : FILM_SHOTS);
    const post = new Post(renderer, W, H, { ss: SS, msaa: 4, aspect: ASP || (CUT === 'promo' ? W / H : 2.39) });
    const scene = new THREE.Scene();
    scene.fog = new THREE.FogExp2(0x1d2738, 0.00042);
    const camera = new THREE.PerspectiveCamera(35, post.rw / post.rh, 0.5, 320000);   // 高空镜头看得到很远（地面在 7 万～30 万格之间融进雾里）
    const sky = makeSky();
    scene.add(sky);
    scene.userData.sky = sky;
    // 环境光照：拿夜空烘一张环境贴图（车身的反光）
    {
      // 夜里的天太暗，金属、油漆反不出形状：用一个暗的室内环境当反光（各材质的 envMapIntensity 压得很低）
      const pm = new THREE.PMREMGenerator(renderer);
      scene.environment = pm.fromScene(new RoomEnvironment(renderer), 0.04).texture;
      pm.dispose();
    }
    const roomEnv = scene.environment;
    const terrain = new THREE.Mesh(new THREE.BufferGeometry(), terrainMaterial(T));
    terrain.receiveShadow = true; terrain.castShadow = !DESERT; terrain.frustumCulled = false;   // 沙漠：地形不给自己投影（崖的影子小，阴影相机只罩镜头附近一小块）
    terrain.material.envMapIntensity = 0.04;
    scene.add(terrain);
    const parts = makeParts(D, T);
    scene.add(parts.group);
    const sea = makeSea(renderer, D, T.water, Math.round(post.rw / 2), Math.round(post.rh / 2));
    scene.add(sea);
    // 月光（带阴影）、天光
    const moon = new THREE.DirectionalLight(0xa6badf, 3.0);
    moon.castShadow = true;
    moon.shadow.mapSize.set(2048, 2048);
    moon.shadow.bias = -0.0004; moon.shadow.normalBias = 0.6;
    scene.add(moon, moon.target);
    const hemi = new THREE.HemisphereLight(0x3c5078, 0x16120e, 1.15);
    scene.add(hemi);
    const fx = new FX(scene, T);
    const titles = new Titles(W, H, post.ah);
    const canvas = document.createElement('canvas'); canvas.width = W; canvas.height = H;
    const ctx = canvas.getContext('2d');

    if (DESERT) sea.visible = false;
    // 沙漠：地形网格只铺到镜头中心外 4.2 万格；高空镜头往远看会看到地面的边——外面再铺一圈平的沙地（比最低的地形还低，地形网格里低洼的地方不会被盖住：内圈 4 万格）
    let farGround = null;
    if (DESERT) {
      const g = new THREE.RingGeometry(40000, 420000, 96, 4);
      g.rotateX(-Math.PI / 2);
      const nv = g.attributes.position.count, col = new Float32Array(nv * 3), w = new Float32Array(nv * 4);
      for (let i = 0; i < nv; i++) { col.set([0.62, 0.47, 0.29], i * 3); w[i * 4] = 1; }   // 平原的沙（同 bigmap MATD.Sand）
      g.setAttribute('color', new THREE.BufferAttribute(col, 3));
      g.setAttribute('aW', new THREE.BufferAttribute(w, 4));
      farGround = new THREE.Mesh(g, terrain.material);
      farGround.receiveShadow = false; farGround.frustumCulled = false;
      scene.add(farGround);
    }
    const env = { THREE, renderer, scene, camera, sky, sea, terrain, parts, moon, hemi, fx, D, T, post, titles, REPO, groundY: heightAt, FPS, W, H, log, DESERT };
    // 地形网格、水深贴图按镜头搭（离镜头近的地方密）：terrainAt(中心 x, z, 网格参数)，同一个中心不重搭
    let tKey = null;
    env.terrainAt = (x, z, o = {}) => {
      const key = [Math.round(x), Math.round(z), o.sp, o.a, o.cap].join(',');
      if (key === tKey) return;
      tKey = key;
      const t0 = performance.now();
      terrain.geometry.dispose();
      terrain.geometry = bigTerrainGeo(x, z, o);
      if (farGround) farGround.position.set(x, -60, z);   // 压在所有地形底下（原来 11 格，盐碱滩底 8 格，4 万格外整块被它盖住、只剩一圈白边）
      if (!DESERT) {   // 沙漠没有海
        const nr = o.seaR ?? 2048;
        const old = sea.userData.depthTex;
        if (old) old.forEach(t => t.dispose());
        const near = seaHeightTex(x, z, nr, 1024), far = seaHeightTex(x, z, 40000, 512);
        sea.userData.depthTex = [near, far];
        sea.userData.setDepth([near, x, z, nr], [far, x, z, 40000]);
      }
      log('地形', key, (performance.now() - t0).toFixed(0) + ' 毫秒', terrain.geometry.index.count / 3 + ' 个三角形');
    };
    env.terrainAt(BIG.fx, BIG.fz);
    // 片名、片尾那几个镜头不要地形、海、天
    env.worldVisible = on => { for (const o of [sky, sea, terrain, parts.group]) o.visible = on; moon.visible = on; hemi.visible = on; if (DESERT) sea.visible = false; if (farGround) farGround.visible = on; };
    let cur = null;   // 当前搭好的镜头
    async function enter(id) {
      if (cur && cur.id === id) return cur;
      if (cur && cur.dispose) cur.dispose();
      fx.clear();
      const S = SHOTS.find(s => s.id === id);
      cur = await setupShot(S, env);
      cur.id = id;
      return cur;
    }
    function frame(sh, t) {
      const P = sh.update(t) || {};
      const tt = sh.tmap ? sh.tmap(t) : t;   // 宣传片的慢镜头 / 截一段：特效、海浪、天空按原镜头的时间走
      scene.updateMatrixWorld(true);
      // 天空、雾、月亮跟着镜头参数走
      sky.position.copy(camera.position);
      const su = sky.material.uniforms;
      su.uTime.value = tt + (sh.t0 || 0);
      const fogC = P.fogColor || new THREE.Color(0x1d2738);
      scene.fog.color.copy(fogC); scene.fog.density = P.fogDensity ?? 0.00042;
      su.uFog.value.copy(fogC); su.uDawn.value = P.dawn || 0;
      if (P.moonDir) su.uMoon.value.copy(P.moonDir); else su.uMoon.value.set(0.3, 0.28, -0.91).normalize();
      su.uSun.value.copy(P.sunDir || new THREE.Vector3(0.6, 0.02, -0.8).normalize());
      su.uMoonI.value = P.moonVis ?? 1;
      su.uDay.value = P.day || 0; su.uHaze.value.copy(P.haze || fogC); su.uCloud.value = P.cloud ?? 0.55; su.uStars.value = P.stars ?? 1;
      moon.intensity = P.moonI ?? 3.0; hemi.intensity = P.hemiI ?? 1.15;
      moon.color.set(P.moonC ?? 0xa6badf);
      hemi.color.set(P.hemiSky ?? 0x3c5078); hemi.groundColor.set(P.hemiGround ?? 0x16120e);
      // 真实天空：天穹贴 HDRI（按太阳方位转），环境光照用同一张（去掉太阳、下半球是沙地），亮度对上原来的半球光，半球光减半（另一半由环境光给）
      if (REAL && P.sky && REAL.has(P.sky) && sky.visible) {
        const S = REAL.sky(P.sky), lum = (r, g, b) => r * 0.2126 + g * 0.7152 + b * 0.0722;
        const sd = P.sky === 'night' ? null : (P.sunDir || P.moonDir);
        const rot = P.skyRot ?? (sd ? REAL.rotFor(P.sky, sd) : 0);
        su.tHdr.value = S.tex; su.uHdrOn.value = 1; su.uHdrRot.value = rot;
        su.uHdrK.value = (P.skyLum ?? 0.4) / Math.max(lum(...S.avg), 1e-6);
        su.uHdrHaze.value = P.skyHaze ?? 0.6;
        scene.environment = REAL.env(P.sky, rot, lum(hemi.color.r, hemi.color.g, hemi.color.b) * hemi.intensity / Math.PI);
        hemi.intensity *= P.hemiKeep ?? 0.5;
        terrain.material.envMapIntensity = P.terrainEnv ?? 0.5;
      } else {
        su.uHdrOn.value = 0; scene.environment = roomEnv; terrain.material.envMapIntensity = 0.04;
      }
      terrain.material.userData.wet = DESERT ? 0 : 1;
      sea.userData.mat.uniforms.uMoon.value.copy(su.uMoon.value);
      moon.position.copy(su.uMoon.value).multiplyScalar(3000).add(P.shadowAt || camera.position);
      moon.target.position.copy(P.shadowAt || camera.position);
      const sr = P.shadowR || 300;
      Object.assign(moon.shadow.camera, { left: -sr, right: sr, top: sr, bottom: -sr, near: 100, far: 7000 });
      moon.shadow.camera.updateProjectionMatrix();
      if (P.fxAmb) fx.amb.copy(P.fxAmb); else fx.amb.setRGB(0.05, 0.06, 0.085);   // 烟的底光：白天被太阳照亮（原来按夜里，白天的烟一团团发黑）
      fx.setFog(scene.fog);
      fx.update(tt, camera);
      if (sea.visible) sea.userData.prepare(renderer, scene, camera, tt + (sh.t0 || 0));
      post.render(scene, camera, { ...P, time: tt + (sh.t0 || 0) });
      // 画面拷到输出画布、叠字幕
      ctx.drawImage(renderer.domElement, 0, 0);
      if (sh.overlay) sh.overlay(ctx, t, W, H, post.ah, P);   // 第三版：平显、瞄准镜、游戏界面画在字幕下面
      titles.draw(ctx, sh.titles ? sh.titles(t) : null, t);
    }
    window.FILM = {
      ready: true, canvas, jpg: true, shots: SHOTS.map(s => ({ id: s.id, dur: s.dur })),
      async renderAt(id, t) { const t0 = performance.now(); const sh = await enter(id); frame(sh, t); return performance.now() - t0; },
      info() { return { W, H, rw: post.rw, rh: post.rh, gl: renderer.getContext().getParameter(renderer.getContext().VERSION), tris: renderer.info.render.triangles, calls: renderer.info.render.calls }; },
      async renderAudio() {
        if (CUT === 'promo') { const { renderPromoScore } = await import('./audio_promo.js'); return renderPromoScore(SHOTS); }
        if (CUT === 'v3') { const { renderV3Score } = await import('./v3/audio.js'); return renderV3Score(SHOTS); }
        if (CUT === 'gulf') { const { renderGulfScore } = await import('./gulf/audio.js'); return renderGulfScore(SHOTS); }
        const { renderScore } = await import('./audio.js'); return renderScore(SHOTS);
      },
    };
    // 网页字体：画布写字不等字体加载（第一次用到某个字重、某段字符时先用替代字体画，同一句字幕前后帧字体不一样）。
    //   开渲之前把字幕可能用到的字都加载好：英文、标点，加上分镜源码里出现的所有中文字
    {
      const src = (await Promise.all(['shots.js', 'promo.js', 'promo_shots.js', 'v3/shots.js', 'gulf/shots.js', 'gulf/kit.js'].map(f => fetch(f).then(r => r.ok ? r.text() : '')))).join('');
      const cjk = [...new Set(src)].filter(c => c.charCodeAt(0) > 0x2000).join('');
      const latin = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .,:;!?-—–·“”"\'()&+/%';
      const faces = ['"Noto Sans SC"', '"Noto Serif SC"'].flatMap(f => [400, 700].map(w => `${w} 32px ${f}`));
      await Promise.all(faces.map(f => document.fonts.load(f, latin + cjk)));
      await document.fonts.ready;
      log('字体', faces.map(f => document.fonts.check(f, 'ISLAND 全面大战场') ? '好' : '缺').join(' '));
    }
    log('准备好了', W, H);
  } catch (e) {
    console.error('[film] 出错', e && e.stack || e);
    window.FILM = { ready: true, error: String(e) };
  }
})();
