-- 坦克开炮、炮弹打地面的声音和弹坑（模拟器）：python3 tools/mock/run.py tools/mock/tankgunsnd.lua
--   用户 11-28 晚「坦克开炮声音 炮弹击中地面的声音和效果没有还原战雷」（SoundLib.lua 的 gunCrack / gunSub / gunTail / gunFar / gunMech /
--   dirtHit / dirtBlast / debrisRain，Fx.lua tankGunSnd、kinSound、boomSound）：
--   ① 别人在镜头旁开炮（vfire f = tank）：炸裂 + 本体 + 低频冲击 + 回声四层，回声晚 0.15 秒以上；截取段照 SoundLib 的 reg
--   ② 一公里外：多了远处那一记闷响、炸裂轻了；两公里外：只剩远处那一记 + 回声；都按声速晚到（每秒 960 格）
--   ③ 自己在车里 / 炮长镜里开炮：车内录音 + 低频 + 压掉高音的炸裂 + 0.3 秒后炮闩的咔嗒
--   ④ 小口径（57 毫米）放得比 120 毫米快（脆）
--   ⑤ 穿甲弹打在镜头前的土里：土爆真录音 + 碎土落下，地上一个小弹坑；一公里外画面只剩一小团土，声音照样有（按声速晚到、吃掉高音）
--   ⑥ 榴弹炸在土里：爆炸 + 土爆 + 近处碎土；炸在钢甲上不叠土爆
--   ⑦ 录音没载上：照旧放叠出来的（不会没声音）
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)
local R, V3 = T.R, T.V3
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 8751, true)
T.runUntil(function() return G.round ~= nil end, 30)
T.leaveMenu()
R.run(1)
local C = T.C
local RS = R.services.ReplicatedStorage
local SL = R.require(RS:FindFirstChild("SoundLib"))
local cam = R.workspace.CurrentCamera

