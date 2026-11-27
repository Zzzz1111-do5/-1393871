-- 载具里按中键标记敌人给全队（模拟器）：python3 tools/mock/run.py tools/mock/vmark.lua
--   用户 11-27：「如果发现了敌载具可以进行全队标记 你仿照战雷就行」
--   ① 坦克试驾：准星对着靶道里的靶车按中键——服务器把它标给全队（G.spotted），客户端红菱形挂在那辆车的模型上（跟着它走）、远处也画
--   ② 准星附近没有敌人：提示「准星附近没有看得见的敌人」；冷却 2 秒
--   ③ 飞机试驾：对着训练场上空的靶机标记（服务器按飞机的 6 公里）
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

T.mapName = "city"
T.wtMode = true
T.rangeTerrain = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local RS = R.services.ReplicatedStorage
local TT = R.require(RS:FindFirstChild("TechTree"))
local me = T.join("P1", 9813, true)
T.runUntil(function() return G.round ~= nil end, 30)
local P = G.P[me]
local C = T.C
T.leaveMenu()
T.runUntil(function() return G.rangeReady == true and T.findNamed("HangarGo") ~= nil end, 600, 1 / 10)
R.run(1)

local MB3 = Enum.UserInputType.MouseButton3
local function middle()
  T.mouse(true, nil, nil, MB3)
  R.run(0.05)
  T.mouse(false, nil, nil, MB3)
end
local function msgSince(since, key)
  for i = since + 1, #R.sent do
    local s = R.sent[i]
    if s.name == "Msg" and s.args[2] == key then return true end
  end
  return false
end
-- 画出来的红菱形：挂在车模型上的在 PlayerGui.SpotMarks 下；找不到车的挂在 workspace 里一个看不见的小零件上
local function marks()
  local out = {}
  local function scan(root)
    for _, b in ipairs(root:GetDescendants()) do
      if b:IsA("BillboardGui") then
        local l = b:FindFirstChildWhichIsA("TextLabel")
        if l and l.Text == "◆" then table.insert(out, b) end
      end
    end
  end
  scan(me.PlayerGui)
  scan(R.services.Workspace)
  return out
end

print("① 坦克试驾：中键标记靶车")
local gKey
for _, k in ipairs(G.treeLineup(P)) do
  local it = TT.byKey[k]
  if it and it.branch == "ground" and not gKey then gKey = k end
end
T.act("testDrive", gKey)
T.runUntil(function() return P.alive and P.vehicle ~= nil and not P.vehicle.air and C.drive ~= nil end, 30)
R.run(2)
local e = P.vehicle
local st = C.drive
check(e ~= nil and st ~= nil, "坐进了试驾的地面车（" .. tostring(gKey) .. "）")
local tgt, td = nil, math.huge
for _, x in ipairs(G.ents or {}) do
  if x.alive and x.testDummy and not x.air and e then
    local d = (x.root.CFrame.Position - e.root.CFrame.Position).Magnitude
    if d < td then tgt, td = x, d end
  end
end
check(tgt ~= nil, string.format("靶道里有靶车（最近的 %.0f 格）", td))
if e and st and tgt then
  st.aimPt = tgt.root.CFrame.Position
  middle()
  R.run(1.2)
  local S = G.spotted and G.spotted[P.team]
  check(S ~= nil and S[tgt.id] ~= nil, "服务器把这辆靶车标给了全队")
  local ms = marks()
  local onModel, far = false, false
  for _, b in ipairs(ms) do
    if b.Adornee then onModel = true end
    if b.MaxDistance >= 1e4 then far = true end
  end
  local vf = C.viewFolder
  print(string.format("  诊断：菱形 %d 个，挂在车上 %s；viewFolder %s（%d 个）", #ms, tostring(onModel), tostring(vf ~= nil), vf and #vf:GetChildren() or 0))
  if vf then
    local p = tgt.root.CFrame.Position
    local best, cls = math.huge, "?"
    for _, m in ipairs(vf:GetChildren()) do
      local ok, pv = pcall(function() return m:GetPivot().Position end)
      if ok and (pv - p).Magnitude < best then best, cls = (pv - p).Magnitude, m.ClassName end
    end
    print(string.format("  诊断：离靶车最近的 %s %.1f 格", cls, best))
  end
  check(#ms >= 1 and far, string.format("客户端：画了红菱形、远处也画（%d 个）", #ms))
  check(onModel, "红菱形挂在那辆车的模型上（跟着它走）")

  print("② 准星附近没有敌人：提示；冷却")
  R.run(2.2)
  local n0 = #R.sent
  st.aimPt = e.root.CFrame.Position + e.root.CFrame.LookVector * -400 + V3(0, 300, 0)   -- 往身后天上指
  middle()
  R.run(0.5)
  check(msgSince(n0, "ui.markNone"), "准星附近没有敌人：提示「准星附近没有看得见的敌人」")
  local n1 = #R.sent
  middle()
  R.run(0.5)
  check(not msgSince(n1, "ui.markNone"), "2 秒冷却里再按：不理")
end
T.remoteAs(me, "Drive", { op = "exit", hangar = true })
T.runUntil(function() return not P.alive end, 15)
R.run(4)

print("③ 飞机试驾：标训练场上空的靶机")
T.act("testDrive", "cn_j6")
T.runUntil(function() return P.alive and P.vehicle ~= nil and P.vehicle.air end, 30)
R.run(1.5)
local ea = P.vehicle
local drone, dd = nil, math.huge
for _, x in ipairs(G.ents or {}) do
  if x.alive and x.testDummy and x.air and ea then
    local d = (x.root.CFrame.Position - ea.root.CFrame.Position).Magnitude
    if d < dd then drone, dd = x, d end
  end
end
check(drone ~= nil, string.format("训练场上空有靶机（最近的 %.0f 格）", dd))
if ea and drone then
  T.act("vmark", drone.root.CFrame.Position)
  R.run(0.5)
  local S = G.spotted and G.spotted[P.team]
  check(dd > 16800 or (S ~= nil and S[drone.id] ~= nil), string.format("飞机里标记靶机（%.0f 格，6 公里 = 16800 格以内能标）", dd))
end

T.summary()
