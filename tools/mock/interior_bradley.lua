-- 布雷德利借 M1A1 原模型的炮长 / 车长位那几件（模拟器；用户 11-24：「把 m1a1 内饰部分插件搬到 a2 和 m3 布雷德利里」）：
--   python3 tools/mock/run.py tools/mock/interior_bradley.lua [dump=<目录>]
--   假装导入了拆好的 m1a1i.glb：
--   ① 炮塔里：炮长目镜、目镜旁的控制面板、双握把、座椅，车长延伸目镜、两块屏的机壳、握把、座椅是原模型的件；M1A1 的炮塔壳、炮尾、装填手那一侧不搬
--   ② 车长两块屏：独立热像观察仪 CIV + 战术显示器（零件拼的那两块不画了）；键都在
--   ③ 炮长面板：射速（高速 / 低速 / 单发）、武器选择（25 毫米炮 / 并列机枪）、武器总开关、视野、极性、视场都真起作用；单发按住不连发、保险打不响
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local dumpDir = TEST_ARGS:match("dump=(%S+)")

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8402, true)
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
local RS = R.services.ReplicatedStorage
local VD = R.require(RS:FindFirstChild("VehDefs"))
local IM = R.require(RS:FindFirstChild("ImportedMeta"))
local Map = G.Map
local def = VD.get("m2a3")
local GW = def.weapons[1]   -- 25 毫米炮的武器号（11-27 起 M2A3 是 M242 + M919：m242m919，原来写死 ac30）
do
  local info = IM.m.m1a1i
  local imp = RS:FindFirstChild("Imported") or R.Instance.new("Folder")
  imp.Name = "Imported"
  imp.Parent = RS
  local vf = imp:FindFirstChild("Veh") or R.Instance.new("Folder")
  vf.Name = "Veh"
  vf.Parent = imp
  local f = R.Instance.new("Folder")
  f.Name = "m1a1i"
  local n = 0
  local gone = {}
  for _, p in pairs(info.parts) do for _, o in ipairs(p.rep or {}) do gone[o] = true end end
  for name, p in pairs(info.parts) do
    if not gone[name] then
      local b = R.Instance.new("MeshPart")
      b.Name = "V_m1a1i__" .. name
      b.Size = V3(p.s[1], p.s[2], p.s[3])
      b.Parent = f
      n = n + 1
    end
  end
  f:SetAttribute("N", n)
  f.Parent = vf
end

print("① 布雷德利的炮塔里")
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or V3(Map.CAMP.x, 0, Map.CAMP.z)
local cx, cz = hp.X + 18, hp.Z
for k = 0, 23 do
  local a = k / 24 * math.pi * 2
  local x, z = hp.X + math.cos(a) * 20, hp.Z + math.sin(a) * 20
  if Map.isLand(x, z) and Map.slope(x, z) < 0.25 then cx, cz = x, z break end
end
local e = G.newVehicle("def", "m2a3", G.vehBaseAt(def, cx, cz, V3(0, 0, -1)))
R.run(0.8)
T.act("enterVeh", e.id)
R.run(1)
check(P.vehicle == e and C.drive ~= nil, "坐上了布雷德利")
T.runUntil(function() return G.round.phase == "battle" end, 60)
T.tap(Enum.KeyCode.C)
R.run(0.8)
local I = C.interiorState()
local cur = I.cur
check(C.interiorOn() and cur ~= nil, "坐进车里（" .. tostring(I.station) .. "）")
if not cur then T.summary() return end
T.tap(Enum.KeyCode.F3)
R.run(0.4)
check(C.interiorState().station == "gunner", "F3：炮长位")
local blocks = {}
for _, it in ipairs(cur.b.parts) do
  local nm = it[1].Name:match("^V_m1a1i__(Int_%w+)$")
  if nm then blocks[nm] = true end
