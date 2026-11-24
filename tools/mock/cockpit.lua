-- 飞机座舱测试（模拟器）：python3 tools/mock/run.py tools/mock/cockpit.lua [air=j20|j35|j16|j15t|f35|f22|a10c] [dump=<目录>]
--   用户 11-21：第一人称开飞机要有和 DCS 一样的视觉细节；座舱盖玻璃要有畸变、划痕、反光折射
--   ① 召唤、坐上，V 进座舱：座舱拼出来了（零件、屏幕、平显、座舱盖玻璃和划痕），镜头在飞行员眼位；外模型的飞行员、座舱盖玻璃不画；外面的 2D 平显不画
--   ② 屏幕边的按键：中间小点对准、左键按（换页，不开炮）
--   ③ 起飞：油门杆往前推、驾驶杆跟着拉、收起落架（手柄、三个绿灯灭）；屏幕和平显是实时的速度、高度、航向；平显的机头符号在组合玻璃中间
--   ④ 头跟着鼠标瞄准转；按住 Alt 自由看：准心不动
--   ⑤ K 导演镜头、U 藏界面
--   ⑥ V 出座舱：外模型放回来；下飞机：座舱拆掉
--   dump=<目录>：写出 interior_<型号>.json，tools/mock/interior_view.cjs 画成图
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local dumpDir = TEST_ARGS:match("dump=(%S+)")
local AIR = TEST_ARGS:match("air=(%w+)") or "j20"
-- canopy=noedit：没开 Mesh / Image API（EditableMesh 拼不成）；canopy=imp：同时假装导入了光滑座舱盖 models/optics/ip_canopy.glb
--   （用户 11-24 晚：「目前飞机驾驶舱玻璃都是多边形 第一人称看非常难受」）
local CANOPY = TEST_ARGS:match("canopy=(%w+)")
local US = { f35 = true, f22 = true, f16 = true, f15 = true, f14 = true, a10c = true, ah64e = true, uh60 = true, ch47 = true, b2 = true }
local side = US[AIR] and "def" or "atk"
-- imp=1：假装 Studio 里导入了这型飞机的原模型（照 ImportedAir 元数据摆一套同名的 MeshPart，开服时收进 Imported），走原模型那条路
local IMP = nil
if TEST_ARGS:match("imp=1") then
  local f = assert(io.open(SRC_DIR .. "/ReplicatedStorage/ImportedAir.lua"))
  local IA = load(f:read("a"))()
  f:close()
  IMP = IA.alias[AIR] or AIR
  local info = IA.m[IMP]
  assert(info, "ImportedAir 里没有 " .. tostring(IMP))
  for name, p in pairs(info.parts) do
    local mp = R.Instance.new("MeshPart")
    mp.Name = "A_" .. IMP .. "__" .. name
    mp.Size = V3(p.s[1], p.s[2], p.s[3])
    mp.CFrame = T.CF(900 + p.c[1], 200 + p.c[2], 900 + p.c[3])
    mp.Parent = R.services.Workspace
  end
end

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
P.team = side
me.Team = G.TEAM[side]
me.Neutral = false
me:SetAttribute("Side", side)
G.pushOne(P)
R.run(1)
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
T.runUntil(function() return G.round.phase == "battle" end, 90)   -- 守方机场准备阶段不能出生
T.actAs(me, "deploy", "rifle", (side == "atk") and "af2" or "afield")
R.run(1.5)
check(P.alive and me.Character ~= nil, "在机场出生了")
local cam = R.workspace.CurrentCamera

print("① 召唤 " .. AIR .. "、坐上，V 进座舱")
local pad = T.pad(AIR)
check(pad ~= nil, "有能召唤 " .. AIR .. " 的召唤位")
local e
if pad then
  T.usePad(me, pad)
  local card = T.findNamed("Pick_" .. AIR)
  if card then T.press(card) end
  R.run(0.3)
  local go = T.findButton("^" .. C.T("pad.spawn") .. "$")
  if go then T.press(go) end
  R.run(1)
  for _, x in ipairs(G.aircraft or {}) do if x.padId == pad.id and x.alive then e = x end end
