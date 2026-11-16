-- 自动生成（tools/weapons/optics.mjs），别手改：瞄准镜、望远镜（Sketchfab 模型原样）的元数据
--   坐标是「器材坐标」：格（1 米 = 2.8 格），+Z 朝前（物镜）、+Y 朝上；瞄准镜原点在镜座底面中心（贴在枪的导轨上），望远镜原点在两个目镜中间
--   parts[块名] = { c 包围盒中心, s 大小, tri 三角形数 }；eye / obj 目镜、物镜的中心 c 和半径 r；eyes 望远镜左右目镜；导入后 MeshPart 叫 O_<键>__<块名>
return {
  atacr = {
    parts = {
      Glass = { c = { -0.004, 0.123, 0.032 }, s = { 0.168, 0.168, 1.103 }, tri = 342 },
      Reticle = { c = { -0.004, 0.123, 0.536 }, s = { 0.127, 0.127, 0 }, tri = 32 },
      Mount = { c = { 0, 0.089, 0 }, s = { 0.144, 0.177, 0.327 }, tri = 3549 },
      Body = { c = { -0.004, 0.145, 0.046 }, s = { 0.227, 0.224, 1.143 }, tri = 6193 },
    },
    eye = { c = { -0.004, 0.123, -0.514 }, r = 0.058 },
    obj = { c = { -0.004, 0.123, 0.573 }, r = 0.084 },
    credit = "狙击镜（Nightforce ATACR 7-35×56 F1，带皮卡汀尼镜座）：Nightforce ATACR 7-35x56 F1，作者 suspensy，CC-BY-4.0 https://sketchfab.com/3d-models/nightforce-atacr-7-35x56-f1-881b1a99ac1c4e3d89c45b4467e738f2",
  },
  binoc = {
    parts = {
      Body = { c = { 0, 0, 0.251 }, s = { 0.463, 0.14, 0.502 }, tri = 4864 },
    },
    credit = "望远镜：binoculars，作者 TORI106，CC-BY-4.0 https://sketchfab.com/3d-models/binoculars-b38216dc4d5248428060d4b854c3d9e5",
  },
}
