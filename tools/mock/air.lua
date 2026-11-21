-- 飞机、直升机测试（模拟器）：python3 tools/mock/run.py tools/mock/air.lua [atk|def] [v]
--   生成点（停机位按 E、挂载界面按「生成」）→ 走过去坐进座舱 → 起飞（油门、抬头、收起落架）→ 飞行（鼠标瞄准、加力、失速）→ 航炮 → 锁定发射导弹 → 热诱弹 →
--   炸弹 → 弹舱门 → 落地补弹 → 跳伞；直升机：起飞悬停、旋翼转速、机头炮塔、火箭巢；模型：舵面、起落架、旋翼动画
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, Enum = T.R, T.V3, T.Enum
local check = T.check
local side = TEST_ARGS:match("def") and "def" or "atk"

-- 假装在 Studio 里导入了歼-20 的原模型（Imports.lua 开服时收进 Imported.Air.<键>）：默认导入新版（j20_v2：舵面、弹舱门、座舱盖是单独的块），
--   参数 old 只导入老版（j20：一整块蒙皮）——游戏照旧用老版、不会动。都查摆放时每块补回了导入时转掉的半圈（ImportTurn.lua）
local IA
do
  local f = assert(io.open(SRC_DIR .. "/ReplicatedStorage/ImportedAir.lua"))
  IA = load(f:read("a"))()
  f:close()
end
local IKEY = TEST_ARGS:match("old") and "j20" or (TEST_ARGS:match("v2") and "j20_v2") or IA.alias.j20   -- 默认最新版；old 只导入了老版、v2 只导入了第二版
for name, p in pairs(IA.m[IKEY].parts) do
  local mp = R.Instance.new("MeshPart")
  mp.Name = "A_" .. IKEY .. "__" .. name
  mp.Size = V3(p.s[1], p.s[2], p.s[3])
  mp.CFrame = T.CF(900 + p.c[1], 200 + p.c[2], 900 + p.c[3])
  mp.Parent = R.services.Workspace
end

local G = T.boot()
G.fortsHold = true   -- 这里测的不是工事：工事不开火
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 120)
local me = T.join("P1", 5001, true)
local other = T.join("P2", 5002, false)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local function setTeam(pl, team)
  local P = G.P[pl]
  P.team = team
  pl.Team = G.TEAM[team]
  pl.Neutral = false
  pl:SetAttribute("Side", team)
  G.pushOne(P)
end
local foe = side == "def" and "atk" or "def"
setTeam(me, side)
setTeam(other, foe)
R.run(1)
local P, PO = G.P[me], G.P[other]
local AD = require and nil
AD = R.requireModule and R.requireModule("AirDefs") or nil
local C = T.C

