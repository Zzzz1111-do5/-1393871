// 微电影主程序：载入数据、搭世界，按分镜（shots.js）把任意镜头的任意时刻渲出来；配乐（audio.js）也从这里离线合成
import * as THREE from 'three';
import { patchFog, makeSky, makeSea, makeTerrain, makeParts, makeNoiseTex, makeGrimeTex, groundY } from './world.js';
import { Post } from './post.js';
import { FX } from './fx.js';
import { setMeta, loadGLB } from './models.js';
import { SHOTS, setupShot } from './shots.js';
import { Titles } from './titles.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

const Q = new URLSearchParams(location.search);
const W = +(Q.get('w') || 1920), H = +(Q.get('h') || 1080), FPS = +(Q.get('fps') || 24), SS = +(Q.get('ss') || 1);
const DATA = '/data', REPO = '/repo';
const log = (...a) => console.log('[film]', ...a);

async function bin(url, T) { return new T(await (await fetch(url)).arrayBuffer()); }
function tex(url, srgb = true) {
  return new Promise((res, rej) => new THREE.TextureLoader().load(url, t => { t.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace; res(t); }, undefined, rej));
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
    const D = { ...world, world, height: await bin(`${DATA}/height.bin`, Float32Array), mat: await bin(`${DATA}/mat.bin`, Uint8Array) };
    const T = {
      noise: makeNoiseTex(256, 3), sand: await tex(`${DATA}/assets/terrain/sand.jpg`), water: await tex(`${DATA}/assets/water/normals.jpg`, false),
      expl: await tex(`${DATA}/assets/vfx/expl.webp`, false), fire: await tex(`${DATA}/assets/vfx/fire.webp`, false), mzl: await tex(`${DATA}/assets/vfx/mzl.webp`, false),
      mzla: await tex(`${DATA}/assets/vfx/mzla.webp`, false), puff: await tex(`${DATA}/assets/vfx/puff.webp`),
    };
    T.sand.wrapS = T.sand.wrapT = THREE.RepeatWrapping; T.sand.anisotropy = 8;
    T.grime = makeGrimeTex(T.noise);
    for (const k of ['expl', 'fire', 'mzl', 'mzla', 'puff']) { T[k].generateMipmaps = true; T[k].minFilter = THREE.LinearMipmapLinearFilter; }

    const post = new Post(renderer, W, H, { ss: SS, msaa: 4 });
    const scene = new THREE.Scene();
    scene.fog = new THREE.FogExp2(0x1d2738, 0.00042);
    const camera = new THREE.PerspectiveCamera(35, post.rw / post.rh, 0.5, 120000);
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
    const terrain = makeTerrain(D, T);
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

    const env = { THREE, renderer, scene, camera, sky, sea, terrain, parts, moon, hemi, fx, D, T, post, titles, REPO, groundY: (x, z) => groundY(D, x, z), FPS, W, H, log };
    // 片名、片尾那几个镜头不要地形、海、天
    env.worldVisible = on => { for (const o of [sky, sea, terrain, parts.group]) o.visible = on; moon.visible = on; hemi.visible = on; };
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
      scene.updateMatrixWorld(true);
      // 天空、雾、月亮跟着镜头参数走
      sky.position.copy(camera.position);
      const su = sky.material.uniforms;
      su.uTime.value = t + (sh.t0 || 0);
      const fogC = P.fogColor || new THREE.Color(0x1d2738);
      scene.fog.color.copy(fogC); scene.fog.density = P.fogDensity ?? 0.00042;
      su.uFog.value.copy(fogC); su.uDawn.value = P.dawn || 0;
      if (P.moonDir) su.uMoon.value.copy(P.moonDir); else su.uMoon.value.set(0.3, 0.28, -0.91).normalize();
      su.uSun.value.copy(P.sunDir || new THREE.Vector3(0.6, 0.02, -0.8).normalize());
      su.uMoonI.value = P.moonVis ?? 1;
      moon.intensity = P.moonI ?? 3.0; hemi.intensity = P.hemiI ?? 1.15;
      moon.color.set(P.moonC ?? 0xa6badf);
      sea.userData.mat.uniforms.uMoon.value.copy(su.uMoon.value);
      moon.position.copy(su.uMoon.value).multiplyScalar(3000).add(P.shadowAt || camera.position);
      moon.target.position.copy(P.shadowAt || camera.position);
      const sr = P.shadowR || 300;
      Object.assign(moon.shadow.camera, { left: -sr, right: sr, top: sr, bottom: -sr, near: 100, far: 7000 });
      moon.shadow.camera.updateProjectionMatrix();
      fx.setFog(scene.fog);
      fx.update(t, camera);
      if (sea.visible) sea.userData.prepare(renderer, scene, camera, t + (sh.t0 || 0));
      post.render(scene, camera, { ...P, time: t + (sh.t0 || 0) });
      // 画面拷到输出画布、叠字幕
      ctx.drawImage(renderer.domElement, 0, 0);
      titles.draw(ctx, sh.titles ? sh.titles(t) : null, t);
    }
    window.FILM = {
      ready: true, canvas, jpg: true, shots: SHOTS.map(s => ({ id: s.id, dur: s.dur })),
      async renderAt(id, t) { const t0 = performance.now(); const sh = await enter(id); frame(sh, t); return performance.now() - t0; },
      info() { return { W, H, rw: post.rw, rh: post.rh, gl: renderer.getContext().getParameter(renderer.getContext().VERSION), tris: renderer.info.render.triangles, calls: renderer.info.render.calls }; },
      async renderAudio() { const { renderScore } = await import('./audio.js'); return renderScore(SHOTS); },
    };
    log('准备好了', W, H);
  } catch (e) {
    console.error('[film] 出错', e && e.stack || e);
    window.FILM = { ready: true, error: String(e) };
  }
})();
