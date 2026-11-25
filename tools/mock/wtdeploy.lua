-- 战雷式直接出击（模拟器）：python3 tools/mock/run.py tools/mock/wtdeploy.lua [veh=leo2a6]
--   ① 没出生的时候：部署界面下面有出击栏（一张张车的卡）
--   ② 点一张（服务器 G.ACT.wtDeployVeh）：在主基地出生、出车、人坐进车里
--   ③ 侦察 / 火炮：坦克按 K 呼叫火炮支援（冷却写在属性上），轻型车按 G 侦察
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local VEH = TEST_ARGS:match("veh=(%w+)") or "leo2a6"

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8601, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.picked = true
local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))
local def = VD.get(VEH)
-- 这一型在哪一队：蓝方的车让玩家去蓝方
local Config = G.Config
local team = "atk"
for _, id in ipairs(Config.Vehicles.def.tank or {}) do if id == VEH then team = "def" end end
P.team = team
me.Team = G.TEAM[team]
me.Neutral = false
me:SetAttribute("Side", team)
G.pushOne(P)
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
T.runUntil(function() return G.round.phase == "battle" end, 90)
R.run(1.5)
print("① 出击栏")
local function find(name)
  for _, d in ipairs(me.PlayerGui:GetDescendants()) do if d.Name == name then return d end end
end
local strip = find("WtLineup")
check(strip ~= nil and T.visible(strip), "部署界面下面有出击栏")
local card = find("Deploy_" .. VEH)
check(card ~= nil, "有 " .. VEH .. " 那张卡")

print("② 点卡片：在车里出生")
if card then T.press(card) else T.actAsRemote(me, "wtDeployVeh", VEH) end
T.runUntil(function() return P.vehicle ~= nil end, 15)
R.run(0.5)
check(P.alive and P.vehicle ~= nil and P.vehicle.def and P.vehicle.def.id == VEH, "人坐在 " .. VEH .. " 里（" .. tostring(P.vehicle and P.vehicle.def and P.vehicle.def.id) .. "）")
check(P.vehicle and P.vehicle.driver == P, "是驾驶员")
local W = G.wtState(P)
check(W.ln[VEH] == 1, "进了出击阵容（" .. tostring(W.ln[VEH]) .. "）")

print("③ 火炮支援 K")
R.run(1)
local st = C.drive
if st then
  st.aimPt = P.vehicle.root.Position + V3(0, 0, -300)
  T.tap(Enum.KeyCode.K)
  R.run(0.5)
  check(me:GetAttribute("WtArtyCd") ~= nil, "火炮支援进了冷却（属性 WtArtyCd）")
  R.run(9)
end
T.summary()