end
if not e then   -- 没有召唤位的（轰炸机）：在本方战斗机召唤位上直接生成
  local fp = T.pad((side == "atk") and "j20" or "f22")
  if fp then
    local c = fp.base.Position
    local d = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs")).get(AIR)
    local pos = R.Vector3.new(c.X, G.airSurface(c.X, c.Z) + d.gearH, c.Z)
    e = G.spawnAircraft(side, AIR, R.CFrame.lookAt(pos, pos + fp.base.LookVector), nil, P, 1)
    local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
    if hrp then me.Character:PivotTo(R.CFrame.new(pos + R.Vector3.new(12, 2, 0))) end
    R.run(0.5)
  end
end
check(e ~= nil, "飞机停在停机位上")
T.act("enterVeh", e and e.id)
R.run(1.5)
local fst = C.fly
check(P.vehicle == e and fst ~= nil and fst.pilot, "坐上了 " .. AIR)
T.runUntil(function() return G.round.phase == "battle" end, 60)
if not fst then T.summary() return end
local edit0 = R.editStats.meshes
if CANOPY == "noedit" or CANOPY == "imp" then R.noEditable = true end
if CANOPY == "imp" then   -- 照 OpticsMeta 在 ReplicatedStorage.Imported.Optics.ip_canopy 摆一块同名、同尺寸的 MeshPart
  local RS = R.services.ReplicatedStorage
  local OM = R.require(RS:FindFirstChild("OpticsMeta"))
  local imp = RS:FindFirstChild("Imported") or R.Instance.new("Folder")
  imp.Name = "Imported"
  imp.Parent = RS
  local of = imp:FindFirstChild("Optics") or R.Instance.new("Folder")
  of.Name = "Optics"
  of.Parent = imp
  local f = R.Instance.new("Folder")
  f.Name = "ip_canopy"
  for name, pi in pairs(OM.ip_canopy.parts) do
    local mp = R.Instance.new("MeshPart")
    mp.Name = "O_ip_canopy__" .. name
    mp.Size = V3(pi.s[1], pi.s[2], pi.s[3])
    mp.Parent = f
  end
  f.Parent = of
end
T.tap(Enum.KeyCode.V)
R.run(0.6)
local I = C.interiorState()
local cur = I.cur
check(C.interiorOn() and cur ~= nil and cur.spec.air and I.mode == "seat", "按 V：坐进座舱（" .. tostring(cur and cur.key) .. "）")
if not cur then T.summary() return end
local nParts, nScreens, nLights, nGlass = #cur.b.parts, #cur.b.screens, #cur.b.lights, #(cur.spec.glass or {})
local v0 = C.viewById(e.id)
local v0M = v0 and v0.M or {}
local MP = cur.spec.modelPit   -- 原模型自带的座舱（F-16）：座舱是原模型的，内饰只有屏幕、平显、键帽
if MP then
  check(nParts >= 10, "原模型座舱：贴的屏幕、键帽、平显框 " .. nParts .. " 个零件")
  local pit, hidPit = 0, 0
  for _, it in ipairs(v0M.items or {}) do
    if it.pit == "Pit" then
      pit = pit + 1
      for _, zp in ipairs(cur.zone or {}) do if zp == it.p then hidPit = hidPit + 1 end end
    end
  end
  check(pit >= 1 and hidPit == 0, string.format("原模型的座舱件（%d 块）坐在座舱里照样画（藏了 %d 块）", pit, hidPit))
  -- 屏幕贴在原模型的显示器上：每块的中心离元数据里量的位置不到 1 厘米
  local I = v0M.imp.info
  local eyeM = R.Vector3.new(I.pit[1][1], I.pit[1][2], I.pit[1][3])
  local worst = 0
  for name, o in pairs(I.pitScr) do
    local want = v0.cf * CF(cur.eyeBody) * CF((R.Vector3.new(o.c[1], o.c[2], o.c[3]) - eyeM))
    local best = math.huge
    for _, sc in ipairs(cur.b.screens) do best = math.min(best, (sc.part.Position - want.Position).Magnitude) end
    worst = math.max(worst, best)
  end
  check(worst < 0.03 * 2.8, string.format("屏幕贴在原模型的显示器、圆表、平显上（最远差 %.1f 厘米）", worst / 2.8 * 100))
else
  check(nParts > 250, "座舱零件 " .. nParts .. " 个")
