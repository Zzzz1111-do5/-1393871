-- Roblox全面大战场（客户端）——舰艇的样子（G.viewKind.ship，View.lua 每帧调）：按 ShipDefs 的 look 拼零件——
--   船体（水线下红色防污漆、水线一圈黑色、水线上舰体灰；船头两块楔形收成尖）、双体 / 三体、甲板、上层建筑（隐身舰两层收口）、舰桥窗、
--   桅杆（055 / 054A 的四面相控阵在一体化桅杆上，美舰的在舰桥四角）、烟囱、垂发（一格一格）、斜置的导弹发射箱、直升机甲板标线、
--   舰炮（炮塔按 Ty / Gp 转，开炮炮管后坐）、近防炮、舷号、航行灯（桅顶白、左红右绿、艉白）、舰旗；
--   随浪起伏、转弯外倾；船头浪花、尾迹、烟囱排烟；挨打冒烟着火；击沉后慢慢倾覆、下沉
--   自己开的船用本地算的位置和炮塔角（Sail.lua 的 G.sail），别人的平滑跟着服务器；船尾一个「上船」提示（码头上走过去按 E）
--   原模型（网页版的舰艇模型原样转的 models/ship/<型号>.glb，Studio 导入后 Imports.lua 收进 ReplicatedStorage.Imported.Ship.<型号>，元数据 ImportedShip）：
--     有就只换「蒙皮」——船体、上层建筑、桅杆、烟囱、垂发、近防炮、舷号换成原模型；主炮用原模型上的（炮塔连炮管跟着炮塔角转，不俯仰）；
--     航行灯、舰旗挪到原模型上，浪花、尾迹、烟囱排烟、着火照旧
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Tint = require(script.Parent:WaitForChild("Tint"))   -- 导入的贴图没出来时的底色（原贴图的平均色）
local TURN = require(RS:WaitForChild("ImportTurn")).TURN   -- 导入的每块网格被 Roblox 转了半圈（ImportTurn.lua）：摆的时候转回来

local ShipView = {}

