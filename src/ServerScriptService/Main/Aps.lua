-- Roblox全面大战场——主动防护系统（硬杀伤拦截，用户 11-19：给坦克实现主动拦截系统；用户 11-22 晚：改装体系照真实的系统做）
--   哪一套、几个发射单元、各管哪个方位、几发、高低角能管多高、多远开始跟踪、离车多远打，都在 TankMods.APS（出处写在那里）：
--     GL5（99A、96B）：四个发射单元各管一个象限、各一发，高低角 20°（陡着砸下来的攻顶弹拦不了），离车 10 米拦截
--     Trophy（M1A2 / M1A1）：两侧各一个能转的发射器，各管一侧，自动再装填（两发至少隔 1.5 秒）
--   来袭的火箭弹、导弹（Ents.lua 每步问 G.apsCheck）进了雷达的距离、确实冲着这辆车来（照现在的速度会打到车身），
--     飞到离车 rng 格时，管它那个方位、还有弹、装填好了的发射单元打一发，把它在空中打爆——这一发就没了，不伤车
--   拦不了的：坦克炮弹（动能弹太快）、炸弹、超出高低角的；打光了等补（regen 秒补一发，游戏里的补给）
--   模型属性 Aps（还剩几发）、ApsMax、ApsL（每个发射单元剩几发，逗号隔开）给客户端（驾驶界面、改装界面）；特效 { k = "aps", side, li }（ArmorFx.lua）
--   拦截的破片会伤到车旁边的步兵（真的系统也是这样）
local RS = game:GetService("ReplicatedStorage")

local Aps = {}

function Aps.init(G)
  local TM = require(RS:WaitForChild("TankMods"))
  local V = Vector3.new
  local now = os.clock

  local function sync(e)
    local A = e.aps
    local n, parts = 0, {}
    for _, L in ipairs(A.L) do
      n += L.n
      table.insert(parts, tostring(L.n))
    end
    A.n = n
    e.model:SetAttribute("Aps", n)
    e.model:SetAttribute("ApsL", table.concat(parts, ","))
  end

  function G.apsSetup(e)
    local m = e.def and e.def.mods
    local sys = m and TM.APS[m.aps]
    if not sys then return end
    local L, max = {}, 0
    for _, l in ipairs(sys.launchers) do
      table.insert(L, { az = l.az, span = l.span, n = l.n, max = l.n, next = 0, refill = 0 })
      max += l.n
    end
    e.aps = { sys = sys, key = m.aps, L = L, max = max, n = max }
    e.model:SetAttribute("ApsMax", max)
    e.model:SetAttribute("ApsSys", m.aps)
    sync(e)
  end

  -- 补弹（每帧）：每个发射单元自己补
  G.onFrame(function()
    local t = now()
    for _, e in ipairs(G.vehicles or {}) do
      local A = e.aps
      if A and e.alive then
        local changed = false
        for _, l in ipairs(A.L) do
          if l.n < l.max then
            if l.refill == 0 then l.refill = t + A.sys.regen end
            if t >= l.refill then
              l.n += 1
              l.refill = (l.n < l.max) and (t + A.sys.regen) or 0
              changed = true
            end
          end
        end
        if changed then sync(e) end
      end
    end
  end)

  local function angDiff(a, b) return (a - b + 180) % 360 - 180 end

  -- 飞行中的弹 s 这一步要不要被拦：返回 true 就是被打掉了（Ents.lua 收走它，不炸、不伤车）
  function G.apsCheck(s, dt)
    if s.kind ~= "rocket" and s.kind ~= "missile" then return false end
    local vel = s.vel
    local sp = vel.Magnitude
    if sp < 5 then return false end
    local team = s.src and s.src.team
    local t = now()
    for _, e in ipairs(G.vehicles or {}) do
      local A = e.aps
      if A and e.alive and A.n > 0 and e.team ~= team then
        local sys = A.sys
        local c = e.root.CFrame.Position
        local rel = s.pos - c
        local dist = rel.Magnitude
        if dist < sys.look and rel:Dot(vel) < 0 then
          -- 冲着这辆车来：照现在的速度，离车中心最近的时候在车身范围里
          local tc = -rel:Dot(vel) / (sp * sp)
          local miss = (rel + vel * tc).Magnitude
          local body = math.max(e.def.L, e.def.W) * 0.5 + 3
          if miss < body and dist < sys.rng + e.def.L * 0.5 + sp * (dt or 1 / 30) then
            local base = e.root.CFrame * CFrame.new(0, -e.def.H / 2, 0)
            local az, el = TM.bearing(base, e.ty or 0, s.pos)
            if el <= sys.elev then
              -- 管这个方位、有弹、装填好了的发射单元（离它中心最近的先打）
              local best, bd = nil, math.huge
              for i, l in ipairs(A.L) do
                local d = math.abs(angDiff(az, l.az))
                if d <= l.span and l.n > 0 and t >= l.next and d < bd then best, bd = i, d end
              end
              if best then
                local l = A.L[best]
                l.n -= 1
                l.next = t + sys.gap
                if l.refill == 0 then l.refill = t + sys.regen end
                sync(e)
                local side = (az >= 0) and 1 or -1
                G.fx({ k = "aps", id = e.id, p = s.pos, side = side, li = best, sys = A.key, v = vel.Unit })
                -- 拦截破片：车旁边、拦截点附近的步兵挨一点
                for _, P in pairs(G.P) do
                  local hrp = P.char and P.char:FindFirstChild("HumanoidRootPart")
                  if hrp and P.alive and not G.inVeh(P) then
                    local dd = (hrp.Position - s.pos).Magnitude
                    if dd < 9 then G.hurtChar(P.char, 35 * (1 - dd / 9), { team = e.team, name = "APS" }) end
                  end
                end
                local D = e.driver
                if D and D.pl then G.msg(D.pl, "good", "aps.hit", A.n) end
                local SP = s.src and s.src.P
                if SP and SP.pl then G.msg(SP.pl, "bad", "aps.blocked") end
                G.apsHits = (G.apsHits or 0) + 1   -- 测试用
                return true
              end
            end
          end
        end
      end
    end
    return false
  end
end

return Aps
