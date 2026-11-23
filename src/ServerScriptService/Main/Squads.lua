-- 全面大战场——小队（用户 11-23「这个游戏按你想的来弄」：战地的小队——四个人一组，能在队友身边出生，倒了先找自己的小队救）
--   进了阵营就自动分进本队的小队（每队 A、B、C……，一队 Config.Squad.size 人，先把没满的填满）；换了阵营重新分；走了腾出位置。
--   小队号写在玩家的属性 Squad 上（所有客户端都看得见：小队面板、队友头顶的绿色标记，Squads.lua 客户端）
--   在小队队友身边出生（部署界面的「小队：某某」，Round.lua 的出生点表）：队友活着、没倒地、不在载具里、站在陆地上、
--     Config.Squad.safe 秒内没挨过打（交火中不能往他身边出）；出生在他身后几格（墙挡着就在他脚边）
local Squads = {}

function Squads.init(G)
  local Config = G.Config
  local SC = Config.Squad or { size = 4, safe = 6 }
  local now = os.clock
  local V = Vector3.new
  local LETTERS = { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L" }
  local squads = { atk = {}, def = {} }   -- [队][小队号] = { P, … }
  G.squadsOf = function(team) return squads[team] end   -- 测试用

  local function leave(P)
    local team, id = P.sqTeam, P.squad
    if team and id and squads[team] and squads[team][id] then
      local list = squads[team][id]
      for i, Q in ipairs(list) do if Q == P then table.remove(list, i) break end end
      if #list == 0 then squads[team][id] = nil end
    end
    P.squad, P.sqTeam = nil, nil
    pcall(function() P.pl:SetAttribute("Squad", nil) end)
  end
  local function join(P, team)
    local best, bn = nil, math.huge
    for _, id in ipairs(LETTERS) do
      local list = squads[team][id]
      if list and #list < SC.size and #list < bn then best, bn = id, #list end
    end
    if not best then
      for _, id in ipairs(LETTERS) do
        if not squads[team][id] then best = id squads[team][id] = {} break end
      end
    end
    if not best then return end
    table.insert(squads[team][best], P)
    P.squad, P.sqTeam = best, team
    pcall(function() P.pl:SetAttribute("Squad", best) end)
  end
  -- 同一个小队的另外几个人
  function G.squadMates(P)
    local list = P.squad and P.sqTeam and squads[P.sqTeam] and squads[P.sqTeam][P.squad] or {}
    local out = {}
    for _, Q in ipairs(list) do if Q ~= P and G.P[Q.pl] == Q then table.insert(out, Q) end end
    return out
  end

  -- 每秒对一次：没分的分进去、换了阵营的重新分、走了的去掉
  local acc = 0
  G.onFrame(function(dt)
    acc += dt
    if acc < 1 then return end
    acc = 0
    for team, set in pairs(squads) do
      for id, list in pairs(set) do
        for i = #list, 1, -1 do
          local Q = list[i]
          if G.P[Q.pl] ~= Q or Q.team ~= team then table.remove(list, i) if G.P[Q.pl] == Q then Q.squad, Q.sqTeam = nil, nil end end
        end
        if #list == 0 then set[id] = nil end
      end
    end
    for _, P in pairs(G.P) do
      if P.team == "atk" or P.team == "def" then
        if P.sqTeam ~= P.team or not P.squad then
          if P.squad then leave(P) end
          join(P, P.team)
        end
      end
    end
  end)

  -- 能不能往这个队友身边出生
  local function mateOk(Q)
    if not Q.alive or Q.downed or not Q.char then return false end
    if G.inVeh and G.inVeh(Q) then return false end
    if Q.boat or Q.chute then return false end
    local hrp = Q.char:FindFirstChild("HumanoidRootPart")
    local hum = Q.char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return false end
    local p = hrp.Position
    if G.Map and G.Map.isLand and not G.Map.isLand(p.X, p.Z) then return false end
    local log = Q.dmgLog
    local last = log and log[#log]
    if last and now() - last.t < (SC.safe or 6) then return false end   -- 交火中
    return true, hrp
  end
  -- 出生点表里加上小队队友（Round.lua 的 spawnList 调）
  function G.squadSpawns(team, P)
    local out = {}
    if not P or not G.round or G.round.phase ~= "battle" then return out end
    for _, Q in ipairs(G.squadMates(P)) do
      if Q.team == team then
        local ok, hrp = mateOk(Q)
        local p = hrp and hrp.Position
        table.insert(out, { id = "sq." .. Q.pl.UserId, kind = "squad", name = Q.pl.DisplayName, uid = Q.pl.UserId,
          x = p and p.X or nil, z = p and p.Z or nil, ok = ok == true })
      end
    end
    return out
  end
  -- 出生在队友身后几格（打一条线看看身后有没有墙；挡着就站他脚边）
  function G.squadSpawnCF(P, sp)
    local Q = nil
    for _, M in ipairs(G.squadMates(P)) do if M.pl.UserId == sp.uid then Q = M end end
    local ok, hrp = false, nil
    if Q then ok, hrp = mateOk(Q) end
    if not ok or not hrp then return nil end
    local cf = hrp.CFrame
    local back = V(-cf.LookVector.X, 0, -cf.LookVector.Z)
    back = (back.Magnitude > 0.01) and back.Unit or V(0, 0, 1)
    local from = cf.Position
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.FilterDescendantsInstances = { Q.char }
    local to = from + back * 4
    if workspace:Raycast(from, back * 4.5, rp) then to = from + V(0.8, 0, 0) end
    to += V(0, 0.4, 0)
    return CFrame.lookAt(to, to + V(cf.LookVector.X, 0, cf.LookVector.Z))
  end
end

return Squads
