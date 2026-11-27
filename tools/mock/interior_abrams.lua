-- M1A1 原模型的炮塔内饰搬进 M1A2 SEPv2 / M1A1（模拟器；用户 11-24：「把 m1a1 内饰部分插件搬到 a2……按钮什么的实现功能，实现现实中那几块屏幕所有的功能」）：
--   python3 tools/mock/run.py tools/mock/interior_abrams.lua [veh=m1a2|m1a1] [dump=<目录>]
--   假装 Studio 里导入了拆好的 m1a1i.glb（照 ImportedMeta 摆一套同名的块：V_m1a1i__Int_Shell……）
--   ① 进车里：内饰用的是原模型的块（15 块都在），炮尾在后坐组、双握把在握把组、摇架在炮组；屏幕：SEPv2 是 GCDP + 车长 CITV / 战术显示器，A1 是 CCP + 状态显示器
--   ② 坐着时外模型的炮、车体不画（伸进乘员舱）
--   ③ 炮长面板上的旋钮、开关（左键拨一下）都接到火控上：视野选择、极性、视场、弹种、激光首 / 末回波、火控方式、稳定器、激光保险、战斗瞄准、
--      炮口基准更新、分划亮度、符号亮度、热像增益 / 电平、分划照明、自检；对准旋钮按真的左键也拨得动
--   ④ GCDP / CCP 的键：数字键盘装定距离、调整页校炮偏差和战斗瞄准距离、激光回波、火控方式、战斗瞄准、炮口基准更新
--   ⑤ 火控真起作用：激光穿过玻璃打到后面的墙（末回波 / 首回波、多回波）、激光保险不出光、炮管热弯曲让炮低一点（更新炮口基准就回来）、
--      手动方式没有超高角
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local VEH = TEST_ARGS:match("veh=(%w+)") or "m1a2"
local dumpDir = TEST_ARGS:match("dump=(%S+)")
local SEP = VEH == "m1a2"

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8401, true)
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
-- 11-27 二审：原来出生在 camp，基线上 ① 就坐不上车（「坐上了 m1a2」不对）；照 fponly / gunsight 出生在 base、等出生了再往下走
T.actAs(me, "deploy", "rifle", "base")
T.runUntil(function() return P.alive and P.char ~= nil end, 15)
R.run(1.5)
local RS = R.services.ReplicatedStorage
local VD = R.require(RS:FindFirstChild("VehDefs"))
local IM = R.require(RS:FindFirstChild("ImportedMeta"))
local Map = G.Map
local def = VD.get(VEH)
-- imp=<模型键>：再假装导入别的原模型（比如 carve.py 挖过的 m1a2dc：车体、炮塔的内壁，看抬头的八边形指挥塔）
for k in TEST_ARGS:gmatch("imp=(%w+)") do check(T.fakeImport(k) > 0, "假装导入了 " .. k) end
local info = IM.m.m1a1i
check(info ~= nil and info.parts.Int_Shell ~= nil and info.parts.Int_Breech ~= nil, "ImportedMeta 里有拆好的 M1A1 炮塔内饰（Int_Shell、Int_Breech……）")

-- 假装导入了拆好的 m1a1i.glb：拆开的块（新块顶替的旧整块 Int_2 不在 GLB 里了）
local NEW = {}
do
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
      if p.k == "int" then NEW[name] = true end
    end
  end
  f:SetAttribute("N", n)
  f.Parent = vf
end

print("① 坐上 " .. VEH .. "、进车里")
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
T.act("enterVeh", e.id)
R.run(1)
check(P.vehicle == e and C.drive ~= nil, "坐上了 " .. VEH)
T.runUntil(function() return G.round.phase == "battle" end, 60)
T.tap(Enum.KeyCode.F3)   -- 11-27 起车外的 C 归车长望远镜：进车里用 F2～F5（F3 炮长位）
T.runUntil(function() return C.interiorOn and C.interiorOn() end, 6)
R.run(0.8)
local I = C.interiorState()
local cur = I.cur
check(C.interiorOn() and cur ~= nil and I.mode == "seat" and I.station == "gunner", "坐进车里（" .. tostring(I.station) .. "）")
if not cur then T.summary() return end
check(cur.spec.modelInt == true and cur.spec.abrams == (SEP and "sep2" or "a1"), "内饰用的是 M1A1 原模型的炮塔内饰（" .. tostring(cur.spec.abrams) .. "）")
check(cur.carved == true, "坐着时外壳照样画（只藏伸进乘员舱的块）")
local blocks, inGroup = {}, {}
for _, it in ipairs(cur.b.parts) do
  local p = it[1]
  local nm = p.Name:match("^V_m1a1i__(Int_%w+)$")
  if nm then blocks[nm] = (blocks[nm] or 0) + 1 inGroup[nm] = it[2].name end
