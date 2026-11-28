-- Roblox全面大战场（客户端）——地面载具的样子：导入了原模型就用原模型（见下），没有就按 VehDefs 的尺寸用零件拼——车体（首上装甲、侧裙、发动机舱、反应装甲块）、
--   履带车的负重轮 / 主动轮 / 诱导轮 / 履带（下面一段段跟着负重轮上下）、轮式车的车轮（带轮毂、挡泥板，前轴转向）、
--   各式炮塔（楔形、圆形、艾布拉姆斯、步战车、遥控武器站、自行高炮、火神炮、自行榴弹炮、发射箱）、炮管（抽烟装置、炮口制退器）、
--   烟幕弹发射筒（就装在 VehDefs 规定的位置、朝规定的方向）
--   返回 { model, parts = { { 零件, 组, 相对位置 } }, wheels = { … } }：组是 hull（车体）/ turret / gun / wheel（第几个轮）/ seg（履带段）
--   每帧由 View 按车体、炮塔、炮、各轮的姿态算出零件位置（BulkMoveTo）
local VehModels = {}

-- 原模型（网页版装备模型原样转的 models/veh/<模型键>.glb，Studio 里导入后由 Imports.lua 收进 ReplicatedStorage.Imported.Veh.<模型键>）：
--   有就整辆换成它（真实尺寸，不缩放；车体、炮塔、炮、各个车轮照元数据 ImportedMeta 摆、按各自的转轴动），没有就用下面零件拼的
local RS = game:GetService("ReplicatedStorage")
local Tint = require(script.Parent:WaitForChild("Tint"))   -- 导入的贴图没出来时的底色（原贴图的平均色）
local TURN = require(RS:WaitForChild("ImportTurn")).TURN   -- 导入的每块网格被 Roblox 转了半圈（ImportTurn.lua）：摆的时候转回来
local TM = require(RS:WaitForChild("TankMods"))   -- 坦克改装：爆反块、主动防御、车顶加特林（用户 11-19）
local IM = nil
do
  local ok, r = pcall(function() return require(RS:WaitForChild("ImportedMeta", 3)) end)
  if ok and type(r) == "table" then IM = r end
end
-- 型号 → 原模型：先找 alias 的模型键；那个模型还没导入（Studio 里没导新 GLB）就退回 old 的旧模型键
--   （用户 11-23「原模型也换成这个」：M1A1 换成从 Sketchfab 原文件直接转的 m1a1i，没重新导入的照旧用以前的 m1a1）
local function importedFor(d)
  if not IM then return nil end
  local imp = RS:FindFirstChild("Imported")
  local veh = imp and imp:FindFirstChild("Veh")
  local keys = { IM.alias and IM.alias[d.id] }
  local old = IM.old and IM.old[d.id]
  if type(old) == "string" then table.insert(keys, old) end
  for _, key in ipairs(keys) do
    local info = IM.m[key]
    local f = info and veh and veh:FindFirstChild(key)
    if f then
      local n = f:GetAttribute("N")   -- 服务器记的块数：还没全复制过来就先不用（View 等块齐了再重建）
      if n and #f:GetChildren() < n then return nil end
      return key, info, f
    end
  end
  return nil
end
VehModels.importedFor = importedFor

local V = Vector3.new
local CF = CFrame.new
local RGB = Color3.fromRGB
local MAT = Enum.Material
local CYL, BALL = Enum.PartType.Cylinder, Enum.PartType.Ball
-- 「窗帘-1」红外干扰灯在各原模型上的位置（车坐标，炮塔转角 0；用户 11-28「t90我记得有一对红色的车灯 这个一定要还原的跟原车一样」）：
--   gx 炮的横坐标、sx 灯离炮多远、y 灯的中心高、zf 灯盒正面（朝前 −Z）、w / h / d 灯盒宽高深——tools/models 的射线量的：
--   坐在炮塔正面防护块的上沿、紧挨着炮盾两边（T-90A 借 T-90M 的模型）
local SHTORA = { t90m = { gx = -0.094, sx = 1.5, y = 5.86, zf = -4.35, w = 0.85, h = 0.72, d = 0.75 } }
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)   -- 圆柱的轴（X）转到 Z（炮管、烟幕弹管）
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)  -- 圆柱的轴转到 Y（竖着的圆盘、舱盖）

local CAMO = {
  atk = { base = RGB(86, 100, 68), dark = RGB(60, 70, 48), light = RGB(118, 126, 90) },   -- 解放军：林地绿
  def = { base = RGB(176, 158, 116), dark = RGB(128, 114, 84), light = RGB(198, 184, 146) },   -- 美军：沙色
}
local TRACK, RUBBER, STEEL, GLASS = RGB(44, 44, 46), RGB(28, 28, 30), RGB(70, 72, 74), RGB(40, 54, 62)

