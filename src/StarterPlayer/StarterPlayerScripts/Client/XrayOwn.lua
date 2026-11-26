-- 全面大战场（客户端）——透视自己的车（战雷式 X 光）
--   用户 11-26：「x透视做的非常潦草 且没有显示」「x应该是摁住显示3d 松手就恢复原样 然后 不同区域要有不同颜色标识 发动机 弹药箱 成员 爆反等等」
--   · 按住 X 显示、松开恢复（Drive.lua 调 G.ownXrayHold）；开着瞄准镜按住会先退到车外看（松手回镜里），原来镜里按 X 什么都没有
--   · 车身变成半透明的壳 + 轮廓线；里面按类别不同颜色：乘员（人形）、发动机、传动、油箱、弹药、炮闩、炮管、炮塔驱动、爆反块（模型上真的那些块）
--   · 每类一个 Highlight（AlwaysOnTop，隔着车身也看得见；Roblox 最多 31 个，这里十来个）；坏了的叠黄 / 红，乘员阵亡暗红
--   · 状态取服务器写在车上的 WtC / WtM（同战后 X 光回放）；屏幕下方一排图例
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local XrayOwn = {}

function XrayOwn.init(G)
  local W = require(RS:WaitForChild("WtDamage"))
  local TH = require(RS:WaitForChild("Theme"))
  local V3, CF, RGB = Vector3.new, CFrame.new, Color3.fromRGB
  local T = function(k, fb) local s = G.T and G.T(k) return (s and s ~= k) and s or fb end
  -- 类别：颜色、图例文字（中、英）
  local CAT = {
    crew = { RGB(90, 210, 120), "xr.crew", "乘员" },
    engine = { RGB(235, 140, 45), "xr.engine", "发动机" },
    trans = { RGB(205, 175, 70), "xr.trans", "传动" },
    fuel = { RGB(245, 215, 70), "xr.fuel", "油箱" },
    ammo = { RGB(225, 60, 55), "xr.ammo", "弹药" },
    breech = { RGB(185, 120, 230), "xr.breech", "炮闩" },
    barrel = { RGB(150, 140, 205), "xr.barrel", "炮管" },
    tdrive = { RGB(120, 200, 190), "xr.tdrive", "炮塔驱动" },
    era = { RGB(235, 95, 175), "xr.era", "爆反" },
    other = { RGB(170, 170, 165), "xr.other", "其他" },
    hurt = { RGB(255, 225, 60), "xr.hurt", "受损" },
    dead = { RGB(120, 20, 20), "xr.dead", "坏了 / 阵亡" },
  }
  local ORDER = { "crew", "engine", "trans", "fuel", "ammo", "breech", "barrel", "tdrive", "era", "hurt", "dead" }
  local function catOf(it)
    if it.kind == "crew" then return "crew" end
    local k = it.k or ""
    if k == "engine" then return "engine" end
    if k == "trans" then return "trans" end
    if k:sub(1, 4) == "fuel" then return "fuel" end
    if k:sub(1, 4) == "ammo" then return "ammo" end
    if k == "breech" then return "breech" end
    if k == "barrel" then return "barrel" end
    if k == "tdrive" then return "tdrive" end
    return "other"
  end

  local cur = nil   -- { st, folder, groups = { [类] = Model }, items = { { it, parts, c, cat } }, era = { { e, box } }, faded, hl, legend }
  local function newPart(size, shape)
    local p = Instance.new("Part")
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    p.Material = Enum.Material.SmoothPlastic
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    if shape then p.Shape = shape end
    p.Size = size
    return p
  end
  local function clear()
    if not cur then return end
    if cur.folder then cur.folder:Destroy() end
    if cur.hl then cur.hl:Destroy() end
    if cur.legend then cur.legend:Destroy() end
    for _, p in ipairs(cur.faded or {}) do if p.Parent then p.LocalTransparencyModifier = 0 end end
    cur = nil
  end
  local function legend()
    local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not pg then return nil end
    local sg = Instance.new("ScreenGui")
    sg.Name, sg.ResetOnSpawn, sg.IgnoreGuiInset, sg.DisplayOrder = "OwnXrayLegend", false, true, 20
    local bar = Instance.new("Frame")
    bar.AnchorPoint, bar.Position, bar.Size = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -96), UDim2.fromOffset(0, 26)
    bar.AutomaticSize = Enum.AutomaticSize.X
    bar.BackgroundColor3, bar.BackgroundTransparency, bar.BorderSizePixel = TH.C.PANEL, 0.25, 0
    bar.Parent = sg
    local lay = Instance.new("UIListLayout")
    lay.FillDirection, lay.VerticalAlignment, lay.Padding = Enum.FillDirection.Horizontal, Enum.VerticalAlignment.Center, UDim.new(0, 10)
    lay.Parent = bar
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
    pad.Parent = bar
    for i, k in ipairs(ORDER) do
      local c = CAT[k]
      local sw = Instance.new("Frame")
      sw.LayoutOrder, sw.Size, sw.BackgroundColor3, sw.BorderSizePixel = i * 2, UDim2.fromOffset(12, 12), c[1], 0
      sw.Parent = bar
      local t = Instance.new("TextLabel")
      t.LayoutOrder, t.AutomaticSize, t.Size = i * 2 + 1, Enum.AutomaticSize.X, UDim2.fromOffset(0, 20)
      t.BackgroundTransparency, t.Text, t.TextColor3 = 1, T(c[2], c[3]), TH.C.TEXT
      t.Font, t.TextSize = TH.F and TH.F.body or Enum.Font.Gotham, 14
      t.Parent = bar
    end
    sg.Parent = pg
    return sg
  end
  local function build(st)
    local d = st.d
    local okL, lay = pcall(W.layout, d)
    if not okL or not lay then return nil end
    local folder = Instance.new("Folder")
    folder.Name = "OwnXray"
    folder.Parent = workspace
    local groups = {}
    local function group(k)
      if groups[k] then return groups[k] end
      local m = Instance.new("Model")
      m.Name = "X_" .. k
      m.Parent = folder
      local h = Instance.new("Highlight")
      h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
      h.FillColor, h.OutlineColor = CAT[k][1], CAT[k][1]:Lerp(RGB(255, 255, 255), 0.35)
      h.FillTransparency, h.OutlineTransparency = 0.2, 0.05
      h.Adornee, h.Parent = m, m
      groups[k] = m
      return m
    end
    local items = {}
    for _, it in ipairs(lay.list) do
      local size = it.hi - it.lo
      local cat = catOf(it)
      local parts = {}
      if it.kind == "crew" then   -- 人形：身子 + 头（坐着）
        local w = math.min(size.X, size.Z)
        local body = newPart(V3(w * 0.7, size.Y * 0.55, w * 0.5))
        local head = newPart(V3(w * 0.45, w * 0.45, w * 0.45), Enum.PartType.Ball)
        parts = { { body, V3(0, -size.Y * 0.12, 0) }, { head, V3(0, size.Y * 0.32, 0) } }
      else
        parts = { { newPart(V3(math.max(size.X, 0.15), math.max(size.Y, 0.15), math.max(size.Z, 0.15))), V3() } }
      end
      for _, pp in ipairs(parts) do pp[1].Parent = group(cat) end
      table.insert(items, { it = it, parts = parts, c = (it.lo + it.hi) / 2, cat = cat })
    end
    -- 爆反块：模型上真的那些块（VehModels 的 M.era；炸掉的不画）
    local era = {}
    local v = G.views and G.views[st.em]
    local M = v and v.M
    for _, e in ipairs((M and M.era) or {}) do
      for _, p in ipairs(e.parts or {}) do
        if p:IsA("BasePart") then
          local b = newPart(p.Size)
          b.Parent = group("era")
          table.insert(era, { e = e, src = p, box = b })
        end
      end
    end
    -- 车身：半透明的壳 + 轮廓线
    local faded, hl = {}, nil
    local m = v and v.model
    if m then
      for _, q in ipairs(m:GetDescendants()) do
        if q:IsA("BasePart") and q.Transparency < 0.95 then
          q.LocalTransparencyModifier = 0.82
          table.insert(faded, q)
        end
      end
      hl = Instance.new("Highlight")
      hl.DepthMode = Enum.HighlightDepthMode.Occluded
      hl.FillTransparency, hl.OutlineTransparency, hl.OutlineColor = 1, 0.25, RGB(225, 228, 220)
      hl.Adornee, hl.Parent = m, folder
    end
    return { st = st, folder = folder, groups = groups, group = group, items = items, era = era, faded = faded, hl = hl, legend = legend() }
  end
  local function states(em)
    local cs, ms = {}, {}
    local wc, wm = em:GetAttribute("WtC"), em:GetAttribute("WtM")
    local i = 0
    for tok in string.gmatch(wc or "", "[^,]+") do i += 1 cs[i] = tonumber(string.sub(tok, 1, 1)) or 2 end
    for j = 1, #(wm or "") do ms[j] = tonumber(string.sub(wm, j, j)) or 2 end
    return cs, ms
  end

  local holding = false
  function G.ownXrayOn() return holding and cur ~= nil end
  function G.ownXrayHold(down)
    holding = down and true or false
    if not holding then clear() end
  end
  G.ownXrayToggle = function() G.ownXrayHold(not holding) return holding end   -- 老的调用（测试）还能用
  RunService.RenderStepped:Connect(function()
    if not holding then return end
    local st = G.drive
    if not st or not st.em or not st.em.Parent or not st.root then holding = false clear() return end
    if not cur or cur.st ~= st then
      clear()
      cur = build(st)
      if not cur then holding = false return end
    end
    local d = st.d
    local base = st.root * CF(0, -d.H / 2, 0)
    local yaw = st.ty or 0
    local cs, ms = states(st.em)
    local ci, mi = 0, 0
    for _, x in ipairs(cur.items) do
      local s
      if x.it.kind == "crew" then ci += 1 s = cs[ci] or 2 else mi += 1 s = ms[mi] or 2 end
      local g = (s == 0) and "dead" or ((s == 1) and "hurt" or x.cat)
      local cf = x.it.tur and (base * CF(W.fromTur(d, x.c, yaw)) * CFrame.Angles(0, -math.rad(yaw), 0)) or (base * CF(x.c))
      local grp = cur.group(g)
      for _, pp in ipairs(x.parts) do
        if pp[1].Parent ~= grp then pp[1].Parent = grp end
        pp[1].CFrame = cf * CF(pp[2])
      end
    end
    for _, r in ipairs(cur.era) do
      if r.e.blown or not r.src.Parent then
        if r.box.Parent then r.box.Parent = nil end
      else
        r.box.CFrame = r.src.CFrame
      end
    end
  end)
end

return XrayOwn
