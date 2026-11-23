-- 全面大战场——倒地与救援（用户 11-23：「这个游戏按你想的来弄」——补上战地那一套小队协作：被打倒不是马上死，队友能把你救起来）
--   挨了致命的一下、又不是打得太狠（爆炸、炮弹、狙击爆头这种一下打掉比剩下的血多 Config.Revive.overkill 以上的直接死）：倒地——
--     人瘫在地上（Humanoid.PlatformStand：身体按物理倒下去），不能动、不能开枪、不能上车；击杀在这一下就记给打倒你的人（战况、加分、击杀信息）
--   倒地以后：Config.Revive.bleed 秒没人救就阵亡（不再算一次击杀）；再挨一下（补枪）马上阵亡；按住空格 giveUp 秒放弃，直接回部署界面
--   救人：同队的人走到旁边按住 E（客户端 Downed.lua 在倒地的队友身上放 ProximityPrompt）——带着急救包 medicHold 秒、救起来满血，
--     没带 hold 秒、救起来 hp 成血；服务器按「开始按」到「按完」的时间核对（ACT.reviveBegin / ACT.revive），离得太远、自己也倒着、在车里都不行
--   在载具里、登陆艇上、跳伞中、水里挨打照旧直接死；机器人照旧直接死（机器人默认关着：Config.Bots.minPerTeam = 0）
local Revive = {}