-- paint：科技树暂用车的真车涂装（TechTree.paint，{ base, dark, light } 各是 RGB 三元组）；没给就按阵营
function VehModels.build(d, team, mods, paint)
  local C = CAMO[team] or CAMO.atk
  if type(paint) == "table" and paint.base then
    local function c3(t, dflt) return (type(t) == "table") and RGB(t[1], t[2], t[3]) or dflt end
    C = { base = c3(paint.base, C.base), dark = c3(paint.dark, C.dark), light = c3(paint.light, C.light) }
  end
  local m = Instance.new("Model")
  m.Name = d.id
  local parts, wheels = {}, {}
  local rng = Random.new(#d.id * 7919 + (team == "def" and 1 or 0))

  local function add(group, size, off, color, mat, shape, idx)
    local p = Instance.new((shape == "wedge") and "WedgePart" or "Part")
    if shape and shape ~= "wedge" then p.Shape = shape end
    p.Size = size
    p.Color = color
    p.Material = mat or MAT.SmoothPlastic
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.CFrame = off
    p.Parent = m
    table.insert(parts, { p, group, off, idx })
    return p
  end
  local function hull(size, off, color, mat, shape) return add("hull", size, off, color or C.base, mat or MAT.Metal, shape) end
  local function tur(size, off, color, mat, shape) return add("turret", size, off, color or C.base, mat or MAT.Metal, shape) end
  local function gun(size, off, color, mat, shape) return add("gun", size, off, color or C.base, mat or MAT.Metal, shape) end
  -- 一根沿 −Z 的圆管：从 z0 到 z1（z1 更靠前），直径 dia
  local function tube(fn, x, y, z0, z1, dia, color, mat)
    local L = math.abs(z1 - z0)
    return fn(V(L, dia, dia), CF(x, y, (z0 + z1) / 2) * ALONG_Z, color, mat, CYL)
  end
  -- 零件拼的车顶遥控武器站（原模型上没有机枪、或者机枪和炮塔分不开的坦克：99A2、15 式、零件拼的 M10；用户 11-19：坦克的机枪要能转，开火位置要在机枪）：
  --   座圈、武器站的罩子、光电盒子跟着底座转（rws，原点在座圈中心），12.7 毫米机枪（机匣、散热套筒、枪管、弹箱）跟着俯仰（rwg，原点在俯仰轴）；
  --   gunOff 俯仰轴相对座圈中心，muz 枪口在俯仰轴前面多远——枪口正好在服务器算的枪口上（VehDefs.muzzle 的 rws）
  local function rwsMg(gunOff, muz)
    local GM, BL = RGB(54, 56, 52), RGB(30, 31, 30)
    local function rw(size, off, color, mat, shape) return add("rws", size, off, color or C.base, mat or MAT.Metal, shape) end
    local function rg(size, off, color, mat, shape) return add("rwg", size, off, color or GM, mat or MAT.Metal, shape) end
    local gy, gz = gunOff.Y, gunOff.Z
    rw(V(0.22, 1.7, 1.7), CF(0, 0.11, 0) * UPRIGHT, C.dark, MAT.Metal, CYL)   -- 座圈
    rw(V(1.0, math.max(0.3, gy - 0.25), 1.1), CF(0, 0.22 + math.max(0.3, gy - 0.25) / 2, gz * 0.45), C.base)   -- 武器站的罩子（底座）
    rw(V(0.2, 0.55, 0.5), CF(0.42, gy - 0.12, gz), C.base)   -- 枪架右侧板
    rw(V(0.2, 0.55, 0.5), CF(-0.42, gy - 0.12, gz), C.base)   -- 枪架左侧板
    rw(V(0.5, 0.42, 0.58), CF(-0.78, gy + 0.05, gz + 0.05), GM)   -- 光电盒子（左边）
    rw(V(0.22, 0.2, 0.06), CF(-0.78, gy + 0.08, gz - 0.25), RGB(18, 22, 26), MAT.Glass)   -- 镜头
    rg(V(0.42, 0.44, 1.35), CF(0, 0, 0.35), GM)   -- 机匣
    rg(V(0.16, 0.3, 0.26), CF(0, -0.08, 1.12), BL)   -- 后部握把
    tube(rg, 0, 0.04, -0.32, -1.25, 0.26, BL)   -- 散热套筒
    tube(rg, 0, 0.04, -1.25, -muz, 0.14, BL)   -- 枪管
    rg(V(0.11, 0.2, 0.2), CF(0, 0.04, -muz + 0.08), BL)   -- 枪口制退器
    rg(V(0.36, 0.44, 0.62), CF(0.44, -0.04, 0.3), C.base)   -- 弹箱（右边供弹）
  end
  -- 手动的车长重机枪（99A 的 QJC-88 12.7 毫米，用户 11-21 晚：照真车加回车顶机枪）：车长舱口的座圈、枪架立柱和叉架、
  --   机匣、粗枪管、枪口制退器、左边弹箱、后面两个握把、环形瞄具——没有遥控武器站的罩子和光电盒子；照样跟着瞄准转、从枪口开火
  local function manualMg(gunOff, muz)
    local GM, BL, OD = RGB(52, 54, 50), RGB(28, 29, 28), RGB(76, 82, 58)
    local function rw(size, off, color, mat, shape) return add("rws", size, off, color or C.base, mat or MAT.Metal, shape) end
    local function rg(size, off, color, mat, shape) return add("rwg", size, off, color or GM, mat or MAT.Metal, shape) end
    local gy, gz = gunOff.Y, gunOff.Z
    rw(V(0.16, 1.6, 1.6), CF(0, 0.08, 0) * UPRIGHT, C.dark, MAT.Metal, CYL)   -- 舱口座圈
    local postH = math.max(0.3, gy - 0.2)
    rw(V(0.16, postH, 0.16), CF(0, 0.16 + postH / 2, gz), GM)   -- 枪架立柱
    rw(V(0.5, 0.1, 0.2), CF(0, gy - 0.2, gz), GM)   -- 叉架
    rg(V(0.34, 0.36, 1.2), CF(0, 0, 0.32), GM)   -- 机匣
    for sx = -1, 1, 2 do rg(V(0.07, 0.2, 0.07), CF(sx * 0.11, -0.08, 1.0), BL) end   -- 两个握把
    tube(rg, 0, 0.03, -0.28, -muz + 0.25, 0.16, BL)   -- 粗枪管
    rg(V(0.2, 0.2, 0.3), CF(0, 0.03, -muz + 0.12), BL)   -- 枪口制退器
    rg(V(0.32, 0.4, 0.55), CF(-0.36, -0.06, 0.28), OD)   -- 弹箱（左边供弹）
    rg(V(0.03, 0.16, 0.16), CF(0, 0.28, -0.25), BL)   -- 环形瞄具
  end
  -- 一组迷彩斑块（贴在一个面上的薄片）
  local function blotches(fn, cx, cy, cz, w, h, axis, n)
    for _ = 1, n do
      local u, v = (rng:NextNumber() - 0.5) * w, (rng:NextNumber() - 0.5) * h
      local sw, sh = rng:NextNumber(1.2, 3.2), rng:NextNumber(0.6, 1.6)
      if axis == "x" then fn(V(0.06, sh, sw), CF(cx, cy + v, cz + u), C.dark, MAT.SmoothPlastic)
      elseif axis == "y" then fn(V(sw, 0.06, sh), CF(cx + u, cy, cz + v), C.dark, MAT.SmoothPlastic) end
    end
  end

  local W, L, H, hh, clear = d.W, d.L, d.H, d.hullH, d.clear
  local extra = {}   -- 原模型的炮塔 / 炮转轴、悬架行程（View 用）

  ---------------------------------------------------------------- 原模型
  local ikey, info, folder = importedFor(d)
  if ikey then
    local function v3(t) return V(t[1], t[2], t[3]) end
    local tpiv = info.tur and v3(info.tur) or d.turret.pivot
    local gpiv = info.gun and v3(info.gun) or (tpiv + d.gun.pivot)
    -- 遥控武器站（M1A2 的 CROWS）：底座转轴、M2 俯仰轴（用户：机枪也要能转动）
    local rpiv = info.rws and info.rws.p and v3(info.rws.p) or nil
    local rgpiv = info.rws and info.rws.g and v3(info.rws.g) or nil
    -- 坦克不带机枪（VehDefs.TANK_MG，用户 11-22「坦克不要弄哪个机枪」）：原模型里拆出来的机枪（RwsGun）不画，
    --   座圈、观察镜、舱盖（Rws）照旧画、焊死在炮塔上；元数据要求拼的机枪（mk）也不拼
    local noMg = d.noRoofMg == true and d.cat == "tank"
    if noMg then rpiv, rgpiv = nil, nil end
    -- 车轮：每个轮一个弹簧（中心、半径照原模型）；轮式车最前面 d.steer 排转向
    local wix, names = {}, {}
    for g in pairs(info.wheels or {}) do table.insert(names, g) end
    table.sort(names)
    local zs = {}
    for _, g in ipairs(names) do
      local w = info.wheels[g]
      local c = v3(w.c)
      local wi = #wheels + 1
      wheels[wi] = { x = c.X, z = c.Z, r = c.Y, rad = math.max(w.r, 0.3), side = (c.X < 0) and -1 or 1, dy = 0, vy = 0, spin = 0, steer = false }
      wix[g] = wi
      table.insert(zs, c.Z)
    end
    if #wheels == 0 then
      -- 原模型的车轮和车身是一整块（JLTV、M270、M1150、M1A1、96 式……）：照型号表的轮位（按原模型的长宽缩放）放几个看不见的弹簧，
      --   车身照样随地面起伏、俯仰、侧倾
      local hb = info.hull or { info.w, info.h, info.len }   -- 车身的宽、高、长
      local kz, kx = hb[3] / math.max(d.L, 1), hb[1] / math.max(d.W, 1)
      local function spring(x, z, r) wheels[#wheels + 1] = { x = x * kx, z = z * kz, r = r, rad = r, side = (x < 0) and -1 or 1, dy = 0, vy = 0, spin = 0, steer = false } end
      if d.arch == "tracked" and d.rw then
        local R = d.rw
        for s = -1, 1, 2 do
          for i = 1, R.n do spring(s * R.x, R.z0 + (i - 1) * (R.z1 - R.z0) / math.max(R.n - 1, 1), R.r) end
        end
      elseif d.axles then
        for _, z in ipairs(d.axles) do
          for s = -1, 1, 2 do spring(s * d.wx, z, d.wr) end
        end
      end
    end
    if d.arch == "wheeled" and #zs > 0 then
      table.sort(zs)
      local axles = {}
      for _, z in ipairs(zs) do
        if #axles == 0 or z - axles[#axles] > 1.5 then table.insert(axles, z) end
      end
      local lim = axles[math.min(#axles, d.steer or 1)] + 0.75
      for _, w in ipairs(wheels) do w.steer = w.z <= lim end
    end
    local carve = { cav = {}, glass = {}, inside = {} }
    -- carve.py 改过的块换了新名字（rep = 它顶替的旧块）：导入了新块就不用旧块；没重新导入的照旧用旧块
    local replaced = {}
    for name, p in pairs(info.parts) do
      if p.rep and folder:FindFirstChild("V_" .. ikey .. "__" .. name) then
        for _, old in ipairs(p.rep) do replaced[old] = true end
      end
    end
    for name, p in pairs(info.parts) do
      local src = folder:FindFirstChild("V_" .. ikey .. "__" .. name)
      -- k = int：原模型自带的车内（M1A1 的炮塔内饰，拆成 Int_* 十几块）不放进车模——坐进车里时内饰（InteriorAbrams）自己克隆、按组摆（炮尾后坐、握把摆）
      if src and src:IsA("BasePart") and not (noMg and p.g == "RwsGun") and not replaced[name] and p.k ~= "int" then
        local mp = Tint.fix(src:Clone(), src)
        mp.Anchored, mp.CanCollide, mp.CanQuery, mp.CanTouch = true, false, false, false
        mp.Size = v3(p.s)
        -- 原模型里这块本来就没贴图（JLTV、M270 整车都是）：照原材质的颜色上色——Studio 导入时不一定把材质颜色带过来
        local okT, tid = pcall(function() return mp.TextureID end)   -- 不是 MeshPart 的没有这个属性
        if p.col and not mp:FindFirstChildOfClass("SurfaceAppearance") and (not okT or (tid or "") == "") then
          mp.Color = Color3.fromRGB(p.col[1], p.col[2], p.col[3])
          mp.Material = p.met and Enum.Material.Metal or Enum.Material.SmoothPlastic
          if p.a then mp.Transparency = 1 - p.a end
        end
        local c = v3(p.c)
        local grp, off, wi = "hull", CF(c), nil
        if p.g == "Turret" or (noMg and p.g == "Rws") then grp, off = "turret", CF(c - tpiv)
        elseif p.g == "Gun" then grp, off = "gun", CF(c - gpiv)
        elseif p.g == "Rws" and rpiv then grp, off = "rws", CF(c - rpiv)
        elseif p.g == "RwsGun" and rgpiv then grp, off = "rwg", CF(c - rgpiv)
        elseif wix[p.g] then
          wi = wix[p.g]
          local w = wheels[wi]
          grp, off = "wheel", CF(c - V(w.x, w.r, w.z))
        end
        off = off * TURN   -- 绕这块自己的中心补回导入时转掉的半圈
        mp.CFrame = off
        -- 从原车挖出来的内腔（tools/models/carve.py，用户 11-23「在原车内部雕刻出来内饰」）：k = cav 内壁（平时藏着，坐进车里 Interior 显示）、
        --   glass 车窗玻璃（透明：车里看出去、车外看进来）、inside 原模型自带的简易内饰（坐进车里时藏起来，换成真内饰）
        if p.k == "cav" then
          if p.col then mp.Color = Color3.fromRGB(p.col[1], p.col[2], p.col[3]) end
          mp.Material = (p.m and Enum.Material[p.m]) or MAT.SmoothPlastic
          mp.CastShadow = false
          mp.Transparency = 1
          table.insert(carve.cav, mp)
        elseif p.k == "glass" then
          mp.Transparency = math.max(mp.Transparency, 1 - (p.a or 0.35))
          mp.CastShadow = false
          table.insert(carve.glass, mp)
        elseif p.k == "inside" then
          table.insert(carve.inside, mp)
        elseif p.k == "radar" then   -- 原模型拆出来的搜索雷达天线（铠甲-S1，blveh.json 的 label Radar）：View.lua 让带 Radar 的块一直转
          mp:SetAttribute("Radar", true)
        end
        mp.Parent = m
        table.insert(parts, { mp, grp, off, wi })
      end
    end
    -- 原模型没有机枪的（悍马 M998 软篷）：篷顶上补一挺零件拼的 M2——座圈、枪盾、枪架跟着炮塔转，枪身跟着俯仰，
    --   枪口正好在服务器算的炮口上（耳轴前 d.gun.len；用户：很多载具的机枪塔没法旋转、开火位置要对）
    if info.mg == "m2" then
      local GM, BL, OD = RGB(46, 48, 46), RGB(28, 29, 28), RGB(74, 80, 58)
      local gy = (gpiv - tpiv).Y   -- 枪架高
      tur(V(0.3, 3.0, 3.0), CF(0, 0.15, 0) * UPRIGHT, C.dark, MAT.Metal, CYL)   -- 座圈
      for sx = -1, 1, 2 do   -- 正面枪盾：左右两块，中间留出枪管的缝
        tur(V(1.05, 1.25, 0.12), CF(sx * 0.66, 0.95, -1.3), C.base)
        tur(V(0.12, 1.1, 0.8), CF(sx * 1.22, 0.9, -0.95) * CFrame.Angles(0, sx * 0.45, 0), C.base)   -- 侧翼
      end
      tur(V(0.24, gy, 0.24), CF(0, gy / 2, 0.1), GM)   -- 枪架立柱
      gun(V(0.5, 0.58, 1.7), CF(0, 0.1, 0.1), GM)   -- 机匣
      gun(V(0.14, 0.36, 0.26), CF(0, 0.05, 1.05), BL)   -- 握把
      tube(gun, 0, 0.12, -0.75, -1.85, 0.3, BL)   -- 散热套筒
      tube(gun, 0, 0.12, -1.85, -d.gun.len, 0.17, BL)   -- 枪管
      gun(V(0.4, 0.5, 0.78), CF(-0.48, -0.06, 0.05), OD)   -- 弹箱（M2 从左边供弹）
    end
    -- 原模型上没有机枪（或者去掉了）的坦克：元数据的 rws.mk——在座圈上拼一个遥控武器站（tools/models/vehrws.py）
    if info.rws and info.rws.mk and rpiv and rgpiv then
      if info.rws.mk == "manual" then manualMg(rgpiv - rpiv, info.rws.muz or 2.45) else rwsMg(rgpiv - rpiv, info.rws.muz or 2.45) end
    end
    extra = { imported = ikey, tpiv = tpiv, gpiv = gpiv - tpiv, travel = (d.arch == "tracked") and 0.12 or d.travel,
      rpiv = rpiv and (rpiv - tpiv) or nil, rgpiv = (rpiv and rgpiv) and (rgpiv - rpiv) or nil, carve = (#carve.cav > 0) and carve or nil }
  end

  if not ikey then
  -- 零件拼的：炮塔、炮按型号表原来的转轴摆（VehDefs 的转轴照原模型改过，给导入了原模型的用；服务器的炮口照原模型，差一两格）
  extra.tpiv, extra.gpiv = d.turret and d.turret.pivot0, d.gun and d.gun.pivot0
  ---------------------------------------------------------------- 行走部分

  if d.arch == "tracked" then
    local R = d.rw
    local tw = math.max(1.2, W * 0.16)   -- 履带宽
    local spacing = (R.z1 - R.z0) / (R.n - 1)
    for s = -1, 1, 2 do
      local x = s * R.x
      for i = 1, R.n do
        local z = R.z0 + (i - 1) * spacing
        local wi = #wheels + 1
        wheels[wi] = { x = x, z = z, r = R.r, side = s, dy = 0, vy = 0, spin = 0, steer = false }
        add("wheel", V(tw * 0.8, R.r * 2, R.r * 2), CF(), RUBBER, MAT.SmoothPlastic, CYL, wi)
        add("wheel", V(tw * 0.84, R.r * 1.2, R.r * 1.2), CF(), C.dark, MAT.Metal, CYL, wi)
        add("wheel", V(tw * 0.86, R.r * 1.5, 0.25), CF(), STEEL, MAT.Metal, nil, wi)   -- 辐条（看得出在转）
        add("seg", V(tw, 0.32, spacing * 1.04), CF(x, 0.16, z), TRACK, MAT.DiamondPlate, nil, wi)   -- 下面这一段履带跟着轮
      end
      -- 上面一段履带、主动轮（前）、诱导轮（后）、前后斜着的两段
      local ytop = R.r * 2 + 0.18
      local zf, zb = R.z0 - R.r * 1.35, R.z1 + R.r * 1.25
      hull(V(tw, 0.32, R.z1 - R.z0 + R.r * 1.6), CF(x, ytop, (R.z0 + R.z1) / 2), TRACK, MAT.DiamondPlate)
      hull(V(tw * 0.9, R.r * 1.7, R.r * 1.7), CF(x, R.r * 1.35, zf), STEEL, MAT.Metal, CYL)
      hull(V(tw * 0.9, R.r * 1.6, R.r * 1.6), CF(x, R.r * 1.3, zb), STEEL, MAT.Metal, CYL)
      for _, e in ipairs({ { R.z0, zf, -1 }, { R.z1, zb, 1 } }) do
        local a = V(x, 0.2, e[1] + e[3] * R.r * 0.3)
        local b = V(x, ytop, e[2] + e[3] * R.r * 0.2)
        local mid, len = (a + b) / 2, (b - a).Magnitude
        hull(V(tw, 0.32, len), CFrame.lookAt(mid, b), TRACK, MAT.DiamondPlate)
      end
      if d.skirt then   -- 侧裙板：盖住负重轮上半截
        hull(V(0.3, R.r * 1.25, R.z1 - R.z0 + R.r * 2.4), CF(s * (W / 2 - 0.15), R.r * 1.75, (R.z0 + R.z1) / 2 - R.r * 0.3), C.base, MAT.Metal)
        blotches(hull, s * (W / 2), R.r * 1.75, (R.z0 + R.z1) / 2, R.z1 - R.z0, R.r, "x", 3)
      end
    end
  else
    local wx, wr, ww = d.wx, d.wr, d.ww
    for ai, z in ipairs(d.axles) do
      for s = -1, 1, 2 do
        local wi = #wheels + 1
        wheels[wi] = { x = s * wx, z = z, r = wr, side = s, dy = 0, vy = 0, spin = 0, steer = ai <= (d.steer or 1) }
        add("wheel", V(ww, wr * 2, wr * 2), CF(), RUBBER, MAT.SmoothPlastic, CYL, wi)
        add("wheel", V(ww + 0.06, wr * 1.1, wr * 1.1), CF(), C.dark, MAT.Metal, CYL, wi)
        add("wheel", V(ww + 0.1, wr * 0.45, wr * 0.45), CF(), STEEL, MAT.Metal, CYL, wi)
        add("wheel", V(ww + 0.08, wr * 1.6, 0.22), CF(), RUBBER, MAT.SmoothPlastic, nil, wi)   -- 胎面花纹（看得出在转）
        -- 挡泥板（跟车体）
        hull(V(ww + 0.5, 0.25, wr * 2.3), CF(s * wx, wr * 2 + 0.55, z), C.dark, MAT.Metal)
      end
    end
  end

  ---------------------------------------------------------------- 车体

  if d.arch == "tracked" then
    local tw = math.max(1.2, W * 0.16)
    local inner = W - 2 * tw - 0.3
    hull(V(inner, hh - clear - 0.7, L * 0.94), CF(0, clear + (hh - clear - 0.7) / 2, 0), C.base)   -- 下车体
    hull(V(W, 0.75, L * 0.9), CF(0, hh - 0.375, L * 0.03), C.base)   -- 上车体（翼子板一直伸到履带上面）
    -- 首上（斜面朝前上）、首下（斜面朝前下）
    hull(V(W * 0.96, 1.5, 3.2), CF(0, hh - 0.75 - 0.75 + 0.75, -L / 2 + 1.0), C.base, MAT.Metal, "wedge")
    hull(V(inner, hh - clear - 1.2, 2.0), CF(0, clear + (hh - clear - 1.2) / 2, -L / 2 + 0.2) * CFrame.Angles(0, 0, math.pi), C.dark, MAT.Metal, "wedge")
    -- 发动机舱：散热格栅、排气口
    for i = 0, 3 do hull(V(W * 0.62, 0.12, 0.5), CF(0, hh + 0.06, L * 0.18 + i * 1.1), C.dark, MAT.DiamondPlate) end
    hull(V(W * 0.7, 0.9, 0.35), CF(0, hh - 0.9, L / 2 - 0.1), C.dark)
    hull(V(1.2, 0.5, 0.4), CF(W * 0.28, hh - 0.6, L / 2 + 0.1), RGB(36, 36, 36))
    -- 车灯、牵引钩、工具箱
    for s = -1, 1, 2 do
      hull(V(0.5, 0.35, 0.3), CF(s * W * 0.36, hh - 0.5, -L / 2 + 0.3), RGB(220, 220, 200), MAT.Glass)
      hull(V(0.5, 0.5, 0.6), CF(s * W * 0.22, clear + 0.5, -L / 2 - 0.1), STEEL)
      hull(V(0.9, 0.7, 3.2), CF(s * (W / 2 - 0.5), hh + 0.35, L * 0.22), C.dark)
    end
    if d.era then   -- 首上的反应装甲块
      for i = -3, 3 do
        for j = 0, 1 do hull(V(0.95, 0.35, 0.9), CF(i * 1.05, hh - 0.35 + j * 0.15, -L / 2 + 1.9 + j * 1.0), C.light, MAT.Metal) end
      end
    end
    if d.plow then   -- 扫雷犁
      hull(V(W * 0.92, 1.4, 0.4), CF(0, 0.9, -L / 2 - 1.6) * CFrame.Angles(math.rad(-25), 0, 0), STEEL, MAT.DiamondPlate)
      for i = -3, 3 do hull(V(0.28, 1.0, 1.2), CF(i * 1.3, 0.45, -L / 2 - 2.1), STEEL) end
    end
    if d.boat then   -- 两栖车：前面的防浪板
      hull(V(W * 0.9, 1.8, 0.3), CF(0, hh - 0.3, -L / 2 - 0.3) * CFrame.Angles(math.rad(35), 0, 0), C.dark)
    end
    if d.cab then   -- M270：前面的驾驶室
      hull(V(W * 0.86, 2.6, 5.6), CF(0, hh + 1.3, -L / 2 + 3.2), C.base)
      hull(V(W * 0.8, 1.0, 0.1), CF(0, hh + 1.9, -L / 2 + 0.38), GLASS, MAT.Glass)
    end
    blotches(hull, 0, hh + 0.01, 0, W * 0.8, L * 0.6, "y", 4)
  else
    local bw = W * 0.9
    if d.light then   -- 悍马、JLTV：低车身 + 发动机罩 + 乘员舱
      hull(V(bw, hh * 0.38, L * 0.96), CF(0, clear + hh * 0.19 + 0.3, 0), C.base)
      hull(V(bw * 0.96, 1.2, L * 0.36), CF(0, clear + hh * 0.38 + 0.9, -L * 0.3), C.base, MAT.Metal, "wedge")
      hull(V(bw, hh * 0.42, L * 0.56), CF(0, clear + hh * 0.38 + hh * 0.21 + 0.3, L * 0.14), C.base)
      for s = -1, 1, 2 do
        hull(V(0.08, hh * 0.24, L * 0.36), CF(s * (bw / 2 + 0.02), clear + hh * 0.66, L * 0.12), GLASS, MAT.Glass)
      end
      hull(V(bw * 0.86, hh * 0.24, 0.1), CF(0, clear + hh * 0.66, -L * 0.15), GLASS, MAT.Glass)
    elseif d.truck then   -- 卡车底盘：驾驶室在前、后面平板上装家伙
      hull(V(bw, 0.9, L * 0.96), CF(0, clear + 0.45, 0), C.dark)
      hull(V(bw, 3.4, 5.4), CF(0, clear + 0.9 + 1.7, -L / 2 + 2.8), C.base)
      hull(V(bw * 0.9, 1.2, 0.1), CF(0, clear + 3.0, -L / 2 + 0.06), GLASS, MAT.Glass)
      hull(V(bw, 0.5, L - 6), CF(0, hh - 0.25, 3.0), C.base)
      for s = -1, 1, 2 do hull(V(0.6, 0.35, 0.25), CF(s * bw * 0.36, clear + 1.4, -L / 2 + 0.05), RGB(220, 220, 200), MAT.Glass) end
    else   -- 装甲车：车身 + 前面的斜板 + 车顶
      hull(V(bw, hh - clear - 0.9, L * 0.94), CF(0, clear + (hh - clear - 0.9) / 2, 0.2), C.base)
      hull(V(bw, 1.8, 3.4), CF(0, hh - 0.9 - 0.9 + 0.9, -L / 2 + 1.5), C.base, MAT.Metal, "wedge")
      hull(V(bw, hh - clear - 2.6, 1.6), CF(0, clear + (hh - clear - 2.6) / 2, -L / 2 + 0.7) * CFrame.Angles(0, 0, math.pi), C.dark, MAT.Metal, "wedge")
      hull(V(bw * 0.96, 0.9, L * 0.78), CF(0, hh - 0.45, L * 0.08), C.base)
      hull(V(bw * 0.5, hh - clear - 1.4, 0.3), CF(0, clear + (hh - clear - 1.4) / 2 + 0.3, L / 2 + 0.05), C.dark)   -- 后门
      for s = -1, 1, 2 do
        hull(V(0.5, 0.3, 0.25), CF(s * bw * 0.34, hh - 1.4, -L / 2 + 0.25), RGB(220, 220, 200), MAT.Glass)
        hull(V(0.9, 0.8, 3.0), CF(s * (bw / 2 + 0.2), hh - 1.3, L * 0.2), C.dark)
      end
      if d.boat then hull(V(bw, 1.6, 0.3), CF(0, hh - 0.6, -L / 2 - 0.4) * CFrame.Angles(math.rad(35), 0, 0), C.dark) end
    end
    blotches(hull, 0, hh + 0.01, 0, bw * 0.7, L * 0.5, "y", 3)
  end

  ---------------------------------------------------------------- 炮塔（坐标系：转轴在原点，−Z 朝前）

  local T = d.turret
  local s = T.size
  local st = T.style
  if st == "wedge" or st == "round" or st == "abrams" then
    if st == "round" then
      tur(V(s.Y, s.X * 0.95, s.X * 0.95), CF(0, s.Y / 2, s.Z * 0.02) * UPRIGHT, C.base, MAT.Metal, CYL)
    else
      tur(V(s.X * 0.86, s.Y, s.Z * 0.66), CF(0, s.Y / 2, s.Z * 0.1), C.base)
    end
    -- 前面两块斜的（楔形装甲 / 反应装甲）
    for sx = -1, 1, 2 do
      local blk = tur(V(s.X * 0.36, s.Y * 0.92, s.Z * 0.42), CF(sx * s.X * 0.24, s.Y * 0.47, -s.Z * 0.33) * CFrame.Angles(0, sx * math.rad(st == "abrams" and 12 or 26), 0),
        (d.era and C.light) or C.base)
      if d.era then
        for i = 0, 2 do tur(V(s.X * 0.37, 0.12, 0.9), CF(sx * s.X * 0.24, s.Y * 0.95, -s.Z * 0.2 - i * 1.0), C.dark, MAT.SmoothPlastic) end
      end
    end
    if T.bustle then tur(V(s.X * 0.72, s.Y * 0.78, T.bustle), CF(0, s.Y * 0.45, s.Z / 2 + T.bustle / 2 - 0.4), C.base) end
    -- 舱盖、观瞄、天线
    tur(V(0.25, 1.4, 1.4), CF(d.cupola and d.cupola.X or 1.4, s.Y + 0.12, d.cupola and d.cupola.Z or 0.2) * UPRIGHT, C.dark, MAT.Metal, CYL)
    tur(V(0.25, 1.2, 1.2), CF(-1.2, s.Y + 0.12, 0.6) * UPRIGHT, C.dark, MAT.Metal, CYL)
    tur(V(0.9, 0.8, 1.1), CF(d.sight.X, s.Y + 0.4, d.sight.Z), C.dark)   -- 炮长镜
    tur(V(0.15, 0.15, 1.4), CF(d.sight.X, s.Y + 0.4, d.sight.Z - 0.6) * CFrame.Angles(0, 0, 0), GLASS, MAT.Glass)
    if d.citv then tur(V(1.0, 1.2, 1.0), CF(d.citv.X, s.Y + 0.6, d.citv.Z), C.dark) end
    if not d.rws and not d.noRoofMg then   -- 车长机枪（有遥控武器站的换成会转的，下面拼；99A 车顶不放机枪）
      tur(V(0.6, 0.6, 1.4), CF((d.cupola and d.cupola.X or 1.4), s.Y + 0.6, (d.cupola and d.cupola.Z or 0.2) - 0.6), RGB(40, 42, 44))
    end
    for sx = -1, 1, 2 do tur(V(0.1, 7, 0.1), CF(sx * s.X * 0.32, s.Y + 3.5, s.Z * 0.42), RGB(30, 30, 30), MAT.Metal, CYL) end
    blotches(tur, 0, s.Y + 0.01, 0, s.X * 0.6, s.Z * 0.6, "y", 3)
  elseif st == "ifv" then
    tur(V(s.X, s.Y, s.Z * 0.8), CF(0, s.Y / 2, s.Z * 0.1), C.base)
    tur(V(s.X * 0.9, s.Y * 0.9, s.Z * 0.3), CF(0, s.Y * 0.45, -s.Z * 0.45), C.base, MAT.Metal, "wedge")
    tur(V(0.8, 0.7, 0.9), CF(d.sight.X, s.Y + 0.35, d.sight.Z), C.dark)
    tur(V(0.25, 1.1, 1.1), CF(0.9, s.Y + 0.12, 0.6) * UPRIGHT, C.dark, MAT.Metal, CYL)
    if T.tow then tur(V(1.2, 1.4, 3.0), CF(s.X / 2 + 0.6, s.Y * 0.6, 0.4), C.dark) end   -- 布雷德利的陶式发射箱
    if T.pods then
      for sx = -1, 1, 2 do tur(V(1.0, 1.4, 2.4), CF(sx * (s.X / 2 + 0.55), s.Y * 0.6, 0.2), C.dark) end
    end
    tur(V(0.1, 6, 0.1), CF(-s.X * 0.35, s.Y + 3, s.Z * 0.4), RGB(30, 30, 30), MAT.Metal, CYL)
  elseif st == "rws" or st == "ring" then
    if st == "ring" then
      tur(V(0.4, s.X, s.X), CF(0, 0.2, 0) * UPRIGHT, C.dark, MAT.Metal, CYL)
      tur(V(1.8, 1.2, 0.15), CF(0, 1.0, -0.9), C.base)   -- 枪盾
      for sx = -1, 1, 2 do tur(V(0.15, 1.0, 1.0), CF(sx * 0.95, 0.9, -0.5) * CFrame.Angles(0, sx * 0.5, 0), C.base) end
    else
      tur(V(1.3, 0.7, 1.3), CF(0, 0.35, 0), C.dark)
      tur(V(0.7, 0.6, 0.7), CF(0.75, 1.0, -0.2), C.dark)   -- 光电
    end
  elseif st == "spaag" then
    tur(V(s.X * 0.7, s.Y, s.Z), CF(0, s.Y / 2, 0), C.base)
    tur(V(s.X * 0.66, s.Y * 0.7, s.Z * 0.3), CF(0, s.Y * 0.35, -s.Z * 0.55), C.base, MAT.Metal, "wedge")
    -- 后上方的搜索雷达（一直转：标记 Radar）、前面的跟踪雷达
    local rd = tur(V(0.25, 3.4, 1.4), CF(0, s.Y + 1.6, s.Z * 0.3), STEEL, MAT.Metal)
    rd:SetAttribute("Radar", true)
    tur(V(0.3, 0.3, 1.4), CF(0, s.Y + 0.7, s.Z * 0.3), STEEL, MAT.Metal, CYL)
    tur(V(0.6, 1.1, 1.1), CF(0, s.Y + 0.5, -s.Z * 0.3) * ALONG_Z, C.dark, MAT.Metal, CYL)
  elseif st == "vulcan" then
    tur(V(s.X, s.Y * 0.7, s.Z), CF(0, s.Y * 0.35, 0), C.base)
    if T.dome then   -- C-RAM：白色雷达罩
      tur(V(1.8, 1.8, 1.8), CF(0, s.Y + 0.6, 0.8), RGB(230, 230, 225), MAT.SmoothPlastic, BALL)
      tur(V(1.0, 1.8, 1.8), CF(0, s.Y - 0.1, 0.8) * UPRIGHT, RGB(230, 230, 225), MAT.SmoothPlastic, CYL)
    elseif T.radar then
      local rd = tur(V(0.2, 2.4, 1.2), CF(0, s.Y + 1.2, s.Z * 0.35), STEEL)
      rd:SetAttribute("Radar", true)
    else
      tur(V(1.2, 1.0, 0.8), CF(s.X * 0.35, s.Y * 0.85, s.Z * 0.2), C.dark)   -- 测距雷达
    end
  elseif st == "sph" then
    tur(V(s.X, s.Y, s.Z), CF(0, s.Y / 2, 0), C.base)
    tur(V(s.X * 0.96, s.Y * 0.5, 1.6), CF(0, s.Y * 0.75, -s.Z / 2 - 0.4), C.base, MAT.Metal, "wedge")
    for sx = -1, 1, 2 do tur(V(0.1, s.Y * 0.6, 2.2), CF(sx * (s.X / 2 + 0.03), s.Y * 0.45, 0.6), C.dark) end   -- 侧门
    tur(V(0.25, 1.4, 1.4), CF(s.X * 0.28, s.Y + 0.12, s.Z * 0.15) * UPRIGHT, C.dark, MAT.Metal, CYL)
    tur(V(0.6, 0.6, 1.4), CF(s.X * 0.28, s.Y + 0.6, s.Z * 0.15 - 0.6), RGB(40, 42, 44))
    blotches(tur, 0, s.Y + 0.01, 0, s.X * 0.6, s.Z * 0.6, "y", 3)
  elseif st == "launcher" then
    tur(V(s.X * 0.8, 0.8, s.Z * 0.5), CF(0, 0.4, 0), C.dark)
  end

  ---------------------------------------------------------------- 炮（坐标系：耳轴在原点，−Z 朝前，跟着俯仰）

  local Gd = setmetatable({ len = d.gun.len0 or d.gun.len, pivot = d.gun.pivot0 or d.gun.pivot }, { __index = d.gun })   -- 炮管长、耳轴也照型号表原来的
  if st == "launcher" then   -- 发射箱整个跟着起竖：前端一格格的管口
    gun(V(s.X, s.Y, s.Z), CF(0, s.Y / 2 + 0.4, 0), C.base)
    local nx, ny = 3, 2
    for i = 0, nx - 1 do
      for j = 0, ny - 1 do
        gun(V(s.X / nx * 0.8, s.Y / ny * 0.8, 0.1), CF((i - (nx - 1) / 2) * s.X / nx, 0.4 + (j + 0.5) * s.Y / ny, -s.Z / 2 - 0.02), RGB(26, 26, 28))
      end
    end
  elseif Gd.len > 0 then
    if st ~= "rws" and st ~= "ring" then gun(V(math.min(s.X * 0.4, 3.0), Gd.cal * 3.6 + 0.6, 1.6), CF(0, 0, -0.4), C.base) end   -- 防盾
    if Gd.gatling then
      for k = 0, 5 do
        local a = k * math.pi / 3
        tube(gun, math.cos(a) * Gd.cal * 0.55, math.sin(a) * Gd.cal * 0.55, -0.6, -Gd.len, Gd.cal * 0.32, RGB(40, 40, 42))
      end
      tube(gun, 0, 0, -0.6, -1.6, Gd.cal * 1.7, RGB(50, 50, 52))
    elseif T.twin then   -- 双管高炮：炮塔两侧各一门
      for sx = -1, 1, 2 do
        gun(V(1.1, 1.3, 3.0), CF(sx * T.twin / 2, 0, -0.6), C.dark)
        tube(gun, sx * T.twin / 2, 0, -2.0, -Gd.len, Gd.cal, RGB(46, 48, 50))
        tube(gun, sx * T.twin / 2, 0, -Gd.len + 0.6, -Gd.len, Gd.cal * 1.6, RGB(46, 48, 50))
      end
    else
      tube(gun, 0, 0, -0.6, -Gd.len, Gd.cal, RGB(52, 54, 52))
      tube(gun, 0, 0, -0.9, -Gd.len * 0.5, Gd.cal * 1.18, C.base)   -- 热护套
      if Gd.fume then tube(gun, 0, 0, -Gd.len * 0.42, -Gd.len * 0.55, Gd.cal * 1.7, C.base) end
      if Gd.brake then gun(V(Gd.cal * 2.4, Gd.cal * 1.5, Gd.cal * 2.8), CF(0, 0, -Gd.len), RGB(48, 50, 50)) end
    end
    if d.coax then   -- 并列机枪口
      local c = d.coax - Gd.pivot
      tube(gun, c.X, c.Y, -0.2, -1.4, 0.2, RGB(30, 30, 30))
    end
  end

  ---------------------------------------------------------------- 烟幕弹发射筒（和 VehDefs.smokeTubes 一样的位置、朝向）

  local S = d.smoke
  if S then
    for _, b in ipairs(S.banks) do
      local fn = b.hull and hull or tur
      local frame = b.hull and (CF(0, hh, 0) * CF(b.at)) or CF(b.at)
      fn(V(1.1, 0.5, 0.9), frame * CF(0, -0.3, 0.1), C.dark)   -- 发射架
      for i = 1, S.n do
        local fan = (S.n > 1) and ((i - 1) / (S.n - 1) - 0.5) or 0
        local yaw2 = math.rad(b.yaw + fan * 40 * (b.yaw >= 0 and 1 or -1))
        local cf = frame * CF(fan * 0.9, (i % 2) * 0.35, 0) * CFrame.Angles(0, -yaw2, 0) * CFrame.Angles(math.rad(35), 0, 0)
        fn(V(0.85, 0.34, 0.34), cf * CF(0, 0, -0.3) * ALONG_Z, RGB(54, 58, 50), MAT.Metal, CYL)
        fn(V(0.05, 0.26, 0.26), cf * CF(0, 0, -0.74) * ALONG_Z, RGB(20, 20, 20), MAT.SmoothPlastic, CYL)   -- 管口
      end
    end
  end

  -- 零件拼的坦克（M10；还有没导入原模型时的退路）：车长位上拼一个会转的遥控武器站（VehDefs 给的 d.rws）
  if d.rws and d.rws.gun then
    rwsMg(d.rws.gun, d.rws.len or 2.45)
    extra.rpiv, extra.rgpiv = d.rws.pivot, d.rws.gun
  end
  end   -- 零件拼的（没有原模型时）

  -- 扬尘：后轮那里两个隐形发射点
  local dust = {}
  for _, s2 in ipairs({ -1, 1 }) do
    local p = hull(V(0.2, 0.2, 0.2), CF(s2 * W * 0.4, 0.4, L * 0.45), C.base)
    p.Transparency = 1
    local pe = Instance.new("ParticleEmitter")
    pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
    pe.Rate = 0
    -- 尘柱：一团团往后、往上慢慢胀开、飘好几秒（Arma 里车后那一长条黄土），颜色和浓淡按脚下的地面在 View.lua 里换
    pe.Lifetime = NumberRange.new(2.6, 5.2)
    pe.Speed = NumberRange.new(3, 8)
    pe.SpreadAngle = Vector2.new(40, 25)
    pe.Acceleration = V(0, 1.6, 0)
    pe.Drag = 0.9
    pe.Rotation = NumberRange.new(0, 360)
    pe.RotSpeed = NumberRange.new(-12, 12)
    pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(0.35, 10), NumberSequenceKeypoint.new(1, 19) })
    pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.4, 0.62), NumberSequenceKeypoint.new(1, 1) })
    pe.Color = ColorSequence.new(RGB(170, 146, 110))
    pe.EmissionDirection = Enum.NormalId.Back
    pe.LightInfluence = 1
    pe.Parent = p
    table.insert(dust, pe)
  end

  -- 排气（用户 11-20：载具照 UE5 的水平升级）：车尾两侧两个排气口——柴油机加油门、换挡那一下喷一股浓黑烟，怠速淡淡一缕；
  --   燃气轮机（M1 系列、T-80 系列：VehDefs 的 turbine）是淡灰的热气。浓淡在 View.lua 按油门 / 加速度调
  --   （原来写死 m1a1 / m1a2：拆出来的 M1、IPM1、M1A1 HC、M1A2 / SEP / SEPv3 照样是燃气轮机，同 Drive.lua 的发动机声）
  local exhaust = {}
  local turbine = d.turbine == true
  for _, s2 in ipairs({ -1, 1 }) do
    local p = hull(V(0.2, 0.2, 0.2), CF(s2 * W * 0.3, hh * 0.92, L * 0.44), C.base)
    p.Transparency = 1
    local pe = Instance.new("ParticleEmitter")
    pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
    pe.Rate = 0
    pe.Lifetime = NumberRange.new(1.1, 2.4)
    pe.Speed = NumberRange.new(2.5, 5)
    pe.SpreadAngle = Vector2.new(18, 18)
    pe.Acceleration = V(0, 3.2, 0)
    pe.Drag = 1.2
    pe.Rotation = NumberRange.new(0, 360)
    pe.RotSpeed = NumberRange.new(-25, 25)
    pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(0.3, 2.6), NumberSequenceKeypoint.new(1, 6.5) })
    pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, turbine and 0.82 or 0.45), NumberSequenceKeypoint.new(0.5, turbine and 0.9 or 0.7),
      NumberSequenceKeypoint.new(1, 1) })
    pe.Color = ColorSequence.new(turbine and RGB(150, 150, 146) or RGB(34, 33, 31))
    pe.EmissionDirection = Enum.NormalId.Top
    pe.LightInfluence = 1
    pe.Parent = p
    table.insert(exhaust, pe)
  end

  -- 被毁后的火、黑烟（平时关着）
  local fireP = hull(V(0.2, 0.2, 0.2), CF(0, hh + 0.5, 0), C.base)
  fireP.Transparency = 1
  local fire = Instance.new("ParticleEmitter")
  fire.Texture = "rbxasset://textures/particles/fire_main.dds"
  fire.Rate = 0
  fire.Lifetime = NumberRange.new(0.6, 1.2)
  fire.Speed = NumberRange.new(4, 8)
  fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 1) })
  fire.Color = ColorSequence.new(RGB(255, 170, 60), RGB(255, 80, 30))
  fire.LightEmission = 1
  fire.Parent = fireP
  local black = Instance.new("ParticleEmitter")
  black.Texture = "rbxasset://textures/particles/smoke_main.dds"
  black.Rate = 0
  black.Lifetime = NumberRange.new(4, 7)
  black.Speed = NumberRange.new(6, 10)
  black.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 18) })
  black.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
  black.Color = ColorSequence.new(RGB(30, 30, 30))
  black.Parent = fireP

  -- 夜里的车灯：前面两盏（轮式车是大灯，射灯照前面的路；履带车是暗的灯火管制灯）、后面两盏红尾灯；有人开才亮（View.lua）
  local lamps = {}
  local function lampPart(off, color, size)
    local p = add("hull", V(size, size * 0.7, 0.15), off, color, MAT.Neon)
    p.CastShadow = false
    table.insert(lamps, p)
    return p
  end
  local wheeled = d.arch == "wheeled"
  for sd = -1, 1, 2 do
    local fl = lampPart(CF(sd * d.W * 0.36, d.hullH * 0.62, -d.L / 2 - 0.05), wheeled and RGB(255, 244, 214) or RGB(255, 186, 120), wheeled and 0.55 or 0.3)
    if wheeled then
      local sl = Instance.new("SpotLight")
      sl.Face, sl.Angle, sl.Range, sl.Brightness, sl.Color, sl.Shadows = Enum.NormalId.Front, 55, 70, 3.2, RGB(255, 240, 210), false   -- 自己开的才投影子（View.lua）
      sl.Parent = fl
    end
    local tl = lampPart(CF(sd * d.W * 0.4, d.hullH * 0.55, d.L / 2 + 0.05), RGB(255, 40, 30), 0.32)
    local pl = Instance.new("PointLight")
    pl.Range, pl.Brightness, pl.Color, pl.Shadows = 6, 0.8, RGB(255, 40, 30), false
    pl.Parent = tl
  end

  ---------------------------------------------------------------- 改装（TankMods / EraMeta）
  --   用户 11-22 晚：「坦克要能自己选位置贴爆反」「要能有一整套的坦克改装体系」「坦克上面就别贴了」「别挡住一些部位」
  --   爆反：一格一格按改装（TankMods.cellsOn）贴；原模型上本来就有的格（own）平时不画，只记位置（被炸掉时 View 补焦黑的空位）；
  --     型号：FY-2 / FY-4 是砖（导入的 Kontakt-1 砖网格，重型的盒子厚 1.35 倍）、ARAT-1（M19）是方盒子瓦、ARAT-2（M32）叠在 M19 外面的弯瓦（原车自带的 M19 外面也叠）
  --   主动防护：GL5 炮塔四角各一个发射单元（带毫米波雷达）；Trophy 两侧各一个能转的发射器 + 四角四块雷达平板
  --   激光告警：炮塔前角、后角的告警探头（JD-3 多一个激光干扰头）
  --   栅栏装甲：车尾、侧面后段（发动机舱外）、炮塔尾部后面，离车身约半米的一排扁钢条
  --   扫雷犁：车头前面一整排犁齿 + 犁板 + 两侧滑橇，两根臂挂在车头下沿；组 plow，按模型属性 Plow 放下 / 升起（View 摆）
  --   多光谱伪装网：炮塔两侧、后面，车体侧面、后面一片片的网（不盖车顶、不挡观瞄）
  --   车底防雷板：车底一整块（从侧面低处才看得到）
  --   车顶加特林（kit 组）：坦克不带机枪以后不用了，代码留着
  local era, kpiv, plowPiv = {}, nil, nil
  local mm = TM.applyDef(d, mods)
  mm = mm and mm.mods
  local L = TM.eraOf(d.id)
  local tp = extra.tpiv or (d.turret and d.turret.pivot) or V()
  if L then
    local kit = RS:FindFirstChild("Imported") and RS.Imported:FindFirstChild("Veh") and RS.Imported.Veh:FindFirstChild("kitera")
    local brickMesh = kit and kit:FindFirstChild("V_kitera__Body_1")
    local function rel(g, cf) if g == "t" then return CF(-tp) * cf end return cf end
    local on = TM.cellsOn(d.id, mm)
    local ET = mm and TM.ERA[mm.era] or nil
    local th = (ET and ET.th) or 1
    local arat = mm and (mm.era == "arat" or mm.era == "arat2")
    for i, b in ipairs(L.b) do
      local own = TM.own(L, b)
      local fitted = on[i] == true
      local cf, w, h, t = TM.blockCF(L, b, CF(), 0, own and 1 or th)
      local g = (b[1] == "t") and "turret" or "hull"
      local e = { g = g, off = rel(b[1], cf), w = w, h = h, t = t, own = own, parts = {}, off2 = not fitted }   -- off2：这一格没贴（不画、炸不着）
      if fitted and extra.imported then
        local col = RGB(b[14], b[15], b[16])
        local base = rel(b[1], cf)
        local function put(size, o, color, mat, shape, tr)
          local p = add(g, size, base * o, color, mat, shape)
          if tr then p.Transparency = tr end
          p.CastShadow = size.Z > 0.1
          table.insert(e.parts, p)
          return p
        end
        if not own and arat then
          -- ARAT-1（M19）：扁方盒，外面一圈压边、四颗固定螺栓，漆成车身色
          local c0 = col:Lerp(RGB(176, 158, 116), 0.35)
          put(V(w, h, t), CF(), c0, MAT.Metal)
          put(V(w * 0.86, h * 0.8, 0.04), CF(0, 0, t / 2 + 0.02), c0:Lerp(RGB(0, 0, 0), 0.08), MAT.SmoothPlastic)
          for sx = -1, 1, 2 do
            for sy = -1, 1, 2 do
              put(V(0.06, 0.13, 0.13), CF(sx * (w / 2 - 0.16), sy * (h / 2 - 0.14), t / 2 + 0.04) * CFrame.Angles(0, math.pi / 2, 0), RGB(70, 66, 56), MAT.Metal, CYL)
            end
          end
        elseif not own and brickMesh and brickMesh:IsA("MeshPart") then   -- 导入了砖的模型（models/veh/kitera.glb：Kontakt-1，evt22，CC-BY；贴图做旧过）
          local mp = Tint.fix(brickMesh:Clone(), brickMesh)
          mp.Anchored, mp.CanCollide, mp.CanQuery, mp.CanTouch = true, false, false, false
          mp.Size = V(w, h, t)
          local off = base * TURN
          mp.CFrame = off
          mp.Parent = m
          table.insert(parts, { mp, g, off })
          table.insert(e.parts, mp)
        elseif not own then
          -- 零件拼的做旧砖：漆面（比车身暗一点、金属纹理）、底下三成积灰、上沿一道掉漆露出的钢、一两道锈迹、两颗螺栓
          put(V(w, h, t), CF(), col:Lerp(RGB(40, 44, 34), 0.18), MAT.Metal)
          put(V(w * 1.004, h * 0.36, t * 1.02), CF(0, -h * 0.32, 0), RGB(92, 80, 60), MAT.Sand, nil, 0.5)
          put(V(w * 0.94, 0.05, 0.05), CF(0, h / 2 - 0.03, t / 2), RGB(150, 148, 136), MAT.Metal)
          for k = 1, (i % 3 == 0) and 2 or 1 do
            local x = ((i * 37 + k * 53) % 100 / 100 - 0.5) * w * 0.7
            put(V(0.07, h * (0.35 + (k * 0.1)), 0.02), CF(x, h * 0.05, t / 2 + 0.006), RGB(112, 60, 30), MAT.SmoothPlastic, nil, 0.3)
          end
          for sx = -1, 1, 2 do
            put(V(0.07, 0.17, 0.17), CF(sx * (w / 2 - 0.2), h / 2 - 0.17, t / 2 + 0.03) * CFrame.Angles(0, math.pi / 2, 0), RGB(48, 46, 40), MAT.Metal, CYL)
          end
        end
        if mm and mm.era == "arat2" then
          -- ARAT-2（M32）：叠在 M19 外面的弯瓦（中间往里凹，像屋顶的筒瓦）——两片斜板拼出弯度，上下两道边筋
          local c2 = col:Lerp(RGB(150, 134, 98), 0.4)
          local z0 = t / 2 + 0.16
          for sx = -1, 1, 2 do
            put(V(w * 0.52, h * 0.94, 0.12), CF(sx * w * 0.24, 0, z0 + 0.04) * CFrame.Angles(0, math.rad(-sx * 12), 0), c2, MAT.Metal)
          end
          for sy = -1, 1, 2 do put(V(w * 0.98, 0.07, 0.24), CF(0, sy * h * 0.47, z0), c2:Lerp(RGB(0, 0, 0), 0.12), MAT.Metal) end
        end
      end
      era[i] = e
    end
    local dark, olive = RGB(34, 36, 34), C.base:Lerp(RGB(50, 54, 44), 0.35)
    local function frameAt(c, n)
      local up = V(0, 1, 0)
      local rt = up:Cross(n)
      if rt.Magnitude < 0.1 then rt = V(1, 0, 0) end
      rt = rt.Unit
      return CFrame.fromMatrix(c, rt, n:Cross(rt).Unit, n)   -- Z 朝外
    end
    local tb, hb = L.tb, L.hb
    local roofY = L.roof or (tb and tb[5] - 0.8) or (tp.Y + 2)
    -- 主动防护
    if mm and mm.aps == "trophy" and L.aps then
      for _, a in ipairs(L.aps.l or {}) do   -- 两侧能转的发射器（带圆顶的弹仓、两根朝外上斜的发射管、探测窗）
        local f = CF(-tp) * frameAt(V(a[1], a[2], a[3]), V(a[4], a[5], a[6]).Unit)
        tur(V(0.5, 0.42, 1.0), f * CF(0, 0, 0.2), dark)   -- 支架
        tur(V(1.2, 0.95, 1.55), f * CF(0, 0.05, 0.95), olive)   -- 发射器
        tur(V(1.1, 0.48, 1.45), f * CF(0, 0.52, 0.95), olive:Lerp(RGB(0, 0, 0), 0.15), MAT.Metal, BALL)   -- 圆顶盖
        for k = -1, 1, 2 do
          tur(V(0.62, 0.34, 0.34), f * CF(k * 0.3, 0.2, 1.75) * CFrame.Angles(math.rad(-30), math.pi / 2, 0), dark, MAT.Metal, CYL)
        end
        tur(V(0.5, 0.22, 0.04), f * CF(0, -0.18, 1.74), RGB(10, 12, 14), MAT.Glass)
      end
      for _, a in ipairs(L.aps.r or {}) do   -- EL/M-2133 四块平板天线（四角各一块，斜着朝外）
        local f = CF(-tp) * frameAt(V(a[1], a[2], a[3]), V(a[4], a[5], a[6]).Unit)
        tur(V(1.4, 1.0, 0.2), f * CF(0, 0, 0.12), olive)
        tur(V(1.18, 0.8, 0.05), f * CF(0, 0, 0.24), RGB(20, 22, 24), MAT.SmoothPlastic)
        tur(V(0.3, 0.3, 0.5), f * CF(0, -0.6, -0.05), dark)
      end
    elseif mm and mm.aps == "gl5" and L.aps then
      for _, a in ipairs(L.aps.r or {}) do   -- GL5：四角各一个方盒（前面一块毫米波雷达面、上面斜着一个发射筒）
        local f = CF(-tp) * frameAt(V(a[1], a[2] - 0.15, a[3]), V(a[4], a[5], a[6]).Unit)
        tur(V(1.3, 1.0, 1.1), f * CF(0, 0, 0.35), olive)
        tur(V(1.08, 0.72, 0.05), f * CF(0, 0.02, 0.92), RGB(24, 26, 28), MAT.SmoothPlastic)   -- 雷达面
        tur(V(0.9, 0.46, 0.46), f * CF(0, 0.62, 0.3) * CFrame.Angles(math.rad(-25), math.pi / 2, 0), dark, MAT.Metal, CYL)   -- 发射筒（朝外上）
        tur(V(0.06, 0.5, 0.5), f * CF(0, 0.82, 0.72) * CFrame.Angles(math.rad(-25), math.pi / 2, 0), RGB(60, 62, 58), MAT.Metal, CYL)   -- 筒口盖
        tur(V(0.4, 0.3, 0.6), f * CF(0, -0.55, -0.05), dark)   -- 托架
      end
    end
    -- 激光告警探头（四个角的侧墙上，不在车顶）；JD-3 多一个激光干扰头（炮塔左前侧墙）；「窗帘-1」也带激光告警
    if mm and (mm.ew == "lws" or mm.ew == "jd3" or mm.ew == "shtora") and L.aps then
      for _, a in ipairs(L.aps.r or {}) do
        local f = CF(-tp) * frameAt(V(a[1], a[2] - 0.85, a[3]), V(a[4], a[5], a[6]).Unit)
        tur(V(0.42, 0.34, 0.3), f * CF(0, 0, 0.15), dark)
        tur(V(0.3, 0.2, 0.04), f * CF(0, 0.02, 0.31), RGB(30, 40, 60), MAT.Glass)
      end
      if mm.ew == "jd3" and L.aps.r[1] then
        local a = L.aps.r[1]
        local f = CF(-tp) * frameAt(V(a[1], a[2] - 0.2, a[3] + 0.9), V(a[4], 0, a[6]).Unit)
        tur(V(0.6, 0.6, 0.55), f * CF(0, 0, 0.3), dark, MAT.Metal, CYL)
        tur(V(0.04, 0.42, 0.42), f * CF(0, 0, 0.6) * CFrame.Angles(0, math.pi / 2, 0), RGB(90, 20, 18), MAT.Glass, CYL)
      end
    end
    -- 「窗帘-1」（T-90A）：炮两边各一个 OTShU-1-7 红外干扰灯——车身色的方盒、上沿一道遮光檐、正面黑圈里一个大圆灯。
    --   开着的样子（用户 11-28 给的图「它开起来是这个效果」）：中心白热、往外金黄 → 橙 → 红的一圈，外面一团光晕把灯框都映红了，
    --   往前照出一片橙红的光；车活着就开着（残骸上灭掉：View.lua），被打的时候干扰（服务器 dazzle）闪一下更亮
    local SH = mm and mm.ew == "shtora" and SHTORA[extra.imported or ""] or nil
    if SH then
      local R90 = CFrame.Angles(0, math.pi / 2, 0)   -- 圆柱的轴（X）转到朝前
      for sx = -1, 1, 2 do
        local box = CF(-tp) * CF(SH.gx + sx * SH.sx, SH.y, SH.zf + SH.d / 2)
        local hb = tur(V(SH.w, SH.h, SH.d), box, olive)
        hb.Name = "ShtoraBox"
        tur(V(SH.w * 0.98, 0.06, 0.26), box * CF(0, SH.h / 2 - 0.03, -SH.d / 2 - 0.12), olive)   -- 遮光檐
        tur(V(0.06, 0.64, 0.64), box * CF(0, -0.02, -SH.d / 2 - 0.03) * R90, RGB(14, 14, 14), MAT.Metal, CYL)   -- 黑圈
        local rim = tur(V(0.05, 0.56, 0.56), box * CF(0, -0.02, -SH.d / 2 - 0.07) * R90, RGB(255, 78, 28), MAT.Neon, CYL)   -- 橙红的一圈
        rim.Name = "ShtoraLens"
        local mid = tur(V(0.05, 0.42, 0.42), box * CF(0, -0.02, -SH.d / 2 - 0.09) * R90, RGB(255, 168, 70), MAT.Neon, CYL)   -- 金黄
        mid.Name = "ShtoraMid"
        local core = tur(V(0.05, 0.24, 0.24), box * CF(0, -0.02, -SH.d / 2 - 0.11) * R90, RGB(255, 244, 222), MAT.Neon, CYL)   -- 白热的芯
        core.Name = "ShtoraCore"
        -- 光晕：贴在灯上的一团柔光（粒子锁在零件上、几颗叠着淡进淡出，看上去一直亮着）
        local at = Instance.new("Attachment")
        at.Name = "ShtoraGlow"
        at.Parent = core
        local pe = Instance.new("ParticleEmitter")
        pe.Name = "ShtoraHalo"
        pe.Texture = "rbxasset://textures/particles/explosion01_implosion_main.dds"
        pe.LightEmission, pe.LightInfluence = 1, 0
        pcall(function() pe.Brightness = 2.2 end)
        pe.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, RGB(255, 196, 120)), ColorSequenceKeypoint.new(1, RGB(255, 110, 50)) })
        pe.Size = NumberSequence.new(1.9)
        pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.55), NumberSequenceKeypoint.new(0.75, 0.55), NumberSequenceKeypoint.new(1, 1) })
        pe.Lifetime = NumberRange.new(1.1, 1.3)
        pe.Rate = 4
        pe.Speed = NumberRange.new(0)
        pe.LockedToPart = true
        pe.ZOffset = 0.6
        pe.Parent = at
        -- 往前照的光（照亮车前一片地；不投影子）
        local sl = Instance.new("SpotLight")
        sl.Name = "ShtoraLight"
        sl.Face, sl.Angle, sl.Range, sl.Brightness, sl.Color, sl.Shadows = Enum.NormalId.Front, 70, 18, 1.6, RGB(255, 120, 56), false
        sl.Parent = hb
      end
    end
    -- 栅栏装甲：扁钢条竖着排（间距约 0.9 格 ≈ 32 厘米），上下两道横框、几根撑杆；离车身 1.4 格（半米）
    if mm and mm.slat == "slat" and hb then
      local SC = C.base:Lerp(RGB(60, 62, 56), 0.25)
      local function grille(group, o, along, wid, hei, depth)
        local fn = (group == "turret") and tur or hull
        local n = math.max(2, math.floor(wid / 0.9))
        for k = 0, n do
          local x = -wid / 2 + wid * k / n
          fn(V(0.07, hei, 0.32), o * CF(along * x, 0, 0), SC, MAT.Metal)
        end
        for sy = -1, 1, 2 do fn(V(wid + 0.1, 0.12, 0.12), o * CF(0, sy * hei / 2, 0), SC, MAT.Metal) end
        for k = -1, 1, 2 do fn(V(0.12, 0.12, depth), o * CF(k * wid * 0.42, hei * 0.3, -depth / 2), SC, MAT.Metal) end   -- 撑杆（往车身那边）
      end
      local rz = hb[6] + 1.4
      local y0, y1 = 1.4, hb[5] - 0.2
      grille("hull", CF(0, (y0 + y1) / 2, rz), 1, hb[4] - hb[1] - 0.6, y1 - y0, 1.4)   -- 车尾
      local sl = (hb[6] - hb[3]) * 0.3
      for sx = -1, 1, 2 do   -- 侧面后段（发动机舱外，裙板外面）
        local x = (sx > 0) and (hb[4] + 1.2) or (hb[1] - 1.2)
        grille("hull", CF(x, (y0 + 1.1 + y1) / 2, hb[6] - sl / 2) * CFrame.Angles(0, math.pi / 2, 0), 1, sl, y1 - y0 - 1.1, 1.2)
      end
      if tb then   -- 炮塔尾部后面
        local tz = tb[6] + 1.0
        local ty0, ty1 = tb[2] + 0.3, roofY - 0.25
        grille("turret", CF(-tp) * CF((tb[1] + tb[4]) / 2, (ty0 + ty1) / 2, tz), 1, (tb[4] - tb[1]) * 0.78, ty1 - ty0, 1.0)
      end
    end
    -- 车底防雷板：车底一整块，四角加强筋
    if mm and mm.belly == "belly" and hb then
      local y = (d.clear or 1.3) * 0.62
      hull(V((hb[4] - hb[1]) * 0.62, 0.18, (hb[6] - hb[3]) * 0.72), CF(0, y, (hb[3] + hb[6]) / 2), RGB(52, 54, 50), MAT.DiamondPlate)
      for sx = -1, 1, 2 do hull(V(0.2, 0.3, (hb[6] - hb[3]) * 0.7), CF(sx * (hb[4] - hb[1]) * 0.3, y + 0.15, (hb[3] + hb[6]) / 2), RGB(46, 48, 44), MAT.Metal) end
    end
    -- 扫雷犁（全宽扫雷犁）：组 plow，转轴在车头下沿；放下时犁齿入土、升起时绕转轴往上抬 14°
    if mm and mm.eng == "plow" and hb then
      plowPiv = V(0, 1.7, hb[3] + 0.6)
      local PC, PD = C.base:Lerp(RGB(70, 72, 64), 0.3), RGB(46, 46, 44)
      local function pl(size, o, color, mat, shape) return add("plow", size, o, color or PC, mat or MAT.Metal, shape) end
      local bw = (hb[4] - hb[1]) * 1.0
      local zb = -3.4   -- 犁板在转轴前面多远
      for sx = -1, 1, 2 do   -- 两根臂
        pl(V(0.45, 0.55, 3.6), CF(sx * bw * 0.32, -0.4, -1.7) * CFrame.Angles(math.rad(10), 0, 0), PD)
      end
      pl(V(bw, 1.6, 0.25), CF(0, 0.2, zb) * CFrame.Angles(math.rad(-18), 0, 0))   -- 犁板（往后仰）
      pl(V(bw, 0.5, 0.25), CF(0, -0.75, zb - 0.45) * CFrame.Angles(math.rad(-48), 0, 0))   -- 犁板下沿往前卷
      pl(V(bw + 0.1, 0.18, 0.8), CF(0, 1.02, zb + 0.15), PD)   -- 顶梁
      local nT = math.max(6, math.floor(bw / 0.75))
      for k = 0, nT - 1 do   -- 犁齿（往前下插）
        local x = -bw / 2 + bw * (k + 0.5) / nT
        pl(V(0.16, 0.16, 1.15), CF(x, -1.05, zb - 0.85) * CFrame.Angles(math.rad(28), 0, 0), RGB(58, 56, 52), MAT.Metal)
      end
      for sx = -1, 1, 2 do   -- 两侧滑橇（控制犁地深度）
        pl(V(0.3, 0.35, 1.6), CF(sx * (bw / 2 + 0.2), -1.15, zb + 0.2), PD)
      end
    end
    -- 多光谱伪装网（梭鱼 MCS 那一类）：炮塔两侧、后面，车体侧面、后面一片片的网——三种颜色的斑块交错，不盖车顶、不挡观瞄、不盖车灯
    if mm and mm.cam == "mcs" and hb and tb then
      local NC = (team == "def") and { RGB(170, 150, 108), RGB(128, 112, 80), RGB(196, 180, 140) } or { RGB(76, 92, 60), RGB(58, 66, 46), RGB(104, 112, 78) }
      local function patch(fn, size, o, k)
        local p = fn(size, o, NC[(k % 3) + 1], MAT.Fabric)
        p.CastShadow = false
        return p
      end
      local k = 0
      for sx = -1, 1, 2 do
        -- 炮塔侧面后半（错开几片）
        local x = (sx > 0) and (tb[4] + 0.18) or (tb[1] - 0.18)
        local z0, z1 = tb[3] + (tb[6] - tb[3]) * 0.45, tb[6] - 0.3
        for j = 0, 3 do
          k += 1
          local zc = z0 + (z1 - z0) * (j + 0.5) / 4
          patch(tur, V(0.08, (roofY - tb[2]) * (0.55 + (j % 2) * 0.2), (z1 - z0) / 3.4), CF(-tp) * CF(x + sx * 0.02 * (j % 2), tb[2] + (roofY - tb[2]) * 0.45, zc), k + (sx > 0 and 1 or 0))
        end
        -- 车体侧面后段（裙板外）
        local hx = (sx > 0) and (hb[4] + 0.22) or (hb[1] - 0.22)
        for j = 0, 4 do
          k += 1
          local zc = hb[3] + (hb[6] - hb[3]) * (0.45 + 0.11 * j)
          patch(hull, V(0.08, 1.6 + (j % 2) * 0.5, (hb[6] - hb[3]) * 0.12), CF(hx + sx * 0.02 * (j % 2), hb[5] * 0.55, zc), k)
        end
      end
      for j = 0, 3 do   -- 车尾
        k += 1
        patch(hull, V((hb[4] - hb[1]) / 4.2, 1.8, 0.08), CF(hb[1] + (hb[4] - hb[1]) * (j + 0.5) / 4, hb[5] * 0.6 + (j % 2) * 0.3, hb[6] + 0.25), k)
      end
    end
    -- 车顶 GAU-8 加特林炮塔附件：转轴在炮塔顶左侧（装填手那边），跟着炮俯仰（坦克不带机枪以后不用了）
    if mm and mm.roof == "gau8" then
      kpiv = TM.kitPivot(L)
      local kp = kpiv - tp
      local GM, BL, OD = RGB(52, 54, 50), RGB(28, 29, 28), C.base
      tur(V(0.3, 2.7, 2.7), CF(kp.X, kp.Y - 0.85, kp.Z) * UPRIGHT, BL, MAT.Metal, CYL)
      tur(V(1.6, 0.7, 1.9), CF(kp.X, kp.Y - 0.45, kp.Z + 0.2), OD)
      local function kg(size, off, color, mat, shape) return add("kit", size, off, color or GM, mat or MAT.Metal, shape) end
      kg(V(1.1, 1.0, 2.5), CF(0, 0, 0.3), OD)
      for k = 0, 6 do
        local a = k / 7 * math.pi * 2
        tube(kg, math.cos(a) * 0.27, math.sin(a) * 0.27, -0.95, -TM.KIT_MUZ, 0.16, BL)
      end
    end
  end

  return { model = m, parts = parts, wheels = wheels, dust = dust, exhaust = exhaust, fire = fire, black = black, def = d, lamps = lamps,
    imported = extra.imported, tpiv = extra.tpiv, gpiv = extra.gpiv, travel = extra.travel, rpiv = extra.rpiv, rgpiv = extra.rgpiv, carve = extra.carve,
    era = era, eraL = L, kpiv = kpiv and (kpiv - tp) or nil, plowPiv = plowPiv, mods = mm }