function ShipView.init(G)
  local SD = require(RS:WaitForChild("ShipDefs"))
  local V, CF, RGB = Vector3.new, CFrame.new, Color3.fromRGB
  local MAT = Enum.Material
  local BALL, CYL = Enum.PartType.Ball, Enum.PartType.Cylinder
  local me = Players.LocalPlayer
  local function T(k, ...) return G.T(k, ...) end
  local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
  local RED_LOW, BOOT, GLASS = RGB(118, 44, 40), RGB(30, 32, 34), RGB(28, 36, 44)
  local TEAMC = { atk = RGB(214, 52, 44), def = RGB(52, 96, 190) }
  local IS = nil   -- 原模型的元数据（tools/models/ship2glb.py 生成）
  do
    local ok, r = pcall(function() return require(RS:WaitForChild("ImportedShip", 3)) end)
    if ok and type(r) == "table" then IS = r end
  end
  local function importedFor(d)
    local info = IS and IS.m and IS.m[d.id]
    local imp = RS:FindFirstChild("Imported")
    local sh = imp and imp:FindFirstChild("Ship")
    local f = sh and sh:FindFirstChild(d.id)
    local n = f and f:GetAttribute("N")   -- 块还没全复制过来就先不用（View 等块齐了再重建）
    if n and #f:GetChildren() < n then return nil end
    if info and f then return info, f end
    return nil
  end
  -- 正在拼哪一类零件（有原模型时只留下 lamp 灯、fx 粒子、flag 舰旗，其余是蒙皮）
  local TAG = nil

  ---------------------------------------------------------------- 拼零件

  -- 一个零件：grp "hull" 跟着船、"t" 跟着第 gi 座炮塔转、"g" 跟着炮管（俯仰、后坐）；off 相对船（水线中心）/ 炮塔 / 炮管的 CFrame
  local function mk(M, cls, size, off, color, mat, grp, gi, shape)
    local p = Instance.new(cls or "Part")
    if shape then p.Shape = shape end
    p.Size, p.Color = size, color
    p.Material = mat or MAT.SmoothPlastic
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.CastShadow = size.Magnitude > 3
    p.CFrame = off
    p.Parent = M.model
    table.insert(M.items, { p = p, g = grp or "hull", off = off, i = gi, tag = TAG })
    return p
  end

  -- 船体一段：宽 w、中线在 x，从 z0（船头尖）到 z1（船尾），底 yb、顶 yt；船头 bowL 长收成尖（左右两块楔形，宽的一头接船身）
  local function hullSeg(M, x, w, z0, z1, yb, yt, bowL, col)
    local h = yt - yb
    if h <= 0.04 then return end
    local yc = (yb + yt) / 2
    local L = z1 - z0 - bowL
    mk(M, "Part", V(w, h, L), CF(x, yc, z0 + bowL + L / 2), col, MAT.Metal)
    mk(M, "WedgePart", V(h, w / 2, bowL), CF(x + w / 4, yc, z0 + bowL / 2) * CFrame.Angles(0, 0, -math.pi / 2), col, MAT.Metal)
    mk(M, "WedgePart", V(h, w / 2, bowL), CF(x - w / 4, yc, z0 + bowL / 2) * CFrame.Angles(0, 0, math.pi / 2), col, MAT.Metal)
  end
  -- 一条船体：水线下红、水线一圈黑、上面舰体色；顶上一层甲板色
  local function hull(M, x, w, z0, z1, yb, yt, bowL, col, deckCol)
    hullSeg(M, x, w, z0, z1, yb, math.min(-0.5, yt), bowL, RED_LOW)
    hullSeg(M, x, w + 0.08, z0 - 0.04, z1 + 0.04, math.max(-0.5, yb), math.min(0.7, yt), bowL, BOOT)
    hullSeg(M, x, w, z0, z1, math.max(0.7, yb), yt, bowL, col)
    if deckCol then
      local L = z1 - z0 - bowL
      mk(M, "Part", V(w - 0.3, 0.12, L - 0.3), CF(x, yt + 0.06, z0 + bowL + L / 2), deckCol, MAT.Concrete)
      mk(M, "WedgePart", V(0.12, w / 2 - 0.2, bowL - 0.6), CF(x + w / 4 - 0.05, yt + 0.06, z0 + bowL / 2 + 0.3) * CFrame.Angles(0, 0, -math.pi / 2), deckCol, MAT.Concrete)
      mk(M, "WedgePart", V(0.12, w / 2 - 0.2, bowL - 0.6), CF(x - w / 4 + 0.05, yt + 0.06, z0 + bowL / 2 + 0.3) * CFrame.Angles(0, 0, math.pi / 2), deckCol, MAT.Concrete)
    end
  end

  -- 夜里的灯：霓虹小块 + 远处也看得见的光晕（BillboardGui）+ 小点光源
  local function lamp(M, off, color, size, range)
    local t0 = TAG
    TAG = "lamp"
    local p = mk(M, "Part", V(size, size, size), off, color, MAT.Neon)
    TAG = t0
    p.CastShadow = false
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(size * 5, 4, size * 5, 4)
    bb.LightInfluence = 0
    bb.MaxDistance = 5000
    bb.Parent = p
    local halo = Instance.new("Frame")
    halo.AnchorPoint, halo.Position, halo.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1)
    halo.BackgroundColor3, halo.BackgroundTransparency, halo.BorderSizePixel = color, 0.72, 0
    halo.Parent = bb
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = halo
    if range then
      local L = Instance.new("PointLight")
      L.Color, L.Range, L.Brightness, L.Shadows = color, range, 1.2, false
      L.Parent = p
    end
    return p
  end

  -- 舷号：船头两侧各一块透明薄板上的字（右舷读向船头、左舷读向船尾，从外面看都是正的）
  local function hullNumber(M, d, text, zc, yc, h)
    if not text or text == "" then return end
    local len = h * 0.62 * #text + h * 0.3
    for _, s in ipairs({ 1, -1 }) do
      local p = mk(M, "Part", V(0.1, h, len), CF(s * (d.W / 2 + 0.1), yc, zc), RGB(0, 0, 0), MAT.SmoothPlastic)
      p.Transparency = 1
      p.CastShadow = false
      local sg = Instance.new("SurfaceGui")
      sg.Face = (s > 0) and Enum.NormalId.Right or Enum.NormalId.Left
      sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
      sg.PixelsPerStud = 24
      sg.LightInfluence = 0.7
      sg.Parent = p
      local l = Instance.new("TextLabel")
      l.Size = UDim2.fromScale(1, 1)
      l.BackgroundTransparency = 1
      l.Text = text
      l.TextScaled = true
      l.Font = Enum.Font.GothamBlack
      l.TextColor3 = RGB(236, 238, 236)
      l.TextStrokeColor3 = RGB(10, 10, 10)
      l.TextStrokeTransparency = 0.25
      l.Parent = sg
    end
  end

  -- 粒子：挂在一个看不见的小零件上（跟着船走）
  local function emitter(M, off, props)
    local t0 = TAG
    TAG = "fx"
    local h = mk(M, "Part", V(0.2, 0.2, 0.2), off, RGB(0, 0, 0), MAT.SmoothPlastic)
    TAG = t0
    h.Transparency = 1
    h.CastShadow = false
    local pe = Instance.new("ParticleEmitter")
    pe.Texture = SMOKE
    pe.Rate = 0
    for k, v in pairs(props) do pe[k] = v end
    pe.Parent = h
    return pe
  end
  local function seq(a, b) return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) }) end

  -- 一座炮：炮塔（隐身舰前面一块斜面）、炮盾、炮管（双联 / 加特林）、炮口
  local CAL = { g130 = 1.2, g127 = 1.1, g76 = 0.8, g57 = 0.62, g30 = 0.9, m2x2 = 0.24 }
  local function gun(M, d, gi, col)
    local g = d.guns[gi]
    local s = g.size
    mk(M, "Part", V(s.X, s.Y, s.Z), CF(0, s.Y / 2, 0), col, MAT.Metal, "t", gi)
    if g.stealth then
      mk(M, "WedgePart", V(s.X, s.Y * 0.92, s.Z * 0.42), CF(0, s.Y * 0.46, -s.Z / 2 - s.Z * 0.21), col, MAT.Metal, "t", gi)
    elseif not g.twin then
      mk(M, "Part", V(s.X * 0.9, s.Y * 0.3, s.Z * 0.5), CF(0, s.Y + s.Y * 0.15, s.Z * 0.15), col:Lerp(RGB(0, 0, 0), 0.1), MAT.Metal, "t", gi)   -- 炮塔顶
    end
    local c = CAL[g.w] or 0.6
    local len = g.len
    if g.twin then
      for _, x in ipairs({ -0.35, 0.35 }) do
        mk(M, "Part", V(len, c, c), CF(x, 0, -len / 2) * CFrame.Angles(0, math.pi / 2, 0), RGB(40, 42, 44), MAT.Metal, "g", gi, CYL)
      end
      mk(M, "Part", V(1.6, 1.0, 0.15), CF(0, 0.2, -0.3), RGB(70, 78, 66), MAT.Metal, "g", gi)   -- 枪盾
    elseif g.gatling then
      mk(M, "Part", V(len, c, c), CF(0, 0, -len / 2) * CFrame.Angles(0, math.pi / 2, 0), RGB(44, 46, 48), MAT.Metal, "g", gi, CYL)
      mk(M, "Part", V(0.3, c * 1.3, c * 1.3), CF(0, 0, -len + 0.15) * CFrame.Angles(0, math.pi / 2, 0), RGB(30, 30, 32), MAT.Metal, "g", gi, CYL)
    else
      mk(M, "Part", V(len, c, c), CF(0, 0, -len / 2) * CFrame.Angles(0, math.pi / 2, 0), col:Lerp(RGB(0, 0, 0), 0.25), MAT.Metal, "g", gi, CYL)
      mk(M, "Part", V(len * 0.12, c * 1.35, c * 1.35), CF(0, 0, -len * 0.06) * CFrame.Angles(0, math.pi / 2, 0), col:Lerp(RGB(0, 0, 0), 0.15), MAT.Metal, "g", gi, CYL)   -- 炮管根部的加粗段
      mk(M, "Part", V(s.X * 0.45, s.Y * 0.5, 0.4), CF(0, 0, 0.1), col:Lerp(RGB(0, 0, 0), 0.2), MAT.Metal, "g", gi)   -- 炮盾
    end
  end

  -- 近防炮：底座、白色雷达罩、一束炮管
  local function ciws(M, mp, col)
    mk(M, "Part", V(2.4, 1.6, 2.4), CF(mp + V(0, -0.9, 0)), col, MAT.Metal)
    mk(M, "Part", V(2.3, 2.3, 2.3), CF(mp + V(0, 0.9, 0.1)), RGB(232, 234, 232), MAT.SmoothPlastic, nil, nil, BALL)
    mk(M, "Part", V(1.4, 1.4, 1.6), CF(mp + V(0, -0.1, 0)), RGB(220, 222, 220), MAT.SmoothPlastic)
    mk(M, "Part", V(2.4, 0.5, 0.5), CF(mp + V(0, -0.1, -1.8)) * CFrame.Angles(0, math.pi / 2, 0), RGB(40, 42, 44), MAT.Metal, nil, nil, CYL)
  end

  local function build(d, team)
    local L = d.look or {}
    local M = { model = Instance.new("Model"), items = {} }
    M.model.Name = "Ship_" .. d.id
    local col = L.color or RGB(120, 126, 130)
    local deckCol = col:Lerp(RGB(30, 34, 36), 0.45)
    local supCol = col:Lerp(RGB(255, 255, 255), 0.04)
    local yb = -d.draft
    local bowL = d.L * 0.27
    local z0, z1 = -d.L / 2, d.L / 2
    -- 船体
    if L.hulls == 2 then   -- 双体（022）：两条窄船体 + 上面一整块桥接甲板（前端一块斜面）
      local hw = d.W * 0.28
      for _, s in ipairs({ -1, 1 }) do hull(M, s * (d.W / 2 - hw / 2), hw, z0, z1, yb, 1.6, d.L * 0.22, col) end
      local cz0 = z0 + d.L * 0.16
      mk(M, "Part", V(d.W, d.deck - 1.4, z1 - cz0 - 6), CF(0, (d.deck + 1.4) / 2, (cz0 + 6 + z1) / 2), col, MAT.Metal)
      mk(M, "WedgePart", V(d.W, d.deck - 1.4, 6), CF(0, (d.deck + 1.4) / 2, cz0 + 3), col, MAT.Metal)
      mk(M, "Part", V(d.W - 0.3, 0.12, z1 - cz0 - 6.3), CF(0, d.deck + 0.06, (cz0 + 6 + z1) / 2), deckCol, MAT.Concrete)
    elseif L.hulls == 3 then   -- 三体（LCS-2）：中间主船体、两边细长的侧体，后面三分之二是整块宽甲板
      local cw = d.W * 0.26
      hull(M, 0, cw, z0, z1, yb, d.deck, d.L * 0.3, col, deckCol)
      for _, s in ipairs({ -1, 1 }) do hull(M, s * (d.W / 2 - d.W * 0.05), d.W * 0.1, -d.L * 0.12, z1, -d.draft * 0.5, 2, d.L * 0.14, col) end
      local sz0 = z0 + d.L * 0.34
      mk(M, "Part", V(d.W, d.deck - 2, z1 - sz0), CF(0, (d.deck + 2) / 2, (sz0 + z1) / 2), col, MAT.Metal)
      mk(M, "WedgePart", V(d.W * 0.6, d.deck - 2, d.L * 0.12), CF(0, (d.deck + 2) / 2, sz0 - d.L * 0.06), col, MAT.Metal)
      mk(M, "Part", V(d.W - 0.3, 0.12, z1 - sz0 - 0.3), CF(0, d.deck + 0.06, (sz0 + z1) / 2), deckCol, MAT.Concrete)
    elseif L.open then   -- 小艇（PBR）：玻璃钢艇身、低矮的驾驶台、后面的发动机舱盖
      hull(M, 0, d.W, z0, z1, yb, d.deck, d.L * 0.3, col, col:Lerp(RGB(0, 0, 0), 0.25))
      mk(M, "Part", V(d.W * 0.7, 1.6, 3), CF(0, d.deck + 0.8, 0.5), col:Lerp(RGB(0, 0, 0), 0.1), MAT.SmoothPlastic)
      mk(M, "Part", V(d.W * 0.66, 0.8, 0.12), CF(0, d.deck + 2, -1.05) * CFrame.Angles(math.rad(-20), 0, 0), GLASS, MAT.Glass).Transparency = 0.3
      mk(M, "Part", V(0.15, 2.6, 0.15), CF(0, d.deck + 2.9, 1.5), RGB(40, 42, 44), MAT.Metal)
      mk(M, "Part", V(1, 0.5, 1), CF(0, d.deck + 4.3, 1.5), RGB(220, 222, 220), MAT.SmoothPlastic, nil, nil, BALL)   -- 雷达罩
      mk(M, "Part", V(d.W * 0.8, 0.8, 4), CF(0, d.deck + 0.4, 5.2), col:Lerp(RGB(0, 0, 0), 0.2), MAT.SmoothPlastic)
      mk(M, "Part", V(1.4, 0.5, 1.4), CF(0, d.deck + 0.25, -5.2), RGB(60, 66, 58), MAT.Metal, nil, nil, CYL)   -- 枪座
    else
      hull(M, 0, d.W, z0, z1, yb, d.deck, bowL, col, deckCol)
    end
    -- 上层建筑：第一块主上层建筑、第二块舰桥（前面一排窗）、其余（机库……）；隐身舰两层（上层窄一点像收口的斜面）
    for k, s in ipairs(L.sup or {}) do
      local za, zb, w, h, y = s[1], s[2], s[3], s[4], s[5]
      local zc, len = (za + zb) / 2, zb - za
      if L.stealth then
        mk(M, "Part", V(w, h * 0.72, len), CF(0, y + h * 0.36, zc), supCol, MAT.Metal)
        mk(M, "Part", V(w * 0.86, h * 0.28, len - w * 0.07), CF(0, y + h * 0.86, zc), supCol, MAT.Metal)
        mk(M, "WedgePart", V(w * 0.86, h * 0.28, w * 0.07), CF(0, y + h * 0.86, za + w * 0.035), supCol, MAT.Metal)
      else
        mk(M, "Part", V(w, h, len), CF(0, y + h / 2, zc), supCol, MAT.Metal)
      end
      if k == 2 then
        local wt = L.stealth and (w * 0.86) or w
        mk(M, "Part", V(wt * 0.84, h * 0.2, 0.2), CF(0, y + h * 0.78, za - 0.08), GLASS, MAT.Glass)
        for _, sx in ipairs({ -1, 1 }) do   -- 两侧舰桥翼
          mk(M, "Part", V(2.4, 0.5, 4), CF(sx * (w / 2 + 1.2), y + h * 0.62, za + 3), supCol, MAT.Metal)
        end
      end
    end
    -- 桅杆：一体化桅杆（宽的）四面相控阵；美舰的相控阵在舰桥（第二块）四角
    local mast = L.mast
    local mastTop = nil
    if mast then
      local mw, mh = L.mastW or 6, L.mastH or 10
      local panelC = RGB(58, 66, 74)
      if mw >= 9 then
        mk(M, "Part", V(mw, mh * 0.75, mw * 1.2), CF(mast + V(0, mh * 0.375, 0)), supCol, MAT.Metal)
        mk(M, "Part", V(mw * 0.7, mh * 0.25, mw * 0.84), CF(mast + V(0, mh * 0.875, 0)), supCol, MAT.Metal)
        if L.panel then
          local ps = mw * 0.62
          for _, f in ipairs({ { 0, -1 }, { 0, 1 }, { 1, 0 }, { -1, 0 } }) do
            local off = (f[2] ~= 0) and V(0, mh * 0.42, f[2] * (mw * 0.6 + 0.12)) or V(f[1] * (mw / 2 + 0.12), mh * 0.42, 0)
            local sz = (f[2] ~= 0) and V(ps, ps, 0.24) or V(0.24, ps, ps)
            mk(M, "Part", sz, CF(mast + off), panelC, MAT.SmoothPlastic)
          end
        end
      else
        mk(M, "Part", V(mw, mh * 0.55, mw), CF(mast + V(0, mh * 0.275, 0)), supCol, MAT.Metal)
        mk(M, "Part", V(0.5, mh * 0.45, 0.5), CF(mast + V(0, mh * 0.55 + mh * 0.225, 0)), RGB(60, 62, 64), MAT.Metal)
        mk(M, "Part", V(mw * 1.8, 0.35, 0.35), CF(mast + V(0, mh * 0.82, 0)), RGB(60, 62, 64), MAT.Metal)   -- 横桁
        local s2 = L.sup and L.sup[2]
        if L.panel and s2 then   -- 舰桥四角斜着的四块（SPY 雷达）
          local za, zb, w, h, y = s2[1], s2[2], s2[3], s2[4], s2[5]
          local ps = math.min(h * 0.8, w * 0.5)
          for _, c in ipairs({ { -1, za, 1 }, { 1, za, 1 }, { -1, zb, -1 }, { 1, zb, -1 } }) do
            local pc = CF(c[1] * w * 0.32, y + h * 0.5, c[2] + c[3] * 0.6) * CFrame.Angles(0, c[1] * c[3] * math.rad(-40), 0)
            mk(M, "Part", V(ps, ps, 0.3), pc, panelC, MAT.SmoothPlastic)
          end
        end
      end
      mastTop = mast + V(0, mh + 0.8, 0)
      mk(M, "Part", V(0.4, 3, 0.4), CF(mastTop + V(0, 0.7, 0)), RGB(60, 62, 64), MAT.Metal)
      TAG = "flag"
      local flag = mk(M, "Part", V(0.08, 1.6, 2.6), CF(mastTop + V(0, 0.4, 1.4)), TEAMC[team] or RGB(200, 200, 200), MAT.Fabric)
      TAG = nil
      flag.CastShadow = false
      M.flag = flag
    end
    -- 烟囱：方的烟囱、顶上一圈黑
    local fl = L.funnel or {}
    M.funnels = {}
    for i = 1, #fl - 1, 2 do
      local p, s = fl[i], fl[i + 1]
      mk(M, "Part", s, CF(p), supCol, MAT.Metal)
      mk(M, "Part", V(s.X * 0.86, 0.5, s.Z * 0.86), CF(p + V(0, s.Y / 2 + 0.2, 0)), RGB(26, 26, 28), MAT.Metal)
      table.insert(M.funnels, p + V(0, s.Y / 2 + 0.6, 0))
    end
    -- 垂发：甲板上一块深灰板，一格一格的缝
    for _, v in ipairs(L.vls or {}) do
      local za, zb = v[1], v[2]
      local w = d.W * 0.5
      local zc, len = (za + zb) / 2, zb - za
      mk(M, "Part", V(w, 0.3, len), CF(0, d.deck + 0.15, zc), RGB(66, 70, 72), MAT.DiamondPlate)
      mk(M, "Part", V(0.15, 0.32, len), CF(0, d.deck + 0.18, zc), RGB(30, 32, 34), MAT.Metal)
      for zz = za + 3.6, zb - 1, 3.6 do mk(M, "Part", V(w, 0.32, 0.15), CF(0, d.deck + 0.18, zz), RGB(30, 32, 34), MAT.Metal) end
    end
    -- 斜置的导弹发射箱：左右两排，箱口朝前上方
    local cn = L.canisters
    if cn then
      for _, s in ipairs({ -1, 1 }) do
        for k2 = 0, (cn.n or 4) / 2 - 1 do
          for r = 0, 1 do
            mk(M, "Part", V(1.5, 1.5, 8), CF(s * (1.2 + k2 * 1.7), cn.y + 1.6 + r * 1.6, cn.z) * CFrame.Angles(math.rad(22), 0, 0), col:Lerp(RGB(0, 0, 0), 0.15), MAT.Metal)
          end
        end
      end
    end
    -- 直升机甲板：两条白边、黄色圆圈、中线
    local hl = L.heli
    if hl then
      local za, zb = hl[1], hl[2]
      local zc, len = (za + zb) / 2, zb - za
      local w = (L.hulls == 3) and d.W * 0.9 or d.W * 0.86
      for _, sx in ipairs({ -1, 1 }) do mk(M, "Part", V(0.4, 0.08, len), CF(sx * w / 2, d.deck + 0.16, zc), RGB(225, 226, 224)) end
      local r = math.min(w * 0.7, len * 0.7)
      mk(M, "Part", V(0.06, r, r), CF(0, d.deck + 0.15, zc) * CFrame.Angles(0, 0, math.pi / 2), RGB(226, 190, 60), MAT.SmoothPlastic, nil, nil, CYL)
      mk(M, "Part", V(0.07, r - 1, r - 1), CF(0, d.deck + 0.155, zc) * CFrame.Angles(0, 0, math.pi / 2), deckCol, MAT.Concrete, nil, nil, CYL)
      mk(M, "Part", V(0.35, 0.08, len * 0.9), CF(0, d.deck + 0.17, zc), RGB(226, 190, 60))
    end
    -- 炮、近防炮
    for gi in ipairs(d.guns or {}) do gun(M, d, gi, supCol) end
    for _, mp in ipairs(d.ciws or {}) do ciws(M, mp, supCol) end
    -- 舷号：船头两侧
    if not L.open then hullNumber(M, d, L.num, z0 + bowL + math.max(4, d.deck * 0.9), d.deck * 0.55 + 0.4, math.max(1.6, d.deck * 0.5)) end
    -- 航行灯：桅顶白灯、舰桥两侧左红右绿、船尾白灯
    local s2 = L.sup and L.sup[2]
    if mastTop then lamp(M, CF(mastTop + V(0, 2.4, 0)), RGB(255, 250, 236), 0.5, 10) end
    if s2 then
      lamp(M, CF(-(s2[3] / 2 + 2.6), s2[5] + s2[4] * 0.62 + 0.6, s2[1] + 3), RGB(255, 50, 40), 0.45, 8)
      lamp(M, CF(s2[3] / 2 + 2.6, s2[5] + s2[4] * 0.62 + 0.6, s2[1] + 3), RGB(60, 255, 120), 0.45, 8)
    elseif L.open then
      lamp(M, CF(-d.W * 0.36, d.deck + 1.7, -0.9), RGB(255, 50, 40), 0.25, 5)
      lamp(M, CF(d.W * 0.36, d.deck + 1.7, -0.9), RGB(60, 255, 120), 0.25, 5)
      lamp(M, CF(0, d.deck + 4.9, 1.5), RGB(255, 250, 236), 0.25, 6)
    end
    lamp(M, CF(0, d.deck + 1, z1 + 0.3), RGB(255, 250, 236), L.open and 0.25 or 0.45, 8)
    -- 粒子：船头浪花（左右）、尾迹、烟囱排烟、挨打着火冒黑烟
    local k = math.clamp(d.W / 20, 0.3, 2.4)
    M.spray = {}
    for _, s in ipairs({ -1, 1 }) do
      table.insert(M.spray, emitter(M, CF(s * d.W * 0.3, 0.4, z0 + bowL * 0.55) * CFrame.Angles(0, 0, 0), {
        EmissionDirection = (s > 0) and Enum.NormalId.Right or Enum.NormalId.Left, Speed = NumberRange.new(4 * k, 10 * k), SpreadAngle = Vector2.new(25, 35),
        Lifetime = NumberRange.new(0.8, 1.6), Size = seq(1.5 * k, 5 * k), Transparency = seq(0.25, 1), Color = ColorSequence.new(RGB(238, 244, 246)),
        Acceleration = V(0, -18, 0), Drag = 1.5, LightInfluence = 0.6 }))
    end
    M.wake = emitter(M, CF(0, 0.3, z1 + 1), {
      EmissionDirection = Enum.NormalId.Back, Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(20, 5), Lifetime = NumberRange.new(5, 8),
      Size = seq(d.W * 0.5, d.W * 1.6), Transparency = seq(0.35, 1), Color = ColorSequence.new(RGB(232, 240, 242)), Drag = 0.6, LightInfluence = 0.6 })
    M.smoke = {}
    for _, fp in ipairs(M.funnels) do
      table.insert(M.smoke, emitter(M, CF(fp), {
        EmissionDirection = Enum.NormalId.Top, Speed = NumberRange.new(4, 8), SpreadAngle = Vector2.new(8, 8), Lifetime = NumberRange.new(3, 5),
        Size = seq(3 * k, 12 * k), Transparency = seq(0.55, 1), Color = ColorSequence.new(RGB(70, 70, 72)), Acceleration = V(0, 1, 0), LightInfluence = 0.7 }))
    end
    local s1 = L.sup and L.sup[1]
    local fireAt = s1 and V(0, s1[5] + s1[4], (s1[1] + s1[2]) / 2) or V(0, d.deck + 1, 0)
    M.fire = emitter(M, CF(fireAt), {
      EmissionDirection = Enum.NormalId.Top, Speed = NumberRange.new(4, 9), SpreadAngle = Vector2.new(30, 30), Lifetime = NumberRange.new(0.6, 1.2),
      Size = seq(3 * k, 1 * k), Transparency = seq(0.1, 1), Color = ColorSequence.new(RGB(255, 170, 60), RGB(255, 80, 30)), LightEmission = 1 })
    M.black = emitter(M, CF(fireAt + V(0, 2, 0)), {
      EmissionDirection = Enum.NormalId.Top, Speed = NumberRange.new(6, 12), SpreadAngle = Vector2.new(15, 15), Lifetime = NumberRange.new(4, 7),
      Size = seq(4 * k, 18 * k), Transparency = seq(0.25, 1), Color = ColorSequence.new(RGB(30, 28, 26)), Acceleration = V(0, 2, 0), LightInfluence = 0.5 })
    M.fireLight = Instance.new("PointLight")
    M.fireLight.Color, M.fireLight.Range, M.fireLight.Brightness, M.fireLight.Enabled = RGB(255, 140, 60), 40, 3, false
    M.fireLight.Parent = M.fire.Parent
    local info, folder = importedFor(d)
    if info then
      -- 蒙皮换成原模型：零件拼的只留灯、粒子、舰旗（主炮也不要：原模型上的炮跟着转；挑不出来的那门就不转）
      local n = 0
      for i = 1, #M.items do
        local it = M.items[i]
        if it.tag == "lamp" or it.tag == "fx" or it.tag == "flag" then
          n += 1
          M.items[n] = it
        else
          it.p:Destroy()
        end
      end
      for i = #M.items, n + 1, -1 do M.items[i] = nil end
      for name, p in pairs(info.parts) do
        local src = folder:FindFirstChild("S_" .. d.id .. "__" .. name)
        if src and src:IsA("BasePart") then
          local mp = Tint.fix(src:Clone(), src)
          mp.Anchored, mp.CanCollide, mp.CanQuery, mp.CanTouch = true, false, false, false
          mp.Size = V(p.s[1], p.s[2], p.s[3])
          local okT, tid = pcall(function() return mp.TextureID end)   -- 不是 MeshPart 的没有这个属性
          if p.col and not mp:FindFirstChildOfClass("SurfaceAppearance") and (not okT or (tid or "") == "") then
            mp.Color = RGB(p.col[1], p.col[2], p.col[3])   -- 原模型这块本来就没贴图：照原材质颜色（Studio 导入不一定带过来）
            if p.a then mp.Transparency = 1 - p.a end
          end
          mp.Parent = M.model
          local c = CF(p.c[1], p.c[2], p.c[3]) * TURN
          local gi = tonumber(string.match(p.g, "^T(%d+)$"))
          local gd = gi and info.guns and info.guns[gi]
          if gd then   -- 主炮：绕原模型的炮塔转轴转
            local piv = CF(gd.piv[1], gd.piv[2], gd.piv[3])
            table.insert(M.items, { p = mp, g = "ti", i = gi, piv = piv, off = piv:Inverse() * c })
          else
            table.insert(M.items, { p = mp, g = "hull", off = c })
          end
        end
      end
      -- 航行灯、舰旗挪到原模型上：最高的白灯 → 桅顶，左红右绿 → 舰桥两侧贴着原模型的外侧，最靠后的白灯 → 船尾甲板
      local top = info.top and V(info.top[1], info.top[2], info.top[3])
      local whites, mast, stern = {}, nil, nil
      for _, it in ipairs(M.items) do
        if it.tag == "lamp" then
          local c = it.p.Color
          if c.R > 0.9 and c.G > 0.9 then table.insert(whites, it)
          elseif info.side then
            local sx = (c.R > c.G) and -1 or 1   -- 红灯在左舷
            it.off = CF(sx * (info.side[1] + 0.4), info.side[2], info.side[3])
          end
        end
      end
      for _, it in ipairs(whites) do if not mast or it.off.Position.Y > mast.off.Position.Y then mast = it end end
      for _, it in ipairs(whites) do if it ~= mast and (not stern or it.off.Position.Z > stern.off.Position.Z) then stern = it end end
      if top and mast then mast.off = CF(top + V(0, 1.2, 0)) end
      if info.stern and stern then stern.off = CF(info.stern[1], info.stern[2] + 0.8, info.stern[3] + 0.3) end
      if top and M.flag then
        for _, it in ipairs(M.items) do
          if it.p == M.flag then it.off = CF(top + V(0, -1.6, 1.4)) end
        end
      end
      M.imported = d.id
    end
    return M
  end
  G.buildShipModel = build

  ---------------------------------------------------------------- 每帧

  local function angDiff(a, b) return (b - a + 180) % 360 - 180 end

  local function viewBuild(v, em, team)
    local d = SD.get(em:GetAttribute("Model") or "")
    if not d then return false end
    local M = build(d, team)
    v.M, v.d, v.model = M, d, M.model
    local anchor = Instance.new("Part")   -- 血条挂的点（桅杆上方）
    anchor.Size, anchor.Transparency, anchor.Anchored = V(0.2, 0.2, 0.2), 1, true
    anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = false, false, false
    anchor.Parent = M.model
    v.anchor = anchor
    -- 上船提示：船尾甲板上（码头在船尾或船边）
    local board = Instance.new("Part")
    board.Size, board.Transparency, board.Anchored = V(0.2, 0.2, 0.2), 1, true
    board.CanCollide, board.CanQuery, board.CanTouch = false, false, false
    board.Parent = M.model
    local pr = Instance.new("ProximityPrompt")
    pr.ActionText = T("ui.boardShip")
    pr.ObjectText = T("veh." .. d.id)
    pr.KeyboardKeyCode = Enum.KeyCode.E
    pr.HoldDuration = 0
    pr.MaxActivationDistance = d.W / 2 + 26
    pr.RequiresLineOfSight = false
    pr.Enabled = false
    pr.Parent = board
    pr.Triggered:Connect(function() G.R.Act:FireServer("enterVeh", v.id) end)
    v.board, v.prompt = board, pr
    v.plist, v.clist = {}, {}
    for i, it in ipairs(M.items) do v.plist[i] = it.p end
    v.base = v.root.CFrame * CF(0, -(d.H / 2 - d.draft), 0)
    v.ty, v.gp, v.rec = {}, {}, {}
    for gi in ipairs(d.guns) do v.ty[gi], v.gp[gi], v.rec[gi] = em:GetAttribute("Ty" .. gi) or 0, em:GetAttribute("Gp" .. gi) or 0, 0 end
    v.phase = math.random() * 6
    v.lastYaw = 0
    v.yawRate = 0
    v.frame = 0
    v.promptT = 0
    return true
  end

  local function viewStep(v, dt, camPos)
    local em, d, M = v.em, v.d, v.M
    local own = G.sail and G.sail.em == em and G.sail or nil
    -- 位置：自己开的用本地的；别人的快照插值（View.lua G.follow：匀速，不一顿一顿；跳太远直接过去）
    local target = v.root.CFrame * CF(0, -(d.H / 2 - d.draft), 0)
    if own and own.cf then v.base = own.cf
    else v.base = G.follow(v, target, 160) end
    local pos = v.base.Position
    local far = (pos - camPos).Magnitude
    v.frame += 1
    v.dtAcc = (v.dtAcc or 0) + dt
    if far > 2600 and v.frame % 4 ~= 0 then return end   -- 很远：四帧挪一次（这几帧的时间攒着一起算：下沉、浪的计时不变慢）
    dt = v.dtAcc
    v.dtAcc = 0
    local t = os.clock()
    local wreck = em:GetAttribute("Wreck") == true
    -- 速度、转向（转弯时外倾）
    local spd = own and own.speed or (em:GetAttribute("Sp") or 0)
    local _, yaw = v.base:ToEulerAnglesYXZ()
    local yr = angDiff(math.deg(v.lastYaw), math.deg(yaw)) / math.max(dt, 1e-3)
    v.lastYaw = yaw
    v.yawRate = v.yawRate + (yr - v.yawRate) * math.min(1, dt * 3)
    local frac = math.clamp(math.abs(spd) / math.max(1, d.speed), 0, 1)
    local k = math.clamp(60 / d.L, 0.12, 1.6)
    local ph = v.phase
    local bob = math.sin(t * 0.8 + ph) * 0.35 * k
    local pitch = math.sin(t * 0.6 + ph * 1.3) * 0.012 * k + frac * 0.01 * math.clamp(k, 0.3, 1)
    local roll = math.sin(t * 0.5 + ph * 0.7) * 0.025 * k + math.clamp(v.yawRate * math.abs(spd) * 0.00025, -0.09, 0.09)
    local cf = v.base * CF(0, bob, 0) * CFrame.Angles(pitch, 0, roll)
    -- 击沉：慢慢倾覆、下沉（20 多秒）
    if wreck then
      v.sinkT = (v.sinkT or 0) + dt
      local st = v.sinkT
      v.sinkDir = v.sinkDir or ((math.random() < 0.5) and -1 or 1)
      cf = v.base * CF(0, -math.min(st * 0.9, d.H * 0.95), 0) * CFrame.Angles(math.min(st * 0.012, 0.22), 0, v.sinkDir * math.min(st * 0.025, 0.55))
    end
    -- 炮塔、炮
    for gi in ipairs(d.guns) do
      local ty, gp
      if own and own.ty then ty, gp = own.ty[gi] or 0, own.gp[gi] or 0 else
        ty = v.ty[gi] + angDiff(v.ty[gi], em:GetAttribute("Ty" .. gi) or 0) * math.min(1, dt * 8)
        gp = v.gp[gi] + ((em:GetAttribute("Gp" .. gi) or 0) - v.gp[gi]) * math.min(1, dt * 8)
      end
      v.ty[gi], v.gp[gi] = ty, gp
      v.rec[gi] = math.max(0, v.rec[gi] - dt * 3)
    end
    local tcf, gcf = {}, {}
    for gi in ipairs(d.guns) do
      tcf[gi] = SD.turretCF(d, cf, gi, v.ty[gi])
      gcf[gi] = SD.gunCF(d, cf, gi, v.ty[gi], v.gp[gi]) * CF(0, 0, v.rec[gi])
    end
    local plist, clist = v.plist, v.clist
    for i, it in ipairs(M.items) do
      if it.g == "t" then clist[i] = tcf[it.i] * it.off
      elseif it.g == "g" then clist[i] = gcf[it.i] * it.off
      elseif it.g == "ti" then clist[i] = cf * it.piv * CFrame.Angles(0, -math.rad(v.ty[it.i] or 0), 0) * it.off   -- 原模型的主炮（船尾的炮原模型里本来就朝后）
      else clist[i] = cf * it.off end
    end
    workspace:BulkMoveTo(plist, clist, Enum.BulkMoveMode.FireCFrameChanged)
    v.anchor.CFrame = cf * CF(0, d.H - d.draft + 4, 0)
    v.board.CFrame = cf * CF(0, d.deck + 2, d.L / 2 - math.min(10, d.L * 0.2))
    if v.bb and not v.bbSet then v.bbSet = true v.bb.MaxDistance = 1800 v.bb.Size = UDim2.fromOffset(70, 7) end
    -- 粒子：近处才算；浪花、尾迹跟速度，烟囱有人开 / 走起来冒烟；血少于四成着火冒黑烟
    if far < 2200 then
      local moving = not wreck and frac > 0.04
      for _, pe in ipairs(M.spray) do pe.Rate = moving and (frac * 40) or 0 end
      M.wake.Rate = moving and (2 + frac * 10) or 0
      local lit = (em:GetAttribute("Driver") or 0) ~= 0 or em:GetAttribute("AI") == true
      for _, pe in ipairs(M.smoke) do pe.Rate = wreck and 0 or ((lit and 1.5 or 0) + frac * 6) end
      local hp, mx = em:GetAttribute("Hp") or 1, em:GetAttribute("MaxHp") or 1
      local burning = wreck or hp < mx * 0.4
      M.fire.Rate = burning and (wreck and 40 or 18) or 0
      M.black.Rate = burning and (wreck and 14 or 6) or 0
      M.fireLight.Enabled = burning
      if burning then M.fireLight.Brightness = 2.2 + math.random() * 1.6 end
    end
    if M.flag then M.flag.CFrame = M.flag.CFrame * CFrame.Angles(0, math.sin(t * 6 + ph) * 0.04, 0) end
    if wreck and not v.darkened then   -- 沉船：灯灭、颜色发黑
      v.darkened = true
      for _, it in ipairs(M.items) do
        local p = it.p
        if p.Material == MAT.Neon then p.Transparency = 1 end
        for _, c in ipairs(p:GetChildren()) do
          if c:IsA("BillboardGui") or (c:IsA("PointLight") and c ~= M.fireLight) then c.Enabled = false end
        end
        if p:IsA("MeshPart") then   -- 原模型：贴图盖住颜色，烧黑要先把贴图去掉
          for _, sa in ipairs(p:GetChildren()) do if sa:IsA("SurfaceAppearance") then sa:Destroy() end end
          pcall(function() p.TextureID = "" end)
          if p.Transparency < 1 then p.Color = RGB(34, 33, 32) end
        elseif p.Transparency < 1 then p.Color = p.Color:Lerp(RGB(18, 18, 18), 0.5) end
      end
    end
    -- 上船提示：自己队的、没人开、不是 AI、没沉；自己活着、没在开别的
    v.promptT -= dt
    if v.promptT <= 0 then
      v.promptT = 0.25
      local ch = me.Character
      local hum = ch and ch:FindFirstChildOfClass("Humanoid")
      local ok = hum and hum.Health > 0 and not G.drive and G.S and G.S.alive and not G.S.veh
      v.prompt.Enabled = (ok and em:GetAttribute("Team") == me:GetAttribute("Side") and (em:GetAttribute("Driver") or 0) == 0
        and not em:GetAttribute("AI") and not wreck) and true or false
    end
  end

  local function viewRecoil(v, g)
    local gi = g or 1
    if v.rec and v.d and v.d.guns[gi] then v.rec[gi] = math.min(1.6, v.d.guns[gi].len * 0.11) end
  end

  G.viewKind = G.viewKind or {}
  G.viewKind.ship = { build = viewBuild, step = viewStep, recoil = viewRecoil, remove = function() end,
    importReady = function(v) return v.M ~= nil and not v.M.imported and v.d ~= nil and importedFor(v.d) ~= nil end }   -- 原模型后来才复制齐：View 重建
end

return ShipView
