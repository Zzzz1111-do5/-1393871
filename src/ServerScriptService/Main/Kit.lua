-- Roblox全面大战场——坦克加装件（TankMods 的 slat / belly / eng / ew / cam，用户 11-22 晚：「要能有一整套的坦克改装体系」「用现实中的标准」）
--   栅栏装甲：火箭弹（单装药破甲：步兵火箭筒、直升机火箭弹）从车尾、侧后打来，打在栅栏上约五成被卡坏引信（维基百科 Slat armor：约 50%），
--     不炸、不伤车（Ents.lua 问 G.kitRocket）；导弹、炮弹照打
--   车底防雷板：雷、炸药在车底炸，这辆车挨的减半（Forts.lua 炸雷时问 G.kitMineK）
--   扫雷犁：放下（客户端 Drive 的 op = "plow"，按键 N）以后车速不超过 15 公里 / 时，车头前面 4.2 米宽的通路里的雷被翻到两边（不炸车），
--     升起要 11 秒（Pearson 全宽扫雷犁的数）
--   激光告警（+ JD-3 激光压制）：激光制导的导弹冲着这辆车来时（Air.lua guideMissile 问 G.kitLaser）报警、报方向，自动打一组烟幕弹；
--     烟幕挡住激光，导弹丢了目标；JD-3 还有一定概率直接把照射干扰掉
--   多光谱伪装网：机器人、AI 车发现你的距离按 0.7 算（G.sigK）
local RS = game:GetService("ReplicatedStorage")

local Kit = {}