end

-- 爆反块被炸掉的样子（View 调）：砖藏起来，原地一块焦黑的底板、几片翻卷的钢皮、一圈熏黑——返回新加的零件 { 零件, 组, 相对位置 }
function VehModels.eraBlown(M, i)
  local e = M.era and M.era[i]
  if not e or e.blown then return {} end
  e.blown = true
  for _, p in ipairs(e.parts) do p.Transparency = 1 end
  local out = {}
  local function put(size, o, color, mat, tr)
    local p = Instance.new("Part")
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.Size, p.Color, p.Material = size, color, mat
    p.Transparency = tr or 0
    p.CastShadow = false
    local off = e.off * o
    p.CFrame = off
    p.Parent = M.model
    table.insert(out, { p, e.g, off })
    return p
  end
  local w, h, t = e.w, e.h, e.t
  -- 砖底下（贴着车身那一面）：焦黑的底板、熏黑的一圈
  put(V(w * 1.25, h * 1.25, 0.05), CF(0, 0, -t / 2 + 0.03), RGB(24, 22, 20), Enum.Material.Slate, 0.15)
  put(V(w * 0.92, h * 0.88, 0.09), CF(0, 0, -t / 2 + 0.07), RGB(40, 37, 33), Enum.Material.CorrodedMetal)
  -- 翻卷的钢皮（几片歪着的薄板）、两颗剩下的螺栓
  for k = 1, 3 do
    local a = (i * 13 + k * 29) % 17 / 17
    put(V(w * 0.22, h * 0.18, 0.04), CF((a - 0.5) * w * 0.8, ((k % 2) - 0.5) * h * 0.6, -t / 2 + 0.16) * CFrame.Angles(math.rad(35 + 30 * a), math.rad(20 * k), 0),
      RGB(70, 66, 58), Enum.Material.CorrodedMetal)
  end
  for sx = -1, 1, 2 do
    put(V(0.12, 0.15, 0.15), CF(sx * (w / 2 - 0.2), h / 2 - 0.17, -t / 2 + 0.12), RGB(44, 42, 38), Enum.Material.Metal)
  end
  return out
