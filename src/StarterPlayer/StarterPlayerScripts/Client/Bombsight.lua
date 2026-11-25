-- 全面大战场（客户端）——战雷式轰炸瞄准镜的画面（F7「轰炸机视角」）和 CCRP 目标点的标记
--   用户 11-24：「飞机锁定敌目标改成战雷一模一样的 包括投弹以及各方面操作细节和手感」
--   状态、按键、镜头、投弹都在 Fly.lua（st.bsight、st.poi、st.ccrp）；这里只画，Fly.lua 每帧调 G.bsDraw(s)：
--   ① 瞄准镜（s.on）：圆形视场（四周压黑），十字中心就是炸弹现在投下去的落点；竖线是航迹方向，竖线上的秒刻度是
--      「地上这一点再过几秒走到十字中心」（目标滑到中心就投）；左边一列：离地高度、地速、落下时间、投弹方式和剩几枚；
--      最下面一行按键
--   ② 目标点（战雷的「兴趣点」，Alt + 中键标的）：红方框，上面一根箭头——歪向要转的那边，旁边写还有几秒投弹、
--      航向差几度；航向偏得太多变灰（这一趟不投）；在屏幕外面（比如拉起抛投时）贴着屏幕边
local Players = game:GetService("Players")

local Bombsight = {}