end
local nb, want = 0, 0
for nm in pairs(NEW) do
  want = want + 1
  if blocks[nm] and nm ~= "Int_1" and nm ~= "Int_3" then nb = nb + 1 end
end
local CAV = cur.spec and cur.b and TEST_ARGS:match("imp=m1a2dc") ~= nil   -- 挖了内腔（假装导入了 carve.py 挖过的 m1a2dc）：M1A1 的炮塔壳不要了
local wantN = want - 2 - (CAV and 1 or 0)
check(nb == wantN, string.format("原模型的块都克隆进来了（%d / %d，车长那两块屏的面换成动态显示面%s）", nb, wantN, CAV and "；挖了内腔不要 M1A1 的炮塔壳" or ""))
check(inGroup.Int_Breech == "recoil" and inGroup.Int_Gun == "gun" and inGroup.Int_Gch == "gch" and (CAV or inGroup.Int_Shell == "turret"),
  string.format("组：炮尾 %s、摇架 %s、双握把 %s、炮塔壳 %s", tostring(inGroup.Int_Breech), tostring(inGroup.Int_Gun), tostring(inGroup.Int_Gch), tostring(inGroup.Int_Shell)))
local pages = {}
for _, s in ipairs(cur.b.screens) do pages[s.page] = (pages[s.page] or 0) + 1 end
if SEP then
  check(pages.gcdp2 == 1 and pages.citv == 1 and pages.cid == 1, "SEPv2：炮长控制显示面板 GCDP、车长 CITV、战术显示器")
else
  check(pages.ccp == 1 and pages.m1stat == 2, "A1：计算机控制面板 CCP、车长两块状态显示器")
end
local nKnob = 0
for _, mv in ipairs(C.interiorMovs()) do if mv.id then nKnob = nKnob + 1 end end
check(nKnob >= (SEP and 20 or 18), "炮长 / 车长位能拨的旋钮、开关、按钮 " .. nKnob .. " 个")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 800))

print("② 坐着时外模型伸进乘员舱的块不画")
local v = C.viewById(e.id)
local hiddenGun, shownSome = true, false
for _, it in ipairs(v.M.parts) do
  local p = it[1]
  if it[2] == "gun" or it[2] == "hull" then
    if p.LocalTransparencyModifier < 1 then hiddenGun = false end
  elseif p.LocalTransparencyModifier == 0 then shownSome = true end
end
check(hiddenGun, "外模型的炮、车体不画")

print("③ 面板上的旋钮、开关都接到火控上")
local st = C.drive
local f = st.fcs
st.mode = 1
R.run(0.3)   -- 旋钮的档位每帧跟着系统状态走：等一帧再拨
local function press(id) local ok = C.interiorMovPress(id) R.run(0.2) return ok end
check(press("VIS") and (st.mode == 3 or st.mode == 4), "视野选择 → 热像（" .. tostring(st.mode) .. "）")
check(press("POL") and st.mode == 4 and st.pol == "BLK", "极性 → 黑热")
press("POL")
check(st.mode == 3, "极性 → 白热")
local Z0 = st.zoom
local zl = C.driveZooms and #C.driveZooms() or 0
check(press("FOV") and st.zoom == Z0 % zl + 1, string.format("视场下一档（%d → %d，热像共 %d 档）", Z0, st.zoom, zl))
if SEP then check(zl == 5, "SEPv2 热像 5 档（3 / 6 / 13 / 25 / 50 倍）") end
local am0 = f.am
press("AMMO")
check(f.am ~= nil and f.am ~= am0, "弹种选择开关：" .. tostring(am0) .. " → " .. tostring(f.am))
press("LRFR")
check(f.lrf == "FIRST", "激光回波选择 → 首回波")
press("LRFR")
check(f.lrf == "LAST", "激光回波选择 → 末回波")
press("FCS")
check(f.mode == 2, "火控方式 → 应急")
press("FCS")
check(f.mode == 3, "火控方式 → 手动")
press("FCS")
check(f.mode == 1, "火控方式 → 正常")
press("STAB")
check(st.stab == false, "稳定器 → 关")
press("STAB")
check(st.stab == true, "稳定器 → 开")
press("ARM")
check(f.arm == false, "激光测距机 → 保险")
press("ARM")
check(f.arm == true, "激光测距机 → 待命")
press("RETICLE")
check(st.retLvl == 1, "分划亮度 → 亮（一档）")
press("SYMB")
check(st.symLvl == 1, "符号亮度 → 亮（一档）")
press("GAIN")
check(st.thGain == 3, "热像增益 +1")
press("LEVEL")
check(st.thLevel == 3, "热像电平 +1")
press("RETN")
check(st.retNight == true, "分划照明 → 夜间（红）")
C.driveRange(1500)
press("BSGT")
check(f.R == nil and not f.man, "战斗瞄准：手动装定的距离清掉了")
f.droop = 0.5
press("MRSU")
check(math.abs(f.mrs - 0.5) < 1e-6, "炮口基准更新：量了现在的炮管弯曲（0.5 毫弧度）")
press("BIT")
check(cur.bitT ~= nil, "自检按钮：开始自检")
-- 对准一个旋钮、按真的左键
do
  local mv
  for _, m in ipairs(C.interiorMovs()) do if m.id == "LRFR" then mv = m end end
  local hitW = mv.g.world * CF(mv.hit.cf.Position * 2.8)
  st.stab = true
  local camCF = R.workspace.CurrentCamera
  local eye = hitW.Position + hitW.LookVector * (-0.4 * 2.8)
  -- 镜头摆到旋钮正前方 0.4 米、对准它（Interior 每帧按乘员位摆镜头：先切到导演镜头，镜头就不归它管）
  local ok = pcall(function() C.interiorFreeCam(R.CFrame.lookAt(eye, hitW.Position)) end)
  R.run(0.15)
  local hv = C.interiorHoverKey()
  if ok and hv and hv.mov == mv then
    T.mouse(true) T.mouse(false)
    R.run(0.2)
    check(f.lrf == "FIRST", "对准激光回波旋钮按左键：拨到首回波")
  else
    print("  （模拟器里镜头不能任意摆：跳过对准按真左键这一步）")
  end
