-- 飞机平显、右侧武器栏、光电吊舱测试（模拟器）：python3 tools/mock/run.py tools/mock/hud.lua [v]
--   用户：驾驶飞机时要有截图那样的界面（绿色、速度 / 高度框、一个大圈）；导弹什么的在右侧显示：按几切换到什么导弹、导弹的图标、剩余数量；
--   飞机驾驶按 P 也要能切换光电视角
--   ① 平显：速度框、高度框、航向、大圈（大小跟着选中的武器：航炮小、红外空空弹大）
--   ② 右侧武器栏：每行按键号、图标、名字、×剩几发，最后一行热诱弹；按 2 选中第二行
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

print("① 平显：速度框、高度框、航向、大圈")
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
local okS, spd = shown("SpdBox")
local okA, alt = shown("AltBox")
local okH, hdg = shown("HdgBox")
check(okS and okA and okH, "速度框、高度框、航向框都在")
local function boxText(b)
  for _, c in ipairs(b:GetChildren()) do if c.ClassName == "TextLabel" then return c.Text end end
end
check(boxText(spd) and boxText(spd):match("^%d+$") and boxText(alt):match("^%d+$") and boxText(hdg):match("^%d%d%d$"),
  string.format("框里是数字：速度 %s、高度 %s、航向 %s", tostring(boxText(spd)), tostring(boxText(alt)), tostring(boxText(hdg))))
local okR, ring = shown("HudRing")
check(okR, "中间一个大圈")
local gunPx = ring.Size.X.Offset
local okW, list = shown("WeaponList")
check(okW, "右侧武器栏")

print("② 右侧武器栏：按键号、图标、名字、剩几发；最后一行热诱弹；按 2 选中第二行")
local rows = {}
for _, r in ipairs(list:GetChildren()) do if r.Name:sub(1, 4) == "Row_" then rows[#rows + 1] = r end end
table.sort(rows, function(a, b) return a.Position.Y.Offset < b.Position.Y.Offset end)
check(#rows == #st.wl + 1, string.format("一行一种武器 + 热诱弹（%d 行，武器 %d 种）", #rows, #st.wl))
local allOk, desc = true, {}
for i, r in ipairs(rows) do
  local key = r:FindFirstChild("Key", true)
  local icon = r:FindFirstChild("Icon")
  local cnt = r:FindFirstChild("Count")
  local nm = r:FindFirstChild("Name")
  local nIcon = icon and #icon:GetChildren() or 0
  local want = (i <= #st.wl) and tostring(i) or "X"
  if not (key and key.Text == want and nIcon >= 2 and cnt and cnt.Text:match("^×%d+$") and nm and nm.Text ~= "") then allOk = false end
  desc[#desc + 1] = string.format("[%s] %s %s（图标 %d 块）", key and key.Text or "?", nm and nm.Text or "?", cnt and cnt.Text or "?", nIcon)
end
check(allOk, "每行都有按键、图标、名字、数量：" .. table.concat(desc, "  "))
check(rows[#rows].Name == "Row_flare", "最后一行是热诱弹")
local function bright(r) return r.BackgroundTransparency end
check(bright(rows[1]) < bright(rows[2]), "选中的第一行亮（" .. tostring(st.wl[1]) .. "）")
T.tap(Enum.KeyCode.Two)
R.run(0.2)
check(st.wi == 2 and bright(rows[2]) < bright(rows[1]), "按 2：第二行亮了（" .. tostring(st.wl[2]) .. "）")
local aamPx = ring.Size.X.Offset
check(aamPx > gunPx * 1.3, string.format("大圈跟着武器变（导引头离轴角）：%s %.0f 像素 → %s %.0f 像素", tostring(st.wl[1]), gunPx, tostring(st.wl[2]), aamPx))
local rt = find("RingText")
check(rt and T.visible(rt) and rt.Text:find("×", 1, true), "圈底下写着武器和剩几发：" .. tostring(rt and rt.Text))

print("③ P：光电吊舱")
local fov0 = cam.FieldOfView
T.tap(Enum.KeyCode.P)
R.run(0.6)
check(st.eo == true, "按 P 进了光电")
local okE = shown("EoView")
check(okE, "吊舱画面（取景框、十字）出来了")
check(not T.visible(ring), "平显的大圈收起来了")
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
check(st.zoom == 3 and cam.FieldOfView < 30, string.format("Z 变焦 3×（视场 %.0f°）", cam.FieldOfView))
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
T.tap(Enum.KeyCode.F)
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

T.summary()
