-- Roblox全面大战场——机载武器的外形（服务器、客户端共用）：按型号拼零件
--   挂在飞机上（AirModels）、飞出去的弹（Fx）、挂载编辑器（Hangar）都用这一套，所以同一枚弹在哪儿看都一样
--   坐标：弹体中心为原点，−Z 朝前（弹头），+Y 朝上（挂架那边）；长度、直径按 AirDefs.W[...].shape（格，1 米约 2.8 格）
--   每个型号一条描述：nose 弹头样式（ir 红外导引头玻璃罩、radar 雷达罩、arm 反辐射雷达罩、tv 电视 / 红外成像大玻璃罩、laser 激光导引头 + 前翼、
--     jdam / bomb 炸弹头）、col 弹体颜色、bands 色带（离弹头的比例、宽、颜色）、tail 尾翼 / mid 弹体中段的弹翼 / can 鸭翼（root 位置、弦长、展长……）、
--     wing 弹体上方的折叠翼（挂着时折在弹体上，飞出去才展开）、kit 炸弹尾翼套件（mk 低阻尾锥、jdam 尾翼套件 + 弹体边条、paveway 大尾翼、sdb 小直径炸弹）、pod 火箭巢
--   WM.spec(w, flight) 返回零件描述 { t = "cyl" | "box" | "ball" | "wedge" | "mesh"（导入的原模型，src 是模板）, size, cf, col, mat }；
--   WM.make(parent, w, cf, flight) 直接拼出零件（返回零件和相对偏移）
local WM = {}

local V = Vector3.new
local CF = CFrame.new
local RGB = Color3.fromRGB
local MAT = Enum.Material

local WHITE = RGB(232, 234, 230)
local LGREY = RGB(196, 200, 198)
local GREY = RGB(150, 156, 156)
local OLIVE = RGB(96, 102, 74)
local OLIVE2 = RGB(124, 128, 92)
local DGREEN = RGB(70, 84, 70)
local DARK = RGB(40, 42, 44)
local YELLOW = RGB(226, 178, 40)
local BROWN = RGB(140, 96, 52)
local RED = RGB(190, 50, 40)
local GLASS = RGB(60, 80, 96)