print("① 召唤位：飞机型号、名额；走到召唤位按 E，选机型（卡片）→ 挂载界面（选内油、按「生成」），再走过去坐上")
local jets = G.Config.Vehicles[side].jet
local jetId = (side == "atk") and "j20" or "f22"
local has = false
for _, id in ipairs(C.S.vehModels or {}) do if id == jetId then has = true end end
check(has, "能用的型号里有 " .. jetId .. "：" .. table.concat(C.S.vehModels or {}, ","))
check(C.S.vehAvail and C.S.vehAvail.jet and C.S.vehAvail.jet.cap >= 1, "固定翼名额 " .. tostring(C.S.vehAvail and C.S.vehAvail.jet and C.S.vehAvail.jet.cap))
T.act("deploy", "rifle", (side == "atk") and "af2" or "afield")   -- 攻方机场岛（歼-20 是陆基飞机）/ 守方机场（据点 D）
R.run(2)
check(P.alive and P.vehicle == nil, "步兵出生了")
local jp = T.pad(jetId)
check(jp ~= nil and jp.kind == "air" and jp.summon == true, "有能召唤 " .. jetId .. " 的召唤位（" .. table.concat((jp and jp.vids) or {}, ",") .. "）")
if jp then T.usePad(me, jp) end
local card = T.findNamed("Pick_" .. jetId)
check(card ~= nil, "弹出了选机型的卡片")
if card then T.press(card) end
R.run(0.3)
local f75 = T.findNamed("Fuel75")
check(f75 ~= nil, "挂载界面里能选内油（25% / 50% / 75% / 100%）")
if f75 then T.press(f75) end
local go = T.findButton("^" .. C.T("pad.spawn") .. "$")
check(go ~= nil, "弹出了挂载界面（按钮是「生成」）")
if go then T.press(go) end
R.run(1)
local e0 = nil
for _, x in ipairs(G.aircraft or {}) do if jp and x.padId == jp.id and x.alive then e0 = x end end
check(e0 ~= nil and e0.driver == nil, "飞机停在停机位上（空着）")
check(e0 ~= nil and e0.fuel == 0.75 and e0.model:GetAttribute("Fuel") == 0.75, "带了选的 75% 内油（" .. tostring(e0 and e0.model:GetAttribute("Fuel")) .. "）")
T.act("enterVeh", e0 and e0.id)
R.run(1.5)
local e = P.vehicle
check(e ~= nil and e.air and e.def.id == jetId, "坐进了 " .. tostring(e and e.def.id))
if e then
  local n = 0
  for _, k in ipairs(e.stores) do n = n + k end
  check(n > 0, "按预设挂了 " .. n .. " 枚：" .. e.model:GetAttribute("Load"))
  local p = e.root.CFrame.Position
  check(math.abs(p.Y - G.airSurface(p.X, p.Z) - e.def.gearH) < 0.5, string.format("停在跑道上（离地 %.1f 格）", p.Y - G.airSurface(p.X, p.Z)))
