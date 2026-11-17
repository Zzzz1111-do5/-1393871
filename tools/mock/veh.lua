-- 载具测试（照 tools/test/ia_veh.luau，在没有 Lune 的机器上用模拟器跑）：
--   python3 tools/mock/run.py tools/mock/veh.lua def   守方：营地车场的生成点生成坦克、坐上去、开车、悬架、瞄准镜四种模式、开炮、烟幕弹、下车上车、被毁
--   python3 tools/mock/run.py tools/mock/veh.lua atk   攻方：登陆平台的生成点（站在气垫艇上）连艇一起开上岸；两栖车自己游上岸
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, Enum = T.R, T.V3, T.Enum
local check = T.check
local side = TEST_ARGS:match("atk") and "atk" or "def"

local G = T.boot()
G.fortsHold = true   -- 这里测的不是工事：工事不开火
G.navyNoAI = true   -- 也不要 AI 舰艇（同 tools/test/ia_veh.luau）
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 120)
check(G.worldReady, "地图生成好了（地形体素 " .. tostring(R.voxelsWritten) .. "）")
local me = T.join("P1", 5001, true)
local other = T.join("P2", 5002, false)
-- 有客户端的这个人放到要测的一方
local function setTeam(pl, team)
  local P = G.P[pl]
  P.team = team
  pl.Team = G.TEAM[team]
  pl.Neutral = false
  pl:SetAttribute("Side", team)
  G.pushOne(P)
end
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
-- 开局时会打乱分队：等分好了再把有客户端的这个人放到要测的一方
setTeam(me, side)
setTeam(other, side == "def" and "atk" or "def")
R.run(1)
local P, PO = G.P[me], G.P[other]
local C = T.C
check(C ~= nil and C.S ~= nil, "客户端收到了服务器状态")

