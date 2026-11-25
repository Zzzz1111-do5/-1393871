-- 自动生成（tools/weapons/optics.mjs），别手改：瞄准镜、望远镜（Sketchfab 模型原样）的元数据
--   坐标是「器材坐标」：格（1 米 = 2.8 格），+Z 朝前（物镜）、+Y 朝上；瞄准镜原点在镜座底面中心（贴在枪的导轨上），望远镜原点在两个目镜中间
--   parts[块名] = { c 包围盒中心, s 大小, tri 三角形数, col / met 没贴图的块的颜色、金属度 }；eye / obj 目镜、物镜的中心 c 和半径 r；pts 握把 grip、导轨 rail 等点；size 总尺寸；
--   inner 镜筒里面的块（内壁、镜片、分划板：第一人称开镜时藏起来，从目镜的洞里直接看放大的画面）
--   导入后 MeshPart 叫 O_<键>__<块名>
return {
  atacr = {
    parts = {
      Mount = { c = { 0.01, 0.021, 0 }, s = { 0.124, 0.042, 0.327 }, tri = 617 },
      Body = { c = { -0.004, 0.159, -0.235 }, s = { 0.227, 0.196, 0.58 }, tri = 1076 },
      GlassIn = { c = { -0.004, 0.123, 0.032 }, s = { 0.168, 0.168, 1.103 }, tri = 342 },
      ReticleIn = { c = { -0.004, 0.123, 0.536 }, s = { 0.127, 0.127, 0 }, tri = 32, col = { 231, 231, 231 }, met = 0 },
      MountIn = { c = { 0, 0.089, 0 }, s = { 0.144, 0.177, 0.327 }, tri = 2932 },
      BodyIn = { c = { -0.004, 0.143, 0.046 }, s = { 0.227, 0.221, 1.143 }, tri = 5117 },
    },
    eye = { c = { -0.004, 0.123, -0.514 }, r = 0.058 },
    obj = { c = { -0.004, 0.123, 0.573 }, r = 0.084 },
    inner = { "GlassIn", "ReticleIn", "MountIn", "BodyIn" },
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
      C333 = { c = { 0.019, -0.055, -0.312 }, s = { 0.114, 0.436, 1.954 }, tri = 1575, col = { 54, 54, 54 }, met = 0 },
      C222 = { c = { 0, 0, 0.001 }, s = { 0.172, 0.706, 2.575 }, tri = 3191, col = { 32, 32, 32 }, met = 0 },
      C444 = { c = { 0.026, 0.082, -0.547 }, s = { 0.093, 0.142, 0.618 }, tri = 70, col = { 63, 61, 61 }, met = 0 },
      C8aa = { c = { 0.038, 0.282, -0.652 }, s = { 0.037, 0.037, 0 }, tri = 1, col = { 139, 164, 172 }, met = 0 },
      Ceee = { c = { 0.02, -0.028, -0.749 }, s = { 0.045, 0.059, 0.168 }, tri = 564, col = { 231, 231, 231 }, met = 0 },
      C333In = { c = { 0.012, 0.141, 0.166 }, s = { 0.059, 0.103, 0.867 }, tri = 185, col = { 54, 54, 54 }, met = 0 },
      C222In = { c = { 0.002, 0.175, 0.311 }, s = { 0.15, 0.334, 1.955 }, tri = 1603, col = { 32, 32, 32 }, met = 0 },
      C8aaIn = { c = { 0.019, 0.263, -0.283 }, s = { 0.087, 0.087, 0.736 }, tri = 11, col = { 139, 164, 172 }, met = 0 },
    },
    eye = { c = { 0, 0.245, -0.666 }, r = 0.05 },
    obj = { c = { 0, 0.245, 0.104 }, r = 0.057 },
    pts = { grip = { 0, -0.19, -0.42 }, muzzle = { 0, 0, 1.22 } },
    inner = { "C333In", "C222In", "C8aaIn" },
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
      Body = { c = { 0.008, 0.078, -0.042 }, s = { 0.122, 0.155, 0.316 }, tri = 1150, col = { 60, 60, 60 }, met = 0 },
      Mount = { c = { 0.029, 0.02, 0.029 }, s = { 0.012, 0.029, 0.175 }, tri = 36, col = { 42, 42, 42 }, met = 0 },
      Knobs = { c = { 0.046, 0.07, -0.016 }, s = { 0.041, 0.112, 0.218 }, tri = 127, col = { 108, 108, 108 }, met = 0 },
      BodyIn = { c = { -0.003, 0.088, 0.002 }, s = { 0.094, 0.133, 0.396 }, tri = 1426, col = { 60, 60, 60 }, met = 0 },
      KnobsIn = { c = { 0.029, 0.098, -0.113 }, s = { 0.01, 0.055, 0.026 }, tri = 81, col = { 108, 108, 108 }, met = 0 },
      FiberCoverIn = { c = { -0.011, 0.138, 0.077 }, s = { 0.034, 0.035, 0.243 }, tri = 60, col = { 203, 203, 203 }, met = 0 },
      FiberIn = { c = { -0.011, 0.137, 0.073 }, s = { 0.027, 0.029, 0.233 }, tri = 44, col = { 165, 0, 0 }, met = 0 },
      GlassIn = { c = { 0, 0.098, -0.022 }, s = { 0.065, 0.065, 0.34 }, tri = 56, col = { 239, 239, 239 }, met = 0 },
      ReticleIn = { c = { 0, 0.087, -0.056 }, s = { 0.005, 0.023, 0 }, tri = 16, col = { 255, 0, 17 }, met = 0 },
      Eyepiece = { c = { 0, 0.098, -0.189 }, s = { 0.067, 0.067, 0.026 }, tri = 7296, col = { 36, 36, 38 }, met = 0 },
    },
    eye = { c = { 0, 0.098, -0.19 }, r = 0.0216 },
    obj = { c = { 0, 0.098, 0.145 }, r = 0.032 },
    inner = { "BodyIn", "KnobsIn", "FiberCoverIn", "FiberIn", "GlassIn", "ReticleIn" },
    size = { 0.122, 0.155, 0.402 },
    credit = "步枪瞄准镜（Trijicon ACOG 3.5×35，装在 M4 上机匣导轨上）：Trijicon ACOG 3.5x35 Riflescope (Low-Poly)，作者 GoldbergR，CC-BY-4.0 https://sketchfab.com/3d-models/trijicon-acog-35x35-riflescope-low-poly-374bd6e3054b47cdbeb2eeb7817613d1",
  },
  sup_socom = {
    parts = {
      Body = { c = { 0, 0, 0.191 }, s = { 0.085, 0.09, 0.382 }, tri = 1843 },
    },
    size = { 0.085, 0.09, 0.382 },
    credit = "SOCOM 战术消音器：Suppressors 10 Pack，作者 TheWarVet，CC-BY-4.0 https://sketchfab.com/models/3a3c123f94a446589873b1d4df53c83c",
  },
  sup_wrap = {
    parts = {
      Body = { c = { 0, 0, 0.186 }, s = { 0.085, 0.089, 0.372 }, tri = 2111 },
    },
    size = { 0.085, 0.089, 0.372 },
    credit = "裹布消音器：Suppressors 10 Pack，作者 TheWarVet，CC-BY-4.0 https://sketchfab.com/models/3a3c123f94a446589873b1d4df53c83c",
  },
  sup_sr8 = {
    parts = {
      Body = { c = { 0, 0, 0.28 }, s = { 0.08, 0.08, 0.561 }, tri = 704 },
    },
    size = { 0.08, 0.08, 0.561 },
    credit = "SR8 长消音器：Silencers Pack 1，作者 pedrobelthori，CC-BY-4.0 https://sketchfab.com/models/e96a019757a6440390edfef888f0867e",
  },
  muz_comp = {
    parts = {
      C333 = { c = { 0, 0, 0.101 }, s = { 0.074, 0.074, 0.202 }, tri = 456, col = { 50, 50, 50 }, met = 1 },
    },
    size = { 0.074, 0.074, 0.202 },
    credit = "战术补偿器：low-poly Muzzle Device Set，作者 DU1701，CC-BY-4.0 https://sketchfab.com/models/07f62ec5ca604446848d1a0238b11f1d",
  },
  muz_brake = {
    parts = {
      C333 = { c = { 0, 0, 0.091 }, s = { 0.072, 0.072, 0.182 }, tri = 440, col = { 50, 50, 50 }, met = 1 },
    },
    size = { 0.072, 0.072, 0.182 },
    credit = "多孔枪口制退器：low-poly Muzzle Device Set，作者 DU1701，CC-BY-4.0 https://sketchfab.com/models/07f62ec5ca604446848d1a0238b11f1d",
  },
  opt_rds = {
    parts = {
      Body = { c = { 0, 0.149, 0 }, s = { 0.283, 0.298, 0.423 }, tri = 4990 },
      Body2 = { c = { 0.037, 0.153, -0.191 }, s = { 0.138, 0.138, 0.008 }, tri = 96 },
    },
    eye = { c = { 0.037, 0.153, -0.191 }, r = 0.069 },
    size = { 0.283, 0.298, 0.423 },
    credit = "T1 红点瞄具：Generic Red Dot Scope / Rifle Attachment Lowpoly，作者 valterjherson1，CC-BY-4.0 https://sketchfab.com/models/8bf2794c30d04fa0aed1e3df92cd8a9e",
  },
  opt_holo = {
    parts = {
      Body = { c = { 0, 0.107, 0 }, s = { 0.168, 0.213, 0.281 }, tri = 5778 },
      Body2 = { c = { 0.004, 0.156, 0.039 }, s = { 0.106, 0.079, 0.046 }, tri = 36 },
      Body3 = { c = { 0, 0.069, 0.004 }, s = { 0.163, 0.115, 0.271 }, tri = 2661 },
      Body4 = { c = { 0.004, 0.156, 0.04 }, s = { 0.106, 0.079, 0 }, tri = 18 },
    },
    eye = { c = { 0.004, 0.156, 0.016 }, r = 0.053 },
    obj = { c = { 0.004, 0.156, 0.062 }, r = 0.053 },
    size = { 0.168, 0.213, 0.281 },
    credit = "EXPS3 全息瞄具：EoTech EXPS3-0 Holographic Weapon Sight Lowpoly，作者 valterjherson1，CC-BY-4.0 https://sketchfab.com/models/45e4fcdfb1b34756ab9e866564a12f66",
  },
  opt_romeo = {
    parts = {
      Body = { c = { -0.005, 0.063, 0.03 }, s = { 0.053, 0.045, 0.003 }, tri = 195 },
      Body2 = { c = { -0.005, 0.063, 0.037 }, s = { 0.053, 0.045, 0.003 }, tri = 195 },
      C022 = { c = { -0.005, 0.063, 0.031 }, s = { 0.054, 0.045, 0.007 }, tri = 312, col = { 0, 33, 35 }, met = 1 },
      Body3 = { c = { -0.005, 0.063, 0.029 }, s = { 0.053, 0.045, 0.003 }, tri = 195 },
      Body4 = { c = { 0, 0.044, 0 }, s = { 0.069, 0.089, 0.126 }, tri = 2172 },
    },
    obj = { c = { -0.005, 0.063, 0.031 }, r = 0.027 },
    size = { 0.069, 0.089, 0.126 },
    credit = "Romeo3 迷你反射瞄具：Sig Sauer Romeo3 Reflex Sight，作者 ense7en，CC-BY-4.0 https://sketchfab.com/models/a099c1db8ceb457aa5d1a44e967cb941",
  },
  opt_acog6 = {
    parts = {
      C555 = { c = { 0, 0.115, 0.053 }, s = { 0.18, 0.23, 0.474 }, tri = 1833, col = { 77, 77, 77 }, met = 0 },
      Cb22 = { c = { 0, 0.157, -0.221 }, s = { 0.125, 0.069, 0.018 }, tri = 14, col = { 187, 35, 31 }, met = 0 },
      C222 = { c = { 0, 0.105, -0.051 }, s = { 0.148, 0.196, 0.476 }, tri = 350, col = { 34, 34, 34 }, met = 0 },
      C666 = { c = { 0, 0.129, -0.159 }, s = { 0.165, 0.106, 0.052 }, tri = 432, col = { 107, 107, 107 }, met = 0 },
      C9ab = { c = { 0, 0.129, -0.263 }, s = { 0.095, 0.095, 0.013 }, tri = 16, col = { 149, 173, 192 }, met = 0 },
      C555In = { c = { -0.005, 0.14, 0 }, s = { 0.17, 0.179, 0.579 }, tri = 577, col = { 77, 77, 77 }, met = 0 },
      C9abIn = { c = { 0, 0.129, -0.032 }, s = { 0.129, 0.129, 0.475 }, tri = 40, col = { 149, 173, 192 }, met = 0 },
      Cf00In = { c = { 0, 0.128, -0.077 }, s = { 0.002, 0.003, 0 }, tri = 6, col = { 255, 2, 0 }, met = 0 },
      C000In = { c = { 0, 0.116, -0.077 }, s = { 0.047, 0.032, 0 }, tri = 42, col = { 0, 0, 0 }, met = 0 },
      Eyepiece = { c = { 0, 0.129, -0.238 }, s = { 0.151, 0.151, 0.107 }, tri = 7296, col = { 32, 32, 33 }, met = 0 },
    },
    eye = { c = { 0, 0.129, -0.27 }, r = 0.0428 },
    obj = { c = { 0, 0.129, 0.205 }, r = 0.064 },
    inner = { "C555In", "C9abIn", "Cf00In", "C000In" },
    size = { 0.18, 0.23, 0.581 },
    credit = "ACOG 6×48 瞄准镜：Trijicon ACOG 6x48 BAC Riflescope (Low-Poly)，作者 GoldbergR，CC-BY-4.0 https://sketchfab.com/models/d7c2a92ba3dc4b02abe03944fc7600d7",
  },
  grip_rvg = {
    parts = {
      C111 = { c = { -0.002, -0.096, 0 }, s = { 0.076, 0.192, 0.101 }, tri = 462, col = { 14, 14, 14 }, met = 0 },
      C333 = { c = { 0.006, -0.012, 0 }, s = { 0.067, 0.019, 0.042 }, tri = 72, col = { 56, 56, 56 }, met = 0.941 },
    },
    size = { 0.08, 0.192, 0.101 },
    credit = "RVG 垂直握把：Low-Poly Magpul RVG，作者 notcplkerry，CC-BY-4.0 https://sketchfab.com/models/86b3580a65c441db9d3401712c5c9b6d",
  },
  grip_afg = {
    parts = {
      C222 = { c = { 0, -0.071, 0 }, s = { 0.08, 0.143, 0.308 }, tri = 446, col = { 39, 39, 39 }, met = 0 },
      Ceee = { c = { -0.029, -0.02, -0.003 }, s = { 0.002, 0.02, 0.023 }, tri = 18, col = { 233, 233, 233 }, met = 1 },
      C333 = { c = { 0.001, -0.062, -0.004 }, s = { 0.065, 0.107, 0.288 }, tri = 184, col = { 46, 46, 46 }, met = 0.934 },
    },
    size = { 0.08, 0.143, 0.308 },
    credit = "AFG 斜握把：Low-Poly Magpul AFG，作者 notcplkerry，CC-BY-4.0 https://sketchfab.com/models/a92a52cbb5854f7c8e33507f579073f7",
  },
  mag_pmag20 = {
    parts = {
      C111 = { c = { 0, -0.183, 0 }, s = { 0.072, 0.366, 0.206 }, tri = 600, col = { 15, 15, 15 }, met = 0 },
    },
    size = { 0.072, 0.366, 0.206 },
    credit = "PMAG 20 发短弹匣：Low-Poly AR-15 magazines，作者 notcplkerry，CC-BY-4.0 https://sketchfab.com/models/72b06590aa4b4b6ab324dc7e0c11b884",
  },
  mag_hex30 = {
    parts = {
      C987 = { c = { 0, -0.257, 0 }, s = { 0.074, 0.515, 0.232 }, tri = 3012, col = { 158, 138, 124 }, met = 0 },
      Cf61 = { c = { 0, -0.251, -0.01 }, s = { 0.045, 0.493, 0.188 }, tri = 84, col = { 255, 103, 17 }, met = 0 },
    },
    size = { 0.074, 0.515, 0.232 },
    credit = "HEXMAG 30 发弹匣：Low-Poly AR-15 magazines，作者 notcplkerry，CC-BY-4.0 https://sketchfab.com/models/72b06590aa4b4b6ab324dc7e0c11b884",
  },
  mag_pmag40 = {
    parts = {
      C111 = { c = { 0, -0.324, 0 }, s = { 0.072, 0.649, 0.27 }, tri = 1464, col = { 15, 15, 15 }, met = 0 },
    },
    size = { 0.072, 0.649, 0.27 },
    credit = "PMAG 40 发扩容弹匣：Low-Poly AR-15 magazines，作者 notcplkerry，CC-BY-4.0 https://sketchfab.com/models/72b06590aa4b4b6ab324dc7e0c11b884",
  },
  mag_drum = {
    parts = {
      C111 = { c = { 0, -0.271, 0 }, s = { 0.3, 0.541, 0.341 }, tri = 955, col = { 10, 10, 10 }, met = 0 },
      Ca97 = { c = { -0.028, -0.015, -0.033 }, s = { 0.019, 0.019, 0.025 }, tri = 24, col = { 167, 154, 112 }, met = 1 },
    },
    size = { 0.3, 0.541, 0.341 },
    credit = "D-60 弹鼓：Low-Poly AR-15 magazines，作者 notcplkerry，CC-BY-4.0 https://sketchfab.com/models/72b06590aa4b4b6ab324dc7e0c11b884",
  },
  tac_peq = {
    parts = {
      Cca6 = { c = { 0.008, 0.067, -0.004 }, s = { 0.217, 0.119, 0.371 }, tri = 1818, col = { 197, 176, 107 }, met = 0 },
      C333 = { c = { 0.008, 0.063, -0.017 }, s = { 0.227, 0.127, 0.234 }, tri = 676, col = { 56, 56, 56 }, met = 0 },
      C235 = { c = { 0.012, 0.06, 0.152 }, s = { 0.162, 0.048, 0.045 }, tri = 18, col = { 38, 45, 87 }, met = 0 },
      C222 = { c = { 0.008, 0.057, -0.011 }, s = { 0.191, 0.091, 0.27 }, tri = 220, col = { 34, 34, 34 }, met = 0 },
      C666 = { c = { -0.098, 0.08, -0.127 }, s = { 0.009, 0.016, 0.016 }, tri = 60, col = { 107, 107, 107 }, met = 0 },
      Cdc4 = { c = { 0, 0.063, 0.002 }, s = { 0.242, 0.119, 0.375 }, tri = 1426, col = { 229, 203, 60 }, met = 0 },
      C36b = { c = { -0.098, 0.08, -0.108 }, s = { 0.009, 0.016, 0.016 }, tri = 60, col = { 50, 95, 179 }, met = 0 },
    },
    size = { 0.243, 0.127, 0.379 },
    credit = "AN/PEQ-15 激光指示器：ATPIAL AN/PEQ-15 (Low-Poly)，作者 GoldbergR，CC-BY-4.0 https://sketchfab.com/models/3758001408b0404592e7e80e7d5b3072",
  },
  tac_light = {
    parts = {
      Cfff = { c = { 0, 0.066, 0 }, s = { 0.116, 0.132, 0.378 }, tri = 2850, col = { 255, 255, 255 }, met = 1 },
    },
    size = { 0.116, 0.132, 0.378 },
    credit = "M952V 战术手电：Surefire M952V Weapon Light，作者 RedRogueXIII，CC-BY-4.0 https://sketchfab.com/models/208f42ab474b40f08453ee8df016a8e6",
  },
  ip_radio = {
    parts = {
      Body = { c = { -0.001, 0.319, 0 }, s = { 1.174, 0.636, 1.373 }, tri = 8541 },
    },
    size = { 1.174, 0.636, 1.373 },
    credit = "车内饰：车载电台（现代数字电台，带安装架、手持话筒）：Military Radio，作者 curichenkow，CC-BY-4.0 https://sketchfab.com/3d-models/military-radio-f5c8f0420f054b32a2e977fbcd248d84",
  },
  ip_radio2 = {
    parts = {
      Body = { c = { 0, 0.138, 0 }, s = { 0.757, 0.277, 0.82 }, tri = 8548 },
    },
    size = { 0.757, 0.277, 0.82 },
    credit = "车内饰：车载电台（老式箱体）：Military Radio - Low Poly，作者 Camille Barral，CC-BY-4.0 https://sketchfab.com/3d-models/military-radio-low-poly-6647f257eb384c108ecf440bb161d91a",
  },
  ip_m829 = {
    parts = {
      Caec = { c = { -0.001, 0, 1.418 }, s = { 0.291, 0.289, 0.415 }, tri = 100, col = { 170, 231, 203 }, met = 0 },
      Cfaa = { c = { 0, 0.003, 0.96 }, s = { 0.048, 0.049, 0.068 }, tri = 13, col = { 255, 170, 170 }, met = 0 },
      C999 = { c = { 0, 0, 2.365 }, s = { 0.086, 0.086, 0.195 }, tri = 636, col = { 158, 158, 158 }, met = 0.15 },
      Caa7 = { c = { 0, 0, 0.017 }, s = { 0.067, 0.067, 0.028 }, tri = 60, col = { 170, 170, 124 }, met = 0 },
      Ccb6 = { c = { 0.002, 0.002, 0.792 }, s = { 0.468, 0.477, 1.584 }, tri = 982, col = { 203, 179, 108 }, met = 1 },
      C000 = { c = { -0.001, 0, 1.144 }, s = { 0.441, 0.443, 1.97 }, tri = 1274, col = { 0, 0, 0 }, met = 0 },
      Cbbb = { c = { 0, 0, 1.309 }, s = { 0.425, 0.431, 2.531 }, tri = 2150, col = { 189, 189, 189 }, met = 0.17 },
      Ceee = { c = { 0, 0, 1.307 }, s = { 0.335, 0.34, 0.763 }, tri = 52, col = { 237, 237, 237 }, met = 0.17 },
      Cddd = { c = { 0, 0, 0.602 }, s = { 0.195, 0.223, 1.204 }, tri = 466, col = { 215, 215, 215 }, met = 0.15 },
    },
    size = { 0.468, 0.477, 2.575 },
    credit = "车内饰：120 毫米 M829A1 尾翼稳定脱壳穿甲弹（整发，装填手手上那一发）：M829A1 OBJ，作者 Jeyhun1985，CC-BY-4.0 https://sketchfab.com/3d-models/m829a1-obj-08c469c62c4e4a2794fd6135ff674b30",
  },
  ip_m829lo = {
    parts = {
      Caec = { c = { 0.016, -0.025, 1.418 }, s = { 0.223, 0.239, 0.415 }, tri = 28, col = { 170, 231, 203 }, met = 0 },
      Cfaa = { c = { -0.002, 0.003, 0.96 }, s = { 0.051, 0.049, 0.068 }, tri = 13, col = { 255, 170, 170 }, met = 0 },
      C999 = { c = { 0, 0, 2.365 }, s = { 0.086, 0.086, 0.195 }, tri = 148, col = { 158, 158, 158 }, met = 0.15 },
      Caa7 = { c = { 0, 0, 0.017 }, s = { 0.067, 0.067, 0.028 }, tri = 52, col = { 170, 170, 124 }, met = 0 },
      Ccb6 = { c = { -0.007, 0, 0.789 }, s = { 0.457, 0.471, 1.573 }, tri = 223, col = { 203, 179, 108 }, met = 1 },
      C000 = { c = { -0.001, 0.004, 1.144 }, s = { 0.441, 0.436, 1.97 }, tri = 297, col = { 0, 0, 0 }, met = 0 },
      Cbbb = { c = { 0, 0, 1.407 }, s = { 0.425, 0.431, 2.334 }, tri = 501, col = { 189, 189, 189 }, met = 0.17 },
      Ceee = { c = { 0, -0.02, 1.582 }, s = { 0.335, 0.3, 0.213 }, tri = 10, col = { 237, 237, 237 }, met = 0.17 },
      Cddd = { c = { 0, 0, 0.602 }, s = { 0.195, 0.223, 1.204 }, tri = 108, col = { 215, 215, 215 }, met = 0.15 },
    },
    size = { 0.457, 0.471, 2.574 },
    credit = "车内饰：120 毫米 M829A1（尾舱弹架里那 36 发，减面版）：M829A1 OBJ，作者 Jeyhun1985，CC-BY-4.0 https://sketchfab.com/3d-models/m829a1-obj-08c469c62c4e4a2794fd6135ff674b30",
  },
  ip_r125 = {
    parts = {
      Body = { c = { 0, 0, 1.044 }, s = { 0.358, 0.359, 2.089 }, tri = 2848 },
    },
    size = { 0.358, 0.359, 2.089 },
    credit = "车内饰：125 毫米 3BK18 破甲弹弹丸（转盘装弹机）：Tank ammo HEAT 3BK18，作者 VladIG_CG，CC-BY-4.0 https://sketchfab.com/3d-models/tank-ammo-heat-3bk18-98087179c6ae4a63a09d017d87945888",
  },
  ip_he125 = {
    parts = {
      Cbbb = { c = { 0, 0, 0.85 }, s = { 0.351, 0.351, 1.7 }, tri = 1217, col = { 181, 181, 181 }, met = 0 },
      C575 = { c = { -0.002, 0, 0.224 }, s = { 0.342, 0.353, 0.369 }, tri = 468, col = { 90, 125, 89 }, met = 0 },
      C888 = { c = { 0, 0, 0.343 }, s = { 0.351, 0.351, 0.498 }, tri = 471, col = { 132, 132, 132 }, met = 0 },
      C997 = { c = { 0, 0, 1.787 }, s = { 0.141, 0.141, 0.175 }, tri = 256, col = { 147, 145, 113 }, met = 0 },
      Ca52 = { c = { 0, 0, 0.453 }, s = { 0.351, 0.351, 0.879 }, tri = 434, col = { 175, 86, 39 }, met = 0 },
    },
    size = { 0.351, 0.353, 1.874 },
    credit = "车内饰：125 毫米杀爆弹弹丸（转盘装弹机）：HE shell 125mm，作者 dichevk，CC-BY-4.0 https://sketchfab.com/3d-models/he-shell-125mm-61532bea91314025b5d3a5eaa63d389b",
  },
  ip_chg125 = {
    parts = {
      Ca62 = { c = { 0, 0, 0.8 }, s = { 0.435, 0.435, 0.745 }, tri = 354, col = { 167, 104, 41 }, met = 0 },
      C888 = { c = { 0, 0, 0.214 }, s = { 0.464, 0.464, 0.427 }, tri = 2494, col = { 140, 140, 140 }, met = 0 },
    },
    size = { 0.464, 0.464, 1.172 },
    credit = "车内饰：125 毫米发射药筒（转盘装弹机）：GunPowder shell 125mm，作者 dichevk，CC-BY-4.0 https://sketchfab.com/3d-models/gunpowder-shell-125mm-ffeec6c6b381415fbf001a3e3dea2004",
  },
  ip_ext = {
    parts = {
      Body = { c = { 0, 0.839, 0 }, s = { 1.281, 1.679, 0.487 }, tri = 3278 },
    },
    size = { 1.281, 1.679, 0.487 },
    credit = "车内饰：二氧化碳手提灭火瓶：Fire Extinguisher，作者 Sir Erdees，CC-BY-4.0 https://sketchfab.com/3d-models/fire-extinguisher-0253bc18de06471e8413ad24ea49ce92",
  },
  ip_cvc = {
    parts = {
      Body = { c = { 0, 0, 0 }, s = { 0.825, 0.852, 0.919 }, tri = 7599 },
    },
    size = { 0.825, 0.852, 0.919 },
    credit = "车内饰：美军坦克乘员头盔（CVC）：Combat Vehicle Crewman (CVC) Helmet, Vietnam Era，作者 olmopotums，CC-BY-4.0 https://sketchfab.com/3d-models/combat-vehicle-crewman-cvc-helmet-vietnam-era-c1516dc3d0ea420b9246334a94e5681e",
  },
  ip_tsh = {
    parts = {
      Body = { c = { 0, -0.001, 0 }, s = { 0.606, 0.923, 0.775 }, tri = 7600 },
    },
    size = { 0.606, 0.923, 0.775 },
    credit = "车内饰：坦克乘员皮帽（带耳机）：Tank Helmet，作者 denj666，CC-BY-4.0 https://sketchfab.com/3d-models/tank-helmet-e0a6ed324a514c57bc05ffd365ac0eb0",
  },
  ip_cdu = {
    parts = {
      Body = { c = { 0, -0.119, -0.108 }, s = { 0.448, 0.671, 0.225 }, tri = 4739 },
      Body2 = { c = { 0, 0, 0 }, s = { 0.24, 0.348, 0.001 }, tri = 16 },
    },
    size = { 0.448, 0.671, 0.225 },
    credit = "车内饰：带边键的显示控制单元（车长热像仪显示器 CITV、炮长控制显示面板 GCDP）：Aircraft instrument/module thingy，作者 LuddePudde，CC-BY-4.0 https://sketchfab.com/3d-models/aircraft-instrumentmodule-thingy-797da922b1724a2fbdcf5b6379525b49",
  },
  ip_tab = {
    parts = {
      Body = { c = { 0, -0.049, 0 }, s = { 0.846, 0.527, 0.19 }, tri = 5151 },
    },
    size = { 0.846, 0.527, 0.19 },
    credit = "车内饰：车长战术显示器（JBC-P 加固显示终端）：Rugged Sci-Fi Tactical Military Tablet，作者 3DMOAN，CC-BY-4.0 https://sketchfab.com/3d-models/rugged-sci-fi-tactical-military-tablet-f7d8e3c008e24e0c9b32748b3d6105f1",
  },
  ip_mon = {
    parts = {
      Body = { c = { 0, 0, 0 }, s = { 0.561, 0.416, 0.18 }, tri = 3708 },
    },
    size = { 0.561, 0.416, 0.18 },
    credit = "车内饰：带侧键的显示器（CROWS 遥控武器站显示器）：Computer Box Monitor，作者 SUrusso613，CC-BY-4.0 https://sketchfab.com/3d-models/computer-box-monitor-894a096d447e4dcaa8869f4c01917f6a",
  },
  ip_yoke = {
    parts = {
      C222 = { c = { 0.002, 0.022, -0.093 }, s = { 0.979, 0.593, 0.456 }, tri = 4654, col = { 37, 37, 37 }, met = 0.678 },
    },
    size = { 0.979, 0.593, 0.456 },
    credit = "车内饰：炮长双握把（凯迪拉克）：ANIMATED KC-135 YOKE，作者 StratoArt，CC-BY-4.0 https://sketchfab.com/3d-models/animated-kc-135-yoke-2d96da0d802746fcb30044bfba87e968",
  },
  ip_stick = {
    parts = {
      Ce10 = { c = { -0.035, 0.501, -0.012 }, s = { 0.079, 0.359, 0.143 }, tri = 289, col = { 231, 11, 0 }, met = 0.954 },
      C000 = { c = { 0, 0.346, 0 }, s = { 0.183, 0.693, 0.225 }, tri = 1807, col = { 0, 0, 0 }, met = 0.558 },
      Ceee = { c = { -0.025, 0.557, -0.007 }, s = { 0.118, 0.279, 0.146 }, tri = 363, col = { 231, 231, 231 }, met = 0.926 },
      C222 = { c = { 0.006, 0.674, 0.014 }, s = { 0.061, 0.052, 0.046 }, tri = 1338, col = { 39, 39, 39 }, met = 0.265 },
    },
    size = { 0.183, 0.701, 0.225 },
    credit = "车内饰：车长操纵握把 CCH：B-8 Fighter Control Stick (Low Poly)，作者 StratoArt，CC-BY-4.0 https://sketchfab.com/3d-models/b-8-fighter-control-stick-low-poly-8d85a47465c94c629c9e6cc60f9106d0",
  },
  ip_asq = {
    parts = {
      Body = { c = { 0, 0.765, 0.001 }, s = { 0.741, 1.529, 1.144 }, tri = 7599 },
    },
    size = { 0.741, 1.529, 1.144 },
    credit = "车内饰：火控计算机（带操纵杆、键盘）：ASQ-155 Ballistic Computer，作者 TwilightFox，CC-BY-4.0 https://sketchfab.com/3d-models/asq-155-ballistic-computer-b8d6bd36d6a446038931b76374a835e7",
  },
  ip_asq2 = {
    parts = {
      Body = { c = { 0, 0.629, 0.001 }, s = { 0.741, 1.258, 1.144 }, tri = 7071 },
    },
    size = { 0.741, 1.258, 1.144 },
    credit = "车内饰：弹道计算机的机箱（去掉原来的操纵杆，上面装 B-8 握杆）——车长操纵握把底下的白色电子箱：ASQ-155 Ballistic Computer，作者 TwilightFox，CC-BY-4.0 https://sketchfab.com/3d-models/asq-155-ballistic-computer-b8d6bd36d6a446038931b76374a835e7",
  },
  ip_sw = {
    parts = {
      Body = { c = { 0, 0, -0.008 }, s = { 0.249, 0.411, 0.011 }, tri = 94 },
      Body2 = { c = { 0, 0.134, -0.008 }, s = { 0.039, 0.062, 0 }, tri = 14 },
      Caaa = { c = { 0, 0.134, -0.009 }, s = { 0.04, 0.063, 0.007 }, tri = 14, col = { 173, 173, 173 }, met = 0 },
      Body3 = { c = { 0, 0, -0.035 }, s = { 0.249, 0.411, 0.045 }, tri = 140 },
      Body4 = { c = { 0, 0.134, -0.013 }, s = { 0.045, 0.073, 0.006 }, tri = 8 },
      Body5 = { c = { 0, 0, -0.006 }, s = { 0.251, 0.413, 0.014 }, tri = 281 },
      Body6 = { c = { -0.001, 0.008, -0.006 }, s = { 0.197, 0.334, 0.018 }, tri = 217 },
      Body7 = { c = { 0, -0.049, 0.006 }, s = { 0.195, 0.262, 0.104 }, tri = 576 },
      Body8 = { c = { 0, -0.049, 0.003 }, s = { 0.194, 0.232, 0.1 }, tri = 5312 },
    },
    size = { 0.251, 0.413, 0.115 },
    credit = "车内饰：拨动开关面板（带护盖）：Industrial Switches Apollo Command Module，作者 ntilted，CC-BY-4.0 https://sketchfab.com/3d-models/industrial-switches-apollo-command-module-b01232380685412a8485c5dd3be4265a",
  },
  ip_lamp = {
    parts = {
      Body = { c = { 0, 0, 0.076 }, s = { 0.274, 0.449, 0.152 }, tri = 180 },
      Body2 = { c = { 0.001, 0, 0.078 }, s = { 0.236, 0.419, 0.13 }, tri = 52, col = { 255, 221, 116 }, met = 0 },
    },
    size = { 0.274, 0.449, 0.152 },
    credit = "车内饰：车内顶灯（防爆壁灯）：Industrial Bulkhead Wall Lamp Lowpoly，作者 iwanPlays，CC-BY-4.0 https://sketchfab.com/3d-models/industrial-bulkhead-wall-lamp-lowpoly-4c50439bcbc247629fe2194862d7acc9",
  },
  ip_can = {
    parts = {
      Body = { c = { 0, 0.302, 0 }, s = { 0.854, 0.596, 0.454 }, tri = 2375 },
    },
    size = { 0.854, 0.596, 0.454 },
    credit = "车内饰：弹药箱（12.7 毫米 M2A1 弹箱）：Ammuntion box，作者 jaiharitheking，CC-BY-4.0 https://sketchfab.com/3d-models/ammuntion-box-6fb5bbb064b649cc92780fad0036db9c",
  },
  ip_canopy = {
    parts = {
      Glass = { c = { 0, 0.056, -0.742 }, s = { 2.912, 1.456, 4.676 }, tri = 5120, col = { 54, 62, 68 }, met = 0 },
    },
    size = { 2.912, 1.456, 4.676 },
  },
  ip_cdus = {
    parts = {
      Housing = { c = { 0, 0, -0.105 }, s = { 1.148, 1.316, 0.21 }, tri = 216, col = { 44, 48, 66 }, met = 0.05 },
      Bezel = { c = { -0.041, 0.049, 0.017 }, s = { 0.876, 1.207, 0.034 }, tri = 432, col = { 170, 172, 180 }, met = 0.35 },
      Glass = { c = { -0.036, 0.04, 0.01 }, s = { 0.745, 1.144, 0 }, tri = 72, col = { 7, 8, 10 }, met = 0.05 },
      Wells = { c = { -0.021, 0.001, 0.002 }, s = { 1.106, 1.287, 0.004 }, tri = 420, col = { 27, 29, 38 }, met = 0.05 },
      LedStrip = { c = { 0.44, 0.364, 0.004 }, s = { 0.067, 0.42, 0.008 }, tri = 60, col = { 20, 22, 28 }, met = 0.05 },
      Handles = { c = { -0.012, 0.052, 0.049 }, s = { 1.113, 1.044, 0.05 }, tri = 168, col = { 92, 96, 106 }, met = 0.35 },
      Posts = { c = { -0.017, 0.058, 0.031 }, s = { 1.126, 1.061, 0.062 }, tri = 336, col = { 60, 62, 70 }, met = 0.05 },
    },
    size = { 1.154, 1.316, 0.284 },
  },
  ip_peri = {
    parts = {
      Body = { c = { -0.023, 0.004, -0.082 }, s = { 0.791, 0.398, 0.274 }, tri = 1995 },
    },
    size = { 0.791, 0.398, 0.274 },
    credit = "车内饰：坦克潜望镜（车里看得见的下半截）：FV105 Sultan periscop，作者 renalds_rs，CC-BY-4.0 https://sketchfab.com/3d-models/fv105-sultan-periscop-52c930bb607f4ae69aab580992e7449e",
  },
  ip_dseat = {
    parts = {
      Body = { c = { 0.029, 0.908, 0.439 }, s = { 1.458, 2.545, 1.662 }, tri = 4000 },
    },
    size = { 1.458, 2.545, 1.662 },
    credit = "车内饰：驾驶员座椅（坐垫 + 靠背 + 头枕，乘员朝 −Z，原点在坐垫顶面中心）：Driver seat \"Pilot\" with air suspension.，作者 dewolfepilot，CC-BY-4.0 https://sketchfab.com/3d-models/driver-seat-pilot-with-air-suspension-b6cd4493fff547af8a87316952a51e82",
  },
  ip_swheel = {
    parts = {
      C222 = { c = { 0, 0, -0.39 }, s = { 1.12, 1.121, 0.857 }, tri = 2998, col = { 39, 39, 39 }, met = 0 },
    },
    size = { 1.12, 1.121, 0.857 },
    credit = "车内饰：方向盘（盘面朝 +Z 对着驾驶员，原点在轮缘中心，直径 0.40 米）：car bus truck steering wheel interior control，作者 kopofx，CC-BY-4.0 https://sketchfab.com/3d-models/car-bus-truck-steering-wheel-interior-control-bd3d964b2ba8425197ef1a76acf131f3",
  },
  ip_lever = {
    parts = {
      C000 = { c = { 0, 0.7, 0 }, s = { 0.393, 1.401, 0.393 }, tri = 2368, col = { 0, 0, 0 }, met = 0 },
      C222 = { c = { -0.021, 0.762, 0.001 }, s = { 0.208, 0.984, 0.241 }, tri = 1630, col = { 37, 37, 37 }, met = 0.506 },
    },
    size = { 0.393, 1.401, 0.393 },
    credit = "车内饰：操纵杆 / 换挡杆（原点在底座中心，高 0.50 米）：Classic Shift Lever，作者 kryoxshade，CC-BY-4.0 https://sketchfab.com/3d-models/classic-shift-lever-ed7ce8e75f9f44dc9a60a499c7fdaf0b",
  },
  ip_gauges = {
    parts = {
      Ceee = { c = { 0, 0, 0.024 }, s = { 0.728, 0.508, 0.024 }, tri = 2172, col = { 231, 231, 231 }, met = 1 },
      Body = { c = { -0.009, 0.109, 0.036 }, s = { 0.267, 0.268, 0 }, tri = 4 },
      C999 = { c = { 0, -0.001, 0.011 }, s = { 0.711, 0.489, 0.022 }, tri = 3809, col = { 150, 150, 150 }, met = 1 },
      Body2 = { c = { 0.25, -0.14, 0.036 }, s = { 0.201, 0.201, 0 }, tri = 4 },
      Body3 = { c = { -0.255, -0.137, 0.036 }, s = { 0.208, 0.202, 0 }, tri = 4 },
    },
    size = { 0.728, 0.508, 0.036 },
    credit = "车内饰：指针式仪表三块（表盘朝 +Z，原点在背面中心）：Dashboard Gauges，作者 kryoxshade，CC-BY-4.0 https://sketchfab.com/3d-models/dashboard-gauges-05288d08679d4cb195217a3477ae10ad",
  },
  ip_pedals = {
    parts = {
      Cbbb = { c = { 0, 0.347, -0.571 }, s = { 0.896, 0.695, 1.101 }, tri = 2451, col = { 188, 188, 188 }, met = 1 },
      C222 = { c = { -0.003, 0.313, -0.212 }, s = { 0.901, 0.499, 0.428 }, tri = 1545, col = { 38, 38, 38 }, met = 0 },
    },
    size = { 0.902, 0.695, 1.124 },
    credit = "车内饰：刹车、油门踏板（踏板面朝 +Z 对着驾驶员，原点在踏板底边中点）：Pedals Sets，作者 kryoxshade，CC-BY-4.0 https://sketchfab.com/3d-models/pedals-sets-aed5b969daad4f2086468869b06a4f84",
  },
  ip_grip = {
    parts = {
      Body = { c = { 0, 0.178, 0 }, s = { 0.144, 0.355, 0.216 }, tri = 812 },
    },
    size = { 0.144, 0.355, 0.216 },
    credit = "车内饰：操纵握把（扳机朝 −Z，原点在握把底面中心，高 0.13 米）：F-4 Phantom II Flight Stick (Joystick)-Low Poly，作者 alpertheronin，CC-BY-4.0 https://sketchfab.com/3d-models/f-4-phantom-ii-flight-stick-joystick-low-poly-b53fdc25c8cc43aba8fdf6c40bb709e3",
  },
  qbz191 = {
    parts = {
      Body = { c = { -0.014, -0.182, -0.07 }, s = { 0.09, 0.591, 0.382 }, tri = 1808 },
      Body2 = { c = { 0, 0.143, 0 }, s = { 0.203, 0.669, 2.465 }, tri = 18049 },
    },
    pts = { grip = { 0, -0.02, -0.62 }, rail = { 0, 0.35, -0.1 }, muzzle = { 0, 0.245, 1.23 }, sightR = { 0, 0.43, -0.59 }, sightF = { 0, 0.44, 0.54 } },
    size = { 0.203, 0.955, 2.465 },
    credit = "解放军步枪（QBZ-191）：QBZ-191 - Free，作者 Brahian_s_g，CC-BY-4.0 https://sketchfab.com/3d-models/qbz-191-free-88786970cb164adaad127a91a29b3dd8",
  },
  qjy88 = {
    parts = {
      C222 = { c = { 0, 0, 0.423 }, s = { 0.469, 0.539, 2.543 }, tri = 4590, col = { 29, 29, 29 }, met = 0.425 },
      C333 = { c = { -0.141, -0.158, -0.032 }, s = { 0.695, 0.749, 1.617 }, tri = 2957, col = { 45, 45, 45 }, met = 0 },
      C000 = { c = { -0.073, 0.055, 0.003 }, s = { 0.139, 0.318, 1.672 }, tri = 2642, col = { 0, 0, 0 }, met = 0 },
      C444 = { c = { -0.068, -0.101, -1.042 }, s = { 0.097, 0.445, 0.967 }, tri = 514, col = { 65, 65, 65 }, met = 0.223 },
      C111 = { c = { 0.033, -0.056, 0.152 }, s = { 0.351, 0.331, 0.946 }, tri = 1686, col = { 22, 22, 22 }, met = 0 },
      Ce81 = { c = { 0.064, -0.056, -0.271 }, s = { 0.289, 0.331, 0.132 }, tri = 10342, col = { 231, 134, 18 }, met = 0.505 },
      C555 = { c = { -0.068, -0.092, -0.543 }, s = { 0.028, 0.069, 0.031 }, tri = 48, col = { 78, 78, 78 }, met = 0 },
    },
    pts = { grip = { 0, -0.215, -0.73 }, rail = { 0, 0.13, -0.3 }, muzzle = { 0, 0.05, 1.66 }, sightR = { 0, 0.18, -0.565 }, sightF = { 0, 0.2, 1.47 } },
    size = { 0.723, 0.802, 3.22 },
    credit = "解放军通用机枪（QJY-88）：QJY88，作者 flyinglist1，CC-BY-4.0 https://sketchfab.com/3d-models/qjy88-f3d6595f4b954ce48d9441590b64fb3e",
  },
  qcw05 = {
    parts = {
      C444 = { c = { 0, 0, 0.016 }, s = { 0.195, 0.952, 1.65 }, tri = 3146, col = { 76, 76, 76 }, met = 0 },
      C333 = { c = { -0.027, 0.069, -0.354 }, s = { 0.13, 0.722, 0.973 }, tri = 666, col = { 57, 57, 57 }, met = 0 },
      Ceee = { c = { -0.025, 0.149, -0.274 }, s = { 0.047, 0.094, 0.098 }, tri = 528, col = { 231, 231, 231 }, met = 0 },
      C555 = { c = { -0.025, 0.261, 0.165 }, s = { 0.11, 0.346, 1.112 }, tri = 192, col = { 85, 85, 85 }, met = 0 },
      C777 = { c = { -0.019, 0.222, 0.009 }, s = { 0.061, 0.093, 0.824 }, tri = 140, col = { 111, 111, 111 }, met = 0 },
    },
    pts = { grip = { 0, -0.12, 0.05 }, rail = { 0, 0.3, 0.2 }, muzzle = { 0, 0.215, 0.87 }, sightR = { 0, 0.415, 0.06 }, sightF = { 0, 0.425, 0.57 } },
    size = { 0.195, 0.952, 1.682 },
    credit = "解放军冲锋枪（QCW-05）：Low-Poly QCW-05 JS，作者 TastyTony，CC-BY-4.0 https://sketchfab.com/3d-models/low-poly-qcw-05-js-0418d46e15d941d1a89f84d639ee118d",
  },
  qbs09 = {
    parts = {
      C444 = { c = { 0.034, 0.053, 0.004 }, s = { 0.126, 0.548, 2.965 }, tri = 910, col = { 74, 73, 73 }, met = 0 },
      C555 = { c = { -0.002, 0.153, 0.016 }, s = { 0.19, 0.312, 2.905 }, tri = 1190, col = { 87, 86, 86 }, met = 0 },
      C888 = { c = { 0.028, 0.079, -0.115 }, s = { 0.104, 0.289, 0.499 }, tri = 284, col = { 133, 133, 133 }, met = 0 },
      C333 = { c = { 0.034, -0.048, -0.306 }, s = { 0.121, 0.558, 2.362 }, tri = 3822, col = { 59, 59, 59 }, met = 0 },
      Ceee = { c = { 0.034, 0.295, -0.529 }, s = { 0.034, 0.007, 0.003 }, tri = 40, col = { 231, 231, 231 }, met = 0 },
    },
    pts = { grip = { 0, -0.15, -0.5 }, rail = { 0, 0.225, -0.13 }, muzzle = { 0, 0.17, 1.46 }, sightR = { 0, 0.275, -0.55 }, sightF = { 0, 0.285, 0.87 } },
    size = { 0.194, 0.654, 2.974 },
    credit = "解放军霰弹枪（QBS-09）：Low-Poly QBS-09，作者 TastyTony，CC-BY-4.0 https://sketchfab.com/3d-models/low-poly-qbs-09-e13ccd2227c64edbb4f611fc52ab6325",
  },
  qsz92 = {
    parts = {
      C555 = { c = { 0, 0, 0.005 }, s = { 0.071, 0.363, 0.514 }, tri = 1698, col = { 78, 78, 78 }, met = 0 },
      C876 = { c = { -0.005, 0.101, -0.155 }, s = { 0.01, 0.043, 0.01 }, tri = 48, col = { 128, 124, 110 }, met = 0 },
      C765 = { c = { -0.005, 0.101, -0.084 }, s = { 0.017, 0.052, 0.04 }, tri = 120, col = { 116, 103, 79 }, met = 0 },
      C544 = { c = { -0.005, 0.101, -0.128 }, s = { 0.02, 0.056, 0.064 }, tri = 396, col = { 88, 75, 75 }, met = 0 },
      C666 = { c = { -0.004, 0.136, -0.001 }, s = { 0.046, 0.046, 0.08 }, tri = 28, col = { 102, 102, 102 }, met = 0 },
      Cbbb = { c = { -0.004, 0.173, 0.017 }, s = { 0.026, 0.014, 0.428 }, tri = 60, col = { 186, 186, 186 }, met = 0 },
      C777 = { c = { -0.004, 0.134, 0.111 }, s = { 0.026, 0.034, 0.308 }, tri = 72, col = { 120, 120, 120 }, met = 0 },
      C444 = { c = { -0.004, -0.031, -0.003 }, s = { 0.059, 0.293, 0.525 }, tri = 940, col = { 60, 60, 60 }, met = 0 },
    },
    pts = { grip = { 0, -0.07, -0.165 }, muzzle = { 0, 0.115, 0.26 }, sightR = { 0, 0.172, -0.188 }, sightF = { 0, 0.174, 0.228 } },
    size = { 0.071, 0.363, 0.531 },
    credit = "解放军手枪（QSZ-92）：Low-Poly QSZ-92，作者 TastyTony，CC-BY-4.0 https://sketchfab.com/3d-models/low-poly-qsz-92-6e8275a366454ad2ad370620412b5075",
  },
  m249 = {
    parts = {
      Body = { c = { 0.028, 0.224, 0 }, s = { 0.372, 0.973, 2.957 }, tri = 14204 },
    },
    pts = { grip = { 0, -0.12, -0.61 }, rail = { 0, 0.52, -0.45 }, muzzle = { 0, 0.33, 1.42 }, sightR = { 0, 0.47, -0.05 }, sightF = { 0, 0.5, 1.05 } },
    size = { 0.372, 0.973, 2.957 },
    credit = "美军轻机枪（M249）：M249，作者 ArtDmitriyK，CC-BY-4.0 https://sketchfab.com/3d-models/m249-b1e60faa37de4461822103fe38e5c9ce",
  },
  m1014 = {
    parts = {
      Body = { c = { 0, 0, 0 }, s = { 0.179, 0.555, 2.83 }, tri = 4118 },
    },
    pts = { grip = { 0, -0.135, -0.62 }, rail = { 0, 0.22, -0.13 }, muzzle = { 0, 0.135, 1.36 }, sightR = { 0, 0.235, -0.45 }, sightF = { 0, 0.24, 1.25 } },
    size = { 0.179, 0.555, 2.83 },
    credit = "美军霰弹枪（M1014）：Low Poly ShotGun-M1014，作者 BravoCastle，CC-BY-4.0 https://sketchfab.com/3d-models/low-poly-shotgun-m1014-623381817230474f9148f6208655cdfb",
  },
  m17 = {
    parts = {
      C222 = { c = { 0, 0.024, 0.011 }, s = { 0.088, 0.398, 0.547 }, tri = 2544, col = { 27, 27, 27 }, met = 0.5 },
      Caa4 = { c = { 0, 0, 0 }, s = { -2000000000, -2000000000, -2000000000 }, tri = 0, col = { 178, 163, 65 }, met = 1 },
      Cb73 = { c = { 0, 0, 0 }, s = { -2000000000, -2000000000, -2000000000 }, tri = 0, col = { 184, 115, 51 }, met = 1 },
      Ca85 = { c = { 0, 0.161, 0.019 }, s = { 0.073, 0.102, 0.522 }, tri = 1185, col = { 171, 130, 91 }, met = 0.5 },
      C0f0 = { c = { 0, 0.218, 0.012 }, s = { 0.029, 0.009, 0.466 }, tri = 18, col = { 0, 255, 0 }, met = 0 },
      Cdb8 = { c = { 0, -0.006, -0.035 }, s = { 0.085, 0.31, 0.499 }, tri = 1357, col = { 224, 189, 136 }, met = 0 },
      C777 = { c = { -0.001, 0.13, -0.109 }, s = { 0.064, 0.063, 0.275 }, tri = 338, col = { 124, 124, 124 }, met = 0.5 },
    },
    pts = { grip = { 0, -0.045, -0.18 }, muzzle = { 0, 0.14, 0.28 }, sightR = { 0, 0.215, -0.2 }, sightF = { 0, 0.215, 0.256 } },
    size = { 0.088, 0.398, 0.569 },
    credit = "美军手枪（M17）：low-poly SIG Sauer M17，作者 DU1701，CC-BY-4.0 https://sketchfab.com/3d-models/low-poly-sig-sauer-m17-35e5bc9e68a841788ec8fdb09589fb92",
  },
  mp7 = {
    parts = {
      C222 = { c = { 0.002, 0.128, 0.187 }, s = { 0.073, 0.204, 0.655 }, tri = 712, col = { 40, 40, 40 }, met = 0 },
      C888 = { c = { -0.013, 0.128, 0.074 }, s = { 0.013, 0.013, 0.011 }, tri = 20, col = { 143, 143, 143 }, met = 0 },
      Ceee = { c = { 0.001, 0.092, 0.1 }, s = { 0.02, 0.04, 0.068 }, tri = 564, col = { 231, 231, 231 }, met = 0 },
      C777 = { c = { 0.002, 0.119, 0.089 }, s = { 0.04, 0.027, 0.14 }, tri = 104, col = { 124, 124, 124 }, met = 0 },
      C333 = { c = { 0, 0, 0 }, s = { 0.089, 0.543, 1.178 }, tri = 5180, col = { 49, 49, 49 }, met = 0 },
      C444 = { c = { 0.002, 0.064, -0.027 }, s = { 0.082, 0.321, 1.1 }, tri = 364, col = { 66, 66, 66 }, met = 0 },
    },
    pts = { grip = { 0, -0.065, 0.105 }, rail = { 0, 0.2, 0.17 }, muzzle = { 0, 0.107, 0.59 }, sightR = { 0, 0.25, -0.024 }, sightF = { 0, 0.25, 0.393 } },
    size = { 0.089, 0.543, 1.178 },
    credit = "美军冲锋枪（MP7A1）：Low-Poly HK MP7，作者 TastyTony，CC-BY-4.0 https://sketchfab.com/3d-models/low-poly-hk-mp7-0ebd1e2b7a60408cb3b587b4807635ab",
  },
}
