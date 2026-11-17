-- 无人机战术平板测试（模拟器）：python3 tools/mock/run.py tools/mock/uav.lua [atk|def] [v]
--   终端前放出无人机 → 人原地端起平板（不藏、不挪进机身，胳膊抬起来、胸前一块平板）→ 画面是平板（外壳、开机、遥测、前视光电、变焦、切镜头）→
--   起飞 → F 收起平板：无人机自动盘旋、人能走了 → T 重新连接 → 操作员挨炸：平板红闪、人照样掉血（G.inVeh 不把他算在载具里）→
--   无人机被击落：操作员不死，只断了链路
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, Enum = T.R, T.V3, T.Enum
local check = T.check
local side = TEST_ARGS:match("def") and "def" or "atk"

local G = T.boot()
G.fortsHold = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 120)
local me = T.join("P1", 5101, true)
local other = T.join("P2", 5102, false)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local function setTeam(pl, team)
  local P = G.P[pl]
  P.team = team
  pl.Team = G.TEAM[team]
  pl.Neutral = false
  pl:SetAttribute("Side", team)
  G.pushOne(P)
end
setTeam(me, side)
setTeam(other, side == "def" and "atk" or "def")
R.run(1)
local P = G.P[me]
local C = T.C

print("① 终端前放出无人机：人原地端起平板，不藏、不挪进机身")
T.act("deploy", "rifle", (side == "atk") and "af2" or "point.D")
R.run(2)
check(P.alive and P.vehicle == nil, "步兵出生了")
-- 模拟器的角色没有胳膊：补一副 R15 的上身和胳膊（肩、肘关节），看平板姿势改没改关节
local char = me.Character
local hrp = char:FindFirstChild("HumanoidRootPart")
do
  local function part(name, size, cf)
    local p = R.Instance.new("Part")
    p.Name = name
    p.Size = size
    p.CFrame = cf
    p.Parent = char
    return p
  end
  local base = hrp.CFrame
  local ut = part("UpperTorso", V3(2, 1.6, 1), base * T.CF(0, 0.4, 0))
  local function joint(name, p0, p1, c0)
    local j = R.Instance.new("Motor6D")
    j.Name = name
    j.Part0, j.Part1 = p0, p1
    j.C0 = c0
    j.Parent = p1
    return j
  end
  joint("Waist", hrp, ut, T.CF(0, 0.4, 0))
  for _, sx in ipairs({ 1, -1 }) do
    local n = (sx > 0) and "Right" or "Left"
    local ua = part(n .. "UpperArm", V3(1, 1.17, 1), base)
    local la = part(n .. "LowerArm", V3(1, 1.05, 1), base)
    joint(n .. "Shoulder", ut, ua, T.CF(sx * 1, 0.56, 0))
    joint(n .. "Elbow", ua, la, T.CF(0, -0.39, 0))
  end
end
local id = (side == "atk") and "gj11" or "mq9"
local pad = T.pad(id)
check(pad ~= nil and pad.kind == "air", "有 " .. id .. " 的生成点")
local tr = char:FindFirstChild("RightUpperArm")
local sh = tr and tr:FindFirstChild("RightShoulder")
local c00 = sh and sh.C0
local e
if pad then
  T.usePad(me, pad)
  local go = T.findButton("^" .. C.T("pad.spawn") .. "$")
  if go then T.press(go) end
  R.run(1.5)
  e = P.vehicle
end
check(e ~= nil and e.air and e.def.drone, "接管了无人机 " .. tostring(e and e.def.id) .. "（不用走到跑道上）")
local stand = hrp.Position
if e then
  check(P.remote == e and G.inVeh(P) == false, "遥控的人不算在载具里（G.inVeh = " .. tostring(G.inVeh(P)) .. "）")
  local head = char:FindFirstChild("Head")
  check(head and head.Transparency == 0, "人没藏起来")
  check((hrp.Position - e.root.CFrame.Position).Magnitude > 20, string.format("人还站在终端前（离无人机 %.0f 格）", (hrp.Position - e.root.CFrame.Position).Magnitude))
  check(hrp.Anchored == true, "站着不动（端着平板）")
  local tab = char:FindFirstChild("UavTablet")
  local n = 0
  if tab then for _ in ipairs(tab:GetChildren()) do n = n + 1 end end
  check(char:GetAttribute("Tablet") == true and n >= 8, "胸前一块平板（" .. n .. " 块零件）")
  local scr = tab and tab:FindFirstChild("Screen")
  local ut = char:FindFirstChild("UpperTorso")
  if scr and ut then
    local l = ut.CFrame:PointToObjectSpace(scr.Position)
    check(l.Z < -0.6 and l.Z > -2 and math.abs(l.X) < 0.2, string.format("平板在胸前（上身坐标 %.2f, %.2f, %.2f）", l.X, l.Y, l.Z))
    local nrm = scr.CFrame.LookVector * -1   -- 屏幕是 +Z 面
    local toFace = (ut.CFrame:PointToWorldSpace(V3(0, 1.6, -0.3)) - scr.Position).Unit   -- 脸（模拟器的 PivotTo 只挪主零件，头留在原地：按上身算）
    check(nrm:Dot(toFace) > 0.3, string.format("屏幕朝着脸（%.2f）", nrm:Dot(toFace)))
  end
  check(sh and sh.C0 ~= c00, "肩关节抬起来了")
end

