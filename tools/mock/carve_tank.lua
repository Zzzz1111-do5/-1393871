-- 坦克的内腔从原车挖出来（模拟器；用户 11-23：「用 blender 继续做内饰，我要在原载具上挖出来，还原每一个载具 1 比 1 的内饰」）：
--   python3 tools/mock/run.py tools/mock/carve_tank.lua [veh=ztz99a] [dump=<目录>]
--   假装 Studio 里重新导入了 carve.py 改过的 GLB（照 ImportedMeta 摆一套同名的块，含 Cav 内壁、Inside 原模型自带的简易内饰），开一辆坦克：
--   ① 车外：内壁藏着；② C 进车里：走挖了内腔的那套（不再摆车体、炮塔的壳板），内壁显示、简易内饰藏起来、外壳照画；
--      舱盖在原车外面看得见的那个位置（炮塔顶），地板高度是内腔量的；③ 换到炮长位、车长位；④ C 出来：内壁又藏起来
--   dump=：写 interior_<型号>_carve.json（CARVE=1 node tools/mock/interior_view.cjs 叠原车 GLB 画成图）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local VEH = TEST_ARGS:match("veh=(%w+)") or "ztz99a"
local dumpDir = TEST_ARGS:match("dump=(%S+)")
local S = 2.8
-- 原车炮塔顶上舱盖的位置（米，相对座圈中心；glbview 量的）
local HATCH = { ztz99a = { g = V3(-0.48, 0, 0.16), c = V3(0.63, 0, 0.23) } }

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8302, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local RS = R.services.ReplicatedStorage
local VD = R.require(RS:FindFirstChild("VehDefs"))
local IM = R.require(RS:FindFirstChild("ImportedMeta"))
local CM = R.require(RS:FindFirstChild("CavityMeta"))
local def = VD.get(VEH)
local team = (def and def.team) or "atk"
local P = G.P[me]
P.team = team
me.Team = G.TEAM[team]
me.Neutral = false
me:SetAttribute("Side", team)
G.pushOne(P)
R.run(1)
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
T.actAs(me, "deploy", "rifle", (team == "atk") and "barge" or "camp")
R.run(1.5)
local Map = G.Map
local ikey = IM.alias and IM.alias[VEH]
local info = ikey and IM.m[ikey]
check(info ~= nil and info.cav == true, VEH .. " 的原模型挖过内腔（ImportedMeta 的 cav）")
check(CM[ikey] ~= nil and CM[ikey].spaces and CM[ikey].spaces.Hull and CM[ikey].spaces.Tur, "CavityMeta 里有车体、炮塔两个内腔")
-- 假装导入了改过的 GLB
do
  local imp = RS:FindFirstChild("Imported") or R.Instance.new("Folder")
  imp.Name = "Imported"
  imp.Parent = RS
  local vf = imp:FindFirstChild("Veh") or R.Instance.new("Folder")
  vf.Name = "Veh"
  vf.Parent = imp
  local f = R.Instance.new("Folder")
  f.Name = ikey
  local n = 0
  local gone = {}
  for _, p in pairs(info.parts) do for _, o in ipairs(p.rep or {}) do gone[o] = true end end
  for name, p in pairs(info.parts) do
    if not gone[name] then
      local b = R.Instance.new("MeshPart")
      b.Name = "V_" .. ikey .. "__" .. name
      b.Size = V3(p.s[1], p.s[2], p.s[3])
      b.Parent = f
      n = n + 1
    end
  end
  f:SetAttribute("N", n)
  f.Parent = vf
end

print("① 车外")
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or V3(Map.CAMP.x, 0, Map.CAMP.z)
local cx, cz = Map.CAMP.x + 30, Map.CAMP.z
for k = 0, 47 do
  local a = k / 48 * math.pi * 2
  for _, r in ipairs({ 40, 70, 110 }) do
    local x, z = Map.CAMP.x + math.cos(a) * r, Map.CAMP.z + math.sin(a) * r
    if Map.isLand(x, z) and Map.slope(x, z) < 0.2 then cx, cz = x, z break end
  end