-- 型号的外形描述（比例都按弹长 L、弹径 d）
local D = {
  -- 空空导弹
  -- 霹雳-10 / 霹雳-15 的尾翼照真弹的比例（用户 11-23 核对歼-20 弹舱：原来的尾翼翼展快一米，四枚霹雳-15 塞不进主弹舱、霹雳-10 收不进侧弹舱）：
  --   霹雳-15 歼-20 用的是切短的尾翼，尾翼尖离弹轴约 0.18 米；霹雳-10 的舵面大一点，约 0.2 米
  pl2 = { nose = "ir", col = LGREY, bands = { { 0.2, 0.03, YELLOW } }, tail = { at = 0.9, c = 0.13, s = 2.3 }, can = { at = 0.16, c = 0.07, s = 1.6 } },   -- 霹雳-2：前面四片小舵、后面四片大尾翼（响尾蛇 B 的样子）
  pl10 = { nose = "ir", col = LGREY, bands = { { 0.22, 0.03, YELLOW } }, tail = { at = 0.9, c = 0.11, s = 0.75 }, mid = { at = 0.28, c = 0.05, s = 0.9, strake = 0.5 } },
  aim9x = { nose = "ir", col = GREY, bands = { { 0.2, 0.025, YELLOW }, { 0.3, 0.025, BROWN } }, tail = { at = 0.93, c = 0.09, s = 2.4 }, mid = { at = 0.24, c = 0.035, s = 1.2 } },
  pl15 = { nose = "radar", col = WHITE, bands = { { 0.25, 0.025, YELLOW } }, tail = { at = 0.92, c = 0.08, s = 0.6 }, mid = { at = 0.5, c = 0.32, s = 0.55, strake = 1 } },
  pl12 = { nose = "radar", col = WHITE, bands = { { 0.24, 0.025, YELLOW } }, tail = { at = 0.93, c = 0.08, s = 2.0 }, mid = { at = 0.42, c = 0.12, s = 1.6 } },
  aim120 = { nose = "radar", col = WHITE, bands = { { 0.22, 0.025, YELLOW }, { 0.34, 0.025, BROWN } }, tail = { at = 0.94, c = 0.075, s = 2.1 }, mid = { at = 0.4, c = 0.1, s = 1.5 } },
  aim54 = { nose = "radar", col = WHITE, bands = { { 0.2, 0.02, YELLOW }, { 0.3, 0.02, BROWN } }, tail = { at = 0.9, c = 0.11, s = 1.5 }, mid = { at = 0.42, c = 0.22, s = 1.2 } },   -- 不死鸟：粗、四片长弦弹翼
  ty90 = { nose = "ir", col = LGREY, bands = { { 0.2, 0.03, YELLOW } }, tail = { at = 0.9, c = 0.1, s = 2.6 }, can = { at = 0.14, c = 0.06, s = 1.4 } },
  aim92 = { nose = "ir", col = GREY, bands = { { 0.2, 0.03, YELLOW }, { 0.3, 0.03, BROWN } }, tail = { at = 0.93, c = 0.08, s = 2.6 }, can = { at = 0.12, c = 0.05, s = 1.5 } },
  -- 空地导弹
  akd10 = { nose = "laser", col = DGREEN, bands = { { 0.3, 0.03, YELLOW } }, tail = { at = 0.9, c = 0.12, s = 1.6 }, mid = { at = 0.55, c = 0.18, s = 1.3 } },
  agm114 = { nose = "laser", col = OLIVE, bands = { { 0.3, 0.03, YELLOW }, { 0.62, 0.03, BROWN } }, tail = { at = 0.9, c = 0.12, s = 1.6 }, mid = { at = 0.5, c = 0.16, s = 1.3 } },
  agm65 = { nose = "tv", col = OLIVE2, bands = { { 0.28, 0.025, YELLOW }, { 0.6, 0.025, BROWN } }, tail = { at = 0.9, c = 0.12, s = 1.9 }, mid = { at = 0.5, c = 0.45, s = 0.9, strake = 1 } },
  kd88 = { nose = "tv", col = LGREY, bands = { { 0.3, 0.02, YELLOW } }, tail = { at = 0.93, c = 0.08, s = 1.5 }, wing = { at = 0.48, c = 0.1, span = 2.6 } },
  yj83k = { nose = "radar", col = LGREY, bands = { { 0.22, 0.025, YELLOW } }, tail = { at = 0.92, c = 0.07, s = 1.5 }, wing = { at = 0.42, c = 0.11, span = 3.4 } },   -- 鹰击-83K：十字形弹翼在中段、尾翼在最后
  yj91 = { nose = "arm", col = GREY, bands = { { 0.26, 0.025, YELLOW } }, tail = { at = 0.92, c = 0.09, s = 1.6 }, mid = { at = 0.45, c = 0.14, s = 1.4 }, can = { at = 0.18, c = 0.06, s = 1.2 } },
  agm88 = { nose = "arm", col = WHITE, bands = { { 0.24, 0.025, YELLOW }, { 0.55, 0.025, BROWN } }, tail = { at = 0.94, c = 0.08, s = 1.8 }, mid = { at = 0.38, c = 0.18, s = 2.0 } },
  -- 惊雷-1 高超音速战术核导弹（虚构）：白色弹体、深色烧蚀弹头、红黄两道警示带、尾部四片小舵（空射弹道导弹的样子）
  hn1 = { nose = "arm", col = WHITE, bands = { { 0.24, 0.018, RED }, { 0.285, 0.018, YELLOW }, { 0.72, 0.012, DARK } }, tail = { at = 0.93, c = 0.1, s = 1.25 } },
  -- 炸弹
  mk82 = { nose = "bomb", col = OLIVE, bands = { { 0.18, 0.025, YELLOW } }, kit = "mk" },
  b250 = { nose = "bomb", col = DGREEN, bands = { { 0.2, 0.025, YELLOW } }, kit = "mk" },
  gbu31 = { nose = "jdam", col = OLIVE, bands = { { 0.16, 0.025, YELLOW } }, kit = "jdam" },
  gbu32 = { nose = "jdam", col = OLIVE, bands = { { 0.16, 0.025, YELLOW } }, kit = "jdam" },
  gbu38 = { nose = "jdam", col = OLIVE, bands = { { 0.16, 0.025, YELLOW } }, kit = "jdam" },
  gbu12 = { nose = "laser", col = OLIVE, bands = { { 0.32, 0.025, YELLOW } }, kit = "paveway" },
  lt2 = { nose = "laser", col = DGREEN, bands = { { 0.32, 0.025, YELLOW } }, kit = "paveway" },
  ls6 = { nose = "jdam", col = LGREY, bands = { { 0.18, 0.025, YELLOW } }, kit = "jdam", wing = { at = 0.42, c = 0.09, span = 3.6 } },
  gbu39 = { nose = "jdam", col = GREY, bands = { { 0.16, 0.03, YELLOW } }, kit = "sdb", wing = { at = 0.4, c = 0.12, span = 4.0 } },
  -- 火箭巢
  hydra = { pod = true, col = OLIVE },
  fl90 = { pod = true, col = DGREEN },
  -- 副油箱：浅灰（解放军 800 升，尾部三片小安定面）、美军灰、直升机墨绿 / 橄榄绿
  tk800 = { tank = true, col = LGREY, fins = true },
  tk370 = { tank = true, col = GREY },
  tkh = { tank = true, col = DGREEN },
  tk230 = { tank = true, col = OLIVE },
}
WM.D = D