end
local minS = cur.spec.minScreens or 5   -- F-35 真就三块（全景屏两半 + 备份飞行显示器）
check(nScreens >= minS, "屏幕 " .. nScreens .. " 块（至少 " .. minS .. "）")
local live = 0
for _, s in ipairs(cur.b.screens) do if s.update then live = live + 1 end end
check(live == nScreens, string.format("屏幕页面都起来了（%d / %d）", live, nScreens))
check(nLights >= 2, "座舱灯 " .. nLights .. " 盏")
if not MP then check(nGlass >= 8, "座舱盖玻璃 " .. nGlass .. " 块") end
local scr = 0
for _, g in ipairs(cur.spec.glass or {}) do
  local sg = g:FindFirstChildOfClass("SurfaceGui")
  if sg and #sg:GetChildren() >= 20 then scr = scr + 1 end
  if CANOPY == "noedit" then   -- 拼不成光滑座舱盖：平板（带划痕的这几块也是）改成几乎全透的塑料（玻璃材质一块一块各折射，棱全看得见）
    check(g.Material == Enum.Material.SmoothPlastic and g.Transparency >= 0.97, "没开 Mesh API：带划痕的平板也几乎全透（看不出棱）")
  else
    check(g.Material == Enum.Material.Glass, "玻璃是 Glass 材质（看出去有折射）")
  end
  break