print("② 自己的画面是平板：外壳从下往上抬、开机「建立数据链」，再出前视光电的画面")
local st = C.fly
local tg = me.PlayerGui:FindFirstChild("UavTablet")
check(st ~= nil and st.uav == true and st.dcam == "nose", "客户端进了平板模式（前视光电）")
check(tg ~= nil and tg.Enabled, "平板界面开着")
R.run(2)
local function seen(pat) return #T.texts(pat) > 0 end
check(seen(C.T("uav.linkName")) and seen(C.T("uav.rec")), "屏幕上有数据链、录像")
check(seen("%d%d%d°"), "航向带下面写着航向")
check(not seen(C.T("uav.link")), "开机画面过去了")
local cam = R.services.Workspace.CurrentCamera
if st and e then
  local d = (cam.CFrame.Position - st.cf.Position).Magnitude
  check(d < e.def.L, string.format("镜头在机头（离机身中心 %.1f 格）", d))
  T.tap(Enum.KeyCode.Z)
  R.run(0.6)
  check(st.zoom == 3 and cam.FieldOfView < 30, string.format("Z 变焦到 3×（视场 %.0f°）", cam.FieldOfView))
  T.tap(Enum.KeyCode.Z)
  T.tap(Enum.KeyCode.Z)
  T.mouse(true, 640, 360, Enum.UserInputType.MouseButton2)
  T.mouse(false, 640, 360, Enum.UserInputType.MouseButton2)
  R.run(0.5)
  check(st.dcam == "chase", "右键换外部视角")
  check((cam.CFrame.Position - st.cf.Position).Magnitude > e.def.L * 0.8, "外部视角镜头在机身后面")
  T.tap(Enum.KeyCode.V)
  R.run(0.2)
  check(st.dcam == "nose", "V 换回前视")
  local help = C.T("air.helpUav")
  check(seen(help:sub(1, 12)), "最下面一行是平板的操作说明")
end

print("③ 起飞，F 收起平板：无人机自动盘旋，人能走了")
if st and e then
  T.key(Enum.KeyCode.W, true)
  T.key(Enum.KeyCode.Up, true)
  local up = T.runUntil(function() return not st.ground end, 50)
  T.key(Enum.KeyCode.Up, false)
  check(up, "滑跑起飞")
  R.run(10)
  T.key(Enum.KeyCode.W, false)
  local p = e.root.CFrame.Position
  check(p.Y > G.airSurface(p.X, p.Z) + 25, string.format("飞起来了（离地 %.0f 格）", p.Y - G.airSurface(p.X, p.Z)))
  T.tap(Enum.KeyCode.F)
  R.run(1)
  check(P.vehicle == nil and P.remote == nil, "收起了平板")
  check(char:GetAttribute("Tablet") == false and char:FindFirstChild("UavTablet") == nil, "平板零件收掉了")
  check(sh and sh.C0 == c00, "胳膊放下了（关节还原）")
  check(hrp.Anchored == false, "人能走了")
  check((hrp.Position - stand).Magnitude < 3, "人还在原地（没被挪到飞机旁边、没跳伞）")
  check(e.loit ~= nil and e.model:GetAttribute("Loiter") == true, "无人机断了链路：自动盘旋")
  local y0 = e.root.CFrame.Position.Y
  local p0 = e.root.CFrame.Position
  R.run(4)
  local p1 = e.root.CFrame.Position
  -- 低空断链的会慢慢爬到离地 120 格以上（安全高度）：只查没往下掉
  check(e.alive and p1.Y > y0 - 15 and (p1 - p0).Magnitude > 40, string.format("盘旋着没掉下来（高度差 %+.0f、飞了 %.0f 格）", p1.Y - y0, (p1 - p0).Magnitude))
  R.run(0.6)
  local hb = me.PlayerGui:FindFirstChild("UavLink")
  local btn = hb and hb:FindFirstChildOfClass("TextButton")
  local bt = btn and btn.Text or ""
  check(btn and T.visible(btn) and bt:find("T", 1, true) and bt:find(C.T("veh." .. e.def.id), 1, true) ~= nil, "提示重新连接：" .. bt)
  check(tg.Enabled == false, "平板界面收起了")
  T.tap(Enum.KeyCode.T)
  R.run(1.2)
  check(P.vehicle == e and P.remote == e and C.fly and C.fly.uav, "按 T 重新连上了")
  check(e.loit == nil and e.model:GetAttribute("Loiter") == false, "盘旋结束、交回操作员")
end

print("④ 操作员挨炸：平板屏幕红闪，人照样掉血；无人机被击落：操作员不死，只断了链路")
T.runUntil(function() return G.round.phase == "battle" end, 45)   -- 开战以后才掉血
if e and P.vehicle == e then
  local hum = char:FindFirstChildOfClass("Humanoid")
  local h0 = hum.Health
  G.explode(hrp.Position + V3(3, 0, 0), { splash = 10, dmg = 30 }, nil)
  R.run(0.4)
  check(hum.Health < h0, string.format("挨炸掉血（%.0f → %.0f）", h0, hum.Health))
  check(seen(C.T("uav.hit")), "平板上「操作员遭到攻击」")
  G.damageEnt(e, 1e6, nil)
  R.run(1)
  check(P.alive and hum.Health > 0, "操作员没死")
  check(P.vehicle == nil and P.remote == nil and C.fly == nil, "断了链路、收起平板")
  check(seen(C.T("ui.uavLost")), "提示无人机被击落")
  check(hrp.Anchored == false and char:FindFirstChild("UavTablet") == nil, "人能走了、平板收掉")
end

T.summary()
