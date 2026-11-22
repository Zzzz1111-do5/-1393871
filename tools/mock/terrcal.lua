-- 地形网格器校准 + 车摆在真地面上（模拟器）：python3 tools/mock/run.py tools/mock/terrcal.lua [model=blob|lin|iso]
--   用户 11-22：「无数个 AI 修了半天修不好，坦克半截身子卡在地里」——车、小兵、沙袋按 Map.height 摆，
--   Roblox 地形网格器画出来的地面却不是「最上面那层体素填几成，地面就在几成高」，画出来高一截。
--   模拟器里假装一种网格器（R.surfFrac：最上面那层填 o 成，地面在这层的几成高）：
--     blob：填一点点就画出半层（0.5 + 0.5 × o）——最坏的情况；lin：几成满就几成高；iso：按 0.5 等值面插值（Surface Nets 那种）
--   ① 开服量出来的对照表和假装的网格器对得上；试验平台量完拆掉；Terrain 上有 SurfCal 属性
--   ② 按对照表写的地形：画出来的地面离 Map.height 多远（和不校准的原写法比）
--   ③ 地面画得比 Map.height 高 1.6 格（假装校准没做成）：自己开的车、别人的车都抬到看得见的地面上
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, Enum = T.R, T.V3, T.Enum
local check = T.check
local MODEL = TEST_ARGS:match("model=(%w+)") or "blob"

local MODELS = {
  blob = function(o) return 0.5 + 0.5 * o end,
  lin = function(o) return o end,
  iso = function(o)
    if o < 0.5 then return -0.5 + 0.5 / (1 - o) end
    return 0.5 + (o - 0.5) / o
  end,
}
local SF = MODELS[MODEL]
R.surfFrac = SF

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 300)
check(G.worldReady, "地图生成好了")
local W = G.World
local Map = G.Map

print("① 开服量网格器（假装的网格器：" .. MODEL .. "）")
local CAL = W.terrainCal and W.terrainCal() or {}
local LG = CAL.LeafyGrass
check(LG ~= nil and CAL.Sand ~= nil, "草地（LeafyGrass）、沙地都量了")
if LG then
  local worst, line = 0, {}
  for a = 1, #LG.o do
    local o = LG.o[a]
    local want = (o <= 0) and 0 or ((o >= 1) and 1 or SF(o))
    worst = math.max(worst, math.abs(LG.s[a] - want))
    table.insert(line, string.format("%g→%.2f", o, LG.s[a]))
  end
  check(worst < 0.02, string.format("量出来的「占有率 → 地面几成高」和网格器一样（最多差 %.3f 层）：%s", worst, table.concat(line, " ")))
end
local terr = R.services.Workspace:FindFirstChildOfClass("Terrain")
local attr = terr and terr:GetAttribute("SurfCal")
check(type(attr) == "string" and string.find(attr, "LeafyGrass=", 1, true) ~= nil, "Terrain 上记着对照表（SurfCal）")
local left = 0
for _ in pairs(R.voxCols or {}) do left = left + 1 end
check(left == 0, "试验平台量完拆掉了（剩 " .. left .. " 列）")

print("② 按对照表写的地形：画出来的地面离 Map.height 多远")
-- 网格器画出来的地面：最上面那层 jT 填 oT（0 就是这层空、下面一层满）
local function drawn(jT, oT)
  if oT <= 0 then return jT * 4 end
  return jT * 4 + 4 * ((oT >= 1) and 1 or SF(oT))
end
-- 原来的写法（不校准）：地面在几成高就填几成、最少 5%
local function oldWay(h)
  local x = h / 4
  local j = math.floor(x)
  local f = x - j
  if f <= 1e-6 then return j, 0 end
  return j, math.max(f, 0.05)
end
local sumNew, maxNew, sumOld, maxOld, upOld, n = 0, 0, 0, 0, 0, 0
for i = 0, 399 do
  local h = 6 + i * 0.0731   -- 一路往上，覆盖一层体素里各个位置
  local jn, on = W.surfAt(h, "LeafyGrass")
  local jo, oo = oldWay(h)
  local en, eo = drawn(jn, on) - h, drawn(jo, oo) - h
  sumNew = sumNew + math.abs(en)
  maxNew = math.max(maxNew, math.abs(en))
  sumOld = sumOld + math.abs(eo)
  maxOld = math.max(maxOld, math.abs(eo))
  upOld = upOld + eo
  n = n + 1
