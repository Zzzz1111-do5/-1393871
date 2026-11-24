-- 战雷式投弹（模拟器）：python3 tools/mock/run.py tools/mock/bombsight.lua
--   用户 11-24：「飞机锁定敌目标改成战雷一模一样的 包括投弹以及各方面操作细节和手感」
--   ① F7 轰炸瞄准镜（战雷的「轰炸机视角」）：镜头到机腹往下看、十字中心就是炸弹落点；选上炸弹；平显收起；鼠标左右修航向、教官平飞；
--      F7 这时不开性能面板（Ctrl + F7 才开）
--   ② Shift + B 投弹数量：单投 → 双投 → 齐投 → 单投
--   ③ Alt + 中键 标目标点（兴趣点）；落点走到目标点自动投，炸点离目标点近；屏幕上红方框 + 箭头 + 倒计时；地上红方框
--   ④ 航向偏得多：箭头变灰、飞过去不投
--   ⑤ 双投两枚同时出；齐投一枚接一枚把这种炸弹投完
--   ⑥ 下飞机：瞄准镜、目标点都收掉
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 120)
local me = T.join("P1", 6301, true)
T.runUntil(function() return G.round and G.round.phase == "battle" end, 200)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
R.run(1)
local C = T.C
T.act("deploy", "rifle", "af2")
R.run(2)
check(P.alive, "出生了")
local cam = R.services.Workspace.CurrentCamera
local AD = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs"))
local function find(name)
  for _, d in ipairs(me.PlayerGui:GetDescendants()) do
    if d.Name == name then return d end
  end
end

-- 服务器投出来的炸弹、炸点
local launched, booms = {}, {}
local launch0, explode0 = G.launch, G.explode
G.launch = function(s)
  if s.kind == "bomb" then table.insert(launched, { t = os.clock(), s = s }) end
  return launch0(s)
end
G.explode = function(pos, w, src, sc)
  if w and w.id == "b250" then table.insert(booms, pos) end
  return explode0(pos, w, src, sc)
end

print("① F7 轰炸瞄准镜")
local p0 = me.Character.HumanoidRootPart.Position
local acf = CF(p0.X, math.max(G.Map.ground(p0.X, p0.Z), 0) + 700, p0.Z)
local jet = G.spawnAircraft("atk", "h6k", acf, nil, P)
me.Character:PivotTo(acf * CF(4, 0, 0))
T.act("enterVeh", jet.id)
R.run(0.2)
local js = C.fly
check(js ~= nil and js.pilot and js.d.id == "h6k", "空中坐进轰-6K")
if not js then T.summary() return end
C.flyMouseAim(true)
js.ground = false
js.spd = js.d.vMil * 0.85
js.vel = js.cf.LookVector * js.spd
js.vdir = js.cf.LookVector
js.thr, js.gearWant, js.gear = 90, 0, 0
local f0 = js.cf.LookVector
js.aimYaw, js.aimPitch = math.atan2(-f0.X, -f0.Z), 0
R.run(0.5)
local function bombsLeft()
  local n = 0
  for i, w in ipairs(js.load or {}) do if w == "b250" then n = n + (js.stores[i] or 0) end end
  return n
end
local n0 = bombsLeft()
check(n0 >= 20, "挂着 250 公斤炸弹 " .. n0 .. " 枚")
-- 先选上导弹（看 F7 会不会自己换成炸弹）
for i, w in ipairs(js.wl) do if w == "kd88" then js.wi = i end end
check(C.flyWantsF7() == true, "挂着炸弹：F7 归轰炸瞄准镜")
T.tap(Enum.KeyCode.F7)
R.run(0.4)
local perf = C.perfPanel
check(js.bsight == true, "按 F7：开轰炸瞄准镜")
check(perf == nil or perf.Enabled ~= true, "同一下 F7 没开性能面板")
check(js.wl[js.wi] == "b250", "选上了炸弹（" .. tostring(js.wl[js.wi]) .. "）")
local lk = cam.CFrame.LookVector
check(lk.Y < -0.3, string.format("镜头往下看（视线 y %.2f）", lk.Y))
local imp = js.bsImp
local sp = imp and cam:WorldToViewportPoint(imp)
local vs = cam.ViewportSize
check(sp ~= nil and math.abs(sp.X - vs.X / 2) < 40 and math.abs(sp.Y - vs.Y / 2) < 40,
  string.format("十字中心对着炸弹落点（落点在屏幕 %.0f, %.0f；中心 %.0f, %.0f）", sp and sp.X or -1, sp and sp.Y or -1, vs.X / 2, vs.Y / 2))
