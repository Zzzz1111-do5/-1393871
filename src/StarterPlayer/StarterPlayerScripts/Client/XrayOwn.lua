-- 全面大战场（客户端）——透视自己的车（用户 11-25「x改成透视自己的坦克」）
--   开车时按 X：自己的车变成半透明，车里的乘员（球）和模块（发动机、传动、弹药架、油箱、炮闩、炮塔驱动、履带、炮管……）
--   按战雷那样上色：乘员绿好、黄伤、红没了；模块灰蓝好、黄伤、红坏了——状态取服务器写在车上的 WtC / WtM（同 X 光回放，WtHud.lua）；
--   炮塔里的跟着炮塔转。再按 X 关上；下车、换车自动关
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local XrayOwn = {}

function XrayOwn.init(G)
  local W = require(RS:WaitForChild("WtDamage"))
  local TH = require(RS:WaitForChild("Theme"))
  local V3 = Vector3.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local OK, HURT, DEAD, MOD = TH.C.GOOD, TH.C.WARN, TH.C.BAD, RGB(120, 150, 170)
  local on, cur = false, nil   -- cur = { st, folder, items = { { it, p } }, faded = { 零件 } }

  local function clear()
    if not cur then return end
    if cur.folder then cur.folder:Destroy() end
    for _, p in ipairs(cur.faded or {}) do if p.Parent then p.LocalTransparencyModifier = 0 end end
    cur = nil
  end
  local function ownModel(st)
    local v = G.views and st and st.em and G.views[st.em]
    return v and v.model or nil
  end
  local function build(st)
    local d = st.d
    local okL, lay = pcall(W.layout, d)
    if not okL or not lay then return nil end
    local folder = Instance.new("Folder")
    folder.Name = "OwnXray"
    folder.Parent = workspace
    local items = {}
    for _, it in ipairs(lay.list) do
      local size = it.hi - it.lo
      local p = Instance.new("Part")
      p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
      p.Material = Enum.Material.Neon
      p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
      if it.kind == "crew" then
        p.Shape = Enum.PartType.Ball
        local s = math.min(size.X, size.Z) * 0.9
        p.Size = V3(s, s, s)
      else
        p.Size = V3(math.max(size.X, 0.1), math.max(size.Y, 0.1), math.max(size.Z, 0.1))
      end
      p.Parent = folder
      table.insert(items, { it = it, p = p, c = (it.lo + it.hi) / 2 })
    end
    -- 自己的车变半透明（车里的东西看得见）
    local faded = {}
    local m = ownModel(st)
    if m then
      for _, q in ipairs(m:GetDescendants()) do
        if q:IsA("BasePart") and q.Transparency < 0.95 then
          q.LocalTransparencyModifier = 0.78
          table.insert(faded, q)
        end
      end
    end
    return { st = st, folder = folder, items = items, faded = faded }
  end
  local function states(em)
    local cs, ms = {}, {}
    local wc = em and em:GetAttribute("WtC")
    local wm = em and em:GetAttribute("WtM")
    local i = 0
    for tok in string.gmatch(wc or "", "[^,]+") do i += 1 cs[i] = tonumber(string.sub(tok, 1, 1)) or 2 end
    for j = 1, #(wm or "") do ms[j] = tonumber(string.sub(wm, j, j)) or 2 end
    return cs, ms
  end

  function G.ownXrayOn() return on end
  function G.ownXrayToggle()
    on = not on
    if not on then clear() end
    if G.sfx then pcall(G.sfx, "uiClick") end
    return on
  end
  RunService.RenderStepped:Connect(function()
    if not on then return end
    local st = G.drive
    if not st or not st.em or not st.em.Parent or not st.root then
      on = false
      clear()
      return
    end
    if not cur or cur.st ~= st then
      clear()
      cur = build(st)
      if not cur then on = false return end
    end
    local d = st.d
    local base = st.root * CF(0, -d.H / 2, 0)
    local cs, ms = states(st.em)
    local ci, mi = 0, 0
    local yaw = st.ty or 0
    for _, x in ipairs(cur.items) do
      local it = x.it
      local s
      if it.kind == "crew" then ci += 1 s = cs[ci] or 2 else mi += 1 s = ms[mi] or 2 end
      local col
      if it.kind == "crew" then col = (s == 0) and DEAD or ((s == 1) and HURT or OK)
      else col = (s == 0) and DEAD or ((s == 1) and HURT or MOD) end
      x.p.Color = col
      x.p.Transparency = (it.kind == "crew") and 0.15 or ((s == 2) and 0.55 or 0.2)
      if it.tur then
        x.p.CFrame = base * CF(W.fromTur(d, x.c, yaw)) * CFrame.Angles(0, -math.rad(yaw), 0)
      else
        x.p.CFrame = base * CF(x.c)
      end
    end
  end)
end

return XrayOwn
