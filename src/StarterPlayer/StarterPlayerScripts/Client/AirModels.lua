-- Roblox全面大战场（客户端）——飞机、直升机的零件模型和动画：按 AirDefs 的外形参数拼
--   固定翼：机身（椭球拼的前机身、中机身、尾锥、雷达罩）、座舱盖（玻璃，停机时打开）和飞行员、进气道、发动机舱、尾喷口（调节片随加力张开）
--     和加力火焰（长度跟油门、带马赫环）、机翼（梯形，三角形楔块拼）、鸭翼 / 平尾（全动）、垂尾（全动或方向舵）、副翼、襟翼、升降副翼、
--     起落架（支柱、机轮、舱门，收放有动画）、尾钩、弹舱门（两扇向下打开）、侧弹舱（挂架连弹推出舱外）、折叠机翼（舰载机停在甲板上折起）、
--     挂架和挂的弹（导弹、炸弹、火箭巢，多联挂架按枚数摆；打掉一枚少一枚）、航行灯（左红右绿、尾白、防撞灯闪）、国籍标志、螺旋桨（无人机）
--   直升机：机身、串列座舱（武装直升机）、发动机舱、尾梁、垂尾、平尾、短翼和挂架、主旋翼（桨毂、桨叶、转起来是一圈模糊的桨盘、随驾驶杆倾斜）、
--     尾桨、机头炮塔（跟着准星转）、光电转塔、毫米波雷达罩、固定起落架、运输直升机的滑门（落地打开）、舱门机枪、支奴干的后跳板和纵列双旋翼
--   AM.build(d, team, load) 返回模型；AM.pose(M, cf, c) 按机体姿态和各通道（c：俯仰 pit、滚转 rol、偏航 yaw 操纵量 −1～1，油门 thr 0～130，
--     起落架 gear 0～1，襟翼 flap，弹舱 bay / bayS，座舱盖 can，尾钩 hook，折翼 fold，旋翼转角 spin1 / spin2 / spinT，转速 rpm，炮塔 ty / gp，
--     滑门 door，跳板 ramp）算出每个零件的位置，一次 BulkMoveTo
--   AM.setStores(M, str)：Stores 属性（每个挂点剩几枚）变了，藏掉打出去的弹
--   原模型（网页版的飞机直升机原样转的 models/air/<模型键>.glb，Studio 导入后 Imports.lua 收进 ReplicatedStorage.Imported.Air.<模型键>，
--     元数据 ImportedAir）：有就只换「蒙皮」——机身、机翼、尾翼、座舱盖、进气道、尾喷口、舵面、舱门、模型自带的起落架、旋翼都换成原模型（真实尺寸）；
--     挂架和弹、航行灯、加力火焰、模型没带的起落架照旧拼，挪到原模型上（挂架挂在机翼下表面、灯在翼尖 / 蒙皮上、火焰从原模型的尾喷口喷）
local AM = {}

local V = Vector3.new
local CF = CFrame.new
local RGB = Color3.fromRGB
local MAT = Enum.Material
local CYL, BALL = Enum.PartType.Cylinder, Enum.PartType.Ball
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)    -- 圆柱的轴（X）转到 Z
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)    -- 圆柱的轴转到 Y
local rad = math.rad

local SKIN = {
  atk = { jet = RGB(150, 157, 163), stealth = RGB(118, 124, 130), heli = RGB(104, 112, 100), drone = RGB(178, 182, 184) },
  def = { jet = RGB(128, 136, 142), stealth = RGB(96, 100, 106), heli = RGB(70, 76, 60), drone = RGB(150, 154, 158) },
}
local SKIN_ID = { h6k = RGB(196, 198, 196), b2 = RGB(66, 68, 72), a10c = RGB(112, 118, 120), j15t = RGB(164, 170, 172), ch47 = RGB(78, 84, 66), uh60 = RGB(58, 64, 52),
  z20 = RGB(100, 110, 104), z10 = RGB(112, 120, 116) }
local GLASS, GOLD, DARK, TIRE, STEEL, RADOME = RGB(36, 52, 62), RGB(150, 122, 62), RGB(36, 38, 40), RGB(26, 26, 28), RGB(84, 86, 88), RGB(200, 202, 196)

local RS = game:GetService("ReplicatedStorage")
local Tint = require(script.Parent:WaitForChild("Tint"))   -- 导入的贴图没出来时的底色（原贴图的平均色）
local TURN = require(RS:WaitForChild("ImportTurn")).TURN   -- 导入的每块网格被 Roblox 转了半圈：摆的时候转回来
local IA = nil   -- 原模型的元数据（tools/models/air2glb.py 生成）
do
  local ok, r = pcall(function() return require(RS:WaitForChild("ImportedAir", 3)) end)
  if ok and type(r) == "table" then IA = r end
end
-- 原模型自带的「转起来的桨盘」（半透明的一整块圆盘 / 方片，材质不透明度只有 0.08 / 0.25）：导进 Roblox 后不透明度丢了，
--   停着也是一整块实心圆盘（用户：挂载界面里螺旋桨位置对不上、而且是转起来的样子）——当成桨盘：停着不显示，转快了才淡淡地出现，桨叶同时变虚
local BLUR = { z10w = { Rotor_2 = true, TRotor_2 = true } }
-- 原模型上切出来的活动部件（ImportedAir 的 surf）：按动法算转角。sg 已经把正方向统一成：舵面后缘往下、方向舵 / 全动垂尾后缘往右、
--   舱门和座舱盖打开、起落架收起；s 是哪一侧（1 右、−1 左）。操纵量 pit / rol / yaw 是 −1～1（抬头、右滚、右偏为正），flap 0～1
--   减速板（c.brk，B 键）：这些机型没有单独的减速板，照真飞机用舵面减速——副翼两边一起上翘、襟副翼往下、双垂尾的方向舵 / 全动垂尾往外撇
local SURF_F = {
  ail = function(c, s) return -s * (c.rol or 0) * rad(20) - (c.brk or 0) * rad(28) end,          -- 副翼：右滚时右边后缘往上；减速时两边一起往上
  flap = function(c) return (c.flap or 0) * rad(30) end,
  flaperon = function(c, s) return (c.flap or 0) * rad(20) - s * (c.rol or 0) * rad(15) + (c.brk or 0) * rad(22) end,   -- 襟副翼：放襟翼 + 差动滚转；减速时往下
  elevon = function(c, s) return math.clamp(-(c.pit or 0) * rad(15) - s * (c.rol or 0) * rad(15), -rad(25), rad(25)) end,   -- 升降副翼：抬头时后缘往上
  stab = function(c, s) return -(c.pit or 0) * rad(18) - s * (c.rol or 0) * rad(6) end,          -- 全动平尾：带一点差动帮滚转
  elev = function(c) return -(c.pit or 0) * rad(20) end,
  can = function(c) return (c.pit or 0) * rad(16) end,                                          -- 鸭翼：抬头时前缘往上（后缘往下）
  rud = function(c, s) return (c.yaw or 0) * rad(25) + (s or 0) * (c.brk or 0) * rad(28) end,   -- 方向舵；双垂尾减速时两边往外撇（单垂尾 s = 0 不动）
  fin = function(c, s) return (c.yaw or 0) * rad(18) + (s or 0) * (c.brk or 0) * rad(22) end,   -- 全动垂尾：同上
  rv = function(c, s) return -(c.pit or 0) * rad(18) + s * (c.yaw or 0) * rad(15) end,          -- V 尾：抬头两边一起往上，偏航两边反着
  bay = function(c, _, A) return (c.bay or 0) * A end,
  bayS = function(c, _, A) return (c.bayS or 0) * A end,
  canopy = function(c, _, A) return (c.can or 0) * A end,
  gear = function(c, _, A) return (1 - (c.gear or 1)) * A end,
}
-- 推力矢量喷口（用户给的「F-15 SE Thrust Vector Nozzle」，models/air/tvc.glb，元数据 ImportedAir.m.tvc；用户：给飞机都用上这个推力矢量推嘴的动画）：
--   圆喷口的战斗机每个尾喷口装一只——外罩贴着原模型的喷口出口往后接，15 片调节片绕喉道处的铰链开合（慢车微张、军推收拢、加力张到最大，
--   原模型的变形动画就是这一开一合），整只绕喉道中心偏转：抬头时出口往上、右偏时出口往右、右滚时右边往上左边往下；加力火焰跟着出口走
local TVC_ON = { j15t = true, j16 = true, j20 = true, j35 = true, f35 = true }
local TVC_P, TVC_Y, TVC_R = rad(16), rad(10), rad(7)
local function tvcOpen(t)
  if t <= 100 then return 0.45 - 0.3 * math.clamp(t / 100, 0, 1) end
  return 0.15 + 0.85 * math.min(1, (t - 100) / 25)