end
if e and e.def.id == "j20" then
  print("② 导入的原模型（" .. IKEY .. "）：每块在原位置、绕自己的中心转了半圈（Roblox 导入 GLB 时把每块网格转了半圈，摆的时候转回来）")
  local v
  if C.views then for em, vv in pairs(C.views) do if em == e.model then v = vv end end end
  local n, bad, worst = 0, 0, 0
  local O = V3(0, -e.def.gearH, 0)
  local byGroup = {}
  if v and v.M then
    for _, it in ipairs(v.M.items) do
      local name = string.match(it.p.Name, "^A_" .. IKEY:gsub("_", "%%_") .. "__(.+)$")
      local p = name and IA.m[IKEY].parts[name]
      if p and it.kind ~= "r" then
        n = n + 1
        local cf = it.cf0
        if it.kind == "h" then cf = it.H * it.off end   -- 绕铰链转的块：转角 0 时的样子
        if cf.LookVector.Z < 0.999 or cf.UpVector.Y < 0.999 then bad = bad + 1 end
        worst = math.max(worst, (cf.Position - (V3(p.c[1], p.c[2], p.c[3]) + O)).Magnitude)
        local g = p.g
        byGroup[g] = byGroup[g] or {}
        table.insert(byGroup[g], it)
      end
    end
  end
  check(v ~= nil and v.M ~= nil and v.M.imported == IKEY, "飞机用上了导入的原模型（" .. tostring(v and v.M and v.M.imported) .. "）")
  check(n > 0 and bad == 0, string.format("%d 块导入的零件都转了半圈（朝向不对的 %d 块）", n, bad))
  check(n > 0 and worst < 0.01, string.format("位置照元数据（最大偏差 %.3f 格）", worst))
  if IA.m[IKEY].surf then
    print("③ 活动部件：按操纵量绕铰链往对的方向转")
    -- 这一组块在通道 c 下，块中心往上挪了多少（格）
    local function dy(g, c)
      local list = byGroup[g]
      if not list then return nil end
      local s = 0
      for _, it in ipairs(list) do
        if it.kind ~= "h" then return nil end
        local cf0 = it.H * it.off
        local cf1 = it.H * R.CFrame.fromAxisAngle(it.ax, it.f(c)) * it.off
        s = s + (cf1.Position.Y - cf0.Position.Y)
      end
      return s / #list
    end
    local function fmt(x) return x and string.format("%.2f", x) or "没有" end
    local a = dy("ElvR", { pit = 1 })
    check(a and a > 0.05, "抬头：右升降副翼后缘往上（块中心升 " .. fmt(a) .. " 格）")
    local r1, r2 = dy("AilR", { rol = 1 }), dy("AilL", { rol = 1 })
    check(r1 and r2 and r1 > 0.05 and r2 < -0.05, "右滚：右副翼往上 " .. fmt(r1) .. "、左副翼往下 " .. fmt(r2))
    local b = dy("BayM1", { bay = 1 })
    check(b and b < -0.3, "开弹舱：主弹舱门往下翻（" .. fmt(b) .. " 格）")
    -- 侧弹舱门在进气道下侧 45° 的斜面上、铰链在外上沿：打开是往外翻（中心高度差不多，往外挪）
    local out = nil
    for _, it in ipairs(byGroup.BaySL or {}) do
      local cf0 = it.H * it.off
      local cf1 = it.H * R.CFrame.fromAxisAngle(it.ax, it.f({ bayS = 1 })) * it.off
      out = (out or 0) + (math.abs(cf1.Position.X) - math.abs(cf0.Position.X)) / #byGroup.BaySL
    end
    check(out and out > 0.3, "开侧弹舱：左侧弹舱门往外翻（" .. fmt(out) .. " 格）")
    local cn = dy("Canopy", { can = 1 })
    check(cn and cn > 1, "停机掀座舱盖：往上掀（" .. fmt(cn) .. " 格）")
    local rz = 0
    for _, it in ipairs(byGroup.FinR or {}) do
      local cf1 = it.H * R.CFrame.fromAxisAngle(it.ax, it.f({ yaw = 1 })) * it.off
      rz = math.max(rz, select(2, (it.H * it.off):ToObjectSpace(cf1):ToAxisAngle()))
    end
    check(rz > math.rad(10), string.format("右偏航：全动垂尾转了 %.0f°", math.deg(rz)))
    local pil, near = 0, 99
    local pit = IA.m[IKEY].pit[1]
    for _, it in ipairs(v.M.items) do
      if it.tag == "pilot" then
        pil = pil + 1
        near = math.min(near, (it.cf0.Position - (V3(pit[1], pit[2], pit[3]) + O)).Magnitude)
      end
    end
    check(pil >= 4 and near < 1.5, string.format("座舱里坐着飞行员（%d 块，离原模型的眼位 %.2f 格）", pil, near))
    -- 起落架（j20_v4：原模型没有，tools/models/j20_gear.py 建的网格，关键帧往前收）、起落架舱门（gdh：放的前 1/4 开门、收的最后 1/4 关门）
    if byGroup.GearL then
      local function at(g, c)
        local s, k = V3(0, 0, 0), 0
        for _, it in ipairs(byGroup[g] or {}) do
          if it.kind == "m" then
            s = s + (it.f(c) * it.cf0).Position
            k = k + 1
          end
        end
        return k > 0 and s * (1 / k) or nil
      end
      local g1, g0, gq = at("GearL", { gear = 1 }), at("GearL", { gear = 0 }), at("GearL", { gear = 0.25 })
      check(g1 and g0 and g0.Y - g1.Y > 2 and g0.Z < g1.Z - 2,
        string.format("收起落架：左主起落架往前 %.1f 格、往上 %.1f 格收进机身", g1 and g0 and (g1.Z - g0.Z) or 0, g1 and g0 and (g0.Y - g1.Y) or 0))
      check(g0 and gq and (g0 - gq).Magnitude < 0.05, "操纵量 0.25 时支柱已经收到底（之后舱门才关）")
      local n1, n0 = dy("GDoorN1", { gear = 1 }), dy("GDoorN1", { gear = 0 })
      check(n1 and n0 and n1 < -0.3 and math.abs(n0) < 0.01, "前起落架舱门：放下时往下开（" .. fmt(n1) .. " 格），收起时关上（" .. fmt(n0) .. "）")
      local mo = 0
      for _, it in ipairs(byGroup.GDoorML or {}) do
        local cf0 = it.H * it.off
        local cf1 = it.H * R.CFrame.fromAxisAngle(it.ax, it.f({ gear = 1 })) * it.off
        mo = mo + (math.abs(cf1.Position.X) - math.abs(cf0.Position.X)) / #byGroup.GDoorML
      end
      check(mo > 0.3, "主起落架舱门：放下时往外翻（" .. fmt(mo) .. " 格）")
      local built = 0
      for _, it in ipairs(v.M.items) do if it.tag == "gear" then built = built + 1 end end
      check(built == 0, "原模型自带起落架：零件拼的起落架不画了（" .. built .. " 个零件）")
    end
    -- 弹舱 / 起落架舱里：WELL 表的深色方盒子（Part），v4 的侧弹舱、起落架舱换成 tools/models/doorbay.py 做的舱（网格 Well_1…，开口一圈封住，开了舱门看不穿飞机）
    local wells, cav = 0, 0
    for _, it in ipairs(v.M.items) do
      local col = it.p.Color
      if it.kind == "b" and not it.tag and it.p.ClassName == "Part" and col.R < 0.16 and col.G < 0.16 and col.B < 0.17 then wells = wells + 1 end
      if it.kind == "b" and string.match(it.p.Name, "__Well_%d+$") then cav = cav + 1 end
    end
    check(wells + cav >= 3, "弹舱里有深色的舱壁（方盒 " .. wells .. " 个、舱 " .. cav .. " 个）")
    if IA.m[IKEY].bayfix then
      check(cav == 5, "侧弹舱、起落架舱是封好的舱（" .. cav .. " 个，应该 5 个：两个侧弹舱、两个主起落架舱、前起落架舱）")
      local duct = 0
      for _, it in ipairs(v.M.items) do
        if it.kind == "b" and string.match(it.p.Name, "__Duct_%d+$") then duct = duct + 1 end
      end
      check(duct == 2, "进气道里补了深色管道（" .. duct .. " 个，应该 2 个）")
    end
  end