local cache = {}
-- 用户给的导弹合集（models/wpn/missiles.glb，开服时 Imports 收进 ReplicatedStorage.Imported.Wpn.<型号>）：导入了就用原模型，
--   按 AirDefs 的弹长 L 等比缩放（GBU-38 借 GBU-32 的模型缩小）；没导入照旧零件拼。原模型导入时被转了半圈，乘 TURN 补回
local IMP_ALIAS = { gbu38 = "gbu32" }
local TURN = CFrame.Angles(0, math.pi, 0)
local function impMesh(id)
  local f = game:GetService("ReplicatedStorage"):FindFirstChild("Imported")
  f = f and f:FindFirstChild("Wpn")
  f = f and f:FindFirstChild(IMP_ALIAS[id] or id)
  if not f then return nil end
  for _, c in ipairs(f:GetChildren()) do
    if c:IsA("MeshPart") then return c end
  end
  return nil
end
WM.impMesh = impMesh
-- flight：飞出去的样子（折叠翼展开）；挂在飞机上是折着的
function WM.spec(w, flight)
  local tpl = impMesh(w.id)
  if tpl then
    local mk = (w.id or "?") .. "M"
    local c = cache[mk]
    if c and c[1].src == tpl then return c end
    local L = (w.shape and w.shape.L) or tpl.Size.Z
    c = { { t = "mesh", src = tpl, size = tpl.Size * (L / math.max(tpl.Size.Z, 0.01)), cf = TURN } }
    cache[mk] = c
    return c
  end
  local key = (w.id or "?") .. (flight and "F" or "S")
  if cache[key] then return cache[key] end
  local S = w.shape or { L = 5, d = 0.6 }
  local L, d = S.L, S.d
  local desc = D[w.id] or (w.kind == "bomb" and { nose = "bomb", col = OLIVE, kit = "mk" }) or (w.kind == "tank" and { tank = true, col = LGREY })
    or (w.kind == "rkt" and { pod = true, col = OLIVE }) or { nose = "radar", col = WHITE, tail = { at = 0.92, c = 0.09, s = 2 } }
  local out = {}
  local function put(t, size, cf, col, mat) table.insert(out, { t = t, size = size, cf = cf, col = col, mat = mat or MAT.SmoothPlastic }) end
  local function zAt(f) return -L / 2 + f * L end   -- 离弹头 f 倍弹长处的 z
  local col = desc.col or WHITE

  if desc.pod then   -- 火箭巢：粗圆筒、前后整流罩、前端一圈发射管口
    local n = w.tubes or 12
    put("cyl", V(L * 0.78, d, d), CF(0, 0, 0), col, MAT.Metal)
    put("ball", V(d, d, L * 0.22), CF(0, 0, -L * 0.39), col, MAT.Metal)
    put("ball", V(d * 0.96, d * 0.96, L * 0.18), CF(0, 0, L * 0.39), col, MAT.Metal)
    put("cyl", V(0.06, d * 0.9, d * 0.9), CF(0, 0, -L * 0.47), DARK)
    local ring = math.min(n, 12)
    for k = 1, ring do   -- 发射管口（前端面上一圈小黑圆）
      local a = (k - 1) / ring * math.pi * 2
      put("cyl", V(0.08, d * 0.16, d * 0.16), CF(math.cos(a) * d * 0.3, math.sin(a) * d * 0.3, -L * 0.48), RGB(20, 20, 20))
    end
    put("cyl", V(L * 0.04, d * 1.03, d * 1.03), CF(0, 0, -L * 0.2), YELLOW)
    put("box", V(d * 0.2, d * 0.25, L * 0.3), CF(0, d * 0.55, 0), DARK, MAT.Metal)   -- 吊耳
    cache[key] = out
    return out
  end
  if desc.tank then   -- 副油箱：两头尖的流线长筒（中段圆柱，前面短椭球、后面长椭球收尖），中间一道焊缝，上面两个吊耳；有的尾部三片小安定面
    put("cyl", V(L * 0.46, d, d), CF(0, 0, -L * 0.02), col, MAT.Metal)
    put("ball", V(d, d, L * 0.44), CF(0, 0, -L * 0.25), col, MAT.Metal)
    put("ball", V(d * 0.99, d * 0.99, L * 0.56), CF(0, 0, L * 0.2), col, MAT.Metal)
    put("cyl", V(0.05, d * 1.01, d * 1.01), CF(0, 0, -L * 0.02), col:Lerp(DARK, 0.3))
    put("cyl", V(0.05, d * 1.01, d * 1.01), CF(0, 0, -L * 0.22), col:Lerp(DARK, 0.3))
    if desc.fins then
      for _, a in ipairs({ math.pi, math.pi * 0.25, -math.pi * 0.25 }) do   -- 下面一片、上面左右各一片（避开挂架）
        put("wedge", V(0.06, d * 0.42, L * 0.13), CF(0, 0, L * 0.38) * CFrame.Angles(0, 0, a) * CF(0, d * 0.3 + d * 0.21, 0), col)
      end
    end
    if not flight then
      put("box", V(d * 0.16, d * 0.14, d * 0.45), CF(0, d * 0.52, -L * 0.12), DARK, MAT.Metal)
      put("box", V(d * 0.16, d * 0.14, d * 0.45), CF(0, d * 0.52, L * 0.12), DARK, MAT.Metal)
    end
    cache[key] = out
    return out
  end

  local bomb = w.kind == "bomb"
  -- 弹头
  local noseL = (desc.nose == "radar" or desc.nose == "arm") and L * 0.16 or ((desc.nose == "bomb" or desc.nose == "jdam") and L * 0.3 or L * 0.09)
  local bodyFrom, bodyTo = -L / 2 + noseL * 0.55, L / 2 - (bomb and L * 0.22 or L * 0.02)
  put("cyl", V(bodyTo - bodyFrom, d, d), CF(0, 0, (bodyFrom + bodyTo) / 2), col)
  local nz = -L / 2 + noseL / 2
  if desc.nose == "ir" then   -- 红外：短锥 + 前端玻璃半球
    put("ball", V(d, d, noseL * 1.3), CF(0, 0, nz + noseL * 0.15), col)
    put("ball", V(d * 0.62, d * 0.62, d * 0.62), CF(0, 0, -L / 2 + d * 0.22), GLASS, MAT.Glass)
  elseif desc.nose == "radar" then   -- 雷达罩：细长的尖头
    put("ball", V(d, d, noseL * 2), CF(0, 0, nz + noseL * 0.45), RGB(214, 216, 212))
  elseif desc.nose == "arm" then   -- 反辐射：深色尖头
    put("ball", V(d, d, noseL * 2), CF(0, 0, nz + noseL * 0.45), RGB(70, 72, 74))
    put("ball", V(d * 0.3, d * 0.3, d * 0.5), CF(0, 0, -L / 2 + d * 0.1), DARK)
  elseif desc.nose == "tv" then   -- 电视 / 红外成像：大玻璃罩
    put("ball", V(d, d, noseL * 1.6), CF(0, 0, nz + noseL * 0.3), col)
    put("ball", V(d * 0.84, d * 0.84, d * 0.7), CF(0, 0, -L / 2 + d * 0.3), GLASS, MAT.Glass)
  elseif desc.nose == "laser" then   -- 激光：细一点的导引头、前端玻璃、四片鸭翼
    local hd = bomb and d * 0.55 or d * 0.82
    put("cyl", V(noseL * 1.2, hd, hd), CF(0, 0, -L / 2 + noseL * 0.75), bomb and RGB(110, 112, 104) or col)
    put("ball", V(hd, hd, hd * 0.9), CF(0, 0, -L / 2 + hd * 0.32), GLASS, MAT.Glass)
    if bomb then
      put("cyl", V(0.12, hd * 1.15, hd * 1.15), CF(0, 0, -L / 2 + noseL * 0.9), RGB(80, 82, 76))   -- 导引头的环
      for k = 0, 3 do   -- 鸭翼
        local a = k * math.pi / 2 + math.pi / 4
        put("box", V(0.06, d * 0.5, L * 0.07), CF(0, 0, -L / 2 + noseL * 1.35) * CFrame.Angles(0, 0, a) * CF(0, hd / 2 + d * 0.22, 0), RGB(110, 112, 104))
      end
    end
  else   -- 炸弹：钝圆的弹头（制导炸弹前面一个引信）
    put("ball", V(d, d, noseL * 1.5), CF(0, 0, nz + noseL * 0.4), col)
    if desc.nose == "jdam" then put("cyl", V(d * 0.3, d * 0.22, d * 0.22), CF(0, 0, -L / 2 + noseL * 0.02), DARK) end
  end
  -- 色带
  for _, b in ipairs(desc.bands or {}) do
    put("cyl", V(math.max(0.06, b[2] * L), d * 1.02, d * 1.02), CF(0, 0, zAt(b[1])), b[3])
  end
  -- 翼面：cruciform（X 形，四片）
  local function fins(F, c2)
    if not F then return end
    local z = zAt(F.at)
    local chord, span = F.c * L, F.s * d
    for k = 0, 3 do
      local a = k * math.pi / 2 + math.pi / 4
      if F.strake then   -- 长边条：贴着弹体的细长翼
        put("box", V(0.05, span * 0.5, chord), CF(0, 0, z) * CFrame.Angles(0, 0, a) * CF(0, d / 2 + span * 0.25, 0), c2 or col)
      else   -- 切角三角翼：楔形（前缘斜、后缘平）
        put("wedge", V(0.06, span, chord), CF(0, 0, z) * CFrame.Angles(0, 0, a) * CF(0, d / 2 + span / 2, 0), c2 or col)
      end
    end
  end
  fins(desc.tail)
  fins(desc.mid)
  fins(desc.can)
  -- 炸弹尾翼套件
  if desc.kit == "mk" then   -- 低阻尾锥 + 四片方尾翼
    put("cyl", V(L * 0.12, d * 0.78, d * 0.78), CF(0, 0, L / 2 - L * 0.17), col)
    put("cyl", V(L * 0.1, d * 0.5, d * 0.5), CF(0, 0, L / 2 - L * 0.06), col)
    for k = 0, 3 do
      local a = k * math.pi / 2 + math.pi / 4
      put("box", V(0.06, d * 0.55, L * 0.17), CF(0, 0, L / 2 - L * 0.1) * CFrame.Angles(0, 0, a) * CF(0, d * 0.42, 0), col)
    end
  elseif desc.kit == "jdam" or desc.kit == "sdb" then   -- 联合直接攻击弹药：灰色尾翼套件、四片长尾翼、弹体中段的边条
    local tk = RGB(150, 150, 140)
    put("cyl", V(L * 0.24, d * 0.86, d * 0.86), CF(0, 0, L / 2 - L * 0.13), tk)
    put("cyl", V(L * 0.04, d * 0.62, d * 0.62), CF(0, 0, L / 2 - L * 0.005), DARK)
    for k = 0, 3 do
      local a = k * math.pi / 2 + math.pi / 4
      put("wedge", V(0.07, d * ((desc.kit == "sdb") and 0.45 or 0.65), L * 0.16), CF(0, 0, L / 2 - L * 0.09) * CFrame.Angles(0, 0, a) * CF(0, d * 0.43 + d * 0.3, 0), tk)
      if desc.kit == "jdam" then   -- 弹体边条
        put("box", V(0.05, d * 0.14, L * 0.3), CF(0, 0, -L * 0.02) * CFrame.Angles(0, 0, a) * CF(0, d * 0.53, 0), tk)
      end
    end
  elseif desc.kit == "paveway" then   -- 激光制导炸弹：尾部四片大翼
    for k = 0, 3 do
      local a = k * math.pi / 2 + math.pi / 4
      put("box", V(0.07, d * 0.85, L * 0.2), CF(0, 0, L / 2 - L * 0.1) * CFrame.Angles(0, 0, a) * CF(0, d * 0.75, 0), RGB(110, 112, 104))
    end
    put("cyl", V(L * 0.2, d * 0.7, d * 0.7), CF(0, 0, L / 2 - L * 0.1), RGB(110, 112, 104))
  end
  -- 折叠翼：挂着时折在弹体上方，飞出去展开
  if desc.wing then
    local W = desc.wing
    local z = zAt(W.at)
    local chord = W.c * L
    if flight then
      put("box", V(W.span, 0.08, chord), CF(0, d * 0.58, z), col:Lerp(DARK, 0.15))
    else
      put("box", V(d * 0.9, 0.1, W.span * 0.5), CF(0, d * 0.58, z + W.span * 0.2), col:Lerp(DARK, 0.15))
    end
  end
  -- 吊耳（挂着时看得到的两个小块）
  if not flight then
    put("box", V(d * 0.18, d * 0.18, d * 0.4), CF(0, d * 0.55, -L * 0.1), DARK, MAT.Metal)
    put("box", V(d * 0.18, d * 0.18, d * 0.4), CF(0, d * 0.55, L * 0.12), DARK, MAT.Metal)
  end
  cache[key] = out
  return out
