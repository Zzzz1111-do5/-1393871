-- 全面大战场——一张图一个服务器（用户 11-28「能不能这样 训练场 还有各种地图单独做成一个服务器」）
--   Roblox 的一个游戏（体验）里可以有好几个地点（place），每个地点开自己的服务器；这些地点用同一份地点文件（同一套脚本），
--   按地点的名字认自己是哪一种（Studio 的「资源管理器 → 地点」里起名，再把同一份地点文件分别发布到每个地点）：
--     名字里有「训练场 / range」→ 训练场服务器：开雪山图（Config.RangeMap），只试驾（每人一条靶道、靶车、靶机：SnowRange.lua），不开对战
--     「钢城 / city」「雪山 / snow」「沙海 / sands」→ 只打这一张图（不投票）
--     别的名字（起始地点）→ 照旧：选地图投票（有自己地点的那几张图不投，点了直接传送过去）
--   有训练场地点时，别的服务器点「试驾」把人传送过去（带着要试的那一辆，到了自动坐进去）；训练场里点「开战」/ 选图传送回去打。
--   传送前先存档（Store.lua G.saveNow 等写进去）；传送没成功就留在这个服务器（试驾照旧在本服务器的训练场区块）。
--   Studio 里 Roblox 不让传送：照旧一个服务器全包（投票选图、训练场区块 Zones.RANGE）；想在 Studio 里看某一种服务器，
--   给 Workspace 设属性 PlaceRole = "range" / "snow" / "city" / "sands"
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Places = {}

-- 地点名里的字 → 哪一种（先认训练场：「雪山训练场」是训练场）
local WORDS = {
  { "range", { "训练场", "訓練場", "试驾", "試駕", "range", "training", "testdrive", "test drive" } },
  { "snow", { "雪山", "snow" } },
  { "city", { "钢城", "鋼城", "city" } },
  { "sands", { "沙海", "sands" } },
}
function Places.roleOfName(name)
  if type(name) ~= "string" then return nil end
  local low = string.lower(name)
  for _, w in ipairs(WORDS) do
    for _, k in ipairs(w[2]) do
      if string.find(low, k, 1, true) then return w[1] end
    end
  end
  return nil
end

