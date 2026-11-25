-- 科技树暂用车换真模型（用户 11-25「需要模型自己找」）：python3 tools/mock/run.py tools/mock/wtreal.lua
--   ① 数据：T-80U / T-80B / T-80BVM、BMP-1、豹 2A6 / 2A4、豹 1 / 1A5、M60A3 / M60A1 十型——型号、炮、弹（弹道 + 穿深）、装甲、名字齐全；
--      原模型元数据（ImportedMeta 的 alias 指到真模型，炮塔转轴、炮耳轴照模型）；T-80U 的接触-5 爆反块（EraMeta）
--   ② 科技树：这几族不再借 T-90M / M1A2 / M10 / BMP-3；同族老型号「性能自己的、模型借同族的」（model）；别的还写「暂用」
--   ③ 试驾每一型：坐进去的就是这一型（TreeKey、型号对得上），T-80U 车上有爆反块
--   ④ 对着靶车开一炮（T-80U、BMP-1、M60A3）：服务器走战雷伤害，用的是这一型的弹
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, Enum = T.R, T.V3, T.Enum
local check = T.check

T.wtMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local RS = R.services.ReplicatedStorage
local TT = R.require(RS:FindFirstChild("TechTree"))
local VD = R.require(RS:FindFirstChild("VehDefs"))
local B = R.require(RS:FindFirstChild("Ballistics"))
local WD = R.require(RS:FindFirstChild("WtDamage"))
local IM = R.require(RS:FindFirstChild("ImportedMeta"))
local TM = R.require(RS:FindFirstChild("TankMods"))
local Lang = R.require(RS:FindFirstChild("Lang"))

print("① 数据")
local MODEL = { t80u = "t80u", t80b = "t80u", t80bvm = "t80u", bmp1 = "bmp1", leo2a6 = "leo2a6", leo2a4 = "leo2a6",
  leo1 = "leo1", leo1a5 = "leo1", m60a3 = "m60a3", m60a1 = "m60a3",
  -- E 11-25（用户「坦克单独找建模很多坦克没有建模」）：M551 换真模型，T-72 乌拉尔 / A / B 改借 T-72B3 的模型
  m551 = "m551", t72ural = "t72b3", t72a = "t72b3", t72b = "t72b3", leo2a7v = "leo2a7v", type10 = "type10" }
local bad = {}
local function near(a, b) return a and b and (a - b).Magnitude < 0.02 end
for id, key in pairs(MODEL) do
  local d = VD.get(id)
  if not d then table.insert(bad, id .. " 没有型号") else
    local w1 = d.weapons[1]
    if not VD.W[w1] then table.insert(bad, id .. " 炮 " .. tostring(w1)) end
    local list = B.GUN[w1]
    if d.cat == "tank" then
      if not list then table.insert(bad, id .. " 弹种表 " .. tostring(w1)) end
      for _, am in ipairs(list or {}) do
        if not B.AMMO[am] then table.insert(bad, id .. " 弹道 " .. am) end
        if not WD.AMMO[am] then table.insert(bad, id .. " 穿深 " .. am) end
      end
    elseif not WD.WPN[w1] then table.insert(bad, id .. " 穿深 " .. w1) end
    if not WD.PROF[id] then table.insert(bad, id .. " 装甲") end
    if IM.alias[id] ~= key then table.insert(bad, id .. " 元数据 alias " .. tostring(IM.alias[id])) end
    local info = IM.m[key]
    if not (info and info.tur and info.gun and info.credit) then table.insert(bad, id .. " 元数据 " .. key)
    else
      local tur = V3(info.tur[1], info.tur[2], info.tur[3])
      if not near(d.turret.pivot, tur) then table.insert(bad, id .. " 炮塔转轴没照模型") end
      if not near(d.gun.pivot, V3(info.gun[1], info.gun[2], info.gun[3]) - tur) then table.insert(bad, id .. " 炮耳轴没照模型") end
    end
    if not (Lang.zh["veh." .. id] and Lang.en["veh." .. id]) then table.insert(bad, id .. " 名字") end
  end
