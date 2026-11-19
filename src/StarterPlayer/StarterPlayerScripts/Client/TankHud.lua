-- Roblox全面大战场（客户端）——坦克驾驶界面的补充（用户 11-19 给了一张手机坦克游戏的截图：「坦克驾驶操作界面改成这样」）
--   照那张图的布局和感觉做（不照抄它的图标、配色细节）：
--   · 敌人头顶：看得见的敌方车辆上面一个小牌子（红色的型号名、距离「183 米」），最多 6 个，离得远的、被挡住的不画
--   · 「被发现！」：附近有敌人看得见自己（视线没被挡），或者刚挨了打——左边一块琥珀色的牌子，一闪一闪
--   · 爆反、主动防御还剩多少（右下面板上面一行，青色）
--   · 开坦克时（电脑）右上的方形小地图挪到左下角、裁成圆的，外圈 0 / 90 / 180 / 270 的方位刻度；下车、换别的载具恢复
--   VehHud.lua 每帧调 G.tankHudExtra(st, 血量比例)；准星两边的弹药数、已就绪、测距在 VehHud 里
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local TankHud = {}

function TankHud.init(G)
  local V2, V3, UD2 = Vector2.new, Vector3.new, UDim2.new
  local RGB = Color3.fromRGB
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local CYAN, RED, AMBER, INK = RGB(110, 226, 240), RGB(255, 78, 64), RGB(255, 186, 72), RGB(6, 10, 14)
  local MONO, BOLD = Enum.Font.RobotoMono, Enum.Font.GothamBold
  local mobile = UIS.TouchEnabled and not UIS.KeyboardEnabled

  local gui = Instance.new("ScreenGui")
  gui.Name = "TankHud"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 4
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")

  local function label(parent, text, size, pos, ts, color, font, anchor, align)
    local l = Instance.new("TextLabel")
    l.Size, l.Position, l.AnchorPoint = size, pos or UD2(), anchor or V2()
    l.BackgroundTransparency = 1
    l.Text, l.TextSize, l.TextColor3, l.Font = text or "", ts or 13, color or CYAN, font or BOLD
    l.TextXAlignment = align or Enum.TextXAlignment.Center
    l.TextStrokeTransparency = 0.55
    l.Parent = parent
    return l
  end

  -- 敌人头顶的牌子（对象池）
  local tags = {}
  for i = 1, 6 do
    local f = Instance.new("Frame")
    f.Size = UDim2.fromOffset(130, 34)
    f.AnchorPoint = V2(0.5, 1)
    f.BackgroundTransparency = 1
    f.Visible = false
    f.Parent = gui
    local nm = label(f, "", UD2(1, 0, 0, 16), UD2(0, 0, 0, 0), 13, RED, BOLD)
    local dist = label(f, "", UD2(1, 0, 0, 14), UD2(0, 0, 0, 17), 12, Color3.new(1, 1, 1), MONO)
    tags[i] = { f = f, nm = nm, dist = dist }
  end

  -- 「被发现！」
  local spot = Instance.new("Frame")
  spot.Size = UDim2.fromOffset(150, 30)
  spot.AnchorPoint = V2(0, 0.5)
  spot.Position = mobile and UD2(0, 16, 0.3, 0) or UD2(0, 36, 0.42, 0)
  spot.BackgroundColor3, spot.BackgroundTransparency = INK, 0.35
  spot.Visible = false
  spot.Parent = gui
  do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 4)
    c.Parent = spot
    local s = Instance.new("UIStroke")
    s.Color, s.Thickness, s.Transparency = AMBER, 1, 0.3
    s.Parent = spot
  end
  local eye = label(spot, "◉", UDim2.fromOffset(26, 30), UD2(0, 4, 0, 0), 16, AMBER, BOLD)
  local spotTxt = label(spot, "", UD2(1, -34, 1, 0), UD2(0, 30, 0, 0), 15, AMBER, BOLD, nil, Enum.TextXAlignment.Left)

  -- 爆反 / 主动防御还剩多少
  local armLine = label(gui, "", UDim2.fromOffset(300, 18), mobile and UD2(0.5, 0, 0, 72) or UD2(1, -24, 1, -204), 13, CYAN, MONO,
    mobile and V2(0.5, 0) or V2(1, 1), mobile and Enum.TextXAlignment.Center or Enum.TextXAlignment.Right)

  -- 圆形小地图的方位刻度（挪到左下时才显示）
  local MS = 210
  local ring = Instance.new("Frame")
  ring.Size = UDim2.fromOffset(MS + 30, MS + 30)
  ring.AnchorPoint = V2(0.5, 0.5)
  ring.Position = UD2(0, 26 + MS / 2, 1, -26 - MS / 2)
  ring.BackgroundTransparency = 1
  ring.Visible = false
  ring.Parent = gui
  do
    local edge = Instance.new("Frame")
    edge.Size = UDim2.fromOffset(MS + 6, MS + 6)
    edge.AnchorPoint, edge.Position = V2(0.5, 0.5), UD2(0.5, 0, 0.5, 0)
    edge.BackgroundTransparency = 1
    edge.Parent = ring
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = edge
    local s = Instance.new("UIStroke")
    s.Color, s.Thickness, s.Transparency = CYAN, 1.5, 0.35
    s.Parent = edge
    for _, b in ipairs({ { 0, "0" }, { 90, "90" }, { 180, "180" }, { 270, "270" } }) do
      local a = math.rad(b[1])
      label(ring, b[2], UDim2.fromOffset(34, 14), UD2(0.5, math.sin(a) * (MS / 2 + 11), 0.5, -math.cos(a) * (MS / 2 + 11)), 11, CYAN, MONO, V2(0.5, 0.5))
    end
  end

  -- 小地图挪到左下变圆 / 恢复
  local docked, saved = false, nil
  local function dock(on)
    if mobile then on = false end
    if on == docked then return end
    local box = G.hudParts and G.hudParts.miniBox
    if not box then return end
    docked = on
    local corner = box:FindFirstChildOfClass("UICorner")
    local squad = G.hudParts.hud and G.hudParts.hud:FindFirstChild("Squad")   -- 左下的小队名单（Hud.lua）：挪到圆形小地图右边，不叠在一起
    if on then
      saved = { a = box.AnchorPoint, p = box.Position, s = box.Size, r = corner and corner.CornerRadius,
        rr = G.hudLayout and G.hudLayout.radarRight, sq = squad and squad.Position }
      box.AnchorPoint, box.Position, box.Size = V2(0, 1), UD2(0, 26, 1, -26), UDim2.fromOffset(MS, MS)
      if corner then corner.CornerRadius = UDim.new(0.5, 0) end
      if G.hudLayout then G.hudLayout.radarRight = false end
      if squad then squad.Position = UD2(0, 26 + MS + 30, 1, -18) end
    elseif saved then
      box.AnchorPoint, box.Position, box.Size = saved.a, saved.p, saved.s
      if corner and saved.r then corner.CornerRadius = saved.r end
      if G.hudLayout then G.hudLayout.radarRight = saved.rr end
      if squad and saved.sq then squad.Position = saved.sq end
    end
    ring.Visible = on
  end
  G.tankHudDocked = function() return docked end   -- 测试用

  ---------------------------------------------------------------- 谁看得见
  local rp = RaycastParams.new()
  rp.FilterType = Enum.RaycastFilterType.Exclude
  local function entOf(inst)
    local ents = workspace:FindFirstChild("Ents")
    while inst and inst.Parent and inst.Parent ~= ents do inst = inst.Parent end
    return (inst and inst.Parent == ents) and inst or nil
  end
  local function excludeList(st)
    local list = {}
    local vf = workspace:FindFirstChild("EntView")   -- View.lua 画的车、船、小兵（看不见的命中盒在 Ents 里）
    if vf then table.insert(list, vf) end   -- 客户端画的车、船（看不见的命中盒在 Ents 里）
    if st and st.em then table.insert(list, st.em) end
    if me.Character then table.insert(list, me.Character) end
    return list
  end
  local function clear(from, to, target, st)
    rp.FilterDescendantsInstances = excludeList(st)
    local hit = workspace:Raycast(from, to - from, rp)
    if not hit then return true end
    local e = entOf(hit.Instance)
    return e ~= nil and e == target
  end

  local cands, lastScan, lastSpot, spotted, hurtT, lastK = {}, 0, 0, false, -9, nil
  local function enemy(em, side)
    if em:GetAttribute("Wreck") or (em:GetAttribute("Hp") or 1) <= 0 then return false end
    local tm = em:GetAttribute("Team")
    return tm ~= nil and tm ~= side
  end

  function G.tankHudExtra(st, hpK)
    gui.Enabled = true
    dock(true)
    local t = os.clock()
    local side = me:GetAttribute("Side")
    local myPos = st.root and st.root.Position or cam.CFrame.Position
    local ents = workspace:FindFirstChild("Ents")
    -- 敌人：每 0.25 秒重新挑一遍（距离、视线），每帧摆牌子
    if t - lastScan > 0.25 then
      lastScan = t
      cands = {}
      for _, em in ipairs(ents and ents:GetChildren() or {}) do
        local cat = em:GetAttribute("Cat")
        if (cat == "armor" or cat == "light" or cat == "ship") and enemy(em, side) then
          local r = em:FindFirstChild("Root")
          if r then
            local d = (r.Position - myPos).Magnitude
            if d < 1100 and clear(cam.CFrame.Position, r.Position, em, st) then table.insert(cands, { em = em, r = r, d = d }) end
          end
        end
      end
      table.sort(cands, function(a, b) return a.d < b.d end)
    end
    local n = 0
    for _, c in ipairs(cands) do
      if n >= #tags then break end
      if c.em.Parent and c.r.Parent then
        local top = c.r.Position + V3(0, c.r.Size.Y / 2 + 2.5, 0)
        local sp, on = cam:WorldToViewportPoint(top)
        if on then
          n += 1
          local tg = tags[n]
          tg.f.Visible = true
          tg.f.Position = UDim2.fromOffset(sp.X, sp.Y)
          local id = c.em:GetAttribute("Model")
          tg.nm.Text = id and T("veh." .. id) or ""
          tg.dist.Text = T("vh.m", math.floor((c.r.Position - myPos).Magnitude / 2.8 + 0.5))
        end
      end
    end
    for i = n + 1, #tags do tags[i].f.Visible = false end
    -- 被发现：附近（500 格以内）的敌方车辆、敌方玩家看得见自己；或者刚挨了打
    if lastK and hpK < lastK - 0.001 then hurtT = t end
    lastK = hpK
    if t - lastSpot > 0.4 then
      lastSpot = t
      spotted = false
      for _, c in ipairs(cands) do
        if c.d < 500 then spotted = true break end   -- 我看得见它，它也看得见我（同一条视线）
      end
      if not spotted then
        for _, pl in ipairs(Players:GetPlayers()) do
          if pl ~= me and pl:GetAttribute("Side") and pl:GetAttribute("Side") ~= side then
            local hrp = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
            if hrp and (hrp.Position - myPos).Magnitude < 500 then
              rp.FilterDescendantsInstances = excludeList(st)
              local hit = workspace:Raycast(myPos + V3(0, 4, 0), hrp.Position - myPos - V3(0, 4, 0), rp)
              if not hit or hit.Instance:IsDescendantOf(pl.Character) then spotted = true break end
            end
          end
        end
      end
    end
    local show = spotted or (t - hurtT < 3)
    spot.Visible = show
    if show then
      spotTxt.Text = T("vh.spotted")
      local blink = (t * 2.5) % 1 < 0.6
      eye.TextTransparency = blink and 0 or 0.6
    end
    -- 爆反、主动防御
    local em = st.em
    local parts = {}
    local nEra = em and em:GetAttribute("Era")
    if nEra then
      local dead = 0
      for _ in string.gmatch(em:GetAttribute("EraX") or "", "%d+") do dead += 1 end
      table.insert(parts, T("vh.era", nEra - dead, nEra))
    end
    local aps = em and em:GetAttribute("ApsMax")
    if aps then table.insert(parts, T("vh.aps", em:GetAttribute("Aps") or 0, aps)) end
    armLine.Text = table.concat(parts, "   ·   ")
  end

  -- 不在开坦克：收起来，小地图放回去
  G.frameConn("TankHud", function()
    if not G.myVeh then
      if gui.Enabled then
        gui.Enabled = false
        for _, tg in ipairs(tags) do tg.f.Visible = false end
      end
      if docked then dock(false) end
    end
  end)
end

return TankHud