local bsGui = C.bsGui
check(bsGui ~= nil and bsGui.Enabled == true, "瞄准镜画面（圆形视场、十字、刻度）")
local data = find("BsData")
check(data ~= nil and data.Text:match("%d") ~= nil, "左边写着高度、地速、落下时间、投弹方式：" .. (data and data.Text:gsub("\n", " / ") or ""))
local tickN = 0
for _, d in ipairs(bsGui:GetDescendants()) do if d.Name == "BsTick" and d.Visible then tickN = tickN + 1 end end
check(tickN >= 2, "竖线上有秒刻度（看得见 " .. tickN .. " 个）")
check(cam.FieldOfView < 50, string.format("视场收窄（%.0f°）", cam.FieldOfView))
local mm = find("MouseAim")
check(mm == nil or not T.visible(mm), "平显（鼠标瞄准小圈）收起来了")
-- 鼠标往右：只细细地修航向，教官平飞
local y0 = js.aimYaw
js.aimPitch = -0.2
for _ = 1, 10 do
  R.mouseDelta = T.V2 and T.V2(30, 0) or R.Vector2.new(30, 0)
  R.run(1 / 30)
end
R.mouseDelta = R.Vector2.new(0, 0)
local dy = math.deg(y0 - js.aimYaw)
check(dy > 3 and dy < 15, string.format("鼠标往右 300 像素：航向往右修了 %.1f°（细调，平时鼠标瞄准是 72°）", dy))
check(math.abs(js.aimPitch) < 0.2 * 0.8, string.format("教官往平飞拉（俯仰 −0.20 → %.2f）", js.aimPitch))
js.aimYaw = y0
js.aimPitch = 0

print("② Shift + B 投弹数量")
local function shiftB()
  T.key(Enum.KeyCode.LeftShift, true)
  T.tap(Enum.KeyCode.B)
  T.key(Enum.KeyCode.LeftShift, false)
  R.run(0.1)
end
check(C.flyBombSeries() == 1, "默认单投")
shiftB()
check(C.flyBombSeries() == 2, "Shift + B：双投")
shiftB()
check(C.flyBombSeries() == 0, "再按：齐投")
shiftB()
check(C.flyBombSeries() == 1, "再按：回到单投")

print("③ Alt + 中键 标目标点 → 落点到了自动投")
T.key(Enum.KeyCode.LeftAlt, true)
T.mouse(true, 640, 360, Enum.UserInputType.MouseButton3)
T.mouse(false, 640, 360, Enum.UserInputType.MouseButton3)
T.key(Enum.KeyCode.LeftAlt, false)
R.run(0.1)
check(js.poi ~= nil, "Alt + 中键：标了目标点")
-- 换成落点前方 3 秒的地方（地速 × 3），看自动投
local hv = R.Vector3.new(js.vel.X, 0, js.vel.Z)
local dir, gs = hv.Unit, hv.Magnitude
imp = js.bsImp
local tp = imp + dir * (gs * 3)
tp = R.Vector3.new(tp.X, math.max(G.Map.ground(tp.X, tp.Z), 0), tp.Z)
js.poi, js.ccrpArm = tp, nil
R.run(0.3)
local cc = js.ccrp
check(cc ~= nil and cc.ok and cc.ttr > 2 and cc.ttr < 3.2, string.format("倒计时 %.1f 秒、航向对得上（偏 %.0f 格）", cc and cc.ttr or -1, cc and cc.cross or -1))
local box, arrow = find("PoiBox"), find("PoiArrow")
check(box ~= nil and T.visible(box), "屏幕上目标点一个红方框")
check(arrow ~= nil and T.visible(arrow) and arrow:GetAttribute("Ok") == true, string.format("上面一根箭头（白的：照现在的航向投得中；Ok=%s、ccrp.ok=%s、passed=%s）",
  tostring(arrow and arrow:GetAttribute("Ok")), tostring(js.ccrp and js.ccrp.ok), tostring(js.ccrp and js.ccrp.passed)))
