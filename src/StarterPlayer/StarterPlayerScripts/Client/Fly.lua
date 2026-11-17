-- Roblox全面大战场（客户端）——飞机、直升机：样子和驾驶
--   样子（G.viewKind.air，View.lua 每帧调）：AirModels 按型号拼零件；位置平滑跟着服务器的 Root，舵面、起落架、弹舱、座舱盖、旋翼按实体属性
--     （Thr、Gear、Pit、Rol、Yaw、Bay、BayS、Rpm、Ty、Gp……）摆；自己开的用本地的；被击毁的往下掉、冒火冒黑烟，落地炸一下
--   驾驶（服务器推来的 S.veh.air）：位置在本地算，每秒 15 次报给服务器（Air.lua 查速度、查撞地）
--     固定翼（用户：准星控制方向手感一般，改成键盘）：S 拉杆抬头、W 推杆低头（↓ / ↑ 同样）、A / D 滚转、Q / E 方向舵、Shift / Ctrl 油门（推满再推进加力）；
--       松开 A / D 自动把机翼摆平（坡度不大、没倒飞时），压着坡度不拉杆也自动带一点杆保持高度（只按 A / D 就能转弯）；鼠标只转镜头看四周，松开一会儿镜头回到机尾；
--       速度不够失速（机头往下掉）、爬升掉速、俯冲加速、拉杆转弯掉能量；跑道 / 甲板上：油门加速，速度够了按 S 抬头离地；
--       放着起落架、下沉不快、速度不快、姿态平就能落地（落在自己的机场 / 甲板上停 5 秒补弹修理）
--     直升机：W / S 前后、A / D 转向（快的时候压坡度转弯）、Q 升 / E 降，旋翼先转起来才飞得动；鼠标转镜头、机头炮塔跟着镜头瞄
--     武器：鼠标左键 机炮（直升机机头炮塔跟着鼠标瞄）；F 发导弹 / 火箭 / 炸弹（1～6 选用哪种；导弹、制导炸弹要锁定：目标在导引头视场里待够锁定时间），
--       R 换目标；X 热诱弹；G 起落架；空格 下飞机（在天上跳伞）
--     平显：速度、高度、油门、准星（机头指向）、鼠标瞄准圈、锁定框、炸弹落点、失速 / 拉起 / 导弹来袭 / 飞出作战区警告
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local Fly = {}

