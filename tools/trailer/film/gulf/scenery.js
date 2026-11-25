// 海湾战争版的场景：地上的碎石、骆驼刺，公路边的电线杆，油井（抽油机、井口），爱国者阵地（雷达、发射车、沙土掩体），
//   镇子（平顶土房、清真寺），机场的机库掩体，烧黑的残骸。位置都按游戏地图（world.json：镇子、油田、油井、公路）摆
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { V3, rng, clamp, lerp, DEG } from '../lib.js';
import { heightAt } from '../bigmap.js';

const M = (c, r = 0.9, m = 0, extra = {}) => new THREE.MeshStandardMaterial({ color: c, roughness: r, metalness: m, envMapIntensity: 0.25, ...extra });
const mesh = (g, m, cast = true) => { const o = new THREE.Mesh(g, m); o.castShadow = cast; o.receiveShadow = true; return o; };

// —— 地上的碎石、骆驼刺：镜头附近铺一圈（实例化），离中心越远越稀 ——
export function clutter(cx, cz, r = 420, o = {}) {
  const g = new THREE.Group();
  const R = rng(o.seed || 7);
  // 碎石：二十面体细分一次、顶点按噪声推一推（不规则的块，不是一颗颗一样的十二面体），颜色混着灰白的石灰岩、黄褐的砂岩、发黑的沙漠漆石头
  const rockG = new THREE.IcosahedronGeometry(1, 1);
  {
    const pa = rockG.attributes.position, v = new THREE.Vector3();
    for (let i = 0; i < pa.count; i++) {
      v.fromBufferAttribute(pa, i);
      const f = 0.72 + 0.28 * Math.sin(v.x * 4.1 + 1.3) * Math.cos(v.y * 3.7 - 0.4) + 0.18 * Math.sin(v.z * 7.3 + v.x * 2.1);
      v.multiplyScalar(f); pa.setXYZ(i, v.x, v.y * 0.8, v.z);
    }
    rockG.computeVertexNormals();
  }
  const rockM = M(0xffffff, 0.92);
  const n = o.rocks ?? 1600;
  const rocks = new THREE.InstancedMesh(rockG, rockM, n);
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), s = new THREE.Vector3(), p = new THREE.Vector3();
  const col = new THREE.Color();
  let k = 0;
  for (let i = 0; i < n * 3 && k < n; i++) {
    const a = R() * Math.PI * 2, d = r * Math.sqrt(R());
    const x = cx + Math.cos(a) * d, z = cz + Math.sin(a) * d;
    if (o.avoid && o.avoid(x, z)) continue;
    const sz = 0.12 + Math.pow(R(), 4) * 1.1;
    p.set(x, heightAt(x, z) + sz * 0.25, z);
    q.setFromEuler(new THREE.Euler(R() * 3, R() * 6, R() * 3));
    s.set(sz * (0.8 + R() * 0.6), sz * (0.45 + R() * 0.4), sz * (0.8 + R() * 0.6));
    m4.compose(p, q, s);
    rocks.setMatrixAt(k, m4);
    const kind = R(), lv = 0.85 + R() * 0.3;
    // 线性反照率：比沙地（约 0.40 / 0.30 / 0.17）略暗、偏灰；沙漠漆的石头更暗
    if (kind < 0.45) col.setRGB(0.23 * lv, 0.195 * lv, 0.15 * lv);       // 灰白石灰岩（朝太阳的面比平地多吃一倍多的光，反照率要比沙低）
    else if (kind < 0.8) col.setRGB(0.2 * lv, 0.14 * lv, 0.09 * lv);     // 黄褐砂岩
    else col.setRGB(0.085 * lv, 0.065 * lv, 0.05 * lv);                  // 沙漠漆：晒黑的石头
    rocks.setColorAt(k, col);
    k++;
  }
  rocks.count = k;
  rocks.castShadow = true; rocks.receiveShadow = true;
  g.add(rocks);
  // 骆驼刺：一团团矮的干枯灌丛（几个压扁的十二面体叠在一起）
  const nb = o.shrubs ?? 70;
  const shrubG = new THREE.IcosahedronGeometry(1, 1);
  const shrubM = M(0x5a4b32, 1.0);
  const shrubs = new THREE.InstancedMesh(shrubG, shrubM, nb * 3);
  let b = 0;
  for (let i = 0; i < nb; i++) {
    const a = R() * Math.PI * 2, d = r * Math.sqrt(R());
    const x = cx + Math.cos(a) * d, z = cz + Math.sin(a) * d;
    if (o.avoid && o.avoid(x, z)) continue;
    const y = heightAt(x, z), sz = 0.4 + R() * 0.9;
    for (let j = 0; j < 3; j++) {
      p.set(x + (R() - 0.5) * sz, y + sz * 0.3, z + (R() - 0.5) * sz);
      q.setFromEuler(new THREE.Euler(0, R() * 6, 0));
      s.set(sz * (0.5 + R() * 0.4), sz * (0.32 + R() * 0.2), sz * (0.5 + R() * 0.4));
      m4.compose(p, q, s);
      shrubs.setMatrixAt(b, m4);
      col.setRGB(0.32 + R() * 0.12, 0.27 + R() * 0.1, 0.17 + R() * 0.06);
      shrubs.setColorAt(b, col);
      b++;
    }
  }
  shrubs.count = b;
  shrubs.castShadow = true; shrubs.receiveShadow = true;
  g.add(shrubs);
  return g;
}

