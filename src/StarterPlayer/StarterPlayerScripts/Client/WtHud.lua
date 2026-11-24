-- Roblox全面大战场（客户端）——战雷式伤害的界面（用户 11-24「把整个游戏做成战雷」：乘员和模块伤害 + X 光回放）
--   · 命中提示（打出去的）：准星下面一行——击穿（橙）/ 未击穿（灰）/ 跳弹（黄）/ 已击毁（红：弹药殉爆、车组全灭、烧毁），
--     后面跟这一发伤了谁：「炮长阵亡 · 炮闩损毁 · 起火」
--   · X 光命中回放（右下一个小窗，四五秒）：目标车的外形半透明、里面的乘员和模块按状态上色（绿好、黄伤、红没了 / 毁了），
--     弹芯 / 射流一道橙线、破片一锥黄线（服务器、客户端用同一个伪随机，画出来和算的一样）；镜头从来弹方向慢慢绕
--   · 自己的车挨打：底下一行红字「被击穿：装填手阵亡」；左下车组 / 模块面板（驾 / 炮 / 车 / 装，发 / 传 / 履 / 炮管 / 闩 / 驱 / 弹 / 油），
--     起火、维修进度、「Y 维修 / 灭火」提示；换位「装填手 6 秒后接替炮长」
--   服务器 Wt.lua 发 { op = "wtHit" / "wtHurt" / "wtSwap" / "wtSwapped" / "wtFireOut" / "wtFixed" }，车的状态在实体属性 WtC / WtM / WtF / WtFix
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local WtHud = {}

