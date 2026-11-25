-- Roblox全面大战场（客户端）——观战（用户 11-25「全部都做」⑮：战雷里被打掉以后能看队友）
--   机库（TechUI）开着的时候顶上一个「观战队友」：点了机库收起（TechUI 的 G.hangarSet 问 G.wtSpectating），镜头跟着一个
--   活着、有真人开的队友的车 / 飞机（← → 换人）；Esc 或「回机库」回去；自己出击了自动停。被打掉那一下的击杀镜头在 DeathFx.lua
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local WtCam = {}

function WtCam.init(G)
  local me = Players.LocalPlayer
  local RGB, UD2, V3 = Color3.fromRGB, UDim2.new, Vector3.new
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local BOLD = Enum.Font.GothamBold

  local gui = Instance.new("ScreenGui")
  gui.Name = "WtCam"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 15   -- 在机库（12）上面
  gui.Parent = me:WaitForChild("PlayerGui")
  local function btn(text, pos)
    local b = Instance.new("TextButton")
    b.Size, b.Position, b.AnchorPoint = UDim2.fromOffset(150, 30), pos, Vector2.new(0.5, 0)
    local TH = G.Theme   -- 统一外观：灰底白字、细边、2 像素圆角（docs/style.md）
    b.BackgroundColor3, b.BackgroundTransparency, b.BorderSizePixel = TH.C.RAISE, 0.1, 0
    b.Text, b.TextSize, b.Font, b.TextColor3 = text, TH.S.body, TH.F.bold, TH.C.TEXT
    TH.corner(b)
    TH.stroke(b)
    b.Visible = false
    b.Parent = gui
    return b
  end
  -- 「观战队友」放在机库右下角（原来在屏幕上方正中，压着机库、科技树的标题）
  local specBtn = btn(T("wt.spec"), UD2(1, -40, 1, -45))
  specBtn.AnchorPoint = Vector2.new(1, 1)
  specBtn.Size = UDim2.fromOffset(170, 36)
  specBtn.Name = "SpecBtn"
  local backBtn = btn(T("wt.specBack"), UD2(0.5, 0, 0, 92))
  backBtn.Name = "SpecBack"
  local info = Instance.new("TextLabel")
  info.BackgroundTransparency = 1
  info.Size, info.Position, info.AnchorPoint = UDim2.fromOffset(600, 24), UD2(0.5, 0, 0, 60), Vector2.new(0.5, 0)
  info.TextSize, info.Font, info.TextColor3 = 16, BOLD, G.Theme.C.TEXT
  info.TextStrokeTransparency = 0.35
  info.Visible = false
  info.Parent = gui

  local on, idx, camType0, smooth = false, 1, nil, nil
  G.wtSpectating = function() return on end
  local function mates()
    local side = me:GetAttribute("Side")
    local out = {}
    local ents = workspace:FindFirstChild("Ents")
    for _, em in ipairs(ents and ents:GetChildren() or {}) do
      local drv = em:GetAttribute("Driver")
      if em:GetAttribute("Team") == side and type(drv) == "number" and drv > 0 and drv ~= me.UserId and not em:GetAttribute("Wreck") then
        table.insert(out, em)
      end
    end
    table.sort(out, function(a, b) return (a:GetAttribute("EntId") or 0) < (b:GetAttribute("EntId") or 0) end)
    return out
  end
  local function stop()
    if not on then return end
    on = false
    local cam = workspace.CurrentCamera
    if cam and camType0 then pcall(function() cam.CameraType = camType0 end) end
    smooth = nil
    if G.hangarSet then pcall(G.hangarSet, true) end   -- 机库马上回来
  end
  local function start()
    if #mates() == 0 then
      if G.toast then G.toast(T("wt.specNone"), "info") end
      return
    end
    on, idx = true, 1
    local cam = workspace.CurrentCamera
    camType0 = cam.CameraType
    pcall(function() cam.CameraType = Enum.CameraType.Scriptable end)
    if G.hangarSet then pcall(G.hangarSet, false) end
  end
  specBtn.MouseButton1Click:Connect(start)
  backBtn.MouseButton1Click:Connect(stop)
  UIS.InputBegan:Connect(function(io, gp)
    if not on or gp then return end
    if io.KeyCode == Enum.KeyCode.Escape then stop()
    elseif io.KeyCode == Enum.KeyCode.Left then idx -= 1 smooth = nil
    elseif io.KeyCode == Enum.KeyCode.Right then idx += 1 smooth = nil end
  end)

  G.frameConn("WtCam", function(dt)
    local S = G.S
    local alive = S and S.alive
    local hangar = G.hangarActive and G.hangarActive() and not alive and S and (S.phase == "battle" or S.phase == "prep")
      and not (G.deathFxOn and G.deathFxOn())
    if on and (alive or not hangar) then stop() end
    specBtn.Visible = (hangar and not on) == true   -- 开局还没有 S 时 hangar 是 nil（给 Visible 赋 nil 会报错）
    backBtn.Visible = on
    info.Visible = on
    if not on then return end
    local list = mates()
    if #list == 0 then stop() return end
    idx = ((idx - 1) % #list) + 1
    local em = list[idx]
    local okP, cf = pcall(function() return em:GetPivot() end)
    if not okP then return end
    local p = cf.Position
    local flat = V3(cf.LookVector.X, 0, cf.LookVector.Z)
    flat = (flat.Magnitude > 0.05) and flat.Unit or V3(0, 0, -1)
    local air = em:GetAttribute("Kind") == "air"
    local want = p - flat * (air and 70 or 34) + V3(0, air and 18 or 12, 0)
    smooth = smooth and smooth:Lerp(want, math.min(1, dt * 4)) or want
    workspace.CurrentCamera.CFrame = CFrame.lookAt(smooth, p + V3(0, 3, 0))
    local pl = Players:GetPlayerByUserId(em:GetAttribute("Driver"))
    local tk = em:GetAttribute("TreeKey")
    local vn = tk and T("tree." .. tk) or T("veh." .. tostring(em:GetAttribute("Model") or ""))
    info.Text = T("wt.specOn", ((pl and pl.DisplayName) or "?") .. " · " .. vn)
  end)
end

return WtCam
