-- 全游戏界面连拍（模拟器，一次开服拍完）：python3 tools/mock/run.py tools/mock/uishots.lua dir=<输出目录> [side=atk]
--   用户 11-25：「整个游戏风格极其割裂……四不像」——统一外观之前、之后各拍一套对比：
--   01 主菜单 → 02 机库（出击阵容）→ 03 科技树 → 04 开坦克（前方一辆敌车、打掉一辆出击杀提示）→ 05 计分板（Tab）
--   → 06 回机库再出一架飞机 → 07 结算页。每张写成 JSON（tools/mock/uidump.lua），tools/mock/hud_render.py 画成图：
--   for f in <目录>/*.json; do SS=2 BIG=1 python3 -I tools/mock/hud_render.py $f ${f%.json}.png; done
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local dir = TEST_ARGS:match("dir=(%S+)") or "."
local side = TEST_ARGS:match("side=(%a+)") or "atk"
local only = TEST_ARGS:match("only=(%S+)")   -- only=01,04：只拍这几张（省时间）
local dump = dofile(MOCK_DIR .. "/uidump.lua")

T.wtMode = true   -- 玩家不当步兵：机库出击（同真游戏）
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local TT = R.require(R.services.ReplicatedStorage:FindFirstChild("TechTree"))
local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))

local me = T.join("P1", 9401, true)
local C = T.C
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
local P = G.P[me]
P.team = side
me.Team = G.TEAM[side]
me.Neutral = false
me:SetAttribute("Side", side)
G.pushOne(P)
R.run(1.5)

local shots = {}
local function want(tag) return not only or only:find(tag, 1, true) ~= nil end
local function shot(tag, name)
  if not want(tag) then return end
  for _, d in ipairs(me.PlayerGui:GetDescendants()) do   -- 新手卡、作战简报只为截图收起
    if d.Name == "CoachCard" or d.Name == "OperationBrief" then d.Visible = false end
  end
  local items = dump(T, me, dir .. "/" .. tag .. "_" .. name .. ".json", true)
  table.insert(shots, tag .. "_" .. name)
  print(string.format("拍了 %s_%s（%d 个元素）", tag, name, #items))
end
local function find(nm, root)
  for _, d in ipairs((root or me.PlayerGui):GetDescendants()) do if d.Name == nm then return d end end
end

shot("01", "menu")
T.leaveMenu()
R.run(1)
T.runUntil(function() return type(me:GetAttribute("Tree")) == "string" end, 20)
R.run(1)
local hg = C.hangarGui
check(hg ~= nil and hg.Visible, "机库显示着")
shot("02", "hangar")

R.as("client", function() C.openTechTree() end)
R.run(0.6)
shot("03", "tree")
local tp = find("TechTree")
if tp then tp.Visible = false end
R.run(0.3)

-- 出击阵容里挑一辆地面车、一架飞机
local function lineupKey(branch)
  for _, c in ipairs(hg and hg:GetDescendants() or {}) do
    if c.Name:match("^Line_") then
      local it = TT.get(c.Name:sub(6))
      if it and it.branch == branch then return it.key end
    end
  end
end
local function sortie(key)
  if not key then return false end
  local card, go = nil, nil
  for _, c in ipairs(hg:GetDescendants()) do
    if c.Name == "Line_" .. key then card = c end
  end
  if card then T.press(card) R.run(0.2) end   -- 点卡片选中，再按右下大「出击」
  for _, c in ipairs(hg:GetDescendants()) do
    if c.Name == "HangarGo" then go = c end
  end
  if go and card then T.press(go) else T.act("deployVeh", key) end
  T.runUntil(function() return P.alive and P.vehicle ~= nil end, 15)
  return P.vehicle ~= nil
end

T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
R.run(1)
local gk = lineupKey("ground")
check(sortie(gk), "出击地面车：" .. tostring(gk))
if P.vehicle then
  R.run(2)
  local e = P.vehicle
  local foe = (side == "atk") and "def" or "atk"
  local ft = G.Config.Vehicles[foe].tank[1]
  local fd = VD.get(ft)
  local cf = e.root.CFrame
  local p1 = cf.Position + cf.LookVector * 420 + cf.RightVector * 40
  local p2 = cf.Position + cf.LookVector * 300 - cf.RightVector * 120
  pcall(function() G.newVehicle(foe, ft, G.vehBaseAt(fd, p1.X, p1.Z, -cf.LookVector)) end)
  local ex = nil
  pcall(function() ex = G.newVehicle(foe, ft, G.vehBaseAt(fd, p2.X, p2.Z, -cf.LookVector)) end)
  R.run(1)
  if ex then G.damageEnt(ex, 1e9, { P = P, team = P.team }) end   -- 打掉一辆：击杀提示、击杀栏
  R.run(1.2)
  shot("04", "tank")
  T.key(Enum.KeyCode.Tab, true)
  R.run(0.3)
  shot("05", "board")
  T.key(Enum.KeyCode.Tab, false)
  R.run(0.2)
  T.remoteAs(me, "Drive", { op = "exit" })
  T.runUntil(function() return P.vehicle == nil end, 10)
  R.run(2)
end
local ak = lineupKey("air")
if want("06") then
  check(sortie(ak), "出击飞机：" .. tostring(ak))
  if P.vehicle then
    R.run(2.5)
    shot("06", "jet")
  end
end
if want("07") then
  G.roundFinish(P.team)
  R.run(2)
  shot("07", "results")
end
print("拍好：" .. table.concat(shots, " "))
T.summary()
