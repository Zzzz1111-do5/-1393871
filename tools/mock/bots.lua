-- 机器人测试（照 tools/test/ia_bots.luau，在没有 Lune 的机器上用模拟器跑）：
--   一个真人、其余全是机器人，打几分钟——补人数、守方守据点、攻方坐艇抢滩、交火、占领；量服务器每步耗时
--   python3 tools/mock/run.py tools/mock/bots.lua [分钟，默认 6] [v]
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local check = T.check
local minutes = tonumber(TEST_ARGS:match("%d+%.?%d*") or "") or 6
local cpu = os.clock   -- 真实耗时（脚本里的 os.clock 是模拟的时钟）

local G = T.boot()
T.runUntil(function() return G.worldReady end, 120)
local pl = T.join("P1", 4001, true)
R.run(3)
local BC = G.Config.Bots
local P = G.P[pl]
print("① 补人数（真人 1 个，在" .. P.team .. "）")
local nA, nD = G.botCount("atk"), G.botCount("def")
local wantA = BC.minPerTeam - ((P.team == "atk") and 1 or 0)
local wantD = BC.minPerTeam - ((P.team == "def") and 1 or 0)
check(nA == wantA and nD == wantD, string.format("机器人 攻 %d / 守 %d（应 %d / %d）", nA, nD, wantA, wantD))

local function ents(kind, team)
  local n = 0
  for _, e in ipairs(G.ents) do if e.alive and e.kind == kind and (not team or e.team == team) then n = n + 1 end end
  return n
end
T.runUntil(function() return G.round.phase == "battle" end, 60)
check(ents("bot", "def") >= nD - 1, "准备阶段守方机器人都出生了：" .. ents("bot", "def"))
local near = 0
for _, e in ipairs(G.ents) do
  if e.alive and e.kind == "bot" and e.team == "def" then
    for _, p in ipairs(G.Map.POINTS) do
      local d = ((e.root.CFrame.Position.X - p.x) ^ 2 + (e.root.CFrame.Position.Z - p.z) ^ 2) ^ 0.5
      if d < 160 then near = near + 1 break end
    end
  end
end
check(near >= ents("bot", "def") * 0.7, "守方大多在据点附近：" .. near)

print("② 开战：攻方坐艇抢滩")
R.run(3)
check(ents("lcm") >= 1, "有登陆艇在开：" .. ents("lcm"))
local landed = T.runUntil(function()
  for _, e in ipairs(G.ents) do
    if e.alive and e.kind == "bot" and e.team == "atk" and e.bot.state == "move" then return true end
  end
  return false
end, 60)
check(landed, "攻方机器人上岸了")

print(string.format("③ 打 %d 分钟", minutes))
local stepT, stepN, worst, slow = 0, 0, 0, 0
local orig = G.botsStep
G.botsStep = function(dt)
  local c = cpu()
  orig(dt)
  local d = cpu() - c
  stepT = stepT + d
  stepN = stepN + 1
  worst = math.max(worst, d)
  if d > 0.008 then slow = slow + 1 end
end
local t0 = R.clock()
local lastPrint = t0
while R.clock() - t0 < minutes * 60 and G.round.phase == "battle" do
  R.run(5)
  if R.clock() - lastPrint >= 60 then
    lastPrint = R.clock()
    local caps = {}
    for _, p in ipairs(G.Map.POINTS) do
      local s = G.points[p.id]
      table.insert(caps, string.format("%s:%s%.0f%%", p.id, s.owner, s.prog * 100))
    end
    local k = { atk = 0, def = 0 }
    for _, row in ipairs(G.botBoard()) do k[row.t] = k[row.t] + row.k end
    print(string.format("  %.0f 秒：机器人在场 攻 %d 守 %d，击杀 攻 %d 守 %d，艇 %d，据点 %s", R.clock() - t0, ents("bot", "atk"), ents("bot", "def"), k.atk, k.def, ents("lcm"), table.concat(caps, " ")))
  end
end
local k = { atk = 0, def = 0 }
local d = { atk = 0, def = 0 }
for _, row in ipairs(G.botBoard()) do k[row.t] = k[row.t] + row.k d[row.t] = d[row.t] + row.d end
check(k.atk + k.def > 10, string.format("交火了：击杀 攻 %d 守 %d，阵亡 攻 %d 守 %d", k.atk, k.def, d.atk, d.def))
local capped = 0
for _, s in pairs(G.points) do if s.owner == "atk" then capped = capped + 1 end end
if minutes >= 5 then check(capped >= 1 or G.round.phase ~= "battle", "攻方拿下了据点：" .. capped .. " 个") else print("  攻方拿下了据点：" .. capped .. " 个") end
check(stepN > 0, string.format("机器人每步平均 %.2f 毫秒，最慢 %.1f 毫秒，超过 8 毫秒 %d 次（模拟器里，Luau 真服务器快几倍）", stepT / math.max(1, stepN) * 1000, worst * 1000, slow))
T.summary()
