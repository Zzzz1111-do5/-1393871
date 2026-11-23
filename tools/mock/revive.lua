-- 倒地与救援（模拟器；用户 11-23「这个游戏按你想的来弄」）：python3 tools/mock/run.py tools/mock/revive.lua
--   ① 挨了致命又不太狠的一枪：倒地（还活着、血 1、身子瘫下去、拿不了枪、开不了火），击杀这一下就记给打倒的人，阵亡没算；客户端倒地界面、镜头
--   ② 队友刚开始按就松手：救不起来；按够时间：救起来（带急救包满血、站起来、加分），死亡数没涨
--   ③ 再倒一次，补一枪：阵亡（击杀不重复记），很快能重新部署
--   ④ 倒地流血到时间：阵亡；⑤ 刚倒下就放弃不认、过一会儿放弃：阵亡；⑥ 一下打得太狠（炸）：直接阵亡、不倒地
--   ⑦ 客户端：倒地的队友身上出现「按住 E 救起」（带急救包按 1.6 秒），头顶救援标记；按完了服务器把他救起来
--   ⑧ 倒地的不算占领人数、机器人不朝倒地的人开枪（findTarget 过滤，这里只查标记）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 9101, true)
local mate = T.join("P2", 9102, false)
local foe = T.join("P3", 9103, false)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local function setTeam(pl, team)
  local P = G.P[pl]
  P.team = team
  pl.Team = G.TEAM[team]
  pl.Neutral = false
  pl:SetAttribute("Side", team)
  G.pushOne(P)
end
setTeam(me, "def")
setTeam(mate, "def")
setTeam(foe, "atk")
R.run(1)
local C = T.C
T.leaveMenu()
local RC = G.Config.Revive
local P1, P2, P3 = G.P[me], G.P[mate], G.P[foe]
T.runUntil(function() return G.round.phase == "battle" end, G.Config.Round.prep + 10)
check(G.round.phase == "battle", "开战")

-- 部署：默认装备栏（主武器 M4、装备栏急救包、手雷）；守方在营地、攻方在后方舰队
local function deploy(pl, local_)
  local P = G.P[pl]
  if P.alive then return end
  T.runUntil(function() return R.clock() >= (P.canDeployAt or 0) end, 15)   -- 服务器用的是模拟器的钟（R.clock）
  local sp = (P.team == "atk") and "fleet" or "camp"
  if local_ then T.act("deploy", {}, sp) else T.actAsRemote(pl, "deploy", {}, sp) end
  T.runUntil(function() return P.alive and P.char ~= nil and P.char:FindFirstChild("HumanoidRootPart") ~= nil end, 10)
  R.run(0.5)
end
local function hrpOf(pl) return pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") end
local function humOf(pl) return pl.Character and pl.Character:FindFirstChildOfClass("Humanoid") end
local function putNear(pl, other, dx)
  local h = hrpOf(other)
  if pl.Character and h then pl.Character:PivotTo(CF(h.Position.X + dx, h.Position.Y, h.Position.Z)) end
end
local function shoot(victimPl, amt, head)
  local part = victimPl.Character and victimPl.Character:FindFirstChild(head and "Head" or "HumanoidRootPart")
  return G.hurtChar(victimPl.Character, amt, { P = P3, team = "atk", name = foe.DisplayName, wid = "m4" }, part)
end
deploy(me, true)
deploy(mate, false)
deploy(foe, false)
check(P1.alive and P2.alive and P3.alive, "三个人都出生了")
check(G.hasMedkit(P2) and G.hasMedkit(P1), "默认装备栏带着急救包")
putNear(mate, me, 6)
R.run(0.3)