end
print("④ 降落伞：角色带着 Chute 属性（服务器在跳伞时设）就在头顶张开一顶伞，落地收掉")
if me.Character then
  me.Character:SetAttribute("Chute", true)
  R.run(1.2)
  local m = R.services.Workspace:FindFirstChild("Parachute")
  local n, hi = 0, -1e9
  if m then for _, p in ipairs(m:GetChildren()) do n = n + 1 hi = math.max(hi, p.CFrame.Position.Y) end end
  local hrp = me.Character:FindFirstChild("HumanoidRootPart")
  check(m ~= nil and n > 20, "张开了一顶伞（" .. n .. " 块）")
  check(hrp and hi > hrp.Position.Y + 12, string.format("伞在头顶上方（最高处比人高 %.1f 格）", hrp and (hi - hrp.Position.Y) or 0))
  me.Character:SetAttribute("Chute", false)
  R.run(0.3)
  check(R.services.Workspace:FindFirstChild("Parachute") == nil, "落地收掉了")
end
print("⑤a 键位（用户 11-21：WASD 控制方向、不要准心）：Shift 加油门、Ctrl 收油门，地上收到底按住 Ctrl 倒退；W / S 不再管油门")
local fst = C.fly
local CFr, V2 = R.CFrame, R.Vector2.new
if fst and e then
  fst.thr = 0
  local p0 = fst.cf.Position
  local lk0 = fst.cf.LookVector
  T.key(Enum.KeyCode.LeftControl, true)
  R.run(2)
  T.key(Enum.KeyCode.LeftControl, false)
  local back = (fst.cf.Position - p0):Dot(lk0)
  check(fst.spd < -3 and back < -3, string.format("地上油门收到底按住 Ctrl：倒退（速度 %.1f、往后挪了 %.1f 格）", fst.spd, -back))
  T.key(Enum.KeyCode.LeftShift, true)
  R.run(1)
  T.key(Enum.KeyCode.LeftShift, false)
  check(fst.thr > 40, string.format("按住 Shift 推油门（%.0f）", fst.thr))
  local t0 = fst.thr
  T.key(Enum.KeyCode.W, true)
  R.run(0.4)
  T.key(Enum.KeyCode.W, false)
  T.key(Enum.KeyCode.S, true)
  R.run(0.4)
  T.key(Enum.KeyCode.S, false)
  check(math.abs(fst.thr - t0) < 0.01, "W / S 不再管油门（是驾驶杆）")
  T.key(Enum.KeyCode.LeftControl, true)
  R.run(0.4)
  T.key(Enum.KeyCode.LeftControl, false)
  check(fst.thr < 40, string.format("按住 Ctrl 收油门（%.0f）", fst.thr))
