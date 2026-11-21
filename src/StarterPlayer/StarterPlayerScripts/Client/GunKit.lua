-- 全面大战场（客户端）——改枪的配件（用户 11-20：做一整套改枪系统，对标三角洲行动；数据和算法在 ReplicatedStorage.GunMods）
--   G.myW(武器)：自己这把枪装了配件以后的武器表（GunMods.apply）——按背包 / 手里那件工具的 Build 属性（服务器发枪时写的），
--     还没出击（部署界面里）按玩家属性 Gun_<枪>（下次出击装的）；init.client.lua 的 G.W 就是它，Play、Hud、FPSView、Scope 都按它
--   第三人称：别人手里（和自己第三人称时）的枪按工具的 Build 属性装上配件模型（工具上零件拼的 M4 比真枪大一倍，配件按各位的倍数放大，
--     GunMods.TP）；PEQ-15 激光：一道细光从激光器沿枪口方向打出去、打到的地方一个亮点（别人看得见：会暴露位置），手电点一盏聚光灯
--   出击后把背包里的枪要用的配件模型先在后台生成好（第一次切枪、开镜不卡那一下）
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local GunKit = {}

function GunKit.init(G)
  local GM = require(RS:WaitForChild("GunMods"))
  local W0 = G.Config.Weapons
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local V, CF, RGB = Vector3.new, CFrame.new, Color3.fromRGB
  local FLIP = CFrame.Angles(0, math.pi, 0)   -- 器材坐标 +Z 朝前 → 工具 −Z 朝前
  local now = os.clock

  ---------------------------------------------------------------- 自己的武器表

  local myTool, missT = {}, {}   -- [枪] = 背包 / 手里的那件工具；没找到的隔一会儿再找
  local cache = {}               -- [枪] = { code, w }
  local function findTool(id)
    local t = myTool[id]
    if t and t.Parent and (t.Parent == me.Character or t.Parent.ClassName == "Backpack") then return t end
    if t == false and now() - (missT[id] or 0) < 0.5 then return nil end
    t = nil
    for _, holder in ipairs({ me.Character, me:FindFirstChildOfClass("Backpack") }) do
      if holder and not t then
        for _, c in ipairs(holder:GetChildren()) do
          if c:IsA("Tool") and c:GetAttribute("Weapon") == id then t = c break end
        end
      end
    end
    myTool[id] = t or false
    if not t then missT[id] = now() end
    return t
  end

  function G.myW(id)
    local base = W0[id]
    if not base or not GM.has(id) then return base end
    local t = findTool(id)
    local code = (t and t:GetAttribute("Build")) or me:GetAttribute("Gun_" .. id) or ""
    local c = cache[id]
    if c and c.code == code then return c.w end
    local w = GM.apply(id, base, GM.decode(code))
    cache[id] = { code = code, w = w }
    return w
  end
  -- 任意一套配件的武器表（改枪界面预览、部署界面的数据条）
  function G.gunW(id, b) return GM.apply(id, W0[id], b) end
  -- 下次出击装的（玩家属性；服务器读档、改枪以后写）
  function G.myBuild(id)
    return GM.clean(id, GM.decode(me:GetAttribute("Gun_" .. id) or ""))
  end

  ---------------------------------------------------------------- 第三人称：枪上装配件

  local done = setmetatable({}, { __mode = "k" })    -- [工具] = true（装过了 / 不用装）
  local tries = setmetatable({}, { __mode = "k" })   -- [工具] = 等模型等了几次
  local lasers = setmetatable({}, { __mode = "k" })  -- [工具] = { h 把手, off 出光口（把手坐标） }
  local lights = setmetatable({}, { __mode = "k" })  -- [工具] = SpotLight

  local function weldTo(h, p, c0)
    p.Anchored, p.Massless, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, true, false, false, false, false
    p.CFrame = h.CFrame * c0
    local wd = Instance.new("Weld")
    wd.Part0, wd.Part1, wd.C0 = h, p, c0
    wd.Parent = p
  end

  -- 装上：模型还在现生成时返回 false（过一会儿再来）
  local function attach(tool)
    local id = tool:GetAttribute("Weapon")
    local code = tool:GetAttribute("Build")
    local TP = id and GM.TP[id]
    local h = tool:FindFirstChild("Handle")
    if not TP or type(code) ~= "string" or code == "" or not h then return true end
    local b = GM.clean(id, GM.decode(code))
    -- 先看模型都好了没有（一件一件现生成；没好的这次先不装，免得装一半）
    local need = {}
    for _, slot in ipairs(GM.SLOTS) do
      local it = b[slot] and GM.ITEM[b[slot]]
      if it and it.model and TP[slot] and not (slot == "optic" and b.optic == "acog") then
        if not (G.opticReady and G.opticReady(it.model)) then
          if G.opticFailed and G.opticFailed(it.model) then
            -- 生成不了（没开 Mesh / Image API）：这件就不装了
          else
            table.insert(need, it.model)
          end
        end
      end
    end
    if #need > 0 then
      for _, k in ipairs(need) do if G.opticParts then G.opticParts(k) end end   -- 开始生成
      return false
    end
    for _, slot in ipairs(GM.SLOTS) do
      local it = b[slot] and GM.ITEM[b[slot]]
      local m = TP[slot]
      if it and it.model and m and not (slot == "optic" and b.optic == "acog") then   -- ACOG：服务器发的工具上本来就有
        local op = G.opticParts and G.opticParts(it.model)
        local M = G.opticMeta and G.opticMeta[it.model]
        if op then
          local s = m[4]
          local base = CF(m[1], m[2], m[3])
          if slot == "tac" then base = base * CFrame.Angles(0, 0, math.pi / 2) end   -- 左侧导轨：底面朝左
          if slot == "optic" and it.riser then   -- 迷你红点的增高座
            local rp = Instance.new("Part")
            rp.Size, rp.Color, rp.Material = V(0.058, it.riser, 0.1) * s, RGB(34, 34, 36), Enum.Material.Metal
            weldTo(h, rp, base * CF(0, it.riser * s / 2, 0))
            rp.Parent = tool
            base = base * CF(0, it.riser * s, 0)
          end
          base = base * FLIP
          for _, x in ipairs(op) do
            local p = x.part
            local c = x.cf.Position
            p.Size = p.Size * s
            local gt = GM.glassT(it.model, x.name)
            if gt then p.Transparency = gt end
            weldTo(h, p, base * CF(c * s) * (x.cf - c))
            p.Parent = tool
          end
          if slot == "tac" and M then   -- 出光口 / 灯头：器材坐标里前端面中心
            local sz = M.size or { 0.2, 0.12, 0.38 }
            local front = (base * CF(0, sz[2] / 2 * s, sz[3] / 2 * s)).Position
            if it.laser then lasers[tool] = { h = h, off = CF(front) } end
            if it.light then
              local lp = Instance.new("Part")
              lp.Size, lp.Transparency = V(0.1, 0.1, 0.1), 1
              weldTo(h, lp, CF(front))   -- 朝向和把手一样：Front（−Z）就是枪口方向
              lp.Parent = tool
              local sl = Instance.new("SpotLight")
              sl.Brightness, sl.Range, sl.Angle, sl.Face, sl.Shadows = 3, 70, 36, Enum.NormalId.Front, false
              sl.Color = RGB(255, 246, 228)
              sl.Parent = lp
              lights[tool] = sl
            end
          end
        end
      end
    end
    return true
  end

  -- 场上谁手里拿着带配件的枪：隔一会儿看一遍（装过的不再装）
  local function scan()
    for _, pl in ipairs(Players:GetPlayers()) do
      local ch = pl.Character
      local t = ch and ch:FindFirstChildOfClass("Tool")
      if t and not done[t] then
        local ok, res = pcall(attach, t)
        if not ok then
          done[t] = true
          warn("[全面大战场] 枪上装配件出错：" .. tostring(res))
        elseif res then
          done[t] = true
        else
          tries[t] = (tries[t] or 0) + 1
          if tries[t] > 60 then done[t] = true end   -- 等了半分钟还没好：不装了
        end
      end
    end
  end

  ---------------------------------------------------------------- 激光（第三人称：别人的、自己第三人称时的）

  local folder = Instance.new("Folder")
  folder.Name = "GunKitFx"
  folder.Parent = workspace
  local pool = {}
  local function beamPart(i)
    local b = pool[i]
    if b then return b end
    local beam = Instance.new("Part")
    beam.Anchored, beam.CanCollide, beam.CanQuery, beam.CanTouch, beam.CastShadow = true, false, false, false, false
    beam.Material, beam.Color, beam.Transparency = Enum.Material.Neon, RGB(255, 40, 30), 0.35
    beam.Size = V(0.03, 0.03, 1)
    beam.Parent = folder
    local dot = beam:Clone()
    dot.Shape = Enum.PartType.Ball
    dot.Size = V(0.35, 0.35, 0.35)
    dot.Transparency = 0.1
    dot.Parent = folder
    b = { beam = beam, dot = dot }
    pool[i] = b
    return b
  end
  local rp = RaycastParams.new()
  rp.FilterType = Enum.RaycastFilterType.Exclude
  local MAXL, MAXD = 6, 320   -- 最多画几道、离镜头多远以内

  local scanT = 0
  G.frameConn("GunKit", function()
    local t = now()
    if t - scanT > 0.5 then
      scanT = t
      scan()
    end
    local cp = cam.CFrame.Position
    local list = {}
    for tool, L in pairs(lasers) do
      local ch = tool.Parent
      if ch and ch:IsA("Model") and ch:FindFirstChildOfClass("Humanoid") and L.h.Parent == tool then
        local mine = ch == me.Character
        if not (mine and G.fps) then   -- 自己第一人称时 FPSView 画
          local o = (L.h.CFrame * L.off).Position
          local d = (o - cp).Magnitude
          if d < MAXD then table.insert(list, { o = o, dir = L.h.CFrame.LookVector, d = d, ch = ch }) end
        end
      end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    for i = 1, MAXL do
      local L = list[i]
      local b = (L or pool[i]) and beamPart(i)
      if b then
        if L then
          rp.FilterDescendantsInstances = { L.ch, folder }
          local hit = workspace:Raycast(L.o, L.dir * 300, rp)
          local e = hit and hit.Position or (L.o + L.dir * 300)
          local len = (e - L.o).Magnitude
          b.beam.Size = V(0.03, 0.03, len)
          b.beam.CFrame = CFrame.lookAt(L.o + L.dir * (len / 2), e)
          b.beam.Transparency = 0.35
          b.dot.CFrame = CFrame.new(e - L.dir * 0.1)
          b.dot.Transparency = hit and 0.1 or 1
        else
          b.beam.Transparency, b.dot.Transparency = 1, 1
        end
      end
    end
    -- 手电：离得远的关掉（几十盏聚光灯一起亮很费）
    for tool, sl in pairs(lights) do
      local h = tool:FindFirstChild("Handle")
      local on = h ~= nil and tool.Parent ~= nil and tool.Parent:IsA("Model") and (h.Position - cp).Magnitude < 200
      if sl.Enabled ~= on then sl.Enabled = on end
    end
  end)

  ---------------------------------------------------------------- 先生成好要用的配件模型

  local function prewarm()
    task.delay(2, function()
      local keys = {}
      for _, holder in ipairs({ me:FindFirstChildOfClass("Backpack"), me.Character }) do
        if holder then
          for _, t in ipairs(holder:GetChildren()) do
            local id = t:IsA("Tool") and t:GetAttribute("Weapon")
            local code = id and t:GetAttribute("Build")
            if code then
              for _, item in pairs(GM.decode(code)) do
                local it = GM.ITEM[item]
                if it and it.model then keys[it.model] = true end
              end
            end
          end
        end
      end
      for k in pairs(keys) do
        if G.opticReady and not G.opticReady(k) and G.opticParts then G.opticParts(k) end   -- Optics.lua 一次只生成一件，排着队
      end
    end)
  end
  me.CharacterAdded:Connect(prewarm)
  if me.Character then prewarm() end
end

return GunKit