if side == "def" then
  print("① 守方在营地出生，走到车场的坦克生成点按 E 生成，再走过去坐上")
  local tankId = G.Config.Vehicles.def.tank[3]
  check(C.S.vehModels and #C.S.vehModels > 0, "客户端拿到了能开的型号：" .. table.concat(C.S.vehModels or {}, ","))
  check(C.S.vehAvail and C.S.vehAvail.tank and C.S.vehAvail.tank.cap >= 1, "坦克名额 " .. tostring(C.S.vehAvail and C.S.vehAvail.tank and C.S.vehAvail.tank.cap))
  C.deploySel.spawn, C.deploySel.role = "camp", "engineer"
  T.leaveMenu()
  R.as("client", function() C.refreshDeploy() end)
  T.click("^" .. C.T("ui.deployBtn") .. "$")
  R.run(2)
  local tp = T.pad(tankId)
  check(tp ~= nil and tp.team == "def" and tp.summon == true and tp.kind == "veh", "营地车场的车位是召唤位（" .. #(tp and tp.vids or {}) .. " 型可选）")
  if tp then
    -- 用户：召唤点里自己选哪种车，不要固定——先按一次 E 看列表：本队全部地面车型都有卡片；取消
    local y = G.airSurface(tp.term.X, tp.term.Z)
    me.Character:PivotTo(T.CF(tp.term.X + 1.5, y + 3, tp.term.Z + 1.5))
    R.run(0.2)
    R.as("server", function() tp.prompt.Triggered:Fire(me) end)
    R.run(0.6)
    local n = 0
    for _, id in ipairs(tp.vids) do if T.findNamed("Pick_" .. id) then n = n + 1 end end
    check(n == #tp.vids and n >= 10, string.format("按 E 弹出了本队全部 %d 型地面载具的卡片（看得见 %d 张）", #tp.vids, n))
    local cancel = T.findNamed("Cancel")
    if cancel then T.press(cancel) end
    R.run(0.2)
    check(not T.findNamed("Pick_" .. tankId), "取消：列表关上了")
  end
  local e0 = tp and T.usePad(me, tp)
  check(e0 ~= nil and e0.driver == nil and e0.def.id == tankId, "点了 " .. tankId .. " 的卡片：生成了一辆空的 " .. tostring(e0 and e0.def.id))
  -- 夜视：出生后屏幕下方提示「按 N 开启夜视」；步兵按 N 打开（整个画面调色，没有望远镜那样的镜筒框），提示消失；坐进车里照样开着
  R.run(2)
  local hintGui = me.PlayerGui:FindFirstChild("NVHint")
  local hint = hintGui and hintGui:FindFirstChild("Hint")
  local lighting = R.services.Lighting
  local nvg = me:FindFirstChild("PlayerGui") and me.PlayerGui:FindFirstChild("NVG")
  -- 昼夜更替以后：白天出生不自动开夜视（天黑了出生才自动开）、白天也不提示；按 N 打开（全屏调色、没有镜筒框），再按关掉、再按又开
  check(C.nvgOn and not C.nvgOn() and lighting:FindFirstChild("NVGrade") == nil and not (hint and hint.Visible), "白天出生：夜视没自动开、没有「按 N」提示")
  T.tap(Enum.KeyCode.N)
  R.run(1)
  check(C.nvgOn() and lighting:FindFirstChild("NVGrade") ~= nil and not (nvg and nvg.Enabled), "按 N 开夜视：全屏调色、没有镜筒框")
  T.tap(Enum.KeyCode.N)
  R.run(1)
  check(C.nvgOn and not C.nvgOn() and lighting:FindFirstChild("NVGrade") == nil, "按 N 关掉")
  T.tap(Enum.KeyCode.N)
  R.run(1)
  check(C.nvgOn() and lighting:FindFirstChild("NVGrade") ~= nil, "再按 N 又开了")
  -- 用户：模型的实体和模型对不上——挡人改成客户端按看得见的零件（离人近的才开）
  local v0
  if C.views and e0 then for em, vv in pairs(C.views) do if em == e0.model then v0 = vv end end end
  local nSolid, nAll = 0, 0
  if v0 and v0.model then
    for _, p in ipairs(v0.model:GetDescendants()) do
      if p:IsA("BasePart") and p.Transparency < 0.9 then
        nAll = nAll + 1
        if p.CanCollide then nSolid = nSolid + 1 end
      end
    end
  end
  check(v0 and v0.solidOn == true and nSolid > nAll * 0.5, string.format("站在车旁边：车的模型零件是实心的（%d / %d 块）", nSolid, nAll))
  T.act("enterVeh", e0 and e0.id)
  R.run(1.5)
  check(v0 and v0.solidOn == false, "坐进自己开的车：这辆不再挡人（人在里面）")
  check(C.nvgOn and C.nvgOn() and lighting:FindFirstChild("NVGrade") ~= nil, "坐进车里夜视照样开着")
  local e = P.vehicle
  check(e ~= nil and e.alive and e.def.id == tankId, "坐进了 " .. tostring(e and e.def.id))
  check(e and e.root.CanCollide == false, "服务器的方盒不挡人（只管挨打）")
  check(P.alive and me.Character and me.Character.HumanoidRootPart.Anchored, "人锚定在车里")
  check(C.drive ~= nil and C.drive.id == (e and e.id), "客户端接管驾驶")
  local v
  if C.views and e then for em, vv in pairs(C.views) do if em == e.model then v = vv end end end
  check(v ~= nil and v.M ~= nil and #v.M.parts > 40, "客户端拼好了车的模型：" .. (v and v.M and #v.M.parts or 0) .. " 个零件、" .. (v and v.M and #v.M.wheels or 0) .. " 个负重轮")

  print("② 开车：按住 W 往前开，服务器跟着动")
  local p0 = e.root.CFrame.Position
  T.key(Enum.KeyCode.W, true)
  R.run(4)
  T.key(Enum.KeyCode.W, false)
  R.run(1)
  local p1 = e.root.CFrame.Position
  local moved = (V3(p1.X, 0, p1.Z) - V3(p0.X, 0, p0.Z)).Magnitude
  check(moved > 40, string.format("开出去 %.0f 格", moved))
  local gy = G.Map.ground(p1.X, p1.Z)
  check(math.abs((p1.Y - e.def.H / 2) - gy) < 3, string.format("贴着地（车底 %.1f，地面 %.1f）", p1.Y - e.def.H / 2, gy))
  local lo, hi = 0, 0
  if v then for _, w in ipairs(v.M.wheels) do lo, hi = math.min(lo, w.dy), math.max(hi, w.dy) end end
  check(hi - lo > 0.05, string.format("负重轮各自上下（%.2f ～ %.2f 格）", lo, hi))

  print("③ 瞄准镜（用户：Shift 开镜，镜里写着按 V 切换光电模式、按 M 释放烟雾弹）：默认夜视 → 热成像白热 → 黑热 → 昼光")
  T.tap(Enum.KeyCode.LeftShift)
  R.run(0.3)
  local cc = C.sightCC
  check(C.drive.sight and cc and cc.Enabled, "Shift 进瞄准镜，画面调色开了")
  local function shown(name)
    for _, d in ipairs(me.PlayerGui:GetDescendants()) do
      if d.Name == name and T.visible(d) then return d.Text end
    end
  end
  local hv, hm = shown("HintOptic"), shown("HintSmoke")
  check(hv and hv:find("V", 1, true) and hv:find(C.T("sight.nv"), 1, true), "镜里写着：" .. tostring(hv))
  check(hm and hm:find("M", 1, true) and hm:find(tostring(e.smoke or e.def.smoke.n * #e.def.smoke.banks), 1, true) ~= nil or (hm and hm:find("M", 1, true)), "镜里写着：" .. tostring(hm))
  check(C.nvgOn() and lighting:FindFirstChild("NVGrade") == nil, "看瞄准镜时夜视仪先让出画面（瞄准镜有自己的夜视 / 热成像）")
  local modes = {}
  for _ = 1, 3 do
    T.tap(Enum.KeyCode.V)
    R.run(0.6)
    modes[#modes + 1] = tostring(({ "day", "nv", "whot", "bhot" })[C.drive.mode])
  end
  check(modes[1] == "whot" and modes[2] == "bhot" and modes[3] == "day", "瞄准镜默认夜视档，V 依次切白热、黑热、昼光：" .. table.concat(modes, " → "))
  local hv2 = shown("HintOptic")
  check(hv2 and hv2:find(C.T("sight.day"), 1, true), "提示跟着换成现在的模式：" .. tostring(hv2))
  T.tap(Enum.KeyCode.LeftShift)
  R.run(0.3)
  check(not C.drive.sight and not cc.Enabled, "再按 Shift 退出瞄准镜，调色关了")
  check(shown("HintOptic") == nil, "退出瞄准镜提示也收起来")
  check(C.nvgOn() and lighting:FindFirstChild("NVGrade") ~= nil, "退出瞄准镜，夜视仪的画面又回来了")

  print("④ 开战后开炮、放烟幕弹")
  T.runUntil(function() return G.round.phase == "battle" end, 40)
  local w1 = e.def.weapons[1]
  local ammo0 = e.wst[w1].reserve + e.wst[w1].mag
  T.mouse(true)
  R.run(0.2)
  T.mouse(false)
  R.run(1)
  local ammo1 = e.wst[w1].reserve + e.wst[w1].mag
  check(ammo1 == ammo0 - 1, string.format("主炮打了一发（%d → %d）", ammo0, ammo1))
  T.tap(Enum.KeyCode.M)
  R.run(1.5)
  check(#G.smokes == e.def.smoke.n * #e.def.smoke.banks, "按 M 放烟幕弹：落地起了 " .. #G.smokes .. " 团烟")

  print("⑤ 下车、再上车")
  T.tap(Enum.KeyCode.F)
  R.run(1)
  check(P.vehicle == nil and not me.Character.HumanoidRootPart.Anchored, "下车了，能走")
  check(C.drive == nil, "客户端退出驾驶")
  T.act("enterVeh", e.id)
  R.run(1)
  check(P.vehicle == e and C.drive ~= nil, "按 E 又坐回去了")

  print("⑥ 被击毁：车组阵亡、名额冷却")
  local used0 = G.vehAvail("def").tank.u
  G.damageEnt(e, 1e6, { P = PO, team = PO.team, name = other.DisplayName })
  R.run(1)
  check(not e.alive and e.wreck, "车被打爆、变成残骸")
  check(not P.alive, "车组阵亡")
  check(G.vehAvail("def").tank.u == used0, "名额还占着（冷却中）")
else
  print("⑦ 攻方：登陆平台出生，水面上的生成点生成（站在气垫艇上），连艇一起开上岸；两栖车下水自己游上岸")
  T.runUntil(function() return G.round.phase == "battle" end, 40)
  -- 摆车（测试里瞬移：服务器、客户端两边一起挪）：base 是车底
  local function placeVeh(e, base)
    R.run(0.1)
    local root = base * T.CF(0, e.def.H / 2, 0)
    G.moveEnt(e, root)
    e.lastSync = os.clock()
    local st = C.drive
    if st then
      st.pos = base.Position
      local look = base.LookVector
      st.yaw = math.atan(-look.X, -look.Z)
      st.speed = 0
      st.root = root
    end
  end
  T.act("deploy", "rifle", "barge")
  R.run(2)
  check(P.alive and P.vehicle == nil, "步兵在登陆平台出生")
  local ap = T.pad("zbd05")
  local ea = ap and T.usePad(me, ap)
  check(ea ~= nil and ea.lcac ~= nil, "两栖车 ZBD-05 站在气垫艇上生成")
  if ea then
    T.act("enterVeh", ea.id)
    R.run(1)
    check(P.vehicle == ea and C.drive ~= nil, "走过去坐上了")
    local b = G.Map.landingOf("white")
    local p0 = V3(b.cx, G.LCAC.deck, b.z + b.dir * 260)
    placeVeh(ea, R.CFrame.lookAt(p0, p0 + V3(0, 0, -b.dir)))
    T.key(Enum.KeyCode.W, true)
    local landed = T.runUntil(function() return ea.lcac == nil end, 30)
    T.key(Enum.KeyCode.W, false)
    check(landed, "连艇一起开上岸，气垫艇把车放下了")
    -- 再摆回海里 140 格（没有艇）：自己游
    local p1 = V3(b.cx, -ea.def.hullH * 0.55, b.z + b.dir * 140)
    placeVeh(ea, R.CFrame.lookAt(p1, p1 + V3(0, 0, -b.dir)))
    T.key(Enum.KeyCode.W, true)
    local track = {}
    local ashore = T.runUntil(function()
      local q = ea.root.CFrame.Position
      if #track < 1300 then track[#track + 1] = q end
      return G.Map.height(q.X, q.Z) > 1
    end, 40)
    T.key(Enum.KeyCode.W, false)
    local q = ea.root.CFrame.Position
    check(ashore, string.format("自己游上了岸（停在 x %.0f z %.0f，地面 %.1f）", q.X, q.Z, G.Map.height(q.X, q.Z)))
    local jump = 0
    for i = 2, #track do jump = math.max(jump, math.abs(track[i].Y - track[i - 1].Y)) end
    check(jump < 0.8, string.format("上岸一路车身每帧高低最多变 %.2f 格", jump))
  end
end
T.summary()