end

print("④ " .. (SEP and "GCDP" or "CCP") .. " 的键")
local scr
for _, s in ipairs(cur.b.screens) do if s.page == (SEP and "gcdp2" or "ccp") then scr = s end end
local function key(label)
  for _, k in ipairs(cur.b.softkeys) do
    if k.label == label and k.screen == scr then
      local ok, err = pcall(scr.onKey, label, cur.env.act)
      if not ok then print("  按键出错：" .. tostring(err)) end
      R.run(0.15)
      return ok
    end
  end
  print("  没找到键 " .. label)
  return false
end
f.lrf = "LAST"
for _, d in ipairs({ "1", "8", "5", "0" }) do key("CCP " .. d) end
key("CCP ENT")
check(f.R == 1850 and f.man == true, "键盘打 1850、ENT：手动装定 1850 米（" .. tostring(f.R) .. "）")
key("CCP CLR")
check(f.R == nil, "CLR（没在打数）：清掉手动距离")
if SEP then
  key("ADJUST")
  key("CCP 6") key("CCP 6") key("CCP 8")
  check(math.abs(f.bore[1] - 0.10) < 1e-6 and math.abs(f.bore[2] - 0.05) < 1e-6, string.format("调整页：校炮偏差 方向 +%.2f、高低 +%.2f 密位", f.bore[1], f.bore[2]))
  key("CCP 0")
  check(f.bore[1] == 0 and f.bore[2] == 0, "调整页 0：校炮偏差归零")
  key("CCP 3")
  local bs = f.bsR[f.am]
  check(bs ~= nil and bs > 0, "调整页 3：这种弹的战斗瞄准距离加 50 米（" .. tostring(bs) .. "）")
  -- 11-27 二审：调整页改的是火控现在装定的那发——原来按面板写死的 SEPv2 那发（BAL.PANEL[符号]）：M1 一族别的型号、M829A1 系的炮改到 M829A3 那一项，
  --   射流弹的符号查不到、键是 nil 还报错。SEPv2 的炮只有射流弹不在面板上：装定它再按 3 / 5
  local am0 = f.am
  f.am = "jet120"
  R.run(0.4)
  key("CCP 3")
  local bsJ = f.bsR.jet120
  key("CCP 5")
  check(bsJ == 950 and f.bsR.jet120 == nil and f.bsR[am0] == bs, string.format("调整页装定射流弹：3 改的是它自己的战斗瞄准距离（900 → %s 米）、5 恢复默认（%s），刚才那发的不动",
    tostring(bsJ), tostring(f.bsR.jet120)))
  f.am = am0
  R.run(0.3)
  key("CCP CLR")
  key("LRF")
  check(f.lrf == "FIRST", "LRF 键：首回波")
  key("FCS")
  check(f.mode == 2, "FCS 键：应急")
  key("FCS") key("FCS")
  check(f.mode == 1, "FCS 键再按两下：回到正常")
  f.droop, f.mrs = 0.7, 0.1
  key("MRS")
  check(math.abs(f.mrs - 0.7) < 1e-6, "MRS 键：炮口基准更新")
  key("BIT")
  R.run(0.3)
  check(scr.st.page == "BIT", "BIT 键：自检页")