// —— 电线杆：沿公路一侧每 120 格一根，横担、瓷瓶、电线（下垂的折线）——
export function poles(road, from = 0, to = 1e9, side = 1) {
  const g = new THREE.Group();
  const wood = M(0x5b4632, 0.9), dark = M(0x2a2a2a, 0.6, 0.2);
  const pts = road.p;
  let acc = 0, next = 0;
  const tops = [];
  for (let i = 0; i < pts.length - 1; i++) {
    const [ax, az] = pts[i], [bx, bz] = pts[i + 1];
    const L = Math.hypot(bx - ax, bz - az);
    if (L < 1e-3) continue;
    const dx = (bx - ax) / L, dz = (bz - az) / L;
    while (next <= acc + L) {
      const u = next - acc;
      const x = ax + dx * u - dz * side * (road.w * 0.5 + 16), z = az + dz * u + dx * side * (road.w * 0.5 + 16);
      if (next >= from && next <= to) {
        const y = heightAt(x, z);
        const pole = mesh(new THREE.CylinderGeometry(0.22, 0.3, 11, 7), wood);
        pole.position.set(x, y + 5.5, z);
        g.add(pole);
        const arm = mesh(new THREE.BoxGeometry(3.6, 0.25, 0.25), wood);
        arm.position.set(x, y + 10.3, z);
        arm.rotation.y = Math.atan2(dx, dz) + Math.PI / 2;
        g.add(arm);
        const tops3 = [-1.5, 0, 1.5].map(o => V3(x + Math.cos(arm.rotation.y) * o * -1, y + 10.6, z + Math.sin(arm.rotation.y) * o));
        tops.push(tops3);
      }
      next += 120;
    }
    acc += L;
  }
  // 电线：相邻两根之间下垂
  const wm = new THREE.LineBasicMaterial({ color: 0x1c1c1c });
  for (let i = 0; i < tops.length - 1; i++) for (let k = 0; k < 3; k++) {
    const a = tops[i][k], b = tops[i + 1][k];
    const P = [];
    for (let s = 0; s <= 8; s++) { const t = s / 8; P.push(a.clone().lerp(b, t).add(V3(0, -2.2 * 4 * t * (1 - t), 0))); }
    g.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints(P), wm));
  }
  return g;
}

