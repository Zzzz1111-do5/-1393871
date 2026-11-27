-- 直升机机头炮塔（模拟器）：python3 tools/mock/run.py tools/mock/heligun.lua [air=ah64e|mi28|mi24]（原来还能测直-10，11-27 删了）
--   用户 11-21：直升机炮管不会转动。原模型的机炮原来和机身烘焙在一块网格里；tools/models/air2glb.py 把它拆成 Gun（方位 + 俯仰）、GunY（炮塔座，只转方位）。
--   假装在 Studio 里导入了新版原模型（ah64_v2 等），开直升机、镜头往右边看、往下看：炮管跟着转过去、压下去，炮塔座只跟着转方位
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local AIR = TEST_ARGS:match("air=(%w+)") or "ah64e"
local IA
do
  local f = assert(io.open(SRC_DIR .. "/ReplicatedStorage/ImportedAir.lua"))
  IA = load(f:read("a"))()
  f:close()
end
local IKEY = IA.alias[AIR]
for name, p in pairs(IA.m[IKEY].parts) do
  local mp = R.Instance.new("MeshPart")
  mp.Name = "A_" .. IKEY .. "__" .. name
  mp.Size = V3(p.s[1], p.s[2], p.s[3])
  mp.CFrame = T.CF(900 + p.c[1], 200 + p.c[2], 900 + p.c[3])
  mp.Parent = R.services.Workspace
end

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 5001, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local side = (AIR == "mi28" or AIR == "mi24") and "atk" or "def"
local P = G.P[me]
P.team = side
me.Team = G.TEAM[side]
me.Neutral = false
me:SetAttribute("Side", side)
G.pushOne(P)
R.run(1)
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
T.runUntil(function() return G.round.phase == "battle" end, 90)
T.act("deploy", "rifle", (side == "def") and "camp" or "fleet")
R.run(2)
print("① 生成 " .. AIR .. "（原模型 " .. IKEY .. "）、坐上")
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or V3(0, 20, 0)
local AD = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs"))
local d = AD.get(AIR)
local pos = V3(hp.X + 30, G.airSurface(hp.X + 30, hp.Z) + d.gearH, hp.Z)
local e = G.spawnAircraft(side, AIR, CF(pos), nil, P, 1)
R.run(1)
if e and P.vehicle ~= e then T.act("enterVeh", e.id) R.run(1) end
local fst = C.fly
check(e ~= nil and P.vehicle == e and fst ~= nil, "坐上了 " .. AIR)
local v
for em, vv in pairs(C.views or {}) do if e and em == e.model then v = vv end end
check(v ~= nil and v.M ~= nil and v.M.imported == IKEY, "用的是新版原模型（" .. tostring(v and v.M and v.M.imported) .. "）")
if not (v and v.M and fst) then T.summary() return end
local gun, guny = {}, {}
for _, it in ipairs(v.M.items) do
  if string.find(it.p.Name, "__Gun_") then table.insert(gun, it) end
  if string.find(it.p.Name, "__GunY_") then table.insert(guny, it) end
end
check(#gun > 0 and gun[1].kind == "t", string.format("机炮是单独的炮塔件（%d 块）", #gun))
check(v.M.gunPiv ~= nil, "知道耳轴在哪（按它算瞄准）")
local function rel(it)   -- 这块在机体坐标里相对耳轴的位置
  return v.cf:PointToObjectSpace(it.p.Position) - v.M.gunPiv
end
local g0, y0 = rel(gun[1]), guny[1] and rel(guny[1])
print("② 镜头往右转 60°：炮管跟着转过去")
local lk = fst.cf.LookVector
fst.camYaw = math.atan2(-lk.X, -lk.Z) - math.rad(60)
fst.camPitch = -0.15
R.run(1.5)
check(math.abs(fst.ty or 0) > 20, string.format("炮塔方位角 %.0f°", fst.ty or 0))
local g1 = rel(gun[1])
local function hang(a, b) return math.deg(math.acos(math.max(-1, math.min(1, V3(a.X, 0, a.Z).Unit:Dot(V3(b.X, 0, b.Z).Unit))))) end
check(hang(g0, g1) > 20, string.format("炮管转过去了 %.0f°", hang(g0, g1)))
if y0 then
  local y1 = rel(guny[1])
  check(hang(y0, y1) > 20 or V3(y0.X, 0, y0.Z).Magnitude < 0.3, string.format("炮塔座跟着转方位（%.0f°）", hang(y0, y1)))
  check(math.abs(y1.Y - y0.Y) < 0.05, "炮塔座不跟着俯仰")
end
print("③ 升到空中、往下看：炮管压下去")
T.key(Enum.KeyCode.E, true)   -- 提总距升空（停在地上时瞄准点就在炮口跟前，压不下去）
T.runUntil(function() return not fst.ground and fst.cf.Position.Y > pos.Y + 40 end, 20)
T.key(Enum.KeyCode.E, false)
local g1b = rel(gun[1])
fst.camPitch = -0.7
R.run(1.5)
g1 = g1b
check((fst.gp or 0) < -10, string.format("炮的俯仰角 %.0f°", fst.gp or 0))
local g2 = rel(gun[1])
check(g2.Y < g1.Y - 0.1, string.format("炮管前端往下了（%.2f → %.2f 格）", g1.Y, g2.Y))
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
