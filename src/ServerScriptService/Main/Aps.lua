-- Roblox全面大战场——主动防御系统（硬杀伤拦截，用户 11-19：给坦克实现主动拦截系统；改装里选装，TankMods.OPT.hk）
--   炮塔两侧各一个发射器（各两发）、四角雷达板：来袭的火箭弹、导弹（Ents.lua 每步问 G.apsCheck）飞到车外十来米、确实冲着这辆车来时，
--     朝它那一侧的发射器打一发，在空中把它打爆——这一发就没了，不伤车
--   拦不了的：坦克炮弹（动能弹太快）、炸弹、从头顶陡着砸下来的（雷达往上只看到 60°）；两次拦截至少隔 gap 秒（齐射能打穿）、弹打光了等补
--   每 reload 秒补一发；模型属性 Aps（剩几发）、ApsMax 给客户端（驾驶界面、发射器的样子）；特效 { k = "aps" }（ArmorFx.lua）
--   拦截的破片会伤到车旁边的步兵（真的系统也是这样）
local RS = game:GetService("ReplicatedStorage")

local Aps = {}

function Aps.init(G)
  local TM = require(RS:WaitForChild("TankMods"))
  local V = Vector3.new
  local now = os.clock
  local RANGE = 30       -- 来袭弹离车中心多近开打（格，约 11 米）
  local LOOK = 90        -- 雷达看多远（格）
  local ELEV = 60        -- 往上最多看多高（度）

  function G.apsSetup(e)
    local m = e.def and e.def.mods
    local o = m and TM.OPT[m.aps]
    if not o or not o.n then return end
    e.aps = { n = o.n, max = o.n, gap = o.gap or 0.6, reload = o.reload or 30, next = 0, refill = now() + (o.reload or 30) }
    e.model:SetAttribute("Aps", o.n)
    e.model:SetAttribute("ApsMax", o.n)
  end

  -- 补弹（每帧）
  G.onFrame(function()
    local t = now()
    for _, e in ipairs(G.vehicles or {}) do
      local A = e.aps
      if A and e.alive and A.n < A.max and t >= A.refill then
        A.n += 1
        A.refill = t + A.reload
        e.model:SetAttribute("Aps", A.n)
      elseif A and A.n >= A.max then
        A.refill = t + A.reload
      end
    end
  end)

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
      if A and e.alive and A.n > 0 and t >= A.next and e.team ~= team then
        local c = e.root.CFrame.Position
        local rel = s.pos - c
        local dist = rel.Magnitude
        if dist < LOOK and rel:Dot(vel) < 0 then
          -- 冲着这辆车来：照现在的速度，离车中心最近的时候在车身范围里
          local tc = -rel:Dot(vel) / (sp * sp)
          local miss = (rel + vel * tc).Magnitude
          local body = math.max(e.def.L, e.def.W) * 0.5 + 3
          local elev = math.deg(math.asin(math.clamp(rel.Y / math.max(dist, 1e-3), -1, 1)))
          if miss < body and elev < ELEV and dist < RANGE + sp * (dt or 1 / 30) then
            A.n -= 1
            A.next = t + A.gap
            A.refill = math.max(A.refill, t + A.reload)
            e.model:SetAttribute("Aps", A.n)
            -- 哪一侧的发射器：来袭弹在炮塔的左边还是右边
            local base = e.root.CFrame
            local yaw = math.rad(e.ty or 0)
            local right = (base * CFrame.Angles(0, -yaw, 0)).RightVector
            local side = (rel:Dot(right) >= 0) and 1 or -1
            G.fx({ k = "aps", id = e.id, p = s.pos, side = side, v = vel.Unit })
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
    return false
  end
end

return Aps
