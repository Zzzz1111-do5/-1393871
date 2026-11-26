-- 火控测距落在视线里第一个实物上、炮弹飞到落地（模拟器）：python3 tools/mock/run.py tools/mock/fcsrange.lua
--   用户 11-26：「然后目前坦克瞄准一个坦克 火控计算机会越过那个坦克瞄准后面的 而且炮弹飞久了会消失」
--   ① 平地上一辆靶车停在 800 米外（瞄准线穿过它，再往后一千来米才落到地上）：开镜激光测距，读数是到车的距离（末回波、首回波都是）；
--      车前面一丛草：首回波是草、末回波是车；看不见又不挡人的零件不算回波；房子那种看不见的碰撞盒算（炮弹也打在它上面）
--   ② 第三人称：准星压在车上，瞄准点（火控按它抬炮）在车上；车开着（画面上的车比服务器的盒子晚一截）：瞄着画面上的车尾测，照样是车的距离
--   ③ 猎歼式（FcsGen 4）：测距锁住这辆车（TRACK），车挪了瞄准线自己跟过去
--   ④ 一发落点 3～4 公里外的破甲弹：服务器的弹、客户端的弹和曳光一路都在，落地才结束
--   ⑤ 7.5 公里外（飞 9 秒多；原来破甲弹 8.5 秒就收掉）：照样飞到落地
--   ⑥ AI 坦克（AIVeh）、机关炮（没有弹道表的炮）：保底寿命 60 秒，飞到落地
--   ⑦ 飞出地图边界的弹收掉（不在地上溅水花）；服务器还没铺到的地形（射线打不到）按地图公式兜底，照样落地
--   ⑧ 自行火炮间瞄（G.shell）：客户端画一发弹沿弹道飞，到时间正好落在落点
--   ⑨ 残骸照样测得到
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check
local function clampN(x, a, b) if x < a then return a elseif x > b then return b end return x end   -- 普通 Lua 没有 math.clamp

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
G.Config.Round.prep = 4   -- 准备阶段缩短（开火要在交战阶段）
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8461, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = "def"
me.Team = G.TEAM.def
me.Neutral = false
me:SetAttribute("Side", "def")
G.pushOne(P)
R.run(1)
local C = T.C
T.leaveMenu()
local spId = "base"
for _, sp in ipairs(G.spawnList and G.spawnList(P.team, P) or {}) do
  if sp.ok and (sp.kind == "camp" or sp.kind == "base" or sp.kind == "redbase") then spId = sp.id break end
end
for _ = 1, 6 do
  if P.alive then break end
  T.actAs(me, "deploy", "rifle", spId)
  T.runUntil(function() return P.alive end, 4)
end
local RS = R.services.ReplicatedStorage
local VD = R.require(RS:FindFirstChild("VehDefs"))
local BAL = R.require(RS:FindFirstChild("Ballistics"))
local Map = G.Map
local cam = R.workspace.CurrentCamera
local S = BAL.S
local function flatV(v) return V3(v.X, 0, v.Z) end