-- 模拟器里没有真的预载：当作这些录音都载上了
local REAL = C.realSoundState()
local KEYS = { "tankGun", "tankGunIn", "gunCrack", "gunSub", "gunTail", "gunFar", "gunMech", "dirtHit", "dirtBlast", "debrisRain", "boomS", "boomM", "boomL" }
local KEYOF = {}
local function loadAll()
  for _, key in ipairs(KEYS) do
    local l = {}
    for _, id in ipairs(SL[key].ids) do
      local sid = "rbxassetid://" .. id
      l[#l + 1] = sid
      KEYOF[sid] = KEYOF[sid] or key
    end
    REAL[key] = l
  end
end
loadAll()
for _, key in ipairs(KEYS) do check(SL[key] ~= nil and #SL[key].ids > 0, "SoundLib 有 " .. key) end

-- 记下每一次放声音：哪几层、每层是哪条录音（键）、截哪一段、晚多少
local calls = {}
local sfx0 = C.sfx
C.sfx = function(def, pos, o)
  calls[#calls + 1] = { def = def, pos = pos, o = o or {} }
  return sfx0(def, pos, o)
end
local function layers(c)
  local out, byKey = {}, {}
  if type(c.def) ~= "table" then return out, byKey end
  for _, L in ipairs(c.def) do
    local k = KEYOF[L.id] or "?"
    out[#out + 1] = k
    byKey[k] = L
  end
  return out, byKey
end
local function last() return calls[#calls] end
local function camAt(off) return cam.CFrame.Position + off end
local function has(list, k) for _, x in ipairs(list) do if x == k then return true end end return false end

print("① 别人在镜头旁开炮")
local n0 = #calls
local M = camAt(V3(0, 0, -25))
R.as("client", function() C.onFx({ { k = "vfire", p = M, d = V3(0, 0, -1), f = "tank", id = "e9001" } }) end)
R.run(0.1)
local c1 = calls[n0 + 1]
local l1, b1 = layers(c1 or {})
print("   层：" .. table.concat(l1, "、"))
check(c1 ~= nil and has(l1, "gunCrack") and has(l1, "tankGun") and has(l1, "gunSub") and has(l1, "gunTail") and not has(l1, "gunFar"),
  "炸裂 + 本体 + 低频冲击 + 回声（近处没有远处那一记）")
check(b1.gunTail and (b1.gunTail.delay or 0) >= 0.15, "回声晚 0.15 秒以上（" .. tostring(b1.gunTail and b1.gunTail.delay) .. "）")
local sub = b1.gunSub
local sid = sub and tonumber(sub.id:match("%d+$"))
check(sub and sub.reg and SL.gunSub.reg[sid] and math.abs(sub.reg[1] - SL.gunSub.reg[sid][1]) < 1e-6, "低频那一层按 SoundLib 截（" .. tostring(sub and sub.reg and sub.reg[1]) .. " 秒起）")
check(b1.gunTail and (b1.gunTail.rmax or 0) >= 6000, "回声传得远（" .. tostring(b1.gunTail and b1.gunTail.rmax) .. " 格）")
check(c1 and math.abs((c1.o.delay or 0) - 25 / 960) < 0.01, string.format("按声速晚到（%.3f 秒）", c1 and c1.o.delay or -1))
R.run(0.5)
local nSnd = 0
for _, d in ipairs(R.workspace:GetDescendants()) do
  if d.ClassName == "Sound" and KEYOF[d.SoundId] then nSnd = nSnd + 1 end
end
check(nSnd >= 3, "场景里真的放了这几条录音（" .. nSnd .. " 个 Sound）")

print("② 远处开炮")
n0 = #calls
C.tankGunSnd(camAt(V3(0, 0, -2800)), 2800, 1, false)
local l2, b2 = layers(calls[n0 + 1] or {})
print("   一公里（2800 格）：" .. table.concat(l2, "、"))
check(has(l2, "gunFar") and has(l2, "gunCrack") and has(l2, "gunTail"), "一公里外：多了远处那一记闷响，还有一点炸裂、回声")
check(b2.gunCrack and b1.gunCrack and b2.gunCrack.vol < b1.gunCrack.vol * 0.7, "炸裂轻了")
check((b2.gunCrack and b2.gunCrack.hc or 0) <= -20, "高音吃掉（" .. tostring(b2.gunCrack and b2.gunCrack.hc) .. " 分贝）")
check(math.abs((calls[n0 + 1].o.delay or 0) - 2800 / 960) < 0.01, string.format("晚到 %.2f 秒", calls[n0 + 1].o.delay or -1))
n0 = #calls
C.tankGunSnd(camAt(V3(0, 0, -5600)), 5600, 1, false)
local l3 = layers(calls[n0 + 1] or {})
print("   两公里（5600 格）：" .. table.concat(l3, "、"))
check(has(l3, "gunFar") and has(l3, "gunTail") and not has(l3, "gunCrack") and not has(l3, "tankGun"), "两公里外：只剩远处那一记 + 回声")

print("③ 自己在车里 / 炮长镜里开炮")
n0 = #calls
C.tankGunSnd(camAt(V3(0, 0, -3)), 3, 1, true)
local l4, b4 = layers(calls[n0 + 1] or {})
print("   层：" .. table.concat(l4, "、"))
check(has(l4, "tankGunIn") and has(l4, "gunSub") and has(l4, "gunMech") and not has(l4, "tankGun"), "车内录音 + 低频 + 炮闩（不放车外那条）")
check(b4.gunCrack and (b4.gunCrack.hc or 0) <= -15, "炸裂压掉了高音（闷）")
check(b4.gunMech and (b4.gunMech.delay or 0) >= 0.28, string.format("炮闩、抛壳 0.3 秒后响（%.2f）", b4.gunMech and b4.gunMech.delay or -1))

print("④ 口径")
n0 = #calls
C.tankGunSnd(camAt(V3(0, 0, -25)), 25, 0.62, false)
local _, b5 = layers(calls[n0 + 1] or {})
n0 = #calls
C.tankGunSnd(camAt(V3(0, 0, -25)), 25, 1, false)
local _, b6 = layers(calls[n0 + 1] or {})
check(b5.tankGun and b6.tankGun and b5.tankGun.s[1] > b6.tankGun.s[1] * 1.1, string.format("57 毫米放得快（%.2f 对 %.2f）", b5.tankGun and b5.tankGun.s[1] or 0, b6.tankGun and b6.tankGun.s[1] or 0))
check(b5.gunCrack and b6.gunCrack and b5.gunCrack.vol < b6.gunCrack.vol, "也轻一点")

print("⑤ 穿甲弹打在土里")
-- 镜头摆到地面上（机库的镜头在九百格高的大厅里：离地面太远，近处的碎土声不会放）
local Map = G.Map
local B = Map.BASES.atk
local bx, bz = B.x, B.z - 900
local cp = V3(bx, Map.height(bx, bz) + 6, bz)
local function groundAt(dx, dz)
  local x, z = cp.X + dx, cp.Z + dz
  return V3(x, Map.height(x, z), z)
end
local function camHere() cam.CFrame = R.CFrame.lookAt(cp, cp + V3(0, -0.2, -1)) end
camHere()
local sc0 = C.vfx.stat.scorch
n0 = #calls
camHere()
local gp = groundAt(0, -40)
C.kineticHit(gp, V3(0, 1, 0), V3(0, -0.4, -1).Unit, "d", 2.1)
local found, deb = nil, nil
for i = n0 + 1, #calls do
  local l, b = layers(calls[i])
  if has(l, "dirtHit") then found = calls[i] deb = b.debrisRain end
end
check(found ~= nil, "镜头前四十格：土爆的真录音")
check(deb ~= nil and (deb.delay or 0) >= 0.2, "再落一阵碎土（晚 " .. tostring(deb and deb.delay) .. " 秒）")
check(C.vfx.stat.scorch > sc0, "地上留一个小弹坑")
n0 = #calls
camHere()
local fp = groundAt(0, -2600)
C.kineticHit(fp, V3(0, 1, 0), V3(0, -0.4, -1).Unit, "d", 2.1)
local farC = nil
for i = n0 + 1, #calls do
  local l = layers(calls[i])
  if has(l, "dirtHit") then farC = calls[i] end
end
check(farC ~= nil, "九百多米外（画面只剩一小团土）：声音照样有")
check(farC and (farC.o.delay or 0) > 2.5 and (farC.o.hiCut or 0) <= -20, string.format("按声速晚到 %.1f 秒、吃掉高音（%s）", farC and farC.o.delay or -1, tostring(farC and farC.o.hiCut)))

print("⑥ 榴弹")
camHere()
n0 = #calls
C.boom(groundAt(0, -60) + V3(0, 0.5, 0), 1, nil, "d", V3(0, -0.5, -1).Unit, "he")
local he = nil
for i = n0 + 1, #calls do
  local l = layers(calls[i])
  if has(l, "dirtBlast") then he = l end
end
check(he ~= nil and (has(he, "boomS") or has(he, "boomM")) and has(he, "debrisRain"), "炸在土里：爆炸 + 土爆 + 碎土（" .. table.concat(he or {}, "、") .. "）")
camHere()
n0 = #calls
C.boom(groundAt(0, -60) + V3(0, 3, 0), 1, nil, "a", V3(0, -0.5, -1).Unit, "he")
local onMetal = false
for i = n0 + 1, #calls do
  local l = layers(calls[i])
  if has(l, "dirtBlast") then onMetal = true end
end
check(not onMetal, "炸在钢甲上：不叠土爆")

print("⑦ 录音没载上")
for _, key in ipairs(KEYS) do REAL[key] = nil end
n0 = #calls
C.tankGunSnd(camAt(V3(0, 0, -25)), 25, 1, false)
local c7 = calls[n0 + 1]
check(c7 ~= nil and type(c7.def) == "table" and #c7.def >= 2 and KEYOF[c7.def[1].id] == nil, "坦克炮照旧放叠出来的那几层")
camHere()
n0 = #calls
C.kineticHit(gp, V3(0, 1, 0), V3(0, -0.4, -1).Unit, "d", 2.1)
check(#calls > n0, "穿甲弹打地照旧有声")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 800))
T.summary()