end
if not MP then check(scr == 1, "玻璃上有划痕、污渍") end
-- 用户 11-22：「飞机不要搞多边形的座舱盖，一反光看着太难受了，就要弧形」——一整块光滑网格（EditableMesh），平板不画（带划痕的只剩划痕）
if cur.spec.canopy and CANOPY == "noedit" then
  -- 拼不成光滑座舱盖：144 块平板改成几乎全透、不反光的塑料（看不出棱），只剩划痕
  local bad = 0
  for _, p in ipairs(cur.spec.canopy.panes or {}) do
    if p.Material ~= Enum.Material.SmoothPlastic or p.Transparency < 0.97 or p.Reflectance > 0 then bad = bad + 1 end
  end
  check(cur.canopyMesh == nil and #(cur.spec.canopy.panes or {}) > 100 and bad == 0,
    string.format("没开 Mesh API：平板几乎全透、不反光（%d 块里 %d 块不对）", #(cur.spec.canopy.panes or {}), bad))
  check(cur.spec.glass[1] and cur.spec.glass[1]:FindFirstChildOfClass("SurfaceGui") ~= nil, "划痕还在")
elseif cur.spec.canopy and CANOPY == "imp" then
  local cm = cur.canopyMesh
  check(cur.spec.canopy.std == true, "这型的座舱盖是标准曲面（和 ip_canopy 一样）")
  check(cm ~= nil and cm.Name == "CanopySmooth" and cm.Parent == cur.model and cm.Material == Enum.Material.Glass and R.editStats.meshes == edit0,
    "没开 Mesh API 也用上了导入的光滑座舱盖（O_ip_canopy__Glass），没现拼网格")
  local panesOff = 0
  for _, p in ipairs(cur.spec.canopy.panes or {}) do if p.Transparency >= 1 then panesOff = panesOff + 1 end end
  check(panesOff == #(cur.spec.canopy.panes or {}), "平板玻璃不画了")
  if cm then
    local v = C.viewById(e.id)
    local rel = cur.b.groups.hull.world:PointToObjectSpace(cm.Position)
    local OM = R.require(R.services.ReplicatedStorage:FindFirstChild("OpticsMeta"))
    local c0 = OM.ip_canopy.parts.Glass.c
    check((rel - V3(c0[1], c0[2], c0[3])).Magnitude < 0.05, string.format("摆在座舱里该在的地方（差 %.3f 格）", (rel - V3(c0[1], c0[2], c0[3])).Magnitude))
  end
elseif cur.spec.canopy then
  local cm = cur.canopyMesh
  local panesOff = 0
  for _, p in ipairs(cur.spec.canopy.panes or {}) do if p.Transparency >= 1 then panesOff = panesOff + 1 end end
  check(cm ~= nil and cm.Parent == cur.model and cm.Material == Enum.Material.Glass and cm.Transparency < 0.95,
    string.format("光滑座舱盖：一整块网格（%s，%d 个三角形）", cm and cm.ClassName or "没有", R.editStats.tris))
  check(panesOff == #(cur.spec.canopy.panes or {}), string.format("原来的平板玻璃不画了（%d / %d）", panesOff, #(cur.spec.canopy.panes or {})))
  local scr2 = cur.spec.glass[1] and cur.spec.glass[1]:FindFirstChildOfClass("SurfaceGui")
  check(scr2 ~= nil, "带划痕的那几块只剩划痕（划痕还在）")
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
local v = C.viewById(e.id)
local eyeW = v.cf * CF(cur.eyeBody)
check((cam.CFrame.Position - eyeW.Position).Magnitude < 0.25 * 2.8, string.format("镜头在飞行员眼位（差 %.2f 格）", (cam.CFrame.Position - eyeW.Position).Magnitude))
local q = v.cf:PointToObjectSpace(cam.CFrame.Position)
local sideOk = (cur.spec.heli or cur.spec.eyeShift) and 0.8 * 2.8 or v.def.W * 0.1   -- 并排座：机长坐一边
check(math.abs(q.X) < sideOk and q.Z < 0, string.format("眼位在机身中线（并排座在一边）、机头那半边（机体坐标 %.1f, %.1f, %.1f）", q.X, q.Y, q.Z))
-- 双座（歼-16）：驾驶员的眼位在前座——座舱盖的前半段、后座飞行员的前面（用户 11-22：「j16 驾驶位第一人称不能坐在后座」）
local Cn = v.def.canopy
if v.def.twoSeat and Cn then
  local s2 = C.AM and C.AM.seatCF and C.AM.seatCF(v.M, 2)
  local zr = s2 and s2.Position.Z or (Cn.z + Cn.len * 0.2)
  check(q.Z < Cn.z and q.Z < zr - 0.8 * 2.8, string.format("双座：驾驶员坐前座（眼位 z %.1f，座舱盖中点 %.1f，后座 %.1f）", q.Z, Cn.z, zr))
end
check(v.M.pilotsOn == false, "外模型里的飞行员不画（第一人称）")
local hid = 0
for _, p in ipairs(cur.zone or {}) do if p.LocalTransparencyModifier == 1 then hid = hid + 1 end end
check(#(cur.zone or {}) >= 1 and hid == #cur.zone, string.format("外模型的座舱盖玻璃、座舱里的块不画（%d / %d）", hid, #(cur.zone or {})))
check(C.airInfo ~= nil, "外面的 2D 平显照样拿到了飞行数据（座舱里不画）")
check(cur.b.named.hud ~= nil or not cur.spec.hud, "有平显组合玻璃")

print("② 屏幕边的按键：中间小点对准、左键按")
local keys = cur.b.softkeys
check(#keys >= 10, "屏幕边有 " .. #keys .. " 个带字的按键")
local want = nil
-- 没有雷达的（A-10C）按左边那块的 DSMS，查它换成外挂页
local KW = cur.spec.noRadar and { DSMS = true } or { RDR = true, ["雷达"] = true, FCR = true }
local PW = cur.spec.noRadar and { "^STORES", "^外挂" } or { "^RDR", "^雷达" }
for _, k in ipairs(keys) do
  if KW[k.label] then want = k break end
end
if want then
  -- 看过去：直升机头跟着镜头方向；固定翼（用户 11-21：WASD 飞、没有准心）按住 Alt 用鼠标转头，中间小点对准按键
  if not cur.spec.heli then T.key(Enum.KeyCode.LeftAlt, true) end
  for _ = 1, 60 do   -- 每帧按眼睛现在的位置重算
    local dir = (want.part.Position - cam.CFrame.Position).Unit
    if cur.spec.heli then fst.camYaw, fst.camPitch = math.atan2(-dir.X, -dir.Z), math.asin(dir.Y)
    else
      local lk = cam.CFrame.LookVector
      local dy = math.atan2(-dir.X, -dir.Z) - math.atan2(-lk.X, -lk.Z)
      dy = (dy + math.pi) % (2 * math.pi) - math.pi
      local dp = math.asin(math.max(-1, math.min(1, dir.Y))) - math.asin(math.max(-1, math.min(1, lk.Y)))
      local sens = 0.0035 * (cam.FieldOfView / 72)
      R.mouseDelta = R.Vector2.new(-dy / sens * 0.5, -dp / sens * 0.5)
    end
    R.run(1 / 30)
  end
  local dirE = (want.part.Position - cam.CFrame.Position).Unit
  print(string.format("  （镜头和按键方向差 %.2f°）", math.deg(math.acos(math.max(-1, math.min(1, dirE:Dot(cam.CFrame.LookVector)))))))
  local hk = C.interiorHoverKey and C.interiorHoverKey()
  check(hk == want, "中间小点对准了「" .. want.label .. "」（对着的是「" .. tostring(hk and hk.label) .. "」，" .. string.format("镜头朝下 %.0f°", -math.deg(math.asin(cam.CFrame.LookVector.Y))) .. "）")
  local fired = false
  T.mouse(true)
  R.run(1 / 30)
  fired = fst.firing == true
  T.mouse(false)
  R.run(0.3)
  check(not fired, "左键按的是屏幕键，不开炮")
  -- 只查按的那块屏，而且字要看得见（父级都没藏起来）
  local function shown(d, root)
    local o = d
    while o and o ~= root do
      if o.Visible == false then return false end
      o = o.Parent
    end
    return true
  end
  local radar = false
  local sc = want.screen or cur.b.screens[1]
  for _, d in ipairs(sc.gui:GetDescendants()) do
    if d:IsA("TextLabel") and shown(d, sc.gui) then
      for _, pat in ipairs(PW) do if d.Text:match(pat) then radar = true end end
    end
  end
  check(radar, "按「" .. want.label .. "」：这块屏换成" .. (cur.spec.noRadar and "外挂" or "雷达") .. "页面")
  if not cur.spec.heli then T.key(Enum.KeyCode.LeftAlt, false) end
else check(false, cur.spec.noRadar and "找到 DSMS 键" or "找到雷达键") end
local lk0 = fst.cf.LookVector
fst.aimYaw, fst.aimPitch = math.atan2(-lk0.X, -lk0.Z), 0
if cur.spec.heli then fst.camYaw, fst.camPitch = math.atan2(-lk0.X, -lk0.Z), 0 end

print("③ 起飞：油门杆、驾驶杆、起落架手柄跟着动；屏幕、平显是实时数据")
local function gearLit()
  local n = 0
  for _, l in ipairs(cur.b.leds) do if l.role == "gear" and l.p.Color == l.on then n = n + 1 end end
  return n
end
if not cur.spec.heli and not MP then check(gearLit() == 3, "停在地上：起落架三个绿灯亮（" .. gearLit() .. "）") end
local gh0 = cur.b.groups.gearh and cur.b.groups.gearh.anim
local thrZ0 = cur.b.groups.thr and cur.b.groups.thr.anim.Position.Z
local maxStick = 0
local function stickNow()
  if not cur.b.groups.stick then return end   -- 原模型座舱：杆是原模型的（不动）
  local rx, _, rz = cur.b.groups.stick.anim:ToEulerAnglesXYZ()
  maxStick = math.max(maxStick, math.abs(rx), math.abs(rz))
end
local heli = cur.spec.heli
if heli then   -- 直升机：旋翼转起来、E 提总距离地、W 推杆往前飞
  T.runUntil(function() return (fst.rpm or 0) >= 92 end, 20)
  check((fst.rpm or 0) >= 92, string.format("旋翼转起来了（%d%%）", math.floor(fst.rpm or 0)))
  local col0 = cur.b.groups.coll.anim
  T.key(Enum.KeyCode.E, true)
  local up = T.runUntil(function() return not fst.ground end, 15)
  R.run(1)
  local col1 = cur.b.groups.coll.anim
  check(up, "提总距：离地")
  check(math.abs(select(1, col0:ToObjectSpace(col1):ToEulerAnglesXYZ())) > math.rad(3), string.format("总距杆提起来了（%.1f°）", math.deg(math.abs(select(1, col0:ToObjectSpace(col1):ToEulerAnglesXYZ())))))
  R.run(4)
  T.key(Enum.KeyCode.E, false)
  T.key(Enum.KeyCode.W, true)
  for _ = 1, 90 do R.run(1 / 30) stickNow() end
  check(maxStick > math.rad(1.5), string.format("周期变距杆跟着推（最大 %.1f°）", math.deg(maxStick)))
  R.run(3)
  T.key(Enum.KeyCode.W, false)
else
  local onDeck = not G.Map.isLand(fst.cf.Position.X, fst.cf.Position.Z)
  T.key(Enum.KeyCode.LeftShift, true)   -- 用户 11-21：WASD 控制方向，油门是 Shift / Ctrl
  if onDeck then   -- 舰载机停在甲板上：只推一秒油门看油门杆（推满会弹射、没挂上弹射器会滑出甲板），然后直接放到天上
    R.run(1)
    T.key(Enum.KeyCode.LeftShift, false)
    local thrZ1 = cur.b.groups.thr.anim.Position.Z
    check(thrZ1 < thrZ0 - 0.02 * 2.8, string.format("油门杆往前推了 %.2f 米", (thrZ0 - thrZ1) / 2.8))
    local p = fst.cf.Position
    local lk = R.Vector3.new(fst.cf.LookVector.X, 0, fst.cf.LookVector.Z).Unit
    local q = R.Vector3.new(p.X, 700, p.Z)
    fst.cf = R.CFrame.lookAt(q, q + lk)
    fst.ground, fst.cat, fst.trap = false, nil, nil
    fst.spd, fst.vel, fst.thr = 190, lk * 190, 110
    fst.vdir = lk
    T.key(Enum.KeyCode.S, true)   -- 拉一下杆
    for _ = 1, 40 do R.run(1 / 30) stickNow() end
    T.key(Enum.KeyCode.S, false)
    for _ = 1, 80 do R.run(1 / 30) stickNow() end
    fst.thr = 100
  else
    T.runUntil(function() stickNow() return fst.spd >= fst.d.vRot end, 40)
    T.key(Enum.KeyCode.S, true)   -- 速度到了按住 S 抬头
    local up = T.runUntil(function() stickNow() return not fst.ground end, 10)
    check(up, string.format("滑跑起飞（离地时 %.0f 格 / 秒）", fst.spd or 0))
    if not MP then
      local thrZ1 = cur.b.groups.thr.anim.Position.Z
      check(thrZ1 < thrZ0 - 0.05 * 2.8, string.format("油门杆往前推了 %.2f 米", (thrZ0 - thrZ1) / 2.8))
    end
    for _ = 1, 30 do R.run(1 / 30) stickNow() end
    T.key(Enum.KeyCode.S, false)
    for _ = 1, 150 do R.run(1 / 30) stickNow() end   -- 加力爬一会儿
    T.key(Enum.KeyCode.LeftShift, false)
    fst.thr = 100
  end
  if not MP then check(maxStick > math.rad(1.5), string.format("驾驶杆跟着拉（最大 %.1f°）", math.deg(maxStick))) end
end
if not heli then
  -- 起飞爬过 15 米自动收起落架（Fly.lua），等它收完
  T.runUntil(function() return (fst.gear or 1) < 0.02 end, 10)
  check((fst.gear or 1) < 0.02 and (MP or gearLit() == 0), string.format("起落架收上去了：绿灯都灭（起落架 %.2f、亮 %d）", fst.gear or -1, gearLit()))
  if not MP then
    local gh1 = cur.b.groups.gearh.anim
    check(math.abs(select(1, gh0:ToObjectSpace(gh1):ToEulerAnglesXYZ())) > math.rad(20), "起落架手柄扳上去了")
  end
  T.tap(Enum.KeyCode.G)
  R.run(3)
  check((fst.gear or 0) > 0.9 and (MP or gearLit() == 3), string.format("G 放起落架：三个绿灯又亮了（起落架 %.2f、亮 %d）", fst.gear or -1, gearLit()))
  T.tap(Enum.KeyCode.G)
  R.run(3)
end
R.run(0.5)
local d = cur.data
local kmh = (fst.vel or V3()).Magnitude / 2.8 * 3.6
check(d.kmh and math.abs(d.kmh - kmh) < 30, string.format("屏幕数据：速度 %.0f 公里 / 时（实际 %.0f）", d.kmh or -1, kmh))
check(d.agl and d.agl > 10, string.format("屏幕数据：离地 %.0f 米", d.agl or -1))
local lk = fst.cf.LookVector
local hdg = math.deg(math.atan2(lk.X, -lk.Z)) % 360
check(d.hdg and math.abs(((d.hdg - hdg + 180) % 360) - 180) < 2, string.format("屏幕数据：航向 %03d（机头 %03d）", math.floor(d.hdg or -1), math.floor(hdg)))
local hs = cur.b.named.hud
if hs and d.hudProj then
  local x, y = d.hudProj(fst.cf.LookVector)
  check(x and math.abs(x - hs.px.X / 2) < hs.px.X * 0.25, string.format("平显：机头符号在组合玻璃中间附近（%.0f / %.0f 像素）", x or -1, hs.px.X))
  local txt = {}
  for _, dd in ipairs(hs.gui:GetDescendants()) do if dd:IsA("TextLabel") and dd.Text ~= "" then table.insert(txt, dd.Text) end end
  local spdTxt = cur.spec.cn and tostring(math.floor(d.kmh)) or tostring(math.floor(d.kt))
  local found = false
  for _, t in ipairs(txt) do if t == spdTxt then found = true end end
  check(found, "平显上写着空速 " .. spdTxt .. "（" .. table.concat(txt, " / ") .. "）")
elseif cur.spec.hud then check(false, "平显有投影") end

print("④ 头跟着鼠标瞄准转；按住 Alt 自由看时准心不动")
local function relYaw(dir)
  local l = v.cf:VectorToObjectSpace(dir)
  return math.deg(math.atan2(-l.X, -l.Z))
end
local function angTo(dir) return math.deg(math.acos(math.max(-1, math.min(1, cam.CFrame.LookVector:Dot(dir))))) end
if heli then   -- 直升机：头跟着镜头方向（鼠标转的就是它，机头跟着转过去）
  local lk2 = fst.cf.LookVector
  fst.camYaw, fst.camPitch = math.atan2(-lk2.X, -lk2.Z) + math.rad(50), 0
  R.run(0.6)
  local diff = angTo((R.CFrame.Angles(0, fst.camYaw, 0) * R.CFrame.Angles(fst.camPitch, 0, 0)).LookVector)
  check(diff < 12, string.format("镜头往左 50°：头跟过去了（差 %.1f°、相对机头 %.0f°）", diff, relYaw(cam.CFrame.LookVector)))
  local lk3 = fst.cf.LookVector
  fst.camYaw, fst.camPitch = math.atan2(-lk3.X, -lk3.Z), 0
  R.run(0.5)
else
  -- 用户 11-21：飞机 WASD 飞、没有准心——头看前方（航迹）；用户 11-21（晚）：飞机要允许用鼠标转视角——
  --   不按 Alt 动鼠标头就转、停在那里；鼠标 2.5 秒不动回到前方；C 立刻回正；按住 Alt 照旧能转头（对准屏幕边的按键），松开回到前方
  --   （用户 11-24 起固定翼默认是战雷式鼠标瞄准——鼠标给方向、头跟着想去的方向；这一段测的是按 M 切回去的纯键盘驾驶的看法）
  if C.flyMouseAim then C.flyMouseAim(false) end
  local function offFwd() return math.deg(math.acos(math.max(-1, math.min(1, cam.CFrame.LookVector:Dot(fst.vdir or fst.cf.LookVector))))) end
  for _ = 1, 15 do
    R.mouseDelta = R.Vector2.new(-40, 0)
    R.run(1 / 30)
  end
  R.mouseDelta = R.Vector2.new(0, 0)
  check(offFwd() > 15, string.format("不按 Alt 动鼠标：头转开了（离前方 %.0f°）", offFwd()))
  R.run(1.2)
  check(offFwd() > 15, string.format("鼠标停 1.2 秒：头还看着那边（离前方 %.0f°）", offFwd()))
  R.run(4.5)
  check(offFwd() < 12, string.format("鼠标停 2.5 秒以上：头回到前方（差 %.1f°）", offFwd()))
  for _ = 1, 15 do
    R.mouseDelta = R.Vector2.new(-40, 0)
    R.run(1 / 30)
  end
  R.mouseDelta = R.Vector2.new(0, 0)
  T.key(Enum.KeyCode.C, true)
  R.run(1 / 30)
  T.key(Enum.KeyCode.C, false)
  R.run(0.6)
  check(offFwd() < 12, string.format("按 C：头立刻回到前方（差 %.1f°）", offFwd()))
  T.key(Enum.KeyCode.LeftAlt, true)
  for _ = 1, 15 do
    R.mouseDelta = R.Vector2.new(-40, 25)
    R.run(1 / 30)
  end
  R.mouseDelta = R.Vector2.new(0, 0)
  local diff2 = offFwd()
  check(diff2 > 15, string.format("按住 Alt 动鼠标：头转开了（离前方 %.0f°、相对机头 %.0f°）", diff2, relYaw(cam.CFrame.LookVector)))
  T.key(Enum.KeyCode.LeftAlt, false)
  R.run(0.8)
  check(offFwd() < 12, string.format("松开 Alt：头回到前方（差 %.1f°）", offFwd()))
  R.run(0.5)
  if C.flyMouseAim then C.flyMouseAim(true) end   -- 后面照默认（战雷式鼠标瞄准）
end

-- 导出给预览图：座舱眼位看前面、看左右、低头看屏幕
local dumpCams = {}
if dumpDir then
  local ref = cur.b.groups.hull.world
  dumpCams.pilot = ref * R.CFrame.Angles(math.rad(-8), 0, 0)
  dumpCams.panel = ref * R.CFrame.Angles(math.rad(-32), 0, 0)
  dumpCams.left = ref * R.CFrame.Angles(0, math.rad(70), 0) * R.CFrame.Angles(math.rad(-25), 0, 0)
  dumpCams.right = ref * R.CFrame.Angles(0, math.rad(-70), 0) * R.CFrame.Angles(math.rad(-25), 0, 0)
  dofile(MOCK_DIR .. "/interior_dump.lua")(cur, ref, dumpCams, dumpDir .. "/interior_" .. AIR .. ".json", cam, Enum)
end

print("⑤ K 导演镜头、U 藏界面")
T.tap(Enum.KeyCode.K)
R.run(0.2)
check(C.interiorState().mode == "free", "K：导演镜头")
local fp0 = cur.b.groups.hull.world:PointToObjectSpace(cam.CFrame.Position)
T.key(Enum.KeyCode.PageUp, true)
R.run(0.5)
T.key(Enum.KeyCode.PageUp, false)
local fp1 = cur.b.groups.hull.world:PointToObjectSpace(cam.CFrame.Position)
check(fp1.Y > fp0.Y + 0.5, string.format("导演镜头 PageUp 往上挪（%.1f → %.1f 格），跟着飞机走", fp0.Y, fp1.Y))
local hidFree = 0
for _, p in ipairs(cur.zone or {}) do if p.LocalTransparencyModifier == 1 then hidFree = hidFree + 1 end end
check(hidFree == 0, "导演镜头从外面看：外模型完整（座舱盖放回来）")
T.tap(Enum.KeyCode.K)
R.run(0.2)
check(C.interiorState().mode == "seat", "再按 K：回到座位")
T.tap(Enum.KeyCode.U)
R.run(0.2)
local function uiOn()
  local n = 0
  for _, g in ipairs(me.PlayerGui:GetChildren()) do if g:IsA("ScreenGui") and g.Enabled and not g:GetAttribute("Fx") then n = n + 1 end end
  return n
end
local function uiNames()
  local t = {}
  for _, g in ipairs(me.PlayerGui:GetChildren()) do if g:IsA("ScreenGui") and g.Enabled and not g:GetAttribute("Fx") then table.insert(t, g.Name) end end
  return table.concat(t, ",")
end
check(uiOn() == 0, "U：界面全藏起来（还开着 " .. uiOn() .. " 个：" .. uiNames() .. "；座舱盖眩光不算界面）")
T.tap(Enum.KeyCode.U)
R.run(0.2)
check(uiOn() > 3, "再按 U：界面回来了（" .. uiOn() .. " 个）")

print("⑥ V 出座舱、下飞机")
T.tap(Enum.KeyCode.V)
R.run(0.4)
check(not C.interiorOn(), "V：出座舱，内饰收起来")
check(v.M.pilotsOn == true, "外模型的飞行员放回来")
local back = 0
for _, p in ipairs(cur.zone or {}) do if p.LocalTransparencyModifier == 0 then back = back + 1 end end
check(back == #(cur.zone or {}), "外模型的座舱盖放回来")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
