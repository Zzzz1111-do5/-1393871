-- 战雷式车辆受伤的样子（模拟器）：python3 tools/mock/run.py tools/mock/wtvfx.lua
--   用户 11-26「很多载具自带爆反，识别并实现它们的效果；不同部位被击中也要有不同效果，如弹药舱燃烧、炮管损毁、殉爆、观瞄受损之类的，并且对应效果」
--   ① T-72B3 原模型上的爆反（接触-5 眉毛、首上、侧屏）登记上了：出车就有爆反块、起作用
--   ② 观瞄（optics 模块）：打坏了——开镜镜里裂成一片、只剩最低倍率；电脑车打得不准（G.wtOptK）
--   ③ 弹药架起火（WtAF）：舱口往上喷火柱、火星；起火（WtF）：发动机舱火苗 + 黑烟 + 火光
--   ④ 发动机打坏：发动机盖冒黑烟；炮管打坏：炮管耷拉下来；履带打断：那边的履带板停住
--   ⑤ 泄压板（M1A2，WtBlow 变了）：尾舱顶上一道火柱
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local KEY = "t72b3"
T.fakeImport(KEY)
local me = T.join("P1", 8701, true)
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
T.actAs(me, "deploy", "rifle", "base")
R.run(1.5)
local RS = R.services.ReplicatedStorage
local VD = R.require(RS:FindFirstChild("VehDefs"))
local W = R.require(RS:FindFirstChild("WtDamage"))
local Map = G.Map
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or V3(0, 0, 0)
local def = VD.get(KEY)
local bx, bz = hp.X + 30, hp.Z
local e = G.newVehicle("def", KEY, G.vehBaseAt(def, bx, bz, V3(0, 0, -1)))
R.run(1)

print("① T-72B3 自带的爆反")
check(e.era ~= nil and (e.era.n or 0) >= 20, string.format("出车就有爆反块（%s 块，型号 %s）", tostring(e.era and e.era.n), tostring(e.era and e.era.L and e.era.L.kind)))
check(e.model:GetAttribute("Era") == (e.era and e.era.n), "车上记着爆反块数（Era 属性）")

print("② 观瞄")
check(W.modIndex(def, "optics") ~= nil, "T-72B3 有观瞄模块（WtM 第 " .. tostring(W.modIndex(def, "optics")) .. " 位）")
if hrp then me.Character:PivotTo(CF(bx + def.W / 2 + 4, Map.height(bx, bz) + 3, bz)) end
R.run(0.3)
T.act("enterVeh", e.id)
R.run(1)
local st = C.drive
check(st ~= nil, "坐进了车")
check(G.wtOptK(e) == 1, "观瞄好的：电脑车散布倍数 1")
local opt = e.wt.byK.optics
opt.hp = 0
G.wtPush(e)
R.run(0.3)
check(G.wtOptK(e) == 3, "观瞄打坏：电脑车散布 × 3（" .. tostring(G.wtOptK(e)) .. "）")
check(C.wtModState(e.model, def, "optics") == 0, "客户端读到观瞄打坏了")
if st and C.driveToggleSight then C.driveToggleSight() end
R.run(0.6)
local gui, hurtSet, deadSet = C.sightDamageGui()
check(st and st.sight == true, "开了镜")
check(gui.Enabled and deadSet.Visible and not hurtSet.Visible, "镜里裂成一片（打坏那一套裂纹）")
check(C.opticsDead() == true, "只剩最低倍率、没有热成像（G.opticsDead）")
local cam = R.workspace.CurrentCamera
local zs = C.driveZooms and select(1, C.driveZooms())
if zs then
  if st then st.zoom = #zs end
  R.run(0.8)
  check(math.abs(cam.FieldOfView - zs[1]) < 2, string.format("倍率按到最大，视野还是最低倍率那一档（%.1f / %.1f）", cam.FieldOfView, zs[1]))
end
opt.hp = opt.max
G.wtPush(e)
R.run(0.3)
check(not gui.Enabled, "修好了：裂纹没了")
if st and C.driveToggleSight then C.driveToggleSight() end
R.run(0.3)