else
  key("TEST")
  check(scr.st.page == "TEST", "TEST 键：计算机自检页")
  key("FCS")
  check(f.mode == 2, "FCS 键：应急")
  key("FCS") key("FCS")
  key("BSGT")
  f.droop, f.mrs = 0.6, 0
  key("MRS")
  check(math.abs(f.mrs - 0.6) < 1e-6, "MRS 键：炮口基准更新")
end

print("⑤ 火控真起作用")
-- 激光：车前面 70 米一块玻璃、150 米一堵墙（测距机最近 50 米）
f.lrf, f.arm, f.R, f.multi = "LAST", true, nil, false
st.sight = false
local base = st.root * CF(0, -def.H / 2, 0)
local tur = VD.turretCF(def, base, st.ty)
local eye = (tur * CF(def.sight)).Position
local fwd = base.LookVector
local glass = R.Instance.new("Part")
glass.Size = V3(30, 30, 0.3)
glass.Material = Enum.Material.Glass
glass.Transparency = 0.5
glass.Anchored = true
glass.CFrame = R.CFrame.lookAt(eye + fwd * 70 * 2.8, eye + fwd * 71 * 2.8)
glass.Parent = R.workspace
local wall = R.Instance.new("Part")
wall.Size = V3(40, 40, 3)
wall.Anchored = true
wall.CFrame = R.CFrame.lookAt(eye + fwd * 150 * 2.8, eye + fwd * 151 * 2.8)
wall.Parent = R.workspace
st.aimPt = eye + fwd * 200 * 2.8
st.kAim = nil
R.run(0.3)
C.driveLase()
check(f.R ~= nil and f.R > 120 and f.multi == true, string.format("末回波：穿过玻璃量到后面的墙（%s 米，多回波 %s）", tostring(f.R), tostring(f.multi)))
f.lrf = "FIRST"
C.driveLase()
check(f.R ~= nil and f.R < 90, "首回波：量到前面那块玻璃（" .. tostring(f.R) .. " 米）")
f.arm = false
local t0 = f.laseT
C.driveLase()
check(f.laseT == t0, "激光保险：不出光")
f.arm = true
glass:Destroy()
wall:Destroy()
-- 炮管热弯曲：没修正的弯曲让炮低一点；更新炮口基准就回来
f.mode, f.R, f.man = 1, 800, true
st.aimPt = eye + fwd * 800 * 2.8
R.run(1.5)
local gp0 = st.gp
f.droop, f.mrs = 0.8, 0
R.run(1.5)
local gp1 = st.gp
check(gp1 < gp0 - 0.02, string.format("炮管热弯曲 0.8 毫弧度没修正：炮低了 %.3f°", gp0 - gp1))
C.driveMrs()
R.run(1.5)
check(math.abs(st.gp - gp0) < 0.01, string.format("更新炮口基准：炮回到原来的角度（差 %.3f°）", st.gp - gp0))
-- 手动方式：没有超高角
f.mode = 3
R.run(0.5)
check(st.fcsSE == 0, "手动方式：弹道计算机不工作，没有超高角")
f.mode = 1
R.run(0.5)
check((st.fcsSE or 0) > 0, string.format("正常方式：超高角 %.2f 密位", (st.fcsSE or 0) * 6400 / (2 * math.pi)))
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 800))

if dumpDir then
  local tw = cur.b.groups.turret.world
  local S = 2.8
  local function at(a, b2) return R.CFrame.lookAt((tw * T.CF(a.X * S, a.Y * S, a.Z * S)).Position, (tw * T.CF(b2.X * S, b2.Y * S, b2.Z * S)).Position) end
  local ge = cur.spec.stations.gunner.eye
  local ce = cur.spec.stations.commander.eye
  local cams = {
    gunner = at(ge, ge + V3(0.05, -0.22, -1)),
    gunner_right = at(ge, ge + V3(0.9, -0.40, -0.55)),
    gunner_left = at(ge, ge + V3(-1, -0.15, -0.45)),
    gunner_up = at(ge, ge + V3(0.3, 0.8, 0.6)),
    commander = at(ce, ce + V3(0.55, -0.25, -1)),
    commander_cdu = at(ce + V3(0.25, 0, 0.1), ce + V3(0.25, -0.05, -1)),
    commander_up = at(ce, ce + V3(0.05, 1, 0.45)),   -- 抬头看指挥塔（挖了内腔：八边形的井和观察镜）
    breech = at(V3(-0.6, 0.45, 0.6), V3(0.0, 0.0, -0.9)),
  }
  dofile(MOCK_DIR .. "/interior_dump.lua")(cur, tw, cams, dumpDir .. "/interior_" .. VEH .. "_abrams.json", R.workspace.CurrentCamera, Enum)
end
T.summary()
