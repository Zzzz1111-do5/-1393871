// 车内、座舱（游戏里一比一的内饰）：tools/mock/interior_dump.lua 导出的 JSON（零件、灯、屏幕上的界面、各乘员位的镜头，坐标是车体 / 飞行员眼位的，单位格）
//   搭成一个 THREE.Group：零件按形状、颜色、Roblox 材质；屏幕按导出的界面节点画到画布上当贴图（自己发光）；灯换成点光源
//   导出：python3 tools/mock/run.py tools/mock/interior.lua veh=m1a2 dump=<目录>（座舱 tools/mock/cockpit.lua air=j20 dump=<目录>）
import * as THREE from 'three';

function wedgeGeo(w, h, l) {
  const A = [-w / 2, -h / 2, -l / 2], B = [w / 2, -h / 2, -l / 2], C = [-w / 2, -h / 2, l / 2], D = [w / 2, -h / 2, l / 2], E = [-w / 2, h / 2, l / 2], F = [w / 2, h / 2, l / 2];
  const tris = [A, C, D, A, D, B, C, E, F, C, F, D, A, B, F, A, F, E, A, E, C, B, D, F];
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(tris.flat(), 3));
  g.computeVertexNormals();
  return g;
}
const MAT = {};
function mat(m, col, t, grime) {
  const key = m + col.join(',') + t;
  if (MAT[key]) return MAT[key];
  const c = new THREE.Color(col[0] / 255, col[1] / 255, col[2] / 255).convertSRGBToLinear();
  let o;
  if (m === 'Neon') o = new THREE.MeshStandardMaterial({ color: c, emissive: c, emissiveIntensity: 2.2 });
  else if (m === 'Glass') o = new THREE.MeshPhysicalMaterial({ color: c, roughness: 0.04, metalness: 0, transparent: true, opacity: Math.min(0.32, 1 - t), reflectivity: 0.7, depthWrite: false });
  else o = new THREE.MeshStandardMaterial({ color: c, map: grime || null, roughness: m === 'Metal' ? 0.42 : (m === 'Fabric' ? 0.95 : 0.6), metalness: (m === 'Metal' || m === 'DiamondPlate') ? 0.5 : 0.02, envMapIntensity: 0.25 });
  if (t > 0.01 && m !== 'Glass') { o.transparent = true; o.opacity = 1 - t; }
  MAT[key] = o;
  return o;
}
// 界面节点（Frame / TextLabel 的绝对位置、颜色、字）画到画布上
export function drawGui(ctx, nodes, sx, sy) {
  for (const n of nodes) {
    if (!n.v) continue;
    ctx.save();
    const x = n.x * sx, y = n.y * sy, w = n.w * sx, h = n.h * sy;
    ctx.translate(x + w / 2, y + h / 2);
    if (n.rot) ctx.rotate(n.rot * Math.PI / 180);
    if (n.bt < 0.99) {
      ctx.globalAlpha = 1 - n.bt;
      ctx.fillStyle = `rgb(${n.bg[0]},${n.bg[1]},${n.bg[2]})`;
      if (n.round) { ctx.beginPath(); ctx.ellipse(0, 0, Math.abs(w / 2), Math.abs(h / 2), 0, 0, Math.PI * 2); ctx.fill(); } else ctx.fillRect(-w / 2, -h / 2, w, h);
      ctx.globalAlpha = 1;
    }
    if (n.st) {
      ctx.strokeStyle = `rgb(${n.st[0]},${n.st[1]},${n.st[2]})`;
      ctx.lineWidth = (n.stw || 1) * sx;
      if (n.round) { ctx.beginPath(); ctx.ellipse(0, 0, Math.abs(w / 2), Math.abs(h / 2), 0, 0, Math.PI * 2); ctx.stroke(); } else ctx.strokeRect(-w / 2, -h / 2, w, h);
    }
    if (n.text) {
      ctx.fillStyle = `rgb(${n.tc[0]},${n.tc[1]},${n.tc[2]})`;
      ctx.font = `${n.bold ? 'bold ' : ''}${Math.max(6, n.ts * sy)}px "Noto Sans SC", monospace`;
      ctx.textBaseline = 'middle';
      ctx.textAlign = n.al === 'Right' ? 'right' : (n.al === 'Center' ? 'center' : 'left');
      const tx = n.al === 'Right' ? w / 2 : (n.al === 'Center' ? 0 : -w / 2);
      ctx.fillText(n.text, tx, 0);
    }
    ctx.restore();
  }
}
const M4 = c => new THREE.Matrix4().set(c[3], c[4], c[5], c[0], c[6], c[7], c[8], c[1], c[9], c[10], c[11], c[2], 0, 0, 0, 1);
// opt：grime 细节纹理、screenGlow 屏幕亮度、lights 灯的亮度倍数（0 不要灯）、skip(page) 不画哪些屏幕（另外自己画的）
export function buildInterior(D, opt = {}) {
  const root = new THREE.Group();
  for (const p of D.parts) {
    let g;
    const [sx, sy, sz] = p.z;
    if (p.s === 'Cylinder') { g = new THREE.CylinderGeometry(sy / 2, sy / 2, sx, 20); g.rotateZ(Math.PI / 2); }
    else if (p.s === 'Ball') g = new THREE.SphereGeometry(sx / 2, 16, 12);
    else if (p.s === 'Sphere') { g = new THREE.SphereGeometry(0.5, 16, 12); g.scale(sx, sy, sz); }
    else if (p.s === 'Wedge') g = wedgeGeo(sx, sy, sz);
    else g = new THREE.BoxGeometry(sx, sy, sz);
    const m = new THREE.Mesh(g, mat(p.m, p.k, p.t, opt.grime));
    m.matrixAutoUpdate = false;
    m.matrix.copy(M4(p.c));
    m.castShadow = Math.max(sx, sy, sz) > 0.14 && p.m !== 'Glass';
    m.receiveShadow = true;
    m.renderOrder = p.m === 'Glass' ? 5 : 0;
    root.add(m);
  }
  const screens = [];
  for (const s of (D.screens || [])) {
    if (opt.skip && opt.skip(s.page)) continue;
    const cv = document.createElement('canvas');
    const aspect = s.z[0] / s.z[1];
    cv.width = 640; cv.height = Math.max(8, Math.round(640 / aspect));
    const ctx = cv.getContext('2d');
    const glass = s.page === 'hud';
    if (!glass) { ctx.fillStyle = '#000'; ctx.fillRect(0, 0, cv.width, cv.height); }
    if (s.gui) drawGui(ctx, s.gui, cv.width / s.pw, cv.height / s.ph);
    const tex = new THREE.CanvasTexture(cv);
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.anisotropy = 8;
    const k = opt.screenGlow ?? 1.4;
    const pl = new THREE.Mesh(new THREE.PlaneGeometry(s.z[0], s.z[1]), new THREE.MeshBasicMaterial({ map: tex, color: new THREE.Color(k, k, k), transparent: glass, depthWrite: !glass, fog: false,
      blending: glass ? THREE.AdditiveBlending : THREE.NormalBlending }));
    const M = M4(s.c);
    // SurfaceGui 的 Front 面是零件的 −Z：平面默认朝 +Z，转半圈，再往前挪一点免得被零件挡住
    M.multiply(new THREE.Matrix4().makeRotationY(Math.PI)).multiply(new THREE.Matrix4().makeTranslation(0, 0, 0.004));
    pl.matrixAutoUpdate = false;
    pl.matrix.copy(M);
    pl.renderOrder = glass ? 6 : 1;
    root.add(pl);
    screens.push({ page: s.page, mesh: pl, canvas: cv, ctx, tex, s });
  }
  const lights = [];
  if ((opt.lights ?? 1) > 0) {
    for (const L of (D.lights || [])) {
      if (!(L.b > 0)) continue;
      const pl = new THREE.PointLight(new THREE.Color(L.k[0] / 255, L.k[1] / 255, L.k[2] / 255), L.b * 9 * (opt.lights ?? 1), L.r * 1.25, 1.4);
      pl.position.set(...L.p);
      root.add(pl);
      lights.push(pl);
    }
  }
  const cams = {};
  for (const c of (D.cams || [])) cams[c.name] = { m: M4(c.c), fov: c.fov };
  return { root, screens, lights, cams };
}