end
print("⑤ 起飞、拉杆（键盘当驾驶杆：S 抬头、W 低头、A / D 滚转）：有重量感、不太灵活；机头的全息标记平飞时在正中、拉杆时挪一点（MWT 那样）")
local cam = R.services.Workspace.CurrentCamera
local function markOff()   -- 机头前方 300 格那一点离屏幕中心多少像素（全息标记就在那里）
  local sp = cam:WorldToViewportPoint(fst.cf.Position + fst.cf.LookVector * 300)
  return math.sqrt((sp.X - cam.ViewportSize.X / 2) ^ 2 + (sp.Y - cam.ViewportSize.Y / 2) ^ 2)
end
local function bankDeg() return math.deg(math.asin(math.max(-1, math.min(1, fst.cf.RightVector.Y)))) end
if fst and e then
  T.key(Enum.KeyCode.LeftShift, true)   -- 推满油门滑跑，速度到了按住 S 抬头离地
  T.runUntil(function() return fst.spd >= e.def.vRot end, 40)
  T.key(Enum.KeyCode.S, true)
  local up = T.runUntil(function() return not fst.ground end, 10)
  check(up, string.format("滑跑到抬头速度、按住 S 离地（离地时速度 %.0f 格 / 秒）", fst.spd or 0))
  R.run(2.5)
  T.key(Enum.KeyCode.S, false)
  R.run(6)
  T.key(Enum.KeyCode.LeftShift, false)
  local p = fst.cf.Position
  check(p.Y == p.Y and p.Y > G.Map.ground(p.X, p.Z) + 20, string.format("飞起来了（离地 %.0f 格，速度 %.0f）", p.Y - G.Map.ground(p.X, p.Z), fst.spd))
  -- 收到军推、摆平（测试直接把姿态放平），松着杆飞：保持航向、高度变化不大，标记在正中
  fst.thr = 85
  local function level()
    local q = fst.cf.Position
    local f = fst.cf.LookVector
    local fl = Vector3 and nil
    fl = R.Vector3.new(f.X, 0, f.Z).Unit
    fst.cf = CFr.lookAt(q, q + fl)
    fst.vdir, fst.pr, fst.rr, fst.yr = fl, 0, 0, 0
  end
  level()
  R.run(1)
  local y0, h0 = fst.cf.Position.Y, fst.cf.LookVector
  local worst = 0
  for _ = 1, 90 do R.run(1 / 30) worst = math.max(worst, markOff()) end
  local turned = math.deg(math.acos(math.max(-1, math.min(1, fst.cf.LookVector:Dot(h0)))))
  check(math.abs(fst.cf.Position.Y - y0) < 40 and turned < 3, string.format("松着杆：照直飞（3 秒高度变了 %.0f 格、航向偏了 %.1f°）", fst.cf.Position.Y - y0, turned))
  check(worst <= 2, string.format("平飞时机头标记在屏幕正中（最远偏 %.1f 像素）", worst))
  local ring = T.findNamed("AimRing")
  check(not (ring and T.visible(ring)), "有人开的固定翼不画准星圈（不要准心控制）")
  -- 拉杆：按住 S——角速度慢慢起来（键 0.3 秒推满 + 转动惯量），航迹慢半拍（迎角），过载不超过收过的上限，拉得狠掉速
  local spd0 = fst.spd
  local PMAX = math.rad(e.def.pitch) * 0.65
  T.key(Enum.KeyCode.S, true)
  R.run(0.1)
  local pr1 = fst.pr
  local aoa, gMax = 0, 0
  worst = 0
  for _ = 1, 45 do
    R.run(1 / 30)
    local f = fst.cf.LookVector
    if fst.vdir then aoa = math.max(aoa, math.deg(math.acos(math.max(-1, math.min(1, f:Dot(fst.vdir)))))) end
    gMax = math.max(gMax, fst.gLoad or 0)
    worst = math.max(worst, markOff())
  end
  T.key(Enum.KeyCode.S, false)
  check(fst.pr > 0.05, string.format("按住 S 抬头（俯仰角速度 %.0f°/秒）", math.deg(fst.pr)))
  check(math.abs(pr1) < PMAX * 0.5, string.format("拉杆 0.1 秒俯仰角速度才到 %.0f%%（杆量慢慢推上去、转动有惯性）", 100 * math.abs(pr1) / PMAX))
  check(aoa > 1.5 and aoa < 25, string.format("拉杆时机头比航迹高 %.1f°（飞机「吃」一下才转过去）", aoa))
  check(gMax <= e.def.g * 0.72 + 0.3, string.format("过载不超过 %.1f g（用户 11-21：太灵活了，上限收到七成；这次最大 %.1f g）", e.def.g * 0.72, gMax))
  check(fst.spd < spd0, string.format("大迎角掉速：%.0f → %.0f", spd0, fst.spd))
  check(worst > 4 and worst < 200, string.format("拉杆时机头标记往上挪了一点（用户 11-21：像 MWT 那样会位移；最远偏 %.1f 像素，原来钉死在正中、再原来乱跑两百多）", worst))
  R.run(1.5)
  check(markOff() <= 3, string.format("松杆 1.5 秒：标记回到正中（偏 %.1f 像素）", markOff()))
  local q = fst.cf.Position
  check(q.X == q.X and q.Y == q.Y and q.Z == q.Z, "位置正常（没有算出 NaN）")
  -- A / D 滚转：不太灵活（用户 11-21），松开以后小坡度自己慢慢摆平
  level()
  R.run(0.5)
  local b0, rmax = bankDeg(), 0
  T.key(Enum.KeyCode.D, true)
  for _ = 1, 24 do
    local b1 = bankDeg()
    R.run(1 / 30)
    rmax = math.max(rmax, math.abs(bankDeg() - b1) * 30)
  end
  T.key(Enum.KeyCode.D, false)
  local rolled = math.abs(bankDeg() - b0)
  check(rolled > 20, string.format("按住 D 往右滚（0.8 秒滚了 %.0f°）", rolled))
  check(rmax < 105, string.format("滚转不太快（最快 %.0f°/秒；原来歼-20 一秒两百多度）", rmax))
  check(bankDeg() < -5, string.format("往右滚是右翼往下（坡度 %.0f°）", bankDeg()))
  level()
  R.run(0.3)
  T.key(Enum.KeyCode.A, true)
  R.run(0.25)
  T.key(Enum.KeyCode.A, false)
  local bSmall = bankDeg()
  R.run(4)
  check(math.abs(bSmall) > 3 and math.abs(bankDeg()) < math.abs(bSmall) * 0.5, string.format("轻点 A 压了 %.0f° 坡度，松开 4 秒自己摆平到 %.1f°", bSmall, bankDeg()))
  -- W 低头
  level()
  R.run(0.3)
  T.key(Enum.KeyCode.W, true)
  R.run(0.6)
  T.key(Enum.KeyCode.W, false)
  check(fst.cf.LookVector.Y < -0.02, string.format("按住 W 低头（俯仰 %.1f°）", math.deg(math.asin(fst.cf.LookVector.Y))))
  -- 鼠标转视角（用户 11-21：飞机要允许用鼠标转视角）：不用按 Alt，拨鼠标镜头转开、停在那里；鼠标 2.5 秒不动慢慢回到身后；C 立刻回正
  level()
  R.run(0.3)
  local function awayDeg() return math.deg(math.acos(math.max(-1, math.min(1, cam.CFrame.LookVector:Dot(fst.cf.LookVector))))) end
  for _ = 1, 10 do
    R.mouseDelta = V2(30, 0)
    R.run(1 / 30)
  end
  R.mouseDelta = V2(0, 0)
  local away = awayDeg()
  check(away > 20, string.format("不按 Alt 拨鼠标：镜头转开 %.0f°", away))
  R.run(1.5)
  check(awayDeg() > 15, string.format("鼠标停 1.5 秒：镜头还停在拨到的地方（%.0f°）", awayDeg()))
  R.run(4)
  check(markOff() <= 3, string.format("鼠标停 2.5 秒以上：镜头慢慢回到身后（标记偏 %.1f 像素）", markOff()))
  for _ = 1, 10 do
    R.mouseDelta = V2(30, 0)
    R.run(1 / 30)
  end
  R.mouseDelta = V2(0, 0)
  T.key(Enum.KeyCode.C, true)
  R.run(1 / 30)
  T.key(Enum.KeyCode.C, false)
  R.run(0.5)
  check(markOff() <= 3, string.format("按 C：镜头立刻回到身后（标记偏 %.1f 像素）", markOff()))
  level()
  R.run(0.5)