local pt = find("PoiText")
check(pt ~= nil and pt.Text:match("%d") ~= nil, "旁边写还有几秒投弹：" .. (pt and pt.Text:gsub("\n", " ") or ""))
local marks = R.workspace:FindFirstChild("Marks")
local pm = 0
for _, c in ipairs(marks and marks:GetChildren() or {}) do if c.Name == "PoiMark" then pm = pm + 1 end end
check(pm == 4, "地上也有红方框（" .. pm .. " 条边）")
local nl = #launched
T.runUntil(function() return #launched > nl end, 5)
check(#launched == nl + 1, string.format("落点走到目标点：自动投了 %d 枚", #launched - nl))
check(js.ccrpRelT ~= nil, "屏幕上写「投弹！」")
local nb = #booms
T.runUntil(function() return #booms > nb end, 15)
local bp = booms[nb + 1]
local miss = bp and ((bp.X - tp.X) ^ 2 + (bp.Z - tp.Z) ^ 2) ^ 0.5 or -1
check(bp ~= nil and miss < 22, string.format("炸点离目标点 %.1f 格（250 公斤弹杀伤半径 30 格）", miss))

print("④ 航向偏得多：箭头变灰、不投")
hv = R.Vector3.new(js.vel.X, 0, js.vel.Z)
dir, gs = hv.Unit, hv.Magnitude
local right = R.Vector3.new(-dir.Z, 0, dir.X)
imp = C.bombImpact((js.cf * CF(0, -(js.d.H or 4) * 0.35 - 1.5, 0)).Position, js.vel - js.cf.UpVector * 4)
tp = imp + dir * (gs * 2) + right * 220
tp = R.Vector3.new(tp.X, math.max(G.Map.ground(tp.X, tp.Z), 0), tp.Z)
js.poi, js.ccrpArm = tp, nil
R.run(0.3)
cc = js.ccrp
check(cc ~= nil and not cc.ok and cc.dev > 0, string.format("目标点在右边 220 格：投不中（偏 %.0f 格），箭头叫往右转（%.0f°）", cc and cc.cross or -1, cc and cc.dev or 0))
check(arrow:GetAttribute("Ok") == false, "箭头变灰")
nl = #launched
R.run(3)
check(#launched == nl, "飞过去了也没投（" .. (#launched - nl) .. " 枚）")
check(js.ccrp and js.ccrp.passed == true, "写着「飞过了 · 掉头再来」")
js.poi = nil
R.run(0.2)

print("⑤ 双投、齐投")
C.flyBombSeries(2)
nl = #launched
local left0 = bombsLeft()
T.key(Enum.KeyCode.F, true)
R.run(0.1)
T.key(Enum.KeyCode.F, false)
R.run(0.2)
local same = #launched == nl + 2 and math.abs(launched[nl + 1].t - launched[nl + 2].t) < 0.005
check(same, string.format("双投：两枚一起出（%d 枚）", #launched - nl))
R.run(0.8)
check(bombsLeft() == left0 - 2, string.format("挂着的少了两枚（%d → %d）", left0, bombsLeft()))
C.flyBombSeries(0)
nl = #launched
left0 = bombsLeft()
T.key(Enum.KeyCode.F, true)
R.run(1 / 30)
T.key(Enum.KeyCode.F, false)
R.run(0.1)
local early = #launched - nl
R.run(left0 * 0.08 + 1.2)
check(early >= 1 and early < left0, string.format("齐投：一枚接一枚（0.12 秒时出了 %d 枚）", early))
check(#launched - nl == left0 and bombsLeft() == 0, string.format("这种炸弹全投完了（投了 %d 枚、还剩 %d）", #launched - nl, bombsLeft()))
C.flyBombSeries(1)

print("⑥ Ctrl + F7 性能面板；下飞机收掉")
T.key(Enum.KeyCode.LeftControl, true)
T.tap(Enum.KeyCode.F7)
T.key(Enum.KeyCode.LeftControl, false)
R.run(0.1)
check(perf == nil or perf.Enabled == true, "Ctrl + F7：开性能面板（瞄准镜还开着：" .. tostring(js.bsight) .. "）")
if perf then perf.Enabled = false end
js.poi = acf.Position
T.tap(Enum.KeyCode.Space)
R.run(1.5)
check(C.fly == nil, "跳伞下了飞机")
check(not bsGui.Enabled and not C.ccrpGui.Enabled, "瞄准镜、目标点的画面都收掉了")
pm = 0
for _, c in ipairs(marks and marks:GetChildren() or {}) do if c.Name == "PoiMark" then pm = pm + 1 end end
check(pm == 0, "地上的红方框也收掉了")
G.launch, G.explode = launch0, explode0
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