function Bombsight.init(G)
  local ui = G.ui
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local me = Players.LocalPlayer
  local RGB, U2, V2 = Color3.fromRGB, UDim2, Vector2.new
  local clamp = math.clamp

  local function screen(name, order)
    local g = Instance.new("ScreenGui")
    g.Name = name
    g.ResetOnSpawn = false
    g.IgnoreGuiInset = true
    g.DisplayOrder = order
    g.Enabled = false
    g.Parent = me:WaitForChild("PlayerGui")
    return g
  end
  local gui = screen("Bombsight", 6)   -- 瞄准镜画面
  local cgui = screen("Ccrp", 7)       -- 目标点（瞄准镜里、外面都画）

  local INK, LIGHT = RGB(10, 11, 9), RGB(255, 248, 220)
  -- 一道线：外面一圈黑、中间一道亮的（地面亮暗都看得清）
  local function line(parent, name)
    local f = ui.frame(parent, U2.fromOffset(3, 3), nil, INK, 0.3, V2(0.5, 0.5))
    f.Name = name
    local hi = ui.frame(f, U2.new(1, -2, 1, -2), U2.fromScale(0.5, 0.5), LIGHT, 0.05, V2(0.5, 0.5))
    hi.Name = "Hi"
    return f
  end
  local function text(parent, name, size, pos, ts, anchor, align)
    local l = ui.label(parent, "", size, pos, ts, LIGHT, Enum.Font.Code, anchor, align)
    l.Name = name
    l.TextStrokeTransparency = 0.25
    l.TextStrokeColor3 = INK
    return l
  end

  ---------------------------------------------------------------- 瞄准镜

  -- 镜片：画面中间一个正圆（按屏幕高度），外面一圈很粗的黑描边把四周压黑
  local lens = ui.frame(gui, U2.fromScale(0.92, 0.92), U2.fromScale(0.5, 0.5), RGB(0, 0, 0), 1, V2(0.5, 0.5))
  lens.Name = "BsLens"
  do
    local ar = Instance.new("UIAspectRatioConstraint")
    ar.AspectRatio = 1
    ar.DominantAxis = Enum.DominantAxis.Height
    ar.Parent = lens
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = lens
    local vig = ui.stroke(lens, RGB(3, 4, 5), 2600, 0)
    vig.Name = "Vignette"
    local rim = ui.frame(lens, U2.fromScale(1, 1), U2.fromScale(0.5, 0.5), RGB(0, 0, 0), 1, V2(0.5, 0.5))
    rim.Name = "Rim"
    local c2 = Instance.new("UICorner")
    c2.CornerRadius = UDim.new(0.5, 0)
    c2.Parent = rim
    ui.stroke(rim, RGB(70, 66, 52), 3, 0.2)
  end
  -- 十字：竖线（航迹）从上到下，横线中间留空；中心一个小圈
  local vLine = line(gui, "BsVLine")
  local hL, hR = line(gui, "BsHLine"), line(gui, "BsHLine")
  local center = ui.frame(gui, U2.fromOffset(14, 14), nil, RGB(0, 0, 0), 1, V2(0.5, 0.5))
  center.Name = "BsCenter"
  do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = center
    ui.stroke(center, LIGHT, 2, 0.05)
  end
  -- 竖线上的秒刻度（1～6 秒）
  local ticks = {}
  for i = 1, 6 do
    local tk = line(gui, "BsTick")
    local lb = text(gui, "BsTickText", U2.fromOffset(30, 16), U2.new(), 13, V2(0, 0.5), Enum.TextXAlignment.Left)
    lb.Text = tostring(i)
    ticks[i] = { tk = tk, lb = lb }
  end
  -- 左边一列数、最下面一行按键
  local data = text(gui, "BsData", U2.fromOffset(300, 120), U2.new(), 16, V2(0, 0), Enum.TextXAlignment.Left)
  data.TextYAlignment = Enum.TextYAlignment.Top
  local hint = text(gui, "BsHint", U2.new(1, -40, 0, 20), U2.new(0.5, 0, 1, -14), 14, V2(0.5, 1))
  local title = text(gui, "BsTitle", U2.fromOffset(400, 22), U2.new(0.5, 0, 0, 14), 16, V2(0.5, 0))

  ---------------------------------------------------------------- 目标点

  local RED, GREY = RGB(255, 64, 52), RGB(150, 150, 150)
  local box = ui.frame(cgui, U2.fromOffset(22, 22), nil, RGB(0, 0, 0), 1, V2(0.5, 0.5))
  box.Name = "PoiBox"
  local boxStroke = ui.stroke(box, RED, 2, 0)
  -- 箭头：一根竖线 + 顶上的三角，整个框的中心在方框上（绕方框转）
  local arrow = ui.frame(cgui, U2.fromOffset(24, 132), nil, RGB(0, 0, 0), 1, V2(0.5, 0.5))
  arrow.Name = "PoiArrow"
  local shaft = ui.frame(arrow, U2.fromOffset(2, 44), U2.new(0.5, 0, 0, 16), LIGHT, 0, V2(0.5, 0))
  shaft.Name = "Shaft"
  local head = ui.label(arrow, "▲", U2.fromOffset(24, 18), U2.new(0.5, 0, 0, 0), 16, LIGHT, Enum.Font.GothamBold, V2(0.5, 0))
  head.Name = "Head"
  head.TextStrokeTransparency = 0.3
  local cInfo = text(cgui, "PoiText", U2.fromOffset(170, 36), U2.new(), 15, V2(0, 0.5), Enum.TextXAlignment.Left)
  cInfo.TextYAlignment = Enum.TextYAlignment.Center

  local function fmtDev(dev)
    local a = math.floor(math.abs(dev) + 0.5)
    if a < 1 then return "✓" end
    return (dev < 0) and ("◀ " .. a .. "°") or (a .. "° ▶")
  end

  local function drawPoi(s, c)
    local p = s.poi
    if not p then
      cgui.Enabled = false
      return
    end
    cgui.Enabled = true
    local vs = c.ViewportSize
    local sp = c:WorldToViewportPoint(p)
    local x, y = sp.X, sp.Y
    if sp.Z < 0 then x, y = vs.X - x, vs.Y * 4 end   -- 在身后（拉起抛投、飞过了）：贴到屏幕下边
    local m = 30
    local edge = x < m or x > vs.X - m or y < m or y > vs.Y - m
    x, y = clamp(x, m, vs.X - m), clamp(y, m, vs.Y - m)
    box.Position = U2.fromOffset(x, y)
    box:SetAttribute("Edge", edge)
    local cc = s.ccrp
    local ok = cc ~= nil and cc.ok and not cc.passed
    local col = ok and LIGHT or GREY
    boxStroke.Color = (cc and not ok) and GREY or RED
    arrow.Position = U2.fromOffset(x, y)
    arrow.Visible = cc ~= nil and not cc.passed   -- 贴在屏幕边上也画（照着它转过去）
    arrow.Rotation = cc and clamp(cc.dev * 3, -75, 75) or 0
    shaft.BackgroundColor3, head.TextColor3 = col, col
    arrow:SetAttribute("Ok", ok)
    cInfo.Position = U2.fromOffset(x + 18, y + 18)
    cInfo.TextColor3 = col
    if s.relT and os.clock() - s.relT < 1.2 then
      cInfo.Text = T("air.ccrpRel")
    elseif not cc then
      cInfo.Text = s.noBomb and T("air.ccrpNoBomb") or ""
    elseif cc.passed then
      cInfo.Text = T("air.ccrpPassed")
    else
      cInfo.Text = T("air.ccrpT", string.format("%.1f", math.max(0, cc.ttr))) .. "\n" .. fmtDev(cc.dev)
    end
  end

  ---------------------------------------------------------------- 每帧

  local function setLine(f, x, y, w, h)
    f.Position, f.Size = U2.fromOffset(x, y), U2.fromOffset(w, h)
  end

  function G.bsDraw(s)
    local c = workspace.CurrentCamera
    drawPoi(s, c)
    if not s.on then
      gui.Enabled = false
      return
    end
    gui.Enabled = true
    local vs = c.ViewportSize
    local cx, cy = vs.X / 2, vs.Y / 2
    local R = vs.Y * 0.46   -- 镜片半径（像素）：按像素定成正圆（Fly.lua 的视场按它算：镜片框住前方 4.5 秒的地面）
    lens.Size = U2.fromOffset(R * 2, R * 2)
    setLine(vLine, cx, cy, 3, R * 2)
    local gap, len = 12, R * 0.8
    setLine(hL, cx - gap - len / 2, cy, len, 3)
    setLine(hR, cx + gap + len / 2, cy, len, 3)
    center.Position = U2.fromOffset(cx, cy)
    -- 秒刻度：落点顺着航迹往前 1、2、3……秒地速的地方投到屏幕上（目标在「3」上，再过 3 秒就到十字中心）
    for i, t in ipairs(ticks) do
      local p = s.imp and s.dir and s.gs and (s.imp + s.dir * (s.gs * i))
      local sp = p and c:WorldToViewportPoint(p)
      local show = sp ~= nil and sp.Z > 0 and math.abs(sp.Y - cy) < R * 0.95 and math.abs(sp.Y - cy) > 8
      t.tk.Visible, t.lb.Visible = show, show
      if show then
        local wdt = (i % 5 == 0) and 26 or 16
        setLine(t.tk, cx, sp.Y, wdt, 3)
        t.lb.Position = U2.fromOffset(cx + wdt / 2 + 4, sp.Y)
      end
    end
    -- 左边一列数（镜片左上里面）
    data.Position = U2.fromOffset(cx - R * 0.78, cy - R * 0.62)
    local lines = {
      T("air.bsAlt", math.max(0, math.floor((s.agl or 0) + 0.5))),
      T("air.bsSpd", math.floor((s.kmh or 0) + 0.5)),
      T("air.bsFall", string.format("%.1f", s.tf or 0)),
      T("air.bsMode" .. tostring(s.mode or 1)) .. "  ·  " .. (s.wname or "") .. "  ×" .. tostring(s.left or 0),
    }
    if s.zoom and s.zoom > 1 then lines[#lines + 1] = string.format("%d×", s.zoom) end
    data.Text = table.concat(lines, "\n")
    title.Text = T("air.bsTitle")
    hint.Text = T("air.bsHint")
  end

  function G.bsOff()
    gui.Enabled, cgui.Enabled = false, false
  end
  G.bsGui, G.ccrpGui = gui, cgui   -- 测试用
end

return Bombsight
