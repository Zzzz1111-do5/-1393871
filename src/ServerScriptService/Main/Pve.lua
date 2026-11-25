-- 全面大战场——PvE 关卡（用户 11-23：「金币 pvp 或者打 pve 来 你搞一些关卡吧」）
--   选地图界面的「关卡 PVE」页点一关（ACT.pickPve）：这个服务器还没定地图 → 按这一关开（那一关的地图）；
--     已经在打别的（对战、别的关）：只有自己一个人、同一张图 → 直接换成这一关重开；不然开一个新的私人服务器把他传过去（线上才行；
--     传送数据里带着关卡号，新服务器第一个进来的人按它开）
--   这一关：真人都在攻方（Round.lua 的分队看 G.pve）；电脑人数按关卡（G.botWanted，Bots.lua）：敌方 enemies（多一个真人多 perPlayer 个）、
--     友军 allies（真人多了少补）；电脑的枪法和反应按 skill 缩放（Config.Bots 的反应时间、散布）；aiVeh：敌方开不开 AI 坦克、飞机
--   赢：拿下 caps 个据点（G.on("captured")；岛、沙海都是）；关卡给了 tickets 的（征服的规则）敌方兵力扣光也赢（原来沙漠风暴的关，11-24 那张图删了，改到沙海）
--   结算（Round.lua 的 finish 先调 G.pveFinish）：赢了每个真人发这一关的奖励（第一次打通 × firstBonus），记进存档（P.data.pve）；
--     下一关同一张图就接着打下一关，不是就提示回菜单选；输了再来这一关
local Players = game:GetService("Players")

local Pve = {}

