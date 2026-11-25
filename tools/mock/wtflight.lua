-- 战雷式的开飞机界面（模拟器）：python3 tools/mock/run.py tools/mock/wtflight.lua
--   用户 11-24 夜发了战雷的截图：「战雷ui压根不是这样的」「那个雷达屏在右侧」「不同导弹有不同锁定范围 锁定前大圈和小圈都是白色的 锁定就都变成红色」
--   「战雷不同的雷达会有不同的扫描图」「飞机本身会和自己的导弹形成数据链互相提供信息」「被发现那个标记移动到左侧」
--   ① 坐进歼-20：左上参数表（节流阀、表速、速度、马赫数、海拔高、雷达高、每种弹一行、热焰弹、干扰箔、燃油量、两台发动机的油温 / 引擎），
--      原来那套 MWT 式的（右上机型卡、准星两边高度速度、六边形武器键）收起来；机头 ⊕；顶上航向罗盘；圆形小地图在右上
--   ② 右侧雷达屏：在屏幕右半边，写 SRC PD、扫描范围、量程；Alt+Q 换量程、Alt+R 关掉（写 OFF，雷达弹看不见目标）再开
--   ③ 选红外弹（霹雳-10）、前方一架敌机：大圈小圈锁定前白、锁上红；锁定框写距离、接近速度、高度差
--   ④ 雷达告警圆盘：敌机雷达锁着我（服务器 rwrLock）→ 标型号、虚线；导弹打过来（rwr）→「MSL」
--   ⑤ 数据链：自己打出去的霹雳-15 在雷达屏上一个点、到目标一条线（导引头开机前虚线、开机后实线）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
T.runUntil(function() return G.worldReady end, 900)
G.Config.Bots.minPerTeam = 0
local me = T.join("P1", 9301, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
R.run(1)
local C = T.C
T.act("deploy", "rifle", G.Map.LANDONLY and "base" or "fleet")
R.run(3)
check(P.alive, "出生了")
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
local AD = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs"))

local function find(name)
  for _, d in ipairs(me.PlayerGui:GetDescendants()) do
    if d.Name == name then return d end
  end
end

print("① 坐进歼-20：左上参数表、机头 ⊕、航向罗盘；MWT 式的收起来")
local p0 = me.Character.HumanoidRootPart.Position
local cf = CF(p0.X, math.max(G.Map.ground(p0.X, p0.Z), 0) + 700, p0.Z)
local e = G.spawnAircraft("atk", "j20", cf, nil, P)
me.Character:PivotTo(cf * CF(4, 0, 0))
T.act("enterVeh", e.id)
R.run(0.2)
local st = C.fly
check(st ~= nil and st.pilot, "坐进了歼-20")
if not st then T.summary() return end
st.ground = false
st.spd = st.d.vMil * 0.8
st.vel = st.cf.LookVector * st.spd
st.vdir = st.cf.LookVector
st.thr, st.gearWant, st.gear = 85, 0, 0
R.run(1.5)
check(C.wtFlightOn == true and C.wtFlightGui and C.wtFlightGui.Enabled, "战雷式界面开着")
local labs = {}
for _, d in ipairs(C.wtFlightGui:GetDescendants()) do
  if d:IsA("TextLabel") and d.Visible and string.match(d.Name, "^Lab%d+") then labs[d.Text] = true end
end
local want = { "wt.thr", "wt.ias", "wt.tas", "wt.mach", "wt.alt", "wt.ralt", "wt.aam", "wt.flare", "wt.chaff", "wt.fuel", "wt.oil", "wt.eng" }
local miss = {}
for _, k in ipairs(want) do if not labs[C.T(k)] then table.insert(miss, C.T(k)) end end
check(#miss == 0, "左上参数表各行都在" .. ((#miss > 0) and ("（缺 " .. table.concat(miss, " ") .. "）") or ""))
local nEng = 0
for _, d in ipairs(C.wtFlightGui:GetDescendants()) do
  if d:IsA("TextLabel") and d.Visible and d.Text == C.T("wt.eng") then nEng = nEng + 1 end
end
check(nEng == #(st.d.eng or {}) and nEng >= 2, "歼-20 两台发动机：两组油温 / 引擎（" .. nEng .. "）")
check(not T.visible(find("AirCard")) and not T.visible(find("AltBracket")) and not T.visible(find("AirWeapons")), "MWT 式的右上机型卡、高度速度括号、六边形武器键收起来了")
check(T.visible(find("WtBore")), "机头 ⊕")
check(T.visible(find("WtHeading")), "顶上航向罗盘")
local box = C.hudParts and C.hudParts.miniBox
check(box and box.AnchorPoint.X == 1, "圆形小地图在右上")

print("② 右侧雷达屏")
local scope = find("RadarScope")
check(scope and T.visible(scope) and scope.Position.X.Scale == 1 and scope.AnchorPoint.X == 1, "雷达屏贴着屏幕右边")
local mode = find("RadarMode")
check(mode and mode.Text == "SRC PD", "写 SRC PD（搜索、脉冲多普勒）：" .. tostring(mode and mode.Text))
local zone, rng = find("RadarZone"), find("RadarRange")
check(zone and zone.Text == string.format("%d°×%d°", st.d.radar.az * 2, st.d.radar.el * 2), "扫描范围（方位 × 俯仰）：" .. tostring(zone and zone.Text))
local r0 = rng and rng.Text
local function altKey(code)
  T.key(Enum.KeyCode.LeftAlt, true)
  T.tap(code)
  T.key(Enum.KeyCode.LeftAlt, false)
  R.run(0.2)
end
altKey(Enum.KeyCode.Q)
check(rng and rng.Text ~= r0, "Alt+Q 换量程：" .. tostring(r0) .. " → " .. tostring(rng and rng.Text))
altKey(Enum.KeyCode.R)
check(mode.Text == "OFF" and C.radarOn and C.radarOn() == false, "Alt+R 关雷达：写 OFF")
altKey(Enum.KeyCode.R)
check(C.radarOn and C.radarOn() == true and string.sub(mode.Text, 1, 3) == "SRC", "再按一下又开了")

print("③ 红外弹的大圈小圈：锁定前白、锁上红；锁定框")
local fe = G.spawnAircraft("def", "f16", st.cf * CF(40, 15, -600), nil, nil)
R.run(0.3)
for i, wid in ipairs(st.wl) do
  local w = AD.W[wid]
  if w and w.seeker == "ir" then st.wi = i end
end
st.lock, st.lockT = nil, 0
R.run(0.4)
local w = AD.W[st.wl[st.wi]]
check(w and w.seeker == "ir", "选了红外弹：" .. tostring(st.wl[st.wi]))
local cone, head = find("SeekerCone"), find("SeekerHead")
local function strokeOf(f) return f and f:FindFirstChildOfClass("UIStroke") end
check(cone and head and T.visible(cone) and T.visible(head), "大圈、小圈都在")
local function isWhite(c) return c.R > 0.95 and c.G > 0.95 and c.B > 0.95 end
local function isRed(c) return c.R > 0.9 and c.G < 0.45 and c.B < 0.4 end
if st.lock then st.lockT = 0.05 end
R.run(1 / 30)
check(cone and isWhite(strokeOf(cone).Color) and isWhite(strokeOf(head).Color), "锁定前：都是白的")
if st.lock and w then st.lockT = (w.lockTime or 1) + 0.1 end
R.run(1 / 30)
check(st.lock ~= nil and cone and isRed(strokeOf(cone).Color) and isRed(strokeOf(head).Color), "锁上了：都变红")
local lb = find("WtLockBox")
check(lb and T.visible(lb) and lb:FindFirstChild("Range") and lb:FindFirstChild("Range").Text:find("m") ~= nil and lb:FindFirstChild("Closure").Text:find("m/s") ~= nil,
  "锁定框：距离 " .. tostring(lb and lb:FindFirstChild("Range") and lb.Range.Text) .. "、接近速度 " .. tostring(lb and lb:FindFirstChild("Closure") and lb.Closure.Text))
check(lb and lb:FindFirstChild("AltDiff") and lb.AltDiff.Text ~= "", "高度差：" .. tostring(lb and lb:FindFirstChild("AltDiff") and lb.AltDiff.Text))
local sel = find("WtSeeker")
check(sel and sel.Text == C.T("wt.seeker", C.T("wt.seekLock")), "底下写「导引头：已锁定」：" .. tostring(sel and sel.Text))

print("④ 雷达告警圆盘")
if fe then
  fe.root.CFrame = R.CFrame.lookAt(st.cf.Position + st.cf.RightVector * 900, st.cf.Position)   -- 在我右边、机头对着我
  R.run(0.3)
  R.as("client", function() C.wtRwrEvent("rwrLock", { by = fe.id }) end)
  R.run(0.2)
  local rwr = find("WtRwr")
  local tag, dash = nil, 0
  for _, d in ipairs(rwr:GetDescendants()) do
    if d:IsA("TextLabel") and d.Visible and d.Text == "F16" then tag = d end
    if d.Name == "RwrDash" and d.Visible then dash = dash + 1 end
  end
  check(tag ~= nil, "敌机雷达锁着我：标它的型号（F16）")
  check(tag and tag.Position.X.Offset > 75, "在圆盘右边（它在我右边）")
  check(dash >= 3, "锁着我：虚线连到中间（" .. dash .. " 段）")
  R.as("client", function() C.wtRwrEvent("rwr", { id = 1, w = "aim120" }) end)
  local msl = false
  for _ = 1, 8 do
    R.run(1 / 15)
    for _, d in ipairs(rwr:GetDescendants()) do if d:IsA("TextLabel") and d.Visible and d.Text == "MSL" then msl = true end end
  end
  check(msl, "导弹打过来：「MSL」")
end

print("⑤ 数据链：自己打出去的霹雳-15（真的打：服务器发弹、导引头开机时 shotAct）")
local pl15i = nil
for i, wid in ipairs(st.wl) do
  local ww = AD.W[wid]
  if ww and ww.seeker == "radar" then pl15i = pl15i or i end
end
check(pl15i ~= nil, "歼-20 挂着雷达弹")
if pl15i and fe then
  st.wi = pl15i
  local wid = st.wl[pl15i]
  local ww = AD.W[wid]
  fe.root.CFrame = st.cf * CF(30, 20, -3300)   -- 导引头开机距离（霹雳-15 2800 格）以外：先走数据链
  st.lock, st.lockT = nil, 0
  local locked = T.runUntil(function()
    fe.root.CFrame = C.fly.cf * CF(30, 20, -3300)   -- 自己在往前飞：敌机跟着摆在前方
    return st.lock ~= nil and st.lockT >= (ww.lockTime or 1)
  end, 8)
  check(locked, "雷达锁上了前方 3300 格的敌机")
  if locked then
    R.as("client", function() C.R.Drive:FireServer({ op = "fire", w = wid, tgt = st.lock.id, aim = st.aimPt }) end)
    local fs = nil
    T.runUntil(function()
      for _, s in pairs(C.flyingShots) do if s.my and s.aw and s.aw.seeker == "radar" then fs = s end end
      return fs ~= nil
    end, 2)
    check(fs ~= nil, "打出去了（客户端收到这发弹）")
    R.run(0.1)
    local function scopeSegs()
      local dot, red, white = nil, 0, 0
      for _, d in ipairs(scope:GetDescendants()) do
        if d.Name == "Missile" and T.visible(d) then dot = d end
        if d.Name == "DlSeg" and T.visible(d) then
          local c = d.BackgroundColor3
          if c.R > 0.9 and c.G < 0.5 then red = red + 1 else white = white + 1 end
        end
      end
      return dot, red, white
    end
    local dot, red, white = scopeSegs()
    check(dot ~= nil, "雷达屏上有这发弹（一个点）")
    check(fs and not fs.act and white >= 2, "导引头开机前：虚线（" .. white .. " 段）")
    local act = T.runUntil(function() return fs.act == true end, 4)
    check(act, "飞近了、导引头开机：客户端收到 shotAct")
    dot, red, white = scopeSegs()
    check(red >= 6, "开机以后：红色实线（" .. red .. " 段）")
  end
end

T.summary()
