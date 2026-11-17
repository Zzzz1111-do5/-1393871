-- Roblox全面大战场——降落伞（客户端）：跳伞的人（服务器给角色设属性 Chute = true：飞机弹射、直升机上跳下去、伞降出生点），
--   头顶张开一顶圆伞（用户：跳伞没有降落伞）——10 片伞衣两种颜色相间、顶上一圈顶孔、六根伞绳连到肩上；开伞 0.6 秒从小到大张开，空中轻轻摆，
--   落地（Chute 变回 false）收掉。别人的伞也画（每个客户端看所有玩家的角色属性）；零件不碰撞、不挡射线，每帧一次 BulkMoveTo
local Players = game:GetService("Players")

local Chute = {}

function Chute.init(G)
  local RGB, V, CF = Color3.fromRGB, Vector3.new, CFrame.new
  local R = 11       -- 伞衣半径（格）：圆伞展开直径约 8 米
  local HC = 4.2     -- 伞衣顶比边缘高多少
  local UP = 15      -- 伞衣边缘比人的身体中心高多少
  local N = 10       -- 伞衣片数
  local OPEN = 0.6   -- 开伞要几秒
  local live = {}    -- [角色] = { parts, rels（伞衣坐标里的样子）, lines, t0 }

  local function mk(cls, size, color, mat)
    local p = Instance.new(cls)
    p.Size = size
    p.Color = color
    p.Material = mat or Enum.Material.Fabric
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    return p
  end

  -- 一个三角形（a、b、c，伞衣坐标）用两块楔块拼：返回 { 零件, 相对 CFrame } ×2（同 AirModels 拼机翼的做法）
  local function tri(list, a, b, c, th, color)
    local ab, ac, bc = b - a, c - a, c - b
    local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
    if abd > acd and abd > bcd then c, a = a, c
    elseif acd > bcd and acd > abd then a, b = b, a end
    ab, ac, bc = b - a, c - a, c - b
    local right = ac:Cross(ab)
    if right.Magnitude < 1e-6 or bc.Magnitude < 1e-6 then return end
    right = right.Unit
    local up = bc:Cross(right).Unit
    local back = bc.Unit
    local height = math.abs(ab:Dot(up))
    local l0, l1 = math.abs(ab:Dot(back)), math.abs(ac:Dot(back))
    if height < 0.05 then return end
    if l0 > 0.05 then table.insert(list, { mk("WedgePart", V(th, height, l0), color), CFrame.fromMatrix((a + b) / 2, right, up, back) }) end
    if l1 > 0.05 then table.insert(list, { mk("WedgePart", V(th, height, l1), color), CFrame.fromMatrix((a + c) / 2, -right, up, -back) }) end
  end

  local function build(ch, side)
    local c1 = (side == "def") and RGB(186, 168, 126) or RGB(98, 116, 76)    -- 美军沙色、解放军橄榄绿
    local c2 = c1:Lerp(Color3.new(1, 1, 1), 0.18)
    local list = {}
    local rim = {}
    for i = 0, N - 1 do
      local a = i / N * math.pi * 2
      rim[i] = V(math.cos(a) * R, 0, math.sin(a) * R)
    end
    local mid = {}
    for i = 0, N - 1 do   -- 伞衣中间一圈：往里收、往上鼓（伞衣是圆顶，不是尖锥）
      local a = (i + 0.5) / N * math.pi * 2
      mid[i] = V(math.cos(a) * R * 0.62, HC * 0.78, math.sin(a) * R * 0.62)
    end
    local top = V(0, HC, 0)
    for i = 0, N - 1 do
      local j = (i + 1) % N
      local col = (i % 2 == 0) and c1 or c2
      tri(list, rim[i], rim[j], mid[i], 0.12, col)
      tri(list, rim[j], mid[j], mid[i], 0.12, col)
      tri(list, mid[i], mid[j], top, 0.12, col)
    end
    local vent = mk("Part", V(0.15, R * 0.28, R * 0.28), RGB(222, 222, 214))   -- 顶孔一圈浅色
    vent.Shape = Enum.PartType.Cylinder
    table.insert(list, { vent, CF(0, HC + 0.05, 0) * CFrame.Angles(0, 0, math.pi / 2) })
    local lines = {}
    for k = 0, 5 do
      local p = mk("Part", V(0.08, 0.08, 1), RGB(200, 200, 190), Enum.Material.SmoothPlastic)
      p.CastShadow = false
      lines[k + 1] = { p = p, rim = rim[math.floor(k * N / 6)] }
    end
    local model = Instance.new("Model")
    model.Name = "Parachute"
    for _, x in ipairs(list) do x[1].Parent = model end
    for _, l in ipairs(lines) do l.p.Parent = model end
    model.Parent = workspace
    return { model = model, list = list, lines = lines, t0 = os.clock(), side = side }
  end

  local function remove(ch)
    local L = live[ch]
    if L then
      L.model:Destroy()
      live[ch] = nil
    end
  end

  local plist, clist = {}, {}
  function G.stepChute(dt)
    local now = os.clock()
    local seen = {}
    for _, pl in ipairs(Players:GetPlayers()) do
      local ch = pl.Character
      if ch and ch:GetAttribute("Chute") == true then
        local hrp = ch:FindFirstChild("HumanoidRootPart")
        if hrp then
          seen[ch] = true
          local L = live[ch]
          if not L then
            L = build(ch, pl:GetAttribute("Side"))
            live[ch] = L
          end
          -- 开伞：0.6 秒从收着（贴着背）张开；张开以后轻轻摆
          local k = math.clamp((now - L.t0) / OPEN, 0, 1)
          local e = 1 - (1 - k) * (1 - k)
          local s = 0.12 + 0.88 * e
          local look = hrp.CFrame.LookVector
          local yaw = math.atan2(-look.X, -look.Z)
          local t = now - L.t0
          local base = CF(hrp.Position + V(0, 1.5 + UP * e, 0)) * CFrame.Angles(0, yaw, 0)
            * CFrame.Angles(math.sin(t * 0.9) * 0.07 * e, 0, math.cos(t * 0.7) * 0.06 * e)
          for _, x in ipairs(L.list) do
            local rel = x[2]
            plist[#plist + 1] = x[1]
            clist[#clist + 1] = base * (CF(rel.Position * s) * (rel - rel.Position))
          end
          -- 伞绳：伞衣边缘 → 肩上
          local sh = hrp.CFrame * CF(0, 1.3, 0)
          for i, l in ipairs(L.lines) do
            local a = (base * CF(l.rim * s)).Position
            local b = (sh * CF((i % 2 == 0) and 0.7 or -0.7, 0, 0)).Position
            local len = (b - a).Magnitude
            if math.abs(l.p.Size.Z - len) > 0.05 then l.p.Size = V(0.08, 0.08, math.max(0.1, len)) end
            plist[#plist + 1] = l.p
            clist[#clist + 1] = CFrame.lookAt((a + b) / 2, b)
          end
        end
      end
    end
    for ch in pairs(live) do
      if not seen[ch] then remove(ch) end
    end
    if #plist > 0 then
      workspace:BulkMoveTo(plist, clist, Enum.BulkMoveMode.FireCFrameChanged)
      table.clear(plist)
      table.clear(clist)
    end
  end
  G.chuteCount = function()
    local n = 0
    for _ in pairs(live) do n += 1 end
    return n
  end
end

return Chute