end
local want = { "Int_GpsEye", "Int_GPanel", "Int_Gch", "Int_GSeat", "Int_Gpse", "Int_Cdu", "Int_Cch", "Int_CSeat" }
local miss = {}
for _, nm in ipairs(want) do if not blocks[nm] then table.insert(miss, nm) end end
check(#miss == 0, "M1A1 的炮长 / 车长位那几件都搬来了" .. ((#miss > 0) and ("（缺 " .. table.concat(miss, "、") .. "）") or ""))
check(not blocks.Int_Shell and not blocks.Int_Breech and not blocks.Int_Loader, "M1A1 的炮塔壳、炮尾、装填手那一侧没搬（布雷德利有自己的 25 毫米炮）")
-- 搬来的件都在炮塔里：不出炮塔壁、不顶穿炮塔顶
local tw = cur.b.groups.turret.world
local TH = math.max(0.45, def.turret.size.Y / 2.8 - 0.10)
local wall = def.turret.size.X / 2.8 * 0.46
local worst = 0
for _, it in ipairs(cur.b.parts) do
  local p = it[1]
  if p.Name:match("^V_m1a1i__") then
    local q = tw:PointToObjectSpace(p.Position) / 2.8
    worst = math.max(worst, q.Y - TH, math.abs(q.X) - wall)
  end
end
check(worst < 0.12, string.format("搬来的件的中心都在炮塔里（最多超出 %.2f 米）", worst))
local pages = {}
for _, s in ipairs(cur.b.screens) do pages[s.page] = (pages[s.page] or 0) + 1 end
check(pages.citv == 1 and pages.cid == 1, "车长两块屏：CIV + 战术显示器（零件拼的那两块不画了）")
local nk = 0
for _, k in ipairs(cur.b.softkeys) do if k.screen and (k.screen.page == "citv" or k.screen.page == "cid") then nk = nk + 1 end end
check(nk >= 40, "车长屏的键 " .. nk .. " 个")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 800))

print("② 炮长面板的旋钮")
local st = C.drive
R.run(0.3)
local function press(id) local ok = C.interiorMovPress(id) R.run(0.2) return ok end
check(press("ROF") and st.rof == "LO", "射速 → 低速")
press("ROF")
check(st.rof == "SS", "射速 → 单发")
press("ROF")
check(st.rof == "HI", "射速 → 高速")
check(press("WPN") and st.wi == 2, "武器选择 → 并列机枪")
press("WPN")
check(st.wi == 1, "武器选择 → 25 毫米炮")
check(press("ARMG") and st.safe == true, "武器总开关 → 保险")
-- 保险时打不响：按住扳机（连发），25 毫米炮的下一发时间不动；拨回待发就打出去
st.wi = 1
st.next[GW] = 0
st.firing = true
R.run(0.5)
st.firing = false
check((st.next[GW] or 0) == 0, "保险：按住扳机不开火")
press("ARMG")
check(st.safe == false, "武器总开关 → 待发")
st.firing = true
R.run(0.3)
st.firing = false
check((st.next[GW] or 0) > 0, "待发：按住扳机开火了")
-- 单发：按住只打一发（连发那一路不走）
press("ROF") press("ROF")
check(st.rof == "SS", "射速 → 单发")
st.next[GW] = 0
st.firing = true
R.run(0.8)
st.firing = false
check((st.next[GW] or 0) == 0, "单发：按住不连发（扳一下打一发，这里没扳）")
press("ROF")
check(st.rof == "HI", "射速 → 高速")
st.mode = 1
R.run(0.3)
check(press("VIS") and st.mode >= 3, "视野选择 → 热像")
local zl = #C.driveZooms()
check(zl == 3, "布雷德利热像 3 档（4 / 12 / 24 倍），现在 " .. zl)
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 800))

if dumpDir then
  local S = 2.8
  local function at(a, b2) return R.CFrame.lookAt((tw * T.CF(a.X * S, a.Y * S, a.Z * S)).Position, (tw * T.CF(b2.X * S, b2.Y * S, b2.Z * S)).Position) end
  local ge = cur.spec.stations.gunner.eye
  local ce = cur.spec.stations.commander.eye
  local cams = {
    gunner = at(ge, ge + V3(0.05, -0.25, -1)),
    gunner_left = at(ge, ge + V3(-1, -0.2, -0.3)),
    commander = at(ce, ce + V3(0.3, -0.25, -1)),
    commander_right = at(ce, ce + V3(0.9, -0.3, -0.6)),
    commander_cdu = at(ce, ce + V3(0.79, -0.14, -0.62)),
    overview = at(V3(0.0, 0.45, 0.75), V3(0.0, 0.05, -0.6)),
  }
  dofile(MOCK_DIR .. "/interior_dump.lua")(cur, tw, cams, dumpDir .. "/interior_m2a3_donor.json", R.workspace.CurrentCamera, Enum)
end
T.summary()
