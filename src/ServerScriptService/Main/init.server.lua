-- Roblox全面大战场——服务器主脚本（ServerScriptService.Main）
-- 各模块共用一个上下文 G：每个模块的 init(G) 把自己的函数挂到 G 上，模块之间通过 G 互相调用（不互相 require，免得循环引用）
--   World 地图 · Store 存档 · Round 回合、分队、部署、据点、胜负 · Weapons 步兵武器 · Ents 实体（机器人、载具、舰艇、工事）与伤害、爆炸、飞行中的弹 ·
--   Vehicles 开载具、登陆艇 · Armor 地面载具 · Air 飞机、直升机 · Depots 地图里的载具生成点 · Navy 舰艇（码头、开船、舰炮、导弹、近防，AI 舰艇） · Forts 地图自带的工事和障碍（玩家走过去能操作） · Bots 机器人
-- 循环里每一步都包在 pcall 里：一处出错只跳过那一下，不会把整个服务器卡死（出错原文发到所有人屏幕上的红条）
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(RS:WaitForChild("Config"))
local Map = require(RS:WaitForChild("Map"))
local G = { Config = Config, Map = Map, P = {} }   -- P[player] = 这个玩家这一局的状态

Players.CharacterAutoLoads = false   -- 先看部署界面：选好兵种和出生点才生成角色

---------------------------------------------------------------- 远程事件

local Remotes = Instance.new("Folder")
Remotes.Name = "Remotes"
G.R = {}
for _, name in ipairs({ "State", "Act", "Shoot", "Msg", "Fx", "Drive", "Err", "Board" }) do
  local r = Instance.new("RemoteEvent")
  r.Name = name
  r.Parent = Remotes
  G.R[name] = r
end
Remotes.Parent = RS

