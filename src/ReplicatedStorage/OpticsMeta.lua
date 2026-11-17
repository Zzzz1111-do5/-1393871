-- 自动生成（tools/weapons/optics.mjs），别手改：瞄准镜、望远镜（Sketchfab 模型原样）的元数据
--   坐标是「器材坐标」：格（1 米 = 2.8 格），+Z 朝前（物镜）、+Y 朝上；瞄准镜原点在镜座底面中心（贴在枪的导轨上），望远镜原点在两个目镜中间
--   parts[块名] = { c 包围盒中心, s 大小, tri 三角形数, col / met 没贴图的块的颜色、金属度 }；eye / obj 目镜、物镜的中心 c 和半径 r；pts 握把 grip、导轨 rail 等点；size 总尺寸
--   导入后 MeshPart 叫 O_<键>__<块名>
return {
  atacr = {
    parts = {
      Glass = { c = { -0.004, 0.123, 0.032 }, s = { 0.168, 0.168, 1.103 }, tri = 342 },
      Reticle = { c = { -0.004, 0.123, 0.536 }, s = { 0.127, 0.127, 0 }, tri = 32, col = { 231, 231, 231 }, met = 0 },
      Mount = { c = { 0, 0.089, 0 }, s = { 0.144, 0.177, 0.327 }, tri = 3549 },
      Body = { c = { -0.004, 0.145, 0.046 }, s = { 0.227, 0.224, 1.143 }, tri = 6193 },
    },
    eye = { c = { -0.004, 0.123, -0.514 }, r = 0.058 },
    obj = { c = { -0.004, 0.123, 0.573 }, r = 0.084 },
    size = { 0.227, 0.257, 1.143 },
    credit = "狙击镜（Nightforce ATACR 7-35×56 F1，带皮卡汀尼镜座）：Nightforce ATACR 7-35x56 F1，作者 suspensy，CC-BY-4.0 https://sketchfab.com/3d-models/nightforce-atacr-7-35x56-f1-881b1a99ac1c4e3d89c45b4467e738f2",
  },
  binoc = {
    parts = {
      Body = { c = { 0, 0, 0.251 }, s = { 0.463, 0.14, 0.502 }, tri = 4864 },
    },
    size = { 0.463, 0.14, 0.502 },
    credit = "望远镜：binoculars，作者 TORI106，CC-BY-4.0 https://sketchfab.com/3d-models/binoculars-b38216dc4d5248428060d4b854c3d9e5",
  },
  m40a5 = {
    parts = {
      Body = { c = { -0.018, -0.019, -0.236 }, s = { 0.225, 0.243, 1.276 }, tri = 3554 },
      Body2 = { c = { -0.023, 0.022, 0.951 }, s = { 0.181, 0.096, 2.226 }, tri = 7684 },
      Body3 = { c = { -0.084, -0.094, 0 }, s = { 0.282, 0.303, 2.167 }, tri = 2084 },
    },
    pts = { grip = { 0, -0.1401, -0.2801 }, rail = { 0, 0.0924, 0.1121 }, muzzle = { 0, 0.005, 2.06 } },
    size = { 0.32, 0.348, 3.148 },
    credit = "美军狙击枪（USMC M40A5）：USMC M40A5 Sniper，作者 Urpo，CC-BY-4.0 https://sketchfab.com/3d-models/usmc-m40a5-sniper-f724d89f40db46b0afce2b57ac6d4823",
  },
  qbu88 = {
    parts = {
      C333 = { c = { 0.019, -0.041, -0.312 }, s = { 0.114, 0.465, 1.954 }, tri = 1760, col = { 54, 54, 54 }, met = 0 },
      C222 = { c = { 0, 0, 0.001 }, s = { 0.172, 0.706, 2.575 }, tri = 4794, col = { 32, 32, 32 }, met = 0 },
      C444 = { c = { 0.026, 0.082, -0.547 }, s = { 0.093, 0.142, 0.618 }, tri = 70, col = { 63, 61, 61 }, met = 0 },
      C8aa = { c = { 0.019, 0.263, -0.283 }, s = { 0.087, 0.087, 0.736 }, tri = 12, col = { 139, 164, 172 }, met = 0 },
      Ceee = { c = { 0.02, -0.028, -0.749 }, s = { 0.045, 0.059, 0.168 }, tri = 564, col = { 231, 231, 231 }, met = 0 },
    },
    eye = { c = { 0, 0.245, -0.666 }, r = 0.05 },
    obj = { c = { 0, 0.245, 0.104 }, r = 0.057 },
    pts = { grip = { 0, -0.19, -0.42 }, muzzle = { 0, 0, 1.22 } },
    size = { 0.172, 0.706, 2.577 },
    credit = "解放军狙击枪（QBU-88）：Low-Poly QBU-88，作者 TastyTony，CC-BY-4.0 https://sketchfab.com/3d-models/low-poly-qbu-88-123f78f80f16461d97920e84135c0550",
  },
  at4 = {
    parts = {
      Body = { c = { 0, 0, 0 }, s = { 0.484, 0.904, 2.856 }, tri = 8779 },
    },
    pts = { grip = { 0, -0.17, 0.96 }, muzzle = { 0, 0.19, 1.43 } },
    size = { 0.484, 0.904, 2.856 },
    credit = "美军火箭筒（AT4）：Anti-Tank Grenade Launcher | AT4 | GameReady，作者 Pan_Ar4ik，CC-BY-4.0 https://sketchfab.com/3d-models/anti-tank-grenade-launcher-at4-gameready-7ef6e4f3f0af4db8a7d3ccbaf506fd38",
  },
  rpg7 = {
    parts = {
      Body = { c = { 0, 0, 0.428 }, s = { 0.296, 0.601, 3.4 }, tri = 16098 },
    },
    pts = { grip = { 0, -0.19, 0.89 }, muzzle = { 0, 0.05, 2.15 } },
    size = { 0.296, 0.601, 3.4 },
    credit = "解放军火箭筒（RPG-7 / 69 式）：RPG-7，作者 Tactical_Beard，CC-BY-4.0 https://sketchfab.com/3d-models/rpg-7-01c0fa7bb9e0439cac27264b3119a3fd",
  },
  stinger = {
    parts = {
      C675 = { c = { 0.009, -0.129, 0.025 }, s = { 1.27, 0.956, 4.208 }, tri = 1032, col = { 101, 115, 90 }, met = 0 },
      C444 = { c = { -0.003, 0.02, 0 }, s = { 1.282, 1.175, 4.258 }, tri = 1366, col = { 61, 61, 61 }, met = 0 },
      C777 = { c = { 0.029, 0.024, -0.082 }, s = { 1.219, 1.076, 3.539 }, tri = 500, col = { 113, 113, 113 }, met = 0 },
    },
    pts = { grip = { 0, -0.33, -0.36 }, muzzle = { 0, -0.02, 2.13 } },
    size = { 1.288, 1.215, 4.258 },
    credit = "美军单兵防空导弹（FIM-92 毒刺）：FIM-92 Stinger，作者 Mortavex，CC-BY-4.0 https://sketchfab.com/3d-models/fim-92-stinger-d9de43d3b00a4381b991c35369b5e183",
  },
  qw2 = {
    parts = {
      C652 = { c = { 0.013, -0.054, 0.962 }, s = { 0.409, 0.872, 4.308 }, tri = 5308, col = { 98, 86, 31 }, met = 0.303 },
      C666 = { c = { 0.058, 0.044, 0.967 }, s = { 0.186, 0.504, 3.398 }, tri = 1391, col = { 108, 108, 108 }, met = 0 },
      C000 = { c = { 0, 0, 1.003 }, s = { 0.45, 0.832, 4.454 }, tri = 9914, col = { 1, 1, 1 }, met = 0 },
      Ceee = { c = { -0.008, 0.234, -0.51 }, s = { 0.335, 0.265, 0.347 }, tri = 440, col = { 231, 231, 231 }, met = 0 },
      C111 = { c = { -0.056, 0.275, -0.326 }, s = { 0.11, 0.117, 0.931 }, tri = 1354, col = { 22, 22, 22 }, met = 0.376 },
      C777 = { c = { 0.058, -0.173, 0.111 }, s = { 0.035, 0.106, 0.112 }, tri = 168, col = { 121, 121, 121 }, met = 0.285 },
      C555 = { c = { -0.027, -0.133, -0.126 }, s = { 0.039, 0.213, 0.724 }, tri = 1477, col = { 86, 86, 86 }, met = 0.174 },
    },
    pts = { grip = { 0, -0.33, 0.24 }, fpOff = { 0, -0.12, 0 }, muzzle = { 0, 0.18, 3.22 } },
    size = { 0.45, 0.906, 4.454 },
    credit = "解放军单兵防空导弹（前卫-2）：QW-2，作者 会飞的购物清单，CC-BY-4.0 https://sketchfab.com/3d-models/qw-2-b3fce788240740a4b15ab1e2011158ce",
  },
  m67 = {
    parts = {
      Body = { c = { 0, 0, 0 }, s = { 0.165, 0.251, 0.176 }, tri = 5046 },
    },
    pts = { grip = { 0, -0.06, 0 }, fpOff = { 0, 0.06, -0.02 } },
    size = { 0.165, 0.251, 0.176 },
    credit = "手雷（M67）：M67，作者 Firewarden3D，CC-BY-4.0 https://sketchfab.com/3d-models/m67-52dc34ff97984927b0322326e3171467",
  },
  ifak = {
    parts = {
      Body = { c = { 0, 0, 0 }, s = { 0.363, 0.503, 0.328 }, tri = 3632 },
    },
    pts = { grip = { 0, -0.12, 0 }, hold = { -10, 0, 0 } },
    size = { 0.363, 0.503, 0.328 },
    credit = "急救包：Tactical FIRST AID KIT，作者 Ruslan Koschey，CC-BY-4.0 https://sketchfab.com/3d-models/tactical-first-aid-kit-011c33c121284bc88bb765a85511dae1",
  },
  wrench = {
    parts = {
      Body = { c = { 0, 0, 0 }, s = { 0.221, 0.085, 1.01 }, tri = 2642 },
    },
    pts = { grip = { 0, 0, -0.36 }, hold = { 15, 0, 0 } },
    size = { 0.221, 0.085, 1.01 },
    credit = "扳手（管钳）：Weathered Wrench (Game Model)，作者 Michael Makivic，CC-BY-4.0 https://sketchfab.com/3d-models/weathered-wrench-game-model-66b29c557ce04bb0b14bdde2cc204a2f",
  },
  c4 = {
    parts = {
      Body = { c = { 0, 0, 0 }, s = { 0.238, 0.699, 0.446 }, tri = 4589 },
    },
    pts = { grip = { 0, -0.2, 0 }, hold = { 0, 90, 0 } },
    size = { 0.238, 0.699, 0.446 },
    credit = "炸药包（C4）：Simple Old C4，作者 Blender3D，CC-BY-4.0 https://sketchfab.com/3d-models/simple-old-c4-43d3b6a933b04aea8006d790627f9555",
  },
  m224 = {
    parts = {
      Body = { c = { 0, 0, 0 }, s = { 1.71, 2.798, 2.249 }, tri = 15240 },
      Caaa = { c = { -0.006, -1.289, 1 }, s = { 1.262, 0.04, 0.039 }, tri = 6400, col = { 169, 169, 169 }, met = 0 },
    },
    pts = { grip = { 0, 0.5, 0 }, hold = { 22, 0, 0 }, fpOff = { 0.18, -0.3, 0.2 } },
    size = { 1.71, 2.798, 2.249 },
    credit = "迫击炮（M224）：Mortar - M224，作者 Jan Češnjevar，CC-BY-4.0 https://sketchfab.com/3d-models/mortar-m224-c86a73e40d994431bcdb57dc741cf8be",
  },
  acog = {
    parts = {
      Body = { c = { 0.008, 0.078, 0 }, s = { 0.122, 0.155, 0.4 }, tri = 2576, col = { 60, 60, 60 }, met = 0 },
      Mount = { c = { 0.029, 0.02, 0.029 }, s = { 0.012, 0.029, 0.175 }, tri = 36, col = { 42, 42, 42 }, met = 0 },
      Knobs = { c = { 0.045, 0.07, -0.016 }, s = { 0.042, 0.112, 0.218 }, tri = 208, col = { 108, 108, 108 }, met = 0 },
      FiberCover = { c = { -0.011, 0.138, 0.077 }, s = { 0.034, 0.035, 0.243 }, tri = 60, col = { 203, 203, 203 }, met = 0 },
      Fiber = { c = { -0.011, 0.137, 0.073 }, s = { 0.027, 0.029, 0.233 }, tri = 44, col = { 165, 0, 0 }, met = 0 },
      Glass = { c = { 0, 0.098, -0.022 }, s = { 0.065, 0.065, 0.34 }, tri = 56, col = { 239, 239, 239 }, met = 0 },
      Reticle = { c = { 0, 0.087, -0.056 }, s = { 0.005, 0.023, 0 }, tri = 16, col = { 255, 0, 17 }, met = 0 },
    },
    eye = { c = { 0, 0.098, -0.19 }, r = 0.025 },
    obj = { c = { 0, 0.098, 0.145 }, r = 0.032 },
    size = { 0.122, 0.155, 0.4 },
    credit = "步枪瞄准镜（Trijicon ACOG 3.5×35，装在 M4 上机匣导轨上）：Trijicon ACOG 3.5x35 Riflescope (Low-Poly)，作者 GoldbergR，CC-BY-4.0 https://sketchfab.com/3d-models/trijicon-acog-35x35-riflescope-low-poly-374bd6e3054b47cdbeb2eeb7817613d1",
  },
}