// —— 油井：抽油机（磕头机）、井口阀门、输油管；fire 着火的只剩井口（抽油机炸倒了）——
export function pumpjack(o = {}) {
  const g = new THREE.Group();
  const steel = M(o.color ?? 0x6d665c, 0.6, 0.5), dark = M(0x2c2a27, 0.7, 0.4), conc = M(0x9a948a, 0.95);
  const base = mesh(new THREE.BoxGeometry(5, 0.8, 14), conc); base.position.y = 0.4; g.add(base);
  const skid = mesh(new THREE.BoxGeometry(3, 0.6, 12), dark); skid.position.y = 1.1; g.add(skid);
  for (const s of [-1, 1]) {   // A 字架
    const leg = mesh(new THREE.BoxGeometry(0.35, 9.5, 0.35), steel);
    leg.position.set(s * 1.1, 5.4, 0.6); leg.rotation.z = -s * 0.1; g.add(leg);
    const brace = mesh(new THREE.BoxGeometry(0.3, 9.8, 0.3), steel);
    brace.position.set(s * 1.0, 5.4, 2.6); brace.rotation.x = -0.4; brace.rotation.z = -s * 0.1; g.add(brace);
  }
  const beamPiv = new THREE.Group(); beamPiv.position.set(0, 10.2, 0.6); g.add(beamPiv);
  const beam = mesh(new THREE.BoxGeometry(0.6, 0.9, 12), steel); beam.position.z = 0.5; beamPiv.add(beam);
  const head = mesh(new THREE.CylinderGeometry(2.2, 2.2, 0.7, 16, 1, false, 0, Math.PI), steel);
  head.rotation.z = Math.PI / 2; head.rotation.y = Math.PI / 2; head.position.set(0, -0.6, -5.6); beamPiv.add(head);
  for (const s of [-1, 1]) {   // 曲柄、配重
    const cw = mesh(new THREE.BoxGeometry(0.5, 3.2, 2.6), dark); cw.position.set(s * 1.4, 3.2, 5.6); g.add(cw);
  }
  const box = mesh(new THREE.BoxGeometry(2.2, 1.8, 2.4), M(0x7a3a26, 0.8)); box.position.set(0, 2, 6.6); g.add(box);   // 电机
  const well = mesh(new THREE.CylinderGeometry(0.35, 0.35, 3.4, 8), dark); well.position.set(0, 1.7, -5.6); g.add(well);
  g.userData.beam = beamPiv;
  g.userData.anim = t => { beamPiv.rotation.x = Math.sin(t * 1.3 + (o.ph || 0)) * 0.28; };
  return g;
}
export function wellhead() {
  const g = new THREE.Group();
  const red = M(0x6a2e20, 0.7, 0.4), dark = M(0x262421, 0.7, 0.4);
  const c = mesh(new THREE.CylinderGeometry(0.6, 0.7, 4.2, 10), dark); c.position.y = 2.1; g.add(c);
  for (const y of [1.2, 2.4, 3.4]) { const v = mesh(new THREE.CylinderGeometry(0.9, 0.9, 0.35, 12), red); v.position.y = y; g.add(v); }
  const arm = mesh(new THREE.CylinderGeometry(0.28, 0.28, 3, 8), dark); arm.rotation.z = Math.PI / 2; arm.position.set(1.4, 2.4, 0); g.add(arm);
  const ring = mesh(new THREE.CylinderGeometry(3.2, 3.6, 0.6, 16), M(0x3a332b, 1)); ring.position.y = 0.2; g.add(ring);   // 烧黑的一圈
  return g;
}