end

-- 按描述拼一个零件（AirModels、Fx、Hangar 共用）：圆柱的轴在 X，这里转到 Z；椭球用 SpecialMesh（Ball 零件只能是正圆）；楔子用 WedgePart
function WM.part(e, parent)
  local p
  if e.t == "mesh" then   -- 原模型：照导入的那块复制、按弹长缩放
    p = e.src:Clone()
    p.Size = e.size
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    p.Parent = parent
    return p
  elseif e.t == "wedge" then
    p = Instance.new("WedgePart")
  else
    p = Instance.new("Part")
    if e.t == "cyl" then p.Shape = Enum.PartType.Cylinder end
  end
  local size = e.size
  p.Size = V(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
  p.Color = e.col
  p.Material = e.mat
  if e.mat == MAT.Glass then p.Transparency = 0.25 end
  p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
  p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
  if e.t == "ball" then
    local m = Instance.new("SpecialMesh")
    m.MeshType = Enum.MeshType.Sphere
    m.Parent = p
  end
  p.Parent = parent
  return p
end
-- 零件相对弹体中心的 CFrame（圆柱要把轴从 X 转到 Z）
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)
function WM.offset(e)
  if e.t == "cyl" then return e.cf * ALONG_Z end
  return e.cf
end
-- 直接拼一枚：返回 { parts, offs }；之后每帧 parts[i].CFrame = cf * offs[i]（或者一次 BulkMoveTo）
function WM.make(parent, w, cf, flight)
  local parts, offs = {}, {}
  for _, e in ipairs(WM.spec(w, flight)) do
    local p = WM.part(e, parent)
    local o = WM.offset(e)
    p.CFrame = cf * o
    table.insert(parts, p)
    table.insert(offs, o)
  end
  return { parts = parts, offs = offs }
end

return WM