end
local e = G.newVehicle(team, VEH, G.vehBaseAt(def, cx, cz, V3(0, 0, -1)))
R.run(0.8)
local v = C.viewById(e.id)
local M = v and v.M
check(M ~= nil and M.imported == ikey, "车用的是导入的原模型")
local cv = M and M.carve
check(cv ~= nil and #cv.cav >= 2, string.format("内壁 %d 块、简易内饰 %d 块", cv and #cv.cav or 0, cv and #cv.inside or 0))
if not cv then T.summary() return end
local function allT(list, prop, val) for _, p in ipairs(list) do if p[prop] ~= val then return false end end return true end
check(allT(cv.cav, "Transparency", 1), "车外：内壁藏着")

print("② C 进车里")
-- 坦克在开着的车边上：传送到车旁边再上车
if me.Character then me.Character:PivotTo(e.root.CFrame * CF(8, 2, 0)) end
R.run(0.3)
T.act("enterVeh", e.id)
R.run(1)
check(P.vehicle == e and C.drive ~= nil, "坐上了 " .. VEH)
T.runUntil(function() return G.round.phase == "battle" end, 60)
T.tap(Enum.KeyCode.C)
R.run(0.6)
-- 等真模型件（座椅、方向盘、踏板、握把……）在后台生成好、内饰重建一次（用户 11-23：不要自己建模，用 Sketchfab 的）
T.runUntil(function() local c = C.interiorState().cur return c ~= nil and c.propsDone == true end, 240)
R.run(0.5)
local I = C.interiorState()
local cur = I.cur
check(C.interiorOn() and cur ~= nil and I.mode == "seat", "坐进车里（" .. tostring(I.station) .. "）")
if not cur then T.summary() return end
check(cur.carved == true and cur.spec.carved == true, "走挖了内腔的那套")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
check(allT(cv.cav, "Transparency", 0), "车里：内壁显示")
check(allT(cv.inside, "LocalTransparencyModifier", 1), "车里：原模型的简易内饰藏起来")
-- 舱盖：在原车炮塔顶上看得见的那个位置（组的中心，米）
local b = cur.b
local H = HATCH[VEH]
if H and b.groups then
  for _, nm in ipairs({ "ghatch", "chatch" }) do
    local gg = b.groups[nm]
    local want = (nm == "chatch") and H.c or H.g
    if gg and gg.pivot then
      local p = gg.pivot.Position / S   -- 组的支点存的是格（toS）：换回米
      local d = math.sqrt((p.X - want.X) ^ 2 + (p.Z - want.Z) ^ 2)
      check(d < 0.05, string.format("%s 在原车舱盖底下（差 %.2f 米：%.2f, %.2f, %.2f）", nm, d, p.X, p.Y, p.Z))
    end
  end
end
-- 地板：内腔量的（不是写死的 −1.05）

local cam = R.workspace.CurrentCamera
local dumpCams = {}
local function snap(name) dumpCams[name] = cam.CFrame end
snap(tostring(I.station))
local seen = { [tostring(I.station)] = true }

print("③ 换乘员位")
for _, k in ipairs({ Enum.KeyCode.F2, Enum.KeyCode.F3, Enum.KeyCode.F4 }) do   -- 坦克：F2 驾驶员、F3 炮长、F4 车长（Interior.lua 的 KEYST）
  T.tap(k)
  R.run(0.5)
  local st = C.interiorState().station
  if st and not seen[st] then
    seen[st] = true
    snap(st)
  end
end
check(seen.driver and seen.gunner and seen.commander, "三个乘员位都坐过：驾驶员、炮长、车长")
check(#R.errors == 0, "换位没有报错：" .. table.concat(R.errors, " | "))
if dumpDir then
  local dumpOut = dofile(MOCK_DIR .. "/interior_dump.lua")
  dumpOut(C.interiorState().cur, v.hullF, dumpCams, dumpDir .. "/interior_" .. VEH .. "_carve.json", cam, Enum)
  print("  写了 " .. dumpDir .. "/interior_" .. VEH .. "_carve.json")
end

print("④ C 出来")
for _ = 1, 6 do
  if not C.interiorOn() then break end
  T.tap(Enum.KeyCode.C)
  R.run(0.4)
end
check(not C.interiorOn(), "出来了")
check(allT(cv.cav, "Transparency", 1), "车外：内壁又藏起来")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
