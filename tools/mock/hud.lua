-- 飞机平显、右侧武器栏、光电吊舱测试（模拟器）：python3 tools/mock/run.py tools/mock/hud.lua [v]
--   用户 11-19：飞机操作界面照 MWT 的截图改（原来是 DCS 式的绿色平显：速度 / 高度框、大圈、右侧武器栏——现在只有遥控无人机还用）；
--   飞机驾驶按 P 也要能切换光电视角
--   ① 准星两边高度 / 速度、右上机型卡（名字、全息侧影、血量）、机头标记、发光的准星细圈；原来的平显（连俯仰梯）收起来；圆形雷达挪到左上
--   ② 右下六边形武器键：按键号、剩几发，最后一个热诱弹；按 2 选中第二个；准星上方写选中的弹、右边剩几发
--   ⑤ 空中：机头前方的全息标记（斜放的一块面）、战雷式锁定框（锁定中一闪一闪、锁上常亮，框上型号、右边距离，出了离轴角变黄不能发射）、
--      N 切 夜视 → 热成像 → 关（进光电吊舱让开、下飞机关掉）
--   ③ P 进光电：镜头到机腹吊舱、平显的圈收起、吊舱画面（模式、倍率、距离）；鼠标只转吊舱、飞机航向不跟着变；Z 变焦；V 电视 → 白热（热成像高亮）；
--      自己的飞机藏起来；再按 P 回来
--   ④ 直升机进光电：不低头往前冲
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 120)
local me = T.join("P1", 6201, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
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

local function find(name)
  for _, d in ipairs(me.PlayerGui:GetDescendants()) do
    if d.Name == name then return d end
  end
end
local function shown(name)
  local d = find(name)
  return d ~= nil and T.visible(d), d
end

print("① 开飞机的界面（用户 11-19 照 MWT 截图改）：高度 / 速度括号、右上机型卡、机头标记、原来的 DCS 平显收起、圆形雷达挪到左上")
local A2 = G.Map.AFIELD2
local x, z = A2.x + 300, A2.z - A2.wid / 2 - 220
local gy = G.airSurface(x, z)
local e = G.spawnAircraft("atk", "j20", CF(x, gy + 6, z), nil, P)
check(e ~= nil, "放了一架歼-20")
me.Character:PivotTo(CF(x + 20, gy + 3.5, z))
R.run(0.3)
T.act("enterVeh", e.id)
R.run(1.2)
local st = C.fly
check(st ~= nil and P.vehicle == e and st.pilot, "坐进了驾驶座")
if not st then T.summary() return end
local okAlt, altB = shown("AltBracket")
local okSpd, spdB = shown("SpdBracket")
local function val(b) local v = b and b:FindFirstChild("Value") return v and v.Text end
check(okAlt and okSpd and val(altB) ~= nil and val(altB):match("^%d+$") ~= nil and val(spdB):match("^%d+$") ~= nil,
  string.format("准星两边：高度 %s、速度 %s", tostring(val(altB)), tostring(val(spdB))))
check(altB and altB:FindFirstChild("Cap").Text == C.T("air.cap.alt") and spdB:FindFirstChild("Cap").Text == C.T("air.cap.spd"), "左边「高度」、右边「速度」")
local okCard = shown("AirCard")
local an, ah = find("AirName"), find("AirHp")
check(okCard and an and an.Text == C.T("veh.j20") and ah and ah.Text:find("/" .. tostring(math.floor(e.maxHp + 0.5)), 1, true) ~= nil,
  string.format("右上：机型 %s、血量 %s", tostring(an and an.Text), tostring(ah and ah.Text)))
local A = C.airHud
check(A ~= nil and (T.visible(A.icon) or T.visible(A.iconFall)), "右上有这架飞机的全息侧影（用不了 EditableImage 时是一道横线）")
check(A ~= nil and (T.visible(A.bore) or T.visible(A.boreFall)), "机头指向的小飞机")
local dcs = find("DcsHud")
local ring = find("HudRing")
check(dcs ~= nil and not T.visible(dcs) and not shown("SpdBox") and not shown("HudRing") and not shown("WeaponList") and not shown("GLoad"),
  "原来的 DCS 平显（速度 / 高度框、大圈、右侧武器栏、G / α / M）收起来了")
check(C.airRadarDocked ~= nil and C.airRadarDocked(), "圆形雷达挪到了左上")
local nLad = 0
for _, d2 in ipairs(me.PlayerGui:GetDescendants()) do
  if d2.Name == "PitchLadder" and T.visible(d2) then nLad = nLad + 1 end
end
check(nLad == 0, "中间没有俯仰梯那些一段段的线（用户 11-19；只有无人机的老平显还画）：" .. nLad .. " 根")
local ar = find("AimRing")
check(ar == nil or not T.visible(ar), "有人开的固定翼不画准星圈（用户 11-21：WASD 控制方向、不要准心控制）")
do   -- 机头的全息标记（机头前方 300 格）钉在屏幕正中：镜头跟着机身（用户 11-21：飞行方向标志不要动来动去）
  local cam = R.services.Workspace.CurrentCamera
  local sp = cam:WorldToViewportPoint(st.cf.Position + st.cf.LookVector * 300)
  local off = math.sqrt((sp.X - cam.ViewportSize.X / 2) ^ 2 + (sp.Y - cam.ViewportSize.Y / 2) ^ 2)
  check(off <= 2, string.format("机头的全息标记在屏幕正中（偏 %.1f 像素）", off))
end

print("② 右下六边形武器键：按键号、弹的图标、剩几发，最后一个热诱弹；按 2 选中第二个；准星上方写选中的弹、右边剩几发")
local bar = find("AirWeapons")
check(bar ~= nil and T.visible(bar), "右下一排武器键")
local hexes = {}
for _, c in ipairs(bar and bar:GetChildren() or {}) do
  if c.Name:sub(1, 3) == "Hex" and T.visible(c) then hexes[#hexes + 1] = c end
end
table.sort(hexes, function(a2, b2) return a2.Position.X.Offset < b2.Position.X.Offset end)
check(#hexes == #st.wl + 1, string.format("一种挂载一个 + 热诱弹（%d 个，挂载 %d 种）", #hexes, #st.wl))
local allOk, desc = true, {}
for i, hx in ipairs(hexes) do
  local key, cnt = hx:FindFirstChild("Key"), hx:FindFirstChild("Count")
  local want = (i <= #st.wl) and tostring(i) or "X"
  if not (key and key.Text == want and cnt and cnt.Text:match("^%d+$")) then allOk = false end
  desc[#desc + 1] = string.format("[%s] %s ×%s", key and key.Text or "?", tostring(hx:GetAttribute("Wid")), cnt and cnt.Text or "?")
end
check(allOk, "每个都有按键号、剩几发：" .. table.concat(desc, "  "))
check(hexes[#hexes] ~= nil and hexes[#hexes]:GetAttribute("Wid") == "flare", "最后一个是热诱弹")
check(hexes[2] ~= nil and hexes[1]:GetAttribute("Sel") == true and hexes[2]:GetAttribute("Sel") == false, "选中的第一个发光（" .. tostring(st.wl[1]) .. "）")
local wn = find("WeaponName")
check(wn ~= nil and T.visible(wn) and wn.Text == C.T("aw." .. st.wl[1]), "准星上方写着选中的弹：" .. tostring(wn and wn.Text))
T.tap(Enum.KeyCode.Two)
R.run(0.2)
check(st.wi == 2 and hexes[2]:GetAttribute("Sel") == true and hexes[1]:GetAttribute("Sel") == false, "按 2：第二个亮了（" .. tostring(st.wl[2]) .. "）")
check(wn ~= nil and wn.Text == C.T("aw." .. st.wl[2]), "准星上方跟着换：" .. tostring(wn and wn.Text))
local sc = find("StoreCount")
check(sc ~= nil and T.visible(sc) and sc.Text:match("^%d+$") ~= nil, "准星右边剩几发：" .. tostring(sc and sc.Text))

print("③ P：光电吊舱")
local fov0 = cam.FieldOfView
T.tap(Enum.KeyCode.P)
R.run(0.6)
check(st.eo == true, "按 P 进了光电")
local okE = shown("EoView")
check(okE, "吊舱画面（取景框、十字）出来了")
check(not T.visible(ring) and not T.visible(find("AirCenter")), "平显收起来了（开飞机的界面也收起）")
local belly = st.cf:PointToObjectSpace(cam.CFrame.Position)
check(belly.Y < 0 and math.abs(belly.X) < 1, string.format("镜头在机腹下面（机身坐标 %.1f, %.1f, %.1f）", belly.X, belly.Y, belly.Z))
local em = find("EoMode")
check(em and em.Text:find(C.T("eo.tv"), 1, true), "左上写着模式：" .. tostring(em and em.Text))
local yaw0, aim0 = st.eoYaw, st.aimYaw
R.mouseDelta = R.Vector2.new(120, 60)
R.run(0.1)
check(st.eoYaw ~= yaw0 and st.aimYaw == aim0, string.format("鼠标只转吊舱（吊舱 %.2f → %.2f，飞机航向 %.2f 不变）", yaw0, st.eoYaw, st.aimYaw))
T.tap(Enum.KeyCode.Z)
R.run(1)
check(st.zoom == 4 and cam.FieldOfView < 30, string.format("Z 变焦 4×（视场 %.0f°；再按 12×、30×，用户：光电要看得远一点）", cam.FieldOfView))
T.tap(Enum.KeyCode.V)
R.run(0.2)
local cc = R.services.Lighting:FindFirstChild("EoCC")
local hl = cam:FindFirstChild("EoHeat")
check(st.eoMode == 2 and cc and cc.Enabled and hl and hl.Enabled, "V 切到热成像白热（画面调色、实体高亮）")
check(em.Text:find(C.T("eo.whot"), 1, true) ~= nil, "模式字跟着变：" .. em.Text)
local v = C.views and C.views[e.model]
local hidden = v and v.M and v.M.plist[1] and v.M.plist[1].LocalTransparencyModifier == 1
check(hidden, "自己的飞机藏起来（不挡吊舱）")
local hint = find("EoHint")
check(hint and hint.Text:find("P", 1, true) and hint.Text:find("V", 1, true), "底下写着操作：" .. tostring(hint and hint.Text))
T.tap(Enum.KeyCode.P)
R.run(1)
check(not st.eo and not T.visible(find("EoView")) and not cc.Enabled and not hl.Enabled, "再按 P 回到平显，调色、高亮关掉")
check(v and v.M.plist[1].LocalTransparencyModifier == 0, "自己的飞机又看得见了")
check(cam.FieldOfView > 60, string.format("视场回来了（%.0f°）", cam.FieldOfView))

print("④ 直升机进光电：不低头往前冲")
T.tap(Enum.KeyCode.Space)   -- 空格下飞机（F 现在是发导弹）
R.run(1.5)
local hx, hz = x + 260, z - 120
local hgy = G.airSurface(hx, hz)
local hcf = CF(hx, hgy + 6, hz)
local h = G.spawnAircraft("atk", "z10", hcf, nil, P)
me.Character:PivotTo(CF(hx + 20, hgy + 3.5, hz))
R.run(0.3)
T.act("enterVeh", h.id)
R.run(1)
local hs = C.fly
check(hs ~= nil and hs.d.kind == "heli", "坐进了直-10")
if hs then
  T.runUntil(function() return hs.rpm and hs.rpm >= 95 end, 15)
  T.key(Enum.KeyCode.E, true)
  R.run(4)
  T.key(Enum.KeyCode.E, false)
  hs.camPitch = -0.12 - 0.45   -- 正往下看
  R.run(0.5)
  T.tap(Enum.KeyCode.P)
  R.run(3)
  local f = V3(-math.sin(hs.yaw), 0, -math.cos(hs.yaw))
  check(hs.eo and hs.tiltP > -0.12 and math.abs(hs.hv:Dot(f)) < 25, string.format("光电里悬停：机头 %.0f°、前进速度 %.0f", math.deg(hs.tiltP), hs.hv:Dot(f)))
  T.tap(Enum.KeyCode.P)
  R.run(0.3)
end

print("⑤ 空中：机头前方的全息标记、战雷式锁定框（框上型号、右边距离、出了离轴角变黄不能发射）、N 切 夜视 → 热成像 → 关")
T.tap(Enum.KeyCode.Space)
R.run(1.5)
local AD = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs"))
local p0 = me.Character.HumanoidRootPart.Position
local acf = CF(p0.X, math.max(G.Map.ground(p0.X, p0.Z), 0) + 700, p0.Z)
local foe = G.spawnAircraft("def", "a10c", acf * CF(60, 20, -900), nil, nil)
local jet = G.spawnAircraft("atk", "j20", acf, nil, P)
me.Character:PivotTo(acf * CF(4, 0, 0))
T.act("enterVeh", jet.id)
R.run(0.2)
local js = C.fly
check(js ~= nil and js.pilot and js.d.id == "j20", "空中坐进歼-20")
if js and foe then
  js.ground = false   -- 刚放的飞机算停在地上：改成巡航
  js.spd = js.d.vMil * 0.8
  js.vel = js.cf.LookVector * js.spd
  js.vdir = js.cf.LookVector   -- 航迹也摆平（刚放的飞机算停在地上，悬在半空已经往下掉了；WASD 飞以后松杆不会自己拉平）
  js.thr, js.gearWant, js.gear = 85, 0, 0
  R.run(0.5)
  foe.root.CFrame = js.cf * CF(60, 20, -700)
  R.run(0.3)
  local A2 = C.airHud
  local back = A2.holoPart.CFrame.LookVector * -1   -- 贴图的那一面（Back，+Z）朝哪
  check(A2.holoGui.Enabled and back:Dot(js.cf.UpVector) > 0.5 and back:Dot(js.cf.LookVector * -1) > 0.3,
    string.format("机头前方的全息标记：一块斜放的面、朝机身后上方（往上 %.2f、往后 %.2f）", back:Dot(js.cf.UpVector), back:Dot(js.cf.LookVector * -1)))
  local ahead = js.cf:PointToObjectSpace(A2.holoPart.CFrame.Position)
  check(-ahead.Z > 250 and math.abs(ahead.X) < 1 and math.abs(ahead.Y) < 1, string.format("在机头正前方 %.0f 格", -ahead.Z))
  local w = AD.W[js.wl[js.wi]]
  check(js.lock ~= nil and w and w.kind == "aam", "锁着前方的 A-10（" .. tostring(js.wl[js.wi]) .. "）")
  local lm = find("LockMark")
  if js.lock and lm then   -- 战雷式锁定（用户 11-23）：细的绿方框、框上型号、右边距离和接近速度
    js.lockT = 0.5 * (w.lockTime or 1)
    R.run(1 / 60)
    local box = lm:FindFirstChildOfClass("UIStroke")
    check(T.visible(lm) and lm:GetAttribute("Locked") == false and math.abs((lm:GetAttribute("Progress") or 0) - 0.5) < 0.1,
      string.format("锁定中：目标上的方框（进度 %.2f），还没锁上", lm:GetAttribute("Progress") or -1))
    R.run((w.lockTime or 1) * 0.6)
    local nm, rg = lm:FindFirstChild("TargetName"), lm:FindFirstChild("TargetRange")
    check(lm:GetAttribute("Locked") == true and box ~= nil and box.Transparency < 0.5, "锁上了：方框常亮")
    check(nm ~= nil and nm.Text ~= "" and rg ~= nil and rg.Text:match("%d") ~= nil,
      string.format("框上写型号（%s）、右边写距离（%s）", nm and nm.Text or "", rg and rg.Text or ""))
    local seeker = find("Seeker")
    if lm:GetAttribute("Seeker") == "ir" then check(seeker ~= nil and T.visible(seeker), "红外弹：导引头的圈套在目标上") end
    -- 锁定音（用户 11-24：战雷一模一样）：锁上了一声又高又稳的长音（红外）/ 快的嘀嘀声（雷达）
    local tone = js.toneSnd
    check(tone ~= nil and tone.Looped == true and (tone.Volume > 0.2 or lm:GetAttribute("Seeker") == "radar"),
      string.format("锁定音在响（音量 %.2f、音高 %.2f）", tone and tone.Volume or -1, tone and tone.PlaybackSpeed or -1))
    check(box and box.Color.G > 0.8 and box.Color.R < 0.6, "在离轴角里：框是绿的")
    foe.root.CFrame = js.cf * CF(520, 20, -640)   -- 往右偏 39°（霹雳-15 离轴角 22°、跟踪 48°）
    R.run(0.3)
    check(js.lock ~= nil and js.lock.out == true and lm:GetAttribute("InCone") == false and box.Color.R > 0.9 and box.Color.G > 0.7 and box.Color.B < 0.4,
      "出了导弹的离轴角：锁还在、框变黄")
    local function stores() local n = 0 for i, v in ipairs(js.stores or {}) do n = n + v end return n end
    local s0 = stores()
    T.tap(Enum.KeyCode.F)
    R.run(0.3)
    check(stores() == s0, string.format("这时按 F 不发射（挂载 %d → %d）", s0, stores()))
    foe.root.CFrame = js.cf * CF(60, 20, -700)
    R.run(0.3)
    check(js.lock ~= nil and not js.lock.out and box.Color.G > 0.8 and box.Color.R < 0.6, "回到离轴角里：框变回绿的")
  end
  -- N：夜视 → 热成像 → 关（不用光电吊舱）
  local cc = R.services.Lighting:FindFirstChild("AirIrCC")
  local seen, order = false, {}
  for _ = 1, 3 do
    T.tap(Enum.KeyCode.N)
    R.run(0.2)
    local nv, ir = C.nvgOn and C.nvgOn(), C.airThermalShown and C.airThermalShown()
    order[#order + 1] = (ir and "热成像") or (nv and "夜视") or "关"
    if ir then seen = cc ~= nil and cc.Enabled and not nv and T.visible(find("Scanlines")) end
  end
  check(seen, "按 N 能切到热成像（画面调灰、扫描线；夜视关着）：" .. table.concat(order, " → "))
  if not (C.airThermal and C.airThermal()) then
    for _ = 1, 3 do
      if C.airThermal and C.airThermal() then break end
      T.tap(Enum.KeyCode.N)
      R.run(0.2)
    end
  end
  T.tap(Enum.KeyCode.P)
  R.run(0.4)
  check(js.eo and not cc.Enabled and not C.airThermalShown(), "进光电吊舱：热成像先让开（吊舱有自己的画面）")
  T.tap(Enum.KeyCode.P)
  R.run(0.4)
  check(not js.eo and cc.Enabled and C.airThermalShown(), "出了吊舱：热成像回来")
  T.tap(Enum.KeyCode.Space)
  R.run(1)
  check(C.fly == nil and not cc.Enabled and not C.airThermal(), "下了飞机：热成像关掉")
end

T.summary()
