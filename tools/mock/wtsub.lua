-- 不同弹种打进车里效果不一样（模拟器）：python3 tools/mock/run.py tools/mock/wtsub.lua
--   用户 11-27「不同弹种击中的 X 光效果不一样」「不光不同动画还要不同效果」：
--   同一辆 T-72B3、同一个位置（车体侧面中间）、同一个方向，每种弹各打 40 发（每发一辆新车），比车里的结果——
--   ① 长杆（fs）：伤得深——弹道上更远的乘员 / 模块也伤；破片锥窄
--   ② 全口径（ap）：塞子 + 宽而重的破片——一发伤到的东西比长杆多
--   ③ 穿甲爆破（aphe）：钻进去炸开——乘员死得最多
--   ④ 破甲射流（heat）：起火比动能弹多
--   ⑤ 碎甲（hesh）：薄装甲没打穿也能把里面的人伤了（内壁崩落）；倾角影响小
--   ⑥ X 光：服务器发的 xr.sub 对；客户端按弹种放慢放（字幕写弹种）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8302, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
R.run(1)
local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))
local W = R.require(R.services.ReplicatedStorage:FindFirstChild("WtDamage"))
local Map = G.Map
local VEH = "t72b3"
local def = VD.get(VEH)
local bx, bz = Map.CAMP.x + 60, Map.CAMP.z + 60
-- 截住服务器发给开炮的人的命中消息（r：pen 打穿 / np 没打穿 / ric 跳弹；xr.sub 弹种）
local P = G.P[me]
local lastHit = nil
G.R.Drive.OnClientEvent:Connect(function(m)
  if type(m) == "table" and m.op == "wtHit" then lastHit = m end
end)

-- 一发：新车、从车的右侧（+X）正对车体中间打进去；返回乘员死 / 伤、模块坏、起火、殉爆、xr
local function shoot(am, opt)
  opt = opt or {}
  local e = G.newVehicle("atk", VEH, G.vehBaseAt(def, bx, bz, V3(0, 0, -1)))
  R.run(0.05)
  local base = e.root.CFrame * CF(0, -def.H / 2, 0)   -- 同 Wt.lua baseOf：车底中心
  local hy = (def.hullH or def.H * 0.55) * (opt.y or 0.8)   -- 默认打在炮塔座圈下面、车长炮长那一层（避开车底的转盘弹药架）
  local ang = math.rad(opt.ang or 0)
  local dirL = V3(-math.cos(ang), 0, math.sin(ang))   -- 车体系：从右往左打（ang 斜着），弹道穿过车体中线（z = opt.z）
  local pL = V3(def.W / 2, hy, (opt.z or 0) - math.tan(ang) * def.W / 2)
  local pos = base:PointToWorldSpace(pL)
  local dir = base:VectorToWorldSpace(dirL)
  local w = { ammo = am, kind = "shell" }
  local s = { w = w, vel = dir * 1500, p0 = pos - dir * 1000, kind = "shell", src = { P = P, name = "P1" } }
  lastHit = nil
  local res = { Position = pos, Normal = base:VectorToWorldSpace(V3(1, 0, 0)), Instance = e.root }
  local r = G.wtShellHit(e, s, res)
  R.run(0.03)   -- 等命中消息送到
  local S = e.wt
  local dead, hurt, mods, deepMod = 0, 0, 0, 0
  local yaw = e.ty or 0
  local function depth(it) return (W.center(def, yaw, it) - pL):Dot(dirL) end   -- 伤到的东西离入口多深（顺着弹道）
  for _, c in ipairs(S and S.crew or {}) do
    if c.hp <= 0 then dead = dead + 1 elseif c.hp < 100 then hurt = hurt + 1 end
    if c.hp < 100 then deepMod = math.max(deepMod, depth(c.it)) end
  end
  for _, c in ipairs(S and S.mods or {}) do
    if c.hp < 100 and not c.it.ext then
      mods = mods + 1
      deepMod = math.max(deepMod, depth(c.it))
    end
  end
  local out = { r = lastHit and lastHit.r, sub = lastHit and lastHit.xr and lastHit.xr.sub, dead = dead, hurt = hurt, mods = mods, deep = deepMod, fire = (S and S.fireT ~= nil) or false, boom = not e.alive }
  if e.alive then G.removeEnt(e) end
  R.run(0.05)
  return out
end
-- 打法：opt 给了就每发同一处；没给就沿车体侧面撒 10 个点（前后 5 处 × 高低 2 层），每点 n / 10 发
local SPOTS = {}
for _, zk in ipairs({ -0.3, -0.15, 0, 0.15, 0.3 }) do
  for _, yk in ipairs({ 0.6, 0.85 }) do table.insert(SPOTS, { z = def.L * zk, y = yk }) end
