-- 从原车挖出来的内腔（模拟器；用户 11-23：「改成在原车内部雕刻出来内饰」「这样各种载具的从外面可以看得见的窗户跟内部的内饰就能对得上了」）：
--   python3 tools/mock/run.py tools/mock/carve.lua veh=hmmwv
--   假装 Studio 里重新导入了 carve.py 改过的 GLB（照 ImportedMeta 摆一套同名的块，含 Cav_ 内壁、Glass_ 玻璃、Inside_ 原模型自带的简易内饰）：
--   ① 车外：内壁藏着（Transparency 1）、玻璃透明、原模型的简易内饰照画
--   ② C 进车里：走挖了内腔的那套（不画自己的车壳和玻璃）；外壳照样画（车窗看出去是自己的车头），简易内饰藏起来，内壁显示；
--      镜头在 carve.json 量的驾驶员眼位上
--   ③ 换到车长位、后座；④ C 出来：内壁又藏起来、简易内饰回来
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local VEH = TEST_ARGS:match("veh=(%w+)") or "hmmwv"
local dumpDir = TEST_ARGS:match("dump=(%S+)")   -- dump=<目录>：写 interior_<型号>_carve.json，CARVE=1 node tools/mock/interior_view.cjs 叠原车 GLB 画成图

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
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
local RS = R.services.ReplicatedStorage
local VD = R.require(RS:FindFirstChild("VehDefs"))
local IM = R.require(RS:FindFirstChild("ImportedMeta"))
local CM = R.require(RS:FindFirstChild("CavityMeta"))
local Map = G.Map
local def = VD.get(VEH)
local ikey = IM.alias and IM.alias[VEH]
local info = ikey and IM.m[ikey]
check(info ~= nil and info.cav == true, VEH .. " 的原模型挖过内腔（ImportedMeta 的 cav）")
check(CM[ikey] ~= nil and CM[ikey].anchors and CM[ikey].anchors.drv ~= nil, "CavityMeta 里有内腔和乘员位")
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
  local gone = {}   -- 重新导入：被新块顶替的旧块不在 GLB 里了
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
local cx, cz = hp.X + 18, hp.Z
for k = 0, 23 do
  local a = k / 24 * math.pi * 2
  local x, z = hp.X + math.cos(a) * 20, hp.Z + math.sin(a) * 20
  if Map.isLand(x, z) and Map.slope(x, z) < 0.25 then cx, cz = x, z break end
end
local e = G.newVehicle("def", VEH, G.vehBaseAt(def, cx, cz, V3(0, 0, -1)))
R.run(0.8)
local v = C.viewById(e.id)
local M = v and v.M
check(M ~= nil and M.imported == ikey, "车用的是导入的原模型")
local cv = M and M.carve
check(cv ~= nil and #cv.cav >= 1 and #cv.glass >= 1, string.format("内壁 %d 块、玻璃 %d 块、简易内饰 %d 块", cv and #cv.cav or 0, cv and #cv.glass or 0, cv and #cv.inside or 0))
if not cv then T.summary() return end
local function allT(list, prop, val) for _, p in ipairs(list) do if p[prop] ~= val then return false end end return true end
check(allT(cv.cav, "Transparency", 1), "车外：内壁藏着")
local gt = cv.glass[1] and cv.glass[1].Transparency or 0
check(gt > 0.4, string.format("车窗玻璃透明（%.2f）", gt))
check(allT(cv.inside, "LocalTransparencyModifier", 0), "车外：原模型的简易内饰照画")

print("② C 进车里")
T.act("enterVeh", e.id)
R.run(1)
check(P.vehicle == e and C.drive ~= nil, "坐上了 " .. VEH)
T.runUntil(function() return G.round.phase == "battle" end, 60)
T.tap(Enum.KeyCode.C)
R.run(0.6)
local I = C.interiorState()
local cur = I.cur
check(C.interiorOn() and cur ~= nil and I.mode == "seat", "坐进车里（" .. tostring(I.station) .. "）")
if not cur then T.summary() return end
check(cur.carved == true and cur.spec.carved == true, "走挖了内腔的那套")
check(#(cur.spec.glass or {}) == 0, "不画自己的玻璃（窗户就是原车的玻璃）")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
check(allT(cv.cav, "Transparency", 0), "车里：内壁显示")
check(allT(cv.inside, "LocalTransparencyModifier", 1), "车里：原模型的简易内饰藏起来")
local extOn = true
for _, it in ipairs(M.parts) do
  local p = it[1]
  local isIn = false
  for _, q in ipairs(cv.inside) do if q == p then isIn = true end end
  if p:IsA("BasePart") and not isIn and p.LocalTransparencyModifier ~= 0 then extOn = false end
end
check(extOn, "车里：外壳照样画（车窗看出去是自己的车头、车门）")
local cam = R.workspace.CurrentCamera
local A = CM[ikey].anchors
local function eyeAt(tag, a, tol)
  local q = v.hullF:PointToObjectSpace(cam.CFrame.Position)
  local d = (q - V3(a[1], a[2], a[3])).Magnitude
  check(d < tol, string.format("%s：镜头在原车量的眼位上（差 %.2f 格；%.2f, %.2f, %.2f）", tag, d, q.X, q.Y, q.Z))
end
eyeAt("驾驶员", A.drv, 0.6)
local dumpCams = {}
local function snap(name) dumpCams[name] = cam.CFrame end
snap("driver")

print("③ 换乘员位")
T.tap(Enum.KeyCode.F3)
R.run(0.5)
check(C.interiorState().station == "commander", "F3：车长位")
eyeAt("车长", A.cmd, 0.6)
snap("commander")
if A.rl then
  T.tap(Enum.KeyCode.F4)
  R.run(0.5)
  check(C.interiorState().station == "rear", "F4：后座")
  eyeAt("后座", A.rl, 0.6)
  snap("rear")
end
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
check(allT(cv.inside, "LocalTransparencyModifier", 0), "车外：简易内饰回来了")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
