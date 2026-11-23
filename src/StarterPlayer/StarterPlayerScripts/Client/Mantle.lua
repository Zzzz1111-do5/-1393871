-- 全面大战场（客户端）——翻越 / 攀爬（用户 11-23「这个游戏按你想的来弄」：沙袋、矮墙、栏杆、窗台、集装箱边不该把人挡死，跟战地一样按空格翻过去）
--   步行时按空格：前面 3 格以内有挡着的东西（墙面），它的顶面比脚高 0.4～2.7 米、顶上有站人的空间，就不跳了改成翻：
--   · 矮的、薄的（沙袋、矮墙、栏杆：顶面往前 2.4 格又掉下去了）：一撑就翻到另一边（约 0.4 秒）；
--   · 高的、厚的（台子、集装箱、窗台）：先往上撑、再往前爬上去（0.45～0.7 秒，越高越慢）
--   动作用速度推（每帧把根零件的速度设成「这一帧该走到哪」）：角色是自己的客户端在算物理，速度这样推别人那边看着也是顺的；
--   最后差一点就直接摆到终点。翻的时候枪往下收（FPSView 看 G.mantling，同疾跑的姿势），起手、落地镜头各晃一下
local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Mantle = {}

function Mantle.init(G)
  local player = Players.LocalPlayer
  local V = Vector3.new
  local busy = nil
  G.mantling = false
  G.mantleState = function() return busy end   -- 测试用
  local MIN_H, MAX_H = 1.1, 7.6   -- 顶面比脚高多少格能翻（约 0.4～2.7 米）
  -- Humanoid 的 Jump / Sit：Lune 测试台的 Humanoid 读不到（没有默认值会报错）——包一层
  local function getP(o, k)
    local ok, v = pcall(function() return o[k] end)
    return ok and v or nil
  end
  local function setJump(hum, v) pcall(function() hum.Jump = v end) end

  local function flat(v)
    local f = V(v.X, 0, v.Z)
    return f.Magnitude > 0.01 and f.Unit or nil
  end

  -- 看前面能不能翻：返回这次翻越的路径
  local function probe()
    local ch = player.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp or hum.Health <= 0 or busy then return nil end
    if G.drive or G.fly or G.downed or getP(hum, "Sit") == true or hrp.Anchored or ch:GetAttribute("Downed") then return nil end
    local dir = flat(hum.MoveDirection) or flat(hrp.CFrame.LookVector)
    if not dir then return nil end
    local feet = hrp.Position.Y - hum.HipHeight - hrp.Size.Y / 2
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.FilterDescendantsInstances = { ch }
    -- ① 前面有墙面（膝盖、腰、胸三个高度打线）
    local wall = nil
    for _, hgt in ipairs({ 0.9, 2.0, 3.2, 4.6 }) do
      local o = V(hrp.Position.X, feet + hgt, hrp.Position.Z)
      local r = workspace:Raycast(o, dir * 3.2, rp)
      if r and r.Normal.Y < 0.5 then wall = r break end
    end
    if not wall then return nil end
    -- ② 墙面后面一点的顶面（从上往下打）
    local over = wall.Position + dir * 1.0
    local top = workspace:Raycast(V(over.X, feet + MAX_H + 1.5, over.Z), V(0, -(MAX_H + 1.5) + 0.4, 0), rp)
    if not top or top.Normal.Y < 0.7 then return nil end
    local h = top.Position.Y - feet
    if h < MIN_H or h > MAX_H then return nil end
    -- ③ 顶上有站人的空间；从头顶到顶面上方的路上没有天花板
    if workspace:Raycast(top.Position + V(0, 0.2, 0), V(0, 5.2, 0), rp) then return nil end
    local headY = feet + 5.2
    local reach = math.max(headY, top.Position.Y + 5)
    if workspace:Raycast(V(hrp.Position.X, headY, hrp.Position.Z), V(0, reach - headY + 0.5, 0), rp) then return nil end
    -- ④ 薄的、矮的：往前 2.4 格又掉下去了 → 翻到另一边落地；不然爬上顶面
    local far = top.Position + dir * 2.4
    local beyond = workspace:Raycast(V(far.X, top.Position.Y + 2, far.Z), V(0, -3.0, 0), rp)
    local thin = (beyond == nil or beyond.Position.Y < top.Position.Y - 0.9) and h < 4.6
    local hipOff = hum.HipHeight + hrp.Size.Y / 2
    local land
    if thin then
      local lx = top.Position + dir * 3.4
      local g = workspace:Raycast(V(lx.X, top.Position.Y + 2, lx.Z), V(0, -(h + 6), 0), rp)
      if not g or g.Normal.Y < 0.6 then return nil end
      if workspace:Raycast(g.Position + V(0, 0.2, 0), V(0, 5, 0), rp) then return nil end
      land = g.Position + V(0, hipOff, 0)
    else
      land = top.Position + dir * 1.3 + V(0, hipOff, 0)
    end
    local start = hrp.Position
    local apex = V(top.Position.X, top.Position.Y + hipOff + (thin and 0.5 or 0.25), top.Position.Z) - dir * (thin and 0.1 or 0.6)
    local dur = thin and 0.42 or math.clamp(0.38 + 0.045 * h, 0.45, 0.72)
    return { hum = hum, hrp = hrp, dir = dir, h = h, thin = thin, p0 = start, p1 = apex, p2 = land, dur = dur, t0 = os.clock() }
  end

  -- 路径：先往上（贝塞尔的控制点在起点正上方），再往前落下
  local function at(M, u)
    u = math.clamp(u, 0, 1)
    local up = V(M.p0.X, M.p1.Y + 0.4, M.p0.Z)
    if u < 0.55 then
      local s = u / 0.55
      local a = M.p0:Lerp(up, s)
      local b = up:Lerp(M.p1, s)
      return a:Lerp(b, s)
    end
    local s = (u - 0.55) / 0.45
    s = s * s * (3 - 2 * s)
    return M.p1:Lerp(M.p2, s)
  end

  local function finish(M, ok)
    busy = nil
    G.mantling = false
    local hrp = M.hrp
    if ok and hrp and hrp.Parent then
      if (hrp.Position - M.p2).Magnitude < 4 then hrp.CFrame = CFrame.lookAt(M.p2, M.p2 + M.dir) end   -- 差一点：直接摆到终点
      hrp.AssemblyLinearVelocity = M.dir * (M.thin and 12 or 6)
      if G.shake then G.shake(M.thin and 0.08 or 0.12) end
    end
    if M.hum and M.hum.Parent then pcall(function() M.hum.AutoRotate = true end) end
  end

  local function start(M)
    busy = M
    G.mantling = true
    pcall(function() M.hum.AutoRotate = false end)
    setJump(M.hum, false)
    if G.shake then G.shake(0.06) end
    if G.sfx then G.sfx("thud", nil, { vol = 0.35, speed = 1.3 }) end
  end
  G.tryMantle = function()
    local M = probe()
    if not M then return false end
    start(M)
    return true
  end

  UIS.InputBegan:Connect(function(io, gp)
    if gp then return end
    if io.KeyCode == Enum.KeyCode.Space or io.KeyCode == Enum.KeyCode.ButtonA then G.tryMantle() end
  end)
  -- 手机：跳跃按钮按下时也看一下（Humanoid.Jump 变成 true）
  local lastJump = false
  RunService.Heartbeat:Connect(function()
    local M = busy
    if not M then
      local ch = player.Character
      local hum = ch and ch:FindFirstChildOfClass("Humanoid")
      local j = hum ~= nil and getP(hum, "Jump") == true
      if j and not lastJump and UIS.TouchEnabled then G.tryMantle() end
      lastJump = j
      return
    end
    local hrp, hum = M.hrp, M.hum
    if not hrp.Parent or not hum.Parent or hum.Health <= 0 or G.downed then finish(M, false) return end
    local u = (os.clock() - M.t0) / M.dur
    if u >= 1 then finish(M, true) return end
    setJump(hum, false)
    local want = at(M, u + 1 / 60 / M.dur)
    local v = (want - hrp.Position) * 60
    if v.Magnitude > 70 then v = v.Unit * 70 end
    hrp.AssemblyLinearVelocity = v
    hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + M.dir)
  end)
end

return Mantle
