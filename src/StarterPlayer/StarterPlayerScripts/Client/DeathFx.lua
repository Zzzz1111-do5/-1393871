-- 全面大战场（客户端）——阵亡效果
--   用户 11-23：「死亡不要瞬间切到部署画面」——自己死了，部署界面 / 机库先不出来（UI.lua 看 G.deathFxOn()），先放四秒左右的阵亡画面；
--   用户 11-25：「包括死亡也别再用之前那个gta的动画了」——原来照 GTA5 的「WASTED」做的（画面褪成黑白、模糊、四边压暗、正中一道横条红色大字、
--     心跳、声音发闷、慢动作往后拉）整套去掉，改成战雷那样：
--   ① 画面颜色照旧，镜头留在被打掉的车 / 倒下的人旁边，稍微往后、往上退开一点（不是慢动作）；
--   ② 一秒后转去看打你的那辆（WtHud 收到 wtKilled 记下的 G.wtKiller；步兵是 killcam 消息里的凶手）；
--   ③ 屏幕下方一块牌子（统一外观 docs/style.md：深色面板、细线）：「被击毁」/「阵亡」，下面一行凶手、距离；
--   ④ 最后半秒淡黑，机库 / 部署界面出来以后黑幕再淡开
--   系统设置里开了「减少动态效果」：不动镜头，只有牌子和淡出；主菜单打开、新角色出生、回合结束都马上停
--   用户 11-27（给了战雷截图）：「飞机被干掉后不要立马爆炸 先跟随视角但是雷达什么图全部消失 然后 5秒后 再自动切换到敌视角」——
--   开飞机死的：镜头先跟着自己那架往下掉的残骸（Fly.lua G.airWreckView：着火冒烟、砸到地上才炸）看 5 秒，HUD、雷达屏全收（Fly.lua stop），
--   正下方只一行小字「损失的载具」（战雷的样子：不衬底板）；5 秒后转去看打你的那架 / 那辆（再看 4 秒），没有凶手（撞地、出界）跟完就回机库。
--   试驾：跟 3 秒、不看凶手，直接回机库
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local DeathFx = {}

