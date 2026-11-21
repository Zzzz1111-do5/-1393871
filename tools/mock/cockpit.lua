-- 飞机座舱测试（模拟器）：python3 tools/mock/run.py tools/mock/cockpit.lua [air=j20|j35|j50|j16|j15t|f35|f22|a10c] [dump=<目录>]
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
local US = { f35 = true, f22 = true, a10c = true, ah64e = true, uh60 = true, ch47 = true, b2 = true }
local side = US[AIR] and "def" or "atk"

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
T.tap(Enum.KeyCode.V)
R.run(0.6)
local I = C.interiorState()
local cur = I.cur
check(C.interiorOn() and cur ~= nil and cur.spec.air and I.mode == "seat", "按 V：坐进座舱（" .. tostring(cur and cur.key) .. "）")
if not cur then T.summary() return end
local nParts, nScreens, nLights, nGlass = #cur.b.parts, #cur.b.screens, #cur.b.lights, #(cur.spec.glass or {})
check(nParts > 250, "座舱零件 " .. nParts .. " 个")
check(nScreens >= 5, "屏幕 " .. nScreens .. " 块")
local live = 0
for _, s in ipairs(cur.b.screens) do if s.update then live = live + 1 end end
check(live == nScreens, string.format("屏幕页面都起来了（%d / %d）", live, nScreens))
check(nLights >= 2, "座舱灯 " .. nLights .. " 盏")
check(nGlass >= 8, "座舱盖玻璃 " .. nGlass .. " 块")
local scr = 0
for _, g in ipairs(cur.spec.glass or {}) do
  local sg = g:FindFirstChildOfClass("SurfaceGui")
  if sg and #sg:GetChildren() >= 20 then scr = scr + 1 end
  check(g.Material == Enum.Material.Glass, "玻璃是 Glass 材质（看出去有折射）")
  break
end
check(scr == 1, "玻璃上有划痕、污渍")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
local v = C.viewById(e.id)
local eyeW = v.cf * CF(cur.eyeBody)
check((cam.CFrame.Position - eyeW.Position).Magnitude < 0.25 * 2.8, string.format("镜头在飞行员眼位（差 %.2f 格）", (cam.CFrame.Position - eyeW.Position).Magnitude))
local q = v.cf:PointToObjectSpace(cam.CFrame.Position)
local sideOk = (cur.spec.heli or cur.spec.eyeShift) and 0.8 * 2.8 or v.def.W * 0.1   -- 并排座：机长坐一边
check(math.abs(q.X) < sideOk and q.Z < 0, string.format("眼位在机身中线（并排座在一边）、机头那半边（机体坐标 %.1f, %.1f, %.1f）", q.X, q.Y, q.Z))
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
for _, k in ipairs(keys) do
  local l = k.label
  if l == "RDR" or l == "雷达" then want = k break end
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
  local radar = false
  for _, s in ipairs(cur.b.screens) do
    for _, d in ipairs(s.gui:GetDescendants()) do
      if d:IsA("TextLabel") and (d.Text:match("^RDR") or d.Text:match("^雷达")) then radar = true end
    end
  end
  check(radar, "按「" .. want.label .. "」：左边那块换成雷达页面")
  if not cur.spec.heli then T.key(Enum.KeyCode.LeftAlt, false) end
else check(false, "找到雷达键") end
local lk0 = fst.cf.LookVector
fst.aimYaw, fst.aimPitch = math.atan2(-lk0.X, -lk0.Z), 0
if cur.spec.heli then fst.camYaw, fst.camPitch = math.atan2(-lk0.X, -lk0.Z), 0 end

print("③ 起飞：油门杆、驾驶杆、起落架手柄跟着动；屏幕、平显是实时数据")
local function gearLit()
  local n = 0
  for _, l in ipairs(cur.b.leds) do if l.role == "gear" and l.p.Color == l.on then n = n + 1 end end
  return n
end
if not cur.spec.heli then check(gearLit() == 3, "停在地上：起落架三个绿灯亮（" .. gearLit() .. "）") end
local gh0 = cur.b.groups.gearh and cur.b.groups.gearh.anim
local thrZ0 = cur.b.groups.thr and cur.b.groups.thr.anim.Position.Z
local maxStick = 0
local function stickNow()
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
    local thrZ1 = cur.b.groups.thr.anim.Position.Z
    check(thrZ1 < thrZ0 - 0.05 * 2.8, string.format("油门杆往前推了 %.2f 米", (thrZ0 - thrZ1) / 2.8))
    for _ = 1, 30 do R.run(1 / 30) stickNow() end
    T.key(Enum.KeyCode.S, false)
    for _ = 1, 150 do R.run(1 / 30) stickNow() end   -- 加力爬一会儿
    T.key(Enum.KeyCode.LeftShift, false)
    fst.thr = 100
  end
  check(maxStick > math.rad(1.5), string.format("驾驶杆跟着拉（最大 %.1f°）", math.deg(maxStick)))
end
if not heli then
  -- 起飞爬过 15 米自动收起落架（Fly.lua），等它收完
  T.runUntil(function() return (fst.gear or 1) < 0.02 end, 10)
  check((fst.gear or 1) < 0.02 and gearLit() == 0, string.format("起落架收上去了：绿灯都灭（起落架 %.2f、亮 %d）", fst.gear or -1, gearLit()))
  local gh1 = cur.b.groups.gearh.anim
  check(math.abs(select(1, gh0:ToObjectSpace(gh1):ToEulerAnglesXYZ())) > math.rad(20), "起落架手柄扳上去了")
  T.tap(Enum.KeyCode.G)
  R.run(3)
  check((fst.gear or 0) > 0.9 and gearLit() == 3, string.format("G 放起落架：三个绿灯又亮了（起落架 %.2f、亮 %d）", fst.gear or -1, gearLit()))
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
  -- 用户 11-21：飞机改成 WASD 飞、没有准心——头看前方（航迹），鼠标不转头；按住 Alt 动鼠标转头，松开回到前方
  local function offFwd() return math.deg(math.acos(math.max(-1, math.min(1, cam.CFrame.LookVector:Dot(fst.vdir or fst.cf.LookVector))))) end
  for _ = 1, 15 do
    R.mouseDelta = R.Vector2.new(-40, 0)
    R.run(1 / 30)
  end
  check(offFwd() < 12, string.format("不按 Alt 动鼠标：头不转，看着前方（偏 %.1f°）", offFwd()))
  T.key(Enum.KeyCode.LeftAlt, true)
  for _ = 1, 15 do
    R.mouseDelta = R.Vector2.new(-40, 25)
    R.run(1 / 30)
  end
  local diff2 = offFwd()
  check(diff2 > 15, string.format("按住 Alt 动鼠标：头转开了（离前方 %.0f°、相对机头 %.0f°）", diff2, relYaw(cam.CFrame.LookVector)))
  T.key(Enum.KeyCode.LeftAlt, false)
  R.run(0.8)
  check(offFwd() < 12, string.format("松开 Alt：头回到前方（差 %.1f°）", offFwd()))
  R.run(0.5)
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
