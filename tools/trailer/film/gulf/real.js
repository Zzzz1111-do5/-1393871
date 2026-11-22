// 写实化（用户 11-22：太假了这个视频）：真实的天空、环境光、地表贴图（Poly Haven 的 CC0 素材，tools/trailer/fetch_cc0.sh 下载到数据目录 assets/ph/）
//   天空：qwantani 一组纯天空 HDRI（同一个地方不同时刻）——天穹直接贴它（按镜头的太阳方位转），
//   环境光照：同一张 HDRI 去掉太阳（直射光由平行光给）、下半球填成被太阳照亮的沙地的亮度，烘成 PMREM——车身反射真的天、底盘照到地面的暖光；
//   按天光的平均亮度缩放到和原来的半球光一样亮，原来调好的曝光不用重调
import * as THREE from 'three';
import { RGBELoader } from 'three/addons/loaders/RGBELoader.js';

export const SKY_FILES = {
  dawn: 'qwantani_sunrise_puresky', morning: 'qwantani_mid_morning_puresky', day: 'qwantani_afternoon_puresky',
  dusk: 'qwantani_dusk_1_puresky', night: 'qwantani_night_puresky',
};
const half = THREE.DataUtils.fromHalfFloat, toHalf = THREE.DataUtils.toHalfFloat;
const SAND = [0.46, 0.37, 0.26];   // 沙地反照率（线性）

// 一张 HDRI：读进来，找太阳，算天光（不含太阳）的平均亮度和水平面照度
async function loadOne(url) {
  const t = await new Promise((res, rej) => new RGBELoader().setDataType(THREE.HalfFloatType).load(url, res, undefined, rej));
  const { width: w, height: h, data } = t.image;   // RGBA 半精度，第 0 行是天顶
  // 太阳、远处灯光的像素超过半精度上限（65504）就成了无穷大：烟、云叠在上面混出 NaN（一块块黑条），泛光、环境光也跟着坏——钳到 3 万以内
  const CAP = toHalf(30000);
  for (let i = 0; i < data.length; i++) if ((data[i] & 0x7c00) === 0x7c00 || (data[i] & 0x7fff) > CAP) data[i] = (data[i] & 0x8000) ? 0 : CAP;
  let best = -1, bi = 0, bj = 0;
  for (let j = 0; j < h / 2; j++) for (let i = 0; i < w; i += 2) {
    const o = (j * w + i) * 4;
    const l = half(data[o]) * 0.2126 + half(data[o + 1]) * 0.7152 + half(data[o + 2]) * 0.0722;
    if (l > best) { best = l; bi = i; bj = j; }
  }
  const el = (0.5 - (bj + 0.5) / h) * Math.PI, phi = ((bi + 0.5) / w - 0.5) * 2 * Math.PI;   // three 的等距柱状：u = atan(z, x) / 2π + 0.5
  const sun = new THREE.Vector3(Math.cos(phi) * Math.cos(el), Math.sin(el), Math.sin(phi) * Math.cos(el));
  // 天光（太阳周围 3 度不算）：平均亮度（按立体角）、水平面照度
  const cosSun = Math.cos(3 * Math.PI / 180);
  const avg = [0, 0, 0], Eh = [0, 0, 0], Es = [0, 0, 0];
  let sw = 0;
  for (let j = 0; j < h / 2; j++) {
    const e = (0.5 - (j + 0.5) / h) * Math.PI, ce = Math.cos(e), se = Math.sin(e), dOm = ce * (2 * Math.PI / w) * (Math.PI / h);
    for (let i = 0; i < w; i += 2) {
      const p = ((i + 0.5) / w - 0.5) * 2 * Math.PI;
      const o = (j * w + i) * 4, c = [half(data[o]), half(data[o + 1]), half(data[o + 2])];
      const isSun = Math.cos(p) * ce * sun.x + se * sun.y + Math.sin(p) * ce * sun.z > cosSun;
      for (let k = 0; k < 3; k++) {
        if (isSun) { Es[k] += c[k] * se * dOm * 2; continue; }
        avg[k] += c[k] * dOm * 2; Eh[k] += c[k] * se * dOm * 2;
      }
      if (!isSun) sw += dOm * 2;
    }
  }
  for (let k = 0; k < 3; k++) avg[k] /= sw;
  return { tex: t, w, h, data, sun, avg, Eh, Es, sunPeak: best };
}

