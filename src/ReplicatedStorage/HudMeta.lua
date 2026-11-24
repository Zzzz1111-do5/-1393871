-- 自动生成（tools/weapons/hud.mjs），别手改：飞机座舱平显（光学瞄准屏）原模型的元数据
--   原模型：J-15T with YJ-83K（作者 Jeyhun1985，CC-BY-4.0）自带座舱里的平显——两根弧形立柱 + 顶梁、投影仪壳子（Frame），组合玻璃（Glass）
--   平显坐标（米）：原点在组合玻璃的包围盒中心，+X 飞行员看来的右边，+Y 上，+Z 朝飞行员；parts[块名] = { c 中心, s 大小, tri 三角形数 }
--   导入后 MeshPart 叫 O_hud15__<块名>，开服时 Imports.lua 收进 ReplicatedStorage.Imported.Optics.hud15；InteriorDefs 的平显有它就换上
return {
  hud15 = {
    parts = {
      Frame = { c = { 0, -0.0658, -0.0037 }, s = { 0.2824, 0.3192, 0.2479 }, tri = 1398 },
      Glass = { c = { 0, 0, 0 }, s = { 0.2317, 0.1829, 0.2231 }, tri = 76 },
    },
    glass = { w = 0.2317, h = 0.1829, d = 0.2231, tilt = -83.3 },   -- 组合玻璃（米）：包围盒、往飞行员那边仰几度
    credit = "平显（光学瞄准屏）：J-15T with YJ-83K 自带座舱里的平显，作者 Jeyhun1985（https://sketchfab.com/3d-models/b416034f0cde4e46b37cf3e5445bd1b7），CC-BY-4.0 授权（http://creativecommons.org/licenses/by/4.0/）",
  },
}