-- 服务器发的特效里记下打中 / 落地的那几种（落点、时刻）
local fxLog = {}
local fx0 = G.fx
G.fx = function(e)
  if type(e) == "table" and (e.k == "boom" or e.k == "gimp" or e.k == "splash" or e.k == "spark") then
    fxLog[#fxLog + 1] = { k = e.k, p = e.p, t = os.clock() }
  end
  return fx0(e)
end

print("① 找一块平地：自己的车、800 米外的靶车、射线穿过靶车再往后一千来米才落地；另两个方向打 3.6 / 7.5 公里")
local MAXL = BAL.MAXR * S
local function flatAt(x, z) return Map.height(x, z) > 2 and Map.slope(x, z) < 0.08 end
-- 直线上地面最高处比 y 高多少（每 step 格取一点）
local function rise(a, dir, from, to, y)
  local worst = -1e9
  local d = from
  while d <= to do
    local p = a + dir * d
    worst = math.max(worst, Map.height(p.X, p.Z) - y)
    d = d + 120
  end
  return worst
end
local pick
for _, z0 in ipairs({ 0, -4000, 4000, -8000, 8000, -2000, 2000, 6000, -6000 }) do
  for x0 = -24000, 24000, 3000 do
    if flatAt(x0, z0) then
      local y0 = Map.height(x0, z0)
      local eye = V3(x0, y0 + 7.8, z0)
      for k = 0, 23 do
        local a = k / 24 * math.pi * 2
        local dir = V3(math.cos(a), 0, math.sin(a))
        local tx, tz = x0 + dir.X * 800 * S, z0 + dir.Z * 800 * S
        if flatAt(tx, tz) and math.abs(Map.height(tx, tz) - y0) < 2 and rise(V3(x0, 0, z0), dir, 30, 800 * S, y0 + 5) < 0 then
          local tc = V3(tx, Map.height(tx, tz) + 3.7, tz)
          local gp = Map.rayGround(eye, (tc - eye).Unit * MAXL)
          local gd = gp and (gp - eye).Magnitude / S or 1e9
          if gd > 1300 and gd < 3000 then
            -- 打远的两个方向：跟靶车那条线差 90° 以上，地面一路不比自己高出 20 格（7.5 公里那条看 6.5～8.5 公里）
            local sh = {}
            for j = 0, 23 do
              local b = j / 24 * math.pi * 2
              local d2 = V3(math.cos(b), 0, math.sin(b))
              if d2:Dot(dir) < 0.2 then
                local base2 = V3(x0, 0, z0)
                local e1 = base2 + d2 * 3600 * S
                local e2 = base2 + d2 * 7500 * S
                local inMap = math.abs(e2.X) < Map.R - 2000 and math.abs(e2.Z) < Map.R - 2000
                if inMap and not sh.near and rise(base2, d2, 40, 3300 * S, y0 + 20) < 0 and math.abs(Map.height(e1.X, e1.Z) - y0) < 12 then sh.near = d2 end
                if inMap and not sh.far and rise(base2, d2, 40, 6400 * S, y0 + 30) < 0 and rise(base2, d2, 6400 * S, 8400 * S, y0 + 12) < 0 then sh.far = d2 end
              end
            end
            if sh.near and sh.far then
              pick = { x = x0, z = z0, y = y0, dir = dir, tx = tx, tz = tz, gd = gd, near = sh.near, far = sh.far }
              break
            end
          end
        end
      end
    end
    if pick then break end
  end
  if pick then break end
end
check(pick ~= nil, pick and string.format("找到了：(%.0f, %.0f)，靶车 800 米，瞄准线穿过它 %.0f 米处才落地", pick.x, pick.z, pick.gd) or "没找到合适的平地")
if not pick then T.summary() return end

local def = VD.get("m1a2")
local e = G.newVehicle("def", "m1a2", G.vehBaseAt(def, pick.x, pick.z, pick.dir))
e.model:SetAttribute("FcsGen", 4)   -- 猎歼式火控（自动目标跟踪）：③ 用
e.model:SetAttribute("ModFcs", 0)
local tdef = VD.get("ztz99a")
local side = V3(-pick.dir.Z, 0, pick.dir.X)
local tgt = G.newVehicle("atk", "ztz99a", G.vehBaseAt(tdef, pick.tx, pick.tz, side))   -- 横着停（侧面对着我）
tgt.hp = 1e9
tgt.invuln = true
R.run(0.5)
me.Character:PivotTo(CF(pick.x + side.X * 14, pick.y + 4, pick.z + side.Z * 14))
R.run(0.4)
T.act("enterVeh", e.id)
R.run(1)
local st = C.drive
check(P.vehicle == e and st ~= nil, "坐上了 M1A2（猎歼式火控）")
if not st then T.summary() return end
T.runUntil(function() return G.round.phase == "battle" end, 60)
R.run(0.5)

-- 镜头（瞄准镜里 / 第三人称）对准一点
local function aimAt(p)
  local d = (p - cam.CFrame.Position).Unit
  st.camYaw = math.atan2(-d.X, -d.Z)
  st.camPitch = math.asin(d.Y)
end
local function settle(p, n)
  for _ = 1, n or 6 do aimAt(p) R.run(0.2) end
end
local function lase()
  R.as("client", function() C.driveLase() end)
  R.run(0.5)   -- 猎歼式：测距 + 解算 0.22 秒才出数
  return st.fcs.R
end
local function eyeDist(p) return (p - cam.CFrame.Position).Magnitude / S end

print("② 开镜激光测距：800 米外的靶车（后面一千多米才是地面）")
R.as("client", function() C.driveSetSight(true) end)
R.run(0.5)
check(st.sight == true, "开了主瞄准镜")
local tc = tgt.root.CFrame.Position + V3(0, 0.5, 0)
settle(tc)
local trueR = eyeDist(tc)
local R1 = lase()
check(R1 ~= nil and math.abs(R1 - trueR) < 12, string.format("激光测距（末回波）%s 米：到车 %.0f 米（瞄准线穿过去 %.0f 米才落地）", tostring(R1), trueR, pick.gd))
st.fcs.lrf = "FIRST"
local R2 = lase()
check(R2 ~= nil and math.abs(R2 - trueR) < 12, string.format("首回波 %s 米", tostring(R2)))
st.fcs.lrf = "LAST"
-- 车前面 400 米一丛草（半透明的叶子）：首回波是草、末回波是车
local eye0 = cam.CFrame.Position
local u0 = (tc - eye0).Unit
local function block(dist, size, props)
  local b = R.Instance.new("Part")
  b.Anchored = true
  b.Size = size
  b.CFrame = CF(eye0 + u0 * dist * S)
  for k, v in pairs(props) do b[k] = v end
  b.Parent = R.workspace
  return b
end
local bush = block(400, V3(3, 3, 3), { Material = R.Enum.Material.LeafyGrass, Transparency = 0.4, CanCollide = false })
st.fcs.lrf = "FIRST"
local R3 = lase()
st.fcs.lrf = "LAST"
local R4 = lase()
check(R3 ~= nil and math.abs(R3 - 400) < 8, string.format("草丛：首回波 %s 米（草在 400 米）", tostring(R3)))
check(R4 ~= nil and math.abs(R4 - trueR) < 12 and st.fcs.multi == true, string.format("末回波 %s 米（车），多回波 %s", tostring(R4), tostring(st.fcs.multi)))
bush:Destroy()
-- 看不见、不挡人的零件（特效锚点那种）：光直接穿过去，不算回波
local ghost = block(500, V3(4, 4, 4), { Transparency = 0.97, CanCollide = false })
local R5 = lase()
check(R5 ~= nil and math.abs(R5 - trueR) < 12 and st.fcs.multi ~= true, string.format("看不见的零件不算：%s 米、多回波 %s", tostring(R5), tostring(st.fcs.multi)))
ghost:Destroy()
-- 房子那种看不见的碰撞盒（挡人、挡车、挡炮弹）：算实物
local wall = block(600, V3(6, 6, 6), { Transparency = 1, CanCollide = true, Name = "Collision" })
local R6 = lase()
check(R6 ~= nil and math.abs(R6 - 600) < 8, string.format("房子的碰撞盒算：%s 米（在 600 米）", tostring(R6)))
wall:Destroy()

print("③ 第三人称：准星压在车上，瞄准点就在车上")
R.as("client", function() C.driveSetSight(false) end)
R.run(0.4)
settle(tc, 8)
local ap = st.aimPt
local inBox = ap and tgt.root.CFrame:PointToObjectSpace(ap)
local hs = tgt.root.Size / 2 + V3(1.5, 1.5, 1.5)
check(inBox ~= nil and math.abs(inBox.X) <= hs.X and math.abs(inBox.Y) <= hs.Y and math.abs(inBox.Z) <= hs.Z,
  string.format("瞄准点在车上（离车中心 %.1f 格；到镜头 %.0f 米）", ap and (ap - tgt.root.CFrame.Position).Magnitude or -1, ap and eyeDist(ap) or -1))

print("④ 车开着：画面上的车比服务器的盒子晚一截——瞄着画面上的车尾测距")
R.as("client", function() C.driveSetSight(true) end)
R.run(0.3)
local v0 = C.views and C.views[tgt.model]
local tcf0 = tgt.root.CFrame
local moveDir = side   -- 车头朝向（横着走：垂直于瞄准线）
local speed = 15 * S   -- 15 米 / 秒
local mt, lag = 0, 0
local lastMove = 0
local function moveStep(dt)
  mt = mt + dt
  if mt - lastMove >= 0.1 then   -- 服务器十来次 / 秒地挪（客户端按快照插值，画面晚一点）
    lastMove = mt
    G.moveEnt(tgt, tcf0 + moveDir * speed * mt)
  end
end
for _ = 1, 30 do moveStep(1 / 30) R.run(1 / 30) end
local vv = C.views and C.views[tgt.model]
local shown = vv and vv.fl and vv.cf and vv.cf.Position
lag = shown and (tgt.root.CFrame.Position - shown):Dot(moveDir) or 0
print(string.format("  （画面上的车比服务器的盒子晚 %.1f 格）", lag))
if shown and lag > 2 then
  -- 瞄准画面上车尾往里 1 格（服务器的盒子已经往前走过去了，这一点不在它里面）
  local rear = shown - moveDir * (tdef.L / 2 - 1.2) + V3(0, 0.5, 0)
  local lp
  for _ = 1, 4 do
    aimAt(rear)
    moveStep(1 / 30)
    R.run(1 / 30)
    vv = C.views[tgt.model]
    shown = vv.cf.Position
    rear = shown - moveDir * (tdef.L / 2 - 1.2) + V3(0, 0.5, 0)
  end
  aimAt(rear)
  R.as("client", function() C.driveLase() end)
  lp = rear
  for _ = 1, 15 do moveStep(1 / 30) R.run(1 / 30) end
  local Rm = st.fcs.R
  local want = eyeDist(lp)
  check(Rm ~= nil and math.abs(Rm - want) < 12, string.format("开着的车：测到 %s 米（画面上的车尾 %.0f 米）", tostring(Rm), want))
else
  check(false, "车开着，画面上的车没有落后服务器的盒子（测不了）")
end
G.moveEnt(tgt, tcf0)
R.run(1)

print("⑤ 猎歼式：测距锁住靶车，车挪了瞄准线自己跟过去")
st.fcs.trk = nil
settle(tc, 6)
lase()
check(st.fcs.trk == tgt.model, "锁住了这辆车（TRACK）：" .. tostring(st.fcs.trk and st.fcs.trk.Name))
check(#T.texts("TRACK") > 0, "镜下写 TRACK")
for i = 1, 40 do   -- 2 秒往旁边挪 30 格
  G.moveEnt(tgt, tcf0 + moveDir * (30 * i / 40))
  R.run(0.05)
end
R.run(1.2)
vv = C.views[tgt.model]
local tp = (vv and vv.cf and vv.cf.Position or tgt.root.CFrame.Position)
local look = cam.CFrame.LookVector
local want = (tp - cam.CFrame.Position).Unit
local off = math.deg(math.acos(clampN(look:Dot(want), -1, 1)))
check(st.fcs.trk == tgt.model and off < 0.6, string.format("瞄准线跟着车走：偏 %.2f°", off))
st.fcs.trk = nil
G.moveEnt(tgt, tcf0)
R.run(0.5)

-- 打一发、一路记服务器和客户端两边：服务器的弹（G.shots）在的每一帧客户端那发都在，曳光一直亮着
local function follow(sid, maxT, dt)
  dt = dt or 1 / 30
  local rec = { t = 0, gone = false, cliMiss = 0, tracerOff = 0, endP = nil, endT = nil, cliEnd = nil, n = 0 }
  local sp = nil
  local t = 0
  local nFx0 = #fxLog
  local seenCli = false
  while t < maxT do
    R.run(dt, dt)
    t = t + dt
    local s = nil
    for _, x in ipairs(G.shots) do if x.id == sid then s = x break end end
    local fs = C.flyingShots and C.flyingShots[sid]
    if fs then seenCli = true end
    if s then
      sp = s.pos
      rec.n = rec.n + 1
      if rec.n > 2 and not fs then rec.cliMiss = rec.cliMiss + 1 end
      if fs and fs.body then
        local bb = fs.body:FindFirstChildOfClass("BillboardGui")
        if bb and bb.Enabled == false then rec.tracerOff = rec.tracerOff + 1 end
      end
    elseif not rec.gone then
      rec.gone, rec.endT, rec.endP = true, t, sp
    end
    if rec.gone and not fs then rec.cliEnd = t break end
  end
  rec.seenCli = seenCli
  rec.fx = {}
  for i = nFx0 + 1, #fxLog do rec.fx[#rec.fx + 1] = fxLog[i] end
  return rec
end
local function hitFx(rec)
  -- 结束那一刻服务器放的打中 / 落地特效（boom 落地炸、gimp 穿甲弹打在地上、spark 打在钢上）
  if not rec.endP then return nil end
  for i = #rec.fx, 1, -1 do
    local f = rec.fx[i]
    if (f.k == "boom" or f.k == "gimp" or f.k == "spark") and typeof(f.p) == "Vector3" and (f.p - rec.endP).Magnitude < 600 then return f end
  end
  return nil
end
local function shotAt(dir2, rangeM, ammo)
  st.fcs.trk = nil
  R.as("client", function() C.driveAmmo(ammo) end)
  st.camYaw = math.atan2(-dir2.X, -dir2.Z)
  st.camPitch = 0
  R.as("client", function() C.driveRange(rangeM) end)
  for _ = 1, 40 do   -- 换弹种要重新装填，炮塔转过去、抬好超高角
    st.camYaw = math.atan2(-dir2.X, -dir2.Z)
    st.camPitch = 0
    R.run(0.25)
  end
  local n0 = #G.shots
  local last = G.shots[#G.shots]
  R.as("client", function() C.driveTryFire() end)
  R.run(1 / 60)
  local s = G.shots[#G.shots]
  if not s or s == last or #G.shots <= n0 then return nil end
  return s
end

print("⑥ 破甲弹打 3.6 公里：服务器的弹、客户端的弹和曳光一路都在，落地才结束")
local s1 = shotAt(pick.near, 3600, "m830")
check(s1 ~= nil and s1.kind == "shell", "打出去了一发炮弹（" .. tostring(s1 and s1.w and s1.w.id) .. "）")
if s1 then
  local mz = s1.p0
  local rec = follow(s1.id, 20)
  local hf = hitFx(rec)
  local dist = rec.endP and flatV(rec.endP - mz).Magnitude / S or 0
  check(rec.gone and rec.endT > 3.3, string.format("服务器那发飞了 %.1f 秒（曳光原来 3.2 秒烧完）", rec.endT or -1))
  check(hf ~= nil and rec.endP and math.abs(rec.endP.Y - Map.height(rec.endP.X, rec.endP.Z)) < 10,
    string.format("落地才结束（%s，落点离地 %.1f 格），飞了 %.0f 米", hf and hf.k or "没有落地特效", rec.endP and rec.endP.Y - Map.height(rec.endP.X, rec.endP.Z) or -1, dist))
  check(dist > 3000 and dist < 4300, string.format("落点在 3～4 公里外（%.0f 米）", dist))
  check(rec.seenCli and rec.cliMiss == 0, string.format("客户端那发一路都在（服务器在、客户端没了 %d 帧）", rec.cliMiss))
  check(rec.tracerOff == 0, string.format("曳光一路亮着（灭了 %d 帧）", rec.tracerOff))
  check(rec.cliEnd ~= nil and rec.cliEnd - rec.endT < 0.2, string.format("服务器落地，客户端那发跟着收（晚 %.2f 秒）", (rec.cliEnd or 99) - (rec.endT or 0)))
end

print("⑦ 破甲弹打 7.5 公里：飞 9 秒多（原来服务器 8.5 秒就收掉），照样飞到落地")
local s2 = shotAt(pick.far, 7500, "m830")
check(s2 ~= nil, "打出去了")
if s2 then
  local oldLife = BAL.MAXR * BAL.S / s2.vel.Magnitude + 1.5
  local mz = s2.p0
  local rec = follow(s2.id, 30, 1 / 20)
  local hf = hitFx(rec)
  local dist = rec.endP and flatV(rec.endP - mz).Magnitude / S or 0
  check(rec.gone and rec.endT > oldLife + 0.3, string.format("飞了 %.1f 秒（原来的寿命 %.1f 秒）", rec.endT or -1, oldLife))
  check(hf ~= nil and dist > 6000, string.format("落地才结束（%s），飞了 %.0f 米", hf and hf.k or "没有落地特效", dist))
  check(rec.seenCli and rec.cliMiss == 0 and rec.tracerOff == 0, string.format("客户端那发和曳光一路都在（没了 %d 帧、曳光灭了 %d 帧）", rec.cliMiss, rec.tracerOff))
end

print("⑧ AI 坦克、机关炮（没有弹道表）：保底寿命 60 秒，飞到落地")
local function aiShot(id, gp, wi)
  local d = VD.get(id)
  local ax, az = pick.x + side.X * 60, pick.z + side.Z * 60
  local ae = G.newVehicle("atk", id, G.vehBaseAt(d, ax, az, pick.far))
  ae.ai = { crew = { name = "AI" }, ammo = nil }
  ae.ty, ae.gp = 0, gp
  R.run(0.3)
  local n0 = #G.shots
  if not G.aiVehFire then return nil, ae end
  G.aiVehFire(ae, d.weapons[wi or 1])
  local s = (#G.shots > n0) and G.shots[#G.shots] or nil
  return s, ae
end
check(G.aiVehFire ~= nil, "AIVeh 给了测试用的开火入口（G.aiVehFire）")
local s3, a3 = aiShot("t90m", 1.2)
check(s3 ~= nil and (s3.life or 0) >= 59, string.format("AI 的 T-90M：炮弹寿命 %.1f 秒（原来 %.1f）", s3 and s3.life or -1, s3 and (BAL.MAXR * BAL.S / s3.vel.Magnitude + 1.5) or -1))
if s3 then
  local rec = follow(s3.id, 30, 1 / 20)
  local hf = hitFx(rec)
  check(rec.gone and hf ~= nil, string.format("AI 那发飞了 %.1f 秒落地（%s，%.0f 米）", rec.endT or -1, hf and hf.k or "没有落地特效", rec.endP and flatV(rec.endP - s3.p0).Magnitude / S or -1))
end
if a3 then G.removeEnt(a3) end
local s4, a4 = aiShot("bmp2", 10)
local w4 = VD.W.ac30
check(s4 ~= nil and (s4.life or 0) >= 59, string.format("AI 的 BMP-2 30 毫米机关炮：寿命 %.1f 秒（原来 %.1f）", s4 and s4.life or -1, math.max(w4.range / w4.speed + 0.5, 4000 * BAL.S / w4.speed)))
if s4 then
  local rec = follow(s4.id, 30, 1 / 20)
  local hf = hitFx(rec)
  local old = math.max(w4.range / w4.speed + 0.5, 4000 * BAL.S / w4.speed)
  check(rec.gone and hf ~= nil and rec.endT > old, string.format("抬 10° 打：飞了 %.1f 秒落地（%s，%.0f 米；原来 %.1f 秒就收掉）", rec.endT or -1, hf and hf.k or "没有落地特效",
    rec.endP and flatV(rec.endP - s4.p0).Magnitude / S or -1, old))
end
if a4 then G.removeEnt(a4) end

print("⑨ 飞出地图边界：收掉，不在地上溅水花；服务器还没铺到的地形：按地图公式兜底落地")
do
  local lim = math.max(Map.R or 0, Map.SEA_R or 0)
  local p0 = V3(lim - 1500, 3000, 0)
  local nfx = #fxLog
  local s = G.launch({ kind = "shell", pos = p0, vel = V3(4000, 0, 0), grav = true, gscale = 0.1, w = VD.W.gun120, src = { team = "def", name = "test" }, ignore = {}, life = 60 })
  local rec = follow(s.id, 5)
  local splash = false
  for i = nfx + 1, #fxLog do if fxLog[i].k == "splash" then splash = true end end
  check(rec.gone and rec.endT < 2 and not splash, string.format("飞出边界就收（%.1f 秒，%s水花）", rec.endT or -1, splash and "有" or "没有"))
end
do
  -- 落点一带假装地形还没铺（射线打不到）：用一个几百格的坑代替
  local d = pick.near
  local land = V3(pick.x, 0, pick.z) + d * 2000 * S
  local h0 = R.terrainHeight
  R.terrainHeight = function(x, z)
    if (x - land.X) ^ 2 + (z - land.Z) ^ 2 < 900 * 900 then return -1e6 end
    return h0(x, z)
  end
  local a = BAL.AMMO.m830
  local v0, drag, gs = BAL.launchArgs(a)
  local se = BAL.superElev(a, 2000, 0)
  local mz = V3(pick.x, pick.y + 8, pick.z)
  local dir = (d * math.cos(se) + V3(0, math.sin(se), 0)).Unit
  local s = G.launch({ kind = "shell", pos = mz, vel = dir * v0, grav = true, gscale = gs, drag = drag, cls = a.cls, w = VD.W.gun120, src = { team = "def", name = "test" }, ignore = {}, life = 60 })
  local rec = follow(s.id, 8)
  R.terrainHeight = h0
  local hf = hitFx(rec)
  local gy = rec.endP and Map.height(rec.endP.X, rec.endP.Z) or 0
  check(rec.gone and hf ~= nil and typeof(hf.p) == "Vector3" and math.abs(hf.p.Y - gy) < 3,
    string.format("地形没铺到的地方：%.1f 秒落地（%s，炸点离地图地面 %.1f 格）", rec.endT or -1, hf and hf.k or "没有落地特效", hf and typeof(hf.p) == "Vector3" and hf.p.Y - gy or -99))
end

print("⑩ 自行火炮间瞄（G.shell 按时间在落点炸）：客户端画一发弹沿弹道飞，到时间落在落点")
do
  local from = V3(pick.x, pick.y + 9, pick.z)
  local to = V3(pick.x, 0, pick.z) + pick.near * 3000
  to = V3(to.X, Map.ground(to.X, to.Z), to.Z)
  local flight = 6 + 3000 / 700
  local before = {}
  for k in pairs(C.flyingShots or {}) do before[k] = true end
  local t0 = os.clock()
  G.shell(to, VD.W.how155, { team = "def", name = "test" }, flight, from)
  local key, fsA = nil, nil
  local mid, last, endT, boomT = nil, nil, nil, nil
  local nfx = #fxLog
  local t = 0
  while t < flight + 2 do
    R.run(1 / 30, 1 / 30)
    t = t + 1 / 30
    if not key then
      for k, fs in pairs(C.flyingShots or {}) do if not before[k] then key, fsA = k, fs end end
    end
    local fs = key and C.flyingShots[key]
    if fs then
      last = fs.p
      if not mid and t > flight * 0.5 then mid = fs.p end
    elseif key and not endT then endT = t end
    if not boomT then
      for i = nfx + 1, #fxLog do if fxLog[i].k == "boom" then boomT = t end end
    end
  end
  check(key ~= nil, "客户端画了一发飞着的弹")
  local chordY = mid and (from.Y + (to.Y - from.Y) * 0.5) or 0
  check(mid ~= nil and mid.Y > chordY + 200, string.format("半路在天上（比炮口到落点的直线高 %.0f 格）", mid and mid.Y - chordY or -1))
  check(last ~= nil and (last - to).Magnitude < 40, string.format("最后落在落点（差 %.0f 格）", last and (last - to).Magnitude or -1))
  check(endT ~= nil and boomT ~= nil and math.abs(endT - boomT) < 0.25, string.format("落地那一刻服务器炸（弹收掉 %.2f 秒、炸 %.2f 秒）", endT or -1, boomT or -1))
  local _ = t0
end

print("⑪ 残骸照样测得到")
tgt.invuln = false
tgt.model:SetAttribute("WtWhy", "crew")
tgt.wtWhy = "crew"
G.wtRaw = true
G.damageEnt(tgt, 1e12, nil)
G.wtRaw = false
R.run(1.5)
check(tgt.model.Parent ~= nil and tgt.model:GetAttribute("Wreck") == true, "靶车成了残骸（还在原地）")
R.as("client", function() C.driveSetSight(true) end)
local tcw = tgt.root.CFrame.Position + V3(0, 0.5, 0)
settle(tcw, 6)
local R7 = lase()
local trueW = eyeDist(tcw)
check(R7 ~= nil and math.abs(R7 - trueW) < 12, string.format("残骸：%s 米（到残骸 %.0f 米）", tostring(R7), trueW))
check(#R.errors == 0, "全程没有报错：" .. table.concat(R.errors, " | "))
T.summary()