function WtHud.init(G)
  local W = require(RS:WaitForChild("WtDamage"))
  local VD = require(RS:WaitForChild("VehDefs"))
  local V2, V3, UD2 = Vector2.new, Vector3.new, UDim2.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local me = Players.LocalPlayer
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local BOLD, MONO = Enum.Font.GothamBold, Enum.Font.RobotoMono
  local mobile = UIS.TouchEnabled and not UIS.KeyboardEnabled
  local OK, HURT, DEAD, GREY = RGB(96, 230, 110), RGB(255, 206, 64), RGB(255, 70, 56), RGB(170, 176, 180)
  local PEN, RIC, KILL = RGB(255, 150, 60), RGB(255, 214, 90), RGB(255, 64, 52)

  local gui = Instance.new("ScreenGui")
  gui.Name = "WtHud"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 6
  gui.Parent = me:WaitForChild("PlayerGui")

  local function label(parent, text, size, pos, ts, color, font, anchor, align)
    local l = Instance.new("TextLabel")
    l.Size, l.Position, l.AnchorPoint = size, pos or UD2(), anchor or V2()
    l.BackgroundTransparency = 1
    l.Text, l.TextSize, l.TextColor3, l.Font = text or "", ts or 14, color or Color3.new(1, 1, 1), font or BOLD
    l.TextXAlignment = align or Enum.TextXAlignment.Center
    l.TextStrokeTransparency, l.TextStrokeColor3 = 0.35, RGB(0, 0, 0)
    l.Parent = parent
    return l
  end
  local function frame(parent, size, pos, color, tr, anchor)
    local f = Instance.new("Frame")
    f.Size, f.Position, f.AnchorPoint = size, pos or UD2(), anchor or V2()
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = color or RGB(0, 0, 0), tr or 0, 0
    f.Parent = parent
    return f
  end

  local function partName(p)
    if p.kind == "crew" then return T("wt.r." .. (p.seat or p.k)) end
    return T("wt.m." .. p.k)
  end
  -- 这一下伤了谁：「炮长阵亡 · 发动机损毁 · 起火」
  local function details(m)
    local bits = {}
    for _, p in ipairs(m.parts or {}) do
      if p.kind == "crew" then
        table.insert(bits, partName(p) .. T((p.s == 0) and "wt.dead" or "wt.hurt"))
      elseif p.s == 0 then
        table.insert(bits, partName(p) .. T("wt.broken"))
      elseif p.s == 1 then
        table.insert(bits, partName(p) .. T("wt.damaged"))
      end
    end
    if m.blow then table.insert(bits, T("wt.blowout")) end
    if m.fire then table.insert(bits, T("wt.onFire")) end
    return table.concat(bits, " · ")
  end

  ---------------------------------------------------------------- 命中提示（打出去的）

  local hitBox = frame(gui, UDim2.fromOffset(640, 52), UD2(0.5, 0, 0.5, 70), RGB(0, 0, 0), 1, V2(0.5, 0))
  hitBox.Name = "WtHitText"
  local hitTop = label(hitBox, "", UD2(1, 0, 0, 24), UD2(0, 0, 0, 0), 20, PEN)
  hitTop.Name = "Result"
  local hitSub = label(hitBox, "", UD2(1, 0, 0, 18), UD2(0, 0, 0, 26), 14, Color3.new(1, 1, 1))
  hitSub.Name = "Detail"
  hitBox.Visible = false
  local hitUntil = 0
  local function showHit(m)
    local top, col
    if m.kill then
      top, col = T((m.why == "ammo") and "wt.killAmmo" or ((m.why == "fire") and "wt.killFire" or "wt.kill")), KILL
    elseif m.r == "pen" then top, col = T("wt.pen"), PEN
    elseif m.r == "ric" then top, col = T("wt.ric"), RIC
    elseif m.r == "np" then top, col = T("wt.np"), GREY
    else top, col = T("wt.hit"), PEN end
    hitTop.Text, hitTop.TextColor3 = top, col
    local sub = details(m)
    if (m.r == "np" or m.r == "ric") and m.pen and m.arm then sub = T("wt.mm", m.arm, m.pen) .. ((sub ~= "") and ("   " .. sub) or "") end
    hitSub.Text = sub
    hitBox.Visible = true
    hitUntil = os.clock() + (m.kill and 3.6 or 2.6)
  end

  -- 飞机（WtAir.lua）：打中了哪块、断翼 / 起火 / 漏油 / 飞行员昏迷
  local function airBits(m)
    local bits, seen = {}, {}
    for _, ev in ipairs(m.ev or {}) do
      if not seen[ev] then seen[ev] = true table.insert(bits, T("wta.e." .. ev)) end
    end
    if #bits == 0 then
      for _, k in ipairs(m.parts or {}) do
        if not seen[k] then seen[k] = true table.insert(bits, T("wta.p." .. k)) end
      end
    end
    return table.concat(bits, " · ")
  end
  local function showAirHit(m)
    local big = false
    for _, ev in ipairs(m.ev or {}) do if ev ~= "leak" then big = true end end
    hitTop.Text = T(big and "wta.crit" or "wt.hit")
    hitTop.TextColor3 = big and KILL or PEN
    hitSub.Text = airBits(m)
    hitBox.Visible = true
    hitUntil = os.clock() + (big and 3 or 1.6)
  end

  ---------------------------------------------------------------- X 光命中回放

  local XW, XH = mobile and 240 or 320, mobile and 150 or 196
  local xr = frame(gui, UDim2.fromOffset(XW, XH + 22), mobile and UD2(1, -12, 0, 120) or UD2(1, -20, 1, -300), RGB(8, 12, 14), 0.25, V2(1, mobile and 0 or 1))
  xr.Name = "WtXray"
  xr.Visible = false
  do
    local s = Instance.new("UIStroke")
    s.Color, s.Thickness, s.Transparency = RGB(120, 200, 140), 1, 0.4
    s.Parent = xr
  end
  local xTitle = label(xr, "", UD2(1, -10, 0, 18), UD2(0, 6, 0, 2), 12, Color3.new(1, 1, 1), BOLD, nil, Enum.TextXAlignment.Left)
  local vp = Instance.new("ViewportFrame")
  vp.Name = "View"
  vp.Size, vp.Position = UD2(1, -4, 1, -24), UD2(0, 2, 0, 22)
  vp.BackgroundColor3, vp.BackgroundTransparency = RGB(14, 22, 30), 0.1
  vp.Ambient, vp.LightColor, vp.LightDirection = RGB(170, 175, 185), RGB(255, 255, 255), V3(-0.4, -1, -0.3)
  vp.Parent = xr
  local vcam = Instance.new("Camera")
  vcam.FieldOfView = 40
  vcam.Parent = vp
  vp.CurrentCamera = vcam
  local world = Instance.new("WorldModel")
  world.Parent = vp
  local xrUntil, xrSpin, xrC, xrDist, xrDir = 0, 0, V3(), 30, V3(0, 0, -1)

  local function box(size, cf, color, tr, mat)
    local p = Instance.new("Part")
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    p.Size = V3(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
    p.CFrame = cf
    p.Color, p.Transparency = color, tr or 0
    p.Material = mat or Enum.Material.SmoothPlastic
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.Parent = world
    return p
  end
  local function line(a, b, color, th)
    local d = b - a
    if d.Magnitude < 0.05 then return end
    box(V3(th or 0.12, th or 0.12, d.Magnitude), CFrame.lookAt((a + b) / 2, b), color, 0, Enum.Material.Neon)
  end
  local function entModel(id)
    local f = workspace:FindFirstChild("Ents")
    if not f then return nil end
    for _, em in ipairs(f:GetChildren()) do if em:GetAttribute("EntId") == id then return em end end
    return nil
  end
  -- 状态：先看实体属性（服务器刚写的），没有就按这一发报来的
  local function states(em, d)
    local lay = W.layout(d)
    local cs, ms = {}, {}
    local wc = em and em:GetAttribute("WtC")
    local wm = em and em:GetAttribute("WtM")
    local i = 0
    for tok in string.gmatch(wc or "", "[^,]+") do i += 1 cs[i] = tonumber(string.sub(tok, 1, 1)) or 2 end
    for j = 1, #(wm or "") do ms[j] = tonumber(string.sub(wm, j, j)) or 2 end
    local out = {}
    local ci, mi = 0, 0
    for _, it in ipairs(lay.list) do
      if it.kind == "crew" then ci += 1 out[it] = cs[ci] or 2 else mi += 1 out[it] = ms[mi] or 2 end
    end
    return out
  end
  local function showXray(m)
    local d = VD.get and VD.get(m.veh) or VD[m.veh]
    local x = m.xr
    if not d or not x then return end
    world:ClearAllChildren()
    local lay = W.layout(d)
    local yaw = x.ty or 0
    local base = CF()   -- 回放里车底座在原点
    -- 车的外形：看得见那辆车就照它的模型复制一份半透明的；看不见画车体、炮塔两个半透明的框
    local v = G.viewById and G.viewById(m.id)
    local n = 0
    if v and v.model and v.hullF then
      local inv = (v.hullF):Inverse()
      for _, p in ipairs(v.model:GetDescendants()) do
        if p:IsA("BasePart") and p.Transparency < 0.9 and n < 400 then
          n += 1
          local c = p:Clone()
          for _, ch in ipairs(c:GetChildren()) do if not ch:IsA("SpecialMesh") then ch:Destroy() end end
          pcall(function() c.TextureID = "" end)
          c.Anchored, c.CanCollide, c.CastShadow = true, false, false
          c.Material, c.Color, c.Transparency = Enum.Material.SmoothPlastic, RGB(150, 190, 220), 0.88
          c.CFrame = inv * p.CFrame
          c.Parent = world
        end
      end
    end
    if n == 0 then
      local hH = lay.hH
      box(V3(d.W, hH - (d.clear or 1.2), d.L), CF(0, ((d.clear or 1.2) + hH) / 2, 0), RGB(150, 190, 220), 0.85)
      if d.turret then
        local tcf = CF(W.fromTur(d, V3(), yaw)) * CFrame.Angles(0, -math.rad(yaw), 0)
        box(lay.ts, tcf * CF(0, lay.ts.Y / 2, 0), RGB(150, 190, 220), 0.8)
      end
    end
    -- 乘员、模块
    local st = states(entModel(m.id), d)
    local hitK = {}
    for _, p in ipairs(m.parts or {}) do hitK[p.k] = true end
    for _, it in ipairs(lay.list) do
      local s = st[it] or 2
      local col
      if it.kind == "crew" then col = (s == 0) and DEAD or ((s == 1) and HURT or OK)
      else col = (s == 0) and DEAD or ((s == 1) and HURT or RGB(120, 150, 170)) end
      local size = it.hi - it.lo
      local c = (it.lo + it.hi) / 2
      local cf
      if it.tur then cf = CF(W.fromTur(d, c, yaw)) * CFrame.Angles(0, -math.rad(yaw), 0)
      else cf = CF(c) end
      local tr = (it.kind == "crew") and 0.1 or ((s == 2 and not hitK[it.k]) and 0.55 or 0.15)
      local p = box((it.kind == "crew") and size * 0.8 or size, cf, col, tr)
      if it.kind == "crew" then
        local sm = Instance.new("SpecialMesh")
        sm.MeshType = Enum.MeshType.Sphere
        sm.Parent = p
      end
    end
    -- 弹道：外面一段、弹芯 / 射流往里一段（橙），破片一锥（黄）
    local p0 = V3(x.p[1], x.p[2], x.p[3])
    local dv = V3(x.d[1], x.d[2], x.d[3]).Unit
    line(p0 - dv * 9, p0, RGB(255, 120, 40), 0.16)
    if m.r == "pen" or m.kill then
      local core = (x.core or 0) * W.M
      if core > 0 then line(p0, p0 + dv * core, RGB(255, 150, 50), 0.2) end
      for i, rv in ipairs(W.cone(dv, x.half or 18, x.n or 0, x.seed)) do
        local len = (1.4 + (i % 4) * 0.35) * W.M
        local hits = W.trace(d, yaw, p0 + dv * 0.1, rv, len, true)
        local l2 = hits[1] and math.max(0.3, hits[1].t + 0.4) or len
        line(p0, p0 + rv * l2, RGB(255, 226, 90), 0.06)
      end
    end
    box(V3(0.5, 0.5, 0.5), CF(p0), RGB(255, 240, 200), 0, Enum.Material.Neon)
    -- 镜头：从来弹方向、稍高一点看车中心，慢慢绕
    xrC = V3(0, (d.H or 7) * 0.45, 0)
    xrDist = math.max(d.L, d.W) * 1.55 + 4
    xrDir = (-dv * V3(1, 0, 1))
    if xrDir.Magnitude < 0.1 then xrDir = V3(0, 0, 1) end
    xrDir = xrDir.Unit
    xrSpin = 0
    local nm = T("veh." .. m.veh)
    xTitle.Text = T("wt.xrTitle", nm, m.dist or 0)
    xr.Visible = true
    xrUntil = os.clock() + (m.kill and 5.5 or 4.5)
    local _ = base
  end

  ---------------------------------------------------------------- 左下：自己这辆车的车组 / 模块

  local panel = frame(gui, UDim2.fromOffset(226, 96), mobile and UD2(0, 12, 1, -238) or UD2(0, 254, 1, -24), RGB(6, 10, 12), 0.35, V2(0, 1))
  panel.Name = "WtCrew"
  panel.Visible = false
  do
    local s = Instance.new("UIStroke")
    s.Color, s.Thickness, s.Transparency = RGB(120, 200, 140), 1, 0.55
    s.Parent = panel
  end
  local crewIcons, modIcons = {}, {}
  local CREW_ROW = { "drv", "gnr", "cmd", "ldr" }
  for i, r in ipairs(CREW_ROW) do
    local f = frame(panel, UDim2.fromOffset(48, 30), UD2(0, 6 + (i - 1) * 54, 0, 6), RGB(20, 30, 26), 0.2)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 4)
    c.Parent = f
    local l = label(f, T("wt.rs." .. r), UD2(1, 0, 1, 0), UD2(), 15, OK, BOLD)
    f.Name = "Crew_" .. r
    crewIcons[r] = { f = f, l = l }
  end
  local MOD_ROW = { "engine", "trans", "track", "barrel", "breech", "tdrive", "ammo", "fuel" }
  for i, k in ipairs(MOD_ROW) do
    local f = frame(panel, UDim2.fromOffset(25, 20), UD2(0, 6 + (i - 1) * 27, 0, 42), RGB(20, 30, 26), 0.2)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 3)
    c.Parent = f
    local l = label(f, T("wt.ms." .. k), UD2(1, 0, 1, 0), UD2(), 11, OK, BOLD)
    f.Name = "Mod_" .. k
    modIcons[k] = { f = f, l = l }
  end
  local panelTip = label(panel, "", UD2(1, -8, 0, 16), UD2(0, 4, 0, 72), 12, Color3.new(1, 1, 1), BOLD, nil, Enum.TextXAlignment.Left)
  panelTip.Name = "Tip"
  local flashUntil = 0

  local hurtText = label(gui, "", UDim2.fromOffset(700, 22), UD2(0.5, 0, 1, -150), 17, DEAD, BOLD, V2(0.5, 1))
  hurtText.Name = "WtHurtText"
  hurtText.Visible = false
  local hurtUntil = 0
  local function say(text, col, dur)
    hurtText.Text, hurtText.TextColor3 = text, col or DEAD
    hurtText.Visible = true
    hurtUntil = os.clock() + (dur or 3)
  end

  local function colOf(s) return (s == 0) and DEAD or ((s == 1) and HURT or OK) end
  local function updatePanel()
    local st = G.myVeh
    local em = st and st.em
    local wc = em and em:GetAttribute("WtC")
    if not wc or (G.S and G.S.veh == nil and not st) then panel.Visible = false return end
    if G.wtTankShown and G.wtTankShown() then panel.Visible = false return end   -- 电脑上是战雷那套的损伤示意图（WtTank.lua）
    panel.Visible = true
    local d = st.d or (VD.get and VD.get(em:GetAttribute("Model") or ""))
    if not d then panel.Visible = false return end
    local lay = W.layout(d)
    -- 乘员：按座位（谁坐在这个位子上、活没活）
    local seatState, have = {}, {}
    for tok in string.gmatch(wc, "[^,]+") do
      local s, seat = tonumber(string.sub(tok, 1, 1)) or 2, string.sub(tok, 2)
      if seatState[seat] == nil or s > seatState[seat] then seatState[seat] = s end
      have[seat] = true
    end
    for _, r in ipairs(CREW_ROW) do
      local ic = crewIcons[r]
      ic.f.Visible = have[r] == true
      if have[r] then ic.l.TextColor3 = colOf(seatState[r]) end
    end
    -- 模块：几块合成一个图标的取最差的（左右履带、几个弹药架、几个油箱）
    local wm = em:GetAttribute("WtM") or ""
    local worst = {}
    local mi = 0
    for _, it in ipairs(lay.list) do
      if it.kind ~= "crew" then
        mi += 1
        local s = tonumber(string.sub(wm, mi, mi)) or 2
        local k = it.k
        if k == "trackL" or k == "trackR" then k = "track" elseif k == "ammoH" then k = "ammo" elseif k == "fuelL" or k == "fuelR" then k = "fuel" end
        if worst[k] == nil or s < worst[k] then worst[k] = s end
      end
    end
    for _, k in ipairs(MOD_ROW) do
      local ic = modIcons[k]
      ic.f.Visible = worst[k] ~= nil
      if worst[k] then ic.l.TextColor3 = colOf(worst[k]) end
    end
    local t = os.clock()
    local flash = t < flashUntil and (t * 8) % 1 < 0.5
    panel.BackgroundColor3 = flash and RGB(90, 20, 14) or RGB(6, 10, 12)
    -- 提示：起火、维修中、坏了能修
    local fire = em:GetAttribute("WtF") == true
    local fix = em:GetAttribute("WtFix")
    local anyBad = false
    for _, s in pairs(worst) do if s < 2 then anyBad = true end end
    if fire then panelTip.Text, panelTip.TextColor3 = T("wt.tipFire"), ((t * 3) % 1 < 0.6) and DEAD or HURT
    elseif fix then panelTip.Text, panelTip.TextColor3 = T("wt.tipFixing", math.floor(fix * 100)), HURT
    elseif anyBad then panelTip.Text, panelTip.TextColor3 = T("wt.tipFix"), Color3.new(1, 1, 1)
    else panelTip.Text = "" end
  end

  ---------------------------------------------------------------- 服务器发来的

  G.R.Drive.OnClientEvent:Connect(function(m)
    if type(m) ~= "table" then return end
    local op = m.op
    if op == "wtHit" then
      showHit(m)
      if m.xr and (m.r == "pen" or m.kill) then G.try_(showXray, m) end
    elseif op == "wtHurt" then
      flashUntil = os.clock() + 1.2
      local head = T((m.r == "pen") and "wt.youPen" or ((m.r == "fire") and "wt.youFire" or ((m.r == "ric") and "wt.youRic" or ((m.r == "np") and "wt.youNp" or "wt.youHit"))))
      local sub = details(m)
      say(head .. ((sub ~= "") and ("：" .. sub) or ""), (m.r == "ric" or m.r == "np") and GREY or DEAD, 3.2)
    elseif op == "wtSwap" then
      say(T("wt.swap", T("wt.r." .. m.from), T("wt.r." .. m.role), m.t or 6), HURT, 3)
    elseif op == "wtSwapped" then
      say(T("wt.swapped", T("wt.r." .. m.from), T("wt.r." .. m.role)), OK, 2.5)
    elseif op == "wtFireOut" then
      say(T(m.ext and "wt.extOk" or "wt.fireOut"), OK, 2)
    elseif op == "wtFixed" then
      say(T("wt.fixed"), OK, 2)
    elseif op == "wtKilled" then   -- 自己的车被打掉：「被 XX 的 YY 击毁」+ 那一发的 X 光（战雷的击毁回放）
      local kv = m.kveh and (string.match(T("veh." .. m.kveh), "^(%S+)") or T("veh." .. m.kveh)) or nil
      say(kv and T("wt.killedBy", m.from or "?", kv) or T("wt.killedBy2", m.from or "?"), DEAD, 5)
      if m.xr then G.try_(showXray, m) end
    elseif op == "wtaHit" then
      showAirHit(m)
    elseif op == "wtaHurt" then
      local only = #(m.ev or {}) == 1 and m.ev[1] == "fireOut"
      if only then say(T("wta.e.fireOut"), OK, 2)
      else say(T("wta.hurt") .. "：" .. airBits(m), DEAD, 3) end
    end
  end)

  G.frameConn("WtHud", function(dt)
    local t = os.clock()
    if hitBox.Visible and t > hitUntil then hitBox.Visible = false end
    if hurtText.Visible and t > hurtUntil then hurtText.Visible = false end
    if xr.Visible then
      if t > xrUntil then
        xr.Visible = false
        world:ClearAllChildren()
      else
        xrSpin += dt * math.rad(16)
        local d = CFrame.Angles(0, xrSpin, 0) * xrDir
        local eye = xrC + d * xrDist + V3(0, xrDist * 0.35, 0)
        vcam.CFrame = CFrame.lookAt(eye, xrC)
      end
    end
    G.try_(updatePanel)
  end)
end

return WtHud