end
local function avg(am, n, opt)
  local t = { dead = 0, hurt = 0, mods = 0, deep = 0, fire = 0, boom = 0, pen = 0 }
  for i = 1, n do
    math.randomseed(1000 + i)
    local o = shoot(am, opt or SPOTS[(i - 1) % #SPOTS + 1])
    t.dead = t.dead + o.dead t.hurt = t.hurt + o.hurt t.mods = t.mods + o.mods t.deep = t.deep + o.deep
    t.fire = t.fire + (o.fire and 1 or 0)
    t.boom = t.boom + (o.boom and 1 or 0)
    t.pen = t.pen + ((o.r == "pen") and 1 or 0)
    t.sub = o.sub
  end
  for k, v in pairs(t) do if type(v) == "number" then t[k] = v / n end end
  print(string.format("    %-10s（%s）打穿 %.0f%% 死 %.2f 伤 %.2f 模块 %.2f 最深 %.1f 格 起火 %.0f%% 击毁 %.0f%%", am, tostring(t.sub), t.pen * 100, t.dead, t.hurt, t.mods, t.deep, t.fire * 100, t.boom * 100))
  return t
end

-- 弹种：照 WtDamage 的表推（Wt.lua xrSub）；要测的几种表里没有的（碎甲、全口径穿甲）临时加进 W.AMMO
W.AMMO.test_ap = { p0 = 300, fall = 40, t = "ke", spall = 20, n = 14, core = 2.4, sub = "ap" }
W.AMMO.test_fs = { p0 = 300, fall = 30, t = "ke", spall = 16, n = 14, core = 3.0, sub = "fs" }
W.AMMO.test_aphe = { p0 = 300, fall = 45, t = "ke", spall = 20, n = 14, core = 2.4, sub = "aphe" }
W.AMMO.test_heat = { p0 = 300, t = "ce", spall = 20, n = 12, core = 2.2 }
W.AMMO.test_hesh = { p0 = 130, t = "he", spall = 20, n = 14, core = 0, blast = 2.0, sub = "hesh" }
local N = 40
print("① ～ ④ 车体侧面撒 10 个点，各打 " .. N .. " 发（T-72B3）")
local fs = avg("test_fs", N)
local ap = avg("test_ap", N)
local aphe = avg("test_aphe", N)
local heat = avg("test_heat", N)
check(fs.pen > 0.9 and ap.pen > 0.9 and aphe.pen > 0.9 and heat.pen > 0.9, "都打穿了")
print(string.format("  伤到的最深处：长杆 %.1f 格、全口径 %.1f 格、射流 %.1f 格", fs.deep, ap.deep, heat.deep))
check(ap.mods > fs.mods, string.format("全口径打坏的模块比长杆多（塞子、宽而重的破片：%.2f > %.2f）", ap.mods, fs.mods))
check(aphe.dead + aphe.hurt > math.max(ap.dead + ap.hurt, fs.dead + fs.hurt, heat.dead + heat.hurt) and aphe.mods > ap.mods,
  string.format("穿甲爆破在车里炸开：乘员伤亡、模块损坏都最多（%.2f / %.2f）", aphe.dead + aphe.hurt, aphe.mods))
print("  打车尾（发动机、油箱那一段）比起火")
local fsR = avg("test_fs", N, { z = def.L * 0.3, y = 0.55 })
local heatR = avg("test_heat", N, { z = def.L * 0.3, y = 0.55 })
check(heatR.fire > fsR.fire, string.format("破甲射流更容易起火（%.0f%% > %.0f%%）", heatR.fire * 100, fsR.fire * 100))

print("⑤ 碎甲弹")
local hesh = avg("test_hesh", N)
check(hesh.sub == "hesh" and hesh.pen > 0.5 and (hesh.dead + hesh.hurt) > 0.5, string.format("装甲没打穿也伤了里面的人（内壁崩落，伤亡 %.2f）", hesh.dead + hesh.hurt))
local hesh40 = avg("test_hesh", 20, { ang = 40 })
check(hesh40.pen >= 0.5 and (hesh40.dead + hesh40.hurt) > 0.3, string.format("斜 40° 照样崩得开（%.0f%%）", hesh40.pen * 100))
check(fs.sub == "fs" and ap.sub == "ap" and aphe.sub == "aphe" and heat.sub == "heat", "服务器发的弹种对（fs / ap / aphe / heat）")

print("⑥ X 光")
local x = { p = { 1, 2, 0 }, d = { -1, 0, 0 }, ty = 0, seed = 77, half = 18, n = 14, core = 2.6, sub = "aphe" }
local m = { op = "wtHit", id = 0, veh = VEH, r = "pen", kill = false, parts = { { k = "gnr", kind = "crew", s = 0 } }, pen = 300, arm = 80, dist = 900, xr = x }
G.R.Drive:FireClient(me, m)
R.run(1.6)
local info
for _, d in ipairs(me.PlayerGui:GetDescendants()) do if d.Name == "XrInfo" then info = d end end
check(info and string.find(info.Text, "穿甲爆破", 1, true) ~= nil, "穿甲爆破弹的字幕：「" .. tostring(info and info.Text) .. "」")
x.sub, x.seed = "hesh", 78
G.R.Drive:FireClient(me, m)
R.run(1.6)
check(info and string.find(info.Text, "碎甲", 1, true) ~= nil, "碎甲弹的字幕：「" .. tostring(info and info.Text) .. "」")
x.sub, x.seed = "fs", 79
G.R.Drive:FireClient(me, m)
R.run(1.6)
check(info and string.find(info.Text, "长杆", 1, true) ~= nil, "长杆弹的字幕：「" .. tostring(info and info.Text) .. "」")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
