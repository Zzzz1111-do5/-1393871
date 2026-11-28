-- 开坦克时屏幕上画了什么（模拟器）：python3 tools/mock/run.py tools/mock/hudshot.lua out=<文件.json> [kind=tank|ifv|ship|inf] [hp=0.5] [erax=1,2,5] [fire=1] [noedit=1]
--   kind=ads：步兵开镜（第一人称，M4 + ACOG；[gun=sniper] 狙击枪、[build=改枪码] 换瞄具）——看 Scope.lua 的镜片那一层（用户 11-21：瞄准镜照使命召唤做）；
--     tools/weapons/gunrender.mjs ads=… 拍同一个开镜画面的 3D 背景，hud_render.py 叠上去
--   kind=jet / heli：开飞机（空中出发，前方一架敌机、地上一辆敌车）[id=j20] [alt=700]——看开飞机的界面（AirHud，用户 11-19 照 MWT 截图改）
--     [lock=0.5]：锁定画到一半（菱形顺时针画了一半）；[outcone=1]：锁上以后把敌机挪到导弹离轴角外（菱形变黄）；[ir=1]：开热成像；
--     [roll=25]：带坡度；[clean=1]：截图前收起新手卡、作战简报；[bs=1]：开轰炸瞄准镜（F7）；[poi=1.5]：落点前方 1.5 秒处标目标点
--   [states=1]：弹药栏的打空 / 冷却（<out>_s1.json）、主炮损坏（<out>）各截一张，平时的截在 <out>_base.json；[vp=1920x1080] 按这个屏幕大小排版
--   用户：开坦克要是 MWT 那套驾驶界面（截图），不要叠着旧界面。坐进一辆车、前方放一辆敌车开一会，
--   把所有显示着的界面元素按 Roblox 的排版算出屏幕上的方框（1280×720，UDim2 + AnchorPoint + UIListLayout + UIScale 的近似），
--   写成 JSON；tools/mock/hud_render.py 画成图看。也按 ScreenGui 列出各有多少个显示着的元素（找没关掉的旧界面）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
-- vp=1920x1080：按这个屏幕大小排版、截图（默认 1280 × 720；hud_render.py 加 size=1920x1080）
local vpW, vpH = TEST_ARGS:match("vp=(%d+)x(%d+)")
if vpW then R.vpW, R.vpH = tonumber(vpW), tonumber(vpH) end
if TEST_ARGS:find("noedit=1", 1, true) then R.noEditable = true end   -- [noedit=1]：当成用不了 EditableImage（看界面退回方块拼的样子）
local out = TEST_ARGS:match("out=(%S+)")
local kind = TEST_ARGS:match("kind=(%a+)") or "tank"
local mySide = TEST_ARGS:match("side=(%a+)") or "def"   -- atk：开 96 式那一边的车

local G = T.boot()
T.runUntil(function() return G.worldReady end, 120)
local me = T.join("P1", 7501, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = mySide
me.Team = G.TEAM[mySide]
me.Neutral = false
me:SetAttribute("Side", mySide)
G.pushOne(P)
R.run(1)
local C = T.C
if kind ~= "ads" then   -- 开镜那种：先存好改枪方案再出击（下面）
  T.act("deploy", "rifle", G.Map.LANDONLY and "base" or (mySide == "def" and "camp" or "fleet"))   -- 沙海（11-24 起只剩这张）只能在自己主基地出生
  R.run(3)
  check(P.alive, "守方在营地出生")
end
if not TEST_ARGS:find("prep", 1, true) then T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10) end

