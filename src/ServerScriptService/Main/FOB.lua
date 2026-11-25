-- 全面大战场——沙海两边的主基地（前进作战基地 FOB + 机场，围在一起）
--   用户 11-24：「整个军事基地的地图过于分散、没有细节、过于粗糙」「固定两边都在双方各自固定位置出生」「做一个军事基地营地，反正一整套细节你给我做到极致」
--   「沙海加载时间太长，而且地图不够精细、细节少，军事基地应该在一起」
--   原来红方的前进基地、前进机场是两块，蓝方的后方营地只有五顶帐篷、两座铁皮房——现在两边各一座照真的前进作战基地排得紧紧的：
--   ① 营区（1120 × 840 格，约 400 × 300 米）：一圈 HESCO 防爆墙、外面一道蛇腹铁丝网、钢架岗楼、拖车照明塔；正门是车辆检查站（ECP：
--      之字形水泥隔离墩、减速带、阻车钉、检查棚、岗亭、抬杆、沙袋碉堡），车场门正对战场；
--      前排：车场（硬化地坪、召唤车位、两座拱顶维修棚、洗车台、零件集装箱、轮胎堆）、出生广场 + 三根旗杆、三个直升机坪（前沿加油点）；
--      中间：战术指挥中心（加固的掩体房、伪装网、卫星天线、拉线天线阵、发电机组）、迫击炮阵地、近防炮；
--      后排：生活区（一排排集装箱宿舍 CHU，中间 T 形防爆墙、混凝土防空掩体、淋浴 / 厕所拖车、流动厕所、水罐）、食堂 DFAC、健身房、
--      商店 PX、洗衣房、后勤区（大仓库、集装箱堆场、油料库：土堤围着的油囊、弹药库：土堤隔开的弹药格）；
--   ② 机场在营区后面（东西向跑道 3600 格、平行滑行道、联络道、停机坪、加固机库、机库、塔台、消防站、进近灯、PAPI、风向袋、雷达、盲降天线）；
--   ③ 整个基地外面一圈土堤。
--   坐标：每边按基地自己的坐标摆（Map.FOB：lx 横向、lz 纵向、−lz 朝战场；Map.baseW 换成世界坐标），两边绕地图中心转半圈——一模一样。
--   零件数：一边大约八九千块（大部分是不挡人、不投影的小装饰）；夜里的真光源一边几十盏，别的灯只画光晕
local RS = game:GetService("ReplicatedStorage")
local Map = require(RS:WaitForChild("Map"))
local Config = require(RS:WaitForChild("Config"))

local FOB = {}

local V, CF, RGB, MAT = Vector3.new, CFrame.new, Color3.fromRGB, Enum.Material
local ANG = CFrame.Angles
local CYL = Enum.PartType.Cylinder
local PI = math.pi
local UPC = ANG(0, 0, PI / 2)   -- 圆柱的轴（X）立起来

local W = nil   -- World 模块（build 时给：part、light、floodPole、building、sign）

---------------------------------------------------------------- 颜色

local COL = {
  hesco = RGB(178, 160, 120), hesco2 = RGB(164, 146, 108), hescoTop = RGB(140, 118, 84), wire = RGB(74, 74, 68),
  conc = RGB(178, 174, 162), concDk = RGB(142, 136, 124), concDirt = RGB(150, 130, 100), jersey = RGB(190, 186, 174),
  sand = RGB(178, 162, 118), sandDk = RGB(156, 140, 100), steel = RGB(98, 102, 104), steelDk = RGB(60, 62, 64),
  ply = RGB(176, 146, 102), tin = RGB(112, 114, 108), tent = RGB(184, 166, 126), tentDk = RGB(156, 140, 104), olive = RGB(88, 98, 68),
  chu = RGB(222, 214, 194), chu2 = RGB(200, 186, 152), door = RGB(98, 92, 82), glass = RGB(38, 50, 60), frame = RGB(214, 212, 204),
  ac = RGB(208, 208, 202), acGr = RGB(70, 72, 74), gravel = RGB(152, 140, 120), asphalt = RGB(54, 56, 58), paint = RGB(232, 228, 216),
  yellow = RGB(228, 188, 48), red = RGB(196, 52, 44), white = RGB(236, 236, 230), wood = RGB(132, 100, 66), pallet = RGB(156, 126, 86),
  crate = RGB(98, 106, 72), rubber = RGB(28, 28, 30), canvas = RGB(122, 118, 90), camo = RGB(146, 132, 96), lamp = RGB(255, 222, 170),
  wireC = RGB(160, 162, 160), duct = RGB(196, 186, 160), gen = RGB(150, 140, 104), blue = RGB(60, 96, 150), green = RGB(70, 120, 76),
}
local CONEX = { RGB(128, 98, 70), RGB(92, 104, 84), RGB(156, 144, 112), RGB(132, 64, 52), RGB(72, 88, 112), RGB(176, 168, 150), RGB(110, 112, 104) }

---------------------------------------------------------------- 零件小工具

local function P(f, sx, sy, sz, cf, col, mat, solid)
  return W.part(f, V(sx, sy, sz), cf, col, mat, nil, solid)
end
local function CylV(f, h, d, cf, col, mat, solid) return W.part(f, V(h, d, d), cf * UPC, col, mat, CYL, solid) end   -- 竖的（cf 是中心）
local function CylX(f, len, d, cf, col, mat, solid) return W.part(f, V(len, d, d), cf, col, mat, CYL, solid) end   -- 顺着 cf 的 X
local function CylZ(f, len, d, cf, col, mat, solid) return W.part(f, V(len, d, d), cf * ANG(0, PI / 2, 0), col, mat, CYL, solid) end
local function Wd(f, sx, sy, sz, cf, col, mat, solid)   -- 楔子：高的一边在 +Z
  local w = Instance.new("WedgePart")
  w.Anchored, w.Size, w.CFrame, w.Color, w.Material = true, V(sx, sy, sz), cf, col, mat or MAT.SmoothPlastic
  w.TopSurface, w.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
  if not solid then
    w.CanCollide, w.CanQuery, w.CanTouch = false, false, false
    w.CastShadow = false
  end
  w.Parent = f
  return w
end
local function folder(name, parent)
  local f = Instance.new("Folder")
  f.Name = name
  f.Parent = parent
  return f
end
-- 两点之间一根细杆（拉索、斜撑、电缆、管子）
local function rod(f, a, b, d, col, mat)
  local L = (b - a).Magnitude
  if L < 0.05 then return nil end
  return P(f, d, d, L, CFrame.lookAt((a + b) / 2, b), col, mat or MAT.Metal)
end
-- 牌子：正面（−Z）一块字
local function board(f, cf, w, h, text, bg, fg, solid)
  local p = P(f, w, h, 0.25, cf, bg or COL.white, MAT.SmoothPlastic, solid)
  local sg = Instance.new("SurfaceGui")
  sg.Face = Enum.NormalId.Front
  sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
  sg.PixelsPerStud = 14   -- 牌子上的字不用多清楚；SurfaceGui / BillboardGui 太多，引擎会把所有 3D 界面（车里、座舱的屏幕）一起降分辨率
  sg.LightInfluence = 0.6
  sg.MaxDistance = 150
  sg.Parent = p
  local t = Instance.new("TextLabel")
  t.Size = UDim2.new(1, -6, 1, -4)
  t.Position = UDim2.fromOffset(3, 2)
  t.BackgroundTransparency = 1
  t.TextScaled = true
  t.Font = Enum.Font.GothamBold
  t.TextColor3 = fg or Color3.new(0.1, 0.1, 0.1)
  t.Text = text
  t.Parent = sg
  return p
end
-- 小灯：只是一块霓虹（用户 11-24：「现在所有显示屏的清晰度非常低」——原来每盏小灯都挂一个 BillboardGui 光晕，两座基地九百多个，
--   引擎画 3D 界面的预算被占满，车里、座舱的屏幕跟着降分辨率；霓虹零件夜里照样亮，不占那份预算）
local function glow(f, pos, col, size)
  local s = size or 0.5
  local p = W.part(f, V(s, s * 0.6, s), CF(pos), col or COL.lamp, MAT.Neon)
  p.CastShadow = false
  return p
end
-- 远处也要看得见的少数几盏（跑道信标）：带光晕
local function beacon(f, pos, col, size) return W.light(f, pos, col or COL.lamp, size or 0.6, nil, nil, nil, 3) end
-- 灯头：霓虹 + 可选的射灯（朝 look 照；不带光晕）
local function lamp(f, pos, look, col, size, range, angle, bright)
  local s = size or 1
  local p = W.part(f, V(s, s * 0.6, s), CFrame.lookAt(pos, pos + look), col or COL.lamp, MAT.Neon)
  p.CastShadow = false
  if range then
    local L = Instance.new("SpotLight")
    L.Face, L.Angle, L.Range, L.Brightness, L.Color, L.Shadows = Enum.NormalId.Front, angle or 70, range, bright or 2.2, col or COL.lamp, false
    L.Parent = p
  end
  return p
end
-- 探照灯杆（同 World.floodPole，灯头不带光晕）
local function floodPole(f, x, y, z, h, col, range)
  W.part(f, V(0.7, h, 0.7), CF(x, y + h / 2, z), RGB(60, 62, 66), MAT.Metal, nil, true)
  W.part(f, V(3.2, 0.5, 1.6), CF(x, y + h, z), RGB(40, 42, 46), MAT.Metal)
  lamp(f, V(x, y + h - 0.4, z), V(0, -1, 0), col, 1.4, range, 95, 2.4)
end

---------------------------------------------------------------- 防御工事

