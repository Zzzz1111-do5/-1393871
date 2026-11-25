-- 全面大战场（客户端）——阵亡效果
--   用户 11-23：「死亡不要瞬间切到部署画面」——自己死了，部署界面 / 机库先不出来（UI.lua 看 G.deathFxOn()），先放四秒左右的阵亡画面；
--   用户 11-25：「包括死亡也别再用之前那个gta的动画了」——原来照 GTA5 的「WASTED」做的（画面褪成黑白、模糊、四边压暗、正中一道横条红色大字、
--     心跳、声音发闷、慢动作往后拉）整套去掉，改成战雷那样：
--   ① 画面颜色照旧，镜头留在被打掉的车 / 倒下的人旁边，稍微往后、往上退开一点（不是慢动作）；
--   ② 一秒后转去看打你的那辆（WtHud 收到 wtKilled 记下的 G.wtKiller；步兵是 killcam 消息里的凶手）；
--   ③ 屏幕下方一块牌子（统一外观 docs/style.md：深色面板、细线）：「被击毁」/「阵亡」，下面一行凶手、距离；
--   ④ 最后半秒淡黑，机库 / 部署界面出来以后黑幕再淡开
--   系统设置里开了「减少动态效果」：不动镜头，只有牌子和淡出；主菜单打开、新角色出生、回合结束都马上停
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
  title.Font = Enum.Font.BuilderSansBold
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
  sub.Font = Enum.Font.BuilderSansMedium
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
    -- 战雷式击杀镜头（C 11-25「全部都做」⑮）：车被打掉的，先看一秒自己的车，再转去看打你的那辆（WtHud 收到 wtKilled 记下 G.wtKiller）——
    --   镜头在凶手和你之间、离凶手三十几格、稍高，看着它
    local K = G.wtKiller
    if K and os.clock() - K.t < 10 and u > 1.0 and G.viewById then
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
      if km and km.Parent then okP, kp = pcall(function() return km:GetPivot().Position end) end
      if okP and kp then
        local dir = (focusPoint() - kp)
        dir = (dir.Magnitude > 1) and dir.Unit or V(0, 0, 1)
        local kf = kp + V(0, 2, 0)
        local kwant = kf + dir * 34 + V(0, 9, 0)
        local blend = smooth((u - 1.0) / 0.6)
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
    S.on, S.t0, S.char, S.dur = true, os.clock(), ch, wasDown and DUR_DOWN or DUR
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
    title.Text = (G.hangarActive and G.hangarActive()) and T("wt.kcTitle") or T("death.title")   -- 战雷式（开车、不当步兵）：「被击毁」
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
    if u >= S.dur then finish(false) return end
    -- 牌子：0.4 秒起淡进来（面板、红线、标题），凶手那一行随后
    local a = smooth((u - 0.4) / 0.35)
    plate.BackgroundTransparency = 1 - 0.85 * a
    plateLine.BackgroundTransparency = 1 - a
    title.TextTransparency = 1 - a
    if sub.Text == "" then sub.Text = subText() end
    sub.TextTransparency = 1 - smooth((u - 0.7) / 0.35)
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
