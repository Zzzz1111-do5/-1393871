-- M1A1 用原模型自带的炮塔内饰（模拟器；用户 11-23：「有一个带内饰的 m1a1……把 m1a1 换成那个 给那个电脑和观瞄设备实现现实中的功能」）：
--   python3 tools/mock/run.py tools/mock/m1a1.lua [old=1]
--   假装 Studio 里导入了 tools/models/blveh.py 转的 m1a1i（照 ImportedMeta 摆一套同名的块），开一辆 M1A1：
--   ① 车外：车内的块（k = "int"）藏着；② C 进车里：走原模型车内那套（外壳照画、车内显示），锁在炮长位；
--   ③ 器材：两块目镜镜片（凸透镜：椭球 + 镀膜 + 高光）、计算机控制面板的屏和 12 个键、控制面板上 4 个旋钮 / 拨杆、车长两块屏；
--   ④ 真功能：键盘打 1840 再按 ENT——火控的距离变成 1840（手动）、CLR 清掉；弹种选择拨杆换弹；视野选择、热像极性换瞄准镜的档；
--   ⑤ C 出来：车内又藏起来
--   old=1：只导入了老的 m1a1（没导新文件）——照旧用老模型、借 M1A2 的内饰
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local VEH = "m1a1"
local OLD = TEST_ARGS:match("old=1") ~= nil
local dumpDir = TEST_ARGS:match("dump=(%S+)")   -- 写 interior_m1a1_carve.json（tools/mock/interior_blender.py 叠 models/veh/m1a1i.glb 渲染）

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8303, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local RS = R.services.ReplicatedStorage
local VD = R.require(RS:FindFirstChild("VehDefs"))
local IM = R.require(RS:FindFirstChild("ImportedMeta"))
local def = VD.get(VEH)
local team = (def and def.team) or "def"
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
local NEW = IM.alias and IM.alias[VEH]
check(NEW == "m1a1i", "M1A1 的模型键换成了 m1a1i（" .. tostring(NEW) .. "）")
check(IM.old and IM.old[VEH] == "m1a1", "没导新文件时退回老的 m1a1（ImportedMeta 的 old）")
local info = IM.m[NEW]
check(info and info.src and info.int == true, "元数据有 src 换算矩阵、带车内（int）")
local nInt = 0
for _, p in pairs(info.parts) do if p.k == "int" then nInt = nInt + 1 end end
check(nInt >= 1, "车内的块 " .. nInt .. " 块")
-- 假装导入了模型
local ikey = OLD and "m1a1" or NEW
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
  for name, p in pairs(IM.m[ikey].parts) do
    local b = R.Instance.new("MeshPart")
    b.Name = "V_" .. ikey .. "__" .. name
    b.Size = V3(p.s[1], p.s[2], p.s[3])
    b.Parent = f
    n = n + 1
  end
  f:SetAttribute("N", n)
  f.Parent = vf
end

print("① 车外")
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
check(M ~= nil and M.imported == ikey, "车用的是导入的 " .. ikey .. "（" .. tostring(M and M.imported) .. "）")
local cv = M and M.carve
local function allT(list, prop, val) for _, p in ipairs(list or {}) do if p[prop] ~= val then return false end end return true end
if OLD then
  check(cv == nil, "老模型没有车内的块")