if kind == "jet" or kind == "heli" then
  local foeSide = mySide == "def" and "atk" or "def"
  local id = TEST_ARGS:match("id=(%w+)") or G.Config.Vehicles[mySide][kind][1]
  local p = me.Character.HumanoidRootPart.Position
  local alt = tonumber(TEST_ARGS:match("alt=(%d+)") or "") or ((kind == "jet") and 700 or 160)
  local x, z = p.X, p.Z
  local cf = CF(x, math.max(G.Map.ground(x, z), 0) + alt, z)   -- 朝 −Z
  local fe = G.spawnAircraft(foeSide, G.Config.Vehicles[foeSide].jet[1], cf * CF(90, 60, -1000), nil, nil)
  local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))
  local ft = G.Config.Vehicles[foeSide].tank[1]
  pcall(function() G.newVehicle(foeSide, ft, G.vehBaseAt(VD.get(ft), x - 160, z - 1500, V3(0, 0, 1))) end)
  local e = G.spawnAircraft(mySide, id, cf, nil, P)
  me.Character:PivotTo(cf * CF(4, 0, 0))
  T.act("enterVeh", e.id)
  R.run(0.2)
  local st = C.fly
  if st then   -- 刚放的飞机算停在地上（零速度、起落架放着）：改成巡航（八成军推速度、收起落架；直升机前飞）
    st.ground = false
    if kind == "jet" then
      st.spd = st.d.vMil * 0.8
      st.vel = st.cf.LookVector * st.spd
      st.vdir = st.cf.LookVector   -- 航迹也摆平（悬在半空的飞机已经往下掉了；WASD 飞以后松杆不会自己拉平）
      st.thr, st.gearWant, st.gear = 85, 0, 0
    else
      st.rpm = 100
      st.hv = st.cf.LookVector * st.d.vMax * 0.5
      st.vel = st.hv
    end
  end
  R.run(2.5)
  check(C.fly ~= nil and C.fly.pilot, "坐进 " .. id .. "（离地 " .. alt .. " 格）")
  check(fe ~= nil, "前方放了一架敌机")
  local hpK = tonumber(TEST_ARGS:match("hp=([%d%.]+)") or "")
  if hpK and e and e.alive then
    G.damageEnt(e, e.maxHp * (1 - hpK), { team = foeSide, name = "test" })
    R.run(0.6)
  end
  local AD = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs"))
  local st2 = C.fly
  if fe and fe.root and st2 then   -- 没人开的敌机停在原地、自己这架掉了一些高度：截图前把它重新摆到正前方 700 格、稍偏右上
    fe.root.CFrame = st2.cf * CF(70, 25, -700)
    R.run(0.3)
  end
  local w = st2 and AD.W[st2.wl[st2.wi]]
  if st2 and fe and fe.root and w and w.seeker == "radar" and not st2.lock and C.radarHas then   -- 雷达弹照战雷手动锁（11-27）：屏上有了它，R 选中、Alt+F 锁定
    T.runUntil(function()
      fe.root.CFrame = st2.cf * CF(70, 25, -700)
      if C.radarHas(st2, fe.model) then
        T.tap(Enum.KeyCode.R)
        T.key(Enum.KeyCode.LeftAlt, true)
        T.tap(Enum.KeyCode.F)
        T.key(Enum.KeyCode.LeftAlt, false)
      end
      return st2.lock ~= nil
    end, 3)
  end
  check(st2 ~= nil and st2.lock ~= nil, "锁着前方的敌机：" .. tostring(st2 and st2.lock and st2.lock.em and st2.lock.em:GetAttribute("Model")))
  local function where(tag)
    if not (st2 and st2.lock) then return end
    local rel = st2.cf:PointToObjectSpace(st2.lock.pos)
    local ang = math.deg(math.acos(math.max(-1, math.min(1, st2.cf.LookVector:Dot((st2.lock.pos - st2.cf.Position).Unit)))))
    print(string.format("  %s：锁定目标在机身坐标 右 %.0f 上 %.0f 前 %.0f（偏 %.0f°），离开离轴角 %s", tag, rel.X, rel.Y, -rel.Z, ang, tostring(st2.lock.out)))
  end
  where("截图前")
  if fe and fe.model then
    print(string.format("  敌机实体：Cat=%s Team=%s Hp=%s/%s Kind=%s Root=%s Wreck=%s", tostring(fe.model:GetAttribute("Cat")), tostring(fe.model:GetAttribute("Team")),
      tostring(fe.model:GetAttribute("Hp")), tostring(fe.model:GetAttribute("MaxHp")), tostring(fe.model:GetAttribute("Kind")), tostring(fe.model:FindFirstChild("Root") ~= nil), tostring(fe.model:GetAttribute("Wreck"))))
  end
  if TEST_ARGS:find("outcone=1", 1, true) and fe and st2 and w then   -- 敌机挪到离轴角外（还在跟踪的范围里）
    local cone = w.cone or 30
    local a = math.rad(math.min(cone * 1.6, 80))
    local p0 = st2.cf.Position
    local dir = (st2.cf.LookVector * math.cos(a) + st2.cf.RightVector * math.sin(a))
    fe.root.CFrame = CF(p0 + dir * 900)
    R.run(0.25)
    where("挪开以后")
    check(st2.lock ~= nil and st2.lock.out == true, "敌机出了离轴角：锁还在、算在发射角度外")
  end
  local wiN = tonumber(TEST_ARGS:match("wi=(%d+)") or "")   -- wi=2：选第二种弹（比如歼-20 的霹雳-10 红外弹：不用雷达也能锁）
  if wiN and st2 then
    st2.wi, st2.lock, st2.lockT = wiN, nil, 0
    R.run(0.5)
  end
  local lockK = tonumber(TEST_ARGS:match("lock=([%d%.]+)") or "")
  if lockK and st2 and st2.lock and w then
    st2.lockT = lockK * (w.lockTime or 1)
    R.run(1 / 60)
  end
  -- bs=1：开战雷式轰炸瞄准镜（F7，要挂炸弹的飞机，比如 side=atk id=h6k）；poi=<秒>：在落点前方这么多秒的地方标目标点（CCRP 的方框和箭头）
  if TEST_ARGS:find("bs=1", 1, true) and st2 and C.flyBombsight then
    C.flyBombsight(true)
    R.run(0.5)
    check(st2.bsight == true, "开了轰炸瞄准镜")
  end
  local poiS = tonumber(TEST_ARGS:match("poi=([%d%.]+)") or "")
  if poiS and st2 then
    local hv = R.Vector3.new(st2.vel.X, 0, st2.vel.Z)
    local imp = C.bombImpact((st2.cf * CF(0, -(st2.d.H or 4) * 0.35 - 1.5, 0)).Position, st2.vel - st2.cf.UpVector * 4)
    local tp = imp + hv.Unit * (hv.Magnitude * poiS) + R.Vector3.new(-hv.Unit.Z, 0, hv.Unit.X) * 25
    st2.poi = R.Vector3.new(tp.X, math.max(G.Map.ground(tp.X, tp.Z), 0), tp.Z)
    R.run(0.2)
  end
  local roll = tonumber(TEST_ARGS:match("roll=(%-?[%d%.]+)") or "")
  if roll and st2 then   -- 带一点坡度（看机头全息准心跟着机身滚转、有透视）
    st2.cf = st2.cf * R.CFrame.Angles(0, 0, math.rad(-roll))
    R.run(1 / 60)
  end
  if TEST_ARGS:find("ir=1", 1, true) and C.airThermal then
    C.airThermal(true)
    R.run(0.2)
  end
  -- rwr=1：敌机雷达锁着我、一发导弹打过来（看战雷式的雷达告警圆盘：型号、虚线、MSL）
  if TEST_ARGS:find("rwr=1", 1, true) and fe and C.wtRwrEvent then
    R.as("client", function()
      C.wtRwrEvent("rwrLock", { by = fe.id })
      C.wtRwrEvent("rwr", { id = 1, w = "aim120" })
    end)
    R.run(0.1)
  end
  -- dl=1：自己打出去一发霹雳-15、导引头还没开机（看雷达屏上的数据链：弹的点、到目标的虚线、截获圈）；只是画面，不经服务器
  if TEST_ARGS:find("dl=1", 1, true) and st2 and C.flyingShots then
    C.flyingShots[991001] = { wm = { parts = {}, offs = {} }, cfs = {}, aw = AD.W.pl15, w = "pl15", burn = 5, half = 2, t = 0, kind = "missile", trailT = 0, my = true,
      p = st2.cf.Position + st2.cf.LookVector * 220 + st2.cf.RightVector * 20, v = st2.cf.LookVector * 820, tg = fe and fe.id or nil }
    R.run(1 / 30)
  end