end
print(string.format("   原写法：平均差 %.2f 格（平均高出 %.2f 格），最多 %.2f 格；校准后：平均差 %.2f 格，最多 %.2f 格", sumOld / n, upOld / n, maxOld, sumNew / n, maxNew))
local limit = (MODEL == "blob") and 1.1 or 0.25   -- blob：一层里最下面那半层画不出来（只能挑近的），最多差半层的一半
check(maxNew <= limit, string.format("校准后画出来的地面离 Map.height 最多 %.2f 格（不超过 %.2f）", maxNew, limit))
check(sumNew / n <= sumOld / n + 1e-6, "校准后不比原写法差")

print("③ 地面画得比 Map.height 高 1.6 格：车都抬到看得见的地面上")
local me = T.join("P1", 8301, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = "def"
me.Team = G.TEAM.def
me.Neutral = false
me:SetAttribute("Side", "def")
G.pushOne(P)
R.run(1)
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
T.actAs(me, "deploy", "rifle", "camp")
R.run(1.5)
local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))
local def = VD.get("m1a2")
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or V3(Map.CAMP.x, 0, Map.CAMP.z)
local spots = {}
for k = 0, 47 do
  local a = k / 48 * math.pi * 2
  for _, rr in ipairs({ 24, 40, 60 }) do
    local x, z = hp.X + math.cos(a) * rr, hp.Z + math.sin(a) * rr
    if Map.isLand(x, z) and Map.height(x, z) > 2 and Map.slope(x, z) < 0.2 then table.insert(spots, { x, z }) end
  end
end
check(#spots >= 2, "营地边上找到两块平地放车")
if #spots < 2 then T.summary() return end
local a1, a2 = spots[1], spots[#spots]
local mine = G.newVehicle("def", "m1a2", G.vehBaseAt(def, a1[1], a1[2], V3(0, 0, -1)))
local other = G.newVehicle("def", "m1a2", G.vehBaseAt(def, a2[1], a2[2], V3(0, 0, -1)))
R.run(0.5)
T.act("enterVeh", mine.id)
R.run(1.5)
check(P.vehicle == mine and C.drive ~= nil, "坐上了 M1A2")
local function myBaseY()
  local d = C.drive
  return d and d.root and (d.root * R.CFrame.new(0, -def.H / 2, 0)).Position.Y
end
local function viewBaseY(e)
  local v = C.viewById and (C.viewById(e.id) or C.viewById(tostring(e.id)))
  if not v or not v.hullF then return nil end
  return v.hullF.Position.Y - (v.bob or 0)
end
local y0 = myBaseY()
local m0 = Map.height(a1[1], a1[2])
local o0 = viewBaseY(other)
check(y0 ~= nil and math.abs(y0 - m0) < 0.6, string.format("地面对得上时：自己的车底在 Map.height 上（差 %.2f 格）", (y0 or 0) - m0))
local H0 = R.terrainHeight
R.terrainHeight = function(x, z) return H0(x, z) + 1.6 end
R.run(2)
local y1 = myBaseY()
local o1 = viewBaseY(other)
do
  local v = C.viewById and (C.viewById(other.id) or C.viewById(tostring(other.id)))
  print(string.format("   （别人的车：量的 %.2f、平滑后 %.2f；自己的车：%.2f）", v and v.tLiftT or -99, v and v.tLift or -99, C.drive and C.drive.tLift or -99))
end
check(y1 ~= nil and y0 ~= nil and math.abs((y1 - y0) - 1.6) < 0.25, string.format("自己开的车跟着抬起来 %.2f 格（要 1.6）", (y1 or 0) - (y0 or 0)))
if o0 and o1 then
  check(math.abs((o1 - o0) - 1.6) < 0.3, string.format("别人的车（服务器按 Map.height 放的）画出来也抬起来 %.2f 格", o1 - o0))
else
  check(false, "别人的车：View 里找得到（viewById）")
end
R.terrainHeight = H0
R.run(2)
local y2 = myBaseY()
check(y2 ~= nil and math.abs(y2 - y0) < 0.25, string.format("地面回到原来：车也落回去（差 %.2f 格）", (y2 or 0) - (y0 or 0)))
T.summary()
