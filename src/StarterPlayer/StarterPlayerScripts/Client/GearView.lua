-- Roblox全面大战场（客户端）——装备的 3D 小图（部署界面的装备格、右边的大图）
--   有真模型就用：手持装备是 Sketchfab 原模型（导入的或现生成的，Optics.lua），M4 是第一人称那支（FPSView）；
--   没有就用服务器放在 ReplicatedStorage.ToolPreview 里的工具样子（零件拼的，导入了原模型的工具上也是原模型）
--   G.gearModel(武器, 阵营) → Model（器材坐标：+Z 朝前、+Y 朝上），真模型还在生成中（过一会儿再要一次），是不是真模型
--   G.viewFit(ViewportFrame, Model, 留边, 视线方向) 把模型放进视口，相机（默认从右前方略俯视）按投影后的大小正好装下
local RS = game:GetService("ReplicatedStorage")

local GearView = {}

function GearView.init(G)
  local GD = require(RS:WaitForChild("GearDefs"))
  local CF, V = CFrame.new, Vector3.new
  local FLIP = CFrame.Angles(0, math.pi, 0)   -- 工具的枪口朝 −Z → 器材坐标 +Z

  local function realModel(id, team)
    local key = GD.key(id, team)
    local M = key and G.opticMeta and G.opticMeta[key]
    if not M or not G.opticParts then return nil, false end
    local mk = GD.MOUNT[key]
    if mk and not G.opticMeta[mk.key] then mk = nil end
    local op = G.opticParts(key)
    local mp = mk and G.opticParts(mk.key)
    if op and (not mk or mp) then
      local m = Instance.new("Model")
      for _, x in ipairs(op) do
        x.part.CFrame = x.cf
        x.part.Parent = m
      end
      if mp then
        local at = GD.mountAt(key, M)
        for _, x in ipairs(mp) do
          x.part.CFrame = at * x.cf
          x.part.Parent = m
        end
      end
      return m, false
    end
    local failed = G.opticFailed and (G.opticFailed(key) or (mk and G.opticFailed(mk.key)))
    return nil, not failed
  end

  local function toolModel(id, team)
    local tp = RS:FindFirstChild("ToolPreview")
    tp = tp and (tp:FindFirstChild(team or "def") or tp:FindFirstChild("def"))
    local t = tp and tp:FindFirstChild(id)
    local h = t and t:FindFirstChild("Handle")
    if not h then return nil end
    local m = Instance.new("Model")
    for _, d in ipairs(t:GetDescendants()) do
      if d:IsA("BasePart") and d ~= h and d.Transparency < 1 then
        local q = d:Clone()
        for _, c in ipairs(q:GetChildren()) do
          if not c:IsA("SurfaceAppearance") then c:Destroy() end
        end
        q.Anchored, q.CanCollide, q.CanQuery, q.CanTouch = true, false, false, false
        q.CFrame = FLIP * h.CFrame:ToObjectSpace(d.CFrame)
        q.Parent = m
      end
    end
    return m
  end

  function G.gearModel(id, team)
    local m, wait = realModel(id, team)
    if m then return m, false, true end
    if id == "m4" and G.m4Model then
      local mm = G.m4Model()
      if mm then return mm, false, true end
      wait = true
    end
    -- 工具上导入了原模型的（MeshPart）也算真的
    local tm = toolModel(id, team)
    local real = false
    if tm then
      for _, p in ipairs(tm:GetChildren()) do if p:IsA("MeshPart") then real = true end end
    end
    return tm, wait, real
  end

  -- 相机：从器材的右边、略靠前、略高处看过去（枪口朝屏幕右边）
  local LOOK = V(1, -0.2, -0.16).Unit
  function G.viewFit(vp, model, pad, look)
    for _, c in ipairs(vp:GetChildren()) do
      if c:IsA("Model") or c:IsA("Camera") or c:IsA("WorldModel") or c:IsA("BasePart") then c:Destroy() end
    end
    local cam = Instance.new("Camera")
    cam.FieldOfView = 24
    cam.Parent = vp
    vp.CurrentCamera = cam
    if not model then return end
    model.Parent = vp
    local R = CFrame.lookAt(V(), look or LOOK)
    local mn, mx = V(1e9, 1e9, 1e9), V(-1e9, -1e9, -1e9)
    for _, p in ipairs(model:GetDescendants()) do
      if p:IsA("BasePart") then
        local h = p.Size / 2
        for sx = -1, 1, 2 do
          for sy = -1, 1, 2 do
            for sz = -1, 1, 2 do
              local w = p.CFrame * V(sx * h.X, sy * h.Y, sz * h.Z)
              local l = R:PointToObjectSpace(w)
              mn = V(math.min(mn.X, l.X), math.min(mn.Y, l.Y), math.min(mn.Z, l.Z))
              mx = V(math.max(mx.X, l.X), math.max(mx.Y, l.Y), math.max(mx.Z, l.Z))
            end
          end
        end
      end
    end
    if mn.X > mx.X then return end
    local okA, abs = pcall(function() return vp.AbsoluteSize end)
    local aspect = (okA and abs and abs.X > 4 and abs.Y > 4) and (abs.X / abs.Y) or (16 / 9)
    local tv = math.tan(math.rad(cam.FieldOfView) / 2)
    local w, h = mx.X - mn.X, mx.Y - mn.Y
    local dist = math.max((w / 2) / (tv * aspect), (h / 2) / tv) * (pad or 1.12) + (mx.Z - mn.Z) / 2
    local c = (mn + mx) / 2
    cam.CFrame = R * CF(c.X, c.Y, c.Z + dist)
    -- 转的时候绕模型中心：中心记在属性 C 里，模型的轴心挪到那儿（零件的位置不动）
    local center = R * c
    pcall(function()
      model.WorldPivot = CF(center)
      model:SetAttribute("C", center)
    end)
  end
end

return GearView
