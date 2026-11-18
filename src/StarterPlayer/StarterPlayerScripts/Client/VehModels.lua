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
local IM = nil
do
  local ok, r = pcall(function() return require(RS:WaitForChild("ImportedMeta", 3)) end)
  if ok and type(r) == "table" then IM = r end
end
local function importedFor(d)
  if not IM then return nil end
  local key = IM.alias and IM.alias[d.id]
  local info = key and IM.m[key]
  if not info then return nil end
  local imp = RS:FindFirstChild("Imported")
  local veh = imp and imp:FindFirstChild("Veh")
  local f = veh and veh:FindFirstChild(key)
  if not f then return nil end
  local n = f:GetAttribute("N")   -- 服务器记的块数：还没全复制过来就先不用（View 等块齐了再重建）
  if n and #f:GetChildren() < n then return nil end
  return key, info, f
end
VehModels.importedFor = importedFor

local V = Vector3.new
local CF = CFrame.new
local RGB = Color3.fromRGB
local MAT = Enum.Material
local CYL, BALL = Enum.PartType.Cylinder, Enum.PartType.Ball
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)   -- 圆柱的轴（X）转到 Z（炮管、烟幕弹管）
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)  -- 圆柱的轴转到 Y（竖着的圆盘、舱盖）

local CAMO = {
  atk = { base = RGB(86, 100, 68), dark = RGB(60, 70, 48), light = RGB(118, 126, 90) },   -- 解放军：林地绿
  def = { base = RGB(176, 158, 116), dark = RGB(128, 114, 84), light = RGB(198, 184, 146) },   -- 美军：沙色
}
local TRACK, RUBBER, STEEL, GLASS = RGB(44, 44, 46), RGB(28, 28, 30), RGB(70, 72, 74), RGB(40, 54, 62)

function VehModels.build(d, team)
  local C = CAMO[team] or CAMO.atk
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
    for name, p in pairs(info.parts) do
      local src = folder:FindFirstChild("V_" .. ikey .. "__" .. name)
      if src and src:IsA("BasePart") then
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
        if p.g == "Turret" then grp, off = "turret", CF(c - tpiv)
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
    extra = { imported = ikey, tpiv = tpiv, gpiv = gpiv - tpiv, travel = (d.arch == "tracked") and 0.12 or d.travel,
      rpiv = rpiv and (rpiv - tpiv) or nil, rgpiv = (rpiv and rgpiv) and (rgpiv - rpiv) or nil }
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
    tur(V(0.6, 0.6, 1.4), CF((d.cupola and d.cupola.X or 1.4), s.Y + 0.6, (d.cupola and d.cupola.Z or 0.2) - 0.6), RGB(40, 42, 44))   -- 车长机枪
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
      sl.Face, sl.Angle, sl.Range, sl.Brightness, sl.Color, sl.Shadows = Enum.NormalId.Front, 55, 70, 3.2, RGB(255, 240, 210), true
      sl.Parent = fl
    end
    local tl = lampPart(CF(sd * d.W * 0.4, d.hullH * 0.55, d.L / 2 + 0.05), RGB(255, 40, 30), 0.32)
    local pl = Instance.new("PointLight")
    pl.Range, pl.Brightness, pl.Color, pl.Shadows = 6, 0.8, RGB(255, 40, 30), false
    pl.Parent = tl
  end

  return { model = m, parts = parts, wheels = wheels, dust = dust, fire = fire, black = black, def = d, lamps = lamps,
    imported = extra.imported, tpiv = extra.tpiv, gpiv = extra.gpiv, travel = extra.travel, rpiv = extra.rpiv, rgpiv = extra.rgpiv }
end

return VehModels
