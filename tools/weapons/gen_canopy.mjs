// 战斗机座舱盖玻璃（零件拼的座舱：Defs.jet）——本项目自己生成的光滑曲面，给 Studio「导入 3D」：
//   用户 11-22：「飞机不要搞多边形的座舱盖，一反光看着太难受了，就要弧形」；11-24 晚：「目前飞机驾驶舱玻璃都是多边形 第一人称看非常难受」——
//   游戏里本来用 EditableMesh 现拼一整块光滑网格，可 Studio / 线上没开「Mesh / Image API」时拼不成，退回 144 块玻璃平板，一块一块的棱全看得见。
//   这里把同一个曲面（InteriorDefs.lua Defs.jet 的座舱盖：截面半圆的管子 + 往前收成弹头形的风挡）预先做成网格：
//   圆周 64 段、风挡 16 圈，法线按曲面算（反光是一整片连续的高光），每个三角形正反各一份（座舱里、外面都看得见）。
//   导入后在 ReplicatedStorage.Imported.Optics.ip_canopy（O_ip_canopy__Glass），Interior.lua 的 smoothCanopy 优先用它。
//   坐标（米）同 InteriorDefs 的座舱坐标：X 向右、Y 向上、−Z 朝机头（原点是飞行员眼睛）；optics.json 里 axes x,y,z、scale 2.8 换成格
//   用法：optics.json 的 sources.ip_canopy.gen 指到这个文件（BUILD=ip_canopy node tools/weapons/optics.mjs）；也可以单独跑 node tools/weapons/gen_canopy.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Document, NodeIO } from '@gltf-transform/core';

const HERE = path.dirname(fileURLToPath(import.meta.url));

// 曲面参数：和 InteriorDefs.lua Defs.jet 的座舱盖同一组数（改那边要一起改，Interior 按 spec.canopy.std 认）
export const CANOPY = { R0: 0.52, cy: -0.24, zf: -0.80, zr: 0.57, Lf: 0.30, tube: 4, nose: 16, cols: 64 };

function surface() {
  const { R0, cy, zf, zr, Lf, tube, nose, cols } = CANOPY;
  // 一圈圈截面：管子（从后往前 tube + 1 圈，半径 R0），风挡（t = 0 管口 → 1 尖，z 往前收、半径 cos^0.6）
  const ring = (t) => [zf - Lf * Math.sin(t * Math.PI / 2), R0 * Math.pow(Math.cos(t * Math.PI / 2), 0.6)];
  const rows = [];
  for (let i = 0; i <= tube; i++) rows.push({ z: zr + (zf - zr) * i / tube, r: R0 });
  for (let k = 1; k <= nose; k++) { const [z, r] = ring(k / nose); rows.push({ z, r: Math.max(r, 0.004) }); }
  const P = [], N = [];
  for (let j = 0; j < rows.length; j++) {
    const a0 = rows[Math.max(0, j - 1)], a1 = rows[Math.min(rows.length - 1, j + 1)];
    const dz = a1.z - a0.z;
    const drdz = Math.abs(dz) > 1e-6 ? (a1.r - a0.r) / dz : 0;
    P.push([]); N.push([]);
    for (let i = 0; i <= cols; i++) {
      const a = (-90 + 180 * i / cols) * Math.PI / 180;
      P[j].push([Math.sin(a) * rows[j].r, cy + Math.cos(a) * rows[j].r, rows[j].z]);
      // 回转曲面的法线：径向（sin a, cos a）加上半径沿 z 的变化（风挡往前收：法线往前倾）
      const n = [Math.sin(a), Math.cos(a), -drdz];
      const l = Math.hypot(n[0], n[1], n[2]);
      N[j].push([n[0] / l, n[1] / l, n[2] / l]);
    }
  }
  return { rows, P, N };
}

export async function build(outFile) {
  const { rows, P, N } = surface();
  const pos = [], nor = [], idx = [];
  const vid = (j, i, side) => {
    pos.push(...P[j][i]);
    const n = N[j][i];
    nor.push(side * n[0], side * n[1], side * n[2]);
    return pos.length / 3 - 1;
  };
  const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
  const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
  const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  // 外面一份（叉乘朝外）、里面一份（反着绕、法线朝里）；尖上退化的三角形不要
  const tri = (A, B, C) => {
    const pa = P[A[0]][A[1]], pb = P[B[0]][B[1]], pc = P[C[0]][C[1]];
    const g = cross(sub(pb, pa), sub(pc, pa));
    if (Math.hypot(g[0], g[1], g[2]) < 1e-9) return;
    const nm = [0, 1, 2].map((k) => N[A[0]][A[1]][k] + N[B[0]][B[1]][k] + N[C[0]][C[1]][k]);
    if (dot(g, nm) < 0) [B, C] = [C, B];
    idx.push(vid(...A, 1), vid(...B, 1), vid(...C, 1));
    idx.push(vid(...A, -1), vid(...C, -1), vid(...B, -1));
  };
  for (let j = 0; j < rows.length - 1; j++) {
    for (let i = 0; i < CANOPY.cols; i++) {
      tri([j, i], [j, i + 1], [j + 1, i + 1]);
      tri([j, i], [j + 1, i + 1], [j + 1, i]);
    }
  }
  const doc = new Document();
  const buf = doc.createBuffer();
  const scene = doc.createScene('canopy');
  // 颜色同 InteriorDefs 的 GC（游戏里会按机型重设颜色、透明度、材质）
  const s2l = (c) => { c /= 255; return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
  const mat = doc.createMaterial('glass').setBaseColorFactor([s2l(54), s2l(62), s2l(68), 1]).setMetallicFactor(0).setRoughnessFactor(0.08);
  const prim = doc.createPrimitive()
    .setAttribute('POSITION', doc.createAccessor().setType('VEC3').setArray(new Float32Array(pos)).setBuffer(buf))
    .setAttribute('NORMAL', doc.createAccessor().setType('VEC3').setArray(new Float32Array(nor)).setBuffer(buf))
    .setIndices(doc.createAccessor().setType('SCALAR').setArray(new Uint32Array(idx)).setBuffer(buf))
    .setMaterial(mat);
  scene.addChild(doc.createNode('glass').setMesh(doc.createMesh('glass').addPrimitive(prim)));
  fs.mkdirSync(path.dirname(outFile), { recursive: true });
  await new NodeIO().write(outFile, doc);
  console.log('gen_canopy：写好了', outFile, '三角形', idx.length / 3, '顶点', pos.length / 3);
  return outFile;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await build(process.argv[2] ? path.resolve(process.argv[2]) : path.join(HERE, 'cache/ip_canopy/model.glb'));
}