end
AM.tvcOpen = tvcOpen
-- 这个型号导入了原模型没有：{ key, info 元数据, folder 导入的块, plain 去掉原机涂装（我方没有模型、拿美军机代的）, O 模型坐标 → 机体坐标的平移 }
--   先找最新版（有舵面、舱门、座舱盖、起落架支柱这些活动部件，修过朝反的面，键名 <键>_v3），没导入就按 ImportedAir 的 old 表挨个找老版
--   （_v2 会动、有的面朝反了；不带后缀的一整块蒙皮、不会动）；
--   元数据里的块要全在（导入了一半、或者文件夹里是别的版本的块，就不用这一版）
local complete = {}   -- [文件夹] = 块齐不齐（每个文件夹只查一次）
--   只记「齐了」：进服时几千块是陆续复制过来的，先看的那一下块不齐就永远当成没导入，很多飞机就一直是零件拼的（用户：很多飞机找不到建模）
--   都复制过来了（块数到了服务器记的 N）还缺几小块的照样用（原模型里有不少 0.02 格的小碎块，Studio 导入时可能丢掉特别小、退化的网格；
--   原来缺一块就整架换成零件拼的）：缺的体积不到百分之三、块数不到四分之一，输出窗口说一声缺哪几块；缺得多（导入了一半、文件夹里是别的版本的块）才不用
local warnedMiss = {}
local function usable(info, f, key)
  if not (info and f) then return false end
  if complete[f] then return true end
  local n = f:GetAttribute("N")   -- 服务器记的块数（Imports.lua）
  if n and #f:GetChildren() < n then return false end
  local miss, missV, totV, total = {}, 0, 0, 0
  for name, p in pairs(info.parts) do
    local v = (p.s and p.s[1] * p.s[2] * p.s[3]) or 1
    totV += v
    total += 1
    if not f:FindFirstChild("A_" .. key .. "__" .. name) then
      table.insert(miss, name)
      missV += v
    end
  end
  if #miss > 0 then
    if not n then return false end   -- 不知道服务器那边有几块：可能还在复制，等等再看
    if #miss > total * 0.25 or missV > totV * 0.03 then return false end
    if not warnedMiss[f] then
      warnedMiss[f] = true
      table.sort(miss)
      warn("[全面大战场] 原模型 " .. key .. " 缺 " .. #miss .. " 块（照样用）：" .. table.concat(miss, "、", 1, math.min(#miss, 8)))
    end
  end
  complete[f] = true
  return true
end
local function tvcAsset()
  local info = IA and IA.m and IA.m.tvc
  local imp = RS:FindFirstChild("Imported")
  local air = imp and imp:FindFirstChild("Air")
  local f = air and air:FindFirstChild("tvc")
  if info and info.tvc and f and usable(info, f, "tvc") then return info, f end
  return nil
end
-- 原模型里「起落架」那几块其实是机腹 / 翼下的蒙皮（转换脚本按最低的三角形挑的；这两架是按收起起落架的样子做的，机轮收在舱里、整架趴在地上）：
--   那几块当蒙皮一直画，整架抬高 lift 格（放下起落架时机身离地的高度，真机全高减模型高），用零件拼的起落架（用户：部分飞机没有起落架）
local NOGEAR = { a10 = 2.5, a10_v2 = 2.5, a10_v3 = 2.5, b2 = 4.8, b2_v2 = 4.8, b2_v3 = 4.8 }
AM.NOGEAR = NOGEAR
function AM.importedFor(d)
  local imp = RS:FindFirstChild("Imported")
  local air = imp and imp:FindFirstChild("Air")
  if not (IA and air) then return nil end
  local list = {}
  if IA.alias and IA.alias[d.id] then table.insert(list, IA.alias[d.id]) end
  local old = IA.old and IA.old[d.id]
  if type(old) == "string" then table.insert(list, old)
  elseif type(old) == "table" then for _, k in ipairs(old) do table.insert(list, k) end end
  for _, k in ipairs(list) do
    local plain = string.sub(k, -1) == "~"
    local key = plain and string.sub(k, 1, -2) or k
    local info = IA.m and IA.m[key]
    local f = air:FindFirstChild(key)
    if usable(info, f, key) then
      local lift = NOGEAR[key]
      return { key = key, info = info, folder = f, plain = plain, O = V(0, -d.gearH + (lift or 0), 0), noGear = lift ~= nil }   -- 模型坐标的高度 0 是停在地上时的地面
    end
  end
  return nil
end
-- 原模型机身中线上 / 下表面在 z 处的高（模型坐标；元数据从 z0 起每格一个）
local function profAt(I, arr, z)
  local P = I.prof
  local a = P and P[arr]
  if not a or #a == 0 then return nil end
  return a[math.clamp(math.floor(z - P.z0) + 1, 1, #a)]
end
-- 夜航灯挪到原模型上：翼尖灯在翼尖（航行灯前段、频闪后段），垂尾灯在垂尾顶，防撞灯、着陆灯贴着机背 / 机腹
local function impLights(L0, imp, d)
  local I, oy = imp.info, imp.O.Y
  local L = table.clone(L0)
  if I.tip and (d.kind == "jet" or d.style == "attackheli") then
    local t = I.tip
    L.tip = V(t[1] + 0.2, t[2] + oy, t[3] + 0.28 * (t[4] - t[3]))
    if L.strobe then L.strobe = V(t[1] + 0.15, t[2] + oy, t[3] + 0.82 * (t[4] - t[3])) end
  end
  if I.tails and d.kind == "jet" and not d.flyingWing and not d.tailless then
    local p = I.tails.p
    L.tails = I.tails.twin and { V(p[1], p[2] + oy + 0.2, p[3]), V(-p[1], p[2] + oy + 0.2, p[3]) } or { V(0, p[2] + oy + 0.2, p[3] + 0.2) }
  end
  local function onSkin(pt, arr, dy)
    local y = pt and profAt(I, arr, pt.Z)
    return y and V(pt.X, y + oy + dy, pt.Z) or pt
  end
  L.top = onSkin(L.top, "top", 0.25)
  L.bottom = onSkin(L.bottom, "bot", -0.25)
  L.land = onSkin(L.land, "bot", -0.1)
  return L
end
-- 桨毂坐标系：Y 轴转到旋翼轴 a 上
local function axisY(a)
  local up = V(0, 1, 0)
  local dot = math.clamp(up:Dot(a), -1, 1)
  if dot > 0.9999 then return CFrame.new() end
  if dot < -0.9999 then return CFrame.Angles(math.pi, 0, 0) end
  return CFrame.fromAxisAngle(up:Cross(a).Unit, math.acos(dot))
end

local function newPart(m, size, color, mat, shape, tr, cls)
  local p = Instance.new(cls or "Part")
  if shape then p.Shape = shape end
  p.Size = V(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
  p.Color = color
  p.Material = mat or MAT.SmoothPlastic
  p.Transparency = tr or 0
  p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
  p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
  p.Parent = m
  return p
end

function AM.build(d, team, load)
  local m = Instance.new("Model")
  m.Name = d.id
  local items = {}
  local M = { model = m, items = items, def = d, stores = {}, pylons = {}, bayItems = {}, blades = {}, discs = {}, flames = {}, strobes = {}, lamps = {}, tvc = {}, team = team }
  local imp = AM.importedFor(d)
  M.imp = imp
  -- 正在拼哪一类零件（有原模型时只留下这几类，其余的是蒙皮、换成原模型）：gear 起落架、rotor 旋翼 / 螺旋桨、lamp 灯、store 挂架和弹、pilot 飞行员
  local TAG = nil
  local skin = SKIN_ID[d.id] or ((SKIN[team] or SKIN.atk)[(d.kind == "heli") and "heli" or (d.drone and "drone") or (d.stealth and "stealth") or "jet"])
  local skinD = skin:Lerp(Color3.new(0, 0, 0), 0.18)
  local skinL = skin:Lerp(Color3.new(1, 1, 1), 0.12)
  local glass = (d.id == "f22" or d.id == "f35") and GOLD or GLASS

  -- 加一个零件：kind b 跟机体、h 绕铰链转（f(c) 给角度）、m 平移（f(c) 给 CFrame）、r 旋翼 / 尾桨 / 螺旋桨、t 炮塔、ab 加力火焰
  local function add(p, cf, kind, extra)
    local it = extra or {}
    it.p, it.cf0, it.kind = p, cf, kind or "b"
    it.tag = TAG
    it.tr0 = p.Transparency
    if it.kind == "h" then
      it.H = CF(it.hp)
      it.off = CF(-it.hp) * cf
    end
    table.insert(items, it)
    return it
  end
  local function box(size, cf, color, mat, kind, extra, tr) return add(newPart(m, size, color or skin, mat or MAT.Metal, nil, tr), cf, kind, extra) end
  local function ball(size, cf, color, mat, kind, extra, tr)   -- 椭球（SpecialMesh 球形，按零件大小拉伸）
    local p = newPart(m, size, color or skin, mat or MAT.Metal, nil, tr)
    local sm = Instance.new("SpecialMesh")
    sm.MeshType = Enum.MeshType.Sphere
    sm.Parent = p
    return add(p, cf, kind, extra)
  end
  local function cylZ(len, dia, cf, color, mat, kind, extra, tr) return add(newPart(m, V(len, dia, dia), color or skin, mat or MAT.Metal, CYL, tr), cf * ALONG_Z, kind, extra) end
  local function cylY(len, dia, cf, color, mat, kind, extra, tr) return add(newPart(m, V(len, dia, dia), color or skin, mat or MAT.Metal, CYL, tr), cf * UPRIGHT, kind, extra) end
  local function cylX(len, dia, cf, color, mat, kind, extra, tr) return add(newPart(m, V(len, dia, dia), color or skin, mat or MAT.Metal, CYL, tr), cf, kind, extra) end
  local function neon(size, cf, color, kind, extra, shape)
    local p = newPart(m, size, color, MAT.Neon, shape or BALL)
    p.CastShadow = false
    return add(p, cf, kind, extra)
  end

  -- 三角形（两块楔块，在 a、b、c 三点决定的平面里，厚 th）；返回零件列表（同一组动画参数）
  local function tri(a, b, c, th, color, mat, kind, extra)
    local ab, ac, bc = b - a, c - a, c - b
    local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
    if abd > acd and abd > bcd then c, a = a, c
    elseif acd > bcd and acd > abd then a, b = b, a end
    ab, ac, bc = b - a, c - a, c - b
    local right = ac:Cross(ab)
    if right.Magnitude < 1e-6 or bc.Magnitude < 1e-6 then return end
    right = right.Unit
    local up = bc:Cross(right).Unit
    local back = bc.Unit
    local height = math.abs(ab:Dot(up))
    local l0, l1 = math.abs(ab:Dot(back)), math.abs(ac:Dot(back))
    if height < 0.05 then return end
    if l0 > 0.05 then
      local w0 = newPart(m, V(th, height, l0), color or skin, mat or MAT.Metal, nil, nil, "WedgePart")
      add(w0, CFrame.fromMatrix((a + b) / 2, right, up, back), kind, extra and table.clone(extra))
    end
    if l1 > 0.05 then
      local w1 = newPart(m, V(th, height, l1), color or skin, mat or MAT.Metal, nil, nil, "WedgePart")
      add(w1, CFrame.fromMatrix((a + c) / 2, -right, up, -back), kind, extra and table.clone(extra))
    end
  end
  local function quad(a, b, c, e, th, color, mat, kind, extra)
    tri(a, b, c, th, color, mat, kind, extra)
    tri(a, c, e, th, color, mat, kind, extra)
  end

  ---------------------------------------------------------------- 翼面（梯形，一边）

  -- 梯形 T 在 s 侧（1 右、−1 左）：返回取点函数 P(u 展向 0 根～1 尖, v 弦向 0 前缘～1 后缘)
  local function trapPt(T, s)
    local dih = math.tan(rad(T.dihedral or 0))
    return function(u, v)
      local x = T.xr + (T.xt - T.xr) * u
      local z0 = T.zr0 + (T.zt0 - T.zr0) * u
      local z1 = T.zr1 + (T.zt1 - T.zr1) * u
      return V(s * x, T.y + (x - T.xr) * dih, z0 + (z1 - z0) * v)
    end
  end
  -- 舵面：后缘一条（v 从 v0 到 1，u 从 u0 到 u1）绕前边那条铰链线转；f(c, s) 给角度（正的是后缘往下）
  local function surface(T, s, u0, u1, v0, th, f, color, foldSide)
    local P = trapPt(T, s)
    local a, b = P(u0, v0), P(u1, v0)
    local axis = (b - a)
    if axis.Magnitude < 1e-3 then return end
    axis = axis.Unit * s   -- 两边都朝 +x：正角度后缘往下
    quad(a, P(u0, 1), P(u1, 1), b, th, color, MAT.Metal, "h", { hp = a, ax = axis, f = function(c) return f(c, s) end, fold = foldSide })
  end
  -- 主翼面（不动的部分）
  local function plate(T, s, u0, u1, v1, th, color, foldSide)
    local P = trapPt(T, s)
    quad(P(u0, 0), P(u0, v1), P(u1, v1), P(u1, 0), th, color, MAT.Metal, foldSide and "f" or "b", foldSide and { fold = foldSide } or nil)
  end

  ---------------------------------------------------------------- 挂的弹

  -- 一枚弹的零件：沿 −Z，cf 是弹体中心
  -- 挂的弹：按型号的外形（WeaponModels，和飞出去的弹、挂载编辑器里的一样）
  local WM = require(game:GetService("ReplicatedStorage"):WaitForChild("WeaponModels"))
  local function storeParts(w, cf, kind, extra)
    local list = {}
    for _, e in ipairs(WM.spec(w, false)) do
      table.insert(list, add(WM.part(e, m), cf * WM.offset(e), kind, extra and table.clone(extra)))
    end
    return list
  end
  -- 一个挂点挂 n 枚的摆法（相对挂点，弹体中心）
  local function layout(n, k, S, inBay)
    local L, dd = S.L, S.d
    if n == 1 then return V(0, -dd / 2, 0) end
    if n == 2 then return V(((k == 1) and -1 or 1) * dd * 0.68, -dd / 2 - 0.15, 0) end
    if n == 3 then
      if k == 3 then return V(0, -dd * 1.45, 0) end
      return V(((k == 1) and -1 or 1) * dd * 0.62, -dd / 2 - 0.1, 0)
    end
    if n == 4 then
      local col, row = (k - 1) % 2, math.floor((k - 1) / 2)
      return V((col - 0.5) * dd * 1.3, -dd / 2 - row * dd * 1.15, 0)
    end
    if n == 8 then   -- 旋转发射架：一圈 8 枚
      local a = (k - 1) / 8 * math.pi * 2
      return V(math.cos(a) * dd * 1.25, -dd * 1.4 + math.sin(a) * dd * 1.25, 0)
    end
    if n == 16 then   -- 前后两圈
      local ring = math.floor((k - 1) / 8)
      local a = ((k - 1) % 8) / 8 * math.pi * 2
      return V(math.cos(a) * dd * 1.25, -dd * 1.4 + math.sin(a) * dd * 1.25, (ring - 0.5) * L * 1.05)
    end
    -- 12 枚：弹舱里 3 排 × 2 列 × 2 层
    local i = k - 1
    local col, row, layer = i % 2, math.floor(i / 2) % 3, math.floor(i / 6)
    return V((col - 0.5) * dd * 1.6, -dd / 2 - layer * dd * 1.2, (row - 1) * L * 1.1)
  end
  local function buildStores()
    local AD = require(game:GetService("ReplicatedStorage"):WaitForChild("AirDefs"))
    local t0 = TAG
    TAG = "store"
    local adjs = imp and imp.info.pyl and imp.info.pyl[d.id]
    for i, s in ipairs(d.st or {}) do
      local wid = load and load[i]
      M.stores[i] = {}
      if wid then
        local w = AD.W[wid]
        local n = AD.count(s, wid)
        local S = w.shape or { L = 5, d = 0.6 }
        -- 原模型：挂点挪到原模型的机翼（短翼）下面——展向照型号表，前后挪到弦上，挂架顶贴着翼下表面（tools/models/air2glb.py 算好的）
        local pos, wy = s.pos, (d.wing and d.wing.y or 0) - 0.3
        local adj = adjs and adjs[i]
        if adj then
          -- 挂架（连发射导轨）高：真飞机 0.3～0.5 米，弹越粗挂架越高一点；直升机的发射架直接吊在短翼下（用户：飞机导弹挂架太长了——
          --   原来照型号表的高低差挂，进气道下的挂点吊下来三四格）
          local S0 = w.shape or { d = 0.6 }
          local hp = (d.kind == "heli") and math.clamp(0.2 + S0.d * 0.25, 0.25, 0.6) or math.clamp(0.35 + S0.d * 0.55, 0.6, 1.3)
          local ys = adj[1] + imp.O.Y
          pos = V(adj[3], ys - hp, adj[2])
          wy = ys
        end
        local side = (pos.X >= 0) and 1 or -1
        local fold = (d.fold and math.abs(pos.X) > d.fold) and side or nil
        local bayK = s.bay and ((s.bay == "main") and "bay" or "bayS") or nil
        -- 外挂：挂架（翼下的竖板）
        if not s.bay and d.kind == "jet" then
          local h = math.max(0.4, wy - pos.Y)
          local pyl = box(V(0.35, h, math.clamp(S.L * 0.38, 2.0, 5.5)), CF(pos.X, pos.Y + h / 2, pos.Z), skinD, MAT.Metal, fold and "f" or "b", fold and { fold = fold } or nil)
          table.insert(M.pylons, pyl)
          if n > 1 and w.kind ~= "rkt" then   -- 多联挂架的横梁
            box(V(S.d * 2.2, 0.3, S.L * 0.4), CF(pos.X, pos.Y - 0.15, pos.Z), skinD, MAT.Metal, fold and "f" or "b", fold and { fold = fold } or nil)
          end
        end
        local count = (w.kind == "rkt") and 1 or n
        for k = 1, count do
          local off = layout((w.kind == "rkt") and 1 or n, k, S, s.bay ~= nil)
          local cf = CF(pos + off)
          local kind, extra = "b", nil
          if s.bay and s.bay ~= "main" then   -- 侧弹舱：挂架连弹推出舱外
            kind = "m"
            local out = (pos.X >= 0) and 1 or -1
            extra = { f = function(c) local k2 = c.bayS or 0 return CF(out * 1.1 * k2, -1.5 * k2, 0) end }
          elseif fold then
            kind, extra = "f", { fold = fold }
          end
          local list = storeParts(w, cf, kind, extra)
          for _, it in ipairs(list) do
            it.st, it.k = i, k
            it.bayK = bayK
            table.insert(M.stores[i], it)
          end
        end
      end
    end
    TAG = t0
  end

  ---------------------------------------------------------------- 旋翼、尾桨、螺旋桨

  local function rotor(R, kind, spinKey, axis)
    local t0 = TAG
    TAG = "rotor"
    -- 桨毂坐标系：主旋翼轴是 Y；尾桨轴是 X（cant 往上斜）；螺旋桨轴是 Z
    local hub
    if axis == "y" then hub = CF(R.hub)
    elseif axis == "x" then hub = CF(R.hub) * CFrame.Angles(0, 0, rad(R.cant or 0)) * CFrame.Angles(0, 0, -math.pi / 2)   -- 把桨毂的 Y 轴转到 −X（尾桨在左边）
    else hub = CF(R.hub) * CFrame.Angles(math.pi / 2, 0, 0) end
    local dir = R.dir or 1
    local f = function(c) return (c[spinKey] or 0) * dir end
    local tiltF = (axis == "y") and function(c) return CFrame.Angles(-(c.pit or 0) * 0.07, 0, -(c.rol or 0) * 0.07) end or nil
    local n = R.blades
    local chord = R.chord or ((axis == "y") and 1.4 or 0.6)
    local th = (axis == "y") and 0.28 or 0.18
    -- 桨毂
    local hubD = (axis == "y") and 2.0 or 1.0
    add(newPart(m, V(hubD * 0.9, hubD, hubD), DARK, MAT.Metal, CYL), CF() * UPRIGHT, "r", { hub = hub, f = f, tilt = tiltF })
    for k = 1, n do
      local a = (k - 1) / n * math.pi * 2
      local scissor = (R.scissor and k % 2 == 0) and rad(-35) or 0
      local cf = CFrame.Angles(0, a + scissor, 0) * CF(R.r / 2 + hubD * 0.3, 0, 0) * CFrame.Angles(rad((axis == "y") and 6 or 4), 0, 0) * CFrame.Angles(0, 0, rad((axis == "y") and 2.5 or 0))
      local it = add(newPart(m, V(R.r, th, chord), DARK, MAT.SmoothPlastic), cf, "r", { hub = hub, f = f, tilt = tiltF })
      table.insert(M.blades, it)
      if axis == "y" then   -- 桨尖的黄色警示条
        local tip = add(newPart(m, V(1.2, th + 0.02, chord + 0.02), RGB(220, 190, 60), MAT.SmoothPlastic), CFrame.Angles(0, a, 0) * CF(R.r + hubD * 0.3 - 0.6, 0, 0) * CFrame.Angles(rad(6), 0, 0) * CFrame.Angles(0, 0, rad(2.5)), "r",
          { hub = hub, f = f, tilt = tiltF })
        table.insert(M.blades, tip)
      end
    end
    -- 转起来的桨盘（模糊的一圈）
    local disc = add(newPart(m, V(0.12, R.r * 2.05, R.r * 2.05), RGB(40, 42, 44), MAT.Glass, CYL, 1), CF(0, (axis == "y") and 0.25 or 0, 0) * UPRIGHT, "r", { hub = hub, f = function() return 0 end, tilt = tiltF })
    disc.p.CastShadow = false
    table.insert(M.discs, disc)
    TAG = t0
    return hub
  end

  ---------------------------------------------------------------- 起落架

  local function wheel(cf, r, w, kind, extra)
    local t0 = TAG
    TAG = "gear"
    local it = add(newPart(m, V(w, r * 2, r * 2), TIRE, MAT.SmoothPlastic, CYL), cf, kind, extra)
    add(newPart(m, V(w * 1.04, r * 1.1, r * 1.1), STEEL, MAT.Metal, CYL), cf, kind, extra and table.clone(extra))
    TAG = t0
    return it
  end
  -- 一根可收放的起落架：铰链在 top（机体坐标），收起绕 ax 转 ang（弧度，按 1 − gear）
  local function gearLeg(top, len, r, ax, ang, twin, bogie, fixed)
    local t0 = TAG
    TAG = "gear"
    local f = fixed and function() return 0 end or function(c) return (1 - (c.gear or 1)) * ang end
    local ex = { hp = top, ax = ax, f = f }
    box(V(0.5, len, 0.5), CF(top - V(0, len / 2, 0)), STEEL, MAT.Metal, "h", table.clone(ex))
    box(V(0.75, len * 0.35, 0.75), CF(top - V(0, len * 0.2, 0)), STEEL:Lerp(Color3.new(1, 1, 1), 0.3), MAT.Metal, "h", table.clone(ex))   -- 减震筒
    local bottom = top - V(0, len, 0)
    if bogie then
      box(V(0.5, 0.5, r * 4.6), CF(bottom), STEEL, MAT.Metal, "h", table.clone(ex))
      for _, dz in ipairs({ -r * 1.2, r * 1.2 }) do
        for _, dx in ipairs({ -0.7, 0.7 }) do wheel(CF(bottom + V(dx * r * 1.1, 0, dz)), r, r * 0.9, "h", table.clone(ex)) end
      end
    elseif twin then
      for _, dx in ipairs({ -0.55, 0.55 }) do wheel(CF(bottom + V(dx * r * 1.2, 0, 0)), r, r * 0.8, "h", table.clone(ex)) end
    else
      wheel(CF(bottom + V(0, 0, 0)), r, r * 0.9, "h", table.clone(ex))
    end
    TAG = t0
  end

  ---------------------------------------------------------------- 灯

  -- 夜战的灯（位置照真飞机）：一盏灯 = 霓虹小球 + 光晕（BillboardGui：远处看是一个亮点、近处一团光）+ 小范围的点光源（照亮旁边的蒙皮）
  --   mode：nav 航行灯常亮、beacon 红色防撞灯一秒闪一下（phase 错开）、strobe 白色频闪双闪、land 着陆灯（随起落架，射灯）
  local NAV_R, NAV_G, NAV_W, BEACON, STROBE = RGB(255, 46, 36), RGB(60, 255, 120), RGB(255, 250, 236), RGB(255, 40, 30), RGB(236, 244, 255)
  local function lamp(pos, color, mode, size, range, kind, extra, phase)
    local t0 = TAG
    TAG = "lamp"
    local it = neon(V(size, size, size), CF(pos), color, kind, extra)
    TAG = t0
    it.p.CastShadow = false
    local bb = Instance.new("BillboardGui")
    bb.Name = "Glow"
    bb.Size = UDim2.new(size * 6, 5, size * 6, 5)   -- 尺寸一半按格（近处大）一半按像素（远处也看得见一个点）
    bb.LightInfluence = 0
    bb.MaxDistance = 6000
    bb.Adornee = it.p
    bb.Parent = it.p
    local halo = Instance.new("Frame")
    halo.AnchorPoint, halo.Position, halo.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1)
    halo.BackgroundColor3, halo.BackgroundTransparency, halo.BorderSizePixel = color, 0.78, 0
    halo.Parent = bb
    local core = Instance.new("Frame")
    core.AnchorPoint, core.Position, core.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.34, 0.34)
    core.BackgroundColor3, core.BackgroundTransparency, core.BorderSizePixel = color:Lerp(Color3.new(1, 1, 1), 0.55), 0.02, 0
    core.Parent = bb
    for _, f in ipairs({ halo, core }) do
      local c = Instance.new("UICorner")
      c.CornerRadius = UDim.new(0.5, 0)
      c.Parent = f
    end
    local pl
    if mode == "land" then
      pl = Instance.new("SpotLight")
      pl.Face, pl.Angle, pl.Range, pl.Brightness = Enum.NormalId.Front, 38, 160, 6
      bb.Enabled = false
    else
      pl = Instance.new("PointLight")
      pl.Range = range
      pl.Brightness = (mode == "strobe") and 5 or ((mode == "beacon") and 2.5 or 1.4)
    end
    pl.Color, pl.Shadows = color, false
    pl.Parent = it.p
    it.lamp, it.bb, it.pl, it.phase = mode, bb, pl, phase or 0
    table.insert(M.lamps, it)
    return it
  end
  -- 一架飞机的整套灯：tip 右翼尖航行灯（左边对称是红的）、strobe 右翼尖频闪、tails 尾部白灯、top / bottom 防撞灯、land 着陆灯
  --   fold：翼尖的灯跟着折叠的外翼走（舰载机停在甲板上折翼）
  local function navLights(L0)
    if imp then L0 = impLights(L0, imp, d) end
    local fk = L0.fold and "f" or nil
    lamp(L0.tip, NAV_G, "nav", 0.42, 9, fk, fk and { fold = 1 } or nil)
    lamp(V(-L0.tip.X, L0.tip.Y, L0.tip.Z), NAV_R, "nav", 0.42, 9, fk, fk and { fold = -1 } or nil)
    if L0.strobe then
      lamp(L0.strobe, STROBE, "strobe", 0.36, 22, fk, fk and { fold = 1 } or nil)
      lamp(V(-L0.strobe.X, L0.strobe.Y, L0.strobe.Z), STROBE, "strobe", 0.36, 22, fk, fk and { fold = -1 } or nil)
    end
    for _, t in ipairs(L0.tails or {}) do lamp(t, NAV_W, "nav", 0.36, 7) end
    if L0.top then lamp(L0.top, BEACON, "beacon", 0.48, 14, nil, nil, 0) end
    if L0.bottom then lamp(L0.bottom, BEACON, "beacon", 0.48, 14, nil, nil, 0.5) end
    if L0.land then
      local it = lamp(L0.land, NAV_W, "land", 0.5, 0)
      it.cf0 = CFrame.lookAt(L0.land, L0.land + V(0, -0.12, -1))   -- 射灯朝前、稍微往下
    end
  end
  local function roundel(cf, r)
    local red, yel, blue, white = RGB(200, 30, 30), RGB(240, 200, 40), RGB(40, 60, 120), RGB(230, 230, 230)
    if d.stealth then red, yel, blue, white = skinD, skinL, skinD, skinL end
    if team == "atk" then
      cylY(0.06, r * 2, cf, yel, MAT.SmoothPlastic)
      cylY(0.08, r * 1.7, cf, red, MAT.SmoothPlastic)
      box(V(r * 3.2, 0.07, r * 0.55), cf * CF(0, 0, r * 0.2), red, MAT.SmoothPlastic)
    else
      cylY(0.06, r * 2, cf, blue, MAT.SmoothPlastic)
      cylY(0.08, r * 1.3, cf, white, MAT.SmoothPlastic)
      box(V(r * 3.6, 0.07, r * 0.6), cf, white, MAT.SmoothPlastic)
    end
  end
  local nPilot = 0
  local function pilot(cf, helmetColor)
    local t0 = TAG
    TAG = "pilot"
    nPilot += 1
    local neck = cf * CF(0, -0.2, 0.1)   -- 头绕脖子转
    local list = {
      add(newPart(m, V(1.5, 1.6, 1.1), RGB(70, 80, 60), MAT.Fabric), cf * CF(0, -0.9, 0.2)),
      add(newPart(m, V(0.95, 0.95, 0.95), RGB(230, 190, 150), MAT.SmoothPlastic, BALL), cf * CF(0, 0.25, 0), "b", { neck = neck }),
      add(newPart(m, V(1.12, 1.12, 1.12), helmetColor or RGB(230, 230, 220), MAT.SmoothPlastic, BALL), cf * CF(0, 0.38, 0.05), "b", { neck = neck }),
      add(newPart(m, V(0.8, 0.3, 0.2), DARK, MAT.Glass), cf * CF(0, 0.3, -0.5), "b", { neck = neck }),   -- 护目镜
    }
    for _, it in ipairs(list) do it.seat, it.ref = nPilot, cf end   -- 换原模型时照原模型座舱里的眼位重新摆
    TAG = t0
  end

  ---------------------------------------------------------------- 固定翼

  local function jet()
    local F = d.fus
    local L, w, h = F.len, F.w, F.h
    local y0 = F.y or 0
    local NL = { tails = {}, fold = d.fold ~= nil }   -- 夜航灯光的位置（下面一边建一边记，最后一起摆）
    local noseZ = -L / 2
    if d.flyingWing then
      ball(V(w, h, L), CF(0, y0, 0), skin)
      ball(V(w * 0.55, h * 0.9, L * 0.55), CF(0, y0 + h * 0.2, -L * 0.18), skin)
    else
      ball(V(w * 0.78, h * 0.86, L * 0.52), CF(0, y0, -L * 0.2), skin)   -- 前机身
      ball(V(w, h, L * 0.62), CF(0, y0, L * 0.06), skin)                  -- 中机身
      ball(V(w * 0.82, h * 0.78, L * 0.4), CF(0, y0, L * 0.3), skinD)      -- 尾锥
      box(V(w * 0.5, h * 0.32, L * 0.46), CF(0, y0 + h * 0.36, -L * 0.02), skin)   -- 背脊
      box(V(w * 0.86, h * 0.42, L * 0.5), CF(0, y0 - h * 0.22, L * 0.04), skin)    -- 平的机腹（弹舱、挂架）
      ball(V(w * 0.52, h * 0.58, (d.nose or 8) * 2), CF(0, y0 - h * 0.05, noseZ + (d.nose or 8)), d.stealth and skin or RADOME)   -- 雷达罩
      if not d.stealth then cylZ(2.2, 0.18, CF(0, y0 - h * 0.05, noseZ - 0.6), STEEL, MAT.Metal) end   -- 空速管
    end
    -- 座舱盖（停机打开：后铰链）、飞行员
    local Cn = d.canopy
    if Cn then
      local hinge = V(0, Cn.y + Cn.h * 0.15, Cn.z + Cn.len * 0.5)
      local canF = function(c) return (c.can or 0) * 0.85 end   -- 绕后铰链往上掀
      local ex = { hp = hinge, ax = V(1, 0, 0), f = canF, canopy = true }   -- canopy：弹射时抛掉
      ball(V(Cn.w, Cn.h * 1.7, Cn.len), CF(0, Cn.y, Cn.z), glass, MAT.Glass, "h", table.clone(ex), 0.35)
      box(V(Cn.w * 0.9, 0.18, 0.35), CF(0, Cn.y + Cn.h * 0.62, Cn.z + Cn.len * 0.1), skinD, MAT.Metal, "h", table.clone(ex))   -- 盖框
      pilot(CF(0, Cn.y - 0.2, Cn.z + Cn.len * 0.05), (team == "atk") and RGB(235, 235, 228) or RGB(110, 116, 96))
      if d.twoSeat then pilot(CF(0, Cn.y - 0.05, Cn.z + Cn.len * 0.38), (team == "atk") and RGB(235, 235, 228) or RGB(110, 116, 96)) end
      box(V(Cn.w * 0.6, 0.6, 1.2), CF(0, Cn.y - 0.3, Cn.z - Cn.len * 0.42), DARK, MAT.SmoothPlastic)   -- 平显
    end
    if d.drone and d.sat then ball(V(w * 1.05, h * 0.9, 7), CF(0, y0 + h * 0.3, noseZ + 5), skinL) end   -- 卫星通信天线的鼓包
    if d.drone then ball(V(1.6, 1.6, 1.6), CF(0, y0 - h * 0.55, noseZ + 6), DARK, MAT.Glass) end         -- 光电球
    -- 进气道
    if d.intake == "dsi" or d.intake == "caret" then
      for s = -1, 1, 2 do
        local x = s * (w * 0.5 + d.intakeW * 0.15)
        if d.intake == "dsi" then ball(V(d.intakeW * 1.3, h * 0.8, 9), CF(x, y0 + 0.1, d.intakeZ), skin) end
        box(V(d.intakeW, h * 0.75, 12), CF(x, y0 - 0.1, d.intakeZ + 6), skin)
        box(V(d.intakeW * 0.8, h * 0.6, 0.3), CF(x, y0 - 0.1, d.intakeZ - 0.1), DARK, MAT.SmoothPlastic)   -- 进气口
      end
    elseif d.intake == "box" then
      for s = -1, 1, 2 do
        local x = s * (d.nacelle and d.nacelle.x or w * 0.4)
        box(V(d.intakeW, h * 0.72, 12), CF(x, y0 - h * 0.42, d.intakeZ + 5), skin)
        box(V(d.intakeW * 0.86, h * 0.6, 0.3), CF(x, y0 - h * 0.42, d.intakeZ - 1.05), DARK, MAT.SmoothPlastic)
      end
    elseif d.intake == "dorsal" then
      box(V(d.intakeW * 1.6, h * 0.5, 12), CF(0, y0 + h * 0.55, d.intakeZ + 6), skin)
      box(V(d.intakeW * 1.4, h * 0.4, 0.3), CF(0, y0 + h * 0.55, d.intakeZ), DARK, MAT.SmoothPlastic)
    end
    if d.nacelle then   -- 发动机舱（歼-15、歼-16：两台发动机分开）
      for s = -1, 1, 2 do
        local Ez = d.eng[1].z
        cylZ(Ez - d.intakeZ, d.nacelle.w, CF(s * d.nacelle.x, y0 - h * 0.18, (Ez + d.intakeZ) / 2), skinD)
      end
    end
    -- 发动机吊舱（轰-6K 翼根、A-10 后机身上方）
    for _, pd in ipairs(d.pods or {}) do
      for s = -1, 1, 2 do
        cylZ(pd.len, pd.r * 2, CF(s * pd.x, pd.y, pd.z), skin)
        cylZ(0.4, pd.r * 1.7, CF(s * pd.x, pd.y, pd.z - pd.len / 2), DARK, MAT.SmoothPlastic)   -- 进气口
        cylZ(0.5, pd.r * 1.4, CF(s * pd.x, pd.y, pd.z - pd.len / 2 + 0.5), STEEL, MAT.Metal)    -- 风扇
        box(V(0.6, math.abs(pd.y) * 0.8 + 0.5, pd.len * 0.5), CF(s * pd.x, pd.y * 0.5, pd.z), skinD)   -- 挂架
      end
    end
    -- 尾喷口：收敛调节片随加力张开、加力火焰、马赫环
    for j, E in ipairs(d.eng or {}) do
      if imp and imp.info.noz and not E.prop then   -- 原模型：火焰从原模型的尾喷口喷（左右按最近的配）
        local best, bd = nil, math.huge
        for _, nz in ipairs(imp.info.noz) do
          local dd = math.abs(nz[1] - E.x) + math.abs(nz[3] - E.z) * 0.1
          if dd < bd then best, bd = nz, dd end
        end
        if best then E = setmetatable({ x = best[1], y = best[2] + imp.O.Y, z = best[3], r = best[4] }, { __index = E }) end
      end
      local tvcVec = nil
      if imp and TVC_ON[d.id] and not E.prop and not E.flat then
        local TI, TF = tvcAsset()
        if TI then
          local T = TI.tvc
          local k = E.r / T.r                            -- 外罩和原模型的喷口一样粗
          local side = (E.x >= 0) and 1 or -1
          local throat = V(E.x, E.y, E.z + 0.42 * k)    -- 铰链那一圈：外罩前沿正好贴着原模型的出口
          local function vec(c)
            local th = -((c.pit or 0) * TVC_P + side * (c.rol or 0) * TVC_R)
            return CF(throat) * CFrame.Angles(th, (c.yaw or 0) * TVC_Y, 0) * CF(-throat)
          end
          tvcVec = vec
          local hinge = {}
          for _, h in ipairs(T.petals) do hinge[h.g] = h end
          local t0 = TAG
          TAG = "tvc"
          for name, p in pairs(TI.parts) do
            local src = TF:FindFirstChild("A_tvc__" .. name)
            if src and src:IsA("BasePart") then
              local mp = Tint.fix(src:Clone(), src)
              mp.Anchored, mp.CanCollide, mp.CanQuery, mp.CanTouch, mp.CastShadow = true, false, false, false, false
              mp.Size = V(p.s[1], p.s[2], p.s[3]) * k
              if p.col and not mp:FindFirstChildOfClass("SurfaceAppearance") then mp.Color, mp.Material = RGB(p.col[1], p.col[2], p.col[3]), MAT.Metal end
              mp.Parent = m
              local cc0 = CF(throat + V(p.c[1], p.c[2], p.c[3]) * k) * TURN
              local H = hinge[p.g]
              local f = vec
              if H then   -- 调节片：绕自己的铰链张开
                local hp, ax = throat + V(H.p[1], H.p[2], H.p[3]) * k, V(H.a[1], H.a[2], H.a[3])
                f = function(c) return vec(c) * CF(hp) * CFrame.fromAxisAngle(ax, tvcOpen(c.thr or 0) * T.A) * CF(-hp) end
              end
              table.insert(M.tvc, add(mp, cc0, "m", { f = f, petal = H ~= nil }))
            end
          end
          TAG = t0
          E = setmetatable({ z = E.z + (0.42 + T.exit) * k }, { __index = E })   -- 火焰从推力矢量喷口的出口喷
        end
      end
      local base = CF(E.x, E.y, E.z)
      if E.fan then   -- 涡扇发动机进气口里的风扇（A-10）：跟着油门转，转快了是一圈模糊的盘
        rotor({ hub = V(E.x, E.y, E.z - E.fan), r = E.r * 1.2, blades = 14, chord = 0.32, dir = 1 }, "r", "spinF", "z")
      end
      if E.prop then   -- 推进式螺旋桨
        ball(V(E.r * 2.4, E.r * 2.4, 2.2), base * CF(0, 0, 0.4), skinD)
        local hub = rotor({ hub = V(E.x, E.y, E.z + 1.2), r = E.prop, blades = 3, chord = 0.55, dir = 1 }, "r", "spinP", "z")
        local _ = hub
      elseif E.flat then
        box(V(E.r * 2.6, E.r * 1.3, 3), base * CF(0, 0, -1.5), skinD, MAT.Metal, d.tvc and "h" or "b",
          d.tvc and { hp = V(E.x, E.y, E.z - 3), ax = V(1, 0, 0), f = function(c) return -(c.pit or 0) * rad(18) end } or nil)
        box(V(E.r * 2.2, E.r * 0.9, 0.2), base * CF(0, 0, 0.05), DARK, MAT.SmoothPlastic, d.tvc and "h" or "b",
          d.tvc and { hp = V(E.x, E.y, E.z - 3), ax = V(1, 0, 0), f = function(c) return -(c.pit or 0) * rad(18) end } or nil)
      else
        cylZ(3.2, E.r * 2.05, base * CF(0, 0, -1.6), E.cold and skinD or RGB(86, 82, 78), MAT.Metal)
        cylZ(0.2, E.r * 1.7, base * CF(0, 0, 0.02), DARK, MAT.SmoothPlastic)
        if d.ab then   -- 8 片调节片：加力时往外张
          for k = 0, 7 do
            local a = k / 8 * math.pi * 2
            local hp = (base * CF(0, 0, -0.2) * CFrame.Angles(0, 0, a) * CF(0, E.r * 0.98, 0)).Position
            local axis = (CF() * CFrame.Angles(0, 0, a) * V(1, 0, 0))
            box(V(E.r * 0.82, 0.12, 1.4), base * CFrame.Angles(0, 0, a) * CF(0, E.r * 0.95, 0.5), RGB(70, 66, 62), MAT.Metal, "h",
              { hp = hp, ax = axis, f = function(c) local t = c.thr or 0 return -(t > 100 and rad(12) * math.min(1, (t - 100) / 25) or rad(-4) * (1 - t / 100)) end })
          end
        end
      end
      if not E.prop then
        -- 尾焰（用户：尾部喷口是一根光柱，不真实；后来又说上一版的尾喷非常怪——那版拖着几团玻璃球当热浪，看着像一串气泡）：
        --   ① 热芯：喷口里凹进去一点的发光圆片，慢车暗红、军推橙、加力黄白（从后面看喷口里是亮的）
        --   ② 加力火焰：两条从喷口往后拉的光带（Beam，正对镜头）——外层橙色，粗→细、实→透明，长度跟着加力；里层蓝白的焰芯短一些；
        --      每帧长短、粗细轻轻抖一点（火焰在跳）；军推以下不画火焰
        --   ③ 热浪（用户 11-18：热浪太假了——原来是喷口后面几团抖动的玻璃球，一个个球的轮廓看得出来）：改成锁在喷口上的一股很淡的气流粒子，
        --      往后拉长、变粗、散掉，受月光照（不自己发光）；油门过两成半才有、越大越浓，加力时接在火焰后面；离镜头远了关掉
        local hot = { base = base, r = E.r, cold = E.cold, mild = E.mild, vec = tvcVec }   -- mild：涡扇（A-10），热芯暗一点
        local function hotItem(extra) return setmetatable(extra, { __index = hot }) end
        local core = E.flat and neon(V(0.12, E.r * 0.85, E.r * 2.1), base, RGB(150, 40, 20), "ab", hotItem({ core = true }), Enum.PartType.Block)   -- 二元喷口：扁的
          or neon(V(0.12, E.r * 1.55, E.r * 1.55), base, RGB(150, 40, 20), "ab", hotItem({ core = true }), CYL)
        core.p.Transparency = 1
        table.insert(M.flames, core)
        if d.ab and not E.cold then
          local src = newPart(m, V(0.2, 0.2, 0.2), RGB(255, 255, 255), MAT.SmoothPlastic, nil, 1)
          src.Name = "Plume"
          src.CastShadow = false
          local it = add(src, base, "ab", hotItem({ plume = true }))
          local a0 = Instance.new("Attachment")
          a0.Name = "P0"
          a0.Parent = src
          local function beam(name, col, tr, w0, w1)
            local a1 = Instance.new("Attachment")
            a1.Name = name .. "End"
            a1.Position = V(0, 0, 1)
            a1.Parent = src
            local bm = Instance.new("Beam")
            bm.Name = name
            bm.Attachment0, bm.Attachment1 = a0, a1
            bm.FaceCamera = true
            bm.Segments = 1
            bm.LightEmission, bm.LightInfluence = 1, 0
            bm.Color, bm.Transparency = col, tr
            bm.Width0, bm.Width1 = w0, w1
            bm.Enabled = false
            bm.Parent = src
            return bm, a1
          end
          local r = E.r
          it.outer, it.outerEnd = beam("AbFlame",
            ColorSequence.new({ ColorSequenceKeypoint.new(0, RGB(255, 226, 170)), ColorSequenceKeypoint.new(0.35, RGB(255, 150, 70)), ColorSequenceKeypoint.new(1, RGB(255, 80, 30)) }),
            NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.45, 0.45), NumberSequenceKeypoint.new(1, 1) }),
            r * 1.8, r * 0.5)
          it.inner, it.innerEnd = beam("AbCore",
            ColorSequence.new({ ColorSequenceKeypoint.new(0, RGB(214, 228, 255)), ColorSequenceKeypoint.new(0.5, RGB(255, 244, 226)), ColorSequenceKeypoint.new(1, RGB(255, 210, 150)) }),
            NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.6, 0.4), NumberSequenceKeypoint.new(1, 1) }),
            r * 1.1, r * 0.2)
          table.insert(M.flames, it)
        end
        if not E.cold then   -- 热浪：一股很淡的气流
          local hs = newPart(m, V(E.r * 1.1, E.r * 1.1, 0.2), RGB(255, 255, 255), MAT.SmoothPlastic, nil, 1)
          hs.Name = "Haze"
          hs.CastShadow = false
          local hz = add(hs, base, "ab", hotItem({ haze = true }))
          local r = E.r
          local pe = Instance.new("ParticleEmitter")
          pe.Name = "HeatHaze"
          pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
          pe.EmissionDirection = Enum.NormalId.Back   -- 从喷口往后
          pe.LockedToPart = true                      -- 跟着飞机走（不锁的话几百格每秒拖成一长条）
          pe.LightEmission, pe.LightInfluence = 0, 1  -- 不自己发光：只是被照到的一点灰白
          pe.Lifetime = NumberRange.new(0.18, 0.3)
          pe.Speed = NumberRange.new(r * 30, r * 40)
          pe.SpreadAngle = Vector2.new(6, 6)
          pe.Rotation = NumberRange.new(0, 360)
          pe.RotSpeed = NumberRange.new(-120, 120)
          pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, r * 0.8), NumberSequenceKeypoint.new(1, r * 2.8) })
          pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.97), NumberSequenceKeypoint.new(0.25, 0.92), NumberSequenceKeypoint.new(1, 1) })
          pe.Color = ColorSequence.new(RGB(196, 200, 206))
          pe.Rate = 0
          pe.Enabled = false
          pe.Parent = hs
          hz.pe = pe
          table.insert(M.flames, hz)
        end
      end
    end
    -- 机翼（舵面：后 22% 弦长；有折叠的在折叠线分开）
    local Wg = d.wing
    if Wg then
      local th = d.flyingWing and 1.2 or ((d.bomber or d.straight) and 0.9 or 0.55)
      local foldU = d.fold and math.clamp((d.fold - Wg.xr) / (Wg.xt - Wg.xr), 0.05, 0.95) or nil
      for s = -1, 1, 2 do
        local splitU = foldU or 0.5
        if foldU then
          plate(Wg, s, 0, foldU, 0.78, th, skin)
          plate(Wg, s, foldU, 1, 0.78, th, skin, s)
        else
          plate(Wg, s, 0, 1, 0.78, th, skin)
        end
        local K = rad(20)
        if d.elevon then   -- 无尾 / 三角翼：升降副翼（外段）、内段也跟着俯仰
          surface(Wg, s, 0.05, splitU, 0.78, th * 0.8, function(c, sd) return (-(c.pit or 0) * 0.8 - sd * (c.rol or 0) * 0.4) * K + (c.flap or 0) * rad(10) end, skinD)
          surface(Wg, s, splitU, 0.96, 0.78, th * 0.8, function(c, sd) return (-(c.pit or 0) - sd * (c.rol or 0)) * K end, skinD)
        else
          surface(Wg, s, 0.04, splitU, 0.78, th * 0.8, function(c, sd) return (c.flap or 0) * rad(32) - sd * (c.rol or 0) * rad(5) end, skinD)   -- 襟翼（襟副翼带一点滚转）
          surface(Wg, s, splitU, 0.95, 0.78, th * 0.8, function(c, sd) return -sd * (c.rol or 0) * K + (c.flap or 0) * rad(8) end, skinD, foldU and s or nil)   -- 副翼
        end
        if d.wingtipRudder then   -- 歼-50 翼尖全动舵面：偏航时上下张开
          local P = trapPt(Wg, s)
          local a, b = P(0.88, 0.1), P(1, 0.25)
          quad(a, P(0.88, 0.75), P(1, 0.8), b, th * 0.7, skinD, MAT.Metal, "h", { hp = a, ax = (P(0.88, 0.75) - a).Unit, f = function(c) return s * (c.yaw or 0) * rad(18) end })
        end
        if Wg.lerx then   -- 边条
          tri(V(s * w * 0.48, Wg.y + 0.2, Wg.zr0 - 9), V(s * Wg.xr, Wg.y, Wg.zr0), V(s * w * 0.48, Wg.y + 0.2, Wg.zr0 + 2), 0.4, skin)
        end
        if Wg.lambda then   -- λ 翼的折线前缘：外段补一块
          local P = trapPt(Wg, s)
          tri(P(0.45, 0), V(s * Wg.lambda.x, Wg.y, Wg.lambda.z - 6), P(0.75, 0.3), th, skin)
        end
      end
      -- 翼尖灯（航行灯在翼尖前段、频闪在后段，稍微探出翼尖）、国籍标志
      local P = trapPt(Wg, 1)
      NL.tip = P(1, 0.28) + V(0.25, 0, 0)
      NL.strobe = P(1, 0.82) + V(0.2, 0, 0)
      local pu = P(0.68, 0.45)
      roundel(CF(pu.X, pu.Y + th / 2 + 0.05, pu.Z), math.min(2.6, (Wg.xt - Wg.xr) * 0.1))
      roundel(CF(-pu.X, pu.Y + th / 2 + 0.05, pu.Z), math.min(2.6, (Wg.xt - Wg.xr) * 0.1))
    end
    if d.canard then
      local Cd = d.canard
      for s = -1, 1, 2 do
        local P = trapPt(Cd, s)
        local a, b = P(0, 0.4), P(1, 0.4)
        quad(P(0, 0), P(0, 1), P(1, 1), P(1, 0), 0.4, skin, MAT.Metal, "h", { hp = a, ax = (b - a).Unit * s, f = function(c) return (c.pit or 0) * rad(16) end })
      end
    end
    if d.htail then   -- 全动平尾（俯仰 + 差动滚转）
      local Ht = d.htail
      for s = -1, 1, 2 do
        local P = trapPt(Ht, s)
        local a, b = P(0, 0.35), P(1, 0.35)
        quad(P(0, 0), P(0, 1), P(1, 1), P(1, 0), 0.45, skin, MAT.Metal, "h",
          { hp = a, ax = (b - a).Unit * s, f = function(c) return (-(c.pit or 0) - s * (c.rol or 0) * 0.5) * rad(18) end })
      end
    end
    -- 垂尾（外倾；全动的整片转，否则后 30% 是方向舵）
    local Vt = d.vt
    if Vt then
      local xs = (Vt.x > 0) and { -1, 1 } or { 0 }
      for _, s in ipairs(xs) do
        local sx = (s == 0) and 1 or s
        local cant = rad(Vt.cant or 0)
        local y0f = Vt.y0 or (y0 + h * 0.3)
        local function pt(v, u)   -- v 0 根部～1 顶部，u 0 前缘～1 后缘
          local zA = Vt.zr0 + (Vt.zt0 - Vt.zr0) * v
          local zB = Vt.zr1 + (Vt.zt1 - Vt.zr1) * v
          local hh = Vt.h * v
          return V(s * Vt.x + sx * math.sin(cant) * hh * ((s == 0) and 0 or 1), y0f + math.cos(cant) * hh, zA + (zB - zA) * u)
        end
        local th = 0.45
        if Vt.allMove then
          local a, b = pt(0, 0.35), pt(1, 0.35)
          quad(pt(0, 0), pt(0, 1), pt(1, 1), pt(1, 0), th, skin, MAT.Metal, "h", { hp = a, ax = (b - a).Unit, f = function(c) return (c.yaw or 0) * rad(20) end })
        else
          quad(pt(0, 0), pt(0, 0.7), pt(1, 0.7), pt(1, 0), th, skin)
          local a, b = pt(0.05, 0.7), pt(1, 0.7)
          quad(a, pt(0.05, 1), pt(1, 1), b, th * 0.9, skinD, MAT.Metal, "h", { hp = a, ax = (b - a).Unit, f = function(c) return (c.yaw or 0) * rad(24) end })
        end
        local top = pt(1, 0.6)
        if Vt.endplate then box(V(1.2, 0.6, 3), CF(top), skinD) end
        table.insert(NL.tails, pt(1, 0.94) + V(0, 0.2, 0))   -- 尾部白灯：垂尾顶端后缘
        if team == "atk" and not d.stealth then box(V(0.06, Vt.h * 0.22, 2.4), CF(pt(0.6, 0.45)) * CF(s * 0.25, 0, 0), RGB(200, 30, 30), MAT.SmoothPlastic) end   -- 尾翼上的八一标志
      end
    end
    -- V 形 / 倒 V 形尾翼（无人机）：方向升降舵
    local VT = d.vtail
    if VT then
      for s = -1, 1, 2 do
        local ang = rad(VT.angle) * (VT.inverted and -1 or 1)
        local function pt(v, u)
          local zA = VT.z0 + 2 * v
          local zB = VT.z1
          local r = VT.h * v
          return V(s * math.sin(math.abs(ang)) * r, (F.y or 0) + 0.6 + math.cos(ang) * r * (VT.inverted and -1 or 1), zA + (zB - zA) * u)
        end
        quad(pt(0, 0), pt(0, 0.7), pt(1, 0.7), pt(1, 0), 0.35, skin)
        local a, b = pt(0.05, 0.7), pt(1, 0.7)
        quad(a, pt(0.05, 1), pt(1, 1), b, 0.3, skinD, MAT.Metal, "h", { hp = a, ax = (b - a).Unit, f = function(c) return ((c.yaw or 0) * s * -1 - (c.pit or 0)) * rad(18) end })
        table.insert(NL.tails, pt(1, 0.92))
      end
      if VT.ventral then box(V(0.3, 3.2, 3.5), CF(0, (F.y or 0) - 2.6, VT.z0 + 2.5), skin) end
    end
    -- 夜航灯光：没有垂尾的（飞翼）尾灯在后缘中间；防撞灯在机背（座舱后面）、机腹；着陆灯在前起落架舱前面
    if #NL.tails == 0 then table.insert(NL.tails, V(0, y0, L / 2 + 0.3)) end
    if NL.tip then
      if d.flyingWing then
        NL.top, NL.bottom = V(0, y0 + h * 0.66, -L * 0.04), V(0, y0 - h * 0.52, L * 0.04)
      else
        NL.top, NL.bottom = V(0, y0 + h * 0.52 + 0.25, L * 0.06), V(0, y0 - h * 0.43 - 0.25, L * 0.12)
      end
      if d.gear then NL.land = V(0, y0 - h * 0.46, d.gear.nose.z - 1.2) end
      navLights(NL)
    end
    -- 起落架、舱门
    local G = d.gear
    if G then
      local r = G.r
      local fixed = G.main.fixed
      local ntop = V(0, y0 - h * 0.38, G.nose.z)
      gearLeg(ntop, ntop.Y - (-d.gearH + r), r, V(1, 0, 0), rad(95), d.carrier, false, fixed)
      for s = -1, 1, 2 do   -- 前起落架舱门
        local hp = V(s * 0.9, y0 - h * 0.42, G.nose.z)
        box(V(0.12, 1.4, 4.2), CF(s * 0.95, y0 - h * 0.42 - 0.7, G.nose.z), skin, MAT.Metal, "h",   -- 放下时竖着开着，收起时往里合上
          { hp = hp, ax = V(0, 0, 1), f = function(c) return -s * (1 - math.min(1, (c.gear or 1) * 4)) * rad(85) end })
      end
      for s = -1, 1, 2 do
        local mx = s * G.main.x
        local topY = G.main.pod and (d.wing.y - 0.4) or ((math.abs(G.main.x) > w * 0.6) and (d.wing.y - 0.4) or (y0 - h * 0.35))
        local mtop = V(mx, topY, G.main.z)
        gearLeg(mtop, mtop.Y - (-d.gearH + r), r, V(0, 0, 1), -s * rad(88), false, G.main.bogie, fixed)
        if not fixed then
          local hp = V(mx - s * 0.4, topY - 0.1, G.main.z)
          box(V(2.6, 0.12, 3.6), CF(mx - s * 1.6, topY - 0.15, G.main.z), skin, MAT.Metal, "h",
            { hp = hp, ax = V(0, 0, 1), f = function(c) return s * math.min(1, (c.gear or 1) * 4) * rad(85) end })
        end
      end
      if G.hook then   -- 尾钩
        local hp = V(0, y0 - h * 0.4, G.hook)
        box(V(0.35, 0.35, 5.5), CF(0, y0 - h * 0.42, G.hook + 2.75), STEEL, MAT.Metal, "h", { hp = hp, ax = V(1, 0, 0), f = function(c) return (c.hook or 0) * rad(55) end })
        box(V(1.4, 0.4, 0.4), CF(0, y0 - h * 0.42, G.hook + 5.6), RGB(220, 190, 60), MAT.Metal, "h", { hp = hp, ax = V(1, 0, 0), f = function(c) return (c.hook or 0) * rad(55) end })
      end
    end
    -- 弹舱门：主弹舱两扇（外侧铰链往下开），侧弹舱一扇
    local B = d.bays
    if B and B.main then
      local bm = B.main
      local by = y0 - h * 0.44
      local len = bm.z1 - bm.z0
      local zc = (bm.z0 + bm.z1) / 2
      local halves = bm.twin and { -bm.twin, bm.twin } or { 0 }
      for _, cx in ipairs(halves) do
        local hw = (bm.twin and bm.w * 0.5 or bm.w) / 2
        box(V(hw * 2 - 0.3, 0.3, len), CF(cx, by + 0.6, zc), DARK, MAT.SmoothPlastic)   -- 舱里（暗）
        for s = -1, 1, 2 do
          local hp = V(cx + s * hw, by, zc)
          box(V(hw, 0.16, len), CF(cx + s * hw / 2, by - 0.05, zc), skin, MAT.Metal, "h",
            { hp = hp, ax = V(0, 0, 1), f = function(c) return s * (c.bay or 0) * rad(100) end })
        end
      end
    end
    if B and B.sideR then
      local bs = B.sideR
      for s = -1, 1, 2 do
        local len = bs.z1 - bs.z0
        local zc = (bs.z0 + bs.z1) / 2
        local hp = V(s * (bs.x + bs.w / 2), y0 - h * 0.3, zc)
        box(V(bs.w, 0.15, len), CF(s * bs.x, y0 - h * 0.34, zc), skin, MAT.Metal, "h",
          { hp = hp, ax = V(0, 0, 1), f = function(c) return s * (c.bayS or 0) * rad(105) end })
      end
    end
    if d.gunPos then   -- 炮口
      box(V(0.6, 0.6, 1.6), CF(d.gunPos), DARK, MAT.SmoothPlastic)
    end
  end

  ---------------------------------------------------------------- 直升机

  local function heli()
    local R = d.rotor
    local style = d.style
    local helmet = (team == "atk") and RGB(200, 204, 196) or RGB(84, 92, 70)
    if style == "attackheli" then
      local tw = d.tw
      ball(V(tw, 5.8, 20), CF(0, 0, -2.5), skin)
      ball(V(tw * 0.82, 4.4, 10), CF(0, -0.6, -11), skin)
      box(V(tw * 0.9, 2.2, 14), CF(0, -1.8, -2), skin)
      -- 串列座舱：前座射手、后座飞行员（后座高一截）
      ball(V(tw * 0.78, 3.6, 5.2), CF(0, 1.4, -9.8), GLASS, MAT.Glass, "b", nil, 0.3)
      ball(V(tw * 0.82, 4.0, 5.6), CF(0, 2.6, -5.0), GLASS, MAT.Glass, "b", nil, 0.3)
      pilot(CF(0, 1.1, -9.6), helmet)
      pilot(CF(0, 2.3, -4.8), helmet)
      -- 发动机舱、红外抑制排气口
      for s = -1, 1, 2 do
        cylZ(9, 2.6, CF(s * (tw * 0.55 + 0.6), 2.6, 1.5), skin)
        box(V(1.6, 1.6, 2.2), CF(s * (tw * 0.55 + 1.0), 2.6, 6.8), DARK, MAT.SmoothPlastic)
      end
      box(V(tw * 0.7, 2.6, 8), CF(0, 2.9, -0.5), skin)   -- 主减速器整流罩
      -- 尾梁、垂尾、平尾
      local tz = 6
      cylZ(d.boom, 2.4, CF(0, 1.6, tz + d.boom / 2), skin)
      cylZ(4, 1.6, CF(0, 1.9, tz + d.boom + 1.5), skin)
      local T = d.tail
      quad(V(0, 1.8, T.hub.Z - 3), V(0, 1.8, T.hub.Z + 2.5), V(0, T.hub.Y + 3.5, T.hub.Z + 1.2), V(0, T.hub.Y + 3.5, T.hub.Z - 1.4), 0.5, skin)
      quad(V(0, 1.4, T.hub.Z - 4), V(0, 1.4, T.hub.Z - 1), V(4.4, 1.4, T.hub.Z - 0.6), V(4.4, 1.4, T.hub.Z - 2.6), 0.35, skin)
      quad(V(0, 1.4, T.hub.Z - 4), V(0, 1.4, T.hub.Z - 1), V(-4.4, 1.4, T.hub.Z - 0.6), V(-4.4, 1.4, T.hub.Z - 2.6), 0.35, skin)
      rotor(T, "r", "spinT", "x")
      -- 短翼
      local S = d.stub
      for s = -1, 1, 2 do
        local x0, x1 = s * (tw * 0.45), s * (S.x + S.span)
        quad(V(x0, S.y, S.z - 1.8), V(x0, S.y, S.z + 1.8), V(x1, S.y, S.z + 1.4), V(x1, S.y, S.z - 1.2), 0.5, skin)
      end
      -- 机头炮塔、光电转塔
      local gp = d.gunPos
      ball(V(1.8, 1.6, 1.8), CF(gp), DARK, MAT.Metal, "t", { piv = gp, yawOnly = true })
      cylZ(5, 0.35, CF(gp) * CF(0, -0.1, -2.6), DARK, MAT.Metal, "t", { piv = gp })
      cylZ(1.4, 0.7, CF(gp) * CF(0, -0.1, -0.9), DARK, MAT.Metal, "t", { piv = gp })
      if d.tads then
        local tp = V(0, -0.6, -15.4)
        box(V(2.0, 1.6, 1.4), CF(tp), skinD, MAT.Metal, "t", { piv = tp, yawOnly = true })
        ball(V(1.1, 1.1, 0.4), CF(tp) * CF(-0.6, 0, -0.7), DARK, MAT.Glass, "t", { piv = tp })
        ball(V(1.1, 1.1, 0.4), CF(tp) * CF(0.6, 0, -0.7), DARK, MAT.Glass, "t", { piv = tp })
      else
        ball(V(1.5, 1.5, 1.5), CF(0, -1.8, -15.2), DARK, MAT.Glass, "t", { piv = V(0, -1.8, -15.2), yawOnly = true })
      end
      -- 固定起落架：两个主轮 + 尾轮
      for s = -1, 1, 2 do
        local top = V(s * 2.4, -2.6, -6)
        box(V(0.4, 2.5, 0.4), CF(top + V(s * 0.5, -1.0, 0)) * CFrame.Angles(0, 0, s * 0.35), STEEL, MAT.Metal)
        wheel(CF(s * 3.0, -d.gearH + 0.9, -6), 0.9, 0.6)
      end
      box(V(0.3, 1.6, 0.3), CF(0, 0.6, T.hub.Z - 2.5), STEEL, MAT.Metal)
      wheel(CF(0, -0.4, T.hub.Z - 2.5), 0.6, 0.35)
      if d.longbow then cylY(1.4, 3.0, CF(R.hub + V(0, 1.6, 0)), skinD, MAT.SmoothPlastic, "r", { hub = CF(R.hub), f = function() return 0 end }) end
      navLights({ tip = V(S.x + S.span + 0.2, S.y + 0.1, S.z - 0.6), tails = { V(0, T.hub.Y + 3.5, T.hub.Z + 1.3) },
        top = V(0, 4.45, 3.8), bottom = V(0, -2.75, -1.5), land = V(0, -2.4, -12.2) })   -- 短翼翼尖航行灯、垂尾顶白灯、主减速器后面 / 机腹防撞灯、机头下着陆灯
      cylY(R.hub.Y - 3.5, 0.9, CF(R.hub.X, (R.hub.Y + 3.5) / 2, R.hub.Z), STEEL, MAT.Metal)   -- 旋翼轴
      rotor(R, "r", "spin1", "y")
    elseif style == "utility" then
      local Cb = d.cabin
      local cw, ch, cl = Cb.w, Cb.h, Cb.len
      box(V(cw, ch * 0.8, cl * 0.8), CF(0, 0, -1), skin)
      ball(V(cw * 1.02, ch * 1.0, cl * 0.9), CF(0, 0.2, -1), skin)
      ball(V(cw * 0.9, ch * 0.85, 10), CF(0, -0.3, -cl * 0.45), skin)
      ball(V(cw * 0.86, ch * 0.62, 6.5), CF(0, 0.9, -cl * 0.47), GLASS, MAT.Glass, "b", nil, 0.3)   -- 座舱窗
      pilot(CF(-1.4, 0.4, -cl * 0.42), helmet)
      pilot(CF(1.4, 0.4, -cl * 0.42), helmet)
      for s = -1, 1, 2 do   -- 顶上两台发动机
        cylZ(8.5, 2.2, CF(s * 1.5, ch * 0.55, 2), skin)
        box(V(1.0, 1.0, 1.4), CF(s * 2.4, ch * 0.55, 6.6), DARK, MAT.SmoothPlastic)
      end
      box(V(cw * 0.5, 1.8, 10), CF(0, ch * 0.5, -1), skin)
      -- 两侧滑门：落地时往后滑开
      for s = -1, 1, 2 do
        box(V(0.2, ch * 0.75, 5.6), CF(s * (cw / 2 + 0.15), -0.2, -3.2), skinD, MAT.Metal, "m",
          { f = function(c) return CF(0, 0, (c.door or 0) * 5.4) end })
        box(V(0.08, 1.4, 1.6), CF(s * (cw / 2 + 0.26), 0.8, -3.2), GLASS, MAT.Glass, "m", { f = function(c) return CF(0, 0, (c.door or 0) * 5.4) end })   -- 门上的窗
        -- 舱门机枪
        local gpz = d.door.z
        box(V(0.25, 0.25, 3.6), CF(s * (cw / 2 + 0.9), 0.4, gpz) * CFrame.Angles(0, s * rad(90), 0), DARK, MAT.Metal)
        box(V(0.4, 1.4, 0.4), CF(s * (cw / 2 + 0.5), -0.3, gpz), STEEL, MAT.Metal)
      end
      local tz = cl * 0.35
      local T = d.tail
      cylZ(T.hub.Z - tz, 2.6, CF(0, 1.4, (T.hub.Z + tz) / 2), skin)
      quad(V(0, 1.6, T.hub.Z - 4), V(0, 1.6, T.hub.Z + 1.5), V(0, T.hub.Y + 2.8, T.hub.Z + 1.5), V(0, T.hub.Y + 2.8, T.hub.Z - 1.2), 0.5, skin)
      for s = -1, 1, 2 do   -- 全动平尾（跟着俯仰）
        local a = V(0, 1.2, T.hub.Z - 1.2)
        quad(a, V(0, 1.2, T.hub.Z + 1.2), V(s * 4.6, 1.2, T.hub.Z + 1.2), V(s * 4.6, 1.2, T.hub.Z - 1.0), 0.3, skin, MAT.Metal, "h",
          { hp = a, ax = V(s, 0, 0) * s, f = function(c) return -(c.pit or 0) * rad(10) end })
      end
      rotor(T, "r", "spinT", "x")
      for s = -1, 1, 2 do
        box(V(0.4, 2.4, 0.4), CF(s * 3.0, -ch / 2 - 1.0, -7), STEEL, MAT.Metal)
        wheel(CF(s * 3.2, -d.gearH + 0.95, -7), 0.95, 0.7)
      end
      wheel(CF(0, -1.4, T.hub.Z - 6), 0.6, 0.4)
      -- 外挂架短翼（挂了东西才有；原模型没有短翼，这个照旧拼）
      TAG = "store"
      for i, s in ipairs(d.st or {}) do
        if load and load[i] then
          local sd = (s.pos.X >= 0) and 1 or -1
          local p = box(V(4.6, 0.4, 2.6), CF(sd * (cw / 2 + 2.2), s.pos.Y + 0.6, s.pos.Z), skinD)
          table.insert(M.pylons, p)
        end
      end
      TAG = nil
      navLights({ tip = V(cw / 2 + 0.15, ch * 0.42, -3), tails = { V(0, T.hub.Y + 2.9, T.hub.Z + 1.2) },
        top = V(0, ch * 0.5 + 1.25, 4.5), bottom = V(0, -ch / 2 - 0.2, -2), land = V(0, -ch / 2 - 0.15, -cl * 0.38) })   -- 座舱两侧航行灯、垂尾顶白灯、发动机后面 / 机腹防撞灯
      cylY(R.hub.Y - ch * 0.6, 0.9, CF(R.hub.X, (R.hub.Y + ch * 0.6) / 2, R.hub.Z), STEEL, MAT.Metal)
      rotor(R, "r", "spin1", "y")
    elseif style == "chinook" then
      local Cb = d.cabin
      local cw, ch = Cb.w, Cb.h
      box(V(cw, ch * 0.86, 38), CF(0, 0, 0), skin)
      ball(V(cw * 1.02, ch * 1.0, 40), CF(0, 0.3, 0), skin)
      ball(V(cw * 0.94, ch * 0.9, 10), CF(0, -0.1, -19.5), skin)
      ball(V(cw * 0.86, ch * 0.5, 6), CF(0, 1.6, -20.5), GLASS, MAT.Glass, "b", nil, 0.3)
      pilot(CF(-1.6, 1.0, -20), helmet)
      pilot(CF(1.6, 1.0, -20), helmet)
      box(V(cw * 0.6, 4, 7), CF(0, ch * 0.5, -15.5), skin)   -- 前塔
      box(V(cw * 0.7, 7.5, 12), CF(0, ch * 0.5 + 2, 15), skin)   -- 后塔（高）
      for s = -1, 1, 2 do
        cylZ(7.5, 2.6, CF(s * (cw * 0.5 + 0.8), ch * 0.4 + 1.5, 16), skin)   -- 发动机
        box(V(1.6, ch * 0.32, 30), CF(s * (cw / 2 + 0.7), -ch * 0.34, -1), skinD)   -- 侧面油箱整流罩
        for _, z in ipairs({ -11, 10 }) do
          box(V(0.45, 2.2, 0.45), CF(s * 3.6, -ch / 2 - 0.6, z), STEEL, MAT.Metal)
          wheel(CF(s * 3.8, -d.gearH + 1.0, z), 1.0, 0.75)
        end
      end
      -- 后跳板：落地放下
      local hp = V(0, -ch / 2 + 0.3, 19.2)
      box(V(cw * 0.86, 5.6, 0.45), CF(0, -ch / 2 + 0.3 + 2.8, 19.2), skinD, MAT.Metal, "h", { hp = hp, ax = V(1, 0, 0), f = function(c) return (c.ramp or 0) * rad(78) end })
      navLights({ tip = V(cw / 2 + 1.6, -ch * 0.3, -1), tails = { V(0, ch * 0.5 + 5.9, 21.2) },
        top = V(0, ch * 0.5 + 6.1, 13), bottom = V(0, -ch / 2 - 0.2, 0), land = V(0, -ch / 2 - 0.15, -18) })   -- 侧面油箱整流罩航行灯、后塔顶白灯和防撞灯、机腹防撞灯
      rotor(R, "r", "spin1", "y")
      rotor(d.rotor2, "r", "spin2", "y")
    end
  end

  if d.kind == "heli" then heli() else jet() end
  buildStores()
  -- 原模型的活动部件：绕铰链转（S.a → S.b，模型坐标；cc0 是这块不转时的样子）
  local function addSurf(mp, cc0, S, I, O)
    if S.k == "gdoor" then   -- 起落架舱门、轮舱：不转，收到一半藏起来
      add(mp, cc0, "b", { vis = function(c) return (c.gear or 1) > 0.5 end })
      return
    end
    if S.k == "kf" then   -- 原模型动画里的部件（F-22A 的起落架、舱门、侧弹舱门和发射架）：按操纵量在动画的关键帧之间插值
      --   每帧 { dx, dy, dz, qx, qy, qz, qw }：绕支点 p 转 q、支点挪 d；ch 是 gear（0 收起～1 放下）或 bayS（0 关～1 开）
      local K = {}
      for i, k in ipairs(S.key) do K[i] = CFrame.new(k[1], k[2], k[3], k[4], k[5], k[6], k[7]) end
      local P = V(S.p[1], S.p[2], S.p[3]) + O
      local PC, PCi = CF(P), CF(-P)
      local n, ch, def = #K, S.ch, (S.ch == "gear") and 1 or 0
      local lastU, lastC = nil, nil
      add(mp, cc0, "m", { kf = S.ch, f = function(c)
        local u = math.clamp(c[ch] or def, 0, 1)
        if u ~= lastU then   -- 操纵量没变就不重算（飞行中起落架一直收着）
          local x = u * (n - 1) + 1
          local i = math.min(n - 1, math.floor(x))
          lastU, lastC = u, PC * K[i]:Lerp(K[i + 1], x - i) * PCi
        end
        return lastC
      end })
      return
    end
    local f = SURF_F[S.k]
    local a, b = V(S.a[1], S.a[2], S.a[3]) + O, V(S.b[1], S.b[2], S.b[3]) + O
    if not f or (b - a).Magnitude < 1e-4 then add(mp, cc0, "b") return end
    local sg, s, A = S.sg or 1, S.s or 0, S.A or 0
    local ex = { hp = a, ax = (b - a).Unit, f = function(c) return sg * f(c, s, A) end }
    if S.k == "gear" then ex.vis = function(c) return (c.gear or 1) > 0.03 end end   -- 收到底就藏起来（收进去的部分别从蒙皮里穿出来）
    if S.k == "gear" and (S.s or 0) == 0 then ex.steer = true end   -- 前起落架（中间那根）：地上滑行时跟着方向舵左右转
    if S.k == "canopy" then ex.canopy = true end   -- 弹射时抛掉
    if S.fold then ex.fold = S.fold end   -- 歼-15 折叠外翼上的：跟着外翼折
    if S.tip then   -- 平尾外段上的：跟着平尾外段的铰链折
      local F = I.fold and I.fold.Tip
      if F then ex.fh, ex.fold = { x = F.x, y = F.y + O.Y, A = F.A }, S.tip end
    end
    add(mp, cc0, "h", ex)
  end
  if imp then
    -- 蒙皮换成原模型：零件拼的只留挂架和弹、灯、加力火焰，模型没带起落架的固定翼留零件拼的起落架
    local keepGear = d.kind == "jet" and (not imp.info.gear or imp.noGear)
    local pit = imp.info.pit   -- 原模型座舱里飞行员头的位置（一个座位一个）
    local n = 0
    for i = 1, #items do
      local it = items[i]
      local t = it.tag
      if it.kind == "ab" or t == "lamp" or t == "store" or t == "tvc" or (t == "gear" and keepGear) or (t == "pilot" and pit and pit[it.seat]) then
        if t == "pilot" then   -- 挪进原模型的座舱：眼位往下 0.3 格、往后 0.3 格是零件拼的那个参考点（头的中心偏下）
          local e = pit[it.seat]
          local mv = CF(V(e[1], e[2] - 0.3, e[3] + 0.3) + imp.O) * it.ref:Inverse()
          it.cf0 = mv * it.cf0
          if it.neck then it.neck = mv * it.neck end
        end
        n += 1
        items[n] = it
      else
        it.p:Destroy()
      end
    end
    for i = #items, n + 1, -1 do items[i] = nil end
    M.blades, M.discs = {}, {}
    local I, O = imp.info, imp.O
    for name, p in pairs(I.parts) do
      local src = imp.folder:FindFirstChild("A_" .. imp.key .. "__" .. name)
      if src and src:IsA("BasePart") then
        local mp = Tint.fix(src:Clone(), src)
        mp.Anchored, mp.CanCollide, mp.CanQuery, mp.CanTouch = true, false, false, false
        mp.Size = V(p.s[1], p.s[2], p.s[3])
        local okT, tid = pcall(function() return mp.TextureID end)   -- 不是 MeshPart 的没有这个属性
        local bare = not mp:FindFirstChildOfClass("SurfaceAppearance") and (not okT or (tid or "") == "")
        if imp.plain then   -- 拿美军机代的：去掉原机涂装（国籍标志、舷号在底色贴图里），按我方蒙皮色
          for _, sa in ipairs(mp:GetChildren()) do if sa:IsA("SurfaceAppearance") then sa:Destroy() end end
          pcall(function() mp.TextureID = "" end)
          if not p.a then mp.Color, mp.Material = skin, MAT.SmoothPlastic end
        elseif p.col and bare then   -- 原模型这块本来就没贴图：照原材质颜色（Studio 导入不一定带过来）
          mp.Color = RGB(p.col[1], p.col[2], p.col[3])
          mp.Material = p.met and MAT.Metal or MAT.SmoothPlastic
          if p.a then mp.Transparency = 1 - p.a end
        end
        mp.Parent = m
        local c = V(p.c[1], p.c[2], p.c[3]) + O
        local cc0 = CF(c) * TURN   -- 这块在机体坐标里的样子（补回导入时转掉的半圈）
        local g = p.g
        local S = I.surf and I.surf[g]
        if imp.noGear and (g == "Gear" or (S and (S.k == "gear" or S.k == "gdoor"))) then   -- 不是真起落架（见 NOGEAR）：当蒙皮一直画
          add(mp, cc0, "b")
        elseif S then   -- 活动部件（舵面、弹舱门、座舱盖、起落架支柱）：绕原模型上切出来的铰链转
          addSurf(mp, cc0, S, I, O)
        elseif g == "Gear" then   -- 起落架：收起时藏起来
          add(mp, cc0, "b", { vis = function(cc) return (cc.gear or 1) > 0.5 end })
        elseif g == "Rotor" or g == "Rotor2" or g == "TRotor" then
          local R = I[string.lower(g)]
          local R0 = (g == "Rotor" and d.rotor) or (g == "Rotor2" and d.rotor2) or nil
          local hub = CF(V(R.p[1], R.p[2], R.p[3]) + O) * axisY(V(R.a[1], R.a[2], R.a[3]).Unit)
          local spinKey = (g == "Rotor" and "spin1") or (g == "Rotor2" and "spin2") or "spinT"
          local dir = R0 and R0.dir or 1
          local tilt = (g ~= "TRotor") and function(cc) return CFrame.Angles(-(cc.pit or 0) * 0.07, 0, -(cc.rol or 0) * 0.07) end or nil
          local it = add(mp, hub:Inverse() * cc0, "r", { hub = hub, f = function(cc) return (cc[spinKey] or 0) * dir end, tilt = tilt })
          if BLUR[imp.key] and BLUR[imp.key][name] then
            mp.CastShadow = false
            mp.Transparency = 1
            table.insert(M.discs, it)
          else
            table.insert(M.blades, it)
          end
        elseif g == "FoldR" or g == "FoldL" then   -- 舰载机折叠的外翼：绕原模型的铰链（M.foldH）
          add(mp, cc0, "f", { fold = (g == "FoldR") and 1 or -1 })
        elseif g == "TipR" or g == "TipL" then   -- 平尾外段：自己的铰链
          local F = I.fold and I.fold.Tip
          add(mp, cc0, "f", { fold = (g == "TipR") and 1 or -1, fh = F and { x = F.x, y = F.y + O.Y, A = F.A } or nil })
        else
          add(mp, cc0, "b")
        end
      end
    end
    for _, w in ipairs(I.wells or {}) do
      local wp = newPart(m, V(math.max(w.s[1] - 0.1, 0.1), math.max(w.s[2], 0.1), math.max(w.s[3] - 0.1, 0.1)), DARK, MAT.SmoothPlastic)
      wp.CastShadow = false
      add(wp, CF(V(w.c[1], w.c[2], w.c[3]) + O), "b")
    end
    local F = I.fold and I.fold.Fold
    if F then M.foldH = { x = F.x, y = F.y + O.Y, A = F.A } end
    M.imported = imp.key
  end

  -- 血条、名字挂的点（机顶）
  local anchor = Instance.new("Part")
  anchor.Size, anchor.Transparency, anchor.Anchored = V(0.2, 0.2, 0.2), 1, true
  anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = false, false, false
  anchor.Parent = m
  M.anchor = anchor
  M.plist, M.clist = {}, {}
  for i, it in ipairs(items) do M.plist[i] = it.p end
  M.n = #items
  M.blur = -1
  M.storeStr = nil
  return M
