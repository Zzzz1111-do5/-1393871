-- Roblox全面大战场——地图里的载具生成点（车场、停机位）
--   守方：营地车场（南面一排地面载具、北面直升机停机坪）、机场停机坪（据点 D 在守方手里才能用）
--   攻方：登陆平台（舰队前面浮在海上的大平台；两侧水面是地面载具的生成点：车站在气垫艇上，自己开去哪个海滩都行）、
--         两栖攻击舰甲板（直升机）、航母甲板（舰载机）、攻方机场岛停机坪（陆基飞机）
--   地面载具每种型号一个生成点：一根终端柱（ProximityPrompt「生成」，文字、牌子由客户端 Depot.lua 按语言写）+ 地上画出停放的位置；
--   飞机、直升机是「召唤点」（用户：地图改成召唤飞机的地方，我可以选哪种飞机、改导弹挂载）：每个航空基地几个召唤位，
--     按 E 弹出这个基地能用的机型（名额、冷却），选了再进挂载编辑器（含副油箱），生成在这个召唤位上（p.summon、p.vids）；
--   走过去按住 E：地面载具直接停在地台上；有挂点的飞机先在客户端弹出 3D 挂载界面，选好再发 padSpawn 生成；生成后自己走过去按 E 坐上
--   刚生成的 30 秒只有生成的人能上（别人抢不走）；90 秒没人上就收走（不算冷却，Armor / Air 里原有的空车回收）
--   舰艇的生成点、码头在 Navy.lua（用这里的 G.depotAddPad / G.depotBuildPad 加进来；kind "ship"，生成后直接坐上舰桥）
local RS = game:GetService("ReplicatedStorage")

local Depots = {}