function Revive.init(G)
  local Config = G.Config
  local RC = Config.Revive or {}
  local now = os.clock
  local Players = game:GetService("Players")

  local function serverNow()
    local ok, t = pcall(function() return workspace:GetServerTimeNow() end)
    return (ok and type(t) == "number") and t or os.clock()
  end
  local function rootOf(P)
    return P and P.char and P.char:FindFirstChild("HumanoidRootPart")
  end
  local function humOf(P)
    return P and P.char and P.char:FindFirstChildOfClass("Humanoid")
  end
  local function byUid(uid)
    if type(uid) ~= "number" then return nil end
    local pl = Players:GetPlayerByUserId(uid)
    return pl and G.P[pl] or nil
  end
  local function hasMedkit(P)
    local kit = G.kitOf and G.kitOf(P)
    return kit ~= nil and table.find(kit.weapons or {}, "medkit") ~= nil
  end
  G.hasMedkit = hasMedkit

  -- 这一下能不能倒地（而不是直接死）
  function G.downOk(P, hum, amt)
    if not RC.on or P.downed or not P.alive or not P.char then return false end
    if not G.round or G.round.phase ~= "battle" then return false end
    if P.vehicle or P.boat or P.chute then return false end   -- 车里、登陆艇上、伞下：直接死
    if amt - hum.Health > (RC.overkill or 70) then return false end   -- 打得太狠
    local hrp = rootOf(P)
    if not hrp then return false end
    local p = hrp.Position
    if G.Map and G.Map.isLand and not G.Map.isLand(p.X, p.Z) then return false end   -- 水里
    return true
  end

  -- 倒地：击杀现在就记（G.creditDeath，Round.lua），人瘫下去
  function G.downPlayer(P, hum, src, part)
    local char = P.char
    hum.Health = 1
    local killer, kname = nil, nil
    if G.creditDeath then
      local ok, k, n = G.try("倒地记功", G.creditDeath, P)
      if ok then killer, kname = k, n end
    end
    local D = { t = now(), til = now() + (RC.bleed or 20), killer = killer, kname = kname, credited = true,
      ws = hum.WalkSpeed, jp = hum.JumpPower }
    pcall(function() D.jh = hum.JumpHeight end)
    P.downed = D
    P.revT = nil
    char:SetAttribute("Downed", true)
    char:SetAttribute("DownT", serverNow() + (RC.bleed or 20))   -- 客户端的倒计时（服务器时间）
    pcall(function() hum:UnequipTools() end)
    hum.WalkSpeed = 0
    hum.JumpPower = 0
    pcall(function() hum.JumpHeight = 0 end)
    pcall(function() hum.PlatformStand = true end)
    G.msg(P.pl, "center", kname and "ui.downedBy" or "ui.downed", kname)
    G.emit("downed", P)
    G.pushOne(P)
  end

  -- 倒地的人死掉（流血、放弃、补枪）：血一清，Humanoid.Died → Round.lua 的 onDied 照常收尾（不再记一次击杀）
  local function finish(P)
    local hum = humOf(P)
    if hum and hum.Health > 0 then hum.Health = 0 end
  end
  G.downFinish = finish

  local function clearDown(P)
    local char = P.char
    P.downed = nil
    if char then
      char:SetAttribute("Downed", nil)
      char:SetAttribute("DownT", nil)
      char:SetAttribute("RevBy", nil)
      char:SetAttribute("RevT", nil)
    end
  end

  -- 救起来
  function G.revivePlayer(T, by, medic)
    local D = T.downed
    local hum = humOf(T)
    if not D or not hum or hum.Health <= 0 then return false end
    clearDown(T)
    T.dmgLog = {}
    pcall(function() hum.PlatformStand = false end)
    local kit = G.kitOf and G.kitOf(T)
    hum.WalkSpeed = (T.kit and T.kit.speed) or (kit and kit.speed) or D.ws or 16
    hum.JumpPower = D.jp or 50
    if D.jh then pcall(function() hum.JumpHeight = D.jh end) end
    hum.Health = math.max(1, math.floor(hum.MaxHealth * (medic and (RC.medicHp or 1) or (RC.hp or 0.35))))
    pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    if by then
      G.addScore(by, (medic and Config.Score.revive or Config.Score.reviveAlly) or 50)
      by.revives = (by.revives or 0) + 1
      G.msg(by.pl, "kill", "ui.youRevived", T.pl.DisplayName)
      G.msg(T.pl, "center", "ui.revivedBy", by.pl.DisplayName)
    end
    G.emit("revived", T, by)
    G.pushOne(T)
    if by then G.pushOne(by) end
    return true
  end

  -- 能不能救：自己活着、没倒、不在车里；对方同队、倒着；离得够近
  local function canRevive(P, T)
    if not P or not T or P == T then return false end
    if not P.alive or P.downed or (G.inVeh and G.inVeh(P)) then return false end
    if not T.alive or not T.downed or T.team ~= P.team then return false end
    local a, b = rootOf(P), rootOf(T)
    if not a or not b then return false end
    return (a.Position - b.Position).Magnitude <= (RC.range or 8) + 3
  end
  G.canRevive = canRevive

  G.ACT.reviveBegin = function(P, uid)
    local T = byUid(uid)
    if not canRevive(P, T) then return end
    P.revT = { uid = uid, t = now() }
    -- 倒着的人那边显示「某某正在救你」（客户端按服务器时间判断还在不在按）
    T.char:SetAttribute("RevBy", P.pl.DisplayName)
    T.char:SetAttribute("RevT", serverNow())
  end
  G.ACT.revive = function(P, uid)
    local T = byUid(uid)
    if not canRevive(P, T) then return end
    local rt = P.revT
    if not rt or rt.uid ~= uid then return end
    local medic = hasMedkit(P)
    local need = (medic and (RC.medicHold or 1.6) or (RC.hold or 4)) - 0.35   -- 网络抖动留一点余量
    if now() - rt.t < need then return end
    P.revT = nil
    G.revivePlayer(T, P, medic)
  end
  -- 放弃：倒地满 0.8 秒以后才认（刚倒下手还按着空格跳）
  G.ACT.giveUp = function(P)
    local D = P.downed
    if not D or now() - D.t < 0.8 then return end
    finish(P)
  end

  -- 流血：到时间没人救就阵亡；角色没了（换角色、离开）就清掉
  local acc = 0
  G.onFrame(function(dt)
    acc += dt
    if acc < 0.2 then return end
    acc = 0
    local t = now()
    for _, P in pairs(G.P) do
      local D = P.downed
      if D then
        local hum = humOf(P)
        if not hum or hum.Health <= 0 or not P.alive then
          P.downed = nil
        elseif t >= D.til then
          finish(P)
        end
      end
    end
  end)
  -- 新一局：倒着的都清掉（角色会被收掉重新部署）
  G.on("roundStart", function()
    for _, P in pairs(G.P) do
      if P.downed then clearDown(P) end
      P.revT = nil
    end
  end)
end

return Revive