function Pve.init(G)
  local Config = G.Config
  local PC = Config.Pve
  local BC = Config.Bots
  local base = { reaction = BC.reaction, spread = BC.spread, spreadPer = BC.spreadPer }
  G.pve = nil

  local function realN()
    local n = 0
    for _ in pairs(G.P) do n += 1 end
    return math.max(1, n)
  end
  -- 换成第 n 关（不重开地图：地图在开服时定）
  local function apply(n)
    local L = PC.levels[n]
    if not L then return false end
    if not G.pve then base.aiVehOff = G.aiVehOff end   -- 对战时的设置（测试台可能关了 AI 载具），退出关卡时还原
    G.pve = { n = n, L = L }
    local k = L.skill or 1
    BC.reaction = base.reaction / k
    BC.spread = base.spread / k
    BC.spreadPer = base.spreadPer / k
    G.aiVehOff = not L.aiVeh
    pcall(function() workspace:SetAttribute("Pve", n) end)
    -- 这一关几点开打（Config.Pve 的 clock；fixed 的一直停在那：夜袭镇子、夜幕坦克战）——DayClock.lua 按这两个属性算钟点
    if L.clock then
      pcall(function()
        local DC = require(game:GetService("ReplicatedStorage"):WaitForChild("DayClock"))
        workspace:SetAttribute("DayFix", L.fixed and L.clock or nil)
        workspace:SetAttribute("DayT0", DC.t0For(L.clock))
      end)
    end
    -- 电脑人数：敌方按关卡 + 每多一个真人多几个；友军补到 allies（真人也算友军）
    G.botWanted = function()
      local P = G.pve
      if not P then return nil end
      local r = realN()
      return { def = P.L.enemies + (PC.perPlayer or 2) * (r - 1), atk = math.max(0, P.L.allies - (r - 1)) }
    end
    -- 真人都去攻方
    for _, P in pairs(G.P) do
      if P.team ~= "atk" and not P.alive and G.setTeamOf then G.setTeamOf(P, "atk") end
    end
    return true
  end
  G.pveApply = apply   -- 测试用
  -- 退出关卡（只剩自己的时候在对战页点地图，Round.lua 的 ACT.pickMap）：电脑的水平、人数、AI 载具都回到对战的
  function G.pveExit()
    if not G.pve then return false end
    G.pve = nil
    BC.reaction, BC.spread, BC.spreadPer = base.reaction, base.spread, base.spreadPer
    G.botWanted = nil
    G.aiVehOff = base.aiVehOff
    pcall(function() workspace:SetAttribute("Pve", nil) end)
    pcall(function() workspace:SetAttribute("DayFix", nil) end)   -- 夜战关卡钉住的钟点松开，接着走
    return true
  end
  G.pveRealN = realN

  -- 这个人能不能打第 n 关：打通了第 n-1 关（第 1 关谁都能打）
  local function unlocked(P, n)
    if n <= 1 then return true end
    local d = P.data
    return d ~= nil and (d.pve or 0) >= n - 1
  end

  G.ACT.pickPve = function(P, n)
    n = tonumber(n)
    if not n or not PC.levels[n] then return end
    n = math.floor(n)
    if not unlocked(P, n) then G.msg(P.pl, "bad", "pve.lockedMsg", n - 1) return end
    local L = PC.levels[n]
    -- 还没定地图：按这一关开
    if not G.mapId then
      apply(n)
      P.wantMap = L.map
      if G.pickMap then G.pickMap(L.map) end
      G.pushAll()
      return
    end
    if G.pve and G.pve.n == n then G.pushOne(P) return end   -- 已经在打这一关：直接加入
    -- 只有自己一个人、同一张图：直接换成这一关，重新开一局
    if G.mapId == L.map and realN() <= 1 then
      apply(n)
      if G.roundStart then G.roundStart() end
      return
    end
    -- 开一个新的私人服务器，把他传过去（Studio 里传不了）
    local ok = pcall(function()
      local TS = game:GetService("TeleportService")
      local code = TS:ReserveServer(game.PlaceId)
      G.msg(P.pl, "info", "pve.teleport")
      TS:TeleportToPrivateServer(game.PlaceId, code, { P.pl }, nil, { pve = n })
    end)
    if not ok then G.msg(P.pl, "bad", "pve.needNew") end
  end

  -- 传过来的人：传送数据里带着关卡号，这个服务器还没定地图就按它开
  local function fromTeleport(pl)
    if G.mapId then return end
    local ok, jd = pcall(function() return pl:GetJoinData() end)
    local td = ok and type(jd) == "table" and jd.TeleportData or nil
    local n = type(td) == "table" and tonumber(td.pve) or nil
    if n and PC.levels[n] then
      apply(n)
      if G.pickMap then G.pickMap(PC.levels[n].map) end
    end
  end
  Players.PlayerAdded:Connect(fromTeleport)
  for _, pl in ipairs(Players:GetPlayers()) do task.spawn(fromTeleport, pl) end

  -- 岛：拿下 caps 个据点就赢
  G.on("captured", function()
    local P = G.pve
    if not P or not P.L.caps or not G.round or G.round.phase ~= "battle" then return end
    local n = 0
    for _, s in pairs(G.points or {}) do if s.owner == "atk" and s.locked then n += 1 end end
    if n >= P.L.caps and G.roundFinish then G.roundFinish("atk") end
  end)
  -- 沙漠：开战时的兵力（Round.lua 的 startBattle 调）
  function G.pveTickets(R)
    local P = G.pve
    if not P or not P.L.tickets then return end
    R.ticketsDef = P.L.tickets
    R.tickets = P.L.ticketsAtk or P.L.tickets
    R.ticketsMax = math.max(R.tickets, R.ticketsDef)
  end

  -- 结算（Round.lua 的 finish 调，先于发金币、经验、存档）
  function G.pveFinish(winner)
    local P0 = G.pve
    if not P0 then return end
    local n, L = P0.n, P0.L
    if winner == "atk" then
      for _, P in pairs(G.P) do
        if P.team == "atk" and P.data then
          local first = (P.data.pve or 0) < n
          local reward = math.floor(L.reward * (first and (PC.firstBonus or 1) or (PC.replay or 1)))   -- 第一次翻倍、再打一半
          if G.addCoins then G.addCoins(P, reward, "eco.pve") end
          if first then P.data.pve = n end
          if G.econPublish then G.econPublish(P) end
        end
      end
      G.msgAll("center", "pve.win")
      local nx = PC.levels[n + 1]
      if not nx then
        G.msgAll("good", "pve.allClear")
      elseif nx.map == G.mapId then
        P0.next = n + 1
        G.msgAll("good", "pve.next", n + 1)
      else
        G.msgAll("good", "pve.nextMap", n + 1)
      end
    else
      G.msgAll("bad", "pve.retry", n)
    end
  end
  -- 新一局：打通了就换下一关；开局在屏幕上播一遍这一关的作战简报（敌情、任务、友军）
  G.on("roundStart", function()
    local P = G.pve
    if P and P.next then apply(P.next) end
    if G.pve then G.msgAll("info", "pve.b" .. G.pve.n) end
  end)
end

return Pve
