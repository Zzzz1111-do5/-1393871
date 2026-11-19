-- Roblox全面大战场（客户端）——手雷抛物线预览（用户：持枪、手雷一切这种，放开了做）
--   拿着手雷（武器 kind = "throw"）按住右键瞄：照服务器扔雷的算法（Weapons.lua KIND.throw：头顶上方出手、45° 抛向准星、最远 range，
--   弹道重力 = Gravity × 0.55，碰到东西弹一下、速度剩 35%）一步步算出去，画一串由白到橙的小点；第一次落地的地方一个小圈；
--   引信到点（fuse 秒）时手雷在哪就在哪画一个红圈（爆炸半径 splash），上面写着秒数。松开右键、换武器、上车就收起来
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Nade = {}

function Nade.init(G)
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local V, CF, RGB = Vector3.new, CFrame.new, Color3.fromRGB
  local W = G.Config.Weapons
  local N_DOT = 34

  local folder = Instance.new("Folder")
  folder.Name = "NadeArc"
  folder.Parent = workspace
  local function mk(shape, size, color, tr)
    local p = Instance.new("Part")
    p.Shape = shape
    p.Size = size
    p.Color = color
    p.Material = Enum.Material.Neon
    p.Transparency = tr
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    p.Parent = folder
    return p
  end
  local dots = {}
  for i = 1, N_DOT do
    local k = (i - 1) / (N_DOT - 1)
    dots[i] = mk(Enum.PartType.Ball, V(0.32, 0.32, 0.32), RGB(255, 255, 255):Lerp(RGB(255, 150, 60), k), 1)
  end
  local bounceRing = mk(Enum.PartType.Cylinder, V(0.15, 3, 3), RGB(255, 236, 200), 1)
  local boomRing = mk(Enum.PartType.Cylinder, V(0.15, 28, 28), RGB(255, 70, 50), 1)
  local boomCore = mk(Enum.PartType.Cylinder, V(0.16, 2.4, 2.4), RGB(255, 90, 60), 1)
  local bb = Instance.new("BillboardGui")
  bb.Size = UDim2.fromOffset(80, 22)
  bb.StudsOffsetWorldSpace = V(0, 3, 0)
  bb.AlwaysOnTop = true
  bb.Enabled = false
  bb.Adornee = boomCore
  bb.Parent = boomCore
  local fuseL = Instance.new("TextLabel")
  fuseL.Size = UDim2.fromScale(1, 1)
  fuseL.BackgroundTransparency = 1
  fuseL.Font = Enum.Font.GothamBold
  fuseL.TextSize = 15
  fuseL.TextColor3 = RGB(255, 120, 90)
  fuseL.TextStrokeTransparency = 0.4
  fuseL.Parent = bb

  local function hide()
    for _, d in ipairs(dots) do d.Transparency = 1 end
    bounceRing.Transparency, boomRing.Transparency, boomCore.Transparency = 1, 1, 1
    bb.Enabled = false
  end

  local rp = RaycastParams.new()
  rp.FilterType = Enum.RaycastFilterType.Exclude
  G.nadeArc = { on = false }   -- 测试用：on、bounce（第一次落地点）、boom（引信到点的位置）

  RunService.RenderStepped:Connect(function()
    local id, aiming = nil, false
    if G.curWeapon then id, aiming = G.curWeapon() end
    local w = id and W[id]
    local ch = me.Character
    local head = ch and ch:FindFirstChild("Head")
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local on = w ~= nil and w.kind == "throw" and aiming == true and head ~= nil and hum ~= nil and hum.Health > 0 and not G.drive
    G.nadeArc.on = on
    if not on then hide() return end
    -- 出手：跟服务器一样
    local aim = G.aimPoint and G.aimPoint(w.range or 90) or (cam.CFrame.Position + cam.CFrame.LookVector * 40)
    local m = head.Position + V(0, 0.5, 0)
    local flat = V(aim.X - m.X, 0, aim.Z - m.Z)
    local d = math.min(flat.Magnitude, w.range or 90)
    local dir = (flat.Magnitude > 0.1) and flat.Unit or V(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z).Unit
    local sp = math.clamp(math.sqrt(math.max(1, d) * workspace.Gravity * 0.55), 20, w.speed or 70)
    local vel = dir * sp * 0.7071 + V(0, sp * 0.7071, 0)
    local grav = V(0, -workspace.Gravity * 0.55, 0)
    rp.FilterDescendantsInstances = { ch, folder, G.fxFolder, G.viewFolder }
    local p = m
    local fuse = w.fuse or 2.8
    local dt = 1 / 30
    local steps = math.floor(fuse / dt + 0.5)
    local bounce, path = nil, {}
    for i = 1, steps do
      vel += grav * dt
      local step = vel * dt
      local res = workspace:Raycast(p, step, rp)
      if res then   -- 弹一下（照服务器）
        if not bounce then bounce = res.Position end
        p = res.Position + res.Normal * 0.6
        vel = (vel - 1.6 * vel:Dot(res.Normal) * res.Normal) * 0.35
      else
        p += step
      end
      path[i] = p
    end
    -- 小点：沿着路径均匀取
    for i, dpart in ipairs(dots) do
      local k = math.clamp(math.floor((i - 1) / (N_DOT - 1) * (#path - 1)) + 1, 1, #path)
      dpart.CFrame = CF(path[k])
      dpart.Transparency = 0.15 + 0.5 * (i / N_DOT)
    end
    local up = CFrame.Angles(0, 0, math.pi / 2)   -- 圆柱的轴转到竖直：平放在地上的圆片
    if bounce then
      bounceRing.CFrame = CF(bounce + V(0, 0.08, 0)) * up
      bounceRing.Transparency = 0.35
    else
      bounceRing.Transparency = 1
    end
    local last = path[#path] or m
    local r = (w.splash or 14) * 2
    boomRing.Size = V(0.15, r, r)
    boomRing.CFrame = CF(last + V(0, 0.1, 0)) * up
    boomRing.Transparency = 0.72
    boomCore.CFrame = CF(last + V(0, 0.12, 0)) * up
    boomCore.Transparency = 0.25
    fuseL.Text = string.format("%.1f s", fuse)
    bb.Enabled = true
    G.nadeArc.bounce, G.nadeArc.boom = bounce, last
  end)
end

return Nade