// 环境贴图：太阳压掉、下半球 = 沙地被（天光 + 太阳）照亮的亮度；k 整体缩放；rot 绕竖轴转（和天穹同一个转角）
function envOf(S, pm, k, rot) {
  const { w, h, data } = S;
  const out = new Uint16Array(w * h * 4);
  const cap = Math.max(S.avg[0], S.avg[1], S.avg[2]) * 6;   // 比天光平均亮 6 倍以上的（太阳、日晕）压平
  const g = SAND.map((a, i) => a * (S.Eh[i] + S.Es[i]) / Math.PI * k);
  const shift = Math.round(-rot / (2 * Math.PI) * w);
  for (let j = 0; j < h; j++) {
    const below = (j + 0.5) / h > 0.5, blend = below ? Math.min(1, ((j + 0.5) / h - 0.5) * 40) : 0;
    for (let i = 0; i < w; i++) {
      const si = ((i - shift) % w + w) % w, o = (j * w + si) * 4, d = (j * w + i) * 4;
      for (let c = 0; c < 3; c++) {
        let v = Math.min(half(data[o + c]), cap) * k;
        if (below) v = v * (1 - blend) + g[c] * blend;
        out[d + c] = toHalf(v);
      }
      out[d + 3] = toHalf(1);
    }
  }
  const t = new THREE.DataTexture(out, w, h, THREE.RGBAFormat, THREE.HalfFloatType);
  t.mapping = THREE.EquirectangularReflectionMapping; t.flipY = S.tex.flipY; t.colorSpace = THREE.LinearSRGBColorSpace;
  t.minFilter = t.magFilter = THREE.LinearFilter; t.generateMipmaps = false; t.needsUpdate = true;
  const env = pm.fromEquirectangular(t).texture;
  t.dispose();
  return env;
}

export async function loadSkies(renderer, DATA) {
  const S = {};
  for (const [key, f] of Object.entries(SKY_FILES)) {
    try { S[key] = await loadOne(`${DATA}/assets/ph/${f}_2k.hdr`); } catch (e) { console.log('[film] 天空 HDRI 没有：', f, e && e.message); }
  }
  for (const k in S) {
    const t = S[k].tex;
    t.wrapS = THREE.RepeatWrapping; t.wrapT = THREE.ClampToEdgeWrapping;
    t.minFilter = THREE.LinearFilter; t.magFilter = THREE.LinearFilter; t.generateMipmaps = false;
    t.needsUpdate = true;
  }
  const pm = new THREE.PMREMGenerator(renderer);
  const cache = {};
  return {
    has: k => !!S[k],
    sky: k => S[k],
    // 绕竖轴的转角：让 HDRI 里的太阳转到镜头要的方位（只管方位，高度角是 HDRI 自己的）
    rotFor(k, sunDir) { const s = S[k].sun; return Math.atan2(sunDir.z, sunDir.x) - Math.atan2(s.z, s.x); },
    // 环境贴图：天光平均亮度对上 target（原来半球光天空色 × 强度 ÷ π），同一个（天空、转角、亮度）只烘一次
    env(k, rot, target) {
      const s = S[k], ky = (s.avg[0] * 0.2126 + s.avg[1] * 0.7152 + s.avg[2] * 0.0722);
      const sc = target / Math.max(ky, 1e-6);
      const key = `${k}|${rot.toFixed(2)}|${sc.toPrecision(3)}`;
      if (!cache[key]) cache[key] = envOf(s, pm, sc, rot);
      return cache[key];
    },
  };
}

