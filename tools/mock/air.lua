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

print("① 生成点：飞机型号、名额；走到停机位按 E，挂载界面按「生成」，再走过去坐上")
local jets = G.Config.Vehicles[side].jet
local jetId = (side == "atk") and "j20" or "f22"
local has = false
for _, id in ipairs(C.S.vehModels or {}) do if id == jetId then has = true end end
check(has, "能用的型号里有 " .. jetId .. "：" .. table.concat(C.S.vehModels or {}, ","))
check(C.S.vehAvail and C.S.vehAvail.jet and C.S.vehAvail.jet.cap >= 1, "固定翼名额 " .. tostring(C.S.vehAvail and C.S.vehAvail.jet and C.S.vehAvail.jet.cap))
T.act("deploy", "rifle", (side == "atk") and "af2" or "point.D")   -- 攻方机场岛（歼-20 是陆基飞机）/ 守方机场（据点 D）
R.run(2)
check(P.alive and P.vehicle == nil, "步兵出生了")
local jp = T.pad(jetId)
check(jp ~= nil and jp.kind == "air", "有 " .. jetId .. " 的停机位生成点")
if jp then T.usePad(me, jp) end
local go = T.findButton("^" .. C.T("pad.spawn") .. "$")
check(go ~= nil, "弹出了挂载界面（按钮是「生成」）")
if go then T.press(go) end
R.run(1)
local e0 = nil
for _, x in ipairs(G.aircraft or {}) do if jp and x.padId == jp.id and x.alive then e0 = x end end
check(e0 ~= nil and e0.driver == nil, "飞机停在停机位上（空着）")
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
    local wells = 0
    for _, it in ipairs(v.M.items) do
      local col = it.p.Color
      if it.kind == "b" and not it.tag and it.p.ClassName == "Part" and col.R < 0.16 and col.G < 0.16 and col.B < 0.17 then wells = wells + 1 end
    end
    check(wells >= 3, "弹舱里有深色的舱壁（" .. wells .. " 个）")
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
print("⑤ 起飞、拉杆：有重量感——航迹落后于机头（迎角）、角速度慢慢起来、大迎角掉速")
local fst = C.fly
if fst and e then
  T.key(Enum.KeyCode.W, true)
  T.key(Enum.KeyCode.Up, true)
  local up = T.runUntil(function() return not fst.ground end, 40)
  T.key(Enum.KeyCode.Up, false)
  check(up, string.format("滑跑起飞（离地时速度 %.0f 格 / 秒）", fst.spd or 0))
  R.run(8)
  local p = fst.cf.Position
  check(p.Y == p.Y and p.Y > G.Map.ground(p.X, p.Z) + 20, string.format("飞起来了（离地 %.0f 格，速度 %.0f）", p.Y - G.Map.ground(p.X, p.Z), fst.spd))
  -- 收到军推、平飞稳一下，再猛拉杆：角速度一开始还没起来，航迹慢半拍跟上机头，大迎角掉速
  T.key(Enum.KeyCode.W, false)
  fst.thr = 85
  R.run(3)
  local spd0 = fst.spd
  T.key(Enum.KeyCode.Down, true)
  R.run(0.1)
  local pr1 = fst.pr
  local aoa = 0
  for _ = 1, 45 do
    R.run(1 / 30)
    local f = fst.cf.LookVector
    if fst.vdir then aoa = math.max(aoa, math.deg(math.acos(math.max(-1, math.min(1, f:Dot(fst.vdir)))))) end
  end
  T.key(Enum.KeyCode.Down, false)
  local prMax = math.rad(e.def.pitch)
  check(math.abs(pr1) < prMax * 0.6, string.format("拉杆 0.1 秒俯仰角速度才到 %.0f%%（转动有惯性）", 100 * math.abs(pr1) / prMax))
  check(aoa > 1.5 and aoa < 25, string.format("拉杆时机头比航迹高 %.1f°（飞机「吃」一下才转过去）", aoa))
  check(fst.spd < spd0, string.format("大迎角掉速：%.0f → %.0f", spd0, fst.spd))
  local q = fst.cf.Position
  check(q.X == q.X and q.Y == q.Y and q.Z == q.Z, "位置正常（没有算出 NaN）")
  T.key(Enum.KeyCode.W, false)
end

T.summary()
