// 看一个 glTF / GLB 里有什么：节点树、每个网格的三角形数、包围盒、材质（透明方式、贴图大小）
// 用法：node tools/scenery/inspect.mjs <模型.glb>
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { getBounds } from '@gltf-transform/core';
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(process.argv[2]);
const root = doc.getRoot();
const scene = root.listScenes()[0];
let n = 0;
function walk(node, depth) {
  const mesh = node.getMesh();
  let tris = 0;
  if (mesh) for (const p of mesh.listPrimitives()) { const idx = p.getIndices(); tris += (idx ? idx.getCount() : p.getAttribute('POSITION').getCount()) / 3; }
  n++;
  if (depth < 4 || mesh) {
    let bb = '';
    try { const b = getBounds(node); bb = `[${b.min.map((v) => v.toFixed(2)).join(',')}] → [${b.max.map((v) => v.toFixed(2)).join(',')}]`; } catch (e) {}
    console.log(`${'  '.repeat(depth)}${node.getName() || '(无名)'}${mesh ? `  △${tris}` : ''}  ${bb}`);
  }
  for (const c of node.listChildren()) walk(c, depth + 1);
}
for (const c of scene.listChildren()) walk(c, 0);
console.log('材质：');
for (const m of root.listMaterials()) {
  const t = m.getBaseColorTexture();
  const sz = t ? t.getSize() : null;
  console.log(`  ${m.getName()}  alpha=${m.getAlphaMode()} cutoff=${m.getAlphaCutoff()} double=${m.getDoubleSided()} base=${sz ? sz.join('x') : '-'} normal=${m.getNormalTexture() ? 'y' : '-'}`);
}
console.log('贴图：');
for (const t of root.listTextures()) console.log(`  ${t.getName() || t.getURI()} ${t.getMimeType()} ${(t.getSize() || []).join('x')} ${Math.round(t.getImage().byteLength / 1024)}KB`);
console.log('扩展：', root.listExtensionsUsed().map((e) => e.extensionName).join(', '));