local fxq = {}
function G.fx(e) fxq[#fxq + 1] = e end
-- 发一条文字（编号 + 参数，客户端按自己的语言翻译）；kind：info / good / bad / kill / center
function G.msg(pl, kind, key, ...)
  if pl then G.R.Msg:FireClient(pl, kind, key, ...) end
end
function G.msgAll(kind, key, ...) G.R.Msg:FireAllClients(kind, key, ...) end
function G.msgTeam(team, kind, key, ...)
  for pl, P in pairs(G.P) do
    if P.team == team then G.R.Msg:FireClient(pl, kind, key, ...) end
  end
end

-- 开服时出的错记下来；运行中接住的错 Output 里留一条、所有玩家屏幕上方红条显示（同一个错只发一次）
G.bootErrors = {}
local function bootError(what, err)
  local msg = "[全面大战场] " .. what .. "出错：" .. tostring(err)
  warn(msg)
  table.insert(G.bootErrors, msg)
end
local errSeen, errN = {}, 0
function G.reportError(where, err)
  local full = tostring(err)
  local first = string.match(full, "^[^\n]*") or full
  local key = tostring(where) .. first
  if errSeen[key] then return end
  errSeen[key] = true
  errN += 1
  warn("[全面大战场] " .. tostring(where) .. " 出错：" .. full)
  if errN <= 8 then pcall(function() G.R.Err:FireAllClients(string.sub(tostring(where) .. "：" .. first, 1, 300)) end) end
end
local function tb(e) return debug.traceback(tostring(e), 2) end
function G.try(where, f, ...)
  local ok, err = xpcall(f, tb, ...)
  if not ok then G.reportError(where, err) end
  return ok, err
end

-- 每帧要做的（登陆艇、开着的车、车组跟车）：G.onFrame 登记
local frameFns = {}
function G.onFrame(f) table.insert(frameFns, f) end

-- 事件：模块之间互相通知（开局、阵亡、走人、据点易手、结算）——G.on 登记、G.emit 挨个调（一个出错不影响别的）
local hooks = {}
function G.on(ev, f)
  hooks[ev] = hooks[ev] or {}
  table.insert(hooks[ev], f)
end
function G.emit(ev, ...)
  for _, f in ipairs(hooks[ev] or {}) do G.try(ev, f, ...) end
end

-- 人在载具里（车、飞机、船里的人由载具挨打，步枪、炮弹打不着人）；遥控无人机的不算：人站在地上端着平板，照样挨打、会被看见（Air.lua 的 P.remote）
function G.inVeh(P)
  local v = P.vehicle
  return v ~= nil and v ~= P.remote
end

local ACT = {}
G.ACT = ACT   -- 各模块往里登记客户端能发来的操作：ACT.deploy = function(P, ...) … end

-- 各模块挂到 G 上；一个出错不影响后面的（init 里不能等网络、不能久等，要等的放 task.spawn）
G.World = require(script:WaitForChild("World"))
for _, name in ipairs({ "Imports", "Store", "Economy", "Tech", "Gunsmith", "Passes", "Shop", "Ents", "Rewind", "Round", "Revive", "Squads", "Weapons", "Vehicles", "Armor", "Era", "Aps", "Wt", "Kit", "Air", "WtAir", "Nuke", "Depots", "WtMatch", "FarLod", "Navy", "Forts", "Nav", "Bots", "AIVeh", "Tactical", "Battle", "Trees", "Pve" }) do
  local mod = script:FindFirstChild(name)
  if mod then
    local ok, err = pcall(function() require(mod).init(G) end)
    if not ok then bootError("模块 " .. name .. " ", err) end
  end
end

---------------------------------------------------------------- 客户端发来的操作

G.R.Act.OnServerEvent:Connect(function(pl, op, a, b, c, d, e)   -- d：飞机部署时的挂载；e：整备即时存挂载时「不弹提示」（Tech.lua treeLoad）
  local P = G.P[pl]
  if not P or type(op) ~= "string" then return end
  -- 限流：每秒十几次
  local now = os.clock()
  P.tokens = math.min(20, (P.tokens or 20) + (now - (P.tokT or now)) * 14)
  P.tokT = now
  if P.tokens < 1 then return end
  P.tokens -= 1
  local f = ACT[op]
  if f then G.try("操作 " .. op, f, P, a, b, c, d, e) end
end)

G.R.Shoot.OnServerEvent:Connect(function(pl, id, a, b)
  local P = G.P[pl]
  if P and type(id) == "string" and G.shoot then G.try("开火", G.shoot, P, id, a, b) end
end)

G.R.Drive.OnServerEvent:Connect(function(pl, d)
  local P = G.P[pl]
  -- 战雷式（Config.Wt.noInfantry，用户 11-25「不要让玩家作为个体活动」）：自己开的车不能下车——要「下车」就是回机库（这辆算没了，Tech.lua）
  --   用户 11-25「在车上按空格也不要自动阵亡了」：只有客户端明说「回机库」（长按 H，d.hangar）才走 treeLeave；别的「下车」（老客户端的空格、F / E）不理
  if P and type(d) == "table" and d.op == "exit" and G.treeLeave and G.treeLeave(P, d.hangar == true) then return end
  if P and type(d) == "table" and G.driveInput then G.try("开载具", G.driveInput, P, d) end
end)

---------------------------------------------------------------- 开服：先生成地图，再开局

-- 选地图（用户 11-22：「界面直接写 play，然后进入界面点地图」；11-23：「三张地图改成投票制，进去投票选地图」）：开服先不造世界，
--   进来的人在主菜单「开始游戏」→ 选地图界面投票（ACT.pickMap，Round.lua；能改票）：第一票投出后 Config.MapVote.time 秒按票数最多的开（平票随机），
--   在场的人都投了就再等 grace 秒提前结束；服务器里一个人也没有（测试台、空服）就等几秒按默认的岛开；后进来的直接加入当前这张。
--   定下来以后 ReplicatedStorage 的 MapId 属性告诉客户端（客户端照着 Map.use）
G.mapId = nil
G.mapVotes = {}   -- [Player] = 地图 id
local voteEnds, allInAt = nil, nil   -- 投票到什么时候截止（os.clock）；在场的人什么时候都投完了
local function validMap(id)
  for _, m in ipairs(Map.ids) do if m == id then return true end end
  return false
end
-- 直接定一张（Studio 的 MapName、测试用）；已经定了就看是不是同一张
function G.pickMap(id)
  if G.mapId then return G.mapId == id end
  if not validMap(id) or not Map.profile(id) then return false end
  G.mapId = id
  return true
end
-- 投一票（改票就是再投一次）；地图已经定了就不算
function G.voteMap(pl, id)
  if G.mapId or type(id) ~= "string" or not validMap(id) or not Map.profile(id) then return false end
  G.mapVotes[pl] = id
  voteEnds = voteEnds or (os.clock() + ((Config.MapVote and Config.MapVote.time) or 25))
  return true
end
local function voteCounts()
  local counts, voters = {}, 0
  for pl, id in pairs(G.mapVotes) do
    if pl.Parent == Players then
      counts[id] = (counts[id] or 0) + 1
      voters += 1
    end
  end
  return counts, voters
end
-- 发给客户端的投票情况（Round.lua 的 common()）：还没定图才有
function G.mapVoteState()
  if G.mapId then return nil end
  local counts, voters = voteCounts()
  return { n = counts, left = voteEnds and math.max(0, voteEnds - os.clock()) or nil, voters = voters, players = #Players:GetPlayers() }
end
-- 票数最多的那张（平票随机挑一张）；没人投返回 nil
local function voteWinner()
  local counts = voteCounts()
  local best, list = 0, {}
  for _, id in ipairs(Map.ids) do
    local n = counts[id] or 0
    if n > best then best, list = n, { id } elseif n == best and n > 0 then table.insert(list, id) end
  end
  if #list == 0 then return nil end
  return list[math.random(1, #list)]
end
local function waitMap()
  local t0 = os.clock()
  -- Studio、测试台：Workspace 的属性 MapName 直接定（"island" / "sands"），不等人选
  do
    local forced
    pcall(function() forced = workspace:GetAttribute("MapName") end)
    if type(forced) == "string" and Map.profile(forced) then G.mapId = forced end
  end
  if not G.mapId and #Map.ids == 1 then G.mapId = Map.ids[1] end   -- 只剩一张（沙海）：不用投票，开服就建（进来的人点「开始游戏」时地图多半已经好了）
  -- 空服等多久就按默认开：Studio / 测试台 3 秒；线上服务器是第一个玩家要进来才开的，他还在加载（可能十几秒）——等 30 秒
  local emptyWait = Config.MapWaitEmpty or (game:GetService("RunService"):IsStudio() and 3 or 30)
  local grace = (Config.MapVote and Config.MapVote.grace) or 3
  local pushAt = 0
  while not G.mapId do
    -- 投票中半秒发一次状态（票数、倒计时、在场人数：有人进来、走了也跟着变）
    if os.clock() >= pushAt and #Players:GetPlayers() > 0 and G.pushAll then
      pushAt = os.clock() + 0.5
      pcall(G.pushAll)
    end
    local anyone = #Players:GetPlayers() > 0
    local waited = os.clock() - t0
    if voteEnds then
      -- 在场的人都投了：再等 grace 秒（还能改票）就开
      local _, voters = voteCounts()
      if anyone and voters >= #Players:GetPlayers() then
        allInAt = allInAt or os.clock()
        voteEnds = math.min(voteEnds, allInAt + grace)
      end
      if os.clock() >= voteEnds then G.mapId = voteWinner() or Config.MapDefault or "sands" end
    end
    if not G.mapId and ((not anyone and not voteEnds and waited > emptyWait) or waited > (Config.MapWaitMax or 900)) then
      G.mapId = voteWinner() or Config.MapDefault or "sands"
    end
    task.wait(0.1)
  end
  if G.pushAll then pcall(G.pushAll) end   -- 选地图界面马上看到定了哪张
  if not Map.use(G.mapId) then
    bootError("地图 " .. tostring(G.mapId) .. " ", "加载不了，改用沙海")
    G.mapId = "sands"
    Map.use("sands")
  end
  Config.useMap(G.mapId)   -- 跟着地图变的数（沙海的五个阶段……）
  local okL, Lang = pcall(function() return require(RS:WaitForChild("Lang")) end)
  if okL and type(Lang) == "table" then Lang.mapId = G.mapId end   -- 服务器发的提示也用这张图的说法（据点名……）
  RS:SetAttribute("MapId", G.mapId)
  print("[全面大战场] 地图：" .. G.mapId)
end

task.spawn(function()
  waitMap()
  local ok, err = xpcall(function() G.World.build(G) end, tb)
  if not ok then bootError("生成地图", err) G.worldReady = true end
  if G.farLodPublish then G.try("远景替身", G.farLodPublish) end   -- 流式加载时远处的楼画替身（FarLod.lua）
  if G.depotsBuild then G.try("生成点", G.depotsBuild) end   -- 载具生成点（要等舰队甲板建好）
  if G.navBuild then G.try("寻路", G.navBuild) end   -- 后台算机器人走路的流场
  if G.roundStart then G.try("开局", G.roundStart) end
  print("[全面大战场] " .. Config.Version .. " 地图好了：" .. tostring(G.terrainChunks) .. " 块地形、" .. tostring(G.terrainVoxels) .. " 个体素")
  -- 训练场（用户 11-26 晚「把训练场单独做一张地图吧」）：自己一块区块（Zones.RANGE），战场开局以后在后台建（Range.lua）；建好以前试驾先等等
  task.spawn(function()
    G.try("训练场", function() require(script:WaitForChild("Range")).build(G.World, G, workspace:FindFirstChild("Map")) end)
  end)
end)

---------------------------------------------------------------- 特效：枪声只发给附近的人

-- 评估后改的（百人同服的带宽）：原来每一发枪（真人、机器人、工事）都广播给所有人，客户端再把 900 格外的扔掉（Fx.lua gunFx）。
--   现在 gun 事件只发给「枪口离他 GUN_R 格以内、或者弹道从他 GUN_PASS 格以内擦过」的人；开飞机的按雷达范围 AIR_R 发（平显雷达上的开枪红圈）；
--   没有身体的（死了、在部署界面）照旧全发；别的事件（爆炸、导弹、炮弹……）照旧发给所有人。
--   客户端照样画：900 格内的枪口、300 格内擦过的弹道、7 格内的子弹擦身声、雷达（步兵 520 格、车 900 格）都在发的范围里
local GUN_R, GUN_PASS, AIR_R = 1100, 400, (Config.Radar and Config.Radar.jet) or 9000
local function viewPoints(P)
  local pts = {}
  local v = P.vehicle
  if v and v.root and v.root.Parent then pts[#pts + 1] = v.root.CFrame.Position end
  local r = P.remote
  if r and r.root and r.root.Parent then pts[#pts + 1] = r.root.CFrame.Position end
  local hrp = P.alive and P.char and P.char:FindFirstChild("HumanoidRootPart")
  if hrp then pts[#pts + 1] = hrp.Position end
  return pts, (v and v.air) and AIR_R or GUN_R
end
local function segDist(p, a, b)
  local ab = b - a
  local L2 = ab:Dot(ab)
  local t = (L2 > 1e-6) and math.clamp((p - a):Dot(ab) / L2, 0, 1) or 0
  return (a + ab * t - p).Magnitude
end
local function gunNear(e, pts, R)
  for _, p in ipairs(pts) do
    if (e.a - p).Magnitude <= R or segDist(p, e.a, e.b) <= GUN_PASS then return true end
  end
  return false
end
function G.flushFx(list)
  local guns, rest = {}, {}
  for _, e in ipairs(list) do
    if e.k == "gun" and typeof(e.a) == "Vector3" and typeof(e.b) == "Vector3" then guns[#guns + 1] = e else rest[#rest + 1] = e end
  end
  if #guns == 0 then
    G.R.Fx:FireAllClients(list)
    return
  end
  local sent = {}
  for pl, P in pairs(G.P) do
    sent[pl] = true
    local pts, R = viewPoints(P)
    local out = list
    if #pts > 0 then
      out = table.clone(rest)
      for _, e in ipairs(guns) do
        if gunNear(e, pts, R) then out[#out + 1] = e end
      end
    end
    if #out > 0 then G.R.Fx:FireClient(pl, out) end
  end
  for _, pl in ipairs(Players:GetPlayers()) do   -- 还没进 G.P 的（刚进服）照旧全发
    if not sent[pl] then G.R.Fx:FireClient(pl, list) end
  end
end

---------------------------------------------------------------- 循环

-- 推演：每 Config.Tick 秒一步（占领、AI、炮弹、导弹、登陆艇）
local acc = 0
RunService.Heartbeat:Connect(function(dt)
  acc += dt
  local n = 0
  while acc >= Config.Tick and n < 3 do
    acc -= Config.Tick
    n += 1
    if G.worldReady then
      if G.roundStep then G.try("回合", G.roundStep, Config.Tick) end
      if G.entsStep then G.try("实体", G.entsStep, Config.Tick) end
      if G.botsStep then G.try("机器人", G.botsStep, Config.Tick) end
      if G.vehStep then G.try("载具", G.vehStep, Config.Tick) end
      if G.fortsStep then G.try("工事", G.fortsStep, Config.Tick) end
    end
  end
  if acc > Config.Tick * 3 then acc = 0 end
  for _, f in ipairs(frameFns) do G.try("逐帧", f, dt) end   -- 登陆艇、开着的载具：每帧挪一次（看着平滑）
  if #fxq > 0 then
    local list = fxq
    fxq = {}
    G.try("特效", G.flushFx, list)
  end
end)

game:BindToClose(function()
  if G.saveAll then G.saveAll() end
end)

print("[全面大战场] " .. Config.Version .. "（脚本构建 " .. tostring(Config.Build) .. "）服务器启动" .. ((#G.bootErrors > 0) and ("（有 " .. #G.bootErrors .. " 处出错，见上面的警告）") or ""))