end

if kind == "ads" then
  -- 开镜：等真 M4、瞄具生成好，按住右键一秒多（举好镜子），再截界面
  local GMx = R.require(R.services.ReplicatedStorage:FindFirstChild("GunMods"))
  local bs = TEST_ARGS:match("build=(%S+)")
  if bs then R.as("server", function() G.ACT.gunBuild(P, "m4", GMx.decode(bs)) end) end   -- 照改枪界面「完成」那样存到服务器
  local gun = TEST_ARGS:match("gun=(%a+)") or "m4"
  T.actAs(me, "deploy", { primary = gun, gadget = "medkit", throw = "grenade" }, G.Map.LANDONLY and "base" or (mySide == "def" and "camp" or "fleet"))
  R.run(2.5)
  check(P.alive, "出生了（" .. gun .. (bs and ("，" .. bs) or "") .. "）")
  T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
  T.runUntil(function()
    local v = C.fps
    return v ~= nil and v.optic ~= nil and v.items[1] ~= nil and v.items[1][1].ClassName == "MeshPart"
  end, 40)
  R.run(1)
  T.mouse(true, nil, nil, Enum.UserInputType.MouseButton2)
  R.run(tonumber(TEST_ARGS:match("hold=([%d%.]+)") or "") or 1.4)
  local camA = R.workspace.CurrentCamera
  print(string.format("开镜：视角 %.2f°，镜片那一层 %s", camA.FieldOfView, tostring(me.PlayerGui:FindFirstChild("Scope") and me.PlayerGui.Scope.Enabled)))
  local lens = me.PlayerGui:FindFirstChild("Scope") and me.PlayerGui.Scope:FindFirstChild("ScopeLens", true)
  if lens then print(string.format("镜片：圆心 (%.1f, %.1f)，直径 %d", lens.Position.X.Offset, lens.Position.Y.Offset, lens.Size.X.Offset)) end
  for _, d in ipairs(me.PlayerGui:GetDescendants()) do   -- 只看镜子：别的界面（弹药、小地图、提示）藏起来
    if d.ClassName == "ScreenGui" and d.Name ~= "Scope" then d.Enabled = false end
  end
