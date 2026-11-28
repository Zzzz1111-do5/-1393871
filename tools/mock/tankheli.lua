-- 坦克炮打直升机（模拟器）：python3 tools/mock/run.py tools/mock/tankheli.lua
--   用户 11-28「然后坦克炮打到直升机为什么直升机还有可能活」（Ents.lua airOneShot）——原来照血算：120 毫米炮一发 640 × 对空 0.8 = 512，
--   阿帕奇 1000 血，打在机身中段（发动机、油箱那块）只掉一半血、部件也没打断，照样飞走：
--   ① 坦克炮穿甲弹（钢针）打在直升机机身中段：一发打下来  ② 榴弹、破甲弹：一样  ③ 反坦克导弹直接打中：一样
--   ④ 30 毫米机炮一发：不会一发打下来（照旧按血、按部件）  ⑤ 自己人的坦克炮：不伤
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check

T.wtMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
local Map = G.Map
local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))
local AD = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs"))

-- 一块平地（直升机停在上面，炮从 300 格外平着打过去）
local px, pz
for r = 0, 6000, 150 do
  for a = 0, 330, 30 do
    local x, z = math.cos(math.rad(a)) * r, math.sin(math.rad(a)) * r
    if Map.height(x, z) > 4 and Map.slope(x, z) < 0.08 and not (Map.bldAt and Map.bldAt(x, z, 60)) then px, pz = x, z break end
  end
  if px then break end
end
check(px ~= nil, "找到一块平地")
if not px then T.summary() return end

local n = 0
local function heli(team)
  n = n + 1
  local x, z = px + n * 80, pz
  local d = AD.get("ah64e")
  local y = Map.ground(x, z) + (d.gearH or 5)
  local e = G.spawnAircraft(team, "ah64e", R.CFrame.lookAt(V3(x, y, z), V3(x, y, z - 10)), nil, nil, nil)
  R.run(0.3)
  return e
end
-- 从直升机正东 300 格、机身中段的高度平着打过去（打在发动机、油箱那块：原来这儿挨一发照样飞）
local function shoot(e, w, extra)
  local c = e.root.CFrame.Position
  local from = c + V3(300, 0, 0)
  local dir = (c - from).Unit
  local s = { kind = "shell", pos = from, vel = dir * 1500, grav = false, w = w, src = { team = (e.team == "atk") and "def" or "atk", name = "测试" }, ignore = {}, life = 4 }
  for k, v in pairs(extra or {}) do s[k] = v end
  if s.kind == "missile" then s.vel = dir * 600 end
  local hp0 = e.hp
  G.launch(s)
  for _ = 1, 20 do R.run(0.05) if not e.alive then break end end
  return hp0
end

print("① 坦克炮穿甲弹（钢针）打在机身中段")
local h1 = heli("def")
check(h1 ~= nil and h1.alive and h1.wta ~= nil, "停着一架阿帕奇（" .. tostring(h1 and h1.hp) .. " 血）")
local k0 = G.airOneShots or 0
shoot(h1, VD.W.gun120, { cls = "ap" })
check(not h1.alive, "120 毫米钢针一发：打下来了")
check((G.airOneShots or 0) > k0, "按坦克炮直接命中判毁（airOneShot）")

print("② 榴弹、破甲弹")
local h2 = heli("def")
shoot(h2, VD.W.gun125, { cls = "he" })
check(not h2.alive, "125 毫米榴弹一发：打下来了")
local h3 = heli("def")
shoot(h3, VD.W.gun105, { cls = "heat" })
check(not h3.alive, "105 毫米破甲弹一发：打下来了")

print("③ 反坦克导弹直接打中")
local h4 = heli("def")
shoot(h4, VD.W.kornet, { kind = "missile" })
check(not h4.alive, "「短号」反坦克导弹直接打中：打下来了")

print("④ 30 毫米机炮一发")
local h5 = heli("def")
local hp5 = shoot(h5, VD.W.ac30, { cls = "he" })
check(h5.alive and h5.hp < hp5, string.format("一发 30 毫米：掉血（%.0f → %.0f）、没有一发打下来", hp5, h5.hp))

print("⑤ 自己人的坦克炮")
local h6 = heli("def")
local c6 = h6.root.CFrame.Position
local from = c6 + V3(300, 0, 0)
local hp6 = h6.hp
G.launch({ kind = "shell", pos = from, vel = (c6 - from).Unit * 1500, grav = false, w = VD.W.gun120, cls = "ap", src = { team = "def", name = "测试" }, ignore = {}, life = 4 })
for _ = 1, 20 do R.run(0.05) end
check(h6.alive and h6.hp == hp6, "同一队的坦克炮打中：不伤（" .. hp6 .. " → " .. h6.hp .. "）")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 800))
T.summary()
