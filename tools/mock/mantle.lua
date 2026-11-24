-- 翻越 / 攀爬、近处爆炸的震荡（模拟器；用户 11-23「这个游戏按你想的来弄」）：python3 tools/mock/run.py tools/mock/mantle.lua
--   ① 面前一道矮墙（1 格厚、比脚高 3.5 格）：按空格不跳、翻到墙另一边（路径的终点在墙后面、落在地上）
--   ② 面前一个台子（8 格见方、5.5 格高）：爬上去（终点在台面上）
--   ③ 面前一堵高墙（12 格）：不翻（照常跳）；④ 前面空的：不翻
--   ⑤ 近处炸了一下：声音发闷（新放的声音切高频、变小）、画面糊、几秒后恢复；远处的不震
--   模拟器没有物理：翻越只查「认出来了、路径对、收枪、结束」，真的推过去要在 Studio 里看
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 9201, true)
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
T.act("deploy", {}, "camp")
T.runUntil(function() return P.alive and me.Character and me.Character:FindFirstChild("HumanoidRootPart") end, 10)
R.run(1)
local hrp = me.Character.HumanoidRootPart
local hum = me.Character:FindFirstChildOfClass("Humanoid")
check(hrp ~= nil and hum ~= nil, "出生了")

-- 找一块平地站好、面朝 -Z
local Map = G.Map
local base = hrp.Position
local x, z = base.X, base.Z
for k = 0, 40 do
  local a = k * 0.7
  local px, pz = base.X + math.cos(a) * (k * 6), base.Z + math.sin(a) * (k * 6)
  if Map.isLand(px, pz) and Map.slope(px, pz) < 0.08 and Map.slope(px, pz - 12) < 0.08 then x, z = px, pz break end
end
local gy = Map.ground(x, z)
local feetOff = hum.HipHeight + hrp.Size.Y / 2
local function stand()
  me.Character:PivotTo(CF(x, gy + feetOff, z) * R.CFrame.Angles(0, 0, 0))
  R.run(0.1)
end
local parts = {}
local function block(sx, sy, sz, cx, cz)
  local p = R.Instance.new("Part")
  p.Anchored = true
  p.Size = V3(sx, sy, sz)
  p.CFrame = CF(cx, gy + sy / 2, cz)
  p.Parent = R.workspace
  table.insert(parts, p)
  return p
end
local function clear()
  for _, p in ipairs(parts) do p:Destroy() end
  parts = {}
end

print("① 矮墙：翻过去")
stand()
local wall = block(8, 3.5, 1, x, z - 2.5)
T.key(Enum.KeyCode.Space, true)
R.run(0.05)
T.key(Enum.KeyCode.Space, false)
local M = C.mantleState()
check(M ~= nil, "按空格：认出来要翻")
check(M and M.thin == true, "矮、薄：翻到另一边")
check(M and M.p2.Z < wall.Position.Z - 0.6, string.format("终点在墙后面（z %.1f，墙 %.1f）", M and M.p2.Z or 0, wall.Position.Z))
check(M and math.abs(M.p2.Y - (gy + feetOff)) < 0.6, string.format("落在地上（终点高 %.2f，站着的高 %.2f）", M and M.p2.Y or 0, gy + feetOff))
check(C.mantling == true, "翻的时候枪收下去（G.mantling）")
R.run(0.8)
check(C.mantleState() == nil and not C.mantling, "翻完了")
clear()

print("② 台子：爬上去")
stand()
local box = block(8, 5.5, 8, x, z - 6.2)
T.tap(Enum.KeyCode.Space)
M = C.mantleState()
check(M ~= nil and M.thin == false, "认出来要爬上去")
check(M and math.abs(M.p2.Y - (gy + 5.5 + feetOff)) < 0.6 and math.abs(M.p2.Z - box.Position.Z) < 4, string.format("终点在台面上（高 %.2f）", M and M.p2.Y or 0))
check(M and M.dur >= 0.45 and M.dur <= 0.72, string.format("爬比翻慢（%.2f 秒）", M and M.dur or 0))
R.run(1)
clear()

print("③ 高墙：不翻")
stand()
block(8, 12, 1, x, z - 2.5)
T.tap(Enum.KeyCode.Space)
check(C.mantleState() == nil, "太高了：不翻")
clear()
print("④ 前面空的：不翻")
stand()
T.tap(Enum.KeyCode.Space)
check(C.mantleState() == nil, "前面没东西：不翻")

print("⑤ 近处炸了一下：发闷、发糊，几秒后恢复")
local cam = R.workspace.CurrentCamera
local cp = cam.CFrame.Position
R.as("client", function() C.onFx({ { k = "boom", p = cp + V3(14, 0, 0), s = 1.2, c = "shell" } }) end)
R.run(0.1)
local m1 = C.muffle()
check(m1 > 0.3, string.format("声音发闷（%.2f）", m1))
local blur = R.services.Lighting:FindFirstChild("ShockBlur")
check(blur ~= nil and blur.Size > 4, string.format("画面糊了（%s）", tostring(blur and blur.Size)))
R.run(7)
check(C.muffle() < 0.01, "几秒后声音回来了")
check(blur and blur.Size < 0.5, "画面清楚了")
R.as("client", function() C.onFx({ { k = "boom", p = cp + V3(900, 0, 0), s = 1.2, c = "shell" } }) end)
R.run(0.1)
check(C.muffle() < 0.01, "远处炸的：不震")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
