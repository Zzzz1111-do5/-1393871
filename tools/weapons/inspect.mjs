// 看一个原模型里有哪些带网格的节点（序号和 optics.mjs 的 keep / drop 一样按遍历顺序）：名字、材质、三角形数、世界包围盒（米）
//   用法：node tools/weapons/inspect.mjs <model.glb> [...]
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
for (const f of process.argv.slice(2)) {
  const doc = await io.read(f);
  const root = doc.getRoot();
  const scene = root.getDefaultScene() || root.listScenes()[0];
  const nodes = [];
  scene.traverse((n) => { if (n.getMesh()) nodes.push(n); });
  console.log(`== ${f}：${nodes.length} 个网格节点`);
  nodes.forEach((n, k) => {
    const M = n.getWorldMatrix();
    const mn = [1e9, 1e9, 1e9], mx = [-1e9, -1e9, -1e9];
    let tri = 0;
    const mats = new Set();
    for (const p of n.getMesh().listPrimitives()) {
      const pos = p.getAttribute('POSITION');
      const e = [0, 0, 0];
      for (let i = 0; i < pos.getCount(); i++) {
        const v = pos.getElement(i, e);
        const w = [M[0] * v[0] + M[4] * v[1] + M[8] * v[2] + M[12], M[1] * v[0] + M[5] * v[1] + M[9] * v[2] + M[13], M[2] * v[0] + M[6] * v[1] + M[10] * v[2] + M[14]];
        for (let q = 0; q < 3; q++) { mn[q] = Math.min(mn[q], w[q]); mx[q] = Math.max(mx[q], w[q]); }
      }
      tri += (p.getIndices() ? p.getIndices().getCount() : pos.getCount()) / 3;
      if (p.getMaterial()) mats.add(p.getMaterial().getName());
    }
    const sz = mx.map((v, q) => (v - mn[q]).toFixed(3));
    const c = mx.map((v, q) => ((v + mn[q]) / 2).toFixed(3));
    console.log(`  [${k}] ${n.getName().slice(0, 40).padEnd(40)} tri ${String(tri).padStart(6)}  中心 ${c.join(',')}  尺寸 ${sz.join('×')}  材质 ${[...mats].join('|').slice(0, 60)}`);
  });
}
