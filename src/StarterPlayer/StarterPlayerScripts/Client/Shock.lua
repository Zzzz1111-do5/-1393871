-- 全面大战场（客户端）——震荡（用户 11-23「这个游戏按你想的来弄」：近处爆炸要有被震到的感觉，跟战地、使命召唤一样）
--   爆炸离得近（杀伤半径 r 的三倍多一点以内，Fx.lua 的 boom 调 G.concuss）：
--   · 耳鸣（SoundLib.earRing，自带淡出）——离得越近越响；
--   · 别的声音一下子发闷、变小（Fx.lua 的 makeSound 看 G.muffle()：高频切掉、音量压低），几秒里慢慢回来；
--   · 画面一白、发糊、去一点色，跟着淡回来；
--   在车里挡掉大半（装甲），开飞机不算；同一时刻挨了好几下取最重的那一下，余震叠上去一点
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Shock = {}

function Shock.init(G)
  local S = { k = 0, flash = 0, t0 = -1e9, dur = 1, ringT = -1e9 }
  G.shockState = function() return S end   -- 测试用
  -- 现在的闷的程度（0～1）：Fx.lua 新放的声音按它切高频、压音量
  function G.muffle()
    local u = os.clock() - S.t0
    if u >= S.dur then return 0 end
    local fade = 1 - u / S.dur
    return S.k * fade * fade
  end
  function G.concuss(d, r, c)
    if G.fly then return end   -- 座舱里不算
    if c == "flak" then return end   -- 天上的高炮空炸：地上的人不震
    local R = r * 3 + 16
    if d >= R then return end
    local k = (1 - d / R) ^ 1.3
    if G.drive then k = k * 0.45 end   -- 车里：装甲挡掉大半
    if k < 0.08 then return end
    local now = os.clock()
    local cur = G.muffle()
    S.k = math.min(1, math.max(cur, k) + 0.25 * math.min(cur, k))   -- 余震叠上去一点
    S.t0 = now
    S.dur = 1.2 + 4.0 * S.k
    S.flash = math.max(S.flash, 0.35 + 0.65 * k)
    -- 耳鸣：近的（k 大）才响；刚响过 2 秒内不重复起头
    if k > 0.3 and now - S.ringT > 2 and G.sfx then
      S.ringT = now
      G.sfx("earRing", nil, { vol = 0.4 + 0.9 * k, dry = true, must = true })
    end
  end

  local blur, cc = nil, nil
  local function ensure()
    if not blur or not blur.Parent then
      blur = Instance.new("BlurEffect")
      blur.Name = "ShockBlur"
      blur.Size = 0
      blur.Parent = Lighting
    end
    if not cc or not cc.Parent then
      cc = Instance.new("ColorCorrectionEffect")
      cc.Name = "ShockGrade"
      cc.Parent = Lighting
    end
  end
  local idle = true
  G.frameConn("Shock", function(dt)
    local m = G.muffle()
    S.flash = S.flash * math.exp(-dt * 3.2)
    if m < 0.005 and S.flash < 0.01 then
      if not idle then
        idle = true
        -- 震完了把两个后期关掉（11-27 M3 丝滑：原来只把大小、亮度归零，第一次近处爆炸以后一直开着，每帧白画两遍全屏）
        if blur then blur.Size = 0 blur.Enabled = false end
        if cc then cc.Brightness, cc.Saturation, cc.Contrast = 0, 0, 0 cc.Enabled = false end
      end
      return
    end
    ensure()
    if idle then
      idle = false
      blur.Enabled, cc.Enabled = true, true
    end
    blur.Size = 2 + 14 * math.max(m, S.flash * 0.8)
    cc.Brightness = 0.32 * S.flash
    cc.Saturation = -0.45 * m
    cc.Contrast = -0.15 * S.flash
  end)
end

return Shock
