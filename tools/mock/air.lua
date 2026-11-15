-- 飞机、直升机测试（模拟器）：python3 tools/mock/run.py tools/mock/air.lua [atk|def] [v]
--   部署界面选型号、出生点、挂载 → 坐进座舱 → 起飞（油门、抬头、收起落架）→ 飞行（鼠标瞄准、加力、失速）→ 航炮 → 锁定发射导弹 → 热诱弹 →
--   炸弹 → 弹舱门 → 落地补弹 → 跳伞；直升机：起飞悬停、旋翼转速、机头炮塔、火箭巢；模型：舵面、起落架、旋翼动画
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, Enum = T.R, T.V3, T.Enum
local check = T.check
local side = TEST_ARGS:match("def") and "def" or "atk"

local G = T.boot()
G.fortsHold = true   -- 这里测的不是工事：工事不开火
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 120)
local me = T.join("P1", 5001, true)
local other = T.join("P2", 5002, false)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local function setTeam(pl, team)
  local P = G.P[pl]
  P.team = team
  pl.Team = G.TEAM[team]
  pl.Neutral = false
  pl:SetAttribute("Side", team)
  G.pushOne(P)
end
local foe = side == "def" and "atk" or "def"
setTeam(me, side)
setTeam(other, foe)
R.run(1)
local P, PO = G.P[me], G.P[other]
local AD = require and nil
AD = R.requireModule and R.requireModule("AirDefs") or nil
local C = T.C

print("① 部署界面：飞机型号、出生点、挂载")
local jets = G.Config.Vehicles[side].jet
local jetId = (side == "atk") and "j20" or "f22"
local has = false
for _, id in ipairs(C.S.vehModels or {}) do if id == jetId then has = true end end
check(has, "能选的型号里有 " .. jetId .. "：" .. table.concat(C.S.vehModels or {}, ","))
check(C.S.vehAvail and C.S.vehAvail.jet and C.S.vehAvail.jet.cap >= 1, "固定翼名额 " .. tostring(C.S.vehAvail and C.S.vehAvail.jet and C.S.vehAvail.jet.cap))
check(C.S.airSpawns and C.S.airSpawns.jet and #C.S.airSpawns.jet > 0, "固定翼出生点 " .. tostring(C.S.airSpawns and C.S.airSpawns.jet and #C.S.airSpawns.jet))
local spawnId = (side == "atk") and "air.af2" or "air.af"
T.actAs(me, "deployVeh", jetId, spawnId, "rifle", nil)
R.run(2)
local e = P.vehicle
check(e ~= nil and e.air and e.def.id == jetId, "坐进了 " .. tostring(e and e.def.id))
if e then
  local n = 0
  for _, k in ipairs(e.stores) do n = n + k end
  check(n > 0, "按预设挂了 " .. n .. " 枚：" .. e.model:GetAttribute("Load"))
  local p = e.root.CFrame.Position
  check(math.abs(p.Y - G.airSurface(p.X, p.Z) - e.def.gearH) < 0.5, string.format("停在跑道上（离地 %.1f 格）", p.Y - G.airSurface(p.X, p.Z)))
end
T.summary()
