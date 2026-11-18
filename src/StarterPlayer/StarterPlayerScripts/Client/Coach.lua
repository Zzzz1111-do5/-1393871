-- Roblox全面大战场（客户端）——新手指导（用户：照你给的建议优化上手；不加「简单 / 真实」切换）
--   ① 屏幕最下面一排按键提示（代替原来那一整行说明）：按现在在干什么只给 3～5 个最要紧的键——步行、开车、气垫艇、
--      开飞机（跑道上 / 天上 / 低空要降落）、直升机（旋翼还没转起来 / 能飞了）、无人机、开船、炮位、火炮、坐后座；
--      状态一变就换，进来 25 秒（看过三步卡的 10 秒）后收成一个「F1 全部按键」；跑道上、要降落、旋翼没转起来这几种一直显示。
--      步行只在头三次出生时显示 8 秒（用户以前说过：持枪第一视角不要显示鼠标、键位）；离当前目标很远时提示一次「H 重新部署」
--   ② F1：这一状态的全部按键 + 通用键（原来最下面那行说明的全文，按「·」拆成一格一格），再按 F1 关上
--   ③ 第一次上某种载具（坦克装甲车、气垫艇、飞机、直升机、无人机、舰艇、炮位、火炮）在左边弹「三步上手」卡：回车 / 点按钮关上，
--      看够 4 秒或者关上就算看过，存档记住（服务器 Store.lua 的 seen → 玩家属性 Seen）
--   ④ 当前目标不在画面里时，屏幕边上一个箭头指过去（据点字母 + 距离）
--   ⑤ 夜里分得清：附近队友头顶一个队色小三角；自己队能开的空车标「可驾驶」（走近了有 Roblox 的「E 上车」提示，就不再标）
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local Coach = {}