end
check(#bad == 0, "这几型的炮、弹、装甲、名字、原模型元数据齐全" .. (#bad > 0 and ("：" .. table.concat(bad, " ", 1, math.min(10, #bad))) or ""))
local L = TM.eraOf("t80u")
check(L ~= nil and L.b ~= nil and #L.b >= 10, "T-80U 原模型上量了爆反块（" .. tostring(L and L.b and #L.b) .. " 块）")
-- 同一族的两型不共用嵌套的表（variant 深拷）：改一型的武器表不会改到另一型
check(VD.get("t80b").turret ~= VD.get("t80u").turret and VD.get("t80b").weapons ~= VD.get("t80u").weapons, "同族两型各有一份炮塔、武器表")
check(VD.get("t80u").weapons[1] == "gun125u" and VD.get("t80b").weapons[1] == "gun125b" and VD.get("t80bvm").weapons[1] == "gun125r", "T-80 一族各打各的弹（3BM42 / 3BM22 / 3BM60）")
-- 车炮的穿深表按武器认（VehDefs.W 没有 id：WtDamage 反查键）：73 毫米 PG-15V 300 毫米破甲、30 毫米脱壳穿甲弹 70 毫米，不再落到通用 40 毫米榴弹
local p73 = WD.pen(VD.W.gun73, 0.3)
local p30 = WD.pen(VD.W.ac30, 0.3)
check(p73 >= 290 and p30 >= 60, string.format("车炮穿深按武器认（73 毫米 %d、30 毫米 %d 毫米）", math.floor(p73), math.floor(p30)))

print("② 科技树")
local want = {
  ru_t80u = { "t80u" }, ru_bmp1 = { "bmp1" }, de_leo2a6 = { "leo2a6" }, de_leo1 = { "leo1" }, us_m60a3 = { "m60a3" },
  ru_t80b = { "t80b", "t80u" }, ru_t80bvm = { "t80bvm", "t80u" }, de_leo2a4 = { "leo2a4", "leo2a6" }, de_leo1a5 = { "leo1a5", "leo1" }, us_m60a1 = { "m60a1", "m60a3" },
}
local tb = {}
for k, w in pairs(want) do
  local it = TT.get(k)
  if not it or it.play ~= w[1] or it.stand or it.model ~= w[2] then table.insert(tb, k .. "→" .. tostring(it and it.play) .. "/" .. tostring(it and it.model)) end
end
check(#tb == 0, "这几族开的是自己的型号（同族老型号借同族的模型）" .. (#tb > 0 and ("：" .. table.concat(tb, " ")) or ""))
local st = {}
for _, k in ipairs({ "cn_86", "ru_t64a", "de_leo2a7v", "us_m60", "jp_type74" }) do
  local it = TT.get(k)
  if not (it and it.stand) then table.insert(st, k) end
end
check(#st == 0 and TT.get("cn_86").play == "bmp1" and TT.get("ru_t64a").play == "t80b" and TT.get("jp_type74").play == "leo1",
  "别的还写「暂用」，改借这几型（86 式借 BMP-1、T-64 借 T-80B、74 式借豹 1）" .. (#st > 0 and ("：" .. table.concat(st, " ")) or ""))

print("③ 试驾每一型")
local me = T.join("P1", 9601, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
T.leaveMenu()
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
R.run(1)
local C = T.C
local function drive(key)
  T.act("testDrive", key)
  T.runUntil(function() return P.alive and P.vehicle ~= nil end, 20)
  return P.vehicle
end
local function leave()
  if P.vehicle then T.remoteAs(me, "Drive", { op = "exit" }) end
  T.runUntil(function() return not P.alive end, 15)
  R.run(1.5)
end
local function nearestDummy(e)
  local best, bd
  for _, x in ipairs(G.vehicles or {}) do
    if x.alive and x.testDummy then
      local dd = (x.root.Position - e.root.Position).Magnitude
      if not bd or dd < bd then best, bd = x, dd end
    end
  end
  return best, bd
end
local function fireAt(e)
  T.runUntil(function() return C.drive ~= nil end, 8)
  local sd = C.drive
  local x = nearestDummy(e)
  if not (sd and x) then return false, "没坐上 / 没靶车" end
  local cam = R.workspace.CurrentCamera
  local tc = x.root.Position + V3(0, 0.6, 0)
  for _ = 1, 14 do
    local dd = (tc - cam.CFrame.Position).Unit
    sd.camYaw = math.atan2(-dd.X, -dd.Z)
    sd.camPitch = math.asin(dd.Y)
    R.run(0.4)
  end
  local h0 = G.wtHits or 0
  if ONLY then
    local x2 = nearestDummy(e)
    print(string.format("  靶车 %s（%s），本车 %s，炮塔 ty %.2f gp %.2f", tostring(x2 and x2.root.Position), tostring(x2 and x2.def.id), tostring(e.root.Position), sd.ty or 0, sd.gp or 0))
  end
  R.as("client", function() C.driveTryFire() end)
  for _ = 1, 300 do
    R.run(1 / 60)
    if (G.wtHits or 0) > h0 then break end
  end
  R.run(0.5)
  return (G.wtHits or 0) > h0, G.wtLast
end
local KEYS = { "ru_bmp1", "ru_t80u", "ru_t80b", "de_leo2a6", "de_leo2a4", "de_leo1", "us_m60a3" }   -- BMP-1 放最前：后面几型打过靶车以后靶车位置会变
local FIRE = { ru_t80u = true, ru_bmp1 = true, us_m60a3 = true }
-- 只跑一型（排查用）：python3 tools/mock/run.py tools/mock/wtreal.lua only=ru_bmp1
local ONLY = TEST_ARGS:match("only=([%w_]+)")
if ONLY then KEYS, FIRE = { ONLY }, { [ONLY] = true } end
if ONLY then   -- 打印每一发的出膛位置、方向
  local launch0 = G.launch
  G.launch = function(sh, ...)
    if sh and sh.kind == "shell" then print(string.format("  出膛 %s 速度 %s", tostring(sh.pos), tostring(sh.vel))) end
    return launch0(sh, ...)
  end
end
for _, key in ipairs(KEYS) do
  local it = TT.get(key)
  local e = drive(key)
  local ok = e ~= nil and e.def and e.def.id == it.play and e.model:GetAttribute("TreeKey") == key
  check(ok, it.name .. "：坐进去的是 " .. tostring(e and e.def and e.def.id) .. "（应为 " .. it.play .. "）")
  if e and key == "ru_t80u" then
    check(e.era ~= nil and (e.era.n or 0) >= 10, "T-80U 车上的爆反块起作用（" .. tostring(e.era and e.era.n) .. " 块）")
  end
  if e and FIRE[key] then
    local hit, last = fireAt(e)
    check(hit, it.name .. "：对靶车开一炮，服务器走了战雷伤害" .. (last and ("（" .. tostring(last.r) .. "，穿深 " .. tostring(last.pen and math.floor(last.pen)) .. " 毫米）") or ""))
  end
  leave()
  check(not P.alive and not P.inTest, it.name .. "：下车回机库")
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 800))
T.summary()