-- HESCO 防爆墙：顺着 cf 的 X 摆 len 长，+Z 是里面（里面那面的铁丝网格缝每个单元一道，外面每组一道）；tiers 几层；gaps 留口子（X 范围）
local function hesco(f, cf, len, tiers, gaps)
  local U = 3.2
  local nU = math.max(1, math.floor(len / U + 0.5))
  local x0 = -nU * U / 2
  local i = 0
  while i < nU do
    local g = math.min(4, nU - i)
    local xa = x0 + i * U
    local xm = xa + g * U / 2
    local skip = false
    for _, gp in ipairs(gaps or {}) do
      if xm > gp[1] and xm < gp[2] then skip = true end
    end
    if not skip then
      for t = 0, (tiers or 1) - 1 do
        local y = t * 3.9
        local col = ((i // 4) % 3 == 1) and COL.hesco2 or COL.hesco
        P(f, g * U - 0.1, 3.8, 3.2, cf * CF(xm, y + 1.9, 0), col, MAT.Fabric, true)
        P(f, g * U - 0.3, 0.3, 2.9, cf * CF(xm, y + 3.85, 0), COL.hescoTop, MAT.Ground)
        for u = 2, g - 1, 2 do P(f, 0.16, 3.8, 0.12, cf * CF(xa + u * U, y + 1.9, 1.62), COL.wire, MAT.Metal) end
        P(f, 0.16, 3.8, 0.12, cf * CF(xa + 0.02, y + 1.9, -1.62), COL.wire, MAT.Metal)
      end
    end
    i += g
  end
end

-- 蛇腹铁丝网：一卷卷半透明的钢丝圈、两道斜拉的钢丝、每卷一根角铁桩
local function wire(f, cf, len, gaps)
  local n = math.max(1, math.floor(len / 24 + 0.5))
  local seg = len / n
  for i = 0, n - 1 do
    local x = -len / 2 + (i + 0.5) * seg
    local skip = false
    for _, gp in ipairs(gaps or {}) do
      if x > gp[1] and x < gp[2] then skip = true end
    end
    if not skip then
      local c = CylX(f, seg - 0.2, 2.8, cf * CF(x, 1.4, 0), COL.wireC, MAT.Metal)
      c.Transparency = 0.72
      c.CastShadow = false
      P(f, seg, 0.07, 0.07, cf * CF(x, 1.4, 0.9) * ANG(0, 0, 0.1), COL.wire, MAT.Metal)
      P(f, seg, 0.07, 0.07, cf * CF(x, 1.4, -0.9) * ANG(0, 0, -0.1), COL.wire, MAT.Metal)
      P(f, 0.22, 3.6, 0.22, cf * CF(x - seg / 2, 1.8, 0), COL.steelDk, MAT.Metal)
    end
  end
end

-- T 形防爆墙（3.7 米高的预制混凝土墙）：一节 7 格宽
local function twall(f, cf, len)
  local n = math.max(1, math.floor(len / 7 + 0.5))
  local seg = len / n
  for i = 0, n - 1 do
    local x = -len / 2 + (i + 0.5) * seg
    local col = COL.conc:Lerp(COL.concDk, ((i * 7) % 5) / 12)
    P(f, seg - 0.15, 12, 0.9, cf * CF(x, 6.6, 0), col, MAT.Concrete, true)
    P(f, seg - 0.15, 1.2, 3.8, cf * CF(x, 0.6, 0), col, MAT.Concrete, true)
    P(f, seg - 0.14, 2.4, 0.94, cf * CF(x, 2.0, 0), COL.concDirt, MAT.Concrete)
    P(f, 0.5, 0.7, 0.3, cf * CF(x, 12.85, 0), COL.steelDk, MAT.Metal)
  end
end

-- 水泥隔离墩（泽西墩）：顺着 cf 的 X
local function jersey(f, cf, col)
  P(f, 8.4, 1.1, 2.3, cf * CF(0, 0.55, 0), col or COL.jersey, MAT.Concrete, true)
  P(f, 8.4, 1.5, 0.95, cf * CF(0, 1.85, 0), col or COL.jersey, MAT.Concrete, true)
end

-- 沙袋墙：一层层错缝（上面一层收一点）
local function bags(f, cf, len, h, th)
  local rows = math.max(1, math.floor(h / 1.0 + 0.5))
  local rh = h / rows
  for r = 0, rows - 1 do
    local col = (r % 2 == 0) and COL.sand or COL.sandDk
    P(f, len - (r % 2) * 0.5, rh - 0.05, (th or 2.2) - r * 0.12, cf * CF(0, r * rh + rh / 2, 0), col, MAT.Fabric, true)
  end
end

-- 土堤：顺着 cf 的 X，两边斜坡（两块楔子背靠背）
local function berm(f, cf, len, h, w)
  Wd(f, len, h, w / 2, cf * CF(0, h / 2, -w / 4), COL.sand:Lerp(COL.hescoTop, 0.35), MAT.Sand, true)
  Wd(f, len, h, w / 2, cf * CF(0, h / 2, w / 4) * ANG(0, PI, 0), COL.sand:Lerp(COL.hescoTop, 0.35), MAT.Sand, true)
end

-- 钢架岗楼：四条腿、两层斜撑、脚下一圈 HESCO、沙袋围起来的哨所、观察窗、铁皮顶、后面的楼梯、正面探照灯和机枪
local function tower(f, cf, lit)
  local H = 20
  for _, o in ipairs({ { -4.6, -4.6 }, { 4.6, -4.6 }, { -4.6, 4.6 }, { 4.6, 4.6 } }) do
    P(f, 0.8, H, 0.8, cf * CF(o[1], H / 2, o[2]), COL.steel, MAT.Metal, true)
  end
  for _, lv in ipairs({ 6.5, 14 }) do
    for s = 0, 3 do
      local r = cf * ANG(0, s * PI / 2, 0)
      rod(f, (r * CF(-4.6, lv - 3.2, -4.6)).Position, (r * CF(4.6, lv + 3.2, -4.6)).Position, 0.3, COL.steelDk)
    end
  end
  for s = 0, 3 do
    local r = cf * ANG(0, s * PI / 2, 0)
    P(f, 13, 3.8, 3, r * CF(0, 1.9, -6.6), COL.hesco, MAT.Fabric, true)
    P(f, 12.8, 0.3, 2.8, r * CF(0, 3.85, -6.6), COL.hescoTop, MAT.Ground)
  end
  P(f, 12, 0.8, 12, cf * CF(0, H + 0.4, 0), COL.ply, MAT.WoodPlanks, true)
  for s = 0, 3 do
    local r = cf * ANG(0, s * PI / 2, 0)
    local back = s == 2
    P(f, back and 6.5 or 12, 3.2, 1.6, r * CF(back and -2.75 or 0, H + 2.4, -5.2), COL.sand, MAT.Fabric, true)
    P(f, 12, 1.0, 0.4, r * CF(0, H + 7.6, -5.8), COL.ply, MAT.WoodPlanks)
    P(f, 0.5, 4.4, 0.5, r * CF(-5.75, H + 6, -5.75), COL.steel, MAT.Metal)
    local g = P(f, 10.6, 3.2, 0.15, r * CF(0, H + 5.6, -5.9), COL.glass, MAT.Glass)
    g.Transparency = 0.55
  end
  P(f, 13.6, 0.4, 13.6, cf * CF(0, H + 8.4, 0) * ANG(0.04, 0, 0), COL.tin, MAT.CorrodedMetal)
  -- 楼梯（后面 +Z）：两根斜梁、踏板、扶手
  local a0, a1 = cf * CF(2.6, 0, 16), cf * CF(2.6, H, 6.2)
  for _, dx in ipairs({ -1.2, 1.2 }) do rod(f, (a0 * CF(dx, 0, 0)).Position, (a1 * CF(dx, 0, 0)).Position, 0.35, COL.steelDk) end
  for k = 1, 9 do
    local t = k / 10
    local p = a0.Position:Lerp(a1.Position, t)
    P(f, 2.4, 0.2, 0.9, CF(p) * (cf - cf.Position), COL.steel, MAT.DiamondPlate)
  end
  rod(f, (a0 * CF(1.4, 3, 0)).Position, (a1 * CF(1.4, 3, 0)).Position, 0.15, COL.yellow)
  -- 机枪：从正面窗口伸出去
  P(f, 0.3, 0.3, 4.2, cf * CF(1.2, H + 4.2, -7.4), COL.steelDk, MAT.Metal)
  P(f, 0.8, 0.8, 2, cf * CF(1.2, H + 4.2, -5.4), COL.steelDk, MAT.Metal)
  -- 天线 + 红灯
  rod(f, (cf * CF(-5, H + 8.6, 5)).Position, (cf * CF(-5, H + 16, 5)).Position, 0.12, COL.steelDk)
  glow(f, (cf * CF(-5, H + 16.3, 5)).Position, RGB(255, 50, 40), 0.4)
  -- 探照灯（往外、往下照）
  local pos = (cf * CF(-2.5, H + 6.4, -6.2)).Position
  lamp(f, pos, cf.LookVector + V(0, -0.28, 0), RGB(255, 238, 206), 1.0, lit and 160 or nil, 32, 2.6)
end

-- 拖车式照明塔：拖车、四个支腿、发电机舱、桅杆、顶上四盏灯（朝 −Z、往下照；lit 的那盏带真光源）
local function lightTower(f, cf, lit)
  P(f, 4.6, 2.4, 8, cf * CF(0, 2.4, 0), COL.yellow, MAT.Metal, true)
  P(f, 4.8, 0.4, 8.4, cf * CF(0, 3.8, 0), COL.yellow:Lerp(COL.steelDk, 0.3), MAT.Metal)
  for _, sx in ipairs({ -2.6, 2.6 }) do CylX(f, 0.9, 2.4, cf * CF(sx, 1.2, 1.2), COL.rubber, MAT.SmoothPlastic) end
  P(f, 0.3, 0.3, 4, cf * CF(0, 1.6, -5.6), COL.steelDk, MAT.Metal)
  for _, o in ipairs({ { -3.4, -3.4 }, { 3.4, -3.4 }, { -3.4, 3.4 }, { 3.4, 3.4 } }) do
    P(f, 0.3, 1.4, 0.3, cf * CF(o[1], 0.7, o[2]), COL.steelDk, MAT.Metal)
    P(f, 2.4, 0.3, 0.3, cf * CF(o[1] * 0.68, 1.3, o[2]), COL.steelDk, MAT.Metal)
  end
  P(f, 0.6, 24, 0.6, cf * CF(0, 15.6, 2.6), COL.steel, MAT.Metal)
  P(f, 7, 0.5, 0.5, cf * CF(0, 27.6, 2.6), COL.steelDk, MAT.Metal)
  for i, x in ipairs({ -2.6, -0.9, 0.9, 2.6 }) do
    local pos = (cf * CF(x, 28.6, 2.3)).Position
    lamp(f, pos, cf.LookVector + V(0, -0.5, 0), COL.lamp, 1.0, (lit and i == 2) and 150 or nil, 75, 2.4)
  end
end

-- 路灯：杆、悬臂、灯头（real：真光源）
local function streetLamp(f, cf, real)
  P(f, 0.5, 14, 0.5, cf * CF(0, 7, 0), COL.steel, MAT.Metal, true)
  P(f, 0.3, 0.3, 3.4, cf * CF(0, 13.8, -1.6), COL.steel, MAT.Metal)
  lamp(f, (cf * CF(0, 13.5, -3.2)).Position, V(0, -1, 0), COL.lamp, 0.8, real and 55 or nil, 110, 1.6)
end

-- 混凝土防空掩体（倒 U 形涵洞 + 顶上沙袋，两头挡墙错开）：顺着 cf 的 X
local function bunker(f, cf)
  P(f, 18, 1, 9, cf * CF(0, 8, 0), COL.conc, MAT.Concrete, true)
  for _, s in ipairs({ -1, 1 }) do P(f, 18, 7.5, 1, cf * CF(0, 3.75, s * 4), COL.conc, MAT.Concrete, true) end
  P(f, 18.4, 1.6, 9.4, cf * CF(0, 9.3, 0), COL.sand, MAT.Fabric, true)
  P(f, 17.4, 1.0, 8.4, cf * CF(0, 10.6, 0), COL.sandDk, MAT.Fabric)
  for _, s in ipairs({ -1, 1 }) do P(f, 1.6, 6, 7, cf * CF(s * 12.2, 3, s * 1.5), COL.sand, MAT.Fabric, true) end
  board(f, cf * CF(0, 6.2, -4.6), 5, 1.4, "防空掩体", COL.yellow, RGB(20, 20, 20))
end

---------------------------------------------------------------- 营房、帐篷、集装箱

-- 集装箱宿舍（CHU，20 尺集装箱改的）：门、窗、窗下空调、台阶、门檐、门灯；正面 −Z
local function chu(f, cf, col, lit)
  local y0 = 0.4
  P(f, 17, 0.4, 7, cf * CF(0, 0.2, 0), COL.concDk, MAT.Concrete)
  P(f, 17, 7.2, 7, cf * CF(0, y0 + 3.6, 0), col, MAT.Metal, true)
  P(f, 17.3, 0.3, 7.3, cf * CF(0, y0 + 7.35, 0), col:Lerp(COL.steelDk, 0.18), MAT.Metal)
  for _, x in ipairs({ -7.2, -1.2, 5.8 }) do P(f, 0.25, 6.6, 0.12, cf * CF(x, y0 + 3.6, -3.55), col:Lerp(COL.steelDk, 0.12), MAT.Metal) end
  P(f, 3, 6.2, 0.15, cf * CF(-4.2, y0 + 3.2, -3.56), COL.door, MAT.Metal)
  P(f, 3.6, 2.6, 0.12, cf * CF(2.4, y0 + 4.5, -3.55), COL.frame, MAT.SmoothPlastic)
  P(f, 3.1, 2.1, 0.16, cf * CF(2.4, y0 + 4.5, -3.57), COL.glass, MAT.Glass)
  P(f, 2.6, 2.0, 1.4, cf * CF(2.4, y0 + 2.0, -4.25), COL.ac, MAT.Metal)
  P(f, 2.1, 1.5, 0.1, cf * CF(2.4, y0 + 2.0, -4.97), COL.acGr, MAT.DiamondPlate)
  P(f, 3.4, 0.35, 1.4, cf * CF(-4.2, 0.85, -4.3), COL.steelDk, MAT.DiamondPlate)
  P(f, 4.6, 0.2, 2.4, cf * CF(-4.2, y0 + 6.8, -4.6) * ANG(-0.12, 0, 0), COL.tin, MAT.Metal)
  local lamp = P(f, 0.5, 0.3, 0.3, cf * CF(-4.2, y0 + 6.45, -3.75), COL.lamp, MAT.Neon)
  if lit then
    local L = Instance.new("PointLight")
    L.Color, L.Range, L.Brightness, L.Shadows = COL.lamp, 14, 0.8, false
    L.Parent = lamp
  end
end

-- 拱形帐篷（TEMPER / 阿拉斯加帐篷）：顺着 cf 的 X；两头门斗、门帘，旁边一台空调机（ECU）两根风管，几根拉绳
local function temper(f, cf, len, col, label)
  local R, cy = 10.5, -2
  CylX(f, len, R * 2, cf * CF(0, cy, 0), col, MAT.Fabric, true)
  for x = -len / 2 + 4, len / 2 - 4, 8 do CylX(f, 0.35, R * 2 + 0.25, cf * CF(x, cy, 0), col:Lerp(COL.steelDk, 0.18), MAT.Fabric) end
  for _, s in ipairs({ -1, 1 }) do
    P(f, 3.2, 7, 7, cf * CF(s * (len / 2 + 1.5), 3.5, 0), col:Lerp(COL.steelDk, 0.08), MAT.Fabric, true)
    P(f, 0.2, 5.6, 3.6, cf * CF(s * (len / 2 + 3.15), 2.8, 0), COL.door, MAT.Fabric)
  end
  local e = cf * CF(len / 4, 0, R + 4.5)
  P(f, 5, 3.6, 3.4, e * CF(0, 1.9, 0), COL.gen, MAT.Metal, true)
  P(f, 4, 2.4, 0.1, e * CF(0, 2.1, -1.72), COL.acGr, MAT.DiamondPlate)
  for _, dx in ipairs({ -1.2, 1.2 }) do CylZ(f, 4, 1.4, e * CF(dx, 3.2, -3.4), COL.duct, MAT.Fabric) end
  for _, s in ipairs({ -1, 1 }) do
    for _, x in ipairs({ -len / 3, 0, len / 3 }) do
      rod(f, (cf * CF(x, 6.5, s * 8.3)).Position, (cf * CF(x, 0.2, s * 14)).Position, 0.08, COL.canvas, MAT.Fabric)
    end
  end
  if label then board(f, cf * CF(len / 2 + 3.3, 6.2, 0) * ANG(0, -PI / 2, 0), 6, 1.4, label, COL.white, RGB(30, 30, 30)) end
end

-- 拱顶大棚（维修棚、仓库）：顺着 cf 的 Z 是纵深，口朝 −Z；门是深色的卷帘
local function clamshell(f, cf, len, R, col)
  local cy = -R * 0.22
  CylZ(f, len, R * 2, cf * CF(0, cy, 0), col or COL.tent, MAT.Fabric, true)
  for z = -len / 2 + 6, len / 2 - 6, 10 do CylZ(f, 0.5, R * 2 + 0.3, cf * CF(0, cy, z), (col or COL.tent):Lerp(COL.steelDk, 0.22), MAT.Metal) end
  local hgt = R + cy
  P(f, R * 1.1, hgt * 0.8, 0.4, cf * CF(0, hgt * 0.4, -len / 2 - 0.15), RGB(56, 58, 56), MAT.CorrodedMetal)
  P(f, R * 1.2, 0.6, 0.6, cf * CF(0, hgt * 0.8 + 0.3, -len / 2 - 0.3), COL.steelDk, MAT.Metal)
  glow(f, (cf * CF(-R * 0.4, hgt * 0.85, -len / 2 - 0.8)).Position, COL.lamp, 0.6)
  glow(f, (cf * CF(R * 0.4, hgt * 0.85, -len / 2 - 0.8)).Position, COL.lamp, 0.6)
end

-- 集装箱（20 尺 / 40 尺）：箱体、几道瓦楞、门那头的锁杆
local function conex(f, cf, long, col)
  local L = long and 33.6 or 17
  P(f, L, 7.2, 6.8, cf * CF(0, 3.6, 0), col, MAT.Metal, true)
  for x = -L / 2 + 2.5, L / 2 - 2.5, long and 5 or 4 do
    P(f, 0.3, 6.6, 6.9, cf * CF(x, 3.6, 0), col:Lerp(COL.steelDk, 0.12), MAT.Metal)
  end
  for _, z in ipairs({ -1.6, 1.6 }) do P(f, 0.12, 6.4, 0.18, cf * CF(L / 2 + 0.05, 3.6, z), COL.steelDk, MAT.Metal) end
end

-- 托盘 + 一摞箱子
local function palletStack(f, cf, kind)
  P(f, 4.4, 0.5, 4.4, cf * CF(0, 0.25, 0), COL.pallet, MAT.WoodPlanks, true)
  if kind == 1 then   -- 弹药箱
    for i = 0, 2 do
      for j = 0, 1 do P(f, 3.9, 1.1, 1.9, cf * CF(0, 1.05 + i * 1.15, -1 + j * 2), COL.crate:Lerp(COL.olive, (i + j) % 2 * 0.3), MAT.Wood, true) end
    end
  elseif kind == 2 then   -- 一桶桶水
    for i = 0, 1 do
      for j = 0, 1 do CylV(f, 2.2, 1.9, cf * CF(-1 + i * 2, 1.6, -1 + j * 2), COL.blue:Lerp(COL.white, 0.4), MAT.Plastic) end
    end
  else   -- 纸箱 / 口粮
    P(f, 4, 3.2, 4, cf * CF(0, 2.1, 0), RGB(150, 128, 92), MAT.Cardboard, true)
    P(f, 4.1, 0.15, 4.1, cf * CF(0, 1.4, 0), RGB(60, 60, 58), MAT.Plastic)
  end
end

-- 一组油桶（几个倒在地上）
local function drums(f, cf, n, col)
  for i = 1, n do
    local x, z = ((i - 1) % 3) * 2.3, math.floor((i - 1) / 3) * 2.3
    if i == n and n > 4 then
      CylX(f, 3.2, 2.2, cf * CF(x + 1, 1.1, z + 2.6) * ANG(0, 0.6, 0), col, MAT.Metal)
    else
      CylV(f, 3.2, 2.2, cf * CF(x, 1.6, z), col, MAT.Metal, true)
      CylV(f, 0.1, 2.25, cf * CF(x, 2.2, z), col:Lerp(COL.steelDk, 0.3), MAT.Metal)
    end
  end
end

-- 发电机组：箱体、百叶、排气管、控制面板（绿灯）、底座
local function genset(f, cf)
  P(f, 6.4, 0.5, 12.6, cf * CF(0, 0.25, 0), COL.steelDk, MAT.Metal, true)
  P(f, 6, 4.2, 12, cf * CF(0, 2.6, 0), COL.gen, MAT.Metal, true)
  P(f, 6.2, 0.4, 12.2, cf * CF(0, 4.9, 0), COL.gen:Lerp(COL.steelDk, 0.25), MAT.Metal)
  for _, s in ipairs({ -1, 1 }) do
    for _, z in ipairs({ -3.4, 0, 3.4 }) do P(f, 0.1, 2.4, 2.6, cf * CF(s * 3.05, 2.8, z), COL.acGr, MAT.DiamondPlate) end
  end
  CylV(f, 3, 0.7, cf * CF(1.6, 6.4, 4), COL.steelDk, MAT.Metal)
  P(f, 2, 1.6, 0.1, cf * CF(-1.4, 3, -6.05), RGB(40, 42, 44), MAT.SmoothPlastic)
  glow(f, (cf * CF(-0.8, 3.4, -6.2)).Position, RGB(80, 255, 120), 0.25)
end

-- 流动厕所（一排）
local function johns(f, cf, n)
  local cols = { RGB(56, 102, 164), RGB(70, 120, 76), RGB(178, 160, 120) }
  for i = 0, n - 1 do
    local c = cf * CF((i - (n - 1) / 2) * 4, 0, 0)
    local col = cols[(i % 3) + 1]
    P(f, 3.4, 7.4, 3.4, c * CF(0, 3.7, 0), col, MAT.Plastic, true)
    P(f, 3.7, 0.4, 3.7, c * CF(0, 7.6, 0), col:Lerp(COL.white, 0.5), MAT.Plastic)
    P(f, 2.4, 6.2, 0.1, c * CF(0, 3.3, -1.72), col:Lerp(COL.steelDk, 0.15), MAT.Plastic)
    CylV(f, 1.6, 0.4, c * CF(1, 8.4, 1), RGB(40, 40, 40), MAT.Plastic)
  end
end

-- 卫浴拖车（淋浴 / 厕所 / 洗衣）：白色长拖车、三扇门、台阶、空调、牌子
local function trailer(f, cf, label)
  P(f, 30, 8, 8.6, cf * CF(0, 5, 0), RGB(226, 224, 216), MAT.Metal, true)
  P(f, 30.4, 0.4, 9, cf * CF(0, 9.2, 0), RGB(190, 188, 180), MAT.Metal)
  P(f, 26, 1, 6, cf * CF(0, 0.5, 0), COL.steelDk, MAT.Metal)
  for i, x in ipairs({ -9, 0, 9 }) do
    P(f, 2.8, 6, 0.15, cf * CF(x, 4.6, -4.35), COL.door, MAT.Metal)
    P(f, 3.6, 1.6, 2.4, cf * CF(x, 0.8, -5.6), COL.steelDk, MAT.DiamondPlate, true)
    glow(f, (cf * CF(x, 8.2, -4.6)).Position, COL.lamp, 0.35)
    if i ~= 2 then P(f, 2.4, 1.8, 1.2, cf * CF(x + 4.5, 7.5, -4.9), COL.ac, MAT.Metal) end
  end
  board(f, cf * CF(0, 8.4, -4.46), 6, 1.3, label, COL.blue, COL.white)
end

-- 水罐（钢架水塔）
local function waterTower(f, cf)
  for _, o in ipairs({ { -3.4, -3.4 }, { 3.4, -3.4 }, { -3.4, 3.4 }, { 3.4, 3.4 } }) do P(f, 0.6, 14, 0.6, cf * CF(o[1], 7, o[2]), COL.steel, MAT.Metal, true) end
  for s = 0, 3 do
    local r = cf * ANG(0, s * PI / 2, 0)
    rod(f, (r * CF(-3.4, 2, -3.4)).Position, (r * CF(3.4, 12, -3.4)).Position, 0.2, COL.steelDk)
  end
  CylV(f, 9, 11, cf * CF(0, 18.5, 0), RGB(214, 210, 198), MAT.Metal, true)
  CylV(f, 0.6, 11.4, cf * CF(0, 23.3, 0), RGB(170, 166, 156), MAT.Metal)
  rod(f, (cf * CF(4.2, 0, 4.2)).Position, (cf * CF(4.2, 23, 4.2)).Position, 0.2, COL.steelDk)
  board(f, cf * CF(0, 18.5, -5.6), 5, 1.4, "饮用水", COL.blue, COL.white)
end

-- 拉线天线杆：红白相间、三向拉线（两层）、地锚、顶上红灯一闪一闪
local function mast(f, cf, h)
  CylV(f, h, 1.0, cf * CF(0, h / 2, 0), COL.white, MAT.Metal, true)
  for k = 1, 3 do CylV(f, h / 7, 1.05, cf * CF(0, h * (2 * k - 1) / 7 + h / 14, 0), COL.red, MAT.Metal) end
  for k = 0, 2 do
    local a = k * 2 * PI / 3 + 0.4
    local anchor = (cf * CF(math.cos(a) * h * 0.42, 0.3, math.sin(a) * h * 0.42)).Position
    for _, t in ipairs({ 0.5, 0.92 }) do rod(f, (cf * CF(0, h * t, 0)).Position, anchor, 0.1, RGB(150, 150, 150)) end
    P(f, 1.4, 0.6, 1.4, CF(anchor), COL.concDk, MAT.Concrete)
  end
  local l = W.light(f, (cf * CF(0, h + 0.8, 0)).Position, RGB(255, 40, 40), 1.1, 18, 1.4)
  l:SetAttribute("Anim", "blink")
  l:SetAttribute("Spd", 0.7)
end

-- 卫星天线：底座、立柱、斜朝天的碟、馈源支臂
local function dish(f, cf, d)
  P(f, d * 0.5, 0.6, d * 0.5, cf * CF(0, 0.3, 0), COL.concDk, MAT.Concrete, true)
  CylV(f, d * 0.45, 0.6, cf * CF(0, d * 0.25, 0), COL.steel, MAT.Metal)
  local dc = cf * CF(0, d * 0.55, 0) * ANG(math.rad(38), 0, 0)
  CylZ(f, 0.35, d, dc, RGB(226, 226, 220), MAT.SmoothPlastic, true)
  CylZ(f, 0.5, d * 0.25, dc * CF(0, 0, 0.3), COL.steel, MAT.Metal)
  local tip = (dc * CF(0, 0, -d * 0.42)).Position
  for _, o in ipairs({ { 0, d * 0.42 }, { d * 0.36, -d * 0.2 }, { -d * 0.36, -d * 0.2 } }) do
    rod(f, (dc * CF(o[1], o[2], -0.1)).Position, tip, 0.12, COL.steelDk)
  end
  P(f, 0.6, 0.6, 0.9, CF(tip) * (dc - dc.Position), COL.steelDk, MAT.Metal)
end

---------------------------------------------------------------- 车（装饰：停着的卡车、悍马式轻车、叉车、油罐车）

local function lightTruck(f, cf, col)   -- 轻型越野车
  col = col or COL.sand:Lerp(COL.olive, 0.25)
  P(f, 7, 2.2, 15, cf * CF(0, 2.6, 0), col, MAT.Metal, true)
  P(f, 6.6, 2.2, 7, cf * CF(0, 4.8, 1), col, MAT.Metal, true)
  P(f, 6, 1.6, 0.2, cf * CF(0, 4.9, -2.55) * ANG(-0.3, 0, 0), COL.glass, MAT.Glass)
  for _, o in ipairs({ { -3.4, -5 }, { 3.4, -5 }, { -3.4, 5 }, { 3.4, 5 } }) do CylX(f, 1.4, 3, cf * CF(o[1], 1.5, o[2]), COL.rubber, MAT.SmoothPlastic) end
  P(f, 1.4, 1.4, 1.4, cf * CF(0, 6.6, 2), COL.steelDk, MAT.Metal)   -- 车顶武器站
end
local function cargoTruck(f, cf, kind)   -- 卡车：cargo 篷布、fuel 油罐、wrecker 吊车
  local col = COL.sand:Lerp(COL.olive, 0.3)
  P(f, 7, 5, 6, cf * CF(0, 4.4, -9), col, MAT.Metal, true)
  P(f, 6.4, 1.8, 0.2, cf * CF(0, 5.4, -12.05), COL.glass, MAT.Glass)
  P(f, 7.2, 1.2, 20, cf * CF(0, 2.6, 2), COL.steelDk, MAT.Metal, true)
  if kind == "fuel" then
    CylZ(f, 15, 5.6, cf * CF(0, 5.8, 3), RGB(170, 168, 156), MAT.Metal, true)
    board(f, cf * CF(0, 6.2, 10.6) * ANG(0, PI, 0), 3.6, 1.2, "易燃", COL.red, COL.white)
  elseif kind == "wrecker" then
    P(f, 3, 3, 8, cf * CF(0, 4.6, 6), COL.yellow, MAT.Metal, true)
    rod(f, (cf * CF(0, 6, 4)).Position, (cf * CF(0, 13, 12)).Position, 0.9, COL.yellow)
    rod(f, (cf * CF(0, 13, 12)).Position, (cf * CF(0, 5, 13)).Position, 0.12, COL.steelDk)
  else
    P(f, 7, 6, 15, cf * CF(0, 6.2, 3), COL.canvas, MAT.Fabric, true)
  end
  for _, z in ipairs({ -8, 4, 9 }) do
    for _, s in ipairs({ -1, 1 }) do CylX(f, 1.6, 3.6, cf * CF(s * 3.3, 1.8, z), COL.rubber, MAT.SmoothPlastic) end
  end
end
local function forklift(f, cf)
  P(f, 4, 3, 6, cf * CF(0, 2, 0), COL.yellow, MAT.Metal, true)
  P(f, 3.6, 0.3, 4, cf * CF(0, 5.6, 0.6), COL.steelDk, MAT.Metal)
  for _, x in ipairs({ -1.6, 1.6 }) do P(f, 0.3, 4, 0.3, cf * CF(x, 3.9, 2.4), COL.steelDk, MAT.Metal) end
  for _, x in ipairs({ -1.4, 1.4 }) do P(f, 0.3, 6.5, 0.4, cf * CF(x, 3.6, -3.2), COL.steelDk, MAT.Metal) end
  for _, x in ipairs({ -0.9, 0.9 }) do P(f, 0.5, 0.2, 4, cf * CF(x, 0.6, -5), COL.steelDk, MAT.Metal) end
  for _, o in ipairs({ { -2, -1.8 }, { 2, -1.8 }, { -2, 1.8 }, { 2, 1.8 } }) do CylX(f, 0.8, 1.8, cf * CF(o[1], 0.9, o[2]), COL.rubber, MAT.SmoothPlastic) end
end

---------------------------------------------------------------- 大件：检查站、指挥中心、食堂、油料库、弹药库、直升机坪、维修区

-- 车辆检查站（ECP）：cf 在围墙正门的中点，−Z 朝外；两条车道（进 / 出）中间一排水泥墩隔开
local function ecp(f, cf, team)
  for k = 0, 8 do jersey(f, cf * CF(0, 0, -6 - k * 8.7) * ANG(0, PI / 2, 0)) end
  -- 之字形：两条车道各四排、左右交替，车得减速绕过去
  for _, lane in ipairs({ { -30, -2 }, { 2, 30 } }) do
    for k = 0, 3 do
      local z = -44 - k * 28
      local left = (k % 2 == 0)
      local x1 = left and lane[1] or (lane[2] - 17)
      for j = 0, 1 do jersey(f, cf * CF(x1 + 4.2 + j * 8.6, 0, z), (j == 0 and k % 2 == 0) and COL.jersey:Lerp(COL.red, 0.15) or nil) end
    end
    local mid = (lane[1] + lane[2]) / 2
    for _, z in ipairs({ -22, -160 }) do   -- 减速带（黄黑）
      P(f, 26, 0.35, 1.6, cf * CF(mid, 0.17, z), COL.yellow, MAT.SmoothPlastic, true)
      for x = -11, 11, 4.4 do P(f, 2.2, 0.36, 1.62, cf * CF(mid + x, 0.17, z), RGB(30, 30, 30), MAT.SmoothPlastic) end
    end
    P(f, 26, 0.18, 0.8, cf * CF(mid, 0.1, -30), RGB(70, 70, 70), MAT.DiamondPlate)   -- 阻车钉（收着）
    -- 抬杆：立柱 + 红白杆（抬起来）
    local px = lane[1] < 0 and lane[1] + 1 or lane[2] - 1
    P(f, 1, 3.6, 1, cf * CF(px, 1.8, -3), COL.steelDk, MAT.Metal, true)
    for k = 0, 4 do   -- 抬起来：往上、稍微斜向车道
      local seg = cf * CF(px, 3.4, -3) * ANG(0, 0, (px < 0 and -1 or 1) * 0.22) * CF(0, 1.3 + k * 2.6, 0)
      P(f, 0.35, 2.6, 0.35, seg, (k % 2 == 0) and COL.red or COL.white, MAT.SmoothPlastic)
    end
  end
  -- 检查棚：内车道上面四根柱、顶棚、底下两盏灯
  for _, o in ipairs({ { -28, -12 }, { -4, -12 }, { -28, -40 }, { -4, -40 } }) do P(f, 0.8, 13, 0.8, cf * CF(o[1], 6.5, o[2]), COL.steel, MAT.Metal, true) end
  P(f, 28, 0.6, 32, cf * CF(-16, 13.3, -26), COL.tin, MAT.Metal)
  P(f, 28.4, 1.4, 0.4, cf * CF(-16, 12.6, -42.1), COL.yellow, MAT.Metal)
  for _, z in ipairs({ -18, -34 }) do lamp(f, (cf * CF(-16, 12.6, z)).Position, V(0, -1, 0), RGB(255, 240, 214), 1.2, 60, 120, 1.8) end
  -- 岗亭（中间隔离墩那头）：混凝土小房、窗、顶、沙袋三面
  local gh = cf * CF(0, 0, -8)
  P(f, 6, 8, 6, gh * CF(0, 4, -4), COL.conc, MAT.Concrete, true)
  P(f, 7, 0.6, 7, gh * CF(0, 8.3, -4), COL.tin, MAT.Metal)
  for _, s in ipairs({ -1, 1 }) do P(f, 0.15, 2.4, 4, gh * CF(s * 3.05, 5.4, -4), COL.glass, MAT.Glass) end
  P(f, 4, 2.4, 0.15, gh * CF(0, 5.4, -7.05), COL.glass, MAT.Glass)
  glow(f, (gh * CF(0, 7.6, -7.4)).Position, COL.lamp, 0.4)
  -- 外面的沙袋碉堡（盯着来车）：一圈沙袋、顶、机枪
  for _, s in ipairs({ -1, 1 }) do
    local bk = cf * CF(s * 48, 0, -70) * ANG(0, s * 0.35, 0)
    bags(f, bk * CF(0, 0, -5), 12, 4.4, 2.4)
    bags(f, bk * CF(-6, 0, 0) * ANG(0, PI / 2, 0), 10, 4.4, 2.4)
    bags(f, bk * CF(6, 0, 0) * ANG(0, PI / 2, 0), 10, 4.4, 2.4)
    P(f, 14, 0.8, 12, bk * CF(0, 6.6, 0), COL.ply, MAT.WoodPlanks)
    P(f, 14.4, 1.2, 12.4, bk * CF(0, 7.6, 0), COL.sand, MAT.Fabric)
    P(f, 0.3, 0.3, 4, bk * CF(0, 5, -7), COL.steelDk, MAT.Metal)
  end
  -- 铁丝网顺着车道外沿一路拉出去
  for _, s in ipairs({ -1, 1 }) do wire(f, cf * CF(s * 36, 0, -95) * ANG(0, PI / 2, 0), 170) end
  -- 牌子
  local sgn = cf * CF(0, 0, -178)
  P(f, 0.6, 10, 0.6, sgn * CF(-9, 5, 0), COL.steelDk, MAT.Metal, true)
  P(f, 0.6, 10, 0.6, sgn * CF(9, 5, 0), COL.steelDk, MAT.Metal, true)
  board(f, sgn * CF(0, 8, 0), 20, 4.4, "停车接受检查 · 擅入者开枪", COL.red, COL.white, true)
  board(f, cf * CF(-16, 3.2, -48) * ANG(0, PI, 0), 5, 2.4, "限速 5", COL.white, RGB(20, 20, 20))
  board(f, cf * CF(16, 3.2, -48) * ANG(0, PI, 0), 6, 2.4, "关闭车灯", COL.yellow, RGB(20, 20, 20))
  -- 探照灯杆
  for _, o in ipairs({ { -40, -20 }, { 40, -20 }, { -40, -130 }, { 40, -130 } }) do
    local p = (cf * CF(o[1], 0, o[2])).Position
    floodPole(f, p.X, cf.Position.Y, p.Z, 18, COL.lamp, 100)
  end
  local _ = team
end

-- 战术指挥中心（TOC）：加固的掩体房、外面一圈 HESCO、正门 L 形 T 墙挡着、伪装网、屋顶空调和天线、两台发电机、牌子
local function toc(f, cf)
  P(f, 44, 13, 28, cf * CF(0, 6.5, 0), COL.conc:Lerp(COL.sand, 0.25), MAT.Concrete, true)
  P(f, 45, 1, 29, cf * CF(0, 13.5, 0), COL.concDk, MAT.Concrete)
  P(f, 4, 7.4, 0.3, cf * CF(0, 3.7, -14.1), COL.door, MAT.Metal)
  P(f, 6, 0.6, 3, cf * CF(0, 0.3, -15.6), COL.concDk, MAT.Concrete, true)
  glow(f, (cf * CF(0, 8.2, -14.6)).Position, COL.lamp, 0.5)
  board(f, cf * CF(0, 10.6, -14.3), 14, 2.6, "战术指挥中心 TOC", RGB(36, 40, 44), COL.white)
  -- 伪装网（透一点）+ 四角支杆
  local net = P(f, 58, 0.3, 42, cf * CF(0, 17.6, 0), COL.camo, MAT.Fabric)
  net.Transparency = 0.22
  for _, o in ipairs({ { -28, -20 }, { 28, -20 }, { -28, 20 }, { 28, 20 }, { 0, -20 }, { 0, 20 } }) do
    P(f, 0.4, 17.4, 0.4, cf * CF(o[1], 8.7, o[2]), COL.wood, MAT.Wood)
  end
  for _, x in ipairs({ -14, -4, 6, 16 }) do P(f, 4, 2.6, 3, cf * CF(x, 15.3, 8), COL.ac, MAT.Metal) end
  for _, o in ipairs({ { -18, -8 }, { -12, -6 }, { 12, -8 }, { 18, -6 } }) do rod(f, (cf * CF(o[1], 14, o[2])).Position, (cf * CF(o[1], 24, o[2])).Position, 0.12, COL.steelDk) end
  -- 外圈 HESCO（四面，正面中间留门）
  hesco(f, cf * CF(0, 0, -19), 54, 1, { { -9, 9 } })
  hesco(f, cf * CF(0, 0, 19) * ANG(0, PI, 0), 54, 1)
  hesco(f, cf * CF(-27, 0, 0) * ANG(0, PI / 2, 0), 38, 1)
  hesco(f, cf * CF(27, 0, 0) * ANG(0, -PI / 2, 0), 38, 1)
  twall(f, cf * CF(0, 0, -25), 24)
  twall(f, cf * CF(12.5, 0, -22) * ANG(0, PI / 2, 0), 6)
  -- 发电机组 + 电缆
  for k = 0, 1 do
    local g = cf * CF(-38, 0, -6 + k * 14) * ANG(0, PI / 2, 0)
    genset(f, g)
    rod(f, (g * CF(0, 0.3, 6.5)).Position, (cf * CF(-22.4, 0.3, -6 + k * 14)).Position, 0.5, COL.rubber, MAT.Rubber)
  end
  CylZ(f, 14, 6, cf * CF(-38, 3.2, 16), RGB(176, 172, 160), MAT.Metal, true)   -- 柴油罐
end

-- 天线阵：三根拉线天线杆、两个卫星天线、一辆卫星通信车（方舱）
local function antennaFarm(f, cf)
  mast(f, cf * CF(-20, 0, -10), 62)
  mast(f, cf * CF(22, 0, -4), 48)
  mast(f, cf * CF(0, 0, 24), 40)
  dish(f, cf * CF(-6, 0, 6), 10)
  dish(f, cf * CF(10, 0, 14), 7)
  P(f, 8, 7, 14, cf * CF(16, 3.5, 22), COL.sand:Lerp(COL.olive, 0.3), MAT.Metal, true)
  P(f, 2.4, 2, 2, cf * CF(16, 8, 18), COL.ac, MAT.Metal)
  dish(f, cf * CF(16, 7, 26), 4)
  local fence = cf * CF(0, 0, 6)
  for s = 0, 3 do
    local r = fence * ANG(0, s * PI / 2, 0)
    wire(f, r * CF(0, 0, -34), 68)
  end
end

-- 迫击炮阵地：圆形沙袋墙（八段）、炮、弹药箱
local function mortarPit(f, cf)
  for k = 0, 7 do
    if k ~= 6 then
      local a = k / 8 * PI * 2
      bags(f, cf * CF(math.cos(a) * 9, 0, math.sin(a) * 9) * ANG(0, -a + PI / 2, 0), 7.4, 3.2, 2.2)
    end
  end
  P(f, 3, 0.4, 3, cf * CF(0, 0.2, 0), COL.steelDk, MAT.Metal)
  local tube = cf * CF(0, 2.6, 0) * ANG(math.rad(-30), 0, 0)
  CylV(f, 5.4, 0.8, tube, COL.olive, MAT.Metal)
  rod(f, (cf * CF(-1.2, 0, -1.6)).Position, (tube * CF(0, 0.6, 0)).Position, 0.25, COL.olive)
  rod(f, (cf * CF(1.2, 0, -1.6)).Position, (tube * CF(0, 0.6, 0)).Position, 0.25, COL.olive)
  for i = 0, 2 do P(f, 2.4, 1, 1.2, cf * CF(4 + i * 0.2, 0.5 + i, 3), COL.crate, MAT.Wood, true) end
end

-- 近防炮（陆基「密集阵」）：拖车底盘、白色雷达罩、炮管
local function cram(f, cf)
  P(f, 10, 2, 16, cf * CF(0, 2, 0), COL.sand, MAT.Metal, true)
  for _, o in ipairs({ { -4.4, -6 }, { 4.4, -6 }, { -4.4, 6 }, { 4.4, 6 } }) do P(f, 0.6, 2, 0.6, cf * CF(o[1], 0.6, o[2]), COL.steelDk, MAT.Metal) end
  CylV(f, 3, 5, cf * CF(0, 4.6, 1), RGB(220, 220, 214), MAT.Metal, true)
  CylV(f, 5, 4.2, cf * CF(0, 8.6, 1), RGB(232, 232, 228), MAT.SmoothPlastic, true)
  W.part(f, V(4.2, 4.2, 4.2), cf * CF(0, 11.1, 1), RGB(232, 232, 228), MAT.SmoothPlastic, Enum.PartType.Ball)
  CylZ(f, 7, 1.2, cf * CF(0, 6.6, -4), COL.steelDk, MAT.Metal)
  board(f, cf * CF(0, 2.6, -8.1), 4, 1, "C-RAM", COL.sand, RGB(30, 30, 30))
  hesco(f, cf * CF(0, 0, 14) * ANG(0, PI, 0), 22, 1)
  hesco(f, cf * CF(-11, 0, 4) * ANG(0, PI / 2, 0), 18, 1)
  hesco(f, cf * CF(11, 0, 4) * ANG(0, -PI / 2, 0), 18, 1)
end

-- 食堂（DFAC）：预制长厅、浅坡屋顶、正门雨棚、侧面空调、牌子、后面垃圾箱、外面野餐桌
local function dfac(f, cf)
  local col = RGB(206, 192, 160)
  P(f, 76, 12, 36, cf * CF(0, 6.2, 0), col, MAT.Metal, true)
  Wd(f, 76, 2.6, 18, cf * CF(0, 13.5, -9), col:Lerp(COL.steelDk, 0.25), MAT.Metal)
  Wd(f, 76, 2.6, 18, cf * CF(0, 13.5, 9) * ANG(0, PI, 0), col:Lerp(COL.steelDk, 0.25), MAT.Metal)
  P(f, 76.6, 0.6, 36.6, cf * CF(0, 12.3, 0), col:Lerp(COL.steelDk, 0.35), MAT.Metal)
  for x = -32, 32, 8 do
    if math.abs(x) > 6 then
      P(f, 4.2, 2.8, 0.12, cf * CF(x, 7, -18.02), COL.frame, MAT.SmoothPlastic)
      P(f, 3.6, 2.2, 0.16, cf * CF(x, 7, -18.06), COL.glass, MAT.Glass)
    end
  end
  P(f, 8, 8, 0.2, cf * CF(0, 4, -18.06), COL.door, MAT.Metal)
  P(f, 18, 0.5, 10, cf * CF(0, 10.4, -23), COL.tin, MAT.Metal)
  for _, o in ipairs({ { -8, -27.5 }, { 8, -27.5 } }) do P(f, 0.6, 10.2, 0.6, cf * CF(o[1], 5.1, o[2]), COL.steel, MAT.Metal, true) end
  lamp(f, (cf * CF(0, 9.8, -23)).Position, V(0, -1, 0), COL.lamp, 0.8, 40, 120, 1.4)
  board(f, cf * CF(0, 11.4, -28.2), 16, 2.6, "食堂 DFAC", RGB(150, 40, 36), COL.white)
  for x = -30, 30, 12 do P(f, 3, 2.6, 2.4, cf * CF(x, 1.3, 19.4), COL.ac, MAT.Metal, true) end
  for k = 0, 1 do
    P(f, 10, 5, 6, cf * CF(26 + k * 12, 2.5, 26), RGB(56, 92, 62), MAT.Metal, true)
    P(f, 10.2, 0.4, 6.4, cf * CF(26 + k * 12, 5.2, 26) * ANG(0.1, 0, 0), RGB(46, 76, 52), MAT.Metal)
  end
  for k = 0, 3 do   -- 外面的野餐桌（遮阳棚下）
    local t = cf * CF(-30 + k * 12, 0, -36)
    P(f, 8, 0.3, 3, t * CF(0, 2.6, 0), COL.wood, MAT.WoodPlanks)
    for _, s in ipairs({ -1, 1 }) do P(f, 8, 0.25, 1.2, t * CF(0, 1.6, s * 2.6), COL.wood, MAT.WoodPlanks) end
    for _, x in ipairs({ -3.4, 3.4 }) do P(f, 0.4, 2.4, 6, t * CF(x, 1.2, 0), COL.steelDk, MAT.Metal) end
  end
  local shade = P(f, 52, 0.3, 10, cf * CF(-12, 9, -36), COL.canvas, MAT.Fabric)
  shade.Transparency = 0.15
  for _, x in ipairs({ -36, -12, 12 }) do
    for _, z in ipairs({ -31.5, -40.5 }) do P(f, 0.4, 9, 0.4, cf * CF(x, 4.5, z), COL.steel, MAT.Metal) end
  end
end

-- 油囊（枕头形：中间一块 + 两边圆边）
local function bladder(f, cf, l, w)
  P(f, l, 3.4, w - 3.4, cf * CF(0, 1.7, 0), RGB(40, 42, 40), MAT.Rubber, true)
  for _, s in ipairs({ -1, 1 }) do CylX(f, l, 3.4, cf * CF(0, 1.7, s * (w / 2 - 1.7)), RGB(40, 42, 40), MAT.Rubber, true) end
  CylV(f, 1.2, 1.2, cf * CF(l / 2 - 2, 3.6, 0), COL.steel, MAT.Metal)
end
-- 油料库：土堤围着三个油囊、泵站、管线、加油点、灭火器、禁烟牌、灯
local function fuelFarm(f, cf)
  for s = 0, 3 do
    local r = cf * ANG(0, s * PI / 2, 0)
    local long = (s % 2 == 0)
    berm(f, r * CF(0, 0, -(long and 26 or 38)), long and 80 or 56, 5, 12)
  end
  for k = -1, 1 do bladder(f, cf * CF(0, 0, k * 14), 22, 11) end
  local pump = cf * CF(44, 0, -14)
  P(f, 7, 3.4, 4.6, pump * CF(0, 1.7, 0), COL.yellow:Lerp(COL.steelDk, 0.2), MAT.Metal, true)
  CylX(f, 3, 2, pump * CF(0, 3.8, 0), COL.steel, MAT.Metal)
  rod(f, (cf * CF(11, 0.6, -14)).Position, (pump * CF(-3.5, 0.6, 0)).Position, 0.7, COL.rubber, MAT.Rubber)
  rod(f, (cf * CF(11, 0.6, 0)).Position, (cf * CF(30, 0.6, -10)).Position, 0.7, COL.rubber, MAT.Rubber)
  for k = 0, 1 do
    local n = pump * CF(10 + k * 6, 0, 2)
    P(f, 1.4, 4.4, 1.4, n * CF(0, 2.2, 0), COL.red, MAT.Metal, true)
    CylZ(f, 1.2, 2, n * CF(0, 3.2, 1.2), COL.rubber, MAT.Rubber)
  end
  for _, o in ipairs({ { 36, -2 }, { -36, -22 } }) do P(f, 0.8, 1.8, 0.8, cf * CF(o[1], 0.9, o[2]), COL.red, MAT.SmoothPlastic, true) end
  board(f, cf * CF(30, 4, -32) * ANG(0, PI, 0), 8, 2.4, "严禁烟火", COL.red, COL.white, true)
  P(f, 0.4, 2.8, 0.4, cf * CF(30, 1.4, -32), COL.steelDk, MAT.Metal)
  floodPole(f, (cf * CF(44, 0, 10)).Position.X, cf.Position.Y, (cf * CF(44, 0, 10)).Position.Z, 16, COL.lamp, 80)
end

-- 弹药库：三个 U 形土堤隔开的弹药格（口朝 −Z），格里托盘弹药箱、一个集装箱；避雷针、红牌子
local function ammoPoint(f, cf)
  for k = -1, 1 do
    local c = cf * CF(k * 34, 0, 0)
    berm(f, c * CF(0, 0, 14), 30, 7, 12)
    berm(f, c * CF(-14, 0, 0) * ANG(0, PI / 2, 0), 26, 7, 10)
    berm(f, c * CF(14, 0, 0) * ANG(0, PI / 2, 0), 26, 7, 10)
    for i = 0, 2 do palletStack(f, c * CF(-6 + i * 6, 0, 2) * ANG(0, (i - 1) * 0.08, 0), 1) end
    if k == 0 then conex(f, c * CF(0, 0, -4) * ANG(0, 0, 0), false, CONEX[2]) end
    rod(f, (c * CF(10, 0, 8)).Position, (c * CF(10, 26, 8)).Position, 0.3, COL.steelDk)
  end
  board(f, cf * CF(0, 4, -22), 12, 2.6, "危险 · 弹药库", COL.red, COL.white, true)
  for _, x in ipairs({ -4, 4 }) do P(f, 0.4, 3, 0.4, cf * CF(x, 1.5, -22), COL.steelDk, MAT.Metal) end
  wire(f, cf * CF(0, 0, -30), 110)
end

-- 直升机坪（细）：方形混凝土坪（只高出地面一点：召唤位按地面摆）、黄圈、白 H、八盏绿边灯、两盏白泛光
local function helipad(f, cf)
  P(f, 44, 0.3, 44, cf * CF(0, -0.07, 0), RGB(150, 148, 140), MAT.Concrete)
  CylV(f, 0.06, 34, cf * CF(0, 0.11, 0), COL.yellow, MAT.SmoothPlastic)
  CylV(f, 0.07, 31, cf * CF(0, 0.12, 0), RGB(150, 148, 140), MAT.Concrete)
  for _, s in ipairs({ { -4, 0, 2, 14 }, { 4, 0, 2, 14 }, { 0, 0, 6, 2 } }) do P(f, s[3], 0.08, s[4], cf * CF(s[1], 0.15, s[2]), COL.white, MAT.SmoothPlastic) end
  for k = 0, 7 do
    local a = k * PI / 4
    glow(f, (cf * CF(math.cos(a) * 21, 0.5, math.sin(a) * 21)).Position, RGB(90, 255, 130), 0.4)
  end
end

-- 维修区：两座拱顶维修棚、洗车台、零件集装箱、轮胎堆、工具箱、吊车
local function maintenance(f, cf)
  clamshell(f, cf * CF(-60, 0, 0), 64, 30, COL.tent)
  clamshell(f, cf * CF(10, 0, 0), 64, 30, COL.tentDk)
  -- 洗车台：混凝土台、排水沟、两根水管架
  local wr = cf * CF(78, 0, -4)
  P(f, 30, 0.6, 44, wr * CF(0, 0.1, 0), COL.concDk, MAT.Concrete, true)
  for _, x in ipairs({ -8, 8 }) do P(f, 1.2, 0.2, 44, wr * CF(x, 0.42, 0), RGB(40, 40, 40), MAT.DiamondPlate) end
  for _, z in ipairs({ -14, 14 }) do
    P(f, 0.5, 9, 0.5, wr * CF(-15.5, 4.5, z), COL.steel, MAT.Metal)
    P(f, 0.5, 9, 0.5, wr * CF(15.5, 4.5, z), COL.steel, MAT.Metal)
    P(f, 31, 0.4, 0.4, wr * CF(0, 9, z), COL.blue, MAT.Metal)
  end
  board(f, wr * CF(0, 3, -23), 8, 1.6, "洗车台", COL.blue, COL.white)
  for k = 0, 4 do conex(f, cf * CF(-90 + k * 19, 0, 52) * ANG(0, PI / 2, 0), false, CONEX[(k % #CONEX) + 1]) end
  for k = 0, 2 do   -- 轮胎堆
    local t = cf * CF(48 + k * 6, 0, 40)
    for i = 0, 3 do CylV(f, 1.4, 5, t * CF(0, 0.7 + i * 1.4, 0), COL.rubber, MAT.Rubber) end
  end
  for k = 0, 3 do P(f, 3, 3.6, 1.8, cf * CF(-36 + k * 4, 1.8, 36), RGB(178, 40, 36), MAT.Metal, true) end   -- 红色工具柜
  cargoTruck(f, cf * CF(40, 0, -40) * ANG(0, 0.2, 0), "wrecker")
  drums(f, cf * CF(-30, 0, -40), 7, RGB(64, 84, 58))
  board(f, cf * CF(-60, 22, -32.4), 14, 2.4, "车辆维修", COL.white, RGB(30, 30, 30))
end

---------------------------------------------------------------- 机场（营区后面，跑道顺着基地坐标的 X、世界的东西向）

local function airfield(f, B0, R, team, yaw)
  local RZ, len, wid = R.lz, R.len, R.wid
  local function L(lx, lz, yaw) return B0 * CF(lx, 0, lz) * ANG(0, yaw or 0, 0) end
  -- 跑道：分段（零件最长 2048），顶面只高出地面 0.25（召唤位按地面摆）
  for i = 0, 1 do P(f, len / 2, 0.5, wid, L(-len / 4 + i * len / 2, RZ), COL.asphalt, MAT.Asphalt, true) end
  for x = -len / 2 + 60, len / 2 - 60, 48 do P(f, 22, 0.06, 1.4, L(x, RZ) * CF(0, 0.28, 0), COL.paint, MAT.SmoothPlastic) end
  for _, s in ipairs({ -1, 1 }) do
    for i = 0, 1 do P(f, len / 2, 0.06, 1.2, L(-len / 4 + i * len / 2, RZ + s * (wid / 2 - 3)) * CF(0, 0.28, 0), COL.paint, MAT.SmoothPlastic) end
    local ex = s * (len / 2 - 14)
    for k = -4, 4 do if k ~= 0 then P(f, 34, 0.06, 4, L(ex - s * 12, RZ + k * wid / 10) * CF(0, 0.28, 0), COL.paint, MAT.SmoothPlastic) end end   -- 入口的斑马线
    for _, d in ipairs({ 300, 600, 900 }) do   -- 接地带标志
      for _, zz in ipairs({ -1, 1 }) do P(f, 30, 0.06, 3, L(s * (len / 2 - d), RZ + zz * 14) * CF(0, 0.28, 0), COL.paint, MAT.SmoothPlastic) end
    end
    P(f, 60, 0.06, 8, L(s * (len / 2 - 420), RZ - 18) * CF(0, 0.28, 0), COL.paint, MAT.SmoothPlastic)   -- 瞄准点
    P(f, 60, 0.06, 8, L(s * (len / 2 - 420), RZ + 18) * CF(0, 0.28, 0), COL.paint, MAT.SmoothPlastic)
    -- 跑道号（平放在跑道头）
    local nb = P(f, 26, 0.06, 18, L(s * (len / 2 - 70), RZ) * CF(0, 0.29, 0) * ANG(0, s > 0 and -PI / 2 or PI / 2, 0), COL.asphalt, MAT.Asphalt)
    local sg = Instance.new("SurfaceGui")
    sg.Face = Enum.NormalId.Top
    sg.CanvasSize = Vector2.new(260, 180)
    sg.Parent = nb
    local t = Instance.new("TextLabel")
    t.Size = UDim2.fromScale(1, 1)
    t.BackgroundTransparency = 1
    t.TextScaled = true
    t.Font = Enum.Font.GothamBlack
    t.TextColor3 = COL.paint
    t.Text = ((s > 0) == (team == "atk")) and "27" or "09"
    t.Parent = sg
  end
  -- 平行滑行道、三条联络道（黄中线）
  local TZ = RZ - 110
  for i = 0, 1 do P(f, 1500, 0.4, 34, L(-750 + i * 1500, TZ), COL.asphalt:Lerp(COL.gravel, 0.12), MAT.Asphalt, true) end
  for i = 0, 1 do P(f, 1500, 0.06, 0.8, L(-750 + i * 1500, TZ) * CF(0, 0.23, 0), COL.yellow, MAT.SmoothPlastic) end
  for _, x in ipairs({ -1400, 0, 1400 }) do
    P(f, 30, 0.4, 66, L(x, RZ - 77) * CF(0, -0.02, 0), COL.asphalt:Lerp(COL.gravel, 0.12), MAT.Asphalt, true)
    P(f, 0.8, 0.06, 66, L(x, RZ - 77) * CF(0, 0.23, 0), COL.yellow, MAT.SmoothPlastic)
  end
  -- 停机坪：滑行道和营区之间两大块（东、西），系留点、停机线
  for _, s in ipairs({ -1, 1 }) do
    local cx = s * 900
    P(f, 640, 0.4, 230, L(cx, RZ - 245), COL.conc, MAT.Concrete, true)
    for k = -3, 3 do
      P(f, 0.8, 0.06, 60, L(cx + k * 80, RZ - 245) * CF(0, 0.23, 0), COL.yellow, MAT.SmoothPlastic)
      P(f, 4, 0.06, 0.8, L(cx + k * 80, RZ - 215) * CF(0, 0.23, 0), COL.yellow, MAT.SmoothPlastic)
    end
  end
  -- 加固机库（HAS）：西边停机坪北沿一排四座，口朝跑道
  for k = 0, 3 do
    local h = L(-1150 + k * 110, RZ - 420)
    CylZ(f, 56, 48, h * CF(0, -8, 0), RGB(150, 146, 134), MAT.Concrete, true)
    P(f, 40, 15, 0.8, h * CF(0, 7.5, 28.2), RGB(84, 88, 86), MAT.CorrodedMetal, true)
    for _, sx in ipairs({ -1, 1 }) do P(f, 4, 15, 8, h * CF(sx * 22, 7.5, 26), RGB(140, 136, 124), MAT.Concrete, true) end
    P(f, 46, 1.2, 50, h * CF(0, 16.4, -2), COL.sand:Lerp(COL.hescoTop, 0.4), MAT.Sand)
    glow(f, (h * CF(0, 16, 29.2)).Position, COL.lamp, 0.7)
    board(f, h * CF(0, 13.4, 28.8) * ANG(0, PI, 0), 5, 2, tostring(k + 1), COL.yellow, RGB(20, 20, 20))
  end
  -- 机库（东边停机坪北沿两座）、塔台、消防站（World.building：能被炸塌）
  local bf = folder("Buildings", f)
  for k = 0, 1 do
    local p = L(700 + k * 170, RZ - 440).Position
    W.building(bf, "hangar", p.X, p.Z, yaw + PI)
  end
  local tp = L(150, RZ - 390).Position
  local _, _, _, th = W.building(bf, "atc", tp.X, tp.Z, yaw + PI)
  if th then W.light(f, V(tp.X, Map.ground(tp.X, tp.Z) + th + 1.2, tp.Z), RGB(255, 40, 40), 1, 14, 1.2).Name = "TowerBeacon" end
  local fp = L(-200, RZ - 430).Position
  W.building(bf, "conc2", fp.X, fp.Z, yaw + PI)
  -- 跑道灯：两边白边灯、两头绿 / 红入口灯、滑行道蓝灯、进近灯（跑道头外面一排排白灯）、PAPI（跑道左边四盏红白）
  local lf = folder("RunwayLights", f)
  local k = 0
  for x = -len / 2 + 10, len / 2 - 10, 60 do
    k += 1
    for _, s in ipairs({ -1, 1 }) do
      local pos = L(x, RZ + s * (wid / 2 + 1.5)).Position + V(0, 1.2, 0)
      if k % 4 == 1 then beacon(lf, pos, RGB(255, 246, 220), 0.6) else glow(lf, pos, RGB(255, 246, 220), 0.6) end
    end
  end
  for z = -wid / 2 + 3, wid / 2 - 3, 8 do
    local edge = math.abs(z) > wid / 2 - 12
    local pa, pb = L(-len / 2 - 2, RZ + z).Position + V(0, 1.2, 0), L(len / 2 + 2, RZ + z).Position + V(0, 1.2, 0)
    if edge then beacon(lf, pa, RGB(60, 255, 120), 0.6) beacon(lf, pb, RGB(255, 50, 40), 0.6)
    else glow(lf, pa, RGB(60, 255, 120), 0.6) glow(lf, pb, RGB(255, 50, 40), 0.6) end
  end
  for x = -1500, 1500, 50 do glow(lf, L(x, TZ - 19).Position + V(0, 1, 0), RGB(70, 120, 255), 0.5) end
  for _, s in ipairs({ -1, 1 }) do
    for d = 60, 300, 60 do
      local bar = (d == 180) and 4 or 1
      for k = -bar, bar do glow(lf, L(s * (len / 2 + d), RZ + k * 4).Position + V(0, 1.4, 0), RGB(255, 250, 236), 0.5) end
      P(lf, 0.4, 1.4, 0.4, L(s * (len / 2 + d), RZ) * CF(0, 0.7, 0), COL.steelDk, MAT.Metal)
    end
    for k = 0, 3 do
      local p = L(s * (len / 2 - 400), RZ + wid / 2 + 30 + k * 10)
      P(lf, 3, 1.6, 2, p * CF(0, 0.8, 0), RGB(230, 220, 60), MAT.Metal)
      glow(lf, (p * CF(0, 1.6, s * 1.2)).Position, (k < 2) and RGB(255, 255, 255) or RGB(255, 40, 40), 0.5)
    end
  end
  -- 风向袋（两头）、雷达（停机坪东边转的）、盲降天线阵（西头外面一排）
  for _, s in ipairs({ -1, 1 }) do
    local p = L(s * (len / 2 - 520), RZ + wid / 2 + 70)
    P(f, 0.5, 12, 0.5, p * CF(0, 6, 0), COL.white, MAT.Metal, true)
    local sock = p * CF(0, 11.6, 0) * ANG(0, math.rad(35), 0) * ANG(math.rad(-14), 0, 0)
    for i = 0, 2 do P(f, 2.2 - i * 0.45, 2.2 - i * 0.45, 2.4, sock * CF(0, 0, -1.4 - i * 2.4), (i % 2 == 0) and RGB(240, 110, 30) or COL.white, MAT.Fabric) end
    glow(f, (p * CF(0, 12.6, 0)).Position, RGB(255, 40, 40), 0.4)
  end
  local rp = L(1500, RZ - 400)
  P(f, 3, 18, 3, rp * CF(0, 9, 0), COL.steel, MAT.Metal, true)
  P(f, 4.6, 2.6, 4.6, rp * CF(0, 19.3, 0), COL.white, MAT.Metal)
  local ant = P(f, 12, 2.8, 0.6, rp * CF(0, 22.4, 0), RGB(214, 214, 210), MAT.Metal)
  ant.Name = "Radar"
  ant:SetAttribute("Anim", "spin")
  ant:SetAttribute("Spd", 0.25)
  ant:SetAttribute("Pivot", ant.CFrame.Position)
  for k = -6, 6 do P(f, 0.5, 4, 0.5, L(-len / 2 - 330, RZ + k * 6) * CF(0, 2, 0), COL.red:Lerp(COL.white, (k % 2 == 0) and 0 or 0.8), MAT.Metal) end
  -- 停机坪上的保障车：油罐车、牵引车、电源车、弹药拖车；探照灯杆
  for k = 0, 2 do cargoTruck(f, L(-1000 + k * 40, RZ - 330) * ANG(0, PI / 2, 0), (k == 1) and "cargo" or "fuel") end
  for k = 0, 3 do
    local t = L(820 + k * 30, RZ - 330)
    P(f, 6, 3, 10, t * CF(0, 1.8, 0), COL.yellow:Lerp(COL.steelDk, 0.2), MAT.Metal, true)
    P(f, 5, 1, 7, t * CF(0, 3.6, -1), RGB(60, 62, 64), MAT.Metal)
  end
  for k = 0, 5 do
    local t = L(-700 + k * 14, RZ - 320)
    P(f, 4, 0.8, 9, t * CF(0, 1.4, 0), COL.olive, MAT.Metal)
    for i = 0, 1 do CylX(f, 6, 1.6, t * CF(0, 2.6, -2 + i * 4), RGB(210, 210, 204), MAT.Metal) end
  end
  for _, x in ipairs({ -1300, -700, -100, 500, 1100 }) do
    local p = L(x, RZ - 370).Position
    floodPole(f, p.X, B0.Position.Y, p.Z, 24, COL.lamp, 130)
  end
end

---------------------------------------------------------------- 一整座基地

function FOB.build(World, root, side)
  W = World
  local B = Map.BASES and Map.BASES[side]
  if not B then return 0 end
  local F = Map.FOB
  local Y = Map.ground(B.x, B.z)
  local B0 = CF(B.x, Y, B.z) * ANG(0, B.yaw, 0)
  local function L(lx, lz, yaw) return B0 * CF(lx, 0, lz) * ANG(0, yaw or 0, 0) end
  local base = folder("FOB_" .. side, root)
  local C = F.camp
  local team = Config.Teams[side]

  -- ① 营区围墙：HESCO（正门、车场门、后门、左右两个侧门留口）、外面一道铁丝网、四角和墙中间的岗楼、墙里一圈照明塔
  local per = folder("Perimeter", base)
  local cw, cd = C.x1 - C.x0, C.z1 - C.z0
  local gateMain, gateMotor = { -34, 34 }, { F.motor.lx - 140, F.motor.lx + 140 }
  hesco(per, L(0, C.z0), cw, 2, { gateMain, gateMotor })
  hesco(per, L(0, C.z1, PI), cw, 2, { { -24, 24 } })
  hesco(per, L(C.x0, 0, PI / 2), cd, 2, { { 170, 230 }, { -90, -40 } })   -- 左墙：墙的 X 顺着 −lz（口子在 lz −200、60 两条横路）
  hesco(per, L(C.x1, 0, -PI / 2), cd, 2, { { -230, -170 }, { 40, 90 } })   -- 右墙：墙的 X 顺着 +lz
  wire(per, L(0, C.z0 - 16), cw + 32, { { -40, 40 }, { gateMotor[1], gateMotor[2] } })
  wire(per, L(C.x0 - 16, 0, PI / 2), cd + 32, { { 165, 235 }, { -95, -35 } })
  wire(per, L(C.x1 + 16, 0, -PI / 2), cd + 32, { { -235, -165 }, { 35, 95 } })
  local towers = { { C.x0 + 12, C.z0 + 12, PI * 0.25 }, { C.x1 - 12, C.z0 + 12, -PI * 0.25 }, { C.x0 + 12, C.z1 - 12, PI * 0.75 }, { C.x1 - 12, C.z1 - 12, -PI * 0.75 },
    { 120, C.z0 + 12, 0 }, { -480, C.z0 + 12, 0 }, { C.x0 + 12, 100, PI / 2 }, { C.x1 - 12, -40, -PI / 2 }, { 180, C.z1 - 12, PI } }
  for i, t in ipairs(towers) do tower(per, L(t[1], t[2], t[3]), i <= 5) end
  local lt = 0
  for x = C.x0 + 70, C.x1 - 70, 150 do
    lt += 1
    lightTower(per, L(x, C.z0 + 30, PI), lt % 2 == 0)
    lightTower(per, L(x, C.z1 - 14), lt % 3 == 0)
  end
  for _, z in ipairs({ -300, -120 }) do
    lightTower(per, L(C.x0 + 30, z, -PI / 2), false)
    lightTower(per, L(C.x1 - 30, z, PI / 2), false)
  end
  -- 正门检查站、车场门外的之字形水泥墩
  ecp(folder("ECP", base), L(0, C.z0), side)
  local mg = folder("MotorGate", base)
  for k = 0, 2 do
    local z = C.z0 - 30 - k * 26
    local xx = (k % 2 == 0) and (F.motor.lx - 80) or (F.motor.lx + 80)
    for j = -1, 1 do jersey(mg, L(xx + j * 8.6, z)) end
  end
  for _, s in ipairs({ -1, 1 }) do hesco(mg, L(F.motor.lx + s * 150, C.z0 - 22, PI / 2), 40, 2) end
  board(mg, L(F.motor.lx - 128, C.z0 - 46) * CF(0, 6, 0), 14, 2.6, "车场出口  ·  车辆出动注意", COL.yellow, RGB(20, 20, 20), true)
  P(mg, 0.6, 6, 0.6, L(F.motor.lx - 128, C.z0 - 46) * CF(0, 3, 0), COL.steelDk, MAT.Metal, true)

  -- 营区里整片铺碎石（真的前进基地没有一块露着的沙地）
  P(base, cw - 6, 0.4, cd - 6, L(0, 0) * CF(0, -0.18, 0), RGB(150, 138, 116), MAT.Pebble)

  -- ② 路：正门 → 出生广场 → 指挥中心 → 后门（柏油、白边线、黄中线），两条东西向的横路（碎石），路灯
  local rd = folder("Roads", base)
  local function road(a, b, w, asphalt)
    local pa, pb = a.Position, b.Position
    local mid = (pa + pb) / 2
    local cf = CFrame.lookAt(V(mid.X, Y + 0.02, mid.Z), V(pb.X, Y + 0.02, pb.Z))
    local len = (pb - pa).Magnitude
    P(rd, w, 0.3, len, cf * CF(0, -0.11, 0), asphalt and COL.asphalt or RGB(124, 116, 102), asphalt and MAT.Asphalt or MAT.Pebble)
    if asphalt then
      for _, s in ipairs({ -1, 1 }) do P(rd, 0.6, 0.05, len, cf * CF(s * (w / 2 - 1.2), 0.04, 0), COL.paint, MAT.SmoothPlastic) end
      for t = -len / 2 + 6, len / 2 - 6, 18 do P(rd, 0.5, 0.05, 8, cf * CF(0, 0.04, t), COL.yellow, MAT.SmoothPlastic) end
    end
  end
  road(L(0, C.z0 - 200), L(0, F.spawn.lz - 36), 26, true)
  road(L(0, F.spawn.lz + 36), L(0, C.z1), 26, true)
  road(L(C.x0, -200), L(C.x1, -200), 22, false)
  road(L(C.x0, 60), L(C.x1, 60), 22, false)
  road(L(F.motor.lx, C.z0 - 100), L(F.motor.lx, C.z0 + 4), 30, false)
  road(L(F.motor.lx, F.motor.lz + 72), L(F.motor.lx, -200), 30, false)
  road(L(0, C.z1), L(0, F.runway.lz - 130), 22, true)   -- 后门 → 停机坪 / 滑行道
  local n = 0
  for z = C.z0 + 40, C.z1 - 40, 60 do
    n += 1
    if math.abs(z - F.spawn.lz) > 40 then   -- 出生广场那一段有探照灯
      streetLamp(rd, L(16, z, PI / 2), n % 2 == 0)
      streetLamp(rd, L(-16, z, -PI / 2), false)
    end
  end
  for x = C.x0 + 60, C.x1 - 60, 90 do
    if math.abs(x) > 30 then
      streetLamp(rd, L(x, -186), false)
      streetLamp(rd, L(x, 74), false)
    end
  end
  -- 路口的指路牌
  local function signpost(cf, lines)
    P(rd, 0.5, 9, 0.5, cf * CF(0, 4.5, 0), COL.steelDk, MAT.Metal, true)
    for i, s in ipairs(lines) do board(rd, cf * CF(s[2] * 2.6, 9.2 - i * 1.6, 0), 5.6, 1.3, s[1], COL.green, COL.white) end
  end
  signpost(L(20, -214), { { "← 车场", -1 }, { "直升机坪 →", 1 }, { "↑ 指挥中心", 0 } })
  signpost(L(-20, 46), { { "← 生活区", -1 }, { "后勤区 →", 1 }, { "↑ 机场", 0 } })

  -- ③ 出生广场（固定出生位：Map.BASES[side].spawns 那 16 格，地上画着队伍色的方块）+ 三根旗杆
  local sp = folder("Spawn", base)
  local S0 = L(F.spawn.lx, F.spawn.lz)
  P(sp, 80, 0.3, 70, S0 * CF(0, -0.07, 0), COL.conc, MAT.Concrete)
  for i = 0, 3 do
    for k = 0, 3 do
      local c = L(F.spawn.lx + (i - 1.5) * 12, F.spawn.lz + (k - 1.5) * 12)
      P(sp, 7, 0.06, 7, c * CF(0, 0.11, 0), team.color, MAT.SmoothPlastic)
      P(sp, 1.4, 0.07, 3.6, c * CF(0, 0.125, -0.4), COL.white, MAT.SmoothPlastic)   -- 箭头：朝战场
      P(sp, 1.2, 0.07, 2.6, c * CF(-0.75, 0.125, -2.2) * ANG(0, -0.7, 0), COL.white, MAT.SmoothPlastic)
      P(sp, 1.2, 0.07, 2.6, c * CF(0.75, 0.125, -2.2) * ANG(0, 0.7, 0), COL.white, MAT.SmoothPlastic)
    end
  end
  board(sp, L(F.spawn.lx - 48, F.spawn.lz, -PI / 2) * CF(0, 6, 0), 24, 4, ((side == "atk") and "攻方主基地" or "守方主基地") .. "  ·  部署点", team.color:Lerp(RGB(20, 20, 20), 0.3), COL.white, true)
  for _, s in ipairs({ -1, 1 }) do P(sp, 0.6, 6, 0.6, L(F.spawn.lx - 48, F.spawn.lz + s * 11) * CF(0, 3, 0), COL.steelDk, MAT.Metal, true) end
  for i, x in ipairs({ 30, 46, 62 }) do
    local fp = L(F.spawn.lx + x, F.spawn.lz + 50)
    CylV(sp, i == 2 and 42 or 34, 0.9, fp * CF(0, (i == 2 and 42 or 34) / 2, 0), COL.white, MAT.Metal, true)
    local cloth = P(sp, 12, 7, 0.3, fp * CF(6.6, (i == 2) and 38 or 30, 0), (i == 2) and team.color or team.color:Lerp(COL.white, 0.35 * i - 0.35), MAT.Fabric)
    cloth.Name = (i == 2) and "BaseFlagCloth" or "FlagCloth"
    CylV(sp, 2.6, 2.6, fp * CF(0, 1.3, 0), COL.concDk, MAT.Concrete, true)
  end
  for _, s in ipairs({ -1, 1 }) do floodPole(sp, L(F.spawn.lx + s * 44, F.spawn.lz).Position.X, Y, L(F.spawn.lx + s * 44, F.spawn.lz).Position.Z, 20, COL.lamp, 110) end

  -- ④ 车场：硬化地坪（召唤车位由 Depots 摆在 motor 那一排）、停着的车、维修区
  local mp = folder("MotorPool", base)
  P(mp, 330, 0.3, 120, L(F.motor.lx, F.motor.lz + 10) * CF(0, -0.07, 0), COL.concDk:Lerp(COL.gravel, 0.4), MAT.Concrete)
  board(mp, L(F.motor.lx, F.motor.lz + 72) * CF(0, 6, 0), 18, 3, "车场  ·  召唤车辆", COL.white, RGB(20, 20, 20), true)
  for _, s in ipairs({ -1, 1 }) do P(mp, 0.6, 6, 0.6, L(F.motor.lx + s * 8, F.motor.lz + 72) * CF(0, 3, 0), COL.steelDk, MAT.Metal, true) end
  for k = 0, 3 do lightTruck(mp, L(F.motor.lx - 150 + k * 10, F.motor.lz + 58, PI)) end
  for k = 0, 2 do cargoTruck(mp, L(F.motor.lx + 120 + k * 12, F.motor.lz + 60, PI), (k == 2) and "fuel" or "cargo") end
  maintenance(mp, L(F.motor.lx, -110))

  -- ⑤ 直升机坪（Depots 的召唤位摆在 heli 那一排：基地坐标横着三个、间隔 90）+ 前沿加油点 + 风向袋
  local hp = folder("Helipads", base)
  for k = -1, 1 do helipad(hp, L(F.heli.lx + k * 90, F.heli.lz)) end
  local farp = L(F.heli.lx, F.heli.lz + 110)
  for k = -1, 1 do bladder(hp, farp * CF(k * 26, 0, 0) * ANG(0, PI / 2, 0), 18, 9) end
  for _, s in ipairs({ -1, 1 }) do berm(hp, farp * CF(0, 0, s * 18), 90, 3.4, 8) end
  board(hp, farp * CF(0, 4, -24), 10, 2, "前沿加油点 FARP", COL.red, COL.white, true)
  do
    local p = L(F.heli.lx + 150, F.heli.lz - 40)
    P(hp, 0.5, 12, 0.5, p * CF(0, 6, 0), COL.white, MAT.Metal, true)
    local sock = p * CF(0, 11.6, 0) * ANG(0, math.rad(35), 0) * ANG(math.rad(-14), 0, 0)
    for i = 0, 2 do P(hp, 2.2 - i * 0.45, 2.2 - i * 0.45, 2.4, sock * CF(0, 0, -1.4 - i * 2.4), (i % 2 == 0) and RGB(240, 110, 30) or COL.white, MAT.Fabric) end
  end
  clamshell(hp, L(F.heli.lx + 60, -60), 70, 32, COL.tent)
  board(hp, L(F.heli.lx + 60, -60) * CF(0, 24, -35.5), 14, 2.4, "航空维修", COL.white, RGB(20, 20, 20))
  conex(hp, L(F.heli.lx - 80, -60, PI / 2), false, CONEX[5])
  mast(hp, L(F.heli.lx - 80, -30), 26)

  -- ⑥ 指挥中心、天线阵、迫击炮、近防炮
  local cmd = folder("Command", base)
  toc(cmd, L(75, -110))
  antennaFarm(cmd, L(185, -110))
  mortarPit(cmd, L(-60, -40))
  mortarPit(cmd, L(-30, -40))
  cram(cmd, L(250, -20))
  for _, x in ipairs({ -70, 40, 100 }) do bunker(cmd, L(x, 10)) end

  -- ⑦ 生活区：三排双排集装箱宿舍（两块，每排八个），中间碎石路、T 形防爆墙，排头防空掩体，卫浴拖车、流动厕所、水罐
  local lv = folder("Living", base)
  local li = 0
  for row = 0, 2 do
    local z0 = 120 + row * 95
    for blk = 0, 1 do
      local x0 = -520 + blk * 200
      for k = 0, 7 do
        li += 1
        local x = x0 + k * 18.5
        chu(lv, L(x, z0 - 8), (k % 5 == 3) and COL.chu2 or COL.chu, li % 6 == 0)
        chu(lv, L(x, z0 + 8, PI), (k % 4 == 1) and COL.chu2 or COL.chu, li % 6 == 3)
      end
      local cx = x0 + 3.5 * 18.5
      P(lv, 160, 0.25, 14, L(cx, z0 - 22) * CF(0, -0.065, 0), RGB(124, 116, 102), MAT.Pebble)
      P(lv, 160, 0.25, 14, L(cx, z0 + 22) * CF(0, -0.065, 0), RGB(124, 116, 102), MAT.Pebble)
      twall(lv, L(cx, z0 - 34), 150)
      bunker(lv, L(x0 - 22, z0 - 22, PI / 2))
    end
    streetLamp(lv, L(-355, z0 - 22), true)
  end
  trailer(lv, L(-330, 410 - 22), "淋浴")
  trailer(lv, L(-420, 410 - 22), "洗手间")
  johns(lv, L(-140, 120), 6)
  johns(lv, L(-140, 310), 5)
  waterTower(lv, L(-140, 220))
  for k = 0, 2 do palletStack(lv, L(-118, 170 + k * 7), 2) end

  -- ⑧ 生活保障：食堂、健身房、商店、洗衣房、礼拜堂（拱形帐篷）
  local sv = folder("Services", base)
  dfac(sv, L(40, 170))
  temper(sv, L(-30, 285, PI / 2), 48, COL.tent, "健身房")
  temper(sv, L(40, 285, PI / 2), 40, COL.tentDk, "洗衣房")
  temper(sv, L(110, 285, PI / 2), 40, COL.tent, "礼拜堂")
  do   -- 商店 PX：两个集装箱 + 雨棚 + 牌子
    local px = L(40, 370)
    conex(sv, px * CF(-10, 0, 0), true, RGB(196, 186, 160))
    conex(sv, px * CF(-10, 0, 9), true, RGB(186, 176, 150))
    P(sv, 36, 0.4, 10, px * CF(-10, 8, -8), COL.tin, MAT.Metal)
    board(sv, px * CF(-10, 9.6, -12.6), 10, 2, "商店 PX", COL.blue, COL.white)
    for _, x in ipairs({ -26, 6 }) do P(sv, 0.4, 8, 0.4, px * CF(x, 4, -12.6), COL.steel, MAT.Metal) end
  end
  for k = 0, 3 do genset(sv, L(160, 140 + k * 16, PI / 2)) end

  -- ⑨ 后勤区：大仓库、集装箱堆场（码两层）、叉车、托盘，油料库、弹药库
  local lg = folder("Logistics", base)
  clamshell(lg, L(320, 150, PI), 90, 36, COL.tentDk)
  board(lg, L(320, 150) * CF(0, 26, 45.6) * ANG(0, PI, 0), 12, 2.4, "物资仓库", COL.white, RGB(20, 20, 20))
  local ci = 0
  for i = 0, 3 do
    for j = 0, 1 do
      ci += 1
      local c = L(430 + j * 40, 110 + i * 9)
      conex(lg, c, true, CONEX[(ci % #CONEX) + 1])
      if (i + j) % 2 == 0 then conex(lg, c * CF(0, 7.3, 0), true, CONEX[((ci + 3) % #CONEX) + 1]) end
    end
  end
  forklift(lg, L(400, 175, 0.4))
  for k = 0, 5 do palletStack(lg, L(380 + (k % 3) * 7, 200 + (k // 3) * 7), (k % 3) + 1) end
  fuelFarm(lg, L(320, 330))
  ammoPoint(lg, L(470, 300, PI))

  -- ⑨½ 空地补满（用户：「过于分散、细节少」）：停车场、医疗站、临时营房帐篷一排、一片片小零碎
  local ex = folder("Extra", base)
  for row = 0, 1 do   -- 停车场：出生广场右边两排，车头朝里；上面拉伪装网
    local z = -375 + row * 56
    for k = 0, 7 do
      local x = 90 + k * 22
      if row == 0 and k % 3 == 2 then cargoTruck(ex, L(x, z, PI), "cargo") else lightTruck(ex, L(x, z, PI)) end
    end
    local net = P(ex, 190, 0.3, 30, L(167, z) * CF(0, 11, 0), COL.camo, MAT.Fabric)
    net.Transparency = 0.25
    for _, x in ipairs({ 74, 167, 260 }) do
      for _, dz in ipairs({ -14, 14 }) do P(ex, 0.4, 11, 0.4, L(x, z + dz) * CF(0, 5.5, 0), COL.wood, MAT.Wood) end
    end
  end
  board(ex, L(60, -330, PI / 2) * CF(0, 4, 0), 8, 1.8, "停车场", COL.blue, COL.white, true)
  do   -- 医疗站：两顶拱形帐篷、帐篷顶上的红十字、救护车
    local med = L(300, -150)
    temper(ex, med * CF(0, 0, -16), 34, COL.tent, "医疗站")
    temper(ex, med * CF(0, 0, 16), 34, COL.tent)
    for _, dz in ipairs({ -16, 16 }) do
      P(ex, 8, 0.2, 8, med * CF(0, 8.55, dz), COL.white, MAT.Fabric)
      P(ex, 6, 0.25, 2, med * CF(0, 8.62, dz), COL.red, MAT.Fabric)
      P(ex, 2, 0.25, 6, med * CF(0, 8.62, dz), COL.red, MAT.Fabric)
    end
    lightTruck(ex, L(338, -112, PI / 2), RGB(226, 224, 216))
  end
  for k = 0, 3 do temper(ex, L(-520 + k * 80, 30), 40, (k % 2 == 0) and COL.tent or COL.tentDk, (k == 0) and "临时营房" or nil) end
  -- 小零碎：几片空地里按固定种子撒托盘、油桶、沙袋堆、电缆盘、小发电机、木箱
  local rng = Random.new(side == "atk" and 24111 or 24112)
  local zones = { { -470, -130, -250, -165, 14 }, { 380, 540, 150, 250, 12 }, { -540, -160, 356, 400, 10 }, { 450, 540, -235, -185, 6 },
    { 30, 140, -62, -22, 6 }, { -150, -110, 100, 360, 8 }, { 150, 260, 300, 400, 8 } }
  for _, z0 in ipairs(zones) do
    for _ = 1, z0[5] do
      local c = L(rng:NextNumber(z0[1], z0[2]), rng:NextNumber(z0[3], z0[4]), rng:NextNumber() * PI * 2)
      local kind = rng:NextInteger(1, 7)
      if kind <= 3 then palletStack(ex, c, kind)
      elseif kind == 4 then drums(ex, c, rng:NextInteger(3, 7), (rng:NextNumber() < 0.5) and RGB(60, 84, 52) or RGB(60, 70, 96))
      elseif kind == 5 then bags(ex, c, 6, 1.6, 2.6)
      elseif kind == 6 then
        CylX(ex, 3, 5, c * CF(0, 2.5, 0), COL.wood, MAT.Wood, true)
        CylX(ex, 3.2, 3.4, c * CF(0, 2.5, 0), COL.rubber, MAT.Rubber)
      else
        P(ex, 3.4, 2.6, 5, c * CF(0, 1.3, 0), COL.gen, MAT.Metal, true)
        CylV(ex, 1.2, 0.4, c * CF(1, 3.2, 1.6), COL.steelDk, MAT.Metal)
      end
    end
  end

  -- ⑩ 机场（营区后面）
  airfield(folder("Airfield", base), B0, F.runway, side, B.yaw)

  -- ⑪ 整个基地外面一圈土堤（路口留口）
  local R = F.rect
  local bm = folder("Berm", base)
  local function bermRun(a, b)
    local pa, pb = a.Position, b.Position
    local d = pb - pa
    local len = d.Magnitude
    local nseg = math.ceil(len / 1600)
    for i = 0, nseg - 1 do
      local t0, t1 = i / nseg, (i + 1) / nseg
      local m = pa:Lerp(pb, (t0 + t1) / 2)
      berm(bm, CFrame.lookAt(V(m.X, Y, m.Z), V(pb.X, Y, pb.Z)) * ANG(0, PI / 2, 0), len / nseg - 2, 5, 18)
    end
  end
  bermRun(L(R.x0, R.z0), L(F.motor.lx - 190, R.z0))   -- 正门、车场门前面一个大口子
  bermRun(L(120, R.z0), L(R.x1, R.z0))
  bermRun(L(R.x1, R.z0), L(R.x1, R.z1))
  bermRun(L(R.x1, R.z1), L(R.x0, R.z1))
  bermRun(L(R.x0, R.z1), L(R.x0, R.z0))

  -- ⑫ 外面：正门外的路、坦克掩体（U 形土堤，口朝里）
  local out = folder("Outer", base)
  for _, x in ipairs({ -900, -620, 620, 900 }) do
    local c = L(x, R.z0 - 60)
    berm(out, c * CF(0, 0, -10), 34, 6, 10)
    berm(out, c * CF(-15, 0, 2) * ANG(0, PI / 2, 0), 24, 5, 8)
    berm(out, c * CF(15, 0, 2) * ANG(0, PI / 2, 0), 24, 5, 8)
  end
  return #base:GetDescendants()
end

return FOB
