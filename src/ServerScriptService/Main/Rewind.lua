-- 全面大战场——开枪的延迟补偿：服务器记下每个实体命中盒、每个真人角色最近零点八秒的位置，
--   真人开枪（步枪、狙击枪，车上 / 工事 / 船上自己操作的机枪）时，按「他屏幕上看到的那一刻」的位置再判一次打没打中。
--   为什么要：客户端画别人是快照插值（View.lua 的 G.follow，比收到的位置晚约 1.3 个更新间隔，机器人约 0.13 秒），
--     再加上网络来回，瞄着跑动的小兵身体中间开枪，服务器上小兵已经往前走了两三格，原来只按「现在」的位置判定就打空了。
--   规矩：
--     · 只有按现在的位置没打中实体 / 角色时才往回找（现在就打中了照旧；先打中自己人、墙、地形的照旧挡住）；
--     · 往回找的那一刻 = 现在 −（画面晚的那一截 + 延迟），延迟按 GetNetworkPing 估：它是单程还是来回说不清，
--       一倍到两倍之间都找，前后再各放宽 SPREAD；最多往回 MAXBACK 秒（作弊的人也只能多占这么一点便宜）；
--     · 只找敌人（不打自己人、不打自己开的车），打中的点要在墙、地形前面（照现在的地图挡）。
local Rewind = {}

