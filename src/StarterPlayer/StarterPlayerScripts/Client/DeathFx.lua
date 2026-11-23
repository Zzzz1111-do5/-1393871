-- 全面大战场（客户端）——阵亡效果（用户 11-23：「死亡不要瞬间切到部署画面，加一个 GTA5 的死亡效果」）
--   自己死了：部署界面先不出来（UI.lua 看 G.deathFxOn()），先放四秒多的阵亡效果，跟 GTA5 的「WASTED」一个路数——
--   ① 一下低沉的闷响加呼的一声、画面一白；之后新响起的声音都发闷（接在 Shock.lua 的 G.muffle 上）、心跳两下
--   ② 画面一秒里褪成黑白，对比加大、一点模糊、四边压暗
--   ③ 镜头留在倒下的地方：从死的那一刻的位置慢慢升高、往后拉，一直看着身体（越来越慢，像慢动作）；在车里死的看着那辆车
--   ④ 屏幕正中一道暗的横条，红色大字「阵亡」从稍大缩回原大、淡进来；下面一行小字：被谁打死、多远（服务器 Battle.lua 的 killcam 消息，
--      阵亡效果开着时这条消息归这里用，原来转镜头看凶手的那一段让给它）
--   ⑤ 最后半秒淡黑，部署界面出来以后黑幕再淡开
--   系统设置里开了「减少动态效果」：不动镜头，只有褪色、字和淡出；主菜单打开、新角色出生、回合结束都马上停
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
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
  local edges = {}
  for _, e in ipairs({ { UDim2.fromScale(1, 0.34), UDim2.fromScale(0, 0), 90 }, { UDim2.fromScale(1, 0.34), UDim2.fromScale(0, 0.66), -90 },
    { UDim2.fromScale(0.26, 1), UDim2.fromScale(0, 0), 0 }, { UDim2.fromScale(0.26, 1), UDim2.fromScale(0.74, 0), 180 } }) do
    local f = frame(gui, e[1], e[2], RGB(0, 0, 0), 0)
    local g = Instance.new("UIGradient")
    g.Rotation = e[3]
    g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
    g.Parent = f
    table.insert(edges, f)
  end
  local band = frame(gui, UDim2.new(1, 0, 0, 132), UDim2.fromScale(0.5, 0.5), RGB(0, 0, 0), 1, Vector2.new(0.5, 0.5))
  band.Name = "Band"
  local bandG = Instance.new("UIGradient")   -- 横条两头淡掉
  bandG.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.18, 0), NumberSequenceKeypoint.new(0.82, 0), NumberSequenceKeypoint.new(1, 1) })
  bandG.Parent = band
  local title = Instance.new("TextLabel")
  title.Name = "Title"
  title.AnchorPoint = Vector2.new(0.5, 0.5)
  title.Position = UDim2.fromScale(0.5, 0.5)
  title.Size = UDim2.fromOffset(900, 110)
  title.BackgroundTransparency = 1
  title.Font = Enum.Font.GothamBlack
  title.TextSize = 92
  title.TextColor3 = RGB(196, 26, 22)
  title.TextStrokeColor3 = RGB(0, 0, 0)
  title.TextStrokeTransparency = 0.15
  title.Text = ""
  title.Parent = gui
  local titleScale = Instance.new("UIScale")
  titleScale.Parent = title
  local sub = Instance.new("TextLabel")
  sub.Name = "Sub"
  sub.AnchorPoint = Vector2.new(0.5, 0)
  sub.Position = UDim2.new(0.5, 0, 0.5, 74)
  sub.Size = UDim2.fromOffset(900, 28)
  sub.BackgroundTransparency = 1
  sub.Font = Enum.Font.GothamMedium
  sub.TextSize = 20
  sub.TextColor3 = RGB(236, 232, 226)
  sub.TextStrokeTransparency = 0.5
  sub.Text = ""
  sub.Parent = gui
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
  local cc, blur = nil, nil
  local killer = nil   -- 这次是谁打死的（killcam 消息：name、d 距离）

  -- 声音发闷：接在 Shock.lua 的 G.muffle 上（Fx.lua 新放的声音按它切高频、压音量）
  local muffle0 = G.muffle
  G.muffle = function()
    local m = muffle0 and muffle0() or 0
    if S.on then
      local u = os.clock() - S.t0
      m = math.max(m, 0.85 * (1 - smooth((u - (S.dur - 1.2)) / 1.2)))
    end
    return m
  end

  local function subText()
    if type(killer) ~= "table" or type(killer.name) ~= "string" then return "" end
    local d = tonumber(killer.d)
    if d and d > 0 then return T("death.by", killer.name, math.floor(d / 2.8 + 0.5)) end
    return T("death.byNear", killer.name)
  end

  local function focusPoint()
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
    if cc then cc:Destroy() cc = nil end
    if blur then blur:Destroy() blur = nil end
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
    -- 越来越慢地升高、往后拉（像慢动作）：从死的那一刻的镜头位置出发
    local k = easeOut(u / (S.dur * 0.95))
    local want = S.from:Lerp(f + S.back * (S.dist + 9 * k) + V(0, 3 + 7 * k, 0), smooth(u / 0.9) * 0.35 + 0.65 * k)
    -- 别穿进墙里、地里
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    local ex = {}
    if S.char then table.insert(ex, S.char) end
    if S.veh then table.insert(ex, S.veh) end
    rp.FilterDescendantsInstances = ex
    local okR, hit = pcall(function() return workspace:Raycast(f, want - f, rp) end)
    if okR and hit then want = f + (want - f).Unit * math.max(2, (hit.Position - f).Magnitude - 0.8) end
    cam.CFrame = CFrame.lookAt(want, f)
    cam.FieldOfView = S.fov0 + (S.fov0 * 0.78 - S.fov0) * smooth(u / S.dur)   -- 慢慢推近一点
  end

  local function start(ch, wasDown)
    if S.on or (G.menuShown and G.menuShown()) then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    if G.S and G.S.phase == "end" then return end
    S.n += 1
    S.on, S.t0, S.char, S.dur = true, os.clock(), ch, wasDown and DUR_DOWN or DUR
    S.beat = 0
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
    S.from = cam.CFrame.Position
    local flat = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
    S.back = (flat.Magnitude > 0.05) and -flat.Unit or V(0, 0, 1)
    S.dist = clamp((S.from - S.focus0).Magnitude, 4, S.veh and 40 or 14)
    if G.killcamStop then pcall(G.killcamStop) end   -- 原来那段转镜头看凶手的（Warfx.lua）先停掉，凶手写在小字里
    if not reducedMotion then pcall(function() cam.CameraType = Enum.CameraType.Scriptable end) end
    -- 褪色、模糊
    cc = Instance.new("ColorCorrectionEffect")
    cc.Name = "DeathGrade"
    cc.Parent = Lighting
    blur = Instance.new("BlurEffect")
    blur.Name = "DeathBlur"
    blur.Size = 0
    blur.Parent = Lighting
    title.Text = T("death.title")
    sub.Text = subText()
    gui.Enabled = true
    blackGui.Enabled = true
    black.BackgroundTransparency = 1
    fadeOutT = nil
    -- 一下闷响加呼的一声
    if G.sfx then pcall(G.sfx, "death", nil, { must = true, dry = true }) end
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
    if u >= S.dur then finish(false) return end
    -- 画面：一白 → 黑白、对比、模糊
    if cc then
      cc.Saturation = -1 * smooth(u / 1.0)
      cc.Contrast = 0.28 * smooth(u / 1.0)
      cc.Brightness = 0.35 * math.exp(-u * 7) - 0.06 * smooth(u / 1.5)
      cc.TintColor = RGB(255, 255, 255)
    end
    if blur then blur.Size = 2 + 4 * smooth(u / 1.4) + 10 * math.exp(-u * 9) end
    for _, e in ipairs(edges) do e.BackgroundTransparency = 1 - 0.85 * smooth(u / 0.8) end
    -- 横条、大字（0.55 秒起淡进来、从 1.25 倍缩回）、小字
    local a = smooth((u - 0.55) / 0.3)
    band.BackgroundTransparency = 1 - 0.55 * a
    title.TextTransparency = 1 - a
    title.TextStrokeTransparency = 1 - 0.85 * a
    titleScale.Scale = 1 + 0.25 * (1 - easeOut((u - 0.55) / 0.45))
    if sub.Text == "" then sub.Text = subText() end
    local b = smooth((u - 1.0) / 0.4)
    sub.TextTransparency = 1 - b
    sub.TextStrokeTransparency = 1 - 0.5 * b
    -- 心跳两下
    if S.beat < 2 and u > 0.5 + S.beat * 0.9 then
      S.beat += 1
      if G.sfx then pcall(G.sfx, "heart", nil, { vol = 1.2, must = true }) end
    end
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
      if S.on then
        sub.Text = subText()
        return
      end
    end
    if prevMsg then return prevMsg(kind, key, ...) end
  end
end

return DeathFx