function Depots.init(G)
  local Config, Map = G.Config, G.Map
  local VD = require(RS:WaitForChild("VehDefs"))
  local AD = require(RS:WaitForChild("AirDefs"))
  local SD = require(RS:WaitForChild("ShipDefs"))
  local V, CF, RGB, MAT = Vector3.new, CFrame.new, Color3.fromRGB, Enum.Material
  local now = os.clock

  local pads, byId = {}, {}
  G.pads = pads
  local SOUTH, NORTH = V(0, 0, 1), V(0, 0, -1)
  local USE_R = 14   -- 离终端柱多近才能生成（按键的距离 9 格，服务器宽一点）

  local function defOf(id) return VD.get(id) or AD.get(id) or SD.get(id) end
  local function models(team, cat)
    local out = {}
    for _, id in ipairs(Config.Vehicles[team][cat] or {}) do
      local d = defOf(id)
      if d and not d.needsAir then table.insert(out, id) end
    end
    return out
  end
  local function deckOf(kind)
    for _, d in ipairs(G.decks or {}) do if d.kind == kind then return d end end
    return nil
  end
  local function surface(x, z) return AD.ground(Map, x, z) end

  -- 一个生成点：team、vid（型号）、kind "veh" / "air"、base（停放位置：地面 / 甲板 / 海面上的点，朝向 = 车头）、
  --   term（终端柱脚下）、sea（码头外的水面）、need（"D"：据点 D 在本队手里才能用）、r（地台上停着东西就不能再生成：查这个半径）
  local function addPad(p)
    p.id = "pad" .. (#pads + 1)
    table.insert(pads, p)
    byId[p.id] = p
    return p
  end
  G.depotAddPad = addPad

  ---------------------------------------------------------------- 布局

  local function layout()
    -- 守方营地：南面一排地面载具（车头朝南，背后是通道，终端柱在车尾），北面直升机停机坪
    local C = Map.CAMP
    local list = {}
    for _, cat in ipairs({ "tank", "apc", "aa", "arty" }) do
      for _, id in ipairs(models("def", cat)) do table.insert(list, id) end
    end
    local gap = 22
    local x0 = C.x - (#list - 1) * gap / 2
    for i, id in ipairs(list) do
      local x, z = x0 + (i - 1) * gap, C.z + 70
      local d = defOf(id)
      addPad({ team = "def", vid = id, kind = "veh", base = CFrame.lookAt(V(x, surface(x, z), z), V(x, surface(x, z), z) + SOUTH),
        term = V(x - 4, 0, z - d.L / 2 - 4), r = 12, size = V(d.W + 2, 0, d.L + 2) })
    end
    local hx = { C.x - 140, C.x + 120, C.x + 172 }
    local dh = models("def", "heli")
    for i = 1, math.min(3, math.max(1, #dh)) do
      if #dh == 0 then break end
      local x, z = hx[i], C.z - 32
      addPad({ team = "def", vid = dh[1], vids = dh, summon = true, kind = "air", base = CFrame.lookAt(V(x, surface(x, z), z), V(x, surface(x, z), z) + SOUTH),
        term = V(x - 24, 0, z + 4), r = 24, size = V(30, 0, 30), heli = true })
    end
    -- 陆上机场的飞机：停在跑道上、机头朝东顺着跑道，一架接一架往东排、左右错开（地上的飞机彼此不碰撞，后面的照样直接起飞）；
    --   从跑道中间偏西开始排，前面还有两千多格跑道；终端柱在跑道北边（用户：机场太小、跑道非常短——
    --   原来停在跑道北边的停机坪上、机头朝南，一推油门就横穿过几十格宽的跑道冲出去了）
    local EAST = V(1, 0, 0)
    local function biggest(ids)   -- 召唤位按这个基地最大的机型留地方
      local L, W = 0, 0
      for _, id in ipairs(ids) do
        local d = defOf(id)
        if d then L, W = math.max(L, d.L), math.max(W, d.W) end
      end
      return L, W
    end
    local function runwayPads(A, team, ids, need)
      if #ids == 0 then return end
      local L, W = biggest(ids)
      local x = A.x - 420
      for i = 1, 4 do   -- 四个召唤位，一个接一个顺着跑道往东排、左右错开
        x += L / 2
        local z = A.z + ((i % 2 == 0) and 1 or -1) * A.wid * 0.2
        local pos = V(x, surface(x, z), z)
        addPad({ team = team, vid = ids[1], vids = ids, summon = true, kind = "air", need = need, base = CFrame.lookAt(pos, pos + EAST),
          term = V(x, 0, A.z - A.wid / 2 - 10), r = math.max(L, W) * 0.45, size = V(W + 4, 0, L + 4) })
        x += L / 2 + 30
      end
    end
    -- 守方机场（据点 D 丢了就用不了）
    local A = Map.AIRFIELD
    runwayPads(A, "def", models("def", "jet"), "D")

    -- 攻方航母：右舷后部停机位（舰岛后面），机头朝舰艏，自己滑到弹射器
    local cv = deckOf("carrier")
    if cv then
      local ids = {}
      for _, id in ipairs(models("atk", "jet")) do if defOf(id).carrier then table.insert(ids, id) end end
      local L, W = biggest(ids)
      for _, zl in ipairs({ 90, 174, 252 }) do
        if #ids == 0 then break end
        local p = (cv.cf * CF(26, 0, zl)).Position
        local base = CFrame.lookAt(V(p.X, surface(p.X, p.Z), p.Z), V(p.X, surface(p.X, p.Z), p.Z) + NORTH)
        addPad({ team = "atk", vid = ids[1], vids = ids, summon = true, kind = "air", base = base, term = (cv.cf * CF(50, 0, zl + 12)).Position,
          r = math.max(L, W) * 0.45, size = V(W + 2, 0, L + 2) })
      end
    end
    -- 攻方两栖攻击舰：左舷一列直升机停机位
    local lhd = deckOf("lhd")
    if lhd then
      local ids = models("atk", "heli")
      for i = 1, 2 do
        if #ids == 0 then break end
        local zl = -70 + (i - 1) * 140
        local p = (lhd.cf * CF(-16, 0, zl)).Position
        local base = CFrame.lookAt(V(p.X, surface(p.X, p.Z), p.Z), V(p.X, surface(p.X, p.Z), p.Z) + NORTH)
        addPad({ team = "atk", vid = ids[1], vids = ids, summon = true, kind = "air", base = base, term = (lhd.cf * CF(-16, 0, zl + 30)).Position, r = 24, size = V(30, 0, 30), heli = true })
      end
    end
    -- 攻方机场岛：陆基飞机（同守方机场，停在跑道上顺着跑道）
    local land = {}
    for _, id in ipairs(models("atk", "jet")) do if not defOf(id).carrier then table.insert(land, id) end end
    runwayPads(Map.AFIELD2, "atk", land, nil)
    -- 攻方登陆平台：两侧水面一格一个地面载具（车头朝北，朝着岛），终端柱在平台边上
    local B = Map.BARGE
    list = {}
    for _, cat in ipairs({ "tank", "apc", "aa", "arty" }) do
      for _, id in ipairs(models("atk", cat)) do table.insert(list, id) end
    end
    local half = math.ceil(#list / 2)
    for i, id in ipairs(list) do
      local west = i <= half
      local k = west and (i - 1) or (i - half - 1)
      local z = B.z - B.L / 2 + 40 + k * 56 + (west and 0 or 28)
      local sx = west and (B.x - B.W / 2 - 16) or (B.x + B.W / 2 + 16)   -- 气垫艇宽 28：贴着平台边，站在边上按 E 够得着
      local tx = west and (B.x - B.W / 2 + 5) or (B.x + B.W / 2 - 5)
      addPad({ team = "atk", vid = id, kind = "veh", sea = true, base = CFrame.lookAt(V(sx, 0, z), V(sx, 0, z) + NORTH),
        term = V(tx, B.top, z + 16), r = 16 })
    end
  end

  ---------------------------------------------------------------- 模型

  local function part(parent, size, cf, color, mat, solid)
    local p = Instance.new("Part")
    p.Anchored = true
    p.Size = size
    p.CFrame = cf
    p.Color = color
    p.Material = mat or MAT.SmoothPlastic
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.CanCollide = solid == true
    p.CanQuery = solid == true
    p.CanTouch = false
    p.CastShadow = solid == true
    p.Parent = parent
    return p
  end

  -- 登陆平台：浮在海上的一大块钢平台（四周护栏、几盏灯、两侧画出每个生成格）
  local function buildBarge(f)
    local B = Map.BARGE
    local m = Instance.new("Model")
    m.Name = "Barge"
    local deckY = B.top - 0.75
    part(m, V(B.W, 9, B.L), CF(B.x, deckY - 4.5 - 0.75, B.z), RGB(70, 74, 78), MAT.Metal, true)   -- 浮箱（往下伸进水里）
    local deck = part(m, V(B.W, 1.5, B.L), CF(B.x, deckY, B.z), RGB(58, 62, 66), MAT.DiamondPlate, true)
    deck.Name = "Deck"
    for _, s in ipairs({ -1, 1 }) do   -- 两侧护栏（中间留出上下车的口子，按生成格开）
      part(m, V(0.4, 2.6, B.L), CF(B.x + s * (B.W / 2 - 0.3), B.top + 1.3, B.z), RGB(150, 140, 60), MAT.Metal)
    end
    part(m, V(B.W, 2.6, 0.4), CF(B.x, B.top + 1.3, B.z - B.L / 2 + 0.3), RGB(150, 140, 60), MAT.Metal)
    part(m, V(B.W, 2.6, 0.4), CF(B.x, B.top + 1.3, B.z + B.L / 2 - 0.3), RGB(150, 140, 60), MAT.Metal)
    for k = -1, 1 do   -- 中线和几处集装箱、器材（站人的地方不挡）
      part(m, V(1, 0.08, B.L * 0.8), CF(B.x + k * 30, B.top + 0.04, B.z), RGB(200, 170, 60))
    end
    -- 夜里：中间一列探照灯、四角红灯、两边每个生成格一盏琥珀色边灯
    local W = G.World
    if W and W.floodPole then
      for k = -1, 1 do W.floodPole(m, B.x, B.top, B.z + k * B.L * 0.32, 16, Color3.fromRGB(255, 222, 172), 100) end
      for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
        W.light(m, V(B.x + c[1] * (B.W / 2 - 1), B.top + 3, B.z + c[2] * (B.L / 2 - 1)), Color3.fromRGB(255, 50, 40), 0.6, 10, 1.2, nil, 3)
      end
    end
    m.Parent = f
    return m
  end

  -- 生成点：终端柱（细高的灰色柱子、上面一块斜着的屏、一盏小灯）+ 地上的停放框（四条细线）
  local function buildPad(f, p)
    local m = Instance.new("Model")
    m.Name = p.id
    local ty = p.ty or (p.sea and Map.BARGE.top) or surface(p.term.X, p.term.Z)   -- ty：终端柱站在多高（码头面）
    local post = part(m, V(0.7, 4.4, 0.7), CF(p.term.X, ty + 2.2, p.term.Z), RGB(46, 48, 52), MAT.Metal, true)
    post.Name = "Post"
    local face = p.base.Position - p.term
    face = V(face.X, 0, face.Z)
    if face.Magnitude < 0.1 then face = V(0, 0, 1) end
    local head = CFrame.lookAt(V(p.term.X, ty + 4.6, p.term.Z), V(p.term.X, ty + 4.6, p.term.Z) - face.Unit) * CFrame.Angles(math.rad(-25), 0, 0)
    local scr = part(m, V(2.6, 1.6, 0.25), head, RGB(20, 22, 24), MAT.SmoothPlastic, true)
    scr.Name = "Screen"
    local lamp = part(m, V(0.35, 0.35, 0.35), CF(p.term.X, ty + 5.7, p.term.Z), RGB(120, 200, 255), MAT.Neon)
    lamp.Name = "Lamp"
    local pl = Instance.new("PointLight")
    pl.Range, pl.Brightness, pl.Color = 7, 0.8, RGB(140, 200, 255)
    pl.Parent = lamp
    local pr = Instance.new("ProximityPrompt")
    pr.Name = "Spawn"
    pr.ActionText = "Spawn"
    pr.ObjectText = p.vid
    pr.HoldDuration = 0.4
    pr.MaxActivationDistance = 9
    pr.RequiresLineOfSight = false
    pr.Parent = post
    pr.Triggered:Connect(function(pl2) G.try("生成点", G.padTrigger, pl2, p.id) end)
    -- 停放框：地上（甲板上）四条细线（码头外的水面不画）
    if p.size and not p.sea then
      local c = p.base
      local y = surface(c.Position.X, c.Position.Z) + 0.06
      local cc = CFrame.new(c.Position.X, y, c.Position.Z) * (c - c.Position)
      local w, l = p.size.X, p.size.Z
      local col = RGB(210, 214, 220)
      part(m, V(0.35, 0.08, l), cc * CF(-w / 2, 0, 0), col)
      part(m, V(0.35, 0.08, l), cc * CF(w / 2, 0, 0), col)
      part(m, V(w, 0.08, 0.35), cc * CF(0, 0, l / 2), col)
      part(m, V(w * 0.3, 0.08, 0.35), cc * CF(0, 0, -l / 2), col)   -- 车头那边只画一小段：开出去的方向
    end
    m:SetAttribute("PadId", p.id)
    m:SetAttribute("Model", p.vid)
    m:SetAttribute("Team", p.team)
    m:SetAttribute("Kind", p.kind)
    m:SetAttribute("Need", p.need or "")
    if p.summon then   -- 召唤位：能选的机型（逗号隔开）、是不是直升机
      m:SetAttribute("Summon", table.concat(p.vids, ","))
      m:SetAttribute("Heli", p.heli == true)
    end
    m.Parent = f
    p.model, p.prompt = m, pr
  end
  G.depotBuildPad = buildPad

  -- 开服：地图（舰队甲板）好了以后摆生成点（init.server.lua 在 World.build 之后调）
  function G.depotsBuild()
    local root = workspace:FindFirstChild("Map") or workspace
    local f = Instance.new("Folder")
    f.Name = "Pads"
    G.try("登陆平台", buildBarge, f)
    layout()
    for _, p in ipairs(pads) do G.try("生成点 " .. p.vid, buildPad, f, p) end
    f.Parent = root
  end

  ---------------------------------------------------------------- 生成

  local function flat(v) return V(v.X, 0, v.Z) end
  -- 这个生成点现在能不能用（need：据点 D 的机场、据点 C 的港口要在本队手里）
  local function padOpen(p, team)
    if p.team ~= team then return false end
    if p.need then
      local s = G.points and G.points[p.need]
      return s ~= nil and s.owner == team
    end
    return true
  end
  G.padOpen = padOpen
  -- 地台上还停着车 / 飞机（刚生成的、没开走的）
  local function padBusy(p)
    local c = flat(p.base.Position)
    for _, e in ipairs(G.vehicles or {}) do
      if e.alive and (flat(e.root.CFrame.Position) - c).Magnitude < (p.r or 14) then return true end
    end
    for _, e in ipairs(G.aircraft or {}) do
      if e.alive and (flat(e.root.CFrame.Position) - c).Magnitude < (p.r or 14) then return true end
    end
    for _, e in ipairs(G.ships or {}) do
      if e.alive and (flat(e.root.CFrame.Position) - c).Magnitude < (p.r or 14) then return true end
    end
    return false
  end

  -- 能不能在这个生成点生成（不能的话给这个人说一声为什么）
  local function check(P, p, vid)
    local R = G.round
    if not R or (R.phase ~= "prep" and R.phase ~= "battle") then return false end
    if not P or not P.alive or not P.char or P.vehicle then return false end
    if P.team ~= p.team then return false end
    local hrp = P.char:FindFirstChild("HumanoidRootPart")
    if not hrp or (flat(hrp.Position) - flat(p.term)).Magnitude > USE_R then return false end
    if not padOpen(p, P.team) then G.msg(P.pl, "bad", "ui.padLocked") return false end
    local d = defOf(vid or p.vid)
    if not d then return false end
    local av = G.vehAvail(P.team)[d.cat]
    if av and av.u >= av.cap then
      if av.cd and av.cd > 0 then G.msg(P.pl, "bad", "ui.vehCdMsg", av.cd) else G.msg(P.pl, "bad", "ui.vehFull") end
      return false
    end
    if padBusy(p) then G.msg(P.pl, "bad", "ui.padBusy") return false end
    return true, d
  end

  local function spawnAt(P, p, load, vid, fuel)
    vid = vid or p.vid
    local ok, d = check(P, p, vid)
    if not ok then return nil end
    if now() < (P.padT or 0) then return nil end
    P.padT = now() + 2
    local e
    if p.kind == "air" then
      local c = p.base.Position
      local pos = V(c.X, surface(c.X, c.Z) + d.gearH, c.Z)
      e = G.spawnAircraft and G.spawnAircraft(P.team, vid, CFrame.lookAt(pos, pos + p.base.LookVector), load, P, fuel)
    elseif p.kind == "ship" then
      e = G.spawnShip and G.spawnShip(P.team, p.vid, p.base, P)
    else
      e = G.spawnGroundVeh and G.spawnGroundVeh(P.team, p.vid, p.base, p.sea, P)
    end
    if e then
      e.padId = p.id
      G.fx({ k = "padSpawn", p = e.root.CFrame.Position })
    end
    return e
  end
  G.padSpawnAt = spawnAt

  -- 按住 E：地面载具直接生成；有挂点的飞机先让客户端弹出挂载界面（选好了发 padSpawn）
  function G.padTrigger(pl, padId)
    local P = G.P[pl]
    local p = byId[padId]
    if not P or not p then return end
    if p.summon then   -- 召唤位：先弹出机型列表（客户端选了机型、挂载再发 padSpawn）
      if not check(P, p, p.vid) then return end   -- 一个召唤位上的机型同一类（飞机 / 直升机），名额一样，先查一遍
      G.R.Drive:FireClient(pl, { op = "airPick", pad = p.id, ids = p.vids, heli = p.heli == true })
      return
    end
    local d = defOf(p.vid)
    if p.kind == "air" and d.st and #d.st > 0 then
      if not check(P, p) then return end
      G.R.Drive:FireClient(pl, { op = "hangar", pad = p.id, id = p.vid })
      return
    end
    spawnAt(P, p, nil)
  end

  -- vid：召唤位上选的机型（要在这个召唤位的列表里）；fuel：挂载界面选的内油（几成，Air.lua 再夹到 0.25～1）
  function G.ACT.padSpawn(P, padId, load, vid, fuel)
    local p = type(padId) == "string" and byId[padId] or nil
    if not p or p.kind ~= "air" then return end
    if p.summon then
      vid = vid or p.vid   -- 没说型号（老客户端、老的一型一位）：这个召唤位的第一型
      local okId = false
      for _, id in ipairs(p.vids) do if id == vid then okId = true end end
      if not okId then return end
    else
      vid = nil
    end
    spawnAt(P, p, (type(load) == "table") and load or nil, vid, (type(fuel) == "number") and fuel or nil)
  end
end

return Depots