function Fly.init(G)
  local Map = require(RS:WaitForChild("Map"))
  local AD = require(RS:WaitForChild("AirDefs"))
  local AM = require(script.Parent:WaitForChild("AirModels"))
  local V = Vector3.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local rad, deg = math.rad, math.deg
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local GR = AD.GRAV
  local function T(k, ...) return G.T(k, ...) end
  local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
  local function approach(a, b, s)
    if a < b then return math.min(b, a + s) end
    return math.max(b, a - s)
  end
  local function angDiff(a, b) return (b - a + math.pi) % (2 * math.pi) - math.pi end
  local function smooth(a, b, v) local t = clamp((v - a) / (b - a), 0, 1) return t * t * (3 - 2 * t) end
  local function ground(x, z) return AD.ground(Map, x, z) end

  local st = nil   -- 正在开 / 坐的飞机
  G.fly = nil
  G.AD = AD

  ---------------------------------------------------------------- 样子

  -- 挂载属性 "pl15,pl15,,kd88" → { "pl15", "pl15", false, "kd88" }
  local function parseLoad(s, d)
    local out = {}
    local i = 0
    for w in string.gmatch((s or "") .. ",", "([^,]*),") do
      i += 1
      out[i] = (w ~= "") and w or false
    end
    for k = 1, #(d.st or {}) do if out[k] == nil then out[k] = false end end
    return out
  end

  local CH = { thr = "Thr", gear = "Gear", flap = "Flap", pit = "Pit", rol = "Rol", yaw = "Yaw", bay = "Bay", bayS = "BayS", rpm = "Rpm", col = "Col", can = "Can",
    hook = "Hook", brk = "Brk", ty = "Ty", gp = "Gp", fold = "Fold" }

  G.viewKind = G.viewKind or {}
  G.viewKind.air = {
    importReady = function(v) return v.M ~= nil and not v.M.imported and v.def ~= nil and AM.importedFor(v.def) ~= nil end,   -- 原模型后来才复制齐：View 重建
    build = function(v, em, team)
      local d = AD.get(em:GetAttribute("Model") or "")
      if not d then return false end
      local M = AM.build(d, team, parseLoad(em:GetAttribute("Load"), d))
      v.M, v.def, v.model, v.anchor = M, d, M.model, M.anchor
      v.c = {}
      v.spin1, v.spin2, v.spinT, v.spinP = math.random() * 6, math.random() * 6, 0, 0
      v.prevT, v.vel = v.root.CFrame, V()
      v.frame = 0
      return true
    end,
    step = function(v, dt, camPos)
      local em, d, M = v.em, v.def, v.M
      local own = st and st.em == em and st
      local target = v.root.CFrame
      -- 别人的飞机：按服务器位置的变化估速度（被击毁时接着往下掉要用）
      if target ~= v.prevT then
        local dp = target.Position - v.prevT.Position
        if dp.Magnitude < 400 then v.vel = v.vel:Lerp(dp / math.max(dt, 1 / 60), 0.5) end
        v.prevT = target
      end
      if em:GetAttribute("Wreck") then   -- 被击毁：带着速度往下掉、翻滚、冒烟，落地炸一下
        if not v.wreck then
          v.wreck = { vel = (own and own.vel) or v.vel, spin = (math.random() - 0.5) * 3, t = 0 }
          if v.M then v.M.dark = true end   -- 被击毁：灯全灭
          for _, it in ipairs(M.items) do
            local p = it.p
            if p:IsA("MeshPart") then   -- 原模型：贴图盖住颜色，烧黑要先把贴图去掉
              for _, sa in ipairs(p:GetChildren()) do if sa:IsA("SurfaceAppearance") then sa:Destroy() end end
              pcall(function() p.TextureID = "" end)
              if p.Transparency < 1 then p.Color = Color3.fromRGB(40, 38, 36) end
            elseif p:IsA("BasePart") and p.Transparency < 1 then p.Color = p.Color:Lerp(Color3.new(0.05, 0.05, 0.05), 0.6) end
          end
        end
        local W = v.wreck
        W.t += dt
        if not W.down then
          W.vel += V(0, -GR, 0) * dt
          W.vel *= (1 - 0.1 * dt)
          local p = v.cf.Position + W.vel * dt
          local g = ground(p.X, p.Z)
          if p.Y < g + 1 then
            W.down = true
            p = V(p.X, g + 1, p.Z)
            if G.boom then G.boom(p, 2, "wreck") end
          end
          local look = (W.vel.Magnitude > 5) and W.vel.Unit or v.cf.LookVector
          v.cf = CFrame.lookAt(p, p + look) * CFrame.Angles(0, 0, W.t * W.spin)
          W.smokeT = (W.smokeT or 0) - dt
          if W.smokeT <= 0 and G.fxPart then
            W.smokeT = 0.06
            local s = G.fxPart(Enum.PartType.Ball, V(4, 4, 4), CFrame.new(p), RGB(40, 38, 36), Enum.Material.SmoothPlastic, 0.3)
            if G.tween then G.tween(s, 2.4, { Size = V(16, 16, 16), Transparency = 1 }) end
            game:GetService("Debris"):AddItem(s, 2.5)
            local f = G.fxPart(Enum.PartType.Ball, V(3, 3, 3), CFrame.new(p), RGB(255, 140, 40), Enum.Material.Neon, 0.1)
            if G.tween then G.tween(f, 0.4, { Size = V(6, 6, 6), Transparency = 1 }) end
            game:GetService("Debris"):AddItem(f, 0.45)
          end
        end
      elseif own then
        v.cf = own.cf
      elseif (target.Position - v.cf.Position).Magnitude > 220 then
        v.cf = target
      else
        v.cf = v.cf:Lerp(target, math.min(1, dt * 11))
      end
      -- 通道：自己开的用本地的操纵量；别人的读属性
      local c = v.c
      if own then
        for k in pairs(CH) do c[k] = own.c[k] or 0 end
      else
        for k, a in pairs(CH) do c[k] = em:GetAttribute(a) or 0 end
        if em:GetAttribute("BayS") == nil then c.bayS = c.bay end
      end
      v.canS = approach(v.canS or c.can, c.can, dt * 0.7)   -- 座舱盖开关是 0 / 1：显示时一秒多一点慢慢掀开、合上
      c.can = v.canS
      local onGround = c.gear > 0.9 and (v.cf.Position.Y - ground(v.cf.Position.X, v.cf.Position.Z) - d.gearH) < 1.5
      c.door = (d.sideDoor and onGround) and 1 or 0
      c.ramp = (d.ramp and onGround) and 1 or 0
      -- 旋翼、螺旋桨转（看着慢一点，免得一格一格跳）
      local rpm = c.rpm or 0
      if d.rotor then v.spin1 = (v.spin1 + rpm / 100 * d.rotor.rpm / 60 * math.pi * 2 * 0.3 * dt) % (math.pi * 2) end
      if d.rotor2 then v.spin2 = (v.spin2 + rpm / 100 * d.rotor2.rpm / 60 * math.pi * 2 * 0.3 * dt) % (math.pi * 2) end
      if d.tail then v.spinT = (v.spinT + rpm / 100 * 18 * dt) % (math.pi * 2) end
      if d.prop then v.spinP = (v.spinP + (c.thr or 0) / 100 * 30 * dt) % (math.pi * 2) end
      c.spin1, c.spin2, c.spinT, c.spinP = v.spin1, v.spin2, v.spinT, v.spinP
      AM.setStores(M, em:GetAttribute("Stores"))
      -- 远的少摆几次（一架几百个零件）
      v.frame += 1
      local dist = (v.cf.Position - camPos).Magnitude
      local every = (own or dist < 1500) and 1 or ((dist < 4000) and 2 or 4)
      if v.frame % every == 0 then AM.pose(M, v.cf, c, os.clock()) end
    end,
  }

  ---------------------------------------------------------------- 平显

  local ui = G.ui
  local gui = Instance.new("ScreenGui")
  gui.Name = "Fly"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 5
  gui.Parent = me:WaitForChild("PlayerGui")
  local HUD = RGB(120, 255, 150)
  local function hud(text, size, pos, ts, anchor, align)
    local l = ui.label(gui, text, size, pos, ts or 16, HUD, Enum.Font.Code, anchor, align)
    l.TextStrokeTransparency = 0.5
    l.TextStrokeColor3 = RGB(0, 30, 10)
    l.Visible = false
    return l
  end
  local panel = ui.frame(gui, UDim2.fromOffset(460, 86), UDim2.new(0.5, 0, 1, -24), RGB(12, 16, 20), 0.35, Vector2.new(0.5, 1))   -- 操作说明在屏幕最下面一行（UI.lua，st.help）
  panel.Visible = false
  local aName = ui.label(panel, "", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 6), 16, Color3.new(1, 1, 1), Enum.Font.GothamBold, nil, Enum.TextXAlignment.Left)
  local hpBg = ui.frame(panel, UDim2.new(1, -20, 0, 8), UDim2.fromOffset(10, 30), RGB(0, 0, 0), 0.4)
  local hpBar = ui.frame(hpBg, UDim2.fromScale(1, 1), nil, RGB(90, 210, 110), 0)
  local aInfo = ui.label(panel, "", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 44), 14, Color3.new(1, 1, 1), Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left)
  local aWpn = ui.label(panel, "", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 62), 14, RGB(255, 220, 120), Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left)
  ui.flatPanel(panel, { hp = hpBg, name = aName })   -- 跟新界面一个样子（UI.lua）
  local bore = hud("+", UDim2.fromOffset(40, 40), UDim2.fromScale(0.5, 0.5), 34, Vector2.new(0.5, 0.5))   -- 机头指向
  local aimRing = hud("◯", UDim2.fromOffset(36, 36), UDim2.fromScale(0.5, 0.5), 30, Vector2.new(0.5, 0.5))   -- 鼠标想去的方向
  aimRing.TextColor3 = Color3.new(1, 1, 1)
  local lockBox = ui.frame(gui, UDim2.fromOffset(46, 46), UDim2.new(), HUD, 1, Vector2.new(0.5, 0.5))
  lockBox.Visible = false
  local lockStroke = ui.stroke(lockBox, HUD, 2, 0)
  local lockText = hud("", UDim2.fromOffset(160, 18), UDim2.new(), 14, Vector2.new(0.5, 0))
  local pipper = hud("◎", UDim2.fromOffset(30, 30), UDim2.new(), 26, Vector2.new(0.5, 0.5))   -- 炸弹落点
  pipper.TextColor3 = RGB(255, 200, 80)
  local spdText = hud("", UDim2.fromOffset(140, 26), UDim2.new(0.5, -230, 0.5, 0), 20, Vector2.new(1, 0.5), Enum.TextXAlignment.Right)
  local altText = hud("", UDim2.fromOffset(140, 26), UDim2.new(0.5, 230, 0.5, 0), 20, Vector2.new(0, 0.5), Enum.TextXAlignment.Left)
  local thrText = hud("", UDim2.fromOffset(140, 18), UDim2.new(0.5, -230, 0.5, 26), 14, Vector2.new(1, 0.5), Enum.TextXAlignment.Right)
  local vsText = hud("", UDim2.fromOffset(140, 18), UDim2.new(0.5, 230, 0.5, 26), 14, Vector2.new(0, 0.5), Enum.TextXAlignment.Left)
  local fuelText = hud("", UDim2.fromOffset(200, 18), UDim2.new(0.5, -230, 0.5, 46), 14, Vector2.new(1, 0.5), Enum.TextXAlignment.Right)   -- 油量、按现在的油门还能飞多久
  local warnText = hud("", UDim2.fromOffset(520, 34), UDim2.new(0.5, 0, 0.5, -130), 26, Vector2.new(0.5, 0.5))
  warnText.TextColor3 = RGB(255, 80, 70)
  local landMark = hud("◇", UDim2.fromOffset(34, 34), UDim2.new(), 30, Vector2.new(0.5, 0.5))   -- 降落点
  landMark.TextColor3 = RGB(120, 200, 255)
  local landText = hud("", UDim2.fromOffset(260, 18), UDim2.new(), 14, Vector2.new(0.5, 0))
  landText.TextColor3 = RGB(120, 200, 255)
  -- 用户发的截图那样：速度、高度各在一个绿框里（左、右），顶上航向；中间一个大圈（选中武器能锁的范围：导弹导引头的离轴角、
  --   航炮 / 火箭 / 炸弹的瞄准圈），圈底下写着武器和射程
  local function box(w, h, pos, anchor)
    local f = ui.frame(gui, UDim2.fromOffset(w, h), pos, RGB(0, 24, 10), 0.72, anchor)
    ui.stroke(f, HUD, 2, 0.1)
    f.Visible = false
    return f
  end
  local spdBox = box(120, 46, UDim2.new(0.5, -300, 0.5, 0), Vector2.new(1, 0.5))
  local altBox = box(120, 46, UDim2.new(0.5, 300, 0.5, 0), Vector2.new(0, 0.5))
  local hdgBox = box(74, 30, UDim2.new(0.5, 0, 0, 104), Vector2.new(0.5, 0.5))
  spdBox.Name, altBox.Name, hdgBox.Name = "SpdBox", "AltBox", "HdgBox"
  for _, it in ipairs({ { spdText, spdBox }, { altText, altBox } }) do
    local l = it[1]
    l.Parent, l.Size, l.Position, l.AnchorPoint = it[2], UDim2.new(1, -8, 1, 0), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5)
    l.TextSize, l.TextXAlignment, l.Visible = 30, Enum.TextXAlignment.Center, true
  end
  local hdgText = ui.label(hdgBox, "", UDim2.fromScale(1, 1), nil, 18, HUD, Enum.Font.Code)
  local spdCap = hud(T("hud.spd"), UDim2.fromOffset(120, 16), UDim2.new(0.5, -420, 0.5, -34), 13, Vector2.new(0, 0.5), Enum.TextXAlignment.Left)
  local altCap = hud(T("hud.alt"), UDim2.fromOffset(120, 16), UDim2.new(0.5, 300, 0.5, -34), 13, Vector2.new(0, 0.5), Enum.TextXAlignment.Left)
  thrText.Position, vsText.Position, fuelText.Position = UDim2.new(0.5, -300, 0.5, 36), UDim2.new(0.5, 300, 0.5, 36), UDim2.new(0.5, -300, 0.5, 56)
  thrText.AnchorPoint, vsText.AnchorPoint, fuelText.AnchorPoint = Vector2.new(1, 0), Vector2.new(0, 0), Vector2.new(1, 0)
  local ring = ui.frame(gui, UDim2.fromOffset(300, 300), UDim2.fromScale(0.5, 0.5), HUD, 1, Vector2.new(0.5, 0.5))
  ring.Name = "HudRing"
  ui.round(ring, 2000)
  ui.stroke(ring, HUD, 2, 0.15)
  ring.Visible = false
  for _, a in ipairs({ { 0.5, 0, 2, 14 }, { 0.5, 1, 2, 14 }, { 0, 0.5, 14, 2 }, { 1, 0.5, 14, 2 } }) do   -- 上下左右四个刻度
    ui.frame(ring, UDim2.fromOffset(a[3], a[4]), UDim2.fromScale(a[1], a[2]), HUD, 0.1, Vector2.new(0.5, 0.5))
  end
  local ringText = hud("", UDim2.fromOffset(240, 18), UDim2.new(), 14, Vector2.new(0.5, 0))
  ringText.Name = "RingText"

  -- 右侧竖排武器栏（用户：导弹什么的在侧面显示，按几切换到什么导弹，带导弹的图标和剩余数量）：
  --   每行 [按键] 图标 名字 ×剩几发，选中的那行亮；打光了变灰；最下面一行热诱弹（X）
  local wList = ui.frame(gui, UDim2.fromOffset(260, 10), UDim2.new(1, -18, 0.5, 0), RGB(0, 0, 0), 1, Vector2.new(1, 0.5))
  wList.Name = "WeaponList"
  wList.Visible = false
  local wRows = {}
  -- 弹的图标：几块小方块拼的（空空弹细长带弹翼、空地弹粗、火箭巢、炸弹、航炮一排炮弹、热诱弹三颗亮点）
  local function drawIcon(ic, it)
    local kind = it.flare and "flare" or (it.w and it.w.kind) or "gun"
    local function r(x, y, sw, sh, rot, rr)
      local f = ui.frame(ic, UDim2.fromOffset(sw, sh), UDim2.fromOffset(x, y), HUD, 0, Vector2.new(0.5, 0.5))
      if rot then f.Rotation = rot end
      if rr then ui.round(f, rr) end
      return f
    end
    if kind == "aam" then
      r(30, 10, 44, 3) r(53, 10, 6, 3, nil, 2)
      r(12, 6, 8, 2, -35) r(12, 14, 8, 2, 35)
      r(31, 7, 6, 2, -30) r(31, 13, 6, 2, 30)
    elseif kind == "agm" then
      r(30, 10, 40, 6) r(51, 10, 6, 6, nil, 3)
      r(12, 5, 9, 3, -40) r(12, 15, 9, 3, 40)
    elseif kind == "rkt" then
      local pod = r(28, 10, 36, 16, nil, 5)
      pod.BackgroundTransparency = 0.55
      for k = -1, 1 do r(43, 10 + k * 4, 3, 3, nil, 2) end
    elseif kind == "bomb" then
      r(30, 10, 30, 9, nil, 5) r(13, 6, 7, 2, -30) r(13, 14, 7, 2, 30)
    elseif kind == "flare" then
      for k = 0, 2 do
        local d = r(16 + k * 14, 10 + ((k == 1) and -3 or 3), 6, 6, nil, 3)
        d.BackgroundColor3 = RGB(255, 232, 150)
      end
    else
      for k = 0, 3 do r(12 + k * 12, 10, 9, 4, nil, 2) end
    end
  end

  -- 光电吊舱的画面（P 键）：四个角的取景框、中间十字、左上模式和倍率、右上目标距离和吊舱指向、底下按键说明
  local eoGui = ui.frame(gui, UDim2.fromScale(1, 1), nil, RGB(0, 0, 0), 1)
  eoGui.Name = "EoView"
  eoGui.Visible = false
  local EOC = RGB(235, 240, 235)
  for _, c in ipairs({ { 0.3, 0.3, 1, 1 }, { 0.7, 0.3, -1, 1 }, { 0.3, 0.7, 1, -1 }, { 0.7, 0.7, -1, -1 } }) do
    ui.frame(eoGui, UDim2.fromOffset(46, 2), UDim2.fromScale(c[1], c[2]), EOC, 0.1, Vector2.new((c[3] > 0) and 0 or 1, 0.5))
    ui.frame(eoGui, UDim2.fromOffset(2, 46), UDim2.fromScale(c[1], c[2]), EOC, 0.1, Vector2.new(0.5, (c[4] > 0) and 0 or 1))
  end
  for _, a in ipairs({ { -30, 0, 36, 2 }, { 30, 0, 36, 2 }, { 0, -30, 2, 36 }, { 0, 30, 2, 36 } }) do
    ui.frame(eoGui, UDim2.fromOffset(a[3], a[4]), UDim2.new(0.5, a[1], 0.5, a[2]), EOC, 0.05, Vector2.new(0.5, 0.5))
  end
  local eoMode = ui.label(eoGui, "", UDim2.fromOffset(360, 24), UDim2.new(0, 28, 0, 90), 18, EOC, Enum.Font.Code, nil, Enum.TextXAlignment.Left)
  local eoInfo = ui.label(eoGui, "", UDim2.fromOffset(360, 24), UDim2.new(1, -300, 0, 90), 16, EOC, Enum.Font.Code, Vector2.new(1, 0), Enum.TextXAlignment.Right)
  local eoHint = ui.label(eoGui, "", UDim2.fromOffset(760, 22), UDim2.new(0.5, 0, 1, -128), 15, EOC, Enum.Font.Gotham, Vector2.new(0.5, 0.5))
  eoMode.Name, eoInfo.Name, eoHint.Name = "EoMode", "EoInfo", "EoHint"
  -- 光电的画面效果：电视（黑白、对比高一点）、热成像白热 / 黑热（所有实体高亮成白 / 黑）
  local eoCC = Instance.new("ColorCorrectionEffect")
  eoCC.Name = "EoCC"
  eoCC.Enabled = false
  eoCC.Parent = game:GetService("Lighting")
  local eoHl = Instance.new("Highlight")
  eoHl.Name = "EoHeat"
  eoHl.Enabled = false
  eoHl.FillTransparency, eoHl.OutlineTransparency = 0.08, 0.6
  eoHl.DepthMode = Enum.HighlightDepthMode.Occluded
  eoHl.Parent = cam
  local EO_MODES = { "tv", "whot", "bhot" }

  local HUDS = { bore, aimRing, spdBox, altBox, hdgBox, spdCap, altCap, thrText, vsText, warnText, fuelText, ring, ringText, wList }

  -- 降落引导：自己这边能落的地方（航母拦阻索区、攻方机场岛、主岛机场——据点 D 在自己手里时），返回 接地点、着陆方向
  local function landSites()
    local out = {}
    local team = me:GetAttribute("Side")
    local function pointMine(id)
      for _, p in ipairs((G.S and G.S.points) or {}) do if p.id == id then return p.owner == team end end
      return false
    end
    local function runway(A)
      for s = -1, 1, 2 do   -- 两头都能落：接地点在跑道头往里 60 格
        local td = V(A.x + s * (A.len / 2 - 60), (A.y or 0), A.z)
        table.insert(out, { p = V(td.X, AD.ground(Map, td.X, td.Z), td.Z), dir = V(-s, 0, 0) })
      end
    end
    if team == "atk" then
      local base = AD.carrierCF(Map)
      if base and st.d.carrier then
        local Wd = AD.WIRES
        local td = (base * CF(Wd.x, 0, (Wd.z0 + Wd.z1) / 2)).Position
        table.insert(out, { p = td, dir = base:VectorToWorldSpace(V(-math.sin(Wd.a), 0, -math.cos(Wd.a))), deck = true })
      end
      runway(Map.AFIELD2)
      if pointMine("D") then runway(Map.AIRFIELD) end
    elseif pointMine("D") then
      runway(Map.AIRFIELD)
    end
    return out
  end

  ---------------------------------------------------------------- 手机：杆、油门 / 升降、开火、换武器、热诱弹、起落架、下飞机

  local touch = nil
  local touchUI = nil
  if UIS.TouchEnabled then
    touch = { up = false, down = false, fire = false }
    local lb = ui.frame(gui, UDim2.fromOffset(90, 170), UDim2.new(0, 20, 1, -320), RGB(0, 0, 0), 1)
    local rb = ui.frame(gui, UDim2.fromOffset(250, 230), UDim2.new(1, -260, 1, -340), RGB(0, 0, 0), 1)
    local function hold(parent, text, size, pos, key)
      local b = ui.button(parent, text, size, pos, RGB(30, 36, 42))
      b.BackgroundTransparency = 0.35
      b.InputBegan:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch then touch[key] = true end end)
      b.InputEnded:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch then touch[key] = false end end)
      return b
    end
    local function tap(parent, text, pos, f)
      local b = ui.button(parent, text, UDim2.fromOffset(60, 60), pos, RGB(30, 36, 42))
      b.BackgroundTransparency = 0.35
      b.TextSize = 14
      b.Activated:Connect(function() if st then f() end end)
      return b
    end
    hold(lb, "▲", UDim2.fromOffset(80, 80), UDim2.fromOffset(5, 0), "up")
    hold(lb, "▼", UDim2.fromOffset(80, 80), UDim2.fromOffset(5, 90), "down")
    hold(rb, "●", UDim2.fromOffset(96, 96), UDim2.fromOffset(150, 130), "fire")
    tap(rb, "1/2", UDim2.fromOffset(80, 150), function() G.flyNextWeapon() end)
    tap(rb, "X", UDim2.fromOffset(150, 60), function() G.R.Drive:FireServer({ op = "flare" }) end)
    tap(rb, "G", UDim2.fromOffset(80, 80), function() if st.d.kind == "jet" and not st.ground then st.gearWant = (st.gearWant > 0.5) and 0 or 1 end end)
    tap(rb, "R", UDim2.fromOffset(10, 150), function() G.flyNextTarget() end)
    tap(rb, "F", UDim2.fromOffset(10, 80), function() G.R.Drive:FireServer({ op = "exit" }) end)
    tap(rb, "J", UDim2.fromOffset(80, 10), function() G.R.Drive:FireServer({ op = "jettison" }) end)
    touchUI = { lb, rb }
    for _, f in ipairs(touchUI) do f.Visible = false end
  end

  ---------------------------------------------------------------- 武器栏、光电吊舱

  local function buildList()
    for _, r in ipairs(wRows) do r.f:Destroy() end
    wRows = {}
    if not st then return end
    local items = {}
    for i, wid in ipairs(st.wl) do items[#items + 1] = { key = tostring(i), wid = wid, w = AD.W[wid], idx = i } end
    items[#items + 1] = { key = "X", flare = true }
    local H = 34
    wList.Size = UDim2.fromOffset(260, #items * (H + 4))
    for i, it in ipairs(items) do
      local f = ui.frame(wList, UDim2.new(1, 0, 0, H), UDim2.fromOffset(0, (i - 1) * (H + 4)), RGB(0, 18, 6), 0.6)
      f.Name = "Row_" .. (it.wid or "flare")
      local sk = ui.stroke(f, HUD, 1, 0.7)
      local kb = ui.frame(f, UDim2.fromOffset(24, 24), UDim2.new(0, 6, 0.5, 0), RGB(0, 0, 0), 0.4, Vector2.new(0, 0.5))
      ui.stroke(kb, HUD, 1, 0.2)
      local kl = ui.label(kb, it.key, UDim2.fromScale(1, 1), nil, 15, HUD, Enum.Font.Code)
      kl.Name = "Key"
      local ic = ui.frame(f, UDim2.fromOffset(60, 20), UDim2.new(0, 38, 0.5, 0), RGB(0, 0, 0), 1, Vector2.new(0, 0.5))
      ic.Name = "Icon"
      drawIcon(ic, it)
      local nm = ui.label(f, it.flare and T("air.flareName") or T("aw." .. it.wid), UDim2.new(1, -164, 1, 0), UDim2.fromOffset(104, 0), 14, HUD, Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left)
      nm.TextWrapped = false
      nm.Name = "Name"
      local cnt = ui.label(f, "", UDim2.fromOffset(58, H), UDim2.new(1, -6, 0, 0), 17, HUD, Enum.Font.Code, Vector2.new(1, 0), Enum.TextXAlignment.Right)
      cnt.Name = "Count"
      wRows[i] = { f = f, s = sk, cnt = cnt, nm = nm, it = it }
    end
  end

  -- 自己的飞机：看光电时藏起来（吊舱在机腹，不然一低头就是自己的机翼）；热成像高亮所有实体时也不把自己涂白
  local ownAir = Instance.new("Model")
  ownAir.Name = "OwnAir"
  ownAir.Parent = workspace
  local function ownHide(on)
    local v = st and G.views and G.views[st.em]
    if not v or not v.M then return end
    for _, p in ipairs(v.M.plist or {}) do
      if p:IsA("BasePart") then p.LocalTransparencyModifier = on and 1 or 0 end
    end
    if on and v.model and v.model.Parent == G.viewFolder then v.model.Parent = ownAir
    elseif not on and v.model and v.model.Parent == ownAir and G.viewFolder then v.model.Parent = G.viewFolder end
  end
  local function eoApply()
    local on = st ~= nil and st.eo == true
    eoGui.Visible = on
    local m = on and EO_MODES[st.eoMode or 1] or nil
    eoCC.Enabled = on
    eoHl.Enabled = on and m ~= "tv"
    if on then
      if m == "tv" then
        eoCC.Saturation, eoCC.Contrast, eoCC.Brightness, eoCC.TintColor = -1, 0.25, 0.02, Color3.new(1, 1, 1)
      elseif m == "whot" then
        eoCC.Saturation, eoCC.Contrast, eoCC.Brightness, eoCC.TintColor = -1, 0.45, -0.3, RGB(225, 225, 225)
        eoHl.FillColor, eoHl.OutlineColor = Color3.new(1, 1, 1), Color3.new(1, 1, 1)
      else
        eoCC.Saturation, eoCC.Contrast, eoCC.Brightness, eoCC.TintColor = -1, 0.25, 0.22, RGB(235, 235, 235)
        eoHl.FillColor, eoHl.OutlineColor = Color3.new(0, 0, 0), Color3.new(0, 0, 0)
      end
      eoHl.Adornee = G.viewFolder
    end
  end
  -- P：进出光电吊舱（用户：飞机驾驶按 P 也要能切换光电视角）。鼠标只转吊舱（稳定在世界方向上），飞机自己保持平飞（固定翼按住进吊舱时的航向、
  --   航迹拉平；直升机机头不跟着转、不低头）；Z / 滚轮变焦，V 电视 / 白热 / 黑热；画面里的瞄准点就是吊舱看着的地方（对地弹、机头炮塔都朝那里）
  local function setEO(on)
    if not st then return end
    if st.uav then st.dcam = (st.dcam == "nose") and "chase" or "nose" return end   -- 无人机本来就有前视光电：P 跟 V 一样切
    on = on and st.pilot and not st.crashed
    if on == (st.eo == true) then return end
    st.eo = on
    if on then
      local look = cam.CFrame.LookVector
      st.eoYaw = math.atan2(-look.X, -look.Z)
      st.eoPitch = clamp(math.asin(clamp(look.Y, -1, 1)) - 0.15, -1.5, 0.35)
      st.eoMode = st.eoMode or 1
      st.zoom = 1
      if st.d.kind == "jet" then   -- 自动驾驶：按现在的航向平飞
        local v = (st.vel.Magnitude > 1) and st.vel.Unit or st.cf.LookVector
        st.aimYaw = math.atan2(-v.X, -v.Z)
        st.aimPitch = clamp(math.asin(clamp(v.Y, -1, 1)), -0.06, 0.12)
      else   -- 直升机：镜头回到略往下看，机头不跟吊舱转
        st.camPitch, st.camYaw = -0.12, st.yaw
      end
    else
      st.zoom = 1
    end
    ownHide(on)
    eoApply()
    if G.playSound then G.playSound("quiet", nil, on and 1.5 or 1.2) end
  end
  G.flyEO = setEO

  ---------------------------------------------------------------- 开始 / 结束

  local function findEnt(id)
    local f = workspace:FindFirstChild("Ents")
    if not f then return nil end
    for _, em in ipairs(f:GetChildren()) do
      if em:GetAttribute("EntId") == id then return em end
    end
    return nil
  end

  local mapParams = RaycastParams.new()
  mapParams.FilterType = Enum.RaycastFilterType.Include
  local aimParams = RaycastParams.new()
  aimParams.FilterType = Enum.RaycastFilterType.Exclude

  local controls = nil
  task.spawn(function()
    local ok, res = pcall(function()
      local pm = require(me:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10))
      return pm:GetControls()
    end)
    if ok then controls = res end
  end)

  local function begin(vs)
    local em = findEnt(vs.id)
    if not em then return end
    local d = AD.get(vs.m)
    if not d then return end
    local cf = em.Root.CFrame
    local look = cf.LookVector
    local yaw = math.atan2(-look.X, -look.Z)
    local onGround = vs.ground == true
    st = { id = vs.id, em = em, d = d, pilot = vs.pilot == true, cf = cf, vel = V(), spd = 0, sink = 0, pr = 0, rr = 0, yr = 0,
      thr = onGround and 0 or 85, ground = onGround, gearWant = onGround and 1 or 0, gear = onGround and 1 or 0, rpm = (d.kind == "heli" and not onGround) and 100 or 0,
      yaw = yaw, hv = V(), vy = 0, tiltP = 0, tiltR = 0, camYaw = yaw, camPitch = -0.15, aimYaw = yaw, aimPitch = 0, c = {},
      load = vs.load or {}, wl = AD.groups(d, vs.load or {}), wi = 1, firing = false, trig = false, sendT = 0, lock = nil, lockT = 0, nextFire = 0,
      ty = 0, gp = 0, lastHv = V(), crashed = false, bay = 0, bayS = 0, lkY = 0, lkP = 0, lkT = 0 }
    for i, wid in ipairs(st.wl) do   -- 默认选中第一种挂载（机炮一直在鼠标左键上）
      local w = AD.W[wid]
      if w and w.kind ~= "gun" then st.wi = i break end
    end
    if not onGround then   -- 空中出发：带着速度
      if d.kind == "jet" then st.spd = d.vMil * 0.8 else st.hv = look * d.vMax * 0.6 end
      st.vel = look * ((d.kind == "jet") and st.spd or d.vMax * 0.6)
    end
    -- 遥控无人机（服务器 vs.uav）：人在地上端着战术平板，画面是平板（Tablet.lua）；默认前视光电，右键 / V 换外部视角，Z 变焦
    st.uav = vs.uav == true and d.drone == true
    st.dcam, st.zoom, st.zoomS = st.uav and "nose" or nil, 1, 1
    G.fly, G.drive = st, st   -- G.drive：步兵的操作（Play）先停下
    cam.CameraType = Enum.CameraType.Scriptable
    panel.Visible = true
    -- 平板模式：面板挪进平板屏幕里（底边外壳上不放东西）
    local rect = G.tabletRect
    panel.Position = (st.uav and rect) and UDim2.new(0.5, 0, rect[4], -12) or UDim2.new(0.5, 0, 1, -24)
    if st.uav and G.tabletOpen then G.tabletOpen(st) end
    for _, l in ipairs(HUDS) do l.Visible = st.pilot end
    buildList()
    if touchUI then for _, f in ipairs(touchUI) do f.Visible = st.pilot end end
    local m = workspace:FindFirstChild("Map")
    mapParams.FilterDescendantsInstances = m and { m } or {}
    if G.playSound then G.playSound("capture") end
  end

  local function stop()
    if st and st.trig then G.R.Drive:FireServer({ op = "trig", on = false }) end
    if G.gunLoop then G.gunLoop("me", nil, nil, false) end
    if st and st.eo then
      ownHide(false)
      st.eo = false
    end
    eoGui.Visible, eoCC.Enabled, eoHl.Enabled = false, false, false
    local old = st
    st = nil
    G.fly = nil
    if G.drive == old then G.drive = nil end
    cam.CameraType = Enum.CameraType.Custom
    cam.FieldOfView = 70
    if UIS.MouseBehavior == Enum.MouseBehavior.LockCenter then UIS.MouseBehavior = Enum.MouseBehavior.Default end
    panel.Visible = false
    for _, l in ipairs(HUDS) do l.Visible = false end
    lockBox.Visible, lockText.Visible, pipper.Visible = false, false, false
    landMark.Visible, landText.Visible = false, false
    if touchUI then for _, f in ipairs(touchUI) do f.Visible = false end end
    panel.Position = UDim2.new(0.5, 0, 1, -24)
    if old and old.uav and G.tabletClose then G.tabletClose() end
  end

  ---------------------------------------------------------------- 武器

  local function curW()
    local wid = st.wl[st.wi]
    return wid, wid and AD.W[wid]
  end
  -- 鼠标左键打的机炮（没有炮就是 nil）；F 打的挂载（选中的那种，选的是炮就用第一种挂载）——用户：F 控制导弹，鼠标控制机枪
  local function gunW()
    for _, wid in ipairs(st.wl) do
      local w = AD.W[wid]
      if w and w.kind == "gun" then return wid, w end
    end
    return nil
  end
  local function storeW()
    local wid, w = curW()
    if w and w.kind ~= "gun" then return wid, w end
    for _, wid2 in ipairs(st.wl) do
      local w2 = AD.W[wid2]
      if w2 and w2.kind ~= "gun" then return wid2, w2 end
    end
    return nil
  end
  -- 这种弹还剩几枚（S.veh.stores 是服务器的数，开火时本地先扣）
  local function left(wid)
    local w = AD.W[wid]
    if not w then return 0 end
    if w.kind == "gun" then return st.gunAmmo or 0 end
    local n = 0
    for i, s in ipairs(st.d.st or {}) do
      if st.load[i] == wid then n += (st.stores and st.stores[i]) or 0 end
    end
    return n
  end
  function G.flyNextWeapon()
    if not st or #st.wl == 0 then return end
    st.wi = st.wi % #st.wl + 1
    st.lock, st.lockT = nil, 0
  end
  -- 弹舱：选中的弹在哪个舱里，那个舱门就开着
  local function bayOf(wid)
    local main, side = false, false
    for i, s in ipairs(st.d.st or {}) do
      if st.load[i] == wid and s.bay then
        if s.bay == "main" then main = true else side = true end
      end
    end
    return main, side
  end

  -- 能锁的目标：敌方实体（空空弹打飞机，空地弹 / 炸弹打地面、海上的）
  local GROUND_KINDS = { veh = true, bot = true, fort = true, lcm = true, lcac = true, ship = true }
  local function candidates(w)
    local out = {}
    local f = workspace:FindFirstChild("Ents")
    if not f or not st then return out end
    local myTeam = me:GetAttribute("Side")
    local p0 = st.cf.Position
    for _, em in ipairs(f:GetChildren()) do
      local kind = em:GetAttribute("Kind")
      local root = em:FindFirstChild("Root")
      if root and em ~= st.em and em:GetAttribute("Team") ~= myTeam and not em:GetAttribute("Wreck") and (em:GetAttribute("Hp") or 1) > 0 then
        local ok = (w.kind == "aam") and kind == "air" or ((w.kind == "agm" or w.kind == "bomb") and GROUND_KINDS[kind])
        if ok then
          local to = root.CFrame.Position - p0
          local dist = to.Magnitude
          if dist < (w.range or 3200) and dist > 30 then table.insert(out, { em = em, id = em:GetAttribute("EntId"), dir = to.Unit, dist = dist, pos = root.CFrame.Position }) end
        end
      end
    end
    return out
  end
  -- 导引头视场：导弹看机头前方 cone 度；炸弹看飞机下前方（俯冲投弹也行）
  local function inCone(w, c)
    local fwd = st.cf.LookVector
    if w.kind == "bomb" then
      local down = (fwd * 0.6 + V(0, -1, 0)).Unit
      return down:Dot(c.dir) > math.cos(rad(w.cone or 60))
    end
    local cone = w.cone or 30
    if st.d.kind == "heli" and w.kind == "agm" then cone += 20 end
    return fwd:Dot(c.dir) > math.cos(rad(cone))
  end
  -- 瞄准 / 挑目标的方向：固定翼是机头（不再用鼠标瞄准），直升机是镜头（鼠标瞄机头炮塔）
  local function aimDirNow()
    if st.d.kind == "jet" then return st.cf.LookVector end
    return cam.CFrame.LookVector
  end
  -- 自动驾驶要去的方向（光电吊舱、飞出作战区自动掉头时用 aimYaw / aimPitch）
  local function autoDir() return (CFrame.Angles(0, st.aimYaw, 0) * CFrame.Angles(st.aimPitch, 0, 0)).LookVector end
  -- 光电吊舱看着的方向（世界方向，鼠标转）；瞄准、挑目标用的方向：开着光电就是吊舱，不然是鼠标瞄准方向
  local function eoDir() return (CFrame.Angles(0, st.eoYaw or 0, 0) * CFrame.Angles(st.eoPitch or 0, 0, 0)).LookVector end
  local function lookDir() return st.eo and eoDir() or aimDirNow() end
  local function pickTarget(w, skip)
    local best, bs = nil, math.huge
    local want = lookDir()
    for _, c in ipairs(candidates(w)) do
      if inCone(w, c) and c.id ~= skip then
        local s = 1 - want:Dot(c.dir) + c.dist / 20000
        if s < bs then best, bs = c, s end
      end
    end
    return best
  end
  function G.flyNextTarget()
    if not st then return end
    local _, w = storeW()
    if not w or w.kind == "gun" or w.kind == "rkt" then return end
    local c = pickTarget(w, st.lock and st.lock.id)
    st.lock, st.lockT = c, 0
  end

  local function setTrig(on)
    -- 航炮声：按住扳机就一直响（循环一小段起爆声，一圈一发），打光了就停
    local loud = on and (st.gunAmmo or 0) > 0 and (not G.S or G.S.phase == "battle")
    if G.gunLoop and loud ~= (st.gunSnd == true) then
      st.gunSnd = loud
      G.gunLoop("me", st.d.gun, nil, loud)
    end
    if st.trig == on then return end
    st.trig = on
    G.R.Drive:FireServer({ op = "trig", on = on, aim = st.aimPt })
  end

  local function fireStore(wid, w)
    local t = os.clock()
    if t < st.nextFire or left(wid) <= 0 then return end
    if G.S and G.S.phase ~= "battle" then G.toast(T("air.notYet"), "info") return end
    local locked = st.lock and st.lockT >= (w.lockTime or 1)
    if w.kind == "aam" and not locked then G.toast(T("air.needLock"), "info") return end
    st.nextFire = t + ((w.kind == "rkt") and (w.rate or 0.12) or 0.4)
    G.R.Drive:FireServer({ op = "fire", w = wid, tgt = locked and st.lock.id or nil, aim = st.aimPt })
    for i in ipairs(st.d.st or {}) do   -- 本地先扣一枚（服务器的数随后推过来）
      if st.load[i] == wid and (st.stores[i] or 0) > 0 then
        st.stores[i] -= 1
        break
      end
    end
    -- 开火声按武器（Fx.lua 的 G.sfx）：导弹低沉的点火 + 呼啸、火箭弹「噗」一声 + 呼的一下、炸弹挂架弹开「咣」一声
    if G.sfx then G.sfx((w.kind == "rkt") and "rkt" or ((w.kind == "bomb") and "bombRel" or "msl"), nil, { vol = (w.kind == "rkt") and 0.7 or 0.8 }) end
  end

  ---------------------------------------------------------------- 物理：固定翼

  local function key(k) return UIS:IsKeyDown(k) end
  local function crash()
    if st.crashed then return end
    st.crashed = true
    G.R.Drive:FireServer({ op = "crash", hit = true })
    if G.shake then G.shake(1) end
  end

  local function jetPhysics(dt)
    local d = st.d
    -- 用户：不让准星控制方向，改成 WASD——S 抬头、W 低头（像驾驶杆：往回拉抬头），A / D 滚转，Q / E 方向舵，Shift / Ctrl 油门
    local up = key(Enum.KeyCode.LeftShift) or key(Enum.KeyCode.RightShift) or (touch and touch.up)
    local dn = key(Enum.KeyCode.LeftControl) or key(Enum.KeyCode.RightControl) or (touch and touch.down)
    st.thr = clamp(st.thr + ((up and 1 or 0) - (dn and 1 or 0)) * 55 * dt, 0, d.ab and 130 or 100)
    if st.out then st.thr = 0 end   -- 油烧干了：发动机熄火，只能滑翔
    local rollIn = (key(Enum.KeyCode.D) and 1 or 0) - (key(Enum.KeyCode.A) and 1 or 0)
    local yawIn = (key(Enum.KeyCode.E) and 1 or 0) - (key(Enum.KeyCode.Q) and 1 or 0)
    local pitchIn = ((key(Enum.KeyCode.W) or key(Enum.KeyCode.Up)) and 1 or 0) - ((key(Enum.KeyCode.S) or key(Enum.KeyCode.Down)) and 1 or 0)
    if G.mobile and controls then   -- 手机：摇杆直接当驾驶杆（往前推是低头）
      local ok, mv = pcall(function() return controls:GetMoveVector() end)
      if ok and typeof(mv) == "Vector3" then
        if math.abs(mv.X) > 0.1 then rollIn = mv.X end
        if math.abs(mv.Z) > 0.1 then pitchIn = mv.Z end
      end
    end
    local cf = st.cf
    local fwd, upV, right = cf.LookVector, cf.UpVector, cf.RightVector
    -- 速度：油门给目标速度（加力到 vAB），往目标加减速；爬升掉速、俯冲加速、拉杆转弯掉能量；地上没油门时滚着慢下来
    -- 重量感（用户：飞机驾驶没有重量感）：W 越大越「沉」——F-22、歼-20 约 1，A-10 约 2，轰-6K、B-2、MQ-9 是 3
    local W = math.clamp(220 / math.max(d.roll or 200, 1), 1, 3)
    -- 发动机有迟滞：推力跟着油门慢慢起来（加力点着要一下）
    st.thrE = approach(st.thrE or st.thr, st.thr, (st.thr > (st.thrE or 0) and 38 or 55) / W * dt)
    local thr = st.thrE
    local tgt = (thr <= 100) and d.vMil * thr / 100 or (d.vMil + (d.vMax - d.vMil) * (thr - 100) / 30)
    local acc = (thr > 100) and (d.accel + (d.abAccel or 0)) or d.accel
    -- 副油箱的阻力：最大速度、加速度都少几成；油多就重：加速慢（满内油 + 两个副油箱比一半内油重三成多）
    tgt *= 1 - (st.drag or 0)
    acc *= (1 - (st.drag or 0)) / (st.heavy or 1)
    -- 地上滑跑：推力要先克服整架飞机的重量和轮子的阻力，加速度只有天上的四分之一（战斗机滑跑两三百米、轰炸机五百米上下，
    --   一推油门不再四五十米就飞起来；弹射器单独算）
    if st.ground and not st.cat then acc *= 0.25 end
    if st.trap then   -- 挂着拦阻索：发动机推力不算，地上那段按拦阻索减速
    elseif tgt > st.spd then st.spd += math.min(tgt - st.spd, acc * dt) else st.spd -= math.min(st.spd - tgt, (st.ground and (key(Enum.KeyCode.B) and 60 or 22) or acc * 0.45) * dt) end
    if not st.ground then
      local vd = st.vdir or fwd
      st.spd -= GR * vd.Y * 0.9 * dt   -- 沿航迹爬升掉速、俯冲加速
      st.spd -= math.abs(st.pr) * st.spd * 0.16 * dt
      st.spd -= (1 - math.clamp(vd:Dot(fwd), -1, 1)) * st.spd * 2.6 * dt   -- 机头和航迹差得越多（大迎角、侧滑）掉速越快
    end
    st.spd = clamp(st.spd, 0, d.vMax * 1.3)
    local q = clamp((st.spd - d.stall * 0.4) / d.stall, 0.12, 1)   -- 舵效：慢了舵不灵
    -- 想怎么转：键盘直接操纵（松开 A / D 自动摆平、压坡度自动带杆保高度）；光电吊舱 / 飞出作战区时自动驾驶
    local pc, rc, yc
    if G.mobile or not (st.eo or st.oob) then
      pc, rc, yc = -pitchIn * rad(d.pitch), rollIn * rad(d.roll), yawIn * rad(d.yaw)
      if not G.mobile and not st.ground then
        local bank = math.asin(clamp(right.Y, -1, 1))
        local upright = upV.Y > 0.3   -- 没倒飞、没在翻筋斗
        if rollIn == 0 and upright then rc = clamp(bank * 2.2, -1, 1) * rad(d.roll) * 0.75 end   -- 松杆：机翼慢慢摆平
        if pitchIn == 0 and upright then   -- 压着坡度：自动带杆，转弯不掉高度（水平转弯要的俯仰角速度 = g·tanφ·sinφ / v）
          local phi = math.min(math.abs(bank), rad(75))
          pc = math.min(GR * math.tan(phi) * math.sin(phi) / math.max(st.spd, 30), rad(d.pitch) * 0.8)
        end
      end
    else
      local aim = autoDir()
      local l = cf:VectorToObjectSpace(aim)
      local fz = -l.Z
      local off = math.acos(clamp(fz, -1, 1))
      local w = Map.smooth(rad(2), rad(10), off)
      local toTarget = math.atan2(l.X, l.Y)   -- 让目标落到机头正上方（升力方向）要滚多少
      if fz < -0.2 and math.abs(l.X) < 0.15 then toTarget = 0 end   -- 目标在正后方偏一点点：先拉起来（筋斗），别来回滚
      local level = math.asin(clamp(right.Y, -1, 1))   -- 目标正前方时把机翼摆平
      rc = (w * clamp(toTarget * 3.2, -1, 1) + (1 - w) * clamp(level * 2.5, -1, 1)) * rad(d.roll)
      local pe = math.atan2(l.Y, math.max(fz, 0.05))
      if fz < 0 then pe = (l.Y >= 0) and math.pi / 2 or -math.pi / 2 end
      pc = clamp(pe * 3, -1, 1) * rad(d.pitch)
      if math.abs(toTarget) > rad(100) and off > rad(25) then pc = math.min(pc, rad(d.pitch) * 0.15) end   -- 还没滚过去别乱拉
      yc = clamp(math.atan2(l.X, math.max(fz, 0.05)) * 2, -1, 1) * rad(d.yaw)
      if rollIn ~= 0 then rc = rollIn * rad(d.roll) end
      if pitchIn ~= 0 then pc = -pitchIn * rad(d.pitch) end
      if yawIn ~= 0 then yc = yawIn * rad(d.yaw) end
    end
    -- 过载限制：转弯角速度不超过 g × 重力 / 速度
    local gLim = d.g * GR / math.max(st.spd, 30) / math.sqrt(st.heavy or 1)   -- 重了转不快
    pc = clamp(pc, -math.min(rad(d.pitch), gLim) * 0.6, math.min(rad(d.pitch), gLim)) * q
    rc, yc = rc * q, yc * q
    st.pr = approach(st.pr, pc, 2.6 / W ^ 0.8 * dt)   -- 角速度要一会儿才起来、停下（转动惯量）：重的更慢
    st.rr = approach(st.rr, rc, rad(d.roll) * 2.8 / W ^ 0.5 * dt)
    st.yr = approach(st.yr, yc, 1.2 / W ^ 0.6 * dt)
    st.c.pit, st.c.rol, st.c.yaw = clamp(st.pr / math.max(rad(d.pitch), 1e-3), -1, 1), clamp(st.rr / math.max(rad(d.roll), 1e-3), -1, 1), clamp(st.yr / math.max(rad(d.yaw), 1e-3), -1, 1)
    local pos = cf.Position
    if st.ground and st.cat then
      -- 航母弹射器：卡上以后原地不动，油门推满按空格（手机：推满等一秒半）沿轨道加速，冲到舰艏就离舰
      local start, dir, len = AD.cat(Map, st.cat.i)
      if st.cat.state == "hooked" then
        st.spd = 0
        st.yaw = math.atan2(-dir.X, -dir.Z)
        pos = start + V(0, d.gearH, 0)
        cf = CFrame.lookAt(pos, pos + dir)
        st.cat.full = (st.thr >= 90) and ((st.cat.full or 0) + dt) or 0
        if st.thr >= 90 and st.cat.full > 1.2 then   -- 推满油门一会儿就弹（空格改成下飞机了）
          st.cat.state, st.cat.s, st.cat.v = "launch", 0, 0
          if G.shake then G.shake(0.4) end
          if G.playSound then G.playSound("boom", pos, 1.6) end
        end
      else
        local vEnd = math.max(d.vRot * 1.2, d.stall * 1.35)
        st.cat.v += vEnd * vEnd / (2 * len) * dt
        st.cat.s += st.cat.v * dt
        st.spd = st.cat.v
        if st.cat.s >= len then   -- 离舰
          st.ground, st.cat = false, nil
          st.pr = rad(5)
          pos = start + dir * len + V(0, d.gearH + 1, 0)
          cf = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(rad(5), 0, 0)
        else
          pos = start + dir * st.cat.s + V(0, d.gearH, 0)
          cf = CFrame.lookAt(pos, pos + dir)
          st.steamT = (st.steamT or 0) - dt
          if st.steamT <= 0 and G.fxPart then   -- 弹射轨道上一路冒白汽
            st.steamT = 0.05
            local s2 = G.fxPart(Enum.PartType.Ball, V(3, 3, 3), CFrame.new(pos - V(0, d.gearH - 0.5, 0)), RGB(236, 236, 232), Enum.Material.SmoothPlastic, 0.35)
            if G.tween then G.tween(s2, 1.4, { Size = V(9, 9, 9), Transparency = 1 }) end
            game:GetService("Debris"):AddItem(s2, 1.5)
          end
        end
      end
      st.vel = cf.LookVector * st.spd
      st.vdir, st.accV = cf.LookVector, nil
      st.sink = 0
    elseif st.ground then
      -- 地上：机头只能左右转（前轮转向：A / D 或 Q / E），速度够了按 S 抬头就离地
      local steer = (yawIn ~= 0) and yawIn or rollIn
      st.yaw -= steer * rad(30) * clamp(st.spd / 25, 0.15, 1) * dt
      -- 航母甲板：没上弹射器滑不快（起飞要靠弹射器）；挂上拦阻索的一路被拉停
      local deck = AD.onDeck(Map, pos.X, pos.Z)
      if st.trap then
        st.spd = math.max(0, st.spd - st.trapA * dt)
        if st.spd < 1 then st.trap = nil end
      elseif deck == "carrier" then
        st.spd = math.min(st.spd, AD.TAXI)
      end
      -- 滑到弹射器起点、机头对正、速度慢：卡上
      if deck == "carrier" and d.carrier and not st.trap and st.spd < 15 then
        local look0 = V(-math.sin(st.yaw), 0, -math.cos(st.yaw))
        for i = 1, #AD.CATS do
          local start, dir = AD.cat(Map, i)
          local rel = V(pos.X - start.X, 0, pos.Z - start.Z)
          local along = rel:Dot(dir)
          local lat = (rel - dir * along).Magnitude
          if math.abs(along) < 12 and lat < 7 and look0:Dot(dir) > math.cos(rad(25)) then
            st.cat = { i = i, state = "hooked" }
            if G.playSound then G.playSound("capture", pos) end   -- 卡上：咔一声，不出字
            break
          end
        end
      end
      local look = V(-math.sin(st.yaw), 0, -math.cos(st.yaw))
      pos += look * st.spd * dt
      local g = ground(pos.X, pos.Z)
      local wantUp = pitchIn < -0.3
      if st.spd >= d.vRot and wantUp then   -- 离地
        st.ground = false
        st.pr = rad(6)
        cf = CFrame.lookAt(pos + V(0, 0.5, 0), pos + V(0, 0.5, 0) + look) * CFrame.Angles(rad(4), 0, 0)
      elseif pos.Y - d.gearH > g + 2.5 then   -- 冲出甲板 / 跑道尽头：掉下去
        st.ground = false
        cf = CFrame.lookAt(pos, pos + look)
      else
        pos = V(pos.X, g + d.gearH, pos.Z)
        cf = CFrame.lookAt(pos, pos + look)
      end
      st.vel = look * st.spd
      st.vdir, st.accV = (st.ground and look) or cf.LookVector, nil
      st.sink = 0
    else
      cf = cf * CFrame.Angles(st.pr * dt, -st.yr * dt, -st.rr * dt)
      -- 失速：升力不够，往下沉、机头往速度方向掉
      local lift = clamp((st.spd / d.stall) ^ 2, 0, 1)
      st.sink = approach(st.sink, GR * (1 - lift) * 1.8, GR * dt)
      if lift < 0.85 then cf = cf * CFrame.Angles(-(1 - lift) * 0.9 * dt, 0, 0) end
      -- 航迹不是机头指哪就飞哪：升力把速度方向往机头那边拉，快、升力足拉得快，重的飞机拉得慢——拉杆时机头先抬、飞机「吃」一下才转过去
      local vd = st.vdir or cf.LookVector
      local pull = math.clamp(lift * st.spd / math.max(d.stall, 1) * 1.7, 0.35, 3.4) / W ^ 0.7
      vd = (vd + (cf.LookVector - vd) * math.min(1, pull * dt))
      st.vdir = (vd.Magnitude > 1e-3) and vd.Unit or cf.LookVector
      local v0 = st.vel
      st.vel = st.vdir * st.spd + V(0, -st.sink, 0)
      if v0 then   -- 加速度（镜头用：过载把镜头甩开）
        local a = (st.vel - v0) / math.max(dt, 1e-3)
        st.accV = (st.accV or a):Lerp(a, math.min(1, dt * 6))
      end
      pos += st.vel * dt
      cf = cf - cf.Position + pos
      -- 撞地 / 落地
      local g = ground(pos.X, pos.Z)
      if pos.Y - d.gearH <= g + 0.3 then
        local fw = cf.LookVector
        local bank = math.abs(deg(math.asin(clamp(cf.RightVector.Y, -1, 1))))
        local pitch = deg(math.asin(clamp(fw.Y, -1, 1)))
        local landable = g > 0.4 or AD.onDeck(Map, pos.X, pos.Z) ~= nil
        if st.gear > 0.9 and landable and st.vel.Y > -24 and st.spd < d.landMax and bank < 20 and pitch > -8 and pitch < 22 then
          st.ground = true
          st.yaw = math.atan2(-fw.X, -fw.Z)
          pos = V(pos.X, g + d.gearH, pos.Z)
          cf = CFrame.lookAt(pos, pos + V(fw.X, 0, fw.Z))
          st.sink, st.pr, st.rr, st.yr = 0, 0, 0, 0
          -- 航母：尾钩放着、落在拦阻索区，被拦阻索拉停（85 格内停住）
          if AD.onDeck(Map, pos.X, pos.Z) == "carrier" and (st.c.hook or 0) > 0.5 and AD.inWires(Map, pos.X, pos.Z) then
            st.trap, st.trapA = true, math.max(20, st.spd * st.spd / (2 * 85))
            if G.shake then G.shake(0.5) end
          end
        else
          crash()
        end
      end
    end
    st.cf = cf
    -- 起落架：离地后自动不收，按 G 收放；地上一直放着
    if st.ground then st.gearWant = 1 end
    st.gear = approach(st.gear, st.gearWant, dt / 2.5)
    st.c.gear = st.gear
    st.c.thr = st.thr
    st.c.flap = (st.gear > 0.5 and st.spd < d.stall * 1.6) and 1 or 0
    st.c.can = (st.ground and st.thr < 5 and st.spd < 3) and 1 or 0
    st.c.fold = (d.fold and st.ground and st.thr < 5 and st.spd < 3 and AD.onDeck(Map, pos.X, pos.Z)) and 1 or 0
    st.c.hook = (d.gear and d.gear.hook and st.gear > 0.9 and not st.ground) and 1 or 0
    st.c.brk = (key(Enum.KeyCode.B)) and 1 or 0
    st.c.rpm = st.thr
  end

  ---------------------------------------------------------------- 物理：直升机

  -- 直升机（用户：直升机操作感觉不太真实）：按真直升机的道理飞——旋翼拉力沿桨盘法线，桨盘往哪倾就往哪加速：
  --   W / S 前推后拉驾驶杆（低头加速、抬头减速 / 后退），Q / E 左右压杆（压坡度侧移）；姿态有惯性（二阶弹簧），松杆自动回平；
  --   低速（悬停附近）松杆时自动往反方向带一点把飘移收住，快的时候松杆就保持平飞、靠阻力慢慢减速（要停下来得抬头拉一下）；
  --   空格 / Ctrl 总距：拉力大小（同样的总距，机身一倾、竖直方向的拉力就小了，会掉高度）；不按时自动把升降速度收到 0（定高）；
  --   A / D 脚蹬：偏航角速度，有惯性；速度上来以后压坡度就会转弯（协调转弯），尾翼让机头顺着来流（风标效应），鼠标看哪边就往哪边压坡度转过去；
  --   平移升力（二十几格每秒以上旋翼效率高一点）、地效（离地一个旋翼直径以内托得更稳）；最高平飞速度、爬升率照型号表
  local function heliPhysics(dt)
    local d = st.d
    if st.out then st.rpm = approach(st.rpm, 72, 9 * dt) else st.rpm = approach(st.rpm, 100, 22 * dt) end   -- 旋翼转起来要四五秒；熄火后靠气流自转，转速掉下来
    local lift = st.rpm >= 92
    local auto = st.out and not st.ground   -- 熄火自转下滑：还能往前飘一点，快落地时拉总距（空格）下沉慢一些
    -- 用户：直升机升降改成 Q / E（Q 升、E 降，空格 / Ctrl 也还能用）；镜头往哪看就往哪飞——往下看机头压下去、惯性往前冲，
    --   往上看抬头减速；机头跟着镜头转；W / S 前后、A / D 左右平移（侧倾）
    -- 再改（用户：鼠标控制机枪）：鼠标只转镜头、瞄机头炮塔，不再带着飞机转；A / D 改成转向（快的时候压坡度协调转弯），Q 升 / E 降，空格下飞机
    local fwdIn = (key(Enum.KeyCode.W) and 1 or 0) - (key(Enum.KeyCode.S) and 1 or 0)
    local sideIn = 0
    local yawIn = (key(Enum.KeyCode.D) and 1 or 0) - (key(Enum.KeyCode.A) and 1 or 0)
    local upIn = ((key(Enum.KeyCode.Q) or (touch and touch.up)) and 1 or 0)
      - ((key(Enum.KeyCode.E) or key(Enum.KeyCode.LeftControl) or key(Enum.KeyCode.C) or (touch and touch.down)) and 1 or 0)
    if G.mobile and controls then
      local ok, mv = pcall(function() return controls:GetMoveVector() end)
      if ok and typeof(mv) == "Vector3" then
        if math.abs(mv.Z) > 0.1 then fwdIn = -mv.Z end
        if math.abs(mv.X) > 0.1 then yawIn, sideIn = mv.X, 0 end   -- 手机：摇杆左右还是转向
      end
    end
    local GS = GR or 27.5
    local heavy = st.heavy or 1
    local maxT = rad(d.tilt)
    local f = V(-math.sin(st.yaw), 0, -math.cos(st.yaw))
    local r = V(math.cos(st.yaw), 0, -math.sin(st.yaw))
    local hv = st.hv
    local spd = hv.Magnitude
    local vf, vr = hv:Dot(f), hv:Dot(r)
    local g0 = ground(st.cf.Position.X, st.cf.Position.Z)
    local agl = st.cf.Position.Y - d.gearH - math.max(g0, 0)
    -- 驾驶杆 → 想要的姿态（俯仰：负的是低头）
    local hold = 1 - smooth(14, 34, spd)   -- 低速：松杆时自动收住飘移
    local tP = (fwdIn ~= 0) and (-fwdIn * maxT * 0.85) or clamp(vf * 0.018 * hold, -maxT * 0.4, maxT * 0.4)
    local tR = (sideIn ~= 0) and (sideIn * maxT * 0.8) or clamp(-vr * 0.018 * hold, -maxT * 0.4, maxT * 0.4)
    -- 快的时候按 A / D：压坡度协调转弯（低速时原地用尾桨转）
    local fast = smooth(18, 40, spd)
    if yawIn ~= 0 and not st.ground then tR += yawIn * maxT * 0.6 * fast end
    tP, tR = clamp(tP, -maxT, maxT), clamp(tR, -maxT, maxT)
    if st.ground then tP, tR = 0, 0 end
    -- 姿态：二阶弹簧（有惯性、不一下子到位）
    st.pR = (st.pR or 0) + ((tP - st.tiltP) * 10 - (st.pR or 0) * 6) * dt
    st.rR = (st.rR or 0) + ((tR - st.tiltR) * 10 - (st.rR or 0) * 6) * dt
    st.tiltP += st.pR * dt
    st.tiltR += st.rR * dt
    -- 偏航：脚蹬给角速度（有惯性）；快的时候协调转弯（坡度 → 转弯角速度）、风标效应（机头顺着来流）
    local yrWant = -yawIn * rad(d.yaw) * (1 - 0.5 * fast)   -- 快的时候转弯主要靠坡度
    if not st.ground then
      yrWant += -GS * math.tan(st.tiltR) / math.max(spd, 25) * fast
      yrWant += -math.atan2(vr, math.max(math.abs(vf), 1)) * 0.8 * smooth(10, 40, spd)
    end
    st.yr = (st.yr or 0) + (yrWant - (st.yr or 0)) * math.min(1, dt * 2.5)
    st.yaw += st.yr * dt
    -- 拉力：总距（松开时自动定高；停在地上时放到底）× 平移升力 × 地效
    local colWant = upIn
    if upIn == 0 then colWant = clamp(-st.vy * 0.07, -0.8, 0.8) end
    if st.ground and upIn <= 0 then colWant = -0.5 end
    if upIn < 0 and agl < 25 then colWant = -0.45 end   -- 快到地面了：下降慢一点（落地不摔）
    st.col = approach(st.col or 0, colWant, dt * 1.8)
    local k = d.climb * 0.6 / GS / heavy   -- 满总距的爬升率 ≈ 型号表 climb
    local etl = 1 + 0.06 * smooth(16, 36, spd)
    local ige = 1 + 0.1 * (1 - clamp(agl / ((d.rotor and d.rotor.r or 20) * 2), 0, 1))
    local Tm
    if auto then Tm = GS * (0.74 + 0.3 * math.max(upIn, 0))
    elseif not lift then Tm = GS * (st.rpm / 100) * 0.8
    else Tm = GS * (1 + st.col * k) * etl * ige end
    local cfA = CFrame.Angles(0, st.yaw, 0) * CFrame.Angles(st.tiltP, 0, -st.tiltR)
    local up = cfA.UpVector
    -- 阻力：最大压杆时最高速度正好是型号表的 vMax
    local cl = 0.03
    local cq = math.max(1e-5, (GS * math.sin(maxT * 0.85) - cl * d.vMax) / (d.vMax * d.vMax)) * (1 + (st.drag or 0))
    st.lastHv = hv
    local acc = V(up.X, 0, up.Z) * Tm - hv * (cl + cq * spd)
    if st.ground then acc = V() hv *= math.max(0, 1 - 5 * dt) end
    st.hv = hv + acc * dt
    st.vy += (Tm * up.Y - GS - st.vy * 0.6) * dt
    local pos = st.cf.Position + (st.hv + V(0, st.vy, 0)) * dt
    local g = ground(pos.X, pos.Z)
    if pos.Y - d.gearH <= g then
      local overSea = g <= 0.4 and not AD.onDeck(Map, pos.X, pos.Z)
      if (st.vy < -30 or overSea) and not st.ground and not st.crashed then crash() end
      pos = V(pos.X, g + d.gearH, pos.Z)
      st.vy = math.max(st.vy, 0)
      st.ground = upIn <= 0 and Tm * up.Y <= GS * 1.02
      if st.ground then st.hv *= math.max(0, 1 - 5 * dt) end
    else
      st.ground = false
    end
    st.cf = CF(pos) * CFrame.Angles(0, st.yaw, 0) * CFrame.Angles(st.tiltP, 0, -st.tiltR)
    st.vel = st.hv + V(0, st.vy, 0)
    -- 动画通道（桨盘跟着驾驶杆倾）：用平滑过的杆量
    st.c.pit = approach(st.c.pit or 0, fwdIn ~= 0 and fwdIn or clamp(-tP / maxT, -1, 1) * 0.5, dt * 4)
    st.c.rol = approach(st.c.rol or 0, sideIn ~= 0 and sideIn or clamp(tR / maxT, -1, 1) * 0.5, dt * 4)
    st.c.yaw, st.c.col = yawIn, clamp(st.col, -1, 1)
    st.c.rpm, st.c.thr, st.c.gear = st.rpm, st.rpm, 1
  end

  ---------------------------------------------------------------- 输入

  UIS.InputBegan:Connect(function(io, gp)
    if gp or not st then return end
    local k = io.KeyCode
    if k == Enum.KeyCode.Space then G.R.Drive:FireServer({ op = "exit" }) return end   -- 用户：空格键脱离载具（在天上就跳伞）
    if not st.pilot then return end
    if io.UserInputType == Enum.UserInputType.MouseButton1 then
      st.firing = true
    elseif k == Enum.KeyCode.F then   -- 发导弹 / 火箭 / 炸弹（选中的那种）
      st.missile = true
    elseif k == Enum.KeyCode.C and st.d.kind == "jet" then   -- 镜头回到机尾
      st.lkY, st.lkP = 0, 0
    elseif k == Enum.KeyCode.X then
      G.R.Drive:FireServer({ op = "flare" })
    elseif k == Enum.KeyCode.J then   -- 抛副油箱（进空战前）
      G.R.Drive:FireServer({ op = "jettison" })
    elseif k == Enum.KeyCode.G then
      if st.d.kind == "jet" and not st.ground then st.gearWant = (st.gearWant > 0.5) and 0 or 1 end
    elseif k == Enum.KeyCode.R then
      G.flyNextTarget()
    elseif k == Enum.KeyCode.P then   -- 光电吊舱视角
      setEO(not st.eo)
    elseif st.eo and k == Enum.KeyCode.V then   -- 光电：电视 → 热成像白热 → 黑热
      st.eoMode = (st.eoMode or 1) % #EO_MODES + 1
      eoApply()
    elseif st.uav and (k == Enum.KeyCode.V or io.UserInputType == Enum.UserInputType.MouseButton2) then   -- 平板：前视光电 ↔ 外部视角
      st.dcam = (st.dcam == "nose") and "chase" or "nose"
    elseif (st.uav or st.eo) and k == Enum.KeyCode.Z then   -- 变焦一档一档跳：1× → 3× → 8× → 1×
      st.zoom = (st.zoom < 2.9) and 3 or ((st.zoom < 7.9) and 8 or 1)
    else
      local n = ({ [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6 })[k]
      if n and st.wl[n] then
        st.wi = n
        st.lock, st.lockT = nil, 0
      end
    end
  end)
  UIS.InputEnded:Connect(function(io)
    if st and io.UserInputType == Enum.UserInputType.MouseButton1 then st.firing = false end
    if st and io.KeyCode == Enum.KeyCode.F then st.missile = false end
  end)
  UIS.InputChanged:Connect(function(io, gp)   -- 平板前视光电：滚轮细调倍率（1× ~ 12×）
    if gp or not st or not (st.uav or st.eo) or io.UserInputType ~= Enum.UserInputType.MouseWheel then return end
    st.zoom = clamp(st.zoom * (1 + 0.18 * io.Position.Z), 1, 12)
  end)

  G.R.Drive.OnClientEvent:Connect(function(m)
    if type(m) ~= "table" or not st then return end
    if m.op == "fix" and typeof(m.cf) == "CFrame" then   -- 服务器不认：拉回去
      st.cf = m.cf
      if typeof(m.v) == "Vector3" then
        st.vel = m.v
        st.spd = m.v.Magnitude
        st.hv = V(m.v.X, 0, m.v.Z)
      end
      -- 航迹方向跟着拉回去（不然留着原来的航迹，机头和航迹差得远，一下子掉光速度失速）
      st.vdir = (typeof(m.v) == "Vector3" and m.v.Magnitude > 1) and m.v.Unit or m.cf.LookVector
      st.accV = nil
    elseif m.op == "rwr" then   -- 有导弹朝我来了
      st.rwrT = os.clock() + 4
      if G.playSound then G.playSound("capture", nil, 2.2) end
    end
  end)

  ---------------------------------------------------------------- 每帧

  local SENS = 0.0042
  local function project(p)
    local sp, on = cam:WorldToViewportPoint(p)
    return UDim2.fromOffset(sp.X, sp.Y), on
  end

  function G.stepFly(dt)
    local S = G.S
    local vs = S and S.alive and S.veh or nil
    if vs and not vs.air then vs = nil end
    if vs and (not st or st.id ~= vs.id) then
      if st then stop() end
      begin(vs)
    elseif not vs and st then
      stop()
    end
    if not st then return end
    if not st.em.Parent then stop() return end
    local d = st.d
    st.pilot = vs.pilot == true
    st.stores = st.storesLocal or {}
    -- 服务器推来的弹药数（半秒一次）：比本地扣的数少才换（本地先扣过的不回弹）
    if vs.stores then
      st.storesLocal = st.storesLocal or table.clone(vs.stores)
      for i, n in ipairs(vs.stores) do
        if st.storesSeen == nil or st.storesSeen[i] ~= n then st.storesLocal[i] = n end
      end
      st.storesSeen = table.clone(vs.stores)
      st.stores = st.storesLocal
    end
    st.gunAmmo, st.flares, st.load = vs.gun or 0, vs.flares or 0, vs.load or st.load
    -- 油量（服务器算，属性 Fuel / FuelX）：烧干了熄火；挂着的副油箱算阻力，油多算重量
    local f0, x0 = st.em:GetAttribute("Fuel"), st.em:GetAttribute("FuelX")
    st.fuel = (type(f0) == "number") and f0 or 1
    st.fuelX = (type(x0) == "number") and x0 or 0
    st.out = st.fuel <= 0 and st.fuelX <= 0
    st.heavy = AD.heavy(d, st.fuel, st.fuelX)
    st.drag, st.tanks = 0, 0
    for i, s2 in ipairs(d.st or {}) do
      local w2 = st.load and st.load[i] and AD.W[st.load[i]]
      if w2 and w2.kind == "tank" and (st.stores[i] or 0) > 0 then
        st.drag += w2.drag * st.stores[i]
        st.tanks += st.stores[i]
      end
    end
    -- 镜头转动
    if not G.mobile then UIS.MouseBehavior = Enum.MouseBehavior.LockCenter end
    local md = UIS:GetMouseDelta()
    -- 平板前视光电变焦：倍率越大鼠标越慢（准星在画面上走得一样快）
    st.zoomS = st.zoomS + ((((st.uav and st.dcam == "nose") or st.eo) and st.zoom or 1) - st.zoomS) * math.min(1, dt * 8)
    if st.uav or st.eo then md = md / st.zoomS end
    if st.eo then   -- 光电：鼠标只转吊舱（飞机按自动驾驶飞）
      st.eoYaw -= md.X * SENS
      st.eoPitch = clamp(st.eoPitch - md.Y * SENS, -1.5, 0.35)
    else
      if d.kind == "jet" and not G.mobile then   -- 鼠标只环视：松开 0.8 秒后镜头慢慢回到机尾
        if md.Magnitude > 0.5 then st.lkT = os.clock() end
        st.lkY = clamp(st.lkY - md.X * SENS, -math.pi, math.pi)
        st.lkP = clamp(st.lkP - md.Y * SENS, -1.2, 1.2)
        if os.clock() - st.lkT > 0.8 then
          local k = math.exp(-dt * 2.5)
          st.lkY, st.lkP = st.lkY * k, st.lkP * k
        end
      end
      -- 直升机：镜头跟着机头一起转（A / D 转向时视角不留在原地），鼠标在这上面加减——瞄机头炮塔
      if d.kind == "heli" and st.yawSeen then st.camYaw += angDiff(st.yawSeen, st.yaw) end
      st.yawSeen = st.yaw
      st.camYaw -= md.X * SENS
      st.camPitch = clamp(st.camPitch - md.Y * SENS, -1.2, 0.9)
    end
    -- 飞
    if st.pilot and not st.crashed then
      if d.kind == "jet" then jetPhysics(dt) else heliPhysics(dt) end
      -- 撞楼、撞舰岛：沿着速度方向打一条射线
      local stepV = st.vel * dt * 1.6
      if stepV.Magnitude > 0.5 and not st.ground then
        local res = workspace:Raycast(st.cf.Position, stepV + stepV.Unit * d.L * 0.4, mapParams)
        if res and res.Normal.Y < 0.6 then crash() end
      end
      -- 飞出作战区（±Map.PLAY，约 5 公里）：自动掉头（喷气机掉头半径七八百格）；再往外硬拦住（服务器在 Map.PLAY + 1200 以外不认）
      local p = st.cf.Position
      local lim = Map.PLAY
      st.oob = math.abs(p.X) > lim or math.abs(p.Z) > lim
      if st.oob and d.kind == "jet" then
        local back = V(-p.X, 0, -p.Z).Unit
        st.aimYaw = math.atan2(-back.X, -back.Z)
        st.aimPitch = 0.05
      end
      local hard = Map.PLAY + 1000
      if math.abs(p.X) > hard or math.abs(p.Z) > hard then
        st.cf = st.cf - p + V(math.clamp(p.X, -hard, hard), p.Y, math.clamp(p.Z, -hard, hard))
        if d.kind == "heli" then st.hv = V() end
      end
      if p.Y > 2600 then st.cf = st.cf - V(0, p.Y - 2600, 0) end
    else
      st.cf = st.em.Root.CFrame   -- 坐在后面：跟着服务器
    end
    -- 镜头
    local pos = st.cf.Position
    if st.eo then
      -- 光电吊舱：机腹下面（固定翼）/ 机头下面的光电球（直升机），视线稳定在世界方向上，不画镜头抖动
      local eye = (d.kind == "jet") and (st.cf * CF(0, -d.H * 0.5 - 0.6, -d.L * 0.12)).Position or (st.cf * CF(0, -d.H * 0.3, -d.L * 0.5 - 0.8)).Position
      cam.CFrame = CFrame.lookAt(eye, eye + eoDir() * 100)
    elseif st.uav and st.dcam == "nose" then
      -- 无人机前视光电（机头下面的光电球）：顺着鼠标想去的方向看（手机上就是机头方向），不画镜头抖动
      local eye = (st.cf * CF(0, -d.H * 0.22, -d.L * 0.5 - 0.8)).Position
      local look = G.mobile and st.cf.LookVector or aimDirNow()
      cam.CFrame = CFrame.lookAt(eye, eye + look * 100)
    elseif d.kind == "jet" and not G.mobile and st.pilot then
      -- 镜头在机尾后上方顺着机头看（鼠标环视在这上面转）；地平线跟着坡度歪三成，翻筋斗时不乱翻
      local lk = st.cf.LookVector
      local nYaw, nPitch = math.atan2(-lk.X, -lk.Z), math.asin(clamp(lk.Y, -1, 1))
      local aim = (CFrame.Angles(0, nYaw + st.lkY, 0) * CFrame.Angles(clamp(nPitch * (1 - math.min(1, math.abs(st.lkY))) + st.lkP, -1.5, 1.5), 0, 0)).LookVector
      local back = d.L * 1.3 + 26
      -- 镜头带弹簧慢半拍跟上，加速度把镜头往反方向甩开一点（转弯时飞机在画面里往外偏、拉起时往下沉）；大过载、加力时轻轻抖
      local want = -aim * back + V(0, d.H * 0.9 + 7, 0)
      st.camOff = st.camOff and st.camOff:Lerp(want, 1 - math.exp(-dt * 7)) or want
      local acc = st.accV or V()
      local push = -acc * 0.014
      if push.Magnitude > 7 then push = push.Unit * 7 end
      st.camPush = (st.camPush or push):Lerp(push, 1 - math.exp(-dt * 4))
      local camPos = pos + st.camOff + st.camPush
      local gl = acc.Magnitude / GR   -- 大概几个 g
      local amp = math.clamp((gl - 3) * 0.0016, 0, 0.012) + ((st.thrE or 0) > 100 and 0.0012 or 0)
      local t = os.clock()
      local shake = CFrame.Angles(math.noise(t * 18, 1.3) * amp, math.noise(t * 18, 7.1) * amp, 0)
      local upC = (V(0, 1, 0) * 0.7 + st.cf.UpVector * 0.3)
      cam.CFrame = CFrame.lookAt(camPos, pos + aim * 300, (upC.Magnitude > 0.1) and upC.Unit or V(0, 1, 0)) * shake
    elseif d.kind == "jet" then
      local camPos = (st.cf * CF(0, d.H * 0.9 + 7, d.L * 1.3 + 26)).Position
      cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(camPos, (st.cf * CF(0, 4, -300)).Position), math.min(1, dt * 8))
    else
      local dirCam = CFrame.Angles(0, st.camYaw, 0) * CFrame.Angles(st.camPitch, 0, 0)
      local camPos = pos + V(0, d.H * 0.5, 0) + dirCam:VectorToWorldSpace(V(0, 0, d.L * 1.1 + 18))
      cam.CFrame = CFrame.lookAt(camPos, camPos + dirCam.LookVector)
    end
    local fovT = (d.kind == "jet") and math.clamp(70 + st.spd / d.vMax * 10, 70, 82) or 70
    if (st.uav and st.dcam == "nose") or st.eo then fovT = 70 / st.zoomS end
    cam.FieldOfView = cam.FieldOfView + (fovT - cam.FieldOfView) * math.min(1, dt * ((st.uav and 10) or 4))
    -- 瞄准点：镜头中间（固定翼：鼠标瞄准方向）打出去碰到的地方
    local ex = { G.viewFolder }
    if me.Character then table.insert(ex, me.Character) end
    table.insert(ex, st.em)
    aimParams.FilterDescendantsInstances = ex
    local adir = lookDir()
    local o = (d.kind == "jet" and not st.eo) and pos or cam.CFrame.Position
    local res = workspace:Raycast(o + adir * (d.L * 0.6), adir * 4000, aimParams)
    st.aimPt = res and res.Position or (o + adir * 4000)
    -- 机头炮塔：跟着瞄准点转（鼠标瞄）
    local gid, gw = gunW()
    local wid, w = storeW()
    if d.gunPos and gw and gw.turret then
      local l = st.cf:PointToObjectSpace(st.aimPt) - d.gunPos
      st.ty = clamp(deg(math.atan2(l.X, -l.Z)), -110, 110)
      st.gp = clamp(deg(math.atan2(l.Y, math.sqrt(l.X * l.X + l.Z * l.Z))), -60, 11)
    end
    st.c.ty, st.c.gp = st.ty, st.gp
    -- 弹舱门
    local bm, bs = false, false
    if wid then bm, bs = bayOf(wid) end
    st.bay = approach(st.bay, bm and 1 or 0, dt * 2.5)
    st.bayS = approach(st.bayS, bs and 1 or 0, dt * 2.5)
    st.c.bay, st.c.bayS = st.bay, st.bayS
    -- 开火：鼠标左键 机炮按住连发（扳机发给服务器）；F 挂的弹一下一发（火箭按住连发）。没有炮的飞机左键也发挂的弹
    --   手机：开火键按选中的那种（选的是炮就打炮）
    if st.pilot then
      local _, cw = curW()
      local touchGun = touch and touch.fire and cw and cw.kind == "gun"
      local gunOn = gid ~= nil and ((st.firing and not G.mobile) or touchGun or false)
      if gid then setTrig(gunOn) end
      local fireS = st.missile or (st.firing and not gid) or (touch and touch.fire and not touchGun)
      if w and fireS then
        if w.kind == "rkt" or not st.fireLatch then fireStore(wid, w) end
        st.fireLatch = true
      else
        st.fireLatch = false
      end
    end
    -- 锁定：选中的弹要锁的话，目标在视场里待够锁定时间
    if st.pilot and w and (w.kind == "aam" or w.kind == "agm" or (w.kind == "bomb" and w.guided)) then
      if st.lock and (not st.lock.em.Parent or st.lock.em:GetAttribute("Wreck")) then st.lock = nil end
      if st.lock then
        local root = st.lock.em:FindFirstChild("Root")
        if root then
          local to = root.CFrame.Position - pos
          st.lock.dir, st.lock.dist, st.lock.pos = to.Unit, to.Magnitude, root.CFrame.Position
          if inCone(w, st.lock) and st.lock.dist < (w.range or 3200) * 1.1 then st.lockT += dt else st.lock, st.lockT = nil, 0 end
        else
          st.lock = nil
        end
      end
      if not st.lock then
        st.lock = pickTarget(w)
        st.lockT = 0
      end
    else
      st.lock, st.lockT = nil, 0
    end
    -- 报给服务器（每秒 15 次）
    st.sendT -= dt
    if st.sendT <= 0 and st.pilot and not st.crashed then
      st.sendT = 1 / 15
      local c = st.c
      G.R.Drive:FireServer({ op = "state", cf = st.cf, v = st.vel, gd = st.ground, aim = st.aimPt, thr = c.thr, gear = c.gear, flap = c.flap, cp = c.pit, cr = c.rol,
        cy = c.yaw, bay = c.bay, bays = c.bayS, rpm = c.rpm, col = c.col, can = c.can, hook = c.hook, brk = c.brk, ty = c.ty, gp = c.gp, fold = c.fold })
    end
    -- 平显
    local em = st.em
    local hp, mx = em:GetAttribute("Hp") or 1, em:GetAttribute("MaxHp") or 1
    hpBar.Size = UDim2.fromScale(clamp(hp / mx, 0, 1), 1)
    hpBar.BackgroundColor3 = ui.hpColor(hp / mx)
    aName.Text = T("veh." .. d.id) .. (st.pilot and "" or ("   " .. T("air.passenger")))
    local kmh = math.floor(st.vel.Magnitude / AD.M * 3.6 + 0.5)
    local agl = math.floor((pos.Y - ground(pos.X, pos.Z) - d.gearH) / AD.M + 0.5)
    aInfo.Text = T("ui.speed", kmh) .. "    " .. T("air.alt", math.max(0, agl)) .. "    " .. T("air.flares", st.flares) .. "    " .. T("air.fuelP", math.floor((st.fuel + st.fuelX) * 100 + 0.5))
      .. ((d.kind == "jet") and ("    " .. T("air.gearState." .. ((st.gearWant > 0.5) and "down" or "up"))) or "")
    if wid then
      aWpn.Text = "F  [" .. st.wi .. "/" .. #st.wl .. "] " .. T("aw." .. wid) .. "  ×" .. left(wid) .. (gid and ("    " .. T("air.mouseGun", T("aw." .. gid), left(gid))) or "")
    elseif gid then
      aWpn.Text = T("air.mouseGun", T("aw." .. gid), left(gid))
    else
      aWpn.Text = T("air.noWeapon")
    end
    st.help = st.pilot and (st.uav and "air.helpUav" or ((d.kind == "jet") and "air.helpJet" or "air.helpHeli")) or "air.helpPass"
    if st.pilot then
      spdText.Text = string.format("%d", kmh)
      altText.Text = string.format("%d", math.max(0, agl))
      thrText.Text = (d.kind == "jet") and ((st.thr > 100) and T("air.ab") or string.format("%d%%", math.floor(st.thr + 0.5))) or string.format("RPM %d%%", math.floor(st.rpm))
      vsText.Text = string.format("%+d", math.floor(st.vel.Y / AD.M + 0.5))
      -- 油量：内油 %（+ 副油箱 %）、照现在的油门还能飞几分几秒；少于两成半变黄、一成变红
      local tot = st.fuel + st.fuelX
      local rate = AD.burn(d, (d.kind == "heli") and 100 or st.thr, st.c.col or 0, (d.kind == "heli") and st.rpm or st.thr, st.vel.Magnitude / math.max(d.vMax, 1), st.ground)
      local secs = (rate > 0) and tot / rate or math.huge
      local left2 = (secs < 5999) and string.format("%d:%02d", math.floor(secs / 60), math.floor(secs % 60)) or "--:--"
      fuelText.Text = T("air.fuel", math.floor(st.fuel * 100 + 0.5)) .. ((st.fuelX > 0) and string.format(" +%d", math.floor(st.fuelX * 100 + 0.5)) or "") .. "  " .. left2
      fuelText.TextColor3 = (tot < 0.1) and RGB(255, 90, 80) or ((tot < 0.25) and RGB(255, 200, 90) or HUD)
      local bp, bon = project(pos + st.cf.LookVector * 400)
      bore.Position, bore.Visible = bp, bon and not st.eo
      -- 大圈：圈心在机头指向；大小是选中武器能锁的离轴角（导弹的导引头）/ 航炮、火箭、炸弹的瞄准圈；圈底下写武器和剩几发
      local rdeg = (not w and 3) or (w.kind == "rkt" and 5) or (w.kind == "bomb" and 9) or (w.cone or 20)
      if d.kind == "heli" and w and w.kind == "agm" then rdeg += 20 end
      local vh = cam.ViewportSize.Y
      local px = clamp(vh / math.tan(rad(cam.FieldOfView / 2)) * math.tan(rad(math.min(rdeg, 55))), 110, vh * 0.86)
      ring.Size, ring.Position, ring.Visible = UDim2.fromOffset(px, px), bp, bon and not st.eo and not st.uav
      ringText.Position, ringText.Visible = bp + UDim2.fromOffset(0, px / 2 + 6), bon and not st.eo and not st.uav
      ringText.Text = wid and (T("aw." .. wid) .. "  ×" .. left(wid)) or (gid and (T("aw." .. gid) .. "  ×" .. left(gid))) or ""
      local lk = st.cf.LookVector
      hdgText.Text = string.format("%03d", math.floor((math.deg(math.atan2(lk.X, -lk.Z)) + 360) % 360 + 0.5) % 360)
      -- 右侧武器栏：剩几发、选中的那行亮、打光了变灰
      for _, r in ipairs(wRows) do
        local n = r.it.flare and st.flares or left(r.it.wid)
        r.cnt.Text = "×" .. n
        local sel = r.it.idx == st.wi
        r.f.BackgroundColor3, r.f.BackgroundTransparency = sel and RGB(20, 96, 44) or RGB(0, 18, 6), sel and 0.3 or 0.6
        r.s.Transparency, r.s.Thickness = sel and 0 or 0.7, sel and 2 or 1
        local col = (n <= 0) and RGB(110, 130, 112) or HUD
        r.cnt.TextColor3, r.nm.TextColor3 = col, col
      end
      -- 光电画面的字：模式、倍率、目标距离、吊舱相对机头的方位 / 俯仰
      if st.eo then
        eoMode.Text = T("eo.title") .. "  " .. T("eo." .. EO_MODES[st.eoMode or 1]) .. string.format("   ×%.1f", st.zoomS)
        local rel = st.cf:VectorToObjectSpace(eoDir())
        local az, el = math.deg(math.atan2(rel.X, -rel.Z)), math.deg(math.asin(clamp(rel.Y, -1, 1)))
        eoInfo.Text = string.format("%s %dm   %+d° %+d°", T("eo.range"), math.floor((st.aimPt - cam.CFrame.Position).Magnitude / AD.M + 0.5), math.floor(az + 0.5), math.floor(el + 0.5))
        eoHint.Text = T("eo.hint")
      end
      if st.eo or (st.uav and st.dcam == "nose") then
        aimRing.Visible = false   -- 光电 / 前视光电：镜头就是瞄准方向，画十字线
      elseif d.kind == "jet" then   -- 固定翼：准星就是机头（bore），不另画鼠标瞄准圈
        aimRing.Visible = false
      else
        aimRing.Position, aimRing.Visible = UDim2.fromScale(0.5, 0.5), d.kind == "heli"
      end
      -- 警告
      local warn = nil
      if st.rwrT and os.clock() < st.rwrT then warn = ((os.clock() * 4) % 1 < 0.6) and T("air.missile") or ""
      elseif st.out and not st.ground then warn = T("air.flameout")
      elseif st.oob then warn = T("air.oob")
      elseif d.kind == "jet" and not st.ground and st.spd < d.stall * 1.05 then warn = T("air.stall")
      elseif not st.ground and agl < 60 and st.vel.Y < -25 then warn = T("air.pullup")
      elseif not st.ground and st.fuel + st.fuelX < 0.12 then warn = ((os.clock() * 2) % 1 < 0.6) and T("air.bingo") or "" end   -- 油不多了：该回去了
      warnText.Text = warn or ""
      warnText.Visible = warn ~= nil
      -- 降落引导：起落架放着、在天上：最近的能落的地方画个菱形，旁边写公里数；菱形按下滑道（3.5°）变色——绿正好、黄偏高、红偏低
      local site = nil
      if d.kind == "jet" and not st.ground and st.gearWant > 0.5 then
        local bd = math.huge
        for _, s2 in ipairs(landSites()) do
          local dd = (V(s2.p.X, 0, s2.p.Z) - V(pos.X, 0, pos.Z)).Magnitude
          if dd < bd then site, bd = s2, dd end
        end
        if site then
          local lp, lon = project(site.p + V(0, 1, 0))
          landMark.Position, landMark.Visible = lp, lon
          landText.Position, landText.Visible = lp + UDim2.fromOffset(0, 22), lon
          local ideal = bd * math.tan(rad(3.5))
          local dh = (pos.Y - d.gearH - site.p.Y) - ideal
          local tol = ideal * 0.35 + 18
          local col = (dh > tol) and RGB(255, 200, 90) or ((dh < -tol) and RGB(255, 90, 80) or RGB(120, 230, 140))
          landMark.TextColor3, landText.TextColor3 = col, col
          landText.Text = string.format("%.1f", bd / AD.M / 1000)
        end
      end
      if not site then landMark.Visible, landText.Visible = false, false end
      -- 锁定框
      if st.lock then
        local lp, lon = project(st.lock.pos)
        local locked = st.lockT >= (w.lockTime or 1)
        lockBox.Position, lockBox.Visible = lp, lon
        lockStroke.Color = locked and RGB(255, 80, 70) or HUD
        lockBox.Size = locked and UDim2.fromOffset(38, 38) or UDim2.fromOffset(52, 52)
        lockText.Position = lp + UDim2.fromOffset(0, 30)
        lockText.Visible = lon
        lockText.Text = locked and (T("air.locked") .. string.format("  %dm", math.floor(st.lock.dist / AD.M))) or T("air.locking", math.floor(st.lockT / (w.lockTime or 1) * 100))
        lockText.TextColor3 = locked and RGB(255, 80, 70) or HUD
      else
        lockBox.Visible, lockText.Visible = false, false
      end
      -- 炸弹落点（不制导的、或者没锁上的制导炸弹）
      if w and w.kind == "bomb" and not (st.lock and st.lockT >= (w.lockTime or 1)) then
        local h = pos.Y - math.max(ground(pos.X, pos.Z), 0)
        local vy = -st.vel.Y
        local tf = (vy + math.sqrt(math.max(0, vy * vy + 2 * GR * math.max(h, 0)))) / GR
        local hit = pos + V(st.vel.X, 0, st.vel.Z) * tf * 0.97
        local gp2, gon = project(V(hit.X, ground(hit.X, hit.Z), hit.Z))
        pipper.Position, pipper.Visible = gp2, gon
      else
        pipper.Visible = false
      end
    end
  end

  -- 被击毁 / 跳伞：服务器推来 alive = false 或 veh = nil，下一帧 stop()
end

return Fly
