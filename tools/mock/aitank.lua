-- 电脑开的坦克像真人车组（模拟器）：python3 tools/mock/run.py tools/mock/aitank.lua
--   用户 11-28 晚「然后目前人机坦克太假」（AIVeh.lua）：
--   ① 车速有惯性：起步按型号的加速慢慢上来（半秒还没到三成），开一阵才到快的；不再一下子满速
--   ② 守在据点、敌方的车在侧面：先把车头转过去对着它（正面装甲），停稳了、瞄一会儿（1.5～3 秒）才开第一炮
--   ③ 打了就躲：开完一炮倒回去二三十格（车头还对着敌人）躲着装弹，再开出来
--   ④ 行进间不开主炮（短停射击）：开着的时候炮不响
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3 = T.R, T.V3
local check = T.check

T.wtMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true   -- 自己派的电脑车不要来搅（下面手动摆两辆、手动让它想）
G.Config.Bots.minPerTeam = 0
G.Config.Round.prep = 4   -- 准备阶段电脑车原地待命（不开不打）：等开战再测
T.runUntil(function() return G.worldReady end, 900)
T.join("P1", 9931, true)
T.runUntil(function() return G.round and G.round.phase == "battle" end, 120)
local Map = G.Map
local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))
local VEH, TGT = "leo2a6", "t72b"
local d, dt = VD.get(VEH), VD.get(TGT)
check(d ~= nil and dt ~= nil, "有 " .. VEH .. "、" .. TGT)
if not d or not dt then T.summary() return end
local function flat(v) return V3(v.X, 0, v.Z) end
local function yawOf(e) local lv = e.root.CFrame.LookVector return math.deg(math.atan2(-lv.X, -lv.Z)) end
local function rel(a) return (a + 180) % 360 - 180 end

-- 找一块平的、四周开阔的地方（两辆车互相看得见）
local spot = nil
for _, pp in ipairs(Map.POINTS) do
  local x, z = pp.x or (pp.pos and pp.pos.X), pp.z or (pp.pos and pp.pos.Z)
  if x and z then
    for k = 0, 23 do
      local a = k / 24 * math.pi * 2
      local sx, sz = x + math.cos(a) * 300, z + math.sin(a) * 300
      local tx, tz = sx, sz - 260
      if Map.isLand(sx, sz) and Map.isLand(tx, tz) and Map.slope(sx, sz) < 0.12 and Map.slope(tx, tz) < 0.2
        and not (Map.bldAt and (Map.bldAt(sx, sz, 30) or Map.bldAt(tx, tz, 20) or Map.bldAt(sx, sz + 40, 20)))
        and Map.lineClear(V3(sx, Map.ground(sx, sz) + 8, sz), V3(tx, Map.ground(tx, tz) + 3, tz), 20) then
        spot = { x = sx, z = sz, tx = tx, tz = tz, goal = pp.id }
        break
      end
    end
  end
  if spot then break end
end
check(spot ~= nil, "找到一块开阔的平地")
if not spot then T.summary() return end

local function newAi(team, x, z, look, state, extra)
  local e = G.newVehicle(team, VEH, G.vehBaseAt(d, x, z, look))
  e.ai = { state = state, goal = spot.goal, land = nil, home = e.root.CFrame.Position, hold = e.root.CFrame.Position, tgt = nil, seekT = 0, aimT = 0,
    stuckT = 0, lastP = e.root.CFrame.Position, sideT = 0, holdT = os.clock() + 1e6, crew = { name = "AI" }, v = 0, shotN = 0, lastShot = -9, scootT = 0 }
  for k, v in pairs(extra or {}) do e.ai[k] = v end
  e.model:SetAttribute("AI", true)
  return e
end

print("① 起步有惯性")
local mv = newAi("atk", spot.x + 120, spot.z + 300, V3(0, 0, -1), "retreat", {})
mv.ai.home = V3(spot.x + 120, 0, spot.z + 300 - 1200)   -- 往前一千二百格「撤」：一直开
local v05, v4 = nil, nil
for i = 1, 40 do
  G.aiVehThink(mv, 0.1)
  R.run(0.1)
  if i == 5 then v05 = mv.ai.v end
end
v4 = mv.ai.v
print(string.format("   0.5 秒 %.1f、4 秒 %.1f 格/秒（最快 %.0f）", v05 or -1, v4 or -1, d.speed))
check(v05 and v05 < d.speed * 0.3, string.format("半秒还没到三成（%.1f 格/秒）", v05 or -1))
check(v4 and v4 > v05 + 10, string.format("开一阵才快起来（4 秒 %.1f 格/秒）", v4 or -1))
-- 刹车：改成就地守着（钉在现在的位置）——刹停也要一会儿
mv.ai.state, mv.ai.pin, mv.ai.hold = "hold", true, mv.root.CFrame.Position
local vb = mv.ai.v
G.aiVehThink(mv, 0.1)
R.run(0.1)
check(mv.ai.v > 0 and mv.ai.v < vb, string.format("刹车也要一会儿（%.1f → %.1f 格/秒，不是一下子停住）", vb, mv.ai.v))

print("② 守着、敌方的车在侧面：车头转过去、停稳瞄一会儿才开炮")
local tgt = G.newVehicle("def", TGT, G.vehBaseAt(dt, spot.tx, spot.tz, V3(0, 0, 1)))
local ai = newAi("atk", spot.x, spot.z, V3(1, 0, 0), "hold", { pin = true })   -- 车头朝东，敌人在北边（侧面 90°）；钉在这儿守着
local bearing = math.deg(math.atan2(-(spot.tx - spot.x), -(spot.tz - spot.z)))
R.run(0.3)
local firstAt, faced, movedWhileFire = nil, nil, false
local t0 = os.clock()
local shots0 = 0
local fired = {}
local onFx0 = G.fx
G.fx = function(e, ...)
  if type(e) == "table" and e.k == "vfire" and e.id == ai.id then
    fired[#fired + 1] = { t = os.clock() - t0, v = ai.ai.v }
  end
  return onFx0(e, ...)
end
local posAtShot, backMax = nil, 0
for i = 1, 140 do
  G.aiVehThink(ai, 0.1)
  R.run(0.1)
  if not faced and math.abs(rel(yawOf(ai) - bearing)) < 26 then faced = (os.clock() - t0) end
  if #fired > shots0 then
    shots0 = #fired
    if not firstAt then firstAt = fired[1].t posAtShot = ai.root.CFrame.Position end
    if math.abs(fired[#fired].v or 0) > 2 then movedWhileFire = true end
  end
  if posAtShot then
    local away = flat(ai.root.CFrame.Position - posAtShot).Magnitude
    if away > backMax then backMax = away end
  end
  if not tgt.alive then break end
end
G.fx = onFx0
print(string.format("   车头转过去 %s 秒、第一炮 %s 秒、一共 %d 炮、打完往后倒最远 %.0f 格", tostring(faced and string.format("%.1f", faced)),
  tostring(firstAt and string.format("%.1f", firstAt)), #fired, backMax))
check(faced ~= nil, "车头转过去对着敌人（正面装甲）")
check(firstAt ~= nil and firstAt >= 1.4, string.format("新目标先瞄一会儿才开第一炮（%s 秒）", tostring(firstAt and string.format("%.1f", firstAt))))
check(not movedWhileFire, "开炮的时候是停稳的（短停射击）")
print("③ 打了就躲")
check(backMax > 12, string.format("开完一炮倒回去躲着装弹（最远倒了 %.0f 格）", backMax))
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 800))
T.summary()
