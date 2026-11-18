-- 落点标记（模拟器）：python3 tools/mock/run.py tools/mock/marks.lua
--   用户：手榴弹增加一个弹道；飞机空投炸弹在地面要有标记，方便查看投到哪
--   ① 拿手雷：地上一串弹道小亮点和落点圈；预测的落点和服务器真扔出去的雷第一次落地的地方对得上
--   ② 炸弹：客户端按服务器的炸弹物理算的落点和真投下去的炸弹炸的地方对得上；开飞机选中炸弹时地上有红圈、十字、光柱；
--      扔出去的炸弹落地前地上也标着落点，炸了就收掉
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check

local G = T.boot()
T.runUntil(function() return G.worldReady end, 120)
local me = T.join("P1", 7101, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
R.run(1)
local C = T.C
T.act("deploy", "rifle", "af2")
R.run(2)
check(P.alive, "出生了")
local folder = R.workspace:FindFirstChild("Marks")
local function count(name)
  local n = 0
  for _, c in ipairs(folder:GetChildren()) do if c.Name == name then n = n + 1 end end
  return n
end

print("① 手雷弹道")
check(count("NadeDot") == 0, "拿着枪：没有弹道")
R.as("client", function() C.equipSlot(2) end)
R.run(0.6)
local id = C.weaponNow and C.weaponNow()
check(id == "grenade", "换成手雷（" .. tostring(id) .. "）")
check(count("NadeDot") == 26 and count("MarkRing") >= 1, "拿着手雷：一串弹道小亮点（" .. count("NadeDot") .. "）、落点圈")
-- 往前方地上一点扔：预测的落点和服务器真扔的雷第一次落地的地方比（等开战时先换回步枪，模拟器里射线慢）
R.as("client", function() C.equipSlot(1) end)
T.runUntil(function() return G.round.phase == "battle" end, 60)
R.as("client", function() C.equipSlot(2) end)
R.run(0.3)
local head = me.Character.Head.Position
local hrp = me.Character.HumanoidRootPart
local fwd = hrp.CFrame.LookVector
local aim = head + V3(fwd.X, 0, fwd.Z).Unit * 45
aim = V3(aim.X, G.Map.ground(aim.X, aim.Z), aim.Z)
local pts, land
R.as("client", function() pts, land = C.nadePath(G.Config.Weapons.grenade, head, aim) end)
local shot
local launch0 = G.launch
G.launch = function(s) if s.kind == "grenade" then shot = s end return launch0(s) end
T.remoteAs(me, "Shoot", "grenade", aim)
G.launch = launch0
local first
for _ = 1, 150 do
  if not shot then break end
  local vy = shot.vel.Y
  R.run(1 / 30)
  if shot.vel.Y > vy + 1 then first = shot.pos break end   -- 弹了一下：第一次落地
end
local d = (first and land) and ((first.X - land.X) ^ 2 + (first.Z - land.Z) ^ 2) ^ 0.5 or -1
check(shot ~= nil and first ~= nil and d >= 0 and d < 6, string.format("预测落点和真扔的雷第一次落地差 %.1f 格", d))
R.as("client", function() C.equipSlot(1) end)
R.run(0.3)
check(count("NadeDot") == 0, "换回步枪：弹道收起来")

print("② 炸弹落点")
local AD = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs"))
local p0, v0 = V3(hrp.Position.X, 900, hrp.Position.Z - 600), V3(160, 0, -40)
local pred
R.as("client", function() pred = C.bombImpact(p0, v0) end)
local boomAt
local ex0 = G.explode
G.explode = function(pos, w, src, sc) if w == AD.W.mk82 then boomAt = pos end return ex0(pos, w, src, sc) end
local myId = "e-test-jet"
G.launch({ kind = "bomb", pos = p0, vel = v0, w = AD.W.mk82, src = { team = "atk", name = "test" }, ignore = {}, life = 30, step = G.airBombStep, age = 0, byEnt = myId })
-- 客户端假装在开这架飞机、选着 mk82（Marks 的选中炸弹落点；扔出去的炸弹按 by 认是自己的）
C.fly = { id = myId, pilot = true, wl = { "mk82" }, wi = 1, cf = CF(p0.X, p0.Y, p0.Z), vel = v0, d = { H = 4 }, ground = false, crashed = false }
R.run(0.3)
check(count("BombCross") == 2 and count("BombBeam") == 1, "选着炸弹：地上一个红圈、十字、一道光柱")
local ringN = count("MarkRing")
check(ringN >= 2, "扔出去的炸弹：地上也标着落点（圈 " .. ringN .. " 个）")
T.runUntil(function() return boomAt ~= nil end, 20)
local db = (boomAt and pred) and ((boomAt.X - pred.X) ^ 2 + (boomAt.Z - pred.Z) ^ 2) ^ 0.5 or -1
check(boomAt ~= nil and db >= 0 and db < 12, string.format("预测落点和炸弹真炸的地方差 %.1f 格（从 %.0f 格高、%.0f 格 / 秒投下）", db, p0.Y - G.Map.ground(p0.X, p0.Z), v0.Magnitude))
G.explode = ex0
R.run(0.5)
C.fly = nil
R.run(0.3)
check(count("MarkRing") == 0 and count("BombBeam") == 0, "炸了、下了飞机：标记都收掉了")
T.summary()