function Coach.init(G)
  local ui = G.ui
  local hud = G.hudParts and G.hudParts.hud
  if not (ui and hud and G.gui) then return end
  local Config, Map = G.Config, G.Map
  local AD = require(RS:WaitForChild("AirDefs"))
  local me = Players.LocalPlayer
  local pg = me:WaitForChild("PlayerGui")
  local RGB = Color3.fromRGB
  local V2 = Vector2.new
  local V3 = Vector3.new
  local WHITE = Color3.new(1, 1, 1)
  local TEXT, MUTE = RGB(232, 236, 238), RGB(160, 166, 170)
  local M_PER = AD.M or 2.8
  local mobile = G.mobile == true
  local clock = os.clock
  local function T(k, ...) return G.T(k, ...) end
  local function teamColor(t) return Config.Teams[(t == "def") and "def" or "atk"].color end
  G.coachOn = not mobile   -- UI.lua：有按键提示就不画最下面那一整行说明（手机上是触屏按钮，本来就不画）

  -- 字的大概宽度（中日韩字一个字号宽，其余半个多）：按键格子、提示条按它排
  local function textW(s, size)
    local w = 0
    for _, c in utf8.codes(s) do w += (c < 0x2E80) and size * 0.56 or size end
    return math.ceil(w)
  end
  local function split(s, sep)
    local out, i = {}, 1
    while true do
      local a, b = string.find(s, sep, i, true)
      if not a then table.insert(out, string.sub(s, i)) break end
      table.insert(out, string.sub(s, i, a - 1))
      i = b + 1
    end
    return out
  end
  local function trim(s) return string.match(s, "^%s*(.-)%s*$") end

  ---------------------------------------------------------------- 现在在干什么

  -- 步行 inf、开车 veh、气垫艇 lcac、飞机 jet、直升机 heli、无人机 uav、开船 ship、炮位 fort、火炮 arty、坐后座 pass；没活着 nil
  local function modeNow()
    local S = G.S
    if not (S and S.alive) then return nil end
    local d = G.drive
    if not d then return "inf" end
    if d == G.fly then
      if not d.pilot then return "pass" end
      if d.uav then return "uav" end
      return (d.d and d.d.kind == "jet") and "jet" or "heli"
    end
    if d == G.sail then return "ship" end
    if d == G.gunner then return (d.help == "ui.howHelp") and "arty" or "fort" end
    return d.hv and "lcac" or "veh"
  end
  G.coachMode = modeNow   -- 测试用

  -- 同一状态里再细分：飞机在跑道上 / 低空要降落（起落架收着、在往下掉），直升机旋翼还没转起来
  local function subOf(mode)
    local f = G.fly
    if mode == "jet" and f then
      if f.ground then return "jetGround" end
      if (f.gearWant or 1) < 0.5 and (f.aglM or 999) < 90 and f.vel and f.vel.Y < -2 then return "jetLand" end
    elseif mode == "heli" and f then
      if (f.rpm or 100) < 92 then return "heliSpool" end
    end
    return mode
  end
  local STICKY = { jetGround = true, jetLand = true, heliSpool = true }   -- 这几种不收起来

  -- 每种状态的几个键：{ 键, 文字编号 }；键是 LMB / RMB / Space / Mouse 的按语言写，nil = 只有一句话
  local KEYN = { LMB = "key.lmb", RMB = "key.rmb", Space = "key.space", Mouse = "key.mouse" }
  local HINTS = {
    inf = { { "LMB", "coach.fire" }, { "RMB", "coach.aim" }, { "R", "coach.reload" }, { "E", "coach.board" }, { "F1", "coach.allKeys" } },
    veh = { { "W/S", "coach.drive" }, { "A/D", "coach.steer" }, { "LMB", "coach.fire" }, { "Shift", "coach.sight" }, { "Space", "coach.exit" } },
    lcac = { { "W/S", "coach.throttle" }, { "A/D", "coach.steer" }, { nil, "coach.lcacBeach" }, { "Space", "coach.exit" } },
    jetGround = { { "W", "coach.throttleUp" }, { "A/D", "coach.taxi" }, { "Mouse", "coach.rotate" }, { "S", "coach.reverse" } },
    jet = { { "Mouse", "coach.aimSteer" }, { "W/S", "coach.speed" }, { "A/D", "coach.roll" }, { "LMB", "coach.gun" }, { "F", "coach.missile" } },
    jetLand = { { "G", "coach.gearDown" }, { "S", "coach.throttleDown" } },
    heliSpool = { { nil, "coach.spool" } },
    heli = { { "Mouse", "coach.nose" }, { "E/Q", "coach.updown" }, { "W/S", "coach.cyclic" }, { "A/D", "coach.strafe" }, { "LMB", "coach.gun" } },
    uav = { { "Mouse", "coach.aimSteer" }, { "W/S", "coach.speed" }, { "A/D", "coach.roll" }, { "LMB", "coach.gun" }, { "F", "coach.missile" }, { "Space", "coach.stowPad" } },
    ship = { { "W/S", "coach.telegraph" }, { "A/D", "coach.rudder" }, { "LMB", "coach.fire" }, { "2", "coach.asm" }, { "Space", "coach.leaveShip" } },
    fort = { { "Mouse", "coach.aim" }, { "LMB", "coach.fire" }, { "RMB", "coach.sight" }, { "Space", "coach.leave" } },
    arty = { { "Mouse", "coach.pointTarget" }, { "LMB", "coach.fire" }, { "RMB", "coach.zoom" }, { "Space", "coach.leave" } },
    pass = { { "Mouse", "coach.look" }, { "Space", "coach.bail" } },
    far = { { "H", "coach.redeploy" } },
  }
  -- F1 面板里的全文（各操作模块自己的那一行说明；开车时 G.drive.help 优先）
  local FULL = { inf = "ui.help", veh = "ui.vehHelp", lcac = "ui.lcacHelp", jet = "air.helpJet", heli = "air.helpHeli", uav = "air.helpUav",
    ship = "ship.help", fort = "ui.fortHelp", arty = "ui.howHelp", pass = "air.helpPass" }
  local function vRotKmh(f)
    return math.floor(((f and f.d and f.d.vRot) or 0) / M_PER * 3.6 + 0.5)
  end
  local function keyText(k) return k and (KEYN[k] and T(KEYN[k]) or k) or nil end
  local function hintList(sub)
    local out = {}
    for _, h in ipairs(HINTS[sub] or {}) do
      local txt = (h[2] == "coach.rotate") and T(h[2], vRotKmh(G.fly)) or T(h[2])
      table.insert(out, { keyText(h[1]), txt })
    end
    return out
  end

  ---------------------------------------------------------------- 三步卡看过没有（服务器存档 → 玩家属性 Seen，逗号隔开）

  local seenLocal = {}
  local function isSeen(k)
    if seenLocal[k] then return true end
    local a = me:GetAttribute("Seen")
    return type(a) == "string" and string.find("," .. a .. ",", "," .. k .. ",", 1, true) ~= nil
  end
  local function markSeen(k)
    if seenLocal[k] then return end
    seenLocal[k] = true
    G.R.Act:FireServer("seen", k)
  end

  ---------------------------------------------------------------- ① 最下面一排按键

  local bar = Instance.new("Frame")
  bar.Name = "CoachKeys"
  bar.BackgroundTransparency = 1
  bar.AnchorPoint = V2(0.5, 1)
  bar.Position = UDim2.new(0.5, 0, 1, -6)
  bar.Size = UDim2.fromOffset(10, 22)
  bar.Visible = false
  bar.Parent = hud
  -- 一个按键格子：深色圆角块 + 白字（键）
  local function keyCap(parent, key, x, y, dim)
    local kw = math.max(22, textW(key, 12) + 12)
    local k = ui.frame(parent, UDim2.fromOffset(kw, 20), UDim2.fromOffset(x, y), RGB(30, 34, 38), dim and 0.45 or 0.12)
    k.Name = "Cap"
    ui.round(k, 4)
    ui.stroke(k, WHITE, 1, dim and 0.85 or 0.7)
    local kl = ui.label(k, key, UDim2.fromScale(1, 1), nil, 12, WHITE, Enum.Font.GothamBold)
    kl.Name = "Key"
    kl.TextWrapped = false
    kl.TextTransparency = dim and 0.35 or 0
    return kw
  end
  local barSig = nil
  local function setChips(list, dim)
    local sig = (dim and "d|" or "|")
    for _, h in ipairs(list) do sig ..= (h[1] or "") .. "=" .. h[2] .. ";" end
    if sig == barSig then return end
    barSig = sig
    for _, c in ipairs(bar:GetChildren()) do c:Destroy() end
    local x = 0
    for i, h in ipairs(list) do
      local c = Instance.new("Frame")
      c.Name = "Chip" .. i
      c.BackgroundTransparency = 1
      c.Position = UDim2.fromOffset(x, 0)
      c.Parent = bar
      local w = 0
      if h[1] then w = keyCap(c, h[1], 0, 1, dim) + 6 end
      local tw = textW(h[2], 13)
      local tl = ui.label(c, h[2], UDim2.fromOffset(tw + 4, 22), UDim2.fromOffset(w, 0), 13, TEXT, Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left)
      tl.Name = "Text"
      tl.TextWrapped = false
      tl.TextStrokeTransparency = 0.6
      tl.TextTransparency = dim and 0.4 or 0
      w += tw + 4
      c.Size = UDim2.fromOffset(w, 22)
      x += w + 16
    end
    bar.Size = UDim2.fromOffset(math.max(10, x - 16), 22)
  end

  ---------------------------------------------------------------- ② F1 全部按键

  local panel = ui.frame(G.gui, UDim2.fromOffset(640, 300), UDim2.fromScale(0.5, 0.46), RGB(8, 10, 12), 0.08, V2(0.5, 0.5))
  panel.Name = "CoachPanel"
  panel.ZIndex = 35
  panel.Visible = false
  ui.stroke(panel, WHITE, 1, 0.85)
  local pTitle = ui.label(panel, "", UDim2.new(1, -150, 0, 24), UDim2.fromOffset(24, 16), 18, WHITE, Enum.Font.GothamBold, nil, Enum.TextXAlignment.Left)
  pTitle.Name = "Title"
  pTitle.TextWrapped = false
  local pClose = ui.label(panel, "", UDim2.fromOffset(120, 18), UDim2.new(1, -24, 0, 20), 12, MUTE, Enum.Font.GothamMedium, V2(1, 0), Enum.TextXAlignment.Right)
  pClose.TextWrapped = false
  local pBody = Instance.new("Frame")
  pBody.Name = "Body"
  pBody.BackgroundTransparency = 1
  pBody.Position = UDim2.fromOffset(24, 56)
  pBody.Size = UDim2.new(1, -48, 1, -72)
  pBody.Parent = panel
  -- 说明里一格「W/S 前后」拆成键和动作：前面连着的几个「像键的词」（大写字母 / 数字 / 左键 右键 空格 鼠标 滚轮 / 斜杠）算键
  local KEYWORD = { ["左键"] = true, ["右键"] = true, ["空格"] = true, ["鼠标"] = true, ["滚轮"] = true, ["/"] = true,
    Mouse = true, Wheel = true, wheel = true, Space = true, LMB = true, RMB = true, Tab = true, Enter = true, Shift = true, Ctrl = true, Alt = true, ["Shift/Ctrl"] = true }
  local function keyPart(entry)
    local toks = {}
    for t in string.gmatch(entry, "%S+") do table.insert(toks, t) end
    local n = 0
    for i, t in ipairs(toks) do
      local norm = string.gsub(t, "–", "-")
      if KEYWORD[t] or string.match(norm, "^[%u%d][%u%d/%-]*$") then n = i else break end
    end
    while n > 0 and toks[n] == "/" do n -= 1 end
    if n == 0 then return "", entry end
    return table.concat(toks, " ", 1, n), table.concat(toks, " ", n + 1)
  end
  local function entries(parent, text, y0)
    local i, y = 0, y0
    for _, e in ipairs(split(text, "·")) do
      e = trim(e)
      if e ~= "" then
        local col, row = i % 2, i // 2
        local key, act = keyPart(e)
        local x, yy = col * 300, y0 + row * 28
        local kx = 0
        if key ~= "" then kx = keyCap(parent, key, x, yy + 2, false) + 8 end
        local l = ui.label(parent, act, UDim2.fromOffset(290 - kx, 24), UDim2.fromOffset(x + kx, yy), 13, TEXT, Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left)
        l.Name = "Entry"
        l.TextWrapped = false
        l.TextTruncate = Enum.TextTruncate.AtEnd
        y = yy + 28
        i += 1
      end
    end
    return y
  end
  local panelMode = false   -- false：关着；否则开着时是哪个状态（nil 也算开着：按 inf 写）
  local panelOpen = false
  local function buildPanel(mode)
    for _, c in ipairs(pBody:GetChildren()) do c:Destroy() end
    local m = mode or "inf"
    local hk = FULL[m] or "ui.help"
    if mode and mode ~= "inf" and G.drive and G.drive.help then hk = G.drive.help end
    pTitle.Text = T("coach.panel", T("coach.mode." .. m))
    pClose.Text = T("coach.panelClose")
    local y = entries(pBody, T(hk), 0)
    local div = ui.frame(pBody, UDim2.new(1, 0, 0, 1), UDim2.fromOffset(0, y + 6), WHITE, 0.88)
    div.Name = "Div"
    local ct = ui.label(pBody, T("coach.commonTitle"), UDim2.fromOffset(200, 16), UDim2.fromOffset(0, y + 14), 11, MUTE, Enum.Font.GothamBold, nil, Enum.TextXAlignment.Left)
    ct.TextWrapped = false
    y = entries(pBody, T("coach.common"), y + 36)
    panel.Size = UDim2.fromOffset(640, y + 76)
    panelMode = mode
  end
  local function setPanel(on)
    panelOpen = on
    if on then buildPanel(modeNow()) end
    panel.Visible = on
  end
  G.coachPanel = function(on) if on == nil then return panelOpen end setPanel(on) end

  ---------------------------------------------------------------- ③ 第一次上某种载具：三步上手

  local CARDS = { veh = true, lcac = true, jet = true, heli = true, uav = true, ship = true, fort = true, arty = true }
  local card = ui.frame(G.gui, UDim2.fromOffset(392, 232), UDim2.new(0, 24, 0.28, 0), RGB(8, 10, 12), 0.1)
  card.Name = "CoachCard"
  card.ZIndex = 20
  card.Visible = false
  ui.stroke(card, WHITE, 1, 0.85)
  local accent = ui.frame(card, UDim2.new(0, 3, 1, 0), nil, WHITE, 0)
  local cTitle = ui.label(card, "", UDim2.new(1, -40, 0, 22), UDim2.fromOffset(22, 14), 17, WHITE, Enum.Font.GothamBold, nil, Enum.TextXAlignment.Left)
  cTitle.Name = "Title"
  cTitle.TextWrapped = false
  local cSub = ui.label(card, "", UDim2.new(1, -40, 0, 14), UDim2.fromOffset(22, 38), 11, MUTE, Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left)
  cSub.TextWrapped = false
  local cRows = {}
  for i = 1, 3 do
    local y = 62 + (i - 1) * 44
    local badge = ui.frame(card, UDim2.fromOffset(20, 20), UDim2.fromOffset(22, y + 1), WHITE, 0.82)
    ui.round(badge, 10)
    ui.label(badge, tostring(i), UDim2.fromScale(1, 1), nil, 11, WHITE, Enum.Font.GothamBold)
    local l = ui.label(card, "", UDim2.new(1, -76, 0, 40), UDim2.fromOffset(52, y), 13, TEXT, Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left)
    l.Name = "Step" .. i
    l.TextYAlignment = Enum.TextYAlignment.Top
    cRows[i] = l
  end
  local gotIt = Instance.new("TextButton")
  gotIt.Name = "CoachGotIt"
  gotIt.Text = ""
  gotIt.BackgroundTransparency = 1
  gotIt.Size = UDim2.fromOffset(150, 26)
  gotIt.Position = UDim2.new(0, 22, 1, -12)
  gotIt.AnchorPoint = V2(0, 1)
  gotIt.Parent = card
  local gotKey = ui.frame(gotIt, UDim2.fromOffset(46, 20), UDim2.new(0, 0, 0.5, 0), RGB(40, 44, 48), 0.2, V2(0, 0.5))
  ui.round(gotKey, 4)
  local gotKeyL = ui.label(gotKey, "", UDim2.fromScale(1, 1), nil, 10, TEXT, Enum.Font.GothamBold)
  gotKeyL.TextWrapped = false
  local gotL = ui.label(gotIt, "", UDim2.fromOffset(96, 20), UDim2.new(0, 54, 0.5, 0), 12, TEXT, Enum.Font.GothamMedium, V2(0, 0.5), Enum.TextXAlignment.Left)
  gotL.TextWrapped = false
  local cMore = ui.label(card, "", UDim2.fromOffset(180, 20), UDim2.new(1, -20, 1, -15), 11, MUTE, Enum.Font.GothamMedium, V2(1, 1), Enum.TextXAlignment.Right)
  cMore.TextWrapped = false
  local cardMode, cardT0 = nil, 0
  local function closeCard(byUser)
    if cardMode and (byUser or clock() - cardT0 >= 4) then markSeen(cardMode) end
    cardMode = nil
    card.Visible = false
  end
  local function openCard(mode)
    cardMode, cardT0 = mode, clock()
    cTitle.Text = T("coach.cardTitle", T("coach.mode." .. mode))
    cSub.Text = T("coach.cardSub")
    for i = 1, 3 do
      local k = "coach.card." .. mode .. "." .. i
      cRows[i].Text = (mode == "jet" and i == 2) and T(k, vRotKmh(G.fly)) or T(k)
    end
    gotKeyL.Text, gotL.Text = T("hud.key.enter"), T("coach.gotIt")
    cMore.Text = T("coach.moreKeys")
    accent.BackgroundColor3 = teamColor(me:GetAttribute("Side"))
    card.Visible = true
  end
  gotIt.Activated:Connect(function() closeCard(true) end)
  G.coachCard = function() return cardMode end   -- 测试用

  -- 按键：F1 开关全部按键；回车关三步卡（Hud 的目标说明开着时回车归它）
  local function hudTipOpen()
    local t = hud:FindFirstChild("Tips")
    return t ~= nil and t.Visible
  end
  UIS.InputBegan:Connect(function(io, gp)
    if gp then return end
    if io.KeyCode == Enum.KeyCode.F1 then
      setPanel(not panelOpen)
    elseif io.KeyCode == Enum.KeyCode.Return and cardMode and not hudTipOpen() then
      closeCard(true)
    end
  end)

  ---------------------------------------------------------------- ④ 当前目标不在画面里：屏幕边上的箭头

  local arrow = Instance.new("Frame")
  arrow.Name = "ObjArrow"
  arrow.BackgroundTransparency = 1
  arrow.AnchorPoint = V2(0.5, 0.5)
  arrow.Size = UDim2.fromOffset(64, 64)
  arrow.Visible = false
  arrow.Parent = hud
  local aGlyph = ui.label(arrow, "▲", UDim2.fromOffset(28, 28), UDim2.fromScale(0.5, 0.5), 22, WHITE, Enum.Font.GothamBold, V2(0.5, 0.5))
  aGlyph.Name = "Glyph"
  aGlyph.TextStrokeTransparency = 0.4
  local aText = ui.label(arrow, "", UDim2.fromOffset(100, 16), UDim2.new(0.5, 0, 0.5, 20), 12, WHITE, Enum.Font.GothamBold, V2(0.5, 0))
  aText.Name = "Label"
  aText.TextWrapped = false
  aText.TextStrokeTransparency = 0.4
  local function pointPos(id)
    local cam = workspace.CurrentCamera
    local mp = cam:FindFirstChild("Obj_" .. id)   -- Hud.lua 放的据点标记（高度照地面找过）
    if mp then return mp.CFrame.Position end
    for _, p in ipairs(Map.POINTS) do
      if p.id == id then return V3(p.x, (p.y or 40) + 30, p.z) end
    end
    return nil
  end
  -- 指哪个：当前阶段开放的据点里，攻方先指还没拿下的、守方先指正被攻的，同样的取最近
  local function objective()
    local S = G.S
    local mine = (S and S.team) or me:GetAttribute("Side") or "atk"
    local cp = workspace.CurrentCamera.CFrame.Position
    local best, bd, bs, bp = nil, nil, nil, -1
    for _, s in ipairs((S and S.points) or {}) do
      if s.act ~= false and not s.locked then
        local pos = pointPos(s.id)
        if pos then
          local pri = (mine == "atk") and ((s.owner ~= "atk") and 1 or 0) or (((s.atk or 0) > 0) and 1 or 0)
          local d = (V3(pos.X, cp.Y, pos.Z) - cp).Magnitude
          if pri > bp or (pri == bp and d < bd) then best, bd, bs, bp = pos, d, s, pri end
        end
      end
    end
    return best, bd, bs
  end
  local function stepArrow(show)
    if not show then arrow.Visible = false return end
    local pos, dist, s = objective()
    if not pos then arrow.Visible = false return end
    local cam = workspace.CurrentCamera
    local vs = cam.ViewportSize
    local sp, onScreen = cam:WorldToViewportPoint(pos)
    local m = 70
    if onScreen and sp.Z > 0 and sp.X > m and sp.X < vs.X - m and sp.Y > m and sp.Y < vs.Y - m then
      arrow.Visible = false
      return
    end
    local rel = cam.CFrame:PointToObjectSpace(pos)
    local dx, dy = rel.X, -rel.Y
    if math.abs(dx) + math.abs(dy) < 1e-3 then dx, dy = 0, 1 end
    local ang = math.atan2(dy, dx)
    if rel.Z > 0 and math.abs(rel.X) < rel.Z * 0.25 then ang = math.pi / 2 end   -- 正后方：放在下沿
    local rx, ry = vs.X * 0.42, vs.Y * 0.36
    arrow.Position = UDim2.fromOffset(vs.X / 2 + math.cos(ang) * rx, vs.Y / 2 + math.sin(ang) * ry)
    aGlyph.Rotation = math.deg(ang) + 90   -- ▲ 本来朝上（−90°）
    local mine = (G.S and G.S.team) or "atk"
    local col = (s.owner == mine) and WHITE or teamColor(s.owner):Lerp(WHITE, 0.25)
    aGlyph.TextColor3 = col
    aText.Text = s.id .. "  " .. math.floor(dist / M_PER + 0.5) .. "m"
    arrow.Visible = true
  end

  ---------------------------------------------------------------- ⑤ 夜里分得清：队友头顶小三角、能开的空车

  local function billboard(name, w, h)
    local bb = Instance.new("BillboardGui")
    bb.Name = name
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.Size = UDim2.fromOffset(w, h)
    bb.ResetOnSpawn = false
    bb.Enabled = false
    bb.Parent = pg
    return bb
  end
  local mates, freeMarks = {}, {}
  local function mateMark(i)
    local m = mates[i]
    if m then return m end
    local bb = billboard("MateMark", 16, 14)
    bb.StudsOffsetWorldSpace = V3(0, 4.4, 0)
    local l = ui.label(bb, "▼", UDim2.fromScale(1, 1), nil, 13, WHITE, Enum.Font.GothamBold)
    l.TextWrapped = false
    l.TextStrokeTransparency = 0.5
    m = { bb = bb, l = l }
    mates[i] = m
    return m
  end
  local function freeMark(i)
    local m = freeMarks[i]
    if m then return m end
    local bb = billboard("FreeVeh", 150, 34)
    local d = ui.label(bb, "◆", UDim2.fromOffset(14, 14), UDim2.new(0.5, 0, 0, 0), 12, WHITE, Enum.Font.GothamBold, V2(0.5, 0))
    d.TextWrapped = false
    d.TextStrokeTransparency = 0.5
    local l = ui.label(bb, "", UDim2.new(1, 0, 0, 16), UDim2.new(0.5, 0, 0, 15), 11, TEXT, Enum.Font.GothamBold, V2(0.5, 0))
    l.TextWrapped = false
    l.TextStrokeTransparency = 0.45
    m = { bb = bb, d = d, l = l }
    freeMarks[i] = m
    return m
  end
  local function rootOf(model)
    return model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChild("Root")) or nil
  end
  local markT = 0
  local function stepMarks(dt, show)
    markT -= dt
    if markT > 0 then return end
    markT = 0.25
    local mine = me:GetAttribute("Side")
    local cam = workspace.CurrentCamera
    local cp = cam.CFrame.Position
    local col = teamColor(mine):Lerp(WHITE, 0.3)
    -- 队友：雷达那份（Hud.lua 0.1 秒收一次）里同队的步兵（真人、机器人）
    local n = 0
    if show and G.radarContacts then
      for _, c in ipairs(G.radarContacts()) do
        if n >= 16 then break end
        if c.team == mine and c.kind == "inf" and c.model and c.model ~= me.Character then
          local d = (c.pos - cp).Magnitude
          local r = rootOf(c.model)
          if r and d > 10 and d < 600 then
            n += 1
            local m = mateMark(n)
            m.bb.Adornee = r
            m.l.TextColor3 = col
            m.l.TextTransparency = (d > 300) and 0.35 or 0.1
            m.bb.Enabled = true
          end
        end
      end
    end
    for i = n + 1, #mates do mates[i].bb.Enabled = false end
    -- 能开的空车：自己队的、没人开的、没被毁的；离自己 40～420 格（再近就有「E 上车」提示）；最近的 6 辆
    local k = 0
    local ch = me.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if show and hrp and not G.drive then
      local list = {}
      for em, v in pairs(G.views or {}) do
        if (v.kind == "veh" or v.kind == "air") and v.anchor and em.Parent and em:GetAttribute("Team") == mine
          and ((em:GetAttribute("Driver") or 0) == 0) and not em:GetAttribute("Wreck") and not em:GetAttribute("Locked")
          and (em:GetAttribute("Hp") or 1) > 0 then
          local d = (v.anchor.Position - hrp.Position).Magnitude
          if d > 40 and d < 420 then table.insert(list, { v = v, d = d }) end
        end
      end
      table.sort(list, function(a, b) return a.d < b.d end)
      for i = 1, math.min(6, #list) do
        local v = list[i].v
        k += 1
        local m = freeMark(k)
        m.bb.Adornee = v.anchor
        m.bb.StudsOffsetWorldSpace = V3(0, ((v.def and v.def.H) or 7) * 0.6 + 3, 0)
        m.d.TextColor3 = col
        m.l.Text = T("coach.free") .. " · " .. T("veh." .. ((v.def and v.def.id) or ""))
        m.bb.Enabled = true
      end
    end
    for i = k + 1, #freeMarks do freeMarks[i].bb.Enabled = false end
  end

  ---------------------------------------------------------------- 每帧

  local wasAlive, spawnN, infUntil = false, 0, 0
  local far, farUntil = false, 0
  local lastSub, subT0 = nil, 0
  function G.stepCoach(dt)
    local S = G.S
    local now = clock()
    local alive = S ~= nil and S.alive == true
    if alive and not wasAlive then
      spawnN += 1
      if spawnN <= 3 then infUntil = now + 8 end   -- 头三次出生：步行的几个键显示 8 秒
    end
    wasAlive = alive
    local mode = modeNow()
    local menu = G.menuOpen ~= nil and G.menuOpen()
    local hudOn = hud.Visible and not menu
    -- F1 面板：状态变了跟着换内容
    if panelOpen and panelMode ~= mode then buildPanel(mode) end
    -- 三步卡：换了状态（下车、阵亡）就收起；第一次进某种载具弹出来；30 秒没关自己收（算看过）
    if cardMode and (cardMode ~= mode or now - cardT0 > 30) then closeCard(now - cardT0 > 30) end
    if not cardMode and mode and CARDS[mode] and not mobile and hudOn and not isSeen(mode) and not hudTipOpen() then openCard(mode) end   -- Hud 的目标说明开着就先等它关上
    card.Visible = cardMode ~= nil and not panelOpen and hudOn
    -- 按键提示
    local sub = mode and subOf(mode)
    if sub ~= lastSub then lastSub, subT0 = sub, now end
    local list, dim = nil, false
    local d = G.drive
    local hidden = mobile or not hudOn or panelOpen or G.scopeOn or (d and (d.sight or d.eo))
    if not hidden and mode then
      if mode == "inf" then
        local od = G.objDist and G.objDist()
        local isFar = od ~= nil and od > 1200
        if isFar and not far then farUntil = now + 10 end   -- 离目标远：提示一次「H 重新部署」
        far = isFar
        if now < infUntil then list = hintList("inf")
        elseif isFar and now < farUntil then list = hintList("far") end
      elseif STICKY[sub] or now - subT0 < (isSeen(mode) and 10 or 25) then
        list = hintList(sub)
      else
        list, dim = { { "F1", T("coach.allKeys") } }, true
      end
    end
    if list and #list > 0 then
      setChips(list, dim)
      bar.Visible = true
    else
      bar.Visible = false
    end
    -- 目标箭头、队友、空车
    local showWorld = hudOn and alive and S.phase ~= "end"
    stepArrow(showWorld and not G.scopeOn and not (d and (d.sight or d.eo)))
    stepMarks(dt, showWorld)
  end
end

return Coach
