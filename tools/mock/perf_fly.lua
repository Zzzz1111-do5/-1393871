-- 开飞机的卡顿排查（模拟器）：python3 tools/mock/run.py tools/mock/perf_fly.lua [秒数，默认 8] [id=j20] [map=city]
--   用户 11-28「然后现在开飞机太卡了」：滑跑起飞、爬到几百格高，开着加力平飞一段，量客户端每个每帧回调的 CPU、
--   每帧建 / 删 / 改属性多少次（哪一行改得最多）、场景里有多少光带 / 粒子 / 拖尾（渲染的负担：尾焰、热浪、导弹尾烟……）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local K = dofile(MOCK_DIR .. "/perfkit.lua")(T)
local secs = tonumber(TEST_ARGS:match("^%s*(%d+)") or TEST_ARGS:match("%s(%d+)%s*$") or "") or 8
local ID = TEST_ARGS:match("id=(%w+)") or "j20"
T.mapName = TEST_ARGS:match("map=(%w+)")
local G = T.boot()
G.fortsHold = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 6311, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
R.run(1)
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
T.act("deploy", "rifle", G.Map.LANDONLY and "baseAir" or "af2")
R.run(2)
local A2 = G.Map.AFIELD2 or G.Map.AIRFIELD
local x, z = A2.x + 300, A2.z - A2.wid / 2 - 220
local gy = G.airSurface(x, z)
local e = G.spawnAircraft("atk", ID, CF(x, gy + 6, z), nil, P)
if me.Character then me.Character:PivotTo(CF(x + 20, gy + 3.5, z)) end
R.run(0.3)
T.act("enterVeh", e.id)
R.run(1.2)
local st = C.fly
check(st ~= nil and st.pilot, "坐进了 " .. ID)
if not st then T.summary() return end
if C.flyMouseAim then C.flyMouseAim(false) end   -- 纯键盘（不按键就是平飞）
T.key(Enum.KeyCode.LeftShift, true)
T.runUntil(function() return st.spd >= e.def.vRot end, 40)
T.key(Enum.KeyCode.S, true)
T.runUntil(function() return not st.ground end, 10)
R.run(3)
T.key(Enum.KeyCode.S, false)
R.run(4)
T.key(Enum.KeyCode.LeftShift, false)
st.thr, st.thrE = 110, 110   -- 加力
st.spd = e.def.vMil * 0.85
st.vel = st.vdir * st.spd
R.run(2)
local pos = st.cf and st.cf.Position or V3(0, 0, 0)
print(string.format("  高度 %.0f 格、速度 %.0f 格 / 秒、油门 %d", pos.Y - G.Map.height(pos.X, pos.Z), st.spd or 0, st.thr or 0))
local function countFx()
  local c = { Beam = 0, BeamOn = 0, ParticleEmitter = 0, PEOn = 0, Trail = 0, TrailOn = 0, PointLight = 0 }
  for _, d in ipairs(R.workspace:GetDescendants()) do
    local k = d.ClassName
    if k == "Beam" then c.Beam = c.Beam + 1 if d.Enabled then c.BeamOn = c.BeamOn + 1 end
    elseif k == "ParticleEmitter" then c.ParticleEmitter = c.ParticleEmitter + 1 if d.Enabled and (d.Rate or 0) > 0 then c.PEOn = c.PEOn + 1 end
    elseif k == "Trail" then c.Trail = c.Trail + 1 if d.Enabled then c.TrailOn = c.TrailOn + 1 end
    elseif k == "PointLight" or k == "SpotLight" then c.PointLight = c.PointLight + 1 end
  end
  return c
end
local c = countFx()
print(string.format("  场景里：光带 %d（开着 %d）、粒子发射器 %d（在发 %d）、拖尾 %d（开着 %d）、灯 %d", c.Beam, c.BeamOn, c.ParticleEmitter, c.PEOn, c.Trail, c.TrailOn, c.PointLight))
K.inventory("开飞机", me)
local timed = { t = {}, n = {} }
K.wrap(C, "^step", "客户端 G.", timed)
K.wrap(G, "Step$", "服务器 G.", timed)
K.measure("开着加力平飞（" .. ID .. "）", secs, timed)
T.summary()
