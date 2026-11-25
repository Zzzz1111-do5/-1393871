-- 夜间登陆的阶段简报与据点反馈。由服务器快照驱动，补上中途入场的当前目标。
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")

local Operation = {}

local RGB = Color3.fromRGB
local INK = RGB(9, 18, 25)
local SLATE = RGB(28, 47, 61)
local WHITE = RGB(234, 243, 247)
local MUTE = RGB(157, 182, 195)
local TEAL = RGB(122, 226, 146)
local AMBER = RGB(255, 192, 122)
local CENTER_TOP = Vector2.new(0.5, 0)
local LEFT = Enum.TextXAlignment.Left
local RIGHT = Enum.TextXAlignment.Right
local HOLD = 4.8
local OPENING_HOLD = 5.8

function Operation.init(G)
  local ui, T, mobile = G.ui, G.T, G.mobile
  local player = Players.LocalPlayer
  local stages = G.Config.Stages or {}
  local capture = G.Config.Capture
  local pointById = {}
  local function indexPoints()
    table.clear(pointById)
    for _, p in ipairs(G.Map.POINTS) do pointById[p.id] = p end
  end
  indexPoints()
  if G.onMap then G.onMap(indexPoints) end

  local reducedMotion = false
  pcall(function()
    local function syncMotion() reducedMotion = GuiService.ReducedMotionEnabled end
    syncMotion()
    GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(syncMotion)
  end)

  local function panel(className, name)
    local f = Instance.new(className)
    f.Name = name
    f.AnchorPoint = CENTER_TOP
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = INK, 0.1, 0
    f.ZIndex, f.Visible = 24, false
    f.Parent = G.gui
    return f
  end

  local function label(parent, name, size, pos, fontSize, color, font, align)
    local l = ui.label(parent, "", size, pos, fontSize, color, font, nil, align)
    l.Name = name
    return l
  end

  local brief = panel("CanvasGroup", "OperationBrief")
  brief.BackgroundTransparency = 1
  local backing = ui.frame(brief, UDim2.fromScale(1, 1), nil, WHITE, 0.05)
  local shade = Instance.new("UIGradient")
  shade.Color = ColorSequence.new(INK, SLATE)
  shade.Rotation = -12
  shade.Parent = backing
  ui.stroke(backing, MUTE, 1, 0.74)
  local rail = ui.frame(brief, UDim2.new(1, 0, 0, 2), nil, TEAL, 0)
  local railFade = Instance.new("UIGradient")
  railFade.Transparency = NumberSequence.new(0, 0.8)
  railFade.Parent = rail

  local header = label(brief, "Chapter", UDim2.new(0.57, -16, 0, 14), nil, 11, TEAL, Enum.Font.BuilderSansBold, LEFT)
  local sector = label(brief, "Sector", UDim2.new(0.43, -16, 0, 14), nil, 11, WHITE, Enum.Font.BuilderSansMedium, RIGHT)
  local title = label(brief, "Title", UDim2.new(), nil, 30, WHITE, Enum.Font.BuilderSansExtraBold, LEFT)
  for _, textLabel in ipairs({ header, sector, title }) do
    textLabel.TextWrapped = false
    textLabel.TextTruncate = Enum.TextTruncate.AtEnd
  end
  title.TextScaled = true
  local titleSize = Instance.new("UITextSizeConstraint")
  titleSize.MinTextSize = 14
  titleSize.Parent = title
  local description = label(brief, "Orders", UDim2.new(), nil, 14, WHITE, Enum.Font.BuilderSansMedium, LEFT)
  description.TextYAlignment = Enum.TextYAlignment.Top
  description.TextScaled = true
  local orderSize = Instance.new("UITextSizeConstraint")
  orderSize.MinTextSize = 11
  orderSize.Parent = description
  local route = ui.frame(brief, UDim2.new(), nil, INK, 1)
  route.Name = "Route"
  local stops = {}
  local shownRound, shownStage, shownTeam, startedAt, renderedLanguage   -- 简报现在显示的是哪一局、哪个阶段（换了地图要重写）
  -- 阶段路线条：地图是进服以后投票定的（定之前 Config.Stages 还是岛的四个阶段），换了图按那张图的阶段重摆（沙海五个阶段）
  local function buildStops()
    for _, st in ipairs(stops) do st.frame:Destroy() end
    table.clear(stops)
    stages = G.Config.Stages or {}
    for i, stage in ipairs(stages) do
      local width = 1 / #stages
      local stop = ui.frame(route, UDim2.new(width, -3, 1, 0), UDim2.new((i - 1) * width, 0, 0, 0), INK, 0.25)
      stop.Name = stage.id
      local edge = ui.frame(stop, UDim2.new(1, 0, 0, 1), UDim2.fromScale(0, 1), MUTE, 0.55, Vector2.new(0, 1))
      local text = label(stop, "Objectives", UDim2.fromScale(1, 1), nil, 11, WHITE, Enum.Font.BuilderSansBold)
      text.TextWrapped = false
      stops[i] = { frame = stop, edge = edge, label = text, points = table.concat(stage.points, " · ") }
    end
    shownRound, shownStage = nil, nil   -- 简报按新的阶段表重写
  end
  buildStops()
  if G.onMap then G.onMap(buildStops) end

  local localPanel = panel("Frame", "ObjectiveStatus")
  localPanel.BackgroundTransparency = 0.08
  ui.stroke(localPanel, MUTE, 1, 0.68)
  local objective = label(localPanel, "Objective", UDim2.new(1, -80, 0, 18), UDim2.fromOffset(12, 6), 14, WHITE, Enum.Font.BuilderSansBold, LEFT)
  local percent = label(localPanel, "Progress", UDim2.fromOffset(56, 18), UDim2.new(1, -68, 0, 6), 14, WHITE, Enum.Font.BuilderSansBold, RIGHT)
  local status = label(localPanel, "Status", UDim2.new(1, -24, 0, 26), UDim2.fromOffset(12, 23), 11, MUTE, Enum.Font.BuilderSansMedium, LEFT)
  local track = ui.frame(localPanel, UDim2.new(1, -24, 0, 3), UDim2.new(0, 12, 1, -9), MUTE, 0.72)
  local fill = ui.frame(track, UDim2.fromScale(0, 1), nil, AMBER, 0)

  local baseX, baseY, viewportW, viewportH, touchWidth, routeNames, canFit
  local redeployHint = false
  local lastPoint, meter = nil, 0

  local function resize(viewport)
    viewportW, viewportH = viewport.X, viewport.Y
    touchWidth = G.infantryTouchWidth
    local compact = mobile or viewportH < 500 or viewportW < 640
    local tiny = compact and viewportH < 360
    local hud = G.hudLayout
    local left, right = 16, 16
    local radarReserve = hud and (hud.radarX + hud.radarSize + 12) or 0
    if hud and hud.radarRight then right = radarReserve end
    if mobile then
      if hud and not hud.radarRight then left = radarReserve end
      if viewportW >= viewportH then right = touchWidth or 178 end
    end
    local width = math.max(1, math.min(viewportW - left - right, compact and 456 or 588))
    canFit = width >= 150
    routeNames = width >= 390
    local center = math.max(left + width / 2, math.min(viewportW / 2, viewportW - right - width / 2))
    baseX = center - viewportW / 2
    baseY = (hud and hud.scoreBottom or (mobile and 88 or 108)) + 7
    local inset = compact and 12 or 19
    local contentSize = UDim2.new(1, -inset * 2, 0, compact and 26 or 42)
    brief.Size = UDim2.fromOffset(width, tiny and 80 or (compact and 104 or 139))
    header.Position = UDim2.fromOffset(inset, compact and 7 or 11)
    sector.Position = UDim2.new(0.57, 4, 0, compact and 7 or 11)
    header.TextSize, sector.TextSize = compact and 10 or 11, compact and 10 or 11
    title.Size, title.Position = contentSize, UDim2.fromOffset(inset, compact and 19 or 23)
    titleSize.MaxTextSize = compact and 23 or 35
    description.Size = UDim2.new(1, -inset * 2, 0, compact and 34 or 38)
    description.Position = UDim2.fromOffset(inset, compact and 46 or 65)
    orderSize.MaxTextSize = compact and 12 or 15
    route.Visible = not tiny
    route.Size = UDim2.new(1, -inset * 2 + 3, 0, compact and 18 or 23)
    route.Position = UDim2.new(0, inset, 1, compact and -23 or -31)
    localPanel.Size = UDim2.fromOffset(math.min(width, 334), 58)
    localPanel.Position = UDim2.new(0.5, baseX, 0, baseY)
  end

  local function writeBrief(s, stage)
    local accent = s.team == "atk" and AMBER or TEAL
    local key = "stage." .. stage.id
    rail.BackgroundColor3, header.TextColor3 = accent, accent
    -- 开场的名字跟着钟点（用户 11-25 昼夜更替：原来锁着晚上，一直写「夜间突击」）
    local opening = "operation.opening"
    if G.clockNow and G.Map and G.Map.DESERT then
      local c = G.clockNow()
      opening = (c >= 4.5 and c < 7.5) and "operation.dawn" or ((c >= 7.5 and c < 17) and "operation.day" or ((c >= 17 and c < 19.5) and "operation.dusk" or "operation.night"))
    end
    header.Text = s.stage == 1 and T(opening) or T("faction." .. s.team .. ".name")
    sector.Text = T("hud.stageN", s.stage, s.stages or #stages)
    title.Text, description.Text = T(key), T(key .. "." .. s.team)
    for i, stop in ipairs(stops) do
      local current, complete = i == s.stage, i < s.stage
      stop.frame.BackgroundColor3 = current and accent or INK
      stop.frame.BackgroundTransparency = current and 0.05 or 0.2
      stop.edge.BackgroundColor3 = complete and accent or MUTE
      stop.edge.Visible = not current
      stop.label.TextColor3 = current and INK or (complete and accent or MUTE)
      stop.label.Text = routeNames and (stop.points .. "  ·  " .. T("stage." .. stages[i].id .. ".short")) or stop.points
    end
    renderedLanguage = G.lang
  end

  local function closestPoint(s)
    if G.fly or G.sail then return nil end
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local pos = root.CFrame.Position
    local closest, best = nil, capture.r ^ 2
    for _, state in ipairs(s.points or {}) do
      local p = pointById[state.id]
      if p and state.act and not state.locked and math.abs(p.y - pos.Y) < capture.height then
        local distance = (p.x - pos.X) ^ 2 + (p.z - pos.Z) ^ 2
        if distance < best then closest, best = state, distance end
      end
    end
    return closest
  end

  local function showCapture(s, p, dt)
    local progress = math.clamp(p.prog or 0, 0, 1)
    local key, color = "operation.inZone", MUTE
    if p.motion == 1 then
      key = s.team == "atk" and "operation.capturing" or "operation.losing"
      color = AMBER
    elseif p.motion == -1 then
      key, color = "operation.recovering", TEAL
    elseif (p.atk or 0) > 0 then
      key = "operation.stalled"
    end
    if reducedMotion or lastPoint ~= p.id then meter = progress end
    lastPoint = p.id
    meter += (progress - meter) * math.min(dt * 14, 1)
    fill.Size = UDim2.fromScale(meter, 1)
    fill.BackgroundColor3 = color
    localPanel.Visible = true
    status.Text, status.TextColor3 = T(key), color
    objective.Text = T("point." .. p.id)
    percent.Text = string.format("%d%%", math.floor(progress * 100 + 0.5))
  end

  G.operationHudVisible = function() return brief.Visible or localPanel.Visible end
  function G.stepOperation(dt)
    local s = G.S
    local canBrief = s and s.phase == "battle" and s.alive and s.team
      and not G.scopeOn and not G.fpsAiming and not (G.drive and (G.drive.sight or G.drive.eo))
      and not (G.boardShown and G.boardShown()) and not (G.menuOpen and G.menuOpen())
      and not (G.menuShown and G.menuShown()) and not G.factionOpen
      and not (G.tabletState and G.tabletState.open)
      and not (G.killcamOn and G.killcamOn())
    if not canBrief then
      brief.Visible, localPanel.Visible, lastPoint = false, false, nil
      if s and s.phase ~= "battle" then startedAt = nil end
      return
    end

    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize
    if not viewport or viewport.X < 1 or viewport.Y < 1 then return end
    local resized = viewport.X ~= viewportW or viewport.Y ~= viewportH or touchWidth ~= G.infantryTouchWidth
    if resized then resize(viewport) end

    local time = os.clock()
    local stage = stages[s.stage]
    if stage and (s.round ~= shownRound or s.stage ~= shownStage) then
      redeployHint = not mobile and shownRound == s.round and shownStage ~= nil and s.stage > shownStage
      shownRound, shownStage, shownTeam, startedAt = s.round, s.stage, s.team, time
      writeBrief(s, stage)
      if G.playSound then G.playSound("capture", nil, 0.65) end
    end

    local hold = s.stage == 1 and OPENING_HOLD or HOLD
    local age = startedAt and time - startedAt or hold
    brief.Visible = canFit and stage ~= nil and age < hold
    if brief.Visible then
      if resized or renderedLanguage ~= G.lang or shownTeam ~= s.team then
        shownTeam = s.team
        writeBrief(s, stage)
      end
      local reveal = reducedMotion and 1 or math.clamp(age / 0.36, 0, 1)
      local eased = 1 - (1 - reveal) ^ 3
      brief.Position = UDim2.new(0.5, baseX, 0, baseY + 9 * (1 - eased))
      brief.GroupTransparency = reducedMotion and 0 or math.clamp(math.max(1 - reveal, (age - hold + 0.42) / 0.42), 0, 1)
      rail.Size = UDim2.new(eased, 0, 0, 2)
    elseif redeployHint then
      redeployHint = false
      local distance = G.objDist()
      if distance and distance > 1200 then G.toast(T("hud.redeployTip"), "info") end
    end

    local p = canFit and not brief.Visible and closestPoint(s)
    if p then
      showCapture(s, p, dt)
    else
      localPanel.Visible, lastPoint = false, nil
    end
  end
end

return Operation