function Places.init(G)
  local Config = G.Config
  local Map = G.Map
  local ROLES = { all = true, range = true }
  for _, id in ipairs(Map.ids or {}) do ROLES[id] = true end
  for _, id in ipairs(Map.extra or {}) do ROLES[id] = true end
  G.placeRole = "all"
  G.placeIds = {}      -- [种类] = PlaceId（这个游戏里别的地点；有才能传送过去）
  G.placesReady = false
  local studio = RunService:IsStudio()
  local function publish()
    local maps = {}
    for id in pairs(G.placeIds) do if id ~= "range" and id ~= "all" then maps[#maps + 1] = id end end
    table.sort(maps)
    pcall(function()
      RS:SetAttribute("PlaceRole", G.placeRole)
      RS:SetAttribute("PlaceMaps", table.concat(maps, ","))
      RS:SetAttribute("RangePlace", G.placeIds.range ~= nil and G.placeRole ~= "range")
    end)
  end
  -- 能不能传送去那一种：Studio 里不行；没有那个地点不行；就是这个服务器自己那一种不用传
  function G.placeFor(role)
    if (studio and not G.placeLive) or G.placeTpOff then return nil end   -- G.placeLive：测试台当成线上（能传送）
    if role == G.placeRole then return nil end
    return G.placeIds[role]
  end

  -- 认身份：Workspace 的 PlaceRole（Studio、测试台）> 地点名（线上：AssetService 列出这个游戏的所有地点）> all
  task.spawn(function()
    local forced = nil
    pcall(function() forced = workspace:GetAttribute("PlaceRole") end)
    if type(forced) == "string" and ROLES[forced] then
      G.placeRole = forced
    elseif not studio then
      local ok, err = pcall(function()
        local AS = game:GetService("AssetService")
        local pages = AS:GetGamePlacesAsync()
        while true do
          for _, pl in ipairs(pages:GetCurrentPage()) do
            local role = Places.roleOfName(pl.Name)
            if pl.PlaceId == game.PlaceId then
              G.placeRole = role or "all"
            elseif role and not G.placeIds[role] then
              G.placeIds[role] = pl.PlaceId
            elseif not role and not G.placeIds.all then
              G.placeIds.all = pl.PlaceId   -- 起始地点（名字里没写哪一种）：训练场里点「开战」、没有自己地点的图都传回这里
            end
          end
          if pages.IsFinished then break end
          pages:AdvanceToNextPageAsync()
        end
      end)
      if not ok then warn("[地点] 列不出这个游戏的地点（" .. tostring(err) .. "）：照一个服务器全包") end
      if G.placeIds[G.placeRole] == game.PlaceId then G.placeIds[G.placeRole] = nil end
    end
    if G.placeRole ~= "all" then
      local extra = {}
      for k, v in pairs(G.placeIds) do extra[#extra + 1] = k .. "=" .. tostring(v) end
      print("[地点] 这个服务器是「" .. G.placeRole .. "」；别的地点：" .. (#extra > 0 and table.concat(extra, " ") or "没有"))
    elseif next(G.placeIds) then
      local extra = {}
      for k, v in pairs(G.placeIds) do extra[#extra + 1] = k .. "=" .. tostring(v) end
      print("[地点] 起始服务器（投票选图）；别的地点：" .. table.concat(extra, " "))
    end
    -- 训练场服务器：不开对战（没有人机、工事不开火、不匹配）
    if G.placeRole == "range" then
      G.aiVehOff, G.fortsHold, G.navyNoAI = true, true, true
      if Config.Bots then Config.Bots.minPerTeam = 0 end
      G.rangePlace = true
    end
    publish()
    G.placesReady = true
  end)
  -- 等身份认完（开服时 init.server.lua 的选图、训练场区块要看它；最多等几秒）
  function G.placesWait(maxT)
    local t0 = os.clock()
    while not G.placesReady and os.clock() - t0 < (maxT or 10) do task.wait(0.1) end
    return G.placesReady
  end
  -- 这一种服务器开哪张图（nil = 投票）
  function G.placeMap()
    local r = G.placeRole
    if r == "range" then return Config.RangeMap or "snow" end
    if r ~= "all" and Map.profile(r) then return r end
    return nil
  end
  -- 本服务器要不要自己建训练场区块：训练场服务器不用（雪山图上试驾）；有能传过去的训练场地点也不用（传送没成功时再建：G.ensureRange）
  function G.wantLocalRange()
    if G.placeRole == "range" then return false end
    return G.placeFor("range") == nil
  end

  ---------------------------------------------------------------- 传送
  local TS = game:GetService("TeleportService")
  local going = {}   -- [Player] = { role, data, t, fallback }
  -- 把一个人传到另一种服务器（data：到了要做的事，{ td = 试驾的车 } / { battle = 出击的车 } / { map = 地图 }）；
  --   fallback：传不过去时在本服务器照做的（试驾就在本服务器的训练场区块里试）。返回 true = 已经在传了
  function G.teleport(P, role, data, fallback)
    local id = G.placeFor(role)
    if not id or not P or not P.pl or going[P.pl] then return false end
    going[P.pl] = { role = role, data = data, t = os.clock(), fallback = fallback }
    G.msg(P.pl, "info", "place.going", { k = "place." .. role })
    task.spawn(function()
      if G.saveNow then pcall(G.saveNow, P) end   -- 先存档写进去（到了那边读到的是新的；没写成也传：那边按版本号合并解锁）
      local td = { from = G.placeRole, fromId = game.PlaceId }
      for k, v in pairs(data or {}) do td[k] = v end
      local ok, err = pcall(function()
        local opt = Instance.new("TeleportOptions")
        opt:SetTeleportData(td)
        TS:TeleportAsync(id, { P.pl }, opt)
      end)
      if not ok then
        local g = going[P.pl]
        going[P.pl] = nil
        warn("[地点] " .. P.pl.Name .. " 传送到「" .. role .. "」没成功：" .. tostring(err))
        G.msg(P.pl, "bad", "place.fail")
        if g and g.fallback then G.try("传送失败后", g.fallback) end
      end
    end)
    return true
  end
  -- 换到另一张图（用户 11-28 晚「然后目前没法切地图」）：一个服务器开服只建一张图、建好以后换不了——
  --   这张图有自己的地点：传送过去（上面 G.teleport）；没有：开一个这个地点的新服务器（预留服务器），带着要打的图传过去，
  --   那边进来就按这张开（init.server.lua waitMap 读传送数据里的 map）；同一张图十分钟内都传进同一个新服务器（一起点的人到一处）。
  --   Studio 里不能传送：告诉他停止后重新开始、进机库先在「这一局」那里选图
  local reserved = {}   -- [图] = { code, t }
  function G.switchMap(P, id)
    if not P or not P.pl or type(id) ~= "string" then return false end
    if G.placeFor(id) then return G.teleport(P, id, { map = id }) end
    if not table.find(Map.ids or {}, id) then return false end   -- 收起来的图（钢城 11-28 晚先不显示）不换
    if (studio and not G.placeLive) or G.placeTpOff then
      G.msg(P.pl, "info", "map.switchStudio", { k = "map." .. id .. ".name" })
      return false
    end
    if going[P.pl] then return false end
    going[P.pl] = { role = id, data = { map = id }, t = os.clock() }
    G.msg(P.pl, "info", "map.switchNew", { k = "map." .. id .. ".name" })
    task.spawn(function()
      if G.saveNow then pcall(G.saveNow, P) end
      local r = reserved[id]
      if not r or os.clock() - r.t > 600 then
        local ok, code = pcall(function() return TS:ReserveServer(game.PlaceId) end)
        if ok and type(code) == "string" then r = { code = code, t = os.clock() } reserved[id] = r else r = nil end
      end
      local ok, err = false, "预留服务器没开成"
      if r then
        ok, err = pcall(function()
          local opt = Instance.new("TeleportOptions")
          opt.ReservedServerAccessCode = r.code
          opt:SetTeleportData({ from = G.placeRole, fromId = game.PlaceId, map = id })
          TS:TeleportAsync(game.PlaceId, { P.pl }, opt)
        end)
      end
      if not ok then
        going[P.pl] = nil
        reserved[id] = nil
        warn("[地点] " .. P.pl.Name .. " 换图到「" .. id .. "」没成功：" .. tostring(err))
        G.msg(P.pl, "bad", "map.switchFail")
      end
    end)
    return true
  end
  pcall(function()
    TS.TeleportInitFailed:Connect(function(pl, result, msg)
      local g = going[pl]
      going[pl] = nil
      if not g then return end
      warn("[地点] " .. pl.Name .. " 传送到「" .. g.role .. "」失败（" .. tostring(result) .. "）：" .. tostring(msg))
      G.msg(pl, "bad", "place.fail")
      if g.fallback then G.try("传送失败后", g.fallback) end
    end)
  end)
  Players.PlayerRemoving:Connect(function(pl) going[pl] = nil end)
  G.teleporting = function(pl) return going[pl] ~= nil end

  ---------------------------------------------------------------- 传过来的人：到了接着做（试驾那一辆 / 排队开战）
  local function arrived(pl)
    local ok, jd = pcall(function() return pl:GetJoinData() end)
    local td = ok and type(jd) == "table" and jd.TeleportData or nil
    if type(td) ~= "table" then return end
    if type(td.from) ~= "string" or td.from == "" then return end
    -- 存档读好、这个服务器的图建好（训练场：雪山图上的靶道算好）才做
    local t0 = os.clock()
    local P
    repeat
      task.wait(0.5)
      P = G.P[pl]
    until (P and P.data and G.worldReady and (G.round ~= nil) and (G.placeRole ~= "range" or G.rangeReady)) or os.clock() - t0 > 180 or pl.Parent ~= Players
    if not P or pl.Parent ~= Players then return end
    P.cameFrom = td.from
    if type(td.td) == "string" and G.ACT.testDrive then
      G.try("传送来试驾", G.ACT.testDrive, P, td.td)
    elseif type(td.battle) == "string" and G.ACT.matchJoin then
      G.try("传送来开战", G.ACT.matchJoin, P, td.battle)
    end
  end
  Players.PlayerAdded:Connect(function(pl) task.spawn(arrived, pl) end)
  for _, pl in ipairs(Players:GetPlayers()) do task.spawn(arrived, pl) end
  G.placeArrived = arrived   -- 测试用
end

return Places