else
  check(cv ~= nil and cv.model == true and #cv.cav == nInt, string.format("车内的块 %d 块", cv and #cv.cav or 0))
  check(allT(cv and cv.cav, "Transparency", 1), "车外：车内的块藏着")
end

print("② C 进车里")
if me.Character then me.Character:PivotTo(e.root.CFrame * CF(8, 2, 0)) end
R.run(0.3)
T.act("enterVeh", e.id)
R.run(1)
check(P.vehicle == e and C.drive ~= nil, "坐上了 M1A1")
T.runUntil(function() return G.round.phase == "battle" end, 60)
T.tap(Enum.KeyCode.C)
R.run(0.6)
T.runUntil(function() local c = C.interiorState().cur return c ~= nil and c.propsDone == true end, 240)
R.run(0.5)
local I = C.interiorState()
local cur = I.cur
check(C.interiorOn() and cur ~= nil and I.mode == "seat" and I.station == "gunner", "坐进车里，炮长位（" .. tostring(I.station) .. "）")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
if not cur then T.summary() return end
if OLD then
  check(cur.key == "m1a2" and not cur.carved, "没导新文件：借 M1A2 的内饰（" .. tostring(cur.key) .. "）")
  T.summary()
  return
end
check(cur.key == "m1a1" and cur.carved == true and cur.spec.modelInt == true, "走原模型自带车内那套（" .. tostring(cur.key) .. "）")
check(allT(cv.cav, "Transparency", 0), "车里：车内的块显示")
local ext = 0
for _, it in ipairs(M.parts) do if it[1]:IsA("BasePart") and it[1].LocalTransparencyModifier ~= 0 then ext = ext + 1 end end
check(ext == 0, "车里：外壳照画（藏起来的 " .. ext .. " 块）")

print("③ 器材")
local b = cur.b
local lens, lensP = 0, {}
for _, it in ipairs(b.parts) do
  local p = it[1]
  local sm = p:FindFirstChildOfClass("SpecialMesh")
  if sm and sm.MeshType == Enum.MeshType.Sphere and p.Material == Enum.Material.Glass then lens = lens + 1 table.insert(lensP, p) end
end
check(lens == 2, "两块目镜镜片（凸透镜，Glass 椭球）：" .. lens)
local ccp, cid, stat
for _, s in ipairs(b.screens) do
  if s.page == "ccp" then ccp = s elseif s.page == "cid" then cid = s elseif s.page == "m1stat" then stat = s end
end
check(ccp ~= nil and ccp.update ~= nil, "计算机控制面板的显示窗（ccp 页）")
check(cid ~= nil and stat ~= nil, "车长两块显示器（战术地图、分系统状态）")
local keys, hots = {}, {}
for _, k in ipairs(b.softkeys) do
  if k.screen == ccp then
    if k.side == "pad" then keys[k.label] = k else hots[k.label] = k end
  end
end
local nk = 0
for _ in pairs(keys) do nk = nk + 1 end
check(nk == 12, "键盘 12 个键：" .. nk)
check(hots["3X/10X"] and hots["DAY/TIS"] and hots["WHT/BLK"] and hots["AMMO"], "控制面板上的倍率、视野选择、极性、弹种 4 个点选块")
check(hots["AMMO"] and hots["AMMO"].part.Transparency == 1, "点选块看不见（盖在模型的旋钮上）")
-- 屏幕在乘员视野里：键盘离炮长眼睛不到 0.6 米
local eye = cur.b.groups.turret.world * CF(cur.spec.stations.gunner.eye * 2.8)
local dk = (keys["CCP 5"].part.Position - eye.Position).Magnitude / 2.8
check(dk < 0.6, string.format("键盘离炮长眼睛 %.2f 米", dk))

if dumpDir then   -- 几个镜头：炮长眼位、看计算机控制面板、凑近目镜镜片、车长看两块屏
  local cam = R.workspace.CurrentCamera
  local tw = cur.b.groups.turret.world
  local function W(p) return (tw * CF(p * 2.8)).Position end
  local gE, cE = cur.spec.stations.gunner.eye, cur.spec.stations.commander.eye
  local cams = { gunner = cam.CFrame,
    ccp = R.CFrame.lookAt(W(gE), keys["CCP 5"].part.Position * 0.5 + ccp.part.Position * 0.5),
    lens = R.CFrame.lookAt(W(gE + V3(0, 0.03, -0.06)), lensP[1].Position),
    commander = R.CFrame.lookAt(W(cE), stat.part.Position * 0.5 + cid.part.Position * 0.5),
    gpse = R.CFrame.lookAt(W(cE + V3(-0.02, 0.02, -0.07)), lensP[2].Position) }
  local dumpOut = dofile(MOCK_DIR .. "/interior_dump.lua")
  dumpOut(cur, v.hullF, cams, dumpDir .. "/interior_m1a1_carve.json", cam, Enum)
  print("  写了 " .. dumpDir .. "/interior_m1a1_carve.json")
end

print("④ 真功能")
local st = C.drive
local act = cur.env.act
local function press(label)
  local ok, err = pcall(ccp.onKey, label, act)
  check(ok, "按 " .. label .. (ok and "" or ("：" .. tostring(err))))
  ccp.nextT = 0
end
for _, k in ipairs({ "CCP 1", "CCP 8", "CCP 4", "CCP 0", "CCP ENT" }) do press(k) end
R.run(0.4)
check(st.fcs.R == 1840 and st.fcs.man == true, string.format("打 1840 再按 ENT：火控距离 %s（手动 %s）", tostring(st.fcs.R), tostring(st.fcs.man)))
local okU, errU = pcall(ccp.update, (function() return nil end)() or { fcsR = st.fcs.R, fcsMan = true, fcsAm = st.fcs.am, ready = true, cant = 1.5 })
check(okU, "显示窗刷新" .. (okU and "" or ("：" .. tostring(errU))))
press("CCP CLR")
check(st.fcs.R == nil and not st.fcs.man, "CLR：手动距离清掉（" .. tostring(st.fcs.R) .. "）")
local am0 = st.fcs.am
press("AMMO")
R.run(0.2)
check(st.fcs.am ~= am0, string.format("弹种选择拨杆：%s → %s", tostring(am0), tostring(st.fcs.am)))
local m0 = st.mode
press("DAY/TIS")
check(((m0 or 1) >= 3) == ((st.mode or 1) < 3), string.format("视野选择：瞄准镜档 %s → %s", tostring(m0), tostring(st.mode)))
press("DAY/TIS")
if (st.mode or 1) < 3 then press("DAY/TIS") end
local p0 = st.mode
press("WHT/BLK")
check(st.mode ~= p0 and (st.mode == 3 or st.mode == 4), string.format("热像极性：%s → %s", tostring(p0), tostring(st.mode)))
local z0 = st.zoom
press("3X/10X")
check(st.zoom ~= z0, string.format("倍率：%s → %s", tostring(z0), tostring(st.zoom)))
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))

print("⑤ C 出来")
for _ = 1, 6 do
  if not C.interiorOn() then break end
  T.tap(Enum.KeyCode.C)
  R.run(0.4)
end
check(not C.interiorOn(), "出来了")
check(allT(cv.cav, "Transparency", 1), "车外：车内的块又藏起来")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