// 扫描贴图里大尺度的明暗（拍的时候光照、湿度不匀：sandy_gravel_02 上半张亮、下半张暗）一铺开就是一道道条纹——
//   除以它自己的低频部分（8×8 格子平均、按平铺包边双线性放大），只留碎石、沙粒的细节，平均颜色不变
function flattenTex(t) {
  const img = t.image, W = img.width, H = img.height;
  const cv = document.createElement('canvas'); cv.width = W; cv.height = H;
  const g = cv.getContext('2d', { willReadFrequently: true }); g.drawImage(img, 0, 0);
  const src = g.getImageData(0, 0, W, H);
  const N = 8, cell = new Float32Array(N * N * 3);
  const d = src.data;
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const o = (y * W + x) * 4, c = (((y * N / H) | 0) * N + ((x * N / W) | 0)) * 3;
    cell[c] += d[o]; cell[c + 1] += d[o + 1]; cell[c + 2] += d[o + 2];
  }
  const per = (W / N) * (H / N), mean = [0, 0, 0];
  for (let i = 0; i < N * N; i++) for (let k = 0; k < 3; k++) { cell[i * 3 + k] /= per; mean[k] += cell[i * 3 + k] / (N * N); }
  const c = (i, j, k) => cell[((((j % N) + N) % N) * N + (((i % N) + N) % N)) * 3 + k];
  for (let y = 0; y < H; y++) {
    const fy = y * N / H - 0.5, y0 = Math.floor(fy), ay = fy - y0;
    for (let x = 0; x < W; x++) {
      const fx = x * N / W - 0.5, x0 = Math.floor(fx), ax = fx - x0, o = (y * W + x) * 4;
      for (let k = 0; k < 3; k++) {
        const low = (c(x0, y0, k) * (1 - ax) + c(x0 + 1, y0, k) * ax) * (1 - ay) + (c(x0, y0 + 1, k) * (1 - ax) + c(x0 + 1, y0 + 1, k) * ax) * ay;
        d[o + k] = Math.max(0, Math.min(255, d[o + k] * mean[k] / Math.max(low, 1)));
      }
    }
  }
  g.putImageData(src, 0, 0);
  const t2 = new THREE.CanvasTexture(cv);
  t2.colorSpace = t.colorSpace; t2.flipY = t.flipY;
  t.dispose();
  return t2;
}
// 地表贴图（PBR：底色、法线、arm）
export const GROUND_SETS = { sand: 'sandy_gravel_02', gravel: 'gravelly_sand', crack: 'dry_ground_01', rock: 'rock_06' };
export async function loadGround(DATA, loadTex) {
  const out = {};
  for (const [k, f] of Object.entries(GROUND_SETS)) {
    try {
      let [d, n, a] = await Promise.all([loadTex(`${DATA}/assets/ph/${f}_Diffuse_2k.jpg`, true), loadTex(`${DATA}/assets/ph/${f}_nor_gl_2k.jpg`, false), loadTex(`${DATA}/assets/ph/${f}_arm_2k.jpg`, false)]);
      d = flattenTex(d);
      for (const t of [d, n, a]) { t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = 8; t.generateMipmaps = true; t.minFilter = THREE.LinearMipmapLinearFilter; t.needsUpdate = true; }
      // 底色的平均值（贴图除以它当细节，大块的颜色还照游戏的材质）
      const cv = document.createElement('canvas'); cv.width = cv.height = 16;
      const g = cv.getContext('2d', { willReadFrequently: true }); g.drawImage(d.image, 0, 0, 16, 16);
      const px = g.getImageData(0, 0, 16, 16).data; const m = [0, 0, 0];
      for (let i = 0; i < px.length; i += 4) for (let c = 0; c < 3; c++) m[c] += Math.pow(px[i + c] / 255, 2.2);
      out[k] = { d, n, a, mean: new THREE.Vector3(m[0], m[1], m[2]).multiplyScalar(1 / 256) };
    } catch (e) { console.log('[film] 地表贴图没有：', f, e && e.message); return null; }
  }
  return out;
}