function DeathFx.init(G)
  local player = Players.LocalPlayer
  local V, RGB = Vector3.new, Color3.fromRGB
  local T = G.T or function(k) return k end
  local DC = (G.Config and G.Config.DeathFx) or {}
  local DUR = DC.dur or 4.4          -- 整段多长（秒），最后 FADE 秒淡黑
  local DUR_DOWN = DC.durDown or 2.8 -- 倒地以后才死的（流血到时间、放弃、补枪）：已经看了半天倒地画面，短一点
  local FADE = 0.5
  local AIR_FOLLOW = DC.airFollow or 5   -- 飞机：先跟着自己的残骸看几秒（用户 11-27「5秒后 再自动切换到敌视角」）
  local AIR_TEST = DC.airTest or 3       -- 试驾里摔了：跟几秒就回机库
  local KILL_SHOW = DC.killShow or 4     -- 再看打你的那个几秒
  local function clamp(x, a, b) return x < a and a or (x > b and b or x) end
  local function smooth(x) x = clamp(x, 0, 1) return x * x * (3 - 2 * x) end
  local function easeOut(x) x = clamp(x, 0, 1) return 1 - (1 - x) ^ 3 end
  local reducedMotion = false
  pcall(function()
    reducedMotion = GuiService.ReducedMotionEnabled == true
    GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function() reducedMotion = GuiService.ReducedMotionEnabled == true end)
  end)

  ---------------------------------------------------------------- 画面：四边压暗、横条、大字、小字、黑幕

  local gui = Instance.new("ScreenGui")
  gui.Name = "DeathFx"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 40   -- 盖在部署界面、倒地界面上面
  gui.Enabled = false
  gui.Parent = player:WaitForChild("PlayerGui")
  local function frame(parent, size, pos, color, tr, anchor)
    local f = Instance.new("Frame")
    f.Size, f.Position = size, pos or UDim2.new()
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = color or RGB(0, 0, 0), tr or 0, 0
    if anchor then f.AnchorPoint = anchor end
    f.Parent = parent
    return f
  end
  -- 下方的牌子：深色面板、上边一道红线（被打掉）、标题、凶手一行
  local TH = G.Theme or { C = {} }
  local plate = frame(gui, UDim2.fromOffset(440, 66), UDim2.new(0.5, 0, 0.8, 0), TH.C.PANEL or RGB(14, 17, 20), 1, Vector2.new(0.5, 0.5))
  plate.Name = "Plate"
  local plateLine = frame(plate, UDim2.new(1, 0, 0, 2), UDim2.new(0, 0, 0, 0), TH.C.BAD or RGB(220, 70, 60), 1)
  plateLine.Name = "Line"
  local title = Instance.new("TextLabel")
  title.Name = "Title"
  title.AnchorPoint = Vector2.new(0.5, 0)
  title.Position = UDim2.new(0.5, 0, 0, 9)
  title.Size = UDim2.new(1, -24, 0, 24)
  title.BackgroundTransparency = 1
  title.Font = Enum.Font.BuilderSansMedium
  title.TextSize = 20
  title.TextColor3 = TH.C.TEXT or RGB(236, 238, 236)
  title.TextTransparency = 1
  title.Text = ""
  title.Parent = plate
  local sub = Instance.new("TextLabel")
  sub.Name = "Sub"
  sub.AnchorPoint = Vector2.new(0.5, 0)
  sub.Position = UDim2.new(0.5, 0, 0, 37)
  sub.Size = UDim2.new(1, -24, 0, 20)
  sub.BackgroundTransparency = 1
  sub.Font = Enum.Font.BuilderSans
  sub.TextSize = 15
  sub.TextColor3 = TH.C.MUTE or RGB(160, 166, 164)
  sub.TextTransparency = 1
  sub.Text = ""
  sub.Parent = plate
  -- 黑幕单独一层：效果结束以后还要盖在部署界面上淡开
  local blackGui = Instance.new("ScreenGui")
  blackGui.Name = "DeathFade"
  blackGui.ResetOnSpawn = false
  blackGui.IgnoreGuiInset = true
  blackGui.DisplayOrder = 41
  blackGui.Enabled = false
  blackGui.Parent = player:WaitForChild("PlayerGui")
  local black = frame(blackGui, UDim2.fromScale(1, 1), nil, RGB(0, 0, 0), 1)
  black.Name = "Black"

  ---------------------------------------------------------------- 状态

  local S = { on = false, n = 0 }
  G.deathFxOn = function() return S.on end
  G.deathFxState = function() return S end   -- 测试用
  local killer = nil   -- 这次是谁打死的（killcam 消息：name、d 距离）

  local function subText()
    S.killerName = (type(killer) == "table" and type(killer.name) == "string") and killer.name or nil   -- 测试用
    if type(killer) ~= "table" or type(killer.name) ~= "string" then return "" end
    local d = tonumber(killer.d)
    if d and d > 0 then return T("death.by", killer.name, math.floor(d / 2.8 + 0.5)) end
    return T("death.byNear", killer.name)
  end

  -- 自己那架残骸（客户端在演的那一份，跟画面上一样顺）：没有就退回服务器的实体
  local function airPos()
    local A = S.air
    if not A then return nil end
    local v = G.airWreckView and G.airWreckView(A.id)
    if v and v.cf then
      A.last = v.cf.Position
      A.size = (v.def and math.max(v.def.L or 0, (v.def.W or 0) * 0.7)) or A.size
      if v.wreck and v.wreck.vel then A.vel = v.wreck.vel end
      return A.last
    end
    return A.last
  end
  -- 凶手看得到吗（WtHud 记下的 G.wtKiller，或者 killcam 消息）
  local function killerKnown()
    local K = G.wtKiller
    if K and os.clock() - (K.t or -99) < 15 then return true end
    return type(killer) == "table" and type(killer.name) == "string"
  end

  local function focusPoint()
    local ap = airPos()
    if ap then return ap end
    local ch = S.char
    local hrp = ch and ch.Parent and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Head"))
    if hrp and hrp:IsA("BasePart") then return hrp.Position end
    return S.focus0
  end

  local fadeOutT = nil   -- 效果结束以后黑幕淡开（部署界面已经出来了）
  local function finish(instant)
    if not S.on then return end
    S.on = false
    pcall(function() RunService:UnbindFromRenderStep("DeathFxCam") end)
    gui.Enabled = false
    local cam = workspace.CurrentCamera
    if cam and S.camType0 and cam.CameraType == Enum.CameraType.Scriptable then
      pcall(function() cam.CameraType = S.camType0 end)
      if S.fov0 then cam.FieldOfView = S.fov0 end
    end
    if instant then blackGui.Enabled = false black.BackgroundTransparency = 1 fadeOutT = nil
    else fadeOutT = os.clock() end
    if G.refresh then pcall(G.refresh) end   -- 部署界面马上出来（不用等服务器下一次推状态）
  end

  local function camStep()
    if not S.on then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    local u = os.clock() - S.t0
    if reducedMotion then return end
    local f = focusPoint() + V(0, 0.8, 0)
    -- 往后、往上退开一点（一秒里退好，之后不动；不做慢动作）：从死的那一刻的镜头位置出发
    local k = easeOut(u / 1.0)
    local want = S.from:Lerp(f + S.back * (S.dist + 6) + V(0, 4 + (S.veh and 4 or 1), 0), k)
    if S.air then
      -- 飞机：跟着残骸（追尾镜头那样在它后上方，方向顺着它往哪掉慢慢转；往下栽时不翻到它底下去），一秒里退到大一点的距离
      local A = S.air
      local vel = A.vel or V()
      local flat = V(vel.X, 0, vel.Z)
      if flat.Magnitude > 8 then A.head = (A.head or flat.Unit):Lerp(flat.Unit, math.min(1, (S.dt or 0) * 1.5)) end
      local head = (A.head and A.head.Magnitude > 1e-3) and A.head.Unit or S.back * -1
      local dist = (A.size or 40) * 0.9 + 22
      local off = -head * dist + V(0, dist * 0.35 + 6, 0)
      S.off = S.off and S.off:Lerp(off, math.min(1, (S.dt or 0) * 2)) or (S.from - f)
      want = f + S.off
    end
    -- 战雷式击杀镜头（C 11-25「全部都做」⑮）：车被打掉的，先看一秒自己的车，再转去看打你的那辆（WtHud 收到 wtKilled 记下 G.wtKiller）——
    --   镜头在凶手和你之间、离凶手三十几格、稍高，看着它
    local K = G.wtKiller
    local kAt = S.follow or 1.0   -- 飞机先跟残骸 S.follow 秒，车一秒
    if K and os.clock() - K.t < 15 and u > kAt and G.viewById and not S.test then
      local v = G.viewById(K.id)
      local km = v and v.model
      if not km then   -- 飞机、直升机不在 View 里：按实体号在 Ents 里找
        if not K.em or not K.em.Parent then
          K.em = nil
          local ents = workspace:FindFirstChild("Ents")
          for _, em in ipairs(ents and ents:GetChildren() or {}) do
            if em:GetAttribute("EntId") == K.id then K.em = em break end
          end
        end
        km = K.em
      end
      local okP, kp = false, nil
      if v and v.cf and v.def then okP, kp = true, v.cf.Position   -- 飞机：View 里演的那一份（跟画面上一样顺）
      elseif km and km.Parent then okP, kp = pcall(function() return km:GetPivot().Position end) end
      if okP and kp then
        local dir = (focusPoint() - kp)
        dir = (dir.Magnitude > 1) and dir.Unit or V(0, 0, 1)
        local kf = kp + V(0, 2, 0)
        local kd = (v and v.def and v.def.L) and math.max(34, v.def.L * 1.6 + 10) or 34   -- 大飞机退远一点
        local kwant = kf + dir * kd + V(0, 9 + kd * 0.12, 0)
        local blend = smooth((u - kAt) / 0.6)
        f = f:Lerp(kf, blend)
        want = want:Lerp(kwant, blend)
      end
    end
    -- 别穿进墙里、地里
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    local ex = {}
    if S.char then table.insert(ex, S.char) end
    if S.veh then table.insert(ex, S.veh) end
    if S.air and G.airWreckView then   -- 射线从残骸 / 凶手的中心打出来：别打在它们自己身上（镜头一下子贴上去）
      local wv = G.airWreckView(S.air.id)
      if wv and wv.model then table.insert(ex, wv.model) end
    end
    if K and G.viewById then
      local kv = G.viewById(K.id)
      if kv and kv.model then table.insert(ex, kv.model) end
      if K.em then table.insert(ex, K.em) end
    end
    rp.FilterDescendantsInstances = ex
    local okR, hit = pcall(function() return workspace:Raycast(f, want - f, rp) end)
    if okR and hit then want = f + (want - f).Unit * math.max(2, (hit.Position - f).Magnitude - 0.8) end
    cam.CFrame = CFrame.lookAt(want, f)
  end

  local function start(ch, wasDown)
    if S.on or (G.menuShown and G.menuShown()) then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    if G.S and G.S.phase == "end" then return end
    S.n += 1
    -- 试驾里摔了 / 被打掉：阵亡画面短一点（2.4 秒）就回机库（用户 11-27「我坠机能不能自动返回主页」）——试驾的车 / 飞机模型带 TestDrive 属性
    local testD = G.inTestDrive and G.inTestDrive() or false
    S.on, S.t0, S.char, S.dur = true, os.clock(), ch, testD and math.min(2.4, DUR) or (wasDown and DUR_DOWN or DUR)
    S.titleK, S.off, S.dt = nil, nil, 0
    S.camType0, S.fov0 = cam.CameraType, cam.FieldOfView
    local hrp = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Head"))
    S.focus0 = (hrp and hrp:IsA("BasePart") and hrp.Position) or cam.Focus.Position
    S.veh = nil
    -- 在车里死的：看着车（Drive / Fly 的车模型），不看人
    local seat = nil
    pcall(function() local hum = ch and ch:FindFirstChildOfClass("Humanoid") seat = hum and hum.SeatPart end)
    if seat then
      local m = seat:FindFirstAncestorOfClass("Model")
      if m and m ~= ch then S.veh = m S.focus0 = m:GetPivot().Position end
    end
    if S.veh and S.veh:GetAttribute("TestDrive") == true then S.dur = math.min(2.4, S.dur) end   -- 死的时候 Drive / Fly 可能已经先收了：再看一眼座位所在的车
    -- 开飞机死的（Fly.lua 每帧记 G.flyLast）：跟残骸 5 秒（试驾 3 秒）再说
    S.air, S.follow, S.test = nil, nil, testD
    local fl = G.flyLast
    if fl and fl.id ~= nil and os.clock() - (fl.t or -99) < 1.5 then
      S.air = { id = fl.id }
      S.test = testD or fl.test == true
      S.follow = S.test and AIR_TEST or AIR_FOLLOW
      S.dur = S.follow
      local ap = airPos()
      if ap then S.focus0 = ap end
      S.veh = nil
    end
    S.from = cam.CFrame.Position
    local flat = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
    S.back = (flat.Magnitude > 0.05) and -flat.Unit or V(0, 0, 1)
    S.dist = clamp((S.from - S.focus0).Magnitude, 4, S.veh and 40 or 14)
    if G.killcamStop then pcall(G.killcamStop) end   -- 原来那段转镜头看凶手的（Warfx.lua）先停掉，凶手写在小字里
    if not reducedMotion then pcall(function() cam.CameraType = Enum.CameraType.Scriptable end) end
    title.Text = (G.hangarActive and G.hangarActive()) and T("wt.kcTitle") or T("death.title")   -- 战雷式（开车、不当步兵）：「被击毁」
    if S.air then title.Text = T("death.vehLost") end   -- 战雷：正下方一行「损失的载具」
    sub.Text = subText()
    gui.Enabled = true
    blackGui.Enabled = true
    black.BackgroundTransparency = 1
    fadeOutT = nil
    pcall(function() RunService:BindToRenderStep("DeathFxCam", Enum.RenderPriority.Camera.Value + 40, camStep) end)
  end

  local function step(dt)
    if fadeOutT then   -- 部署界面出来了：黑幕淡开
      local v = (os.clock() - fadeOutT) / 0.45
      black.BackgroundTransparency = clamp(v, 0, 1)
      if v >= 1 then fadeOutT = nil blackGui.Enabled = false end
    end
    if not S.on then return end
    local u = os.clock() - S.t0
    -- 打断：主菜单开了、新角色出来了、回合结束了
    local ch = player.Character
    if (G.menuShown and G.menuShown()) or (ch and ch ~= S.char) or (G.S and G.S.phase == "end") then finish(true) return end
    if G.S and G.S.alive and ch and ch ~= S.char then finish(true) return end
    S.dt = dt
    if S.air and not S.test then S.dur = S.follow + (killerKnown() and KILL_SHOW or 0) end   -- 有凶手再看它 4 秒
    if u >= S.dur then finish(false) return end
    -- 牌子：0.4 秒起淡进来（面板、红线、标题），凶手那一行随后
    local a = smooth((u - 0.4) / 0.35)
    plate.BackgroundTransparency = S.air and 1 or (1 - 0.85 * a)   -- 飞机：战雷那样只一行字，不衬底板
    plateLine.BackgroundTransparency = S.air and 1 or (1 - a)
    if S.air and not S.test and u > S.follow and killerKnown() and S.titleK ~= true then   -- 转去看凶手：这一行换成谁打的、多远
      local st = subText()
      if st ~= "" then
        S.titleK = true
        title.Text = st
      end
    end
    title.TextTransparency = 1 - a
    if sub.Text == "" then sub.Text = subText() end
    sub.TextTransparency = S.air and 1 or (1 - smooth((u - 0.7) / 0.35))   -- 飞机：只一行（凶手写在这一行里，见上）
    -- 最后半秒淡黑
    black.BackgroundTransparency = 1 - smooth((u - (S.dur - FADE)) / FADE)
  end
  if G.frameConn then G.frameConn("DeathFx", step) else RunService.RenderStepped:Connect(step) end

  -- 自己的角色死了：开始（倒地的人流血到时间、放弃、被补枪也是这里——短一点）
  local function watch(ch)
    local hum = ch:WaitForChild("Humanoid", 10)
    if not hum then return end
    hum.Died:Connect(function()
      local ok, err = pcall(start, ch, ch:GetAttribute("Downed") == true or G.downed == true)
      if not ok then
        finish(true)
        if G.showError then G.showError("阵亡效果：" .. tostring(err)) end
      end
    end)
  end
  if player.Character then task.spawn(watch, player.Character) end
  player.CharacterAdded:Connect(function(ch)
    if S.on then finish(true) end
    killer = nil
    task.spawn(watch, ch)
  end)

  -- 凶手（服务器 Battle.lua 的 killcam）：阵亡效果开着就归这里（写在小字里），原来那段转镜头看凶手的不放了
  local prevMsg = G.onMsg
  G.onMsg = function(kind, key, ...)
    if kind == "killcam" then
      killer = key
      -- 凶手坐的那辆 / 那架（服务器 Battle.lua 给的 kid）：镜头转去看它（地面车被打掉时 WtHud 的 wtKilled 已经记过的不覆盖）
      if type(key) == "table" and key.kid ~= nil and not (G.wtKiller and G.wtKiller.id == key.kid) then
        G.wtKiller = { id = key.kid, t = os.clock() }
      end
      if S.on then
        sub.Text = subText()
        return
      end
    end
    if prevMsg then return prevMsg(kind, key, ...) end
  end
end

return DeathFx
