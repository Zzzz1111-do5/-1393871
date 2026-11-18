-- 夜间登陆的阶段简报与据点反馈。由服务器快照驱动，补上中途入场的当前目标。
local Players = game:GetService("Players")

local Operation = {}

local RGB = Color3.fromRGB
local INK = RGB(9, 18, 25)
local WHITE = RGB(234, 243, 247)
local MUTE = RGB(157, 182, 195)
local TEAL = RGB(121, 220, 213)
local AMBER = RGB(255, 192, 122)
local CENTER_TOP = Vector2.new(0.5, 0)
local LEFT = Enum.TextXAlignment.Left
local RIGHT = Enum.TextXAlignment.Right
local HOLD = 4.8

function Operation.init(G)
  local ui, T, mobile = G.ui, G.T, G.mobile
  local player = Players.LocalPlayer
  local stages = G.Config.Stages or {}
  local capture = G.Config.Capture
  local pointById = {}
  for _, p in ipairs(G.Map.POINTS) do pointById[p.id] = p end

  local function panel(className, name, width, height)
    local f = Instance.new(className)
    f.Name = name
    f.AnchorPoint = CENTER_TOP
    f.Position = UDim2.new(0.5, mobile and -22 or 0, 0, mobile and 86 or 112)
    f.Size = mobile and UDim2.new(1, -400, 0, height) or UDim2.new(0.82, 0, 0, height)
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = INK, 0.1, 0
    f.ZIndex, f.Visible = 24, false
    local bounds = Instance.new("UISizeConstraint")
    bounds.MaxSize = Vector2.new(width, height)
    bounds.Parent = f
    f.Parent = G.gui
    return f
  end

  local function label(parent, name, size, pos, fontSize, color, font, align)
    local l = ui.label(parent, "", size, pos, fontSize, color, font, nil, align)
    l.Name = name
    return l
  end

  local brief = panel("CanvasGroup", "OperationBrief", mobile and 438 or 562, mobile and 94 or 128)
  local rail = ui.frame(brief, UDim2.new(1, 0, 0, 2), nil, TEAL, 0)
  local header = label(brief, "Sector", UDim2.new(1, -32, 0, 13), UDim2.fromOffset(16, mobile and 7 or 10), 11, TEAL, Enum.Font.GothamBold, LEFT)
  local title = label(brief, "Title", UDim2.new(1, -32, 0, mobile and 25 or 34), UDim2.fromOffset(16, mobile and 19 or 23),
    mobile and 22 or 30, WHITE, Enum.Font.GothamBlack, LEFT)
  local description = label(brief, "Orders", UDim2.new(1, -32, 0, mobile and 27 or 33), UDim2.fromOffset(16, mobile and 43 or 57),
    mobile and 12 or 14, WHITE, Enum.Font.GothamMedium, LEFT)
  description.TextYAlignment = Enum.TextYAlignment.Top
  local route = ui.frame(brief, UDim2.new(1, -32, 0, mobile and 19 or 23), UDim2.new(0, 16, 1, mobile and -24 or -30), INK, 1)
  route.Name = "Route"
  local stops = {}
  for i, stage in ipairs(stages) do
    local width = 1 / #stages
    local stop = ui.frame(route, UDim2.new(width, -4, 1, 0), UDim2.new((i - 1) * width, 0, 0, 0), TEAL, 0.8)
    stop.Name = stage.id
    local text = label(stop, "Objectives", UDim2.fromScale(1, 1), nil, 11, WHITE, Enum.Font.GothamBold)
    stops[i] = { frame = stop, label = text, points = table.concat(stage.points, " · ") }
  end

  local localPanel = panel("Frame", "ObjectiveStatus", 334, 56)
  ui.stroke(localPanel, MUTE, 1, 0.68)
  local objective = label(localPanel, "Objective", UDim2.new(1, -80, 0, 18), UDim2.fromOffset(12, 6), 14, WHITE, Enum.Font.GothamBold, LEFT)
  local percent = label(localPanel, "Progress", UDim2.fromOffset(56, 18), UDim2.new(1, -68, 0, 6), 14, WHITE, Enum.Font.GothamBold, RIGHT)
  local status = label(localPanel, "Status", UDim2.new(1, -24, 0, 14), UDim2.fromOffset(12, 25), 11, MUTE, Enum.Font.GothamMedium, LEFT)
  local track = ui.frame(localPanel, UDim2.new(1, -24, 0, 3), UDim2.new(0, 12, 1, -9), MUTE, 0.72)
  local fill = ui.frame(track, UDim2.fromScale(0, 1), nil, AMBER, 0)

  local shownRound, shownStage, startedAt, renderedLanguage
  local redeployHint = false
  local lastPoint, meter = nil, 0

  local function writeBrief(s, stage)
    local accent = s.team == "atk" and AMBER or TEAL
    local key = "stage." .. stage.id
    rail.BackgroundColor3, header.TextColor3 = accent, accent
    header.Text = T("hud.stageN", s.stage, s.stages or #stages)
    title.Text, description.Text = T(key), T(key .. "." .. s.team)
    for i, stop in ipairs(stops) do
      stop.frame.BackgroundColor3 = i == s.stage and accent or MUTE
      stop.frame.BackgroundTransparency = i == s.stage and 0.07 or (i < s.stage and 0.81 or 0.9)
      stop.label.TextColor3 = i == s.stage and INK or MUTE
      stop.label.Text = mobile and stop.points or (T("stage." .. stages[i].id .. ".short") .. "  " .. stop.points)
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
    local progress = p.prog or 0
    local key, color = "operation.inZone", MUTE
    if p.motion == 1 then
      key = s.team == "atk" and "operation.capturing" or "operation.losing"
      color = AMBER
    elseif p.motion == -1 then
      key, color = "operation.recovering", TEAL
    elseif (p.atk or 0) > 0 then
      key = "operation.stalled"
    end
    if lastPoint ~= p.id then meter = progress end
    lastPoint = p.id
    meter += (progress - meter) * math.min(dt * 14, 1)
    fill.Size = UDim2.fromScale(meter, 1)
    localPanel.Visible = true
    status.Text, status.TextColor3 = T(key), color
    objective.Text = T("point." .. p.id)
    percent.Text = string.format("%d%%", math.floor(progress * 100 + 0.5))
  end

  G.operationHudVisible = function() return brief.Visible or localPanel.Visible end
  function G.stepOperation(dt)
    local s = G.S
    local canBrief = s and s.phase == "battle" and s.alive and s.team
      and not G.scopeOn and not (G.drive and (G.drive.sight or G.drive.eo))
      and not (G.boardShown and G.boardShown()) and not (G.menuOpen and G.menuOpen())
      and not (G.tabletState and G.tabletState.open)
    if not canBrief then
      brief.Visible, localPanel.Visible, lastPoint = false, false, nil
      if s and s.phase ~= "battle" then startedAt = nil end
      return
    end

    local time = os.clock()
    local stage = stages[s.stage]
    if stage and (s.round ~= shownRound or s.stage ~= shownStage) then
      redeployHint = not mobile and shownRound == s.round and shownStage ~= nil and s.stage > shownStage
      shownRound, shownStage, startedAt = s.round, s.stage, time
      writeBrief(s, stage)
      if G.playSound then G.playSound("capture", nil, 0.65) end
    end

    local age = startedAt and time - startedAt or HOLD
    brief.Visible = stage ~= nil and age < HOLD
    if brief.Visible then
      if renderedLanguage ~= G.lang then writeBrief(s, stage) end
      brief.GroupTransparency = math.clamp(math.max(1 - age / 0.22, (age - HOLD + 0.45) / 0.45), 0, 1)
    elseif redeployHint then
      redeployHint = false
      local distance = G.objDist()
      if distance and distance > 1200 then G.toast(T("hud.redeployTip"), "info") end
    end

    local p = not brief.Visible and closestPoint(s)
    if p then
      showCapture(s, p, dt)
    else
      localPanel.Visible, lastPoint = false, nil
    end
  end
end

return Operation