// —— 爱国者阵地：相控阵雷达车（平板天线朝北）、指挥车、电源车、四辆发射车围成半圈，各自在沙土掩体里 ——
//   launchers：传进来已经载好的发射车（models.js vehicle('patriot')）
export function samSite(cx, cz, launchers, o = {}) {
  const g = new THREE.Group();
  const y0 = heightAt(cx, cz);
  const sand = M(0xb39467, 1.0), olive = M(o.color ?? 0x8b7d5c, 0.8, 0.2), dark = M(0x262624, 0.7, 0.3), panel = M(0x4a4a44, 0.5, 0.3);
  const face = o.face ?? 0;   // 雷达朝向（0 = 北）
  // 掩体：一圈 U 形沙堤（管状扫掠）
  const berm = (x, z, r, a0, a1, h = 3.2) => {
    const pts = [];
    for (let i = 0; i <= 20; i++) { const a = a0 + (a1 - a0) * i / 20; pts.push(V3(x + Math.sin(a) * r, heightAt(x + Math.sin(a) * r, z - Math.cos(a) * r) + 0.2, z - Math.cos(a) * r)); }
    const curve = new THREE.CatmullRomCurve3(pts);
    const tube = mesh(new THREE.TubeGeometry(curve, 40, h, 8, false), sand, false);
    tube.scale.y = 1; tube.position.y = -h * 0.55;
    g.add(tube);
  };
  // 雷达（AN/MPQ-65 的样子：拖车 + 斜立的大平板天线）
  const radar = new THREE.Group();
  const rx = cx + Math.sin(face) * 0, rz = cz;
  const tr = mesh(new RoundedBoxGeometry(5.2, 2.4, 13, 2, 0.2), olive); tr.position.y = 2.6; radar.add(tr);
  for (const s of [-1, 1]) for (const zz of [-3.5, 3.5]) { const w = mesh(new THREE.CylinderGeometry(1.1, 1.1, 0.8, 14), dark); w.rotation.z = Math.PI / 2; w.position.set(s * 2.4, 1.1, zz); radar.add(w); }
  const antPiv = new THREE.Group(); antPiv.position.set(0, 4, -3.5); radar.add(antPiv);
  const ant = mesh(new THREE.BoxGeometry(5.6, 7.2, 0.7), panel); ant.position.set(0, 3.2, 0); ant.rotation.x = -0.35; antPiv.add(ant);
  const face2 = mesh(new THREE.CircleGeometry(2.4, 32), M(0x3b3d3a, 0.4, 0.2)); face2.position.set(0, 3.25, -0.37); face2.rotation.x = -0.35; face2.rotation.y = Math.PI; antPiv.add(face2);
  radar.position.set(rx, y0, rz); radar.rotation.y = face;
  g.add(radar);
  berm(rx, rz, 16, face + Math.PI * 0.35, face + Math.PI * 1.65);
  // 指挥车（ECS 方舱）、电源车
  const ecs = new THREE.Group();
  const cab = mesh(new RoundedBoxGeometry(3, 3, 3.6, 2, 0.2), olive); cab.position.set(0, 2.2, -4.6); ecs.add(cab);
  const shel = mesh(new RoundedBoxGeometry(3.2, 3.6, 7, 2, 0.15), olive); shel.position.set(0, 3.2, 1.2); ecs.add(shel);
  for (const s of [-1, 1]) for (const zz of [-4.4, 0.5, 3.4]) { const w = mesh(new THREE.CylinderGeometry(0.75, 0.75, 0.6, 12), dark); w.rotation.z = Math.PI / 2; w.position.set(s * 1.5, 0.75, zz); ecs.add(w); }
  ecs.position.set(cx - 42, heightAt(cx - 42, cz + 30), cz + 30); ecs.rotation.y = 0.6;
  g.add(ecs);
  const gen = ecs.clone(); gen.position.set(cx - 30, heightAt(cx - 30, cz + 48), cz + 48); gen.rotation.y = 1.1; g.add(gen);
  // 发射车：半圈，各自在掩体里，发射箱朝北仰着
  const L = [];
  launchers.forEach((V, i) => {
    const a = face + (-0.9 + 1.8 * i / Math.max(1, launchers.length - 1));
    const d = o.r ?? 110;
    const x = cx + Math.sin(a) * d, z = cz - Math.cos(a) * d;
    V.root.position.set(x, heightAt(x, z), z);
    V.root.rotation.y = a + Math.PI;   // 车头朝外（发射箱朝外仰）：模型车头 −Z
    g.add(V.root);
    berm(x, z, 13, a + Math.PI + 0.9, a + Math.PI * 2.9);
    L.push({ V, x, z, a });
  });
  g.userData = { radar, antPiv, ecs, gen, launchers: L, y0 };
  return g;
}