end

print("⑤½ 机炮黏住目标（用户 11-21：机炮也能像 MWT 那样黏在载具上）")
if fst and e then
  R.run(0.5)
  local ents = R.workspace:FindFirstChild("Ents")
  local fake = R.Instance.new("Model")
  fake.Name = "FakeTank"
  local root = R.Instance.new("Part")
  root.Name = "Root"
  root.Size = V3(8, 6, 14)
  root.Anchored = true
  root.CFrame = R.CFrame.new(fst.cf.Position + fst.cf.LookVector * 900 + fst.cf.RightVector * 40)   -- 机头右边 2.5°、900 格
  root.Parent = fake
  fake:SetAttribute("Kind", "veh")
  fake:SetAttribute("Team", (me:GetAttribute("Side") == "atk") and "def" or "atk")
  fake:SetAttribute("Hp", 100)
  fake:SetAttribute("EntId", 99901)
  fake.Parent = ents
  local gun0 = fst.d.gun
  fst.d.gun = gun0 or "gsh30"   -- 歼-20 没有内置机炮：这一段借一门 30 毫米炮来测（测完还原）
  R.run(0.4)
  check(fst.stick ~= nil and fst.stick.em == fake, "机头前方 2.5° 的敌方坦克：机炮黏上去了")
  local function aimRingShown()   -- AirHud 的准星圈（ImageLabel，T.findNamed 只找按钮）
    for _, g in ipairs(R.localPlayer.PlayerGui:GetDescendants()) do
      if g.Name == "AimRing" and g.ClassName == "ImageLabel" and T.visible(g) then return g end
    end
  end
  local ring = aimRingShown()
  check(ring ~= nil, "黏住时准星圈画在目标上")
  if ring and fst.stick then
    local cam2 = R.workspace.CurrentCamera
    local sp = cam2:WorldToViewportPoint(fst.stick.lead)
    local vp = cam2.ViewportSize
    local pos = ring.Position
    local dx = pos.X.Scale * vp.X + pos.X.Offset - sp.X
    local dy = pos.Y.Scale * vp.Y + pos.Y.Offset - sp.Y
    check(math.sqrt(dx * dx + dy * dy) < 6, string.format("准星圈在提前量那一点上（差 %.1f 像素）", math.sqrt(dx * dx + dy * dy)))
  end
  if fst.stick then
    local to = (fst.stick.lead - fst.cf.Position).Unit
    local off = math.deg(math.acos(math.max(-1, math.min(1, to:Dot(fst.cf.LookVector)))))
    check(off > 1 and off < 12, string.format("瞄准点在提前量上（离机头 %.1f°，服务器 12° 以内照着打）", off))
  end
  R.run(0.3)
  check(e.stick == true and e.aim ~= nil, "服务器收到了「黏住了」和瞄准点")
  -- 偏到 9° 以外松开；队友的车不黏
  root.CFrame = R.CFrame.new(fst.cf.Position + fst.cf.LookVector * 600 + fst.cf.RightVector * 150)   -- 约 14°
  R.run(0.3)
  check(fst.stick == nil, "目标偏到 9° 以外：松开了")
  root.CFrame = R.CFrame.new(fst.cf.Position + fst.cf.LookVector * 900)
  fake:SetAttribute("Team", me:GetAttribute("Side"))
  R.run(0.3)
  check(fst.stick == nil, "自己队的车不黏")
  fake:Destroy()
  R.run(0.3)
  check(aimRingShown() == nil, "没黏住：准星圈收起来")
  fst.d.gun = gun0