end

-- 静止的样子（炮塔朝前、炮平着）：把 build 出来的零件摆到车的底座系（科技树资料卡的装甲查看器用；车库 Garage.lua 里有一份一样的）
function VehModels.pose(M, d)
  local tp = M.tpiv or (d.turret and d.turret.pivot) or V()
  local tF = CF(tp)
  local gF = tF * CF(M.gpiv or (d.gun and d.gun.pivot) or V())
  local rF = M.rpiv and (tF * CF(M.rpiv)) or tF
  local rgF = (M.rpiv and M.rgpiv) and (rF * CF(M.rgpiv)) or rF
  local kF = M.kpiv and (tF * CF(M.kpiv)) or tF
  for _, it in ipairs(M.parts) do
    local p, grp, off, idx = it[1], it[2], it[3], it[4]
    local cf
    if grp == "turret" then cf = tF * off
    elseif grp == "gun" then cf = gF * off
    elseif grp == "rws" then cf = rF * off
    elseif grp == "rwg" then cf = rgF * off
    elseif grp == "kit" then cf = kF * off
    elseif grp == "wheel" then
      local w = M.wheels[idx]
      cf = w and (CF(w.x, w.r, w.z) * off) or off
    else cf = off end
    p.CFrame = cf
  end
  return tp
end

return VehModels