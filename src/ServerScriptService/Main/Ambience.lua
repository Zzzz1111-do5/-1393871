-- Roblox全面大战场——战场氛围（用户：感受不到激烈对抗）：开战以后当前阶段的目标一带不停地落炮弹——七成是攻方舰炮砸守方阵地（据点后面、两边），
--   三成是守方炮兵打滩头和海面；每个阶段开头 60 秒是火力准备，炮弹密；越往后的阶段越密。头顶隔一会儿两架战机呼啸着低空掠过（两边轮流）。
--   只有声音和火光、不伤人：落点离任何人（玩家、机器人）至少 70 格，免得看着炸在身边却不掉血；飞过去的飞机是客户端画的（TacPad.lua 的 flyby）。
--   每个阶段开头 60 秒的火力准备专砸当前目标附近的守方工事（碉堡、岸防炮、高炮）：炮弹落在 60 格以内的工事缩着停火 4 秒（Forts.lua supUntil）——
--   只压制、不摧毁，掩护第一波登陆（机器人对打：工事对着唯一的登陆滩，攻方一半的阵亡是工事打的，一个点都拿不下）
local Ambience = {}

function Ambience.init(G)
  local Map = G.Map
  local V = Vector3.new
  local now = os.clock
  local SAFE = 70        -- 落点离人至少多远
  local nextShell, nextFly, flySide = 0, 0, "atk"

  -- 这里周围 r 格内没人（玩家、机器人、载具里的人都算）
  local function clear(x, z, r)
    local r2 = r * r
    for _, P in pairs(G.P) do
      if P.alive and P.char then
        local hrp = P.char:FindFirstChild("HumanoidRootPart")
        if hrp and (hrp.Position.X - x) ^ 2 + (hrp.Position.Z - z) ^ 2 < r2 then return false end
      end
    end
    if G.countAt then
      local a, d = G.countAt(x, z, Map.ground(x, z), r)
      if (a or 0) + (d or 0) > 0 then return false end
    end
    return true
  end

  -- 一发炮弹：先呼啸（客户端 shell 特效：落地前一秒多响），1.3 秒后陆地上炸开、海里溅起水柱；落在守方工事 60 格以内的压制它 4 秒
  local function shell(x, z)
    local land = Map.isLand(x, z)
    local y = land and Map.ground(x, z) or 0
    local p = V(x, y + 0.5, z)
    G.fx({ k = "shell", p = p, t = 1.3 })
    task.delay(1.3, function()
      if land then G.fx({ k = "boom", p = p, s = 1.1 + math.random() * 0.7 }) else G.fx({ k = "splash", p = p }) end
      for _, f in ipairs(G.forts or {}) do
        if f.alive and f.team == "def" and f.base then
          local q = f.base.Position
          if (q.X - x) ^ 2 + (q.Z - z) ^ 2 < 60 * 60 then f.supUntil = math.max(f.supUntil or 0, now() + 4) end
        end
      end
    end)
  end
  -- 当前目标 700 格以内的守方工事（火力准备的靶子）
  local function fortsNear(o)
    local out = {}
    for _, f in ipairs(G.forts or {}) do
      if f.alive and f.team == "def" and f.base then
        local q = f.base.Position
        if (q.X - o.x) ^ 2 + (q.Z - o.z) ^ 2 < 700 * 700 then table.insert(out, q) end
      end
    end
    return out
  end

  G.onFrame(function()
    local R = G.round
    if not R or R.phase ~= "battle" or not G.objectives then return end
    local t = now()
    local objs = G.objectives(false)
    if #objs == 0 then return end
    if t >= nextShell then
      local heavy = t - (R.stageAt or 0) < 60   -- 每个阶段开头：火力准备
      local k = 0.85 + 0.15 * (R.stage or 1)    -- 越往后越密
      nextShell = t + (heavy and (0.45 + math.random() * 0.5) or (2.2 + math.random() * 2.8)) / k
      local o = objs[math.random(#objs)]
      local fs = heavy and fortsNear(o) or {}
      if #fs > 0 and math.random() < 0.75 then   -- 火力准备：砸工事（落点在工事 15～45 格以内，离人照样至少 SAFE 格）
        local q = fs[math.random(#fs)]
        for _ = 1, 6 do
          local a, r = math.random() * math.pi * 2, 15 + math.random() * 30
          local x, z = q.X + math.cos(a) * r, q.Z + math.sin(a) * r
          if clear(x, z, SAFE) then shell(x, z) return end
        end
      end
      for _ = 1, 8 do
        local defSide = math.random() < 0.7
        local a = math.random() * math.pi
        local r = (defSide and 110 or 200) + math.random() * 380
        local x = o.x + math.cos(a) * r
        local z = o.z + (defSide and -1 or 1) * math.sin(a) * r   -- 守方在北（−Z），攻方从南边来
        if clear(x, z, SAFE) then
          shell(x, z)
          break
        end
      end
    end
    if t >= nextFly then   -- 两架战机掠过目标上空（两边轮流）
      nextFly = t + 32 + math.random() * 28
      local o = objs[math.random(#objs)]
      local a = math.random() * math.pi * 2
      G.fx({ k = "flyby", p = V(o.x, math.max(Map.ground(o.x, o.z), 0), o.z), d = V(math.cos(a), 0, math.sin(a)), team = flySide, n = 2 })
      flySide = (flySide == "atk") and "def" or "atk"
    end
  end)
end

return Ambience
