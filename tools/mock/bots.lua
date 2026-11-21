-- 机器人测试（照 tools/test/ia_bots.luau，在没有 Lune 的机器上用模拟器跑）：
--   一个真人、其余全是机器人，打几分钟——补人数、守方守据点、攻方坐艇抢滩、交火、占领；量服务器每步耗时
--   python3 tools/mock/run.py tools/mock/bots.lua [分钟，默认 6] [v]
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local check = T.check
local Enum = T.Enum
local minutes = tonumber(TEST_ARGS:match("%d+%.?%d*") or "") or 6
local cpu = os.clock   -- 真实耗时（脚本里的 os.clock 是模拟的时钟）

local G = T.boot()
G.Config.Bots.minPerTeam = 18   -- 正式服关了（用户 11-18：把 AI 士兵去掉），这里打开，测机器人代码还能用
T.runUntil(function() return G.worldReady end, 120)
local pl = T.join("P1", 4001, true)
R.run(3)
local BC = G.Config.Bots
local P = G.P[pl]
-- 真人放在守方：攻方有真人在线时机器人自己占不下据点（要真人进圈，Round.lua 的 PvP 规则），这里要看机器人能不能打下来
if P.team ~= "def" then
  P.team = "def"
  pl.Team = G.TEAM.def
  pl.Neutral = false
  pl:SetAttribute("Side", "def")
  G.pushOne(P)
  R.run(3)
end
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
-- 机器人的样子：Roblox 小人（模拟器里没有 R15 模板，用零件拼的经典小人：圆头、笑脸）
do
  -- 离镜头 1500 格外的收起来了（不在 EntView 里，自动画质）：按客户端的视图表数
  local nb, okHead = 0, false
  for _, v in pairs(T.C.views or {}) do
    local m = v.model
    if m and m.Name == "bot" then
      nb = nb + 1
      for _, p in ipairs(m:GetChildren()) do
        local sm = p:IsA("BasePart") and p:FindFirstChildOfClass("SpecialMesh")
        if sm and sm.MeshType == Enum.MeshType.Head and p:FindFirstChild("face") then okHead = true end
      end
    end
  end
  check(nb > 5 and okHead, "机器人是 Roblox 小人的样子（圆头、笑脸）：" .. nb .. " 个")
end

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
local nades = 0
local launch0 = G.launch
G.launch = function(sh, ...)
  if sh and sh.kind == "grenade" and sh.src and sh.src.bot then nades = nades + 1 end
  return launch0(sh, ...)
end
local t0 = R.clock()
local lastPrint = t0
-- 小队、姿势、动作（用户：给小兵加上动画和姿势；登陆和防守的按小队聚在一起，每个人要有自己的动作逻辑）：每 5 秒看一眼
local stances, acts, bigSquads, tight, sqSeen = { [0] = 0, [1] = 0, [2] = 0 }, {}, 0, 0, 0
local function sample()
  for _, e in ipairs(G.ents) do
    if e.alive and e.kind == "bot" then
      stances[e.stance or 0] = stances[e.stance or 0] + 1
      local a = e.model:GetAttribute("Act")
      if type(a) == "string" then acts[a:sub(1, 1)] = (acts[a:sub(1, 1)] or 0) + 1 end
    end
  end
  for _, S in ipairs(G.botSquads()) do
    local alive = {}
    for _, B in ipairs(S.m) do if B.e and B.e.alive and B.state ~= "boat" then table.insert(alive, B) end end
    if #alive >= 3 then
      bigSquads = bigSquads + 1
      local L = S.lead and S.lead.e and S.lead.e.root.CFrame.Position
      if L then
        local near = 0
        for _, B in ipairs(alive) do
          local p = B.e.root.CFrame.Position
          if ((p.X - L.X) ^ 2 + (p.Z - L.Z) ^ 2) ^ 0.5 < 45 then near = near + 1 end
        end
        sqSeen = sqSeen + 1
        if near >= #alive * 0.6 then tight = tight + 1 end
      end
    end
  end
end
while R.clock() - t0 < minutes * 60 and G.round.phase == "battle" do
  R.run(5)
  sample()
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
print("④ 小队、姿势、动作、每人不一样")
check(bigSquads > 0 and tight >= sqSeen * 0.6, string.format("按小队行动：三人以上的小队 %d 次，其中队员大多在队长 45 格以内的 %d / %d 次", bigSquads, tight, sqSeen))
check(stances[0] > 0 and stances[1] > 0 and stances[2] > 0, string.format("姿势有站有蹲有趴（站 %d、蹲跪 %d、趴 %d 人次）", stances[0], stances[1], stances[2]))
check((acts.r or 0) > 0 and (acts.s or 0) > 0 and nades > 0, string.format("有人换弹匣（%d）、队长打手势（%d）、扔手雷（扔了 %d 颗）", acts.r or 0, acts.s or 0, nades))
local rs = {}
for _, e in ipairs(G.ents) do if e.alive and e.kind == "bot" and e.bot then table.insert(rs, e.bot.pers.react) end end
local mn, mx = math.huge, -math.huge
for _, x in ipairs(rs) do mn, mx = math.min(mn, x), math.max(mx, x) end
check(#rs > 5 and mx - mn > 0.3, string.format("每个人反应快慢不一样（%.2f～%.2f）", mn, mx))
check(stepN > 0, string.format("机器人每步平均 %.2f 毫秒，最慢 %.1f 毫秒，超过 8 毫秒 %d 次（模拟器里，Luau 真服务器快几倍）", stepT / math.max(1, stepN) * 1000, worst * 1000, slow))
T.summary()