end

---------------------------------------------------------------- 挂的弹：打掉一枚藏一枚

function AM.setStores(M, str)
  if M.storeStr == str then return end
  M.storeStr = str
  for i, list in pairs(M.stores) do
    local n = str and (string.byte(str, i) or 48) - 48 or 99
    for _, it in ipairs(list) do it.gone = it.k > n end
  end
  M.bayVis = nil
end

---------------------------------------------------------------- 每帧：摆零件

local function foldCF(M, side, c)
  local d = M.def
  local H = M.foldH   -- 原模型：照原模型的铰链和折起的角度
  if H then return CF(side * H.x, H.y, 0) * CFrame.Angles(0, 0, side * (c.fold or 0) * H.A) * CF(-side * H.x, -H.y, 0) end
  local hx = side * d.fold
  local y = d.wing.y
  return CF(hx, y, 0) * CFrame.Angles(0, 0, side * (c.fold or 0) * rad(100)) * CF(-hx, -y, 0)
end

function AM.pose(M, cf, c, now, world)
  local plist, clist = M.plist, M.clist
  local cam = workspace.CurrentCamera
  M.near = (world == nil) and cam ~= nil and (cf.Position - cam.CFrame.Position).Magnitude < 700   -- 热浪只画近处的（挂载编辑器里不画）
  local fold = { [1] = nil, [-1] = nil }
  if M.def.fold then fold[1], fold[-1] = foldCF(M, 1, c), foldCF(M, -1, c) end
  -- 弹舱里的弹：舱门开了才看得见
  local bayOpen, baySOpen = (c.bay or 0) > 0.15, (c.bayS or 0) > 0.15
  local vis = (bayOpen and "1" or "0") .. (baySOpen and "1" or "0")
  local visChanged = M.bayVis ~= vis
  M.bayVis = vis
  for i, it in ipairs(M.items) do
    local k = it.kind
    local base = cf
    if it.fh then   -- 自己有铰链的折叠面（原模型歼-15 的平尾外段）
      local h, sd = it.fh, it.fold
      base = cf * CF(sd * h.x, h.y, 0) * CFrame.Angles(0, 0, sd * (c.fold or 0) * h.A) * CF(-sd * h.x, -h.y, 0)
    elseif it.fold then base = cf * fold[it.fold] end
    local out
    if k == "b" then
      if it.neck then out = cf * it.neck * CFrame.Angles(0, c.hy or 0, 0) * CFrame.Angles(c.hp or 0, 0, 0) * it.neck:Inverse() * it.cf0   -- 飞行员的头：c.hy 左右、c.hp 上下（Fly.lua 算）
      else out = cf * it.cf0 end
    elseif k == "f" then out = base * it.cf0
    elseif k == "h" then
      if it.steer then out = base * it.H * CFrame.fromAxisAngle(it.ax, it.f(c)) * CFrame.Angles(0, -(c.steer or 0), 0) * it.off   -- 前轮转向（c.steer 往右为正）
      else out = base * it.H * CFrame.fromAxisAngle(it.ax, it.f(c)) * it.off end
    elseif k == "m" then out = cf * it.f(c) * it.cf0
    elseif k == "r" then
      local hub = cf * it.hub
      if it.tilt then hub = hub * it.tilt(c) end
      out = hub * CFrame.Angles(0, it.f(c), 0) * it.cf0
    elseif k == "t" then
      local yaw = -rad(c.ty or 0)
      local piv = CF(it.piv)
      if it.yawOnly then out = cf * piv * CFrame.Angles(0, yaw, 0) * CF(-it.piv) * it.cf0
      else out = cf * piv * CFrame.Angles(0, yaw, 0) * CFrame.Angles(rad(c.gp or 0), 0, 0) * CF(-it.piv) * it.cf0 end
    elseif k == "ab" then   -- 尾焰：喷口里的热芯、加力火焰的光带，都跟着油门；推力矢量喷口跟着出口偏
      local t = c.thr or 0
      local b0 = it.vec and (it.vec(c) * it.base) or it.base
      local ab = (t > 100) and math.min(1, (t - 100) / 25) or 0
      local r = it.r
      local tr = 1
      if it.core then
        out = cf * b0 * CF(0, 0, -0.25) * ALONG_Z   -- 凹进喷口一点：从侧面看不见，从后面看喷口里发亮
        if it.mild then   -- 涡扇：喷口里只有暗暗的橙红（排气温度低）
          tr = math.clamp(0.98 - t / 100 * 0.32, 0.62, 0.98)
          local col = RGB(110, 36, 18):Lerp(RGB(196, 84, 36), math.clamp(t / 100, 0, 1))
          if it.p.Color ~= col then it.p.Color = col end
        elseif not it.cold then
          tr = (ab > 0) and (0.04 + (1 - ab) * 0.18) or math.clamp(0.95 - t / 100 * 0.55, 0.4, 0.95)
          local col = (ab > 0) and RGB(255, 190, 110):Lerp(RGB(255, 242, 214), ab) or RGB(150, 40, 20):Lerp(RGB(255, 118, 42), math.clamp(t / 100, 0, 1))
          if it.p.Color ~= col then it.p.Color = col end
        end
      elseif it.plume then   -- 加力火焰的光带：长短、粗细跟着加力，每帧轻轻抖一点
        out = cf * b0 * CF(0, 0, 0.1)
        local on = ab > 0.02
        if on ~= it.on then
          it.on = on
          it.outer.Enabled, it.inner.Enabled = on, on
        end
        if on then
          local fl = 1 + 0.06 * math.sin((now or 0) * 37 + r) + 0.04 * math.sin((now or 0) * 61)
          it.outerEnd.Position = V(0, 0, r * (3.2 + 4.5 * ab) * fl)
          it.innerEnd.Position = V(0, 0, r * (1.6 + 1.6 * ab) * (2 - fl))
          it.outer.Width0 = r * (1.55 + 0.25 * ab) * fl
        end
      elseif it.haze then   -- 热浪：气流粒子（加力时接在火焰后面）；油门过两成半、离镜头近才放，分 6 档，变了才改（每帧改粒子属性费）
        out = cf * b0 * CF(0, 0, (ab > 0) and r * (4.5 + 3 * ab) or r * 0.4)
        local q = (not it.cold and t > 25 and M.near) and math.clamp(math.floor((math.min(t, 100) - 25) / 15) + 1 + ((ab > 0) and 1 or 0), 1, 6) or 0
        if q ~= it.q and it.pe then
          it.q = q
          it.pe.Enabled = q > 0
          if q > 0 then it.pe.Rate = (it.mild and 10 or 16) * q end
        end
      end
      if math.abs(it.p.Transparency - tr) > 0.01 then it.p.Transparency = tr end
    else out = cf * it.cf0 end
    clist[i] = out
    if it.vis then   -- 原模型的起落架：收起时藏起来
      local on = it.vis(c)
      if on ~= it.visOn then
        it.visOn = on
        it.p.Transparency = on and it.tr0 or 1
      end
    end
    if it.st and (visChanged or it.goneSeen ~= it.gone) then   -- 挂的弹：打掉的、弹舱关着的藏起来
      it.goneSeen = it.gone
      local hide = it.gone or (it.bayK == "bay" and not bayOpen) or (it.bayK == "bayS" and not baySOpen)
      it.p.Transparency = hide and 1 or it.tr0
    end
  end
  (world or workspace):BulkMoveTo(plist, clist, Enum.BulkMoveMode.FireCFrameChanged)
  -- 旋翼：转快了桨叶变虚、桨盘出现
  local rpm = c.rpm or 0
  local blur = (rpm > 55) and 1 or 0
  if blur ~= M.blur then
    M.blur = blur
    for _, it in ipairs(M.blades) do it.p.Transparency = (blur == 1) and 0.72 or 0 end
    for _, it in ipairs(M.discs) do it.p.Transparency = (blur == 1) and 0.86 or 1 end
  end
  -- 灯：航行灯常亮；防撞灯一秒闪一下（机背、机腹错开半拍）；翼尖频闪双闪；着陆灯随起落架；被击毁 / 关灯（M.dark）全灭
  local gearDown = (c.gear or 0) > 0.6
  for _, it in ipairs(M.lamps) do
    local on = not M.dark
    if on then
      if it.lamp == "beacon" then on = ((now + it.phase) % 1.0) < 0.12
      elseif it.lamp == "strobe" then local u = now % 1.3 on = u < 0.05 or (u > 0.16 and u < 0.21)
      elseif it.lamp == "land" then on = gearDown end
    end
    if it.on ~= on then
      it.on = on
      it.p.Transparency = on and 0 or 0.92
      if it.lamp ~= "land" then it.bb.Enabled = on end
      it.pl.Enabled = on
    end
  end
  M.anchor.CFrame = cf * CF(0, M.def.H * 0.7 + 2, 0)