print("① 致命的一枪：倒地")
local k0, d0 = P3.kills, P1.deaths
shoot(me, 130)
R.run(0.3)
local hum = humOf(me)
check(P1.downed ~= nil and P1.alive, "倒地了、还活着")
check(hum and hum.Health > 0 and hum.Health <= 5, "血剩一点（" .. tostring(hum and hum.Health) .. "）")
check(hum and hum.PlatformStand == true and hum.WalkSpeed == 0, "身子瘫下去、走不了")
check(me.Character:GetAttribute("Downed") == true and type(me.Character:GetAttribute("DownT")) == "number", "角色上有倒地标记和流血时间")
check(P3.kills == k0 + 1, "击杀这一下就记给打倒的人（" .. P3.kills - k0 .. "）")
check(P1.deaths == d0, "阵亡还没算")
check(me.Character:FindFirstChildOfClass("Tool") == nil, "手里没拿着枪")
R.run(0.5)
check(C.downed == true and C.downedState().on, "客户端：进了倒地界面")
check(#T.texts(C.T("down.title")) > 0, "屏幕上写着「" .. C.T("down.title") .. "」")
-- 流血倒计时：「18 秒后阵亡」——按语言把数字后面那一截拿出来找
local tail = (C.T("down.bleed", 99):gsub("99", "", 1))
local bleedTxt = nil
for _, x in ipairs(T.texts()) do if x:find(tail, 1, true) and x:find("%d") then bleedTxt = x end end
check(bleedTxt ~= nil and not bleedTxt:find("{", 1, true), "流血倒计时写着「" .. tostring(bleedTxt) .. "」")
-- 开不了火：拿出枪也不让（服务器 holding 拒绝）
local shots0 = 0
for _ in pairs(G.shots or {}) do shots0 = shots0 + 1 end
local tool = me.Backpack and me.Backpack:FindFirstChildOfClass("Tool")
if tool then tool.Parent = me.Character end
local fired = false
local bs0 = G.fx
G.fx = function(e) if type(e) == "table" and e.k == "gun" and e.by == me.UserId then fired = true end return bs0(e) end
R.as("server", function() G.R.Shoot.OnServerEvent:Fire(me, "m4", hrpOf(me).Position + V3(0, 0, -50), "hip") end)
R.run(0.3)
G.fx = bs0
check(not fired, "倒地开不了火")
R.run(0.5)
check(me.Character:FindFirstChildOfClass("Tool") == nil, "拿出来的枪又被收起来")

print("② 队友救：太快不认，按够了救起来")
local s0 = P2.score
T.actAsRemote(mate, "reviveBegin", me.UserId)
R.run(0.2)
T.actAsRemote(mate, "revive", me.UserId)
R.run(0.2)
check(P1.downed ~= nil, "刚按 0.2 秒：没救起来")
T.actAsRemote(mate, "reviveBegin", me.UserId)
R.run(RC.medicHold + 0.1)
T.actAsRemote(mate, "revive", me.UserId)
R.run(0.3)
hum = humOf(me)
check(P1.downed == nil and P1.alive, "救起来了")
check(hum and hum.PlatformStand == false and hum.WalkSpeed > 0, "站起来、能走了")
check(hum and hum.Health >= hum.MaxHealth - 0.5, string.format("带急救包救的：满血（%s / %s）", tostring(hum and hum.Health), tostring(hum and hum.MaxHealth)))
check(P2.score - s0 == G.Config.Score.revive, "救人的加分（+" .. (P2.score - s0) .. "）")
check(P1.deaths == d0, "死亡数没涨")
check(me.Character:GetAttribute("Downed") == nil, "倒地标记清掉了")
R.run(0.5)
check(C.downed == false and not C.downedState().on, "客户端：倒地界面收了")

print("③ 再倒一次、补一枪：阵亡，击杀不重复记")
local k1 = P3.kills
shoot(me, 130)
R.run(0.2)
check(P1.downed ~= nil, "又倒了")
check(P3.kills == k1 + 1, "又记一次击杀")
shoot(me, 20)
R.run(0.3)
check(not P1.alive and P1.downed == nil, "补一枪：阵亡")
check(P3.kills == k1 + 1, "补枪不重复记（" .. (P3.kills - k1) .. "）")
check(P1.deaths == d0 + 1, "阵亡算一次")
check((P1.canDeployAt or 0) - R.clock() <= RC.afterDown + 0.2, string.format("倒地以后阵亡：很快能重新部署（%.1f 秒）", (P1.canDeployAt or 0) - R.clock()))

print("④ 流血到时间：阵亡")
deploy(me, true)
check(P1.alive, "重新部署了")
shoot(me, 130)
R.run(0.2)
check(P1.downed ~= nil, "倒地")
R.run(RC.bleed - 2)
check(P1.alive and P1.downed ~= nil, "快到时间还倒着")
R.run(3)
check(not P1.alive, "流血到时间：阵亡")

print("⑤ 放弃")
deploy(me, true)
shoot(me, 130)
R.run(0.2)
T.act("giveUp")
R.run(0.2)
check(P1.alive and P1.downed ~= nil, "刚倒下就放弃：不认")
R.run(1.0)
-- 客户端按住空格放弃
T.key(Enum.KeyCode.Space, true)
R.run(RC.giveUp + 0.6)
T.key(Enum.KeyCode.Space, false)
R.run(0.3)
check(not P1.alive, "按住空格放弃：阵亡")

print("⑥ 一下打得太狠（炸）：直接阵亡")
deploy(me, true)
shoot(me, 100 + RC.overkill + 40)
R.run(0.3)
check(not P1.alive and P1.downed == nil, "直接阵亡、没倒地")

print("⑦ 客户端：倒地的队友身上「按住 E 救起」")
deploy(me, true)
putNear(me, mate, 4)
R.run(0.3)
shoot(mate, 130)
R.run(0.6)
check(P2.downed ~= nil, "队友倒地了")
local pr = hrpOf(mate) and hrpOf(mate):FindFirstChild("Revive")
check(pr ~= nil and pr:IsA("ProximityPrompt"), "队友身上出现救人的提示")
check(pr and math.abs(pr.HoldDuration - RC.medicHold) < 0.01, "带着急救包：按住 " .. RC.medicHold .. " 秒（" .. tostring(pr and pr.HoldDuration) .. "）")
local marks = 0
for _, d in ipairs(me.PlayerGui:GetDescendants()) do if d.Name == "ReviveMark" then marks = marks + 1 end end
check(marks == 1, "头顶一个救援标记（" .. marks .. " 个）")
if pr then
  R.as("client", function() pr.PromptButtonHoldBegan:Fire(me) end)
  R.run(RC.medicHold + 0.1)
  R.as("client", function() pr.Triggered:Fire(me) end)
  R.run(0.4)
end
check(P2.downed == nil and P2.alive, "按完了：队友救起来了")
check((P1.revives or 0) >= 1, "我救人的次数记上了")
R.run(0.5)
check((hrpOf(mate) and hrpOf(mate):FindFirstChild("Revive")) == nil, "救起来以后提示收了")

print("⑧ 倒地的不算占领、机器人不打倒地的人")
shoot(mate, 130)
R.run(0.3)
check(P2.downed ~= nil, "队友又倒了")
R.run(0.3)
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