elseif kind == "gunsmith" then
  -- 改枪界面：打开、点「瞄具」、鼠标停在全息瞄具的卡片上（预览）；镜头参数写进 <out>.cam.json（tools/weapons/gunrender.mjs 照它拍枪，贴进视口）
  R.as("client", function() C.openGunsmith(TEST_ARGS:match("gun=(%w+)") or "m4") end)
  for _ = 1, 40 do R.run(0.25) end
  local slot = TEST_ARGS:match("slot=(%w+)") or "optic"
  local hover = TEST_ARGS:match("hover=([%w_]+)") or "opt_holo"
  local gui = me.PlayerGui:FindFirstChild("Gunsmith")
  for _, d in ipairs(gui:GetDescendants()) do
    if d.ClassName == "TextLabel" and d.Text == C.T("gm.slot." .. slot) and d.Parent and d.Parent.ClassName == "TextButton" then T.press(d.Parent) end
  end
  for _ = 1, 20 do R.run(0.1) end
  for _, d in ipairs(gui:GetDescendants()) do
    if d.ClassName == "TextLabel" and d.Text == C.T("gm.item." .. hover) and d.Parent and d.Parent.ClassName == "TextButton" then
      R.as("client", function() d.Parent.MouseEnter:Fire() end)
    end
  end
  for _ = 1, 30 do R.run(1 / 30) end
  if out then
    local S, vcam = C.gunsmithDebug()
    local b = {}
    for k, v in pairs(S.cur) do b[k] = v end
    if S.hover and S.slot then b[S.slot] = S.hover end
    local c = { vcam.CFrame:GetComponents() }
    local f = io.open(out .. ".cam.json", "w")
    local parts = {}
    for k, v in pairs(b) do parts[#parts + 1] = string.format('"%s":"%s"', k, v) end
    f:write(string.format('{"gun":"%s","fov":%.3f,"cf":[%s],"build":{%s}}', S.id, vcam.FieldOfView, table.concat((function()
      local o = {}
      for i, v in ipairs(c) do o[i] = string.format("%.5f", v) end
      return o
    end)(), ","), table.concat(parts, ",")))
    f:close()
  end
elseif kind ~= "inf" and kind ~= "jet" and kind ~= "heli" and kind ~= "ads" then
  local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))
  local list = G.Config.Vehicles[mySide][kind] or G.Config.Vehicles[mySide].tank
  local foeSide = mySide == "def" and "atk" or "def"
  local tid = list[1]
  local d = VD.get(tid)
  local hrp = me.Character.HumanoidRootPart
  local p = hrp.Position
  local x, z = p.X + 30, p.Z + 30
  if mySide == "atk" then   -- 攻方在舰队出生：找一块岸上的平地
    local pt = G.points and (G.points.A or G.points.C)
    local px, pz = pt and pt.pos and pt.pos.X or 0, pt and pt.pos and pt.pos.Z or 0
    for r = 120, 900, 40 do
      local found = false
      for a = 0, 330, 30 do
        local tx, tz = px + math.cos(math.rad(a)) * r, pz + math.sin(math.rad(a)) * r
        if G.Map.height(tx, tz) > 4 and G.Map.slope(tx, tz) < 0.12 and G.Map.height(tx, tz - 160) > 3 then x, z, found = tx, tz, true break end
      end
      if found then break end
    end
  end
  local e = G.newVehicle(mySide, tid, G.vehBaseAt(d, x, z, V3(0, 0, -1)))
  local ft = G.Config.Vehicles[foeSide].tank[1]
  G.newVehicle(foeSide, ft, G.vehBaseAt(VD.get(ft), x + 25, z - 160, V3(0, 0, 1)))
  R.run(0.5)
  me.Character:PivotTo(CF(x + 6, G.Map.ground(x + 6, z) + 3.5, z))
  R.run(0.3)
  T.act("enterVeh", e.id)
  R.run(1)
  check(C.drive ~= nil, "坐进 " .. tid)
  if C.drive then C.drive.camYaw = C.drive.yaw + math.pi end   -- 镜头朝车头看（模拟器里镜头偏航和车头差半圈；炮塔不用转过来）
  R.run(1)
  T.key(Enum.KeyCode.W, true)
  R.run(1.5)
  T.key(Enum.KeyCode.W, false)
  R.run(2.5)
  -- hp=0.5：挨一下打到这个血量（看「被发现!」、车的图标按车况变黄 / 变红）
  local hpK = tonumber(TEST_ARGS:match("hp=([%d%.]+)") or "")
  if hpK and e and e.alive then
    G.damageEnt(e, e.maxHp * (1 - hpK), { team = foeSide, name = "test" })
    R.run(0.6)
  end
  -- sight=1：按 Shift 开炮长瞄准镜（用户 11-21 截图：开镜右边一块黑、整屏暗青色）；optic=day|nv|whot|bhot 按 V 换到这一档；night=1 先调到夜里
  if TEST_ARGS:find("night=1", 1, true) then R.services.Lighting.ClockTime = 1 R.run(1) end
  if TEST_ARGS:find("sight=1", 1, true) then
    T.key(Enum.KeyCode.LeftShift, true)
    T.key(Enum.KeyCode.LeftShift, false)
    R.run(1.2)
    check(C.drive and C.drive.sight == true, "开了瞄准镜")
    local want = TEST_ARGS:match("optic=(%a+)")
    local MODES = { day = 1, nv = 2, whot = 3, bhot = 4 }
    if want and MODES[want] and C.drive then
      for _ = 1, 4 do
        if C.drive.mode == MODES[want] then break end
        T.tap(Enum.KeyCode.V)
        R.run(0.2)
      end
      check(C.drive.mode == MODES[want], "瞄准镜换到 " .. want .. "（现在第 " .. tostring(C.drive.mode) .. " 档）")
    end
    R.run(1)
  end
  -- erax=1,2,5：这几块爆反算炸掉了（看视角图上爆反的缺口）
  local ex = TEST_ARGS:match("erax=([%d,]+)")
  if ex and e and e.model then
    e.model:SetAttribute("EraX", ex)
    R.run(0.3)
  end
  -- fire=1：开一炮，截图时正在装填（看弹药栏底边的装填进度、名牌右边的「装填 x.x s」）；[after=2] 开炮后过几秒截
  if TEST_ARGS:find("fire=1", 1, true) and C.drive and C.driveTryFire then
    local stF = C.drive
    local f0 = stF.fireT
    for _ = 1, 300 do
      R.as("client", function() C.driveTryFire() end)
      if stF.fireT ~= f0 then break end
      R.run(1 / 30)
    end
    check(stF.fireT ~= f0, "开了一炮（截图时在装填）")
    R.run(tonumber(TEST_ARGS:match("after=([%d%.]+)") or "") or 2)
  end
  -- states=1：弹药栏的几种状态（11-27 美术审查：打空、损坏、冷却没截过图）——先截平时（<out>_base.json），
  --   再把第二种弹打空、叫一次火炮（冷却）截 <out>_s1.json，最后把炮闩打坏（主炮损坏：WtGun = false）截 <out>
  if TEST_ARGS:find("states=1", 1, true) and e and e.alive and out then
    local dump = dofile(MOCK_DIR .. "/uidump.lua")
    R.run(0.5)
    dump(T, me, (out:gsub("%.json$", "") .. "_base.json"), true)
    local BALx = R.require(R.services.ReplicatedStorage:FindFirstChild("Ballistics"))
    local wid = d.weapons and d.weapons[1]
    local list = wid and BALx.GUN[wid]
    local L = list and e.amL and e.amL[wid]
    if L and list[2] then
      L[list[2]] = 0
      G.wtAmmoRefill(e, wid, 0)   -- 补 0 发：只为了把 AmL 推给客户端
    end
    local aim = e.model and e.model:FindFirstChild("Root") and (e.model.Root.CFrame * CF(0, 0, -400)).Position
    if aim and G.ACT.wtArty then G.ACT.wtArty(P, aim) end
    R.run(1)
    check(L ~= nil and list[2] ~= nil and L[list[2]] == 0, "第二种弹打空了（" .. tostring(list and list[2]) .. "）")
    check(me:GetAttribute("WtArtyCd") ~= nil, "叫了一次火炮：冷却中")
    dump(T, me, (out:gsub("%.json$", "") .. "_s1.json"), true)
    local br = e.wt and e.wt.byK and e.wt.byK.breech
    if br then
      br.hp = 0
      G.wtPush(e)
    end
    R.run(1)
    check(e.model:GetAttribute("WtGun") == false, "炮闩打坏了：主炮损坏")
  end
end

-- clean=1：截图前收起新手三步卡、开局的作战简报（只为了截图好看）
if TEST_ARGS:find("clean=1", 1, true) then
  for _, d in ipairs(me.PlayerGui:GetDescendants()) do
    if d.Name == "CoachCard" or d.Name == "OperationBrief" then d.Visible = false end
  end
end
-- 排版：算每个显示着的界面元素在屏幕上的方框
-- 排版、写 JSON：tools/mock/uidump.lua（uishots.lua 也用）
dofile(MOCK_DIR .. "/uidump.lua")(T, me, out)
T.summary()