function Rewind.init(G)
  local now = os.clock
  local KEEP = 0.8        -- 记多久（秒）
  local STEP = 0.05       -- 多久记一次（20 次 / 秒，中间按时间插值）
  local MAXBACK = 0.6     -- 最多往回推多久
  local VIEW_ENT = 0.13   -- 客户端画实体比收到的晚多少（View.lua G.follow：1.3 × 更新间隔 0.1 秒）
  local VIEW_CHAR = 0.10  -- 别的真人角色：Roblox 自己的插值
  local SPREAD = 0.06     -- 估的时刻前后各放宽多少
  local SAMPLE = 0.035    -- 窗口里每隔多久试一次
  -- 真人角色挨打的零件（R15，没有的话 R6）
  local PARTS = { "Head", "UpperTorso", "LowerTorso", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg",
    "LeftUpperArm", "RightUpperArm", "Torso", "Left Leg", "Right Leg", "Left Arm", "Right Arm", "HumanoidRootPart" }

  local entHist = {}    -- [实体 e] = { { t, cf, size }, … }（命中盒：小兵是随姿势变的 Hit，别的是 Root）
  local charHist = {}   -- [角色 Model] = { P = 谁, list = { { t, cf }, … } }（HumanoidRootPart）

  local function push(list, s)
    list[#list + 1] = s
    while #list > 1 and s.t - list[1].t > KEEP do table.remove(list, 1) end
  end

  local function record()
    local t = now()
    for _, e in ipairs(G.ents or {}) do
      local hb = e.alive and (e.hit or e.root)
      if hb and hb.Parent then
        local list = entHist[e]
        if not list then list = {} entHist[e] = list end
        push(list, { t = t, cf = hb.CFrame, size = hb.Size })
      end
    end
    for e in pairs(entHist) do
      if not e.alive or not (G.entById and G.entById[e.id] == e) then entHist[e] = nil end
    end
    local live = {}
    for _, P in pairs(G.P) do
      local char = P.alive and P.char
      local hrp = char and char.Parent and char:FindFirstChild("HumanoidRootPart")
      if hrp then
        live[char] = true
        local h = charHist[char]
        if not h then h = { list = {} } charHist[char] = h end
        h.P = P
        push(h.list, { t = t, cf = hrp.CFrame })
      end
    end
    for char in pairs(charHist) do
      if not live[char] then charHist[char] = nil end
    end
  end

  local acc = 0
  G.onFrame(function(dt)
    acc += dt
    if acc >= STEP then
      acc = 0
      record()
    end
  end)

  -- t 时刻的样子（前后两次记录之间按时间插值；超出记录的范围用最近的一次）
  local function at(list, t)
    local n = #list
    if n == 0 then return nil end
    if t >= list[n].t then return list[n].cf, list[n].size end
    if t <= list[1].t then return list[1].cf, list[1].size end
    for i = n, 2, -1 do
      local a = list[i - 1]
      if a.t <= t then
        local b = list[i]
        return a.cf:Lerp(b.cf, (t - a.t) / math.max(1e-4, b.t - a.t)), b.size
      end
    end
    return list[1].cf, list[1].size
  end

  -- 射线（起点 o、单位方向 d）打一个方盒（cf、size），maxT 以内打中返回距离
  local function slab(p, v, h, tmin, tmax)
    if math.abs(v) < 1e-9 then
      if p < -h or p > h then return nil end
      return tmin, tmax
    end
    local t1, t2 = (-h - p) / v, (h - p) / v
    if t1 > t2 then t1, t2 = t2, t1 end
    if t1 > tmin then tmin = t1 end
    if t2 < tmax then tmax = t2 end
    if tmin > tmax then return nil end
    return tmin, tmax
  end
  local function rayBox(o, d, cf, size, maxT)
    local lo = cf:PointToObjectSpace(o)
    local ld = cf:VectorToObjectSpace(d)
    local tmin, tmax = slab(lo.X, ld.X, size.X / 2, 0, maxT)
    if tmin then tmin, tmax = slab(lo.Y, ld.Y, size.Y / 2, tmin, tmax) end
    if tmin then tmin, tmax = slab(lo.Z, ld.Z, size.Z / 2, tmin, tmax) end
    return tmin
  end
  G.rayBox = rayBox

  -- 这段时间里最快挪了多少格 / 秒（粗筛用）
  local function speedOf(list)
    local a, b = list[1], list[#list]
    if not a or a == b then return 0 end
    return (b.cf.Position - a.cf.Position).Magnitude / math.max(0.05, b.t - a.t)
  end

  local function pingOf(P)
    local ok, v = pcall(function() return P.pl:GetNetworkPing() end)
    if ok and type(v) == "number" and v == v and v >= 0 then return math.min(v, 0.5) end
    return 0.08
  end

  -- 往回找的几个时刻：[现在 −（画面晚 + 两倍延迟）− SPREAD，现在 −（画面晚 + 一倍延迟）+ SPREAD]，最多往回 MAXBACK
  local function times(t0, view, ping)
    local far = math.min(MAXBACK, view + 2 * ping + SPREAD)
    local near = math.min(far, math.max(0, view + ping - SPREAD))
    local out = {}
    local k = near
    while k < far do
      out[#out + 1] = t0 - k
      k += SAMPLE
    end
    out[#out + 1] = t0 - far
    return out, far
  end

  -- 粗筛：现在的位置离射线够不着就不用一刻一刻地试
  local function nearRay(o, d, len, pos, reach)
    local rel = pos - o
    local along = rel:Dot(d)
    if along < -reach or along > len + reach then return false end
    return (rel - d * along).Magnitude <= reach
  end

  -- 真人 P 从 o 朝 d（单位向量）开枪，len 以内（墙、地形挡住的地方以前）有没有打中他屏幕上那一刻的敌人
  --   返回 { e = 实体, cf, size, pos } 或 { char = 角色, part = 零件, pos }
  function G.rewindTrace(P, o, d, len)
    if not P or not P.pl then return nil end
    local t0 = now()
    local ping = pingOf(P)
    local best, bestT = nil, len
    local ts, back = times(t0, VIEW_ENT, ping)
    for e, list in pairs(entHist) do
      if e.alive and e.team ~= P.team and e ~= P.vehicle and e ~= P.remote and #list > 0 then
        local last = list[#list]
        local reach = last.size.Magnitude / 2 + speedOf(list) * (back + 0.1) + 2
        if nearRay(o, d, bestT, last.cf.Position, reach) then
          for _, t in ipairs(ts) do
            local cf, size = at(list, t)
            local hitT = rayBox(o, d, cf, size, bestT)
            if hitT and hitT < bestT then best, bestT = { e = e, cf = cf, size = size }, hitT end
          end
        end
      end
    end
    local tsC, backC = times(t0, VIEW_CHAR, ping)
    for char, h in pairs(charHist) do
      local Q = h.P
      local hrp = char:FindFirstChild("HumanoidRootPart")
      if Q and Q ~= P and Q.alive and Q.team ~= P.team and hrp and #h.list > 0 then
        local reach = 6 + speedOf(h.list) * (backC + 0.1)
        if nearRay(o, d, bestT, h.list[#h.list].cf.Position, reach) then
          local nowCF = hrp.CFrame
          local parts = {}
          for _, name in ipairs(PARTS) do
            local part = char:FindFirstChild(name)
            if part and part:IsA("BasePart") then parts[#parts + 1] = { part, nowCF:ToObjectSpace(part.CFrame) } end
          end
          for _, t in ipairs(tsC) do
            local cf = at(h.list, t)
            for _, it in ipairs(parts) do
              local hitT = rayBox(o, d, cf * it[2], it[1].Size, bestT)
              if hitT and hitT < bestT then best, bestT = { char = char, part = it[1] }, hitT end
            end
          end
        end
      end
    end
    if best then best.pos = o + d * bestT end
    return best
  end

  -- 这个零件是不是实体或真人角色的（现在的位置就打中了，不用往回找）
  local function isTarget(inst)
    if G.entOf(inst) then return true end
    local m = inst:FindFirstAncestorOfClass("Model")
    while m do
      if m:FindFirstChildOfClass("Humanoid") then return true end
      m = m:FindFirstAncestorOfClass("Model")
    end
    return false
  end

  -- 照现在的位置打的那一枪（res：workspace:Raycast 的结果）没打中实体 / 角色时，按 P 屏幕上那一刻再判一次
  function G.rewindShot(P, o, d, range, res)
    if not P or not P.pl then return nil end
    if res and res.Instance and isTarget(res.Instance) then return nil end
    local len = res and (res.Position - o).Magnitude or range
    return G.rewindTrace(P, o, d, len)
  end

  -- 往回找打中的：照 Ents.lua hitThing 的规矩扣血（小兵命中盒上面 headTop 格算爆头；真人打在 Head 上算爆头）
  function G.hitRewound(rw, w, dmg, src, headMul)
    if rw.e then
      local e = rw.e
      local head = e.headTop ~= nil and rw.pos.Y > rw.cf.Position.Y + rw.size.Y / 2 - e.headTop
      local k = head and (headMul or 1) or 1
      G.damageEnt(e, dmg * G.mult(w, e.cat) * k, src, head and (headMul or 1) > 1)
      return true
    elseif rw.char then
      local k = (rw.part.Name == "Head") and (headMul or 1) or 1
      return G.hurtChar(rw.char, dmg * G.mult(w, "inf") * k, src, rw.part)
    end
    return false
  end
end

return Rewind