// —— 镇子：平顶土房（带女儿墙、窗洞）、院墙、清真寺（圆顶、宣礼塔）、水塔 ——
export function town(cx, cz, o = {}) {
  const g = new THREE.Group();
  const R = rng(o.seed || 902);
  const walls = [0xc9b28c, 0xbfa57d, 0xd2bf9c, 0xb59a74, 0xcbb592].map(c => M(c, 0.95));
  const dark = M(0x1d1915, 0.9), wood = M(0x5a4430, 0.9);
  const box = new THREE.BoxGeometry(1, 1, 1);
  const n = o.n ?? 70, rad = o.r ?? 380;
  const placed = [];
  for (let i = 0; i < n * 4 && placed.length < n; i++) {
    const a = R() * Math.PI * 2, d = rad * Math.sqrt(R());
    const x = cx + Math.cos(a) * d, z = cz + Math.sin(a) * d;
    const w = 14 + R() * 18, dd = 12 + R() * 16, h = (R() < 0.3 ? 2 : 1) * (9 + R() * 2);
    if (o.avoid && o.avoid(x, z, Math.max(w, dd))) continue;
    if (placed.some(p => Math.abs(p[0] - x) < (p[2] + w) / 2 + 7 && Math.abs(p[1] - z) < (p[3] + dd) / 2 + 7)) continue;
    placed.push([x, z, w, dd]);
    const y = heightAt(x, z);
    const m = walls[Math.floor(R() * walls.length)];
    const b = mesh(box, m); b.scale.set(w, h, dd); b.position.set(x, y + h / 2 - 0.5, z); g.add(b);
    const par = mesh(box, m); par.scale.set(w + 0.6, 1.1, dd + 0.6); par.position.set(x, y + h + 0.05, z); g.add(par);   // 女儿墙
    const roof = mesh(box, M(0x9c8a6c, 1)); roof.scale.set(w - 0.6, 0.3, dd - 0.6); roof.position.set(x, y + h + 0.2, z); g.add(roof);
    // 窗洞、门洞（暗的方块贴在墙面上）
    for (let f = 0; f < 4; f++) {
      const along = (f % 2 === 0) ? w : dd, nWin = Math.max(1, Math.floor(along / 7));
      for (let k = 0; k < nWin; k++) for (let lv = 0; lv < h / 10 - 0.2; lv++) {
        if (R() < 0.3) continue;
        const win = mesh(box, dark, false);
        const off = (k + 0.5) / nWin * along - along / 2;
        const wy = y + 3.6 + lv * 10;
        if (f === 0) { win.scale.set(1.8, 2.2, 0.3); win.position.set(x + off, wy, z - dd / 2 - 0.05); }
        if (f === 1) { win.scale.set(0.3, 2.2, 1.8); win.position.set(x + w / 2 + 0.05, wy, z + off); }
        if (f === 2) { win.scale.set(1.8, 2.2, 0.3); win.position.set(x + off, wy, z + dd / 2 + 0.05); }
        if (f === 3) { win.scale.set(0.3, 2.2, 1.8); win.position.set(x - w / 2 - 0.05, wy, z + off); }
        g.add(win);
      }
    }
    if (R() < 0.35) {   // 院墙
      const cw = mesh(box, m); cw.scale.set(w + 12, 4, 0.8); cw.position.set(x, y + 1.5, z + dd / 2 + 7); g.add(cw);
    }
  }
  // 清真寺：方殿、圆顶、宣礼塔
  if (o.mosque !== false) {
    const mx = cx + 40, mz = cz - 30, my = heightAt(mx, mz);
    const hall = mesh(box, walls[2]); hall.scale.set(30, 12, 30); hall.position.set(mx, my + 5.5, mz); g.add(hall);
    const dome = mesh(new THREE.SphereGeometry(10, 24, 12, 0, Math.PI * 2, 0, Math.PI / 2), M(0x8aa0a0, 0.5, 0.3)); dome.position.set(mx, my + 11.5, mz); g.add(dome);
    const tw = mesh(new THREE.CylinderGeometry(1.6, 1.9, 34, 12), walls[2]); tw.position.set(mx + 19, my + 16.5, mz - 19); g.add(tw);
    const bal = mesh(new THREE.CylinderGeometry(2.6, 2.6, 1.2, 12), walls[0]); bal.position.set(mx + 19, my + 28, mz - 19); g.add(bal);
    const cap = mesh(new THREE.ConeGeometry(1.9, 5, 12), M(0x8aa0a0, 0.5, 0.3)); cap.position.set(mx + 19, my + 36, mz - 19); g.add(cap);
  }
  // 水塔
  {
    const tx = cx - 120, tz = cz + 90, ty = heightAt(tx, tz);
    for (const [sx, sz] of [[-3, -3], [3, -3], [-3, 3], [3, 3]]) { const l = mesh(new THREE.CylinderGeometry(0.3, 0.3, 22, 6), M(0x6a6560, 0.6, 0.4)); l.position.set(tx + sx, ty + 11, tz + sz); g.add(l); }
    const tank = mesh(new THREE.SphereGeometry(6, 16, 10), M(0xb8b2a6, 0.5, 0.4)); tank.scale.y = 0.75; tank.position.set(tx, ty + 25, tz); g.add(tank);
  }
  g.userData.houses = placed;
  return g;
}