local function vview()
  for em2, v in pairs(C.views or {}) do if em2 == e.model then return v end end
end
local function fxOf()
  local v = vview()
  if not v or not v.model then return nil end
  local n = { jet = 0, fire = 0, smoke = 0 }
  for _, x in ipairs(v.model:GetDescendants()) do
    if x:IsA("ParticleEmitter") and x.Parent and x.Parent.Name == "WtVfx" then
      if x.Rate > 50 and x.Speed.Min > 15 then n.jet = n.jet + 1 end
      if x.Texture:find("fire") and x.Rate > 0 then n.fire = n.fire + 1 end
      if x.Texture:find("smoke") and x.Rate > 0 then n.smoke = n.smoke + 1 end
    end
  end
  return n
end

print("③ 弹药架起火")
e.wt.fireT, e.wt.ammoFireT, e.wt.fireUntil = os.clock(), os.clock(), os.clock() + 8
G.wtPush(e)
R.run(0.5)
local f = fxOf()
check(e.model:GetAttribute("WtAF") == true, "车上记着弹药架起火（WtAF）")
check(f ~= nil and f.jet >= 1, "舱口往上喷火柱（" .. tostring(f and f.jet) .. " 道）")
T.actAs(me, "wtExt")
R.run(0.5)
check(e.model:GetAttribute("WtAF") == false and e.model:GetAttribute("WtF") == false, "灭火器：弹药架的火也灭了")

print("④ 发动机、炮管、履带")
e.wt.byK.engine.hp = 0
G.wtPush(e)
R.run(0.5)
f = fxOf()
check(f ~= nil and f.smoke >= 1, "发动机打坏：发动机盖冒黑烟")
e.wt.byK.barrel.hp = 0
G.wtPush(e)
R.run(2)
local v = vview()
check(v ~= nil and v.gp < -3.5, string.format("炮管打坏：炮管耷拉下来（%.1f°）", v and v.gp or 0))
e.wt.byK.trackL.hp = 0
G.wtPush(e)
R.run(0.3)
-- 车往前挪：左边的履带板不走、右边照走
local links = {}
for _, p in ipairs(v.model:GetDescendants()) do if p.Name == "TrackLink" then table.insert(links, p) end end
local function rel(p) return v.hullF:PointToObjectSpace(p.Position) end
local r0 = {}
for i, p in ipairs(links) do r0[i] = rel(p) end
for k = 1, 20 do
  G.moveEnt(e, G.vehBaseAt(def, bx, bz - k * 0.4, V3(0, 0, -1)))
  R.run(1 / 30)
end
local movL, movR, hidL = 0, 0, 0
for i, p in ipairs(links) do
  local dd = (rel(p) - r0[i]).Magnitude
  if r0[i].X < 0 then
    if dd > 0.2 then movL = movL + 1 end
    if p.Transparency > 0.5 then hidL = hidL + 1 end
  elseif dd > 0.2 then movR = movR + 1 end
end
check(#links > 0 and movL == 0 and movR > 5, string.format("左履带打断：左边不走（%d 块动了）、右边照走（%d 块）", movL, movR))
check(hidL > 5, "左边上面一段履带掉了（藏起 " .. hidL .. " 块）")

print("⑤ 泄压板（M1A2）")
local dm = VD.get("m1a2")
local e2 = G.newVehicle("def", "m1a2", G.vehBaseAt(dm, bx + 40, bz + 40, V3(0, 0, -1)))
R.run(1)
e2.model:SetAttribute("WtBlow", (e2.model:GetAttribute("WtBlow") or 0) + 1)
R.run(0.6)
local v2
for em2, vv in pairs(C.views or {}) do if em2 == e2.model then v2 = vv end end
local jets = 0
for _, x in ipairs(v2 and v2.model and v2.model:GetDescendants() or {}) do
  if x:IsA("ParticleEmitter") and x.Parent and x.Parent.Name == "WtVfx" and x.Rate > 60 and x.Speed.Min > 25 then jets = jets + 1 end
end
check(jets >= 1, "尾舱顶上一道火柱（" .. jets .. "）")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