end

print("⑥ 油量：飞着就烧油（油门越大越费）、平显上有油量；副油箱先烧、烧干自动抛、J 键手动抛；烧干熄火")
check(fst ~= nil and e ~= nil and e.alive and P.vehicle == e, string.format("还开着飞机（fly %s、alive %s、P.vehicle 是它 %s、高度 %.0f）", tostring(fst ~= nil),
  tostring(e and e.alive), tostring(P.vehicle == e), fst and (fst.cf.Position.Y - G.Map.ground(fst.cf.Position.X, fst.cf.Position.Z)) or -1))
if fst and e and e.alive then
  local f0 = e.fuel
  fst.thr = 100
  R.run(3)
  local used = f0 - e.fuel
  local want = AD and AD.burn(e.def, 100) * 3 or used
  check(used > 0 and math.abs(used - want) < want * 0.5, string.format("军推 3 秒烧了 %.4f（应该约 %.4f）", used, want))
  local ft = T.texts((C.T("air.fuel", math.floor(e.model:GetAttribute("Fuel") * 100 + 0.5)):gsub("%%", "%%%%")))
  check(#ft > 0, "平显上写着油量：" .. tostring(ft[1]))
  -- 直接给它挂上两个副油箱（服务器那边的挂载），看先烧外挂的、J 键抛掉
  local wing = {}
  for i, s in ipairs(e.def.st or {}) do
    for _, w in ipairs(s.opts) do if w == "tk800" or w == "tk370" then wing[i] = w end end
  end
  local n = 0
  for i, w in pairs(wing) do e.load[i], e.stores[i], n = w, 1, n + 1 end
  if n == 0 then   -- F-22 只有弹舱、没有挂副油箱的挂点（AirDefs 的 TANKS 里没有它）：守方这两项跳过
    print("  （" .. e.def.id .. " 没有挂副油箱的挂点，副油箱两项跳过）")
  else
    e.fuelX = n * 0.3
    local fi, fx = e.fuel, e.fuelX
    R.run(2)
    check(e.fuelX < fx and math.abs(e.fuel - fi) < 1e-6, string.format("先烧副油箱（外挂 %.3f → %.3f，内油没动）", fx, e.fuelX))
    local fxn = 0
    local fx0 = G.fx
    G.fx = function(x) if x.k == "tankDrop" then fxn = fxn + 1 end return fx0(x) end
    T.key(Enum.KeyCode.J, true)
    R.run(0.3)
    T.key(Enum.KeyCode.J, false)
    R.run(0.5)
    local left = 0
    for i in pairs(wing) do left = left + (e.stores[i] or 0) end
    check(left == 0 and e.fuelX == 0 and fxn == n, string.format("J 键抛掉了 %d 个副油箱（还挂着 %d 个，掉下去的特效 %d 个）", n, left, fxn))
    G.fx = fx0
  end
  -- 烧干：熄火，油门推不上去
  e.fuel = 0.0005
  R.run(1.5)
  fst.thr = 100
  R.run(0.5)
  check(e.fuel == 0 and fst.out == true and fst.thr == 0, string.format("油烧干了熄火（内油 %.4f，油门 %.0f）", e.fuel, fst.thr))
  local wt = T.texts(C.T("air.flameout"))
  check(#wt > 0, "平显警告：燃油耗尽")
end

T.summary()