end

---------------------------------------------------------------- 飞机动画第二批用（AirAnim.lua）：加跟着机体的零件、飞行员显隐、弹射、翼尖位置

-- 加一个跟着机体走的零件（翼尖涡流的拖尾架、凝结雾的发射点）：cf0 是机体坐标
function AM.attach(M, part, cf0)
  part.Parent = M.model
  local it = { p = part, cf0 = cf0, kind = "b", tr0 = part.Transparency }
  table.insert(M.items, it)
  M.plist[#M.items] = part
  M.n = #M.items
  return it
end

-- 飞行员显隐（座舱里没人时不画；弹射以后不再画）
function AM.setPilots(M, on)
  if M.ejected then on = false end
  if M.pilotsOn == on then return end
  M.pilotsOn = on
  for _, it in ipairs(M.items) do
    if it.tag == "pilot" then it.p.Transparency = on and it.tr0 or 1 end
  end
end

-- 机体坐标里第 seat 个座位的飞行员身子（没有座舱的返回 nil）
function AM.seatCF(M, seat)
  for _, it in ipairs(M.items) do
    if it.tag == "pilot" and it.seat == (seat or 1) and not it.neck then return it.cf0 end
  end
  return nil
end

-- 弹射：座舱盖、飞行员藏起来；返回座舱盖每块复制出来的零件和它现在的世界位置（AirAnim 让它们翻滚着飞走）
function AM.eject(M, cf)
  local caps = {}
  for i, it in ipairs(M.items) do
    if it.canopy and it.p.Transparency < 1 then
      local ok, q = pcall(function() return it.p:Clone() end)
      if ok and q then
        q.Anchored, q.CanCollide, q.CanQuery, q.CanTouch = true, false, false, false
        table.insert(caps, { p = q, cf = (M.clist and M.clist[i]) or (cf * it.cf0) })
      end
      it.p.Transparency = 1
      it.tr0 = 1
    end
  end
  M.ejected = true
  M.pilotsOn = nil
  AM.setPilots(M, false)
  return caps
end

-- 左右翼尖后缘（机体坐标；翼尖涡流从这里拖出去）
function AM.tips(M)
  local d = M.def
  if M.imp and M.imp.info.tip then
    local t, oy = M.imp.info.tip, M.imp.O.Y
    return V(t[1], t[2] + oy, t[4]), V(-t[1], t[2] + oy, t[4])
  end
  local w = d.wing
  if not w or not w.xt then return nil end
  return V(w.xt, (w.y or 0), w.zt1 or 0), V(-w.xt, (w.y or 0), w.zt1 or 0)
end

return AM
