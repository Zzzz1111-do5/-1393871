-- 车里地图屏上的军标（模拟器）：python3 tools/mock/run.py tools/mock/mapsym.lua [veh=m1a2]
--   用户 11-22：「电子屏地图要能显示敌单位，坦克、车之类的要有不同符号」
--   坐进 M1A2，周围摆一圈敌人：坦克、装甲车、自行火炮、防空车、直升机、战斗机、步兵、工事；车长的指挥地图（JBC-P）上：
--   每个都画成军标（敌军红菱形框，框里的图形分兵种），友军蓝长方框；兵种认得对
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local VEH = TEST_ARGS:match("veh=(%w+)") or "m1a2"

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8101, true)
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
local Map = G.Map

local def = VD.get(VEH)
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or V3(Map.CAMP.x, 0, Map.CAMP.z)
local bx, bz = hp.X + 16, hp.Z
for k = 0, 23 do
  local a = k / 24 * math.pi * 2
  local x, z = hp.X + math.cos(a) * 20, hp.Z + math.sin(a) * 20
  if Map.isLand(x, z) and Map.slope(x, z) < 0.2 then bx, bz = x, z break end
end
local e = G.newVehicle("def", VEH, G.vehBaseAt(def, bx, bz, V3(0, 0, -1)))
if hrp then me.Character:PivotTo(CF(bx + def.W / 2 + 4, Map.height(bx, bz) + 3, bz)) end
R.run(0.5)
T.act("enterVeh", e.id)
R.run(1)
check(P.vehicle == e and C.drive ~= nil, "坐上了 " .. VEH)
T.runUntil(function() return G.round.phase == "battle" end, 60)

print("① 周围摆一圈敌人（400 格内，车长看得见）")
local want = {}
local function spot(i, n, r)
  local a = i / n * math.pi * 2
  local x, z = bx + math.cos(a) * r, bz + math.sin(a) * r
  return x, z
end
local list = { { "veh", "ztz99a", "tank" }, { "veh", "zbd05", "apc" }, { "veh", "plz07", "arty" }, { "veh", "pgz07", "aa" },
  { "air", "z10", "heli" }, { "air", "j20", "jet" }, { "bot", nil, "inf" } }
for i, it in ipairs(list) do
  local x, z = spot(i, #list, 260)
  local id
  if it[1] == "veh" then
    local d2 = VD.get(it[2])
    local ve = G.newVehicle("atk", it[2], G.vehBaseAt(d2, x, z, V3(0, 0, 1)))
    id = ve and ve.id
  elseif it[1] == "air" then
    local y = Map.height(x, z) + 200
    local ae = G.newEnt({ kind = "air", team = "atk", cat = "air", hp = 500, size = V3(12, 5, 18), cf = CF(x, y, z), air = true })
    ae.model:SetAttribute("Model", it[2])
    id = ae.id
  else
    local be = G.newEnt({ kind = "bot", team = "atk", cat = "inf", hp = 100, size = V3(2, 5, 2), cf = CF(x, Map.height(x, z) + 2.5, z) })
    id = be.id
  end
  want[tostring(id)] = it[3]
end
R.run(1)

print("② 车长位：指挥地图上的军标")
T.tap(Enum.KeyCode.C)
R.run(0.6)
for _ = 1, 4 do
  if C.interiorState().station == "commander" then break end
  T.tap(Enum.KeyCode.F4)
  R.run(0.3)
end
local I = C.interiorState()
check(I.mode == "seat" and I.cur ~= nil, "坐进车里（" .. tostring(I.station) .. "）")
R.run(1.0)
local d = I.cur and I.cur.data
local got = {}
for _, en in ipairs(d and d.ents or {}) do
  if en.team ~= "def" and en.typ then got[en.typ] = (got[en.typ] or 0) + 1 end
end
local miss = {}
for _, t in ipairs({ "tank", "apc", "arty", "aa", "heli", "jet", "inf" }) do
  if not got[t] then table.insert(miss, t) end
end
check(#miss == 0, "敌人的兵种都认得对（缺 " .. table.concat(miss, ",") .. "）")
-- 地图屏：看得见的军标（红菱形框）数、框里的图形有几种
local scr
for _, s in ipairs(I.cur.b.screens) do if s.page == "cid" or s.page == "cnmap" then scr = s end end
check(scr ~= nil, "车里有指挥地图屏")
if scr then
  local dias, rects, shapes = 0, 0, {}
  for _, f in ipairs(scr.root:GetDescendants()) do
    if f:IsA("Frame") and f.Rotation == 45 and f.Size.X.Offset == 12 and f.Visible and f.Parent and f.Parent.Visible then
      dias = dias + 1
      local icon = nil
      for _, ch in ipairs(f.Parent:GetChildren()) do if ch ~= f and ch:IsA("Frame") and ch.Size.X.Offset == 20 then icon = ch end end
      local n = icon and #icon:GetChildren() or 0
      shapes[n] = (shapes[n] or 0) + 1
    elseif f:IsA("Frame") and f.Size.X.Offset == 16 and f.Size.Y.Offset == 11 and f.Visible and f.Parent and f.Parent.Visible then
      rects = rects + 1
    end
  end
  local kinds = 0
  for _ in pairs(shapes) do kinds = kinds + 1 end
  check(dias >= #list, string.format("地图上敌军军标（红菱形框）%d 个（摆了 %d 个）", dias, #list))
  check(kinds >= 4, string.format("框里的图形有 %d 种（坦克椭圆、装甲车叉加椭圆、炮兵圆点、防空拱、直升机蝴蝶结、飞机尖头、步兵叉）", kinds))
end
T.summary()