// —— 加固机库（海湾战争标志性的拱形混凝土机库）——
export function shelter(x, z, rot = 0) {
  const g = new THREE.Group();
  const conc = M(0x9d9688, 0.95), dark = M(0x111111, 0.9);
  const arch = mesh(new THREE.CylinderGeometry(14, 14, 36, 24, 1, true, -Math.PI / 2, Math.PI), conc);
  arch.rotation.x = Math.PI / 2; arch.rotation.y = 0; arch.position.y = 0; arch.material.side = THREE.DoubleSide;
  arch.scale.set(1.25, 1, 0.75);
  g.add(arch);
  const back = mesh(new THREE.CircleGeometry(14, 24, 0, Math.PI), conc); back.position.z = 18; back.rotation.y = Math.PI; back.scale.set(1.25, 0.75, 1); g.add(back);
  const door = mesh(new THREE.CircleGeometry(13.6, 24, 0, Math.PI), dark); door.position.z = -17.9; door.scale.set(1.25, 0.75, 1); g.add(door);
  const sand = mesh(new THREE.SphereGeometry(18, 20, 10, 0, Math.PI * 2, 0, Math.PI / 2), M(0xb79a6c, 1)); sand.scale.set(1.3, 0.62, 1.15); sand.position.z = 2; g.add(sand);
  g.position.set(x, heightAt(x, z), z);
  g.rotation.y = rot;
  return g;
}

// —— 烧黑的残骸：车模型的材质整体压黑、哑光（锈色斑），炮塔可以歪 ——
export function burnt(V, k = 1) {
  V.root.traverse(o => {
    if (!o.isMesh || !o.material) return;
    const one = m => { m = m.clone(); if (m.color) m.color.multiplyScalar(lerp(1, 0.14, k)).lerp(new THREE.Color(0.09, 0.06, 0.045), 0.4 * k); m.roughness = 1; m.metalness = 0.1; m.envMapIntensity = 0.05; if (m.map) m.map = m.map; return m; };
    o.material = Array.isArray(o.material) ? o.material.map(one) : one(o.material);
  });
  return V;
}
// 车模型整体换一身热成像的样子：车身浅灰、发动机舱 / 履带 / 车轮发白（热）
export function thermalize(V, hot = 1) {
  V.root.traverse(o => {
    if (!o.isMesh) return;
    const name = (o.name || '') + (o.parent ? o.parent.name : '');
    const isHot = /Wheel|Track|W\d|Engine|Exhaust/i.test(name);
    o.material = new THREE.MeshBasicMaterial({ color: new THREE.Color().setScalar(isHot ? 1.8 * hot : 0.75 * hot) });
  });
  return V;
}

// 车身蒙一层沙土：颜色压暗一点、偏土黄、更哑光（沙漠里的车不会锃亮）
export function dusty(V, k = 0.72) {
  V.root.traverse(o => {
    if (!o.isMesh || !o.material) return;
    const one = m => { m = m.clone(); if (m.color) m.color.multiplyScalar(k).lerp(new THREE.Color(0.42, 0.36, 0.27), 0.12); m.roughness = Math.max(m.roughness ?? 0.6, 0.78); m.envMapIntensity = 0.15; return m; };
    o.material = Array.isArray(o.material) ? o.material.map(one) : one(o.material);
  });
  return V;
}
