-- 全面大战场（客户端）——坐在别人开的地面车后面当乘客（用户 11-24：「运载车步战车要真的能载人」）
--   服务器（Armor.lua）：有人开（或者 AI 开着）的步战车、运兵车、悍马还有座位，走过去按 E 就坐后面（车的座位 seats 连司机算）；
--     人藏进车里跟着车走，不能开枪；车被打爆乘客一起阵亡；F / E / 空格下车，从车尾（步战车、运兵车的后门）下去
--   这里：G.S.veh.pass 时接管镜头——绕着车转的弹簧臂（同开车，VehCam），鼠标转、滚轮远近；屏幕下面写着第几座、谁在开、怎么下车；
--     手机右边一个「下车」按钮。下车 / 车没了把镜头还给步兵
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local Ride = {}

function Ride.init(G)
  local V, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local function T(k, ...) return G.T and G.T(k, ...) or k end

  local gui = Instance.new("ScreenGui")
  gui.Name = "Ride"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")
  local hint = Instance.new("TextLabel")
  hint.AnchorPoint = Vector2.new(0.5, 1)
  hint.Position = UDim2.new(0.5, 0, 1, -28)
  hint.Size = UDim2.fromOffset(720, 30)
  hint.BackgroundColor3 = Color3.fromRGB(10, 12, 10)
  hint.BackgroundTransparency = 0.35
  hint.BorderSizePixel = 0
  hint.TextColor3 = Color3.fromRGB(220, 236, 220)
  hint.Font = Enum.Font.BuilderSansMedium
  hint.TextSize = 15
  hint.Parent = gui
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 6)
  corner.Parent = hint
  local btn = Instance.new("TextButton")   -- 手机：下车
  btn.AnchorPoint = Vector2.new(1, 1)
  btn.Position = UDim2.new(1, -24, 1, -90)
  btn.Size = UDim2.fromOffset(110, 52)
  btn.BackgroundColor3 = Color3.fromRGB(20, 26, 20)
  btn.BackgroundTransparency = 0.25
  btn.TextColor3 = Color3.fromRGB(230, 240, 230)
  btn.Font = Enum.Font.BuilderSansBold
  btn.TextSize = 18
  btn.Visible = false
  btn.Parent = gui
  local bc = corner:Clone()
  bc.Parent = btn

  local riding = nil   -- { id, yaw, pitch, dist }
  local function getOut() G.R.Drive:FireServer({ op = "exit" }) end
  btn.Activated:Connect(getOut)

  local function stop()
    if not riding then return end
    riding = nil
    gui.Enabled = false
    if G.vehCamReset then G.vehCamReset("ride") end
    cam.CameraType = Enum.CameraType.Custom
    cam.FieldOfView = 70
    local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
    if hum then cam.CameraSubject = hum end
    if UIS.MouseBehavior == Enum.MouseBehavior.LockCenter then UIS.MouseBehavior = Enum.MouseBehavior.Default end
    G.riding = nil
  end

  UIS.InputBegan:Connect(function(io, gp)
    if gp or not riding then return end
    local k = io.KeyCode
    if k == Enum.KeyCode.F or k == Enum.KeyCode.E or k == Enum.KeyCode.Space then getOut() end
  end)
  UIS.InputChanged:Connect(function(io, gp)
    if gp or not riding then return end
    if io.UserInputType == Enum.UserInputType.MouseWheel then
      riding.dist = math.clamp(riding.dist - io.Position.Z * 3, 10, 48)
    end
  end)

  local lastPos = nil
  function G.stepRide(dt)
    local S = G.S
    local vs = S and S.alive and S.veh or nil
    if not (vs and vs.pass and not vs.air and not vs.ship and not vs.fort) then
      stop()
      return
    end
    local v = G.viewById and G.viewById(vs.id)
    if not v or not v.cf then return end
    if not riding or riding.id ~= vs.id then
      local _, yaw = v.cf:ToEulerAnglesYXZ()
      riding = { id = vs.id, yaw = yaw, pitch = -0.28, dist = math.max(18, (v.def and v.def.L or 18) * 1.25) }
      lastPos = nil
      G.riding = riding
    end
    gui.Enabled = true
    btn.Visible = UIS.TouchEnabled
    btn.Text = T("ride.exitBtn")
    hint.Text = T("ride.hint", (vs.np or 1), (vs.seats or 1), tostring(vs.drv or "—"))
    -- 镜头：绕着车转（鼠标 / 手机滑动），弹簧臂跟着车
    if not UIS.TouchEnabled then UIS.MouseBehavior = Enum.MouseBehavior.LockCenter end
    local md = UIS:GetMouseDelta()
    riding.yaw -= md.X * 0.0045
    riding.pitch = math.clamp(riding.pitch - md.Y * 0.0045, -1.1, 0.35)
    local d = v.def
    local pivot = v.cf.Position + V(0, (d and d.H or 6) * 0.55, 0)
    local vel = lastPos and (pivot - lastPos) / math.max(dt, 1e-3) or V()
    lastPos = pivot
    cam.CameraType = Enum.CameraType.Scriptable
    local dir = ANG(0, riding.yaw, 0) * ANG(riding.pitch, 0, 0)
    if G.vehCam then
      local cf, jit, fov = G.vehCam({ key = "ride", pivot = pivot, dir = dir, dist = riding.dist, up = 2, vel = vel, dt = dt, fov0 = 70, fovK = 5 })
      cam.CFrame = cf * (jit or CF())
      cam.FieldOfView = fov or 70
    else
      cam.CFrame = CF(pivot) * dir * CF(0, 2, riding.dist)
    end
  end
  G.rideStop = stop   -- 测试用
end

return Ride