function Kit.init(G)
  local TM = require(RS:WaitForChild("TankMods"))
  local V, CF = Vector3.new, CFrame.new
  local now = os.clock

  local function kitOf(e) return e and e.def and e.def.kit end

  -- 隐身系数：这辆车被发现的距离乘几（伪装网 0.7）
  function G.sigK(e)
    local k = kitOf(e)
    return (k and k.mcs) and TM.KIT.mcs.spot or 1
  end

  -- 火箭弹打到东西（res：Raycast 结果）：打在带栅栏的车的车尾 / 侧后，一半被卡坏引信——返回 true 就是哑火（不炸）
  function G.kitRocket(s, res)
    if not res or not res.Instance then return false end
    local e = G.entOf and G.entOf(res.Instance)
    local k = kitOf(e)
    if not k or not k.slat or not e.alive then return false end
    -- 车体坐标里：打在车尾（后 40%）、或者从侧后 / 正后方来（来向和车头夹角 > 110°）才算在栅栏上
    local hull = e.root.CFrame
    local lp = hull:PointToObjectSpace(res.Position)
    local from = res.Position - s.vel.Unit * 4
    local lf = hull:PointToObjectSpace(from)
    local az = math.deg(math.atan2(lf.X, -lf.Z))
    local rear = lp.Z > e.def.L * 0.1
    if not (rear or math.abs(az) > 110) then return false end
    if lp.Y > e.def.H * 0.5 + 2 and not rear then return false end   -- 炮塔正面、侧面前段没有栅栏
    if math.random() >= TM.KIT.slat.p then return false end
    G.fx({ k = "slat", p = res.Position, n = res.Normal })
    G.slatHits = (G.slatHits or 0) + 1   -- 测试用
    local P = s.src and s.src.P
    if P and P.pl then G.msg(P.pl, "bad", "kit.slatDud") end
    local D = e.driver
    if D and D.pl then G.msg(D.pl, "good", "kit.slatSaved") end
    return true
  end

  -- 地雷、炸药在 pos 炸：车底就在附近的带防雷板的车，伤害乘几（{ [车] = 倍数 }，没有 nil）
  function G.kitMineK(pos)
    local out = nil
    for _, e in ipairs(G.vehicles or {}) do
      local k = kitOf(e)
      if k and k.belly and e.alive then
        local lp = e.root.CFrame:PointToObjectSpace(pos)
        if math.abs(lp.X) < e.def.W * 0.6 and math.abs(lp.Z) < e.def.L * 0.6 and lp.Y < 2 then
          out = out or {}
          out[e] = TM.KIT.belly.k
        end
      end
    end
    return out
  end

  ---------------------------------------------------------------- 扫雷犁

  local PL = TM.KIT.plow
  -- 放下 / 升起（开车的人按 N）：升起要 11 秒（这期间算放着）
  function G.kitPlow(P, e, down)
    local k = kitOf(e)
    if not k or not k.plow or e.driver ~= P then return end
    local t = now()
    if down then
      e.plowDown, e.plowUpAt = true, nil
    elseif e.plowDown and not e.plowUpAt then
      e.plowUpAt = t + PL.raise
    end
    e.model:SetAttribute("Plow", down and 1 or 0.5)   -- 1 放下、0.5 正在升、0 收好
  end
  -- 车速上限（格 / 秒）：犁放着不超过 15 公里 / 时（换算成这型车的游戏车速：按真车公路速度的比例）
  function G.kitSpeedCap(e)
    if not e.plowDown then return nil end
    local sp = e.def.stats and TM.SPEC[e.def.id]
    local vmax = sp and sp.vmax or 65
    return e.def.speed * PL.vcap / vmax
  end
  G.onFrame(function()
    local t = now()
    for _, e in ipairs(G.vehicles or {}) do
      if e.plowDown and e.alive then
        if e.plowUpAt and t >= e.plowUpAt then
          e.plowDown, e.plowUpAt = false, nil
          e.model:SetAttribute("Plow", 0)
        elseif G.minesNear then
          -- 犁刃在车头前 1.5 格、宽 lane：这一条里的雷翻到两边（不炸）
          local hull = e.root.CFrame
          local front = hull * CF(0, -e.def.H / 2, -e.def.L / 2 - 1.5)
          for _, m in ipairs(G.minesNear(front.Position.X, front.Position.Z, PL.lane)) do
            local lp = hull:PointToObjectSpace(V(m.x, m.y, m.z))
            if math.abs(lp.X) < PL.lane / 2 and lp.Z < -e.def.L / 2 + 1 and lp.Z > -e.def.L / 2 - 4 then
              G.mineClear(m, "plow")
              G.plowCleared = (G.plowCleared or 0) + 1   -- 测试用
            end
          end
        end
      end
    end
  end)

  ---------------------------------------------------------------- 激光告警、自动烟幕

  -- 激光制导的弹 s 冲着车 t 来（Air.lua guideMissile 每步问）：返回 true 就是导弹丢了目标
  --   指令制导的反坦克弹（陶式、HOT、攻击……）也问：只有「窗帘-1」（TM.EW.shtora，irJam）的红外干扰灯管用——
  --   发射架上的测角仪跟着弹尾的红外灯修正，干扰灯一晃就跟丢（这一发进到告警距离时掷一次）；激光告警看不到它（没有激光照射）
  function G.kitLaser(s, t, dt)
    local k = kitOf(t)
    if not k or not k.ew or not t.alive or not t.root then return false end
    local W = TM.EW[k.ew]
    if not W then return false end
    local tp = t.root.CFrame.Position
    if s.w and s.w.guide == "cmd" then
      if not W.irJam then return false end
      if s.irJam == nil then
        if (tp - s.pos).Magnitude > 2400 then return false end
        s.irJam = math.random() < W.irJam
        if s.irJam then
          G.fx({ k = "dazzle", id = t.id })
          local D = t.driver
          if D and D.pl then G.msg(D.pl, "good", "kit.irJam") end
          G.irJams = (G.irJams or 0) + 1   -- 测试用
        end
      end
      return s.irJam == true
    end
    if not s.lws then
      local d = (tp - s.pos).Magnitude
      if d > 2400 then return false end   -- 告警器看得到的距离（激光照射一开始就报，这里按导弹进到约 850 米）
      s.lws = true
      local az = TM.bearing(t.root.CFrame * CF(0, -t.def.H / 2, 0), 0, s.pos)
      local D = t.driver
      if D and D.pl then
        G.msg(D.pl, "bad", "kit.lwsWarn", math.floor((az + 360) % 360 / 30 + 0.5) % 12 == 0 and 12 or math.floor((az + 360) % 360 / 30 + 0.5) % 12)
        G.R.Drive:FireClient(D.pl, { op = "lws", az = az })
      end
      if W.auto and G.vehSmoke then G.vehSmoke(t) end
      G.lwsWarns = (G.lwsWarns or 0) + 1   -- 测试用
      if W.dazzle > 0 and math.random() < W.dazzle then
        G.fx({ k = "dazzle", id = t.id })
        return true
      end
    end
    -- 烟幕挡在中间：激光照射点看不到了
    if G.smokeBlocks and G.smokeBlocks(s.pos, tp + V(0, 2, 0)) then
      G.lwsBroken = (G.lwsBroken or 0) + 1   -- 测试用
      return true
    end
    return false
  end
end

return Kit
