-- 全面大战场（客户端）——机库背后的厂房（用户 11-25 给了两张截图：「一进入游戏的界面给我改成这样」）
--   截图里界面背后是一间修理厂房：水泥地、黄线、地沟、吊灯一排排打下来的光、红油桶、轮胎、黄色的检修梯。这里用零件搭一间自己的：
--   长 280 格、宽 192 格、檐口 62 格的钢结构厂房——水泥地（分缝、黄色引导线、停车框、排水篦子、检修地沟）、下半截水泥上半截钢板的墙、
--   立柱（底下黄黑警示带）、桁架、屋面和采光板、两头的推拉大门、侧墙的窗、桥式起重机（吊钩垂着）、两排吊灯（带光柱）、
--   靠墙的杂物（油桶、木箱、轮胎、工作台、工具柜、检修梯、货架、地上盘着的电缆、路锥）、空气里飘的灰。
--   只在本机：搭在地图外很高的地方，机库界面开着时镜头在里面对着停在正中的那辆车（TechUI.lua 把出击阵容里选中的那一辆摆进来），
--   按住拖动转着看、滚轮拉近拉远；关了机库收起来、镜头还给游戏。
local Stage = {}

local RGB = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local MAT = Enum.Material
local UP = ANG(0, 0, math.pi / 2)   -- 圆柱的轴（X）竖起来
-- 搭在大厅那一块（Zones.LOBBY，x = −100000）：用户 11-26 晚「目前游戏里的几个地图是连起来的 不行」——原来在 (−9000, 900, 9000)，
--   钢城地形铺到 ±12288，厂房就悬在战场上空（开飞机看得见，从厂房里也看得见底下的城）
local Zones = require(game:GetService("ReplicatedStorage"):WaitForChild("Zones"))
local Theme = require(game:GetService("ReplicatedStorage"):WaitForChild("Theme"))   -- 高亮的琥珀（选中）、动效的缓动（Theme.ease）
local ORIGIN = Zones.HANGAR
-- 看飞机、直升机（用户 11-25「查看飞机和直升机的时候单独做个背景吧」）：大厅里另一处搭一块露天机场停机坪（隔三万格），选中飞机就切过去
local ORIGIN_AIR = Zones.HANGAR_AIR
local BUILD_AT = ORIGIN   -- part() 摆零件用哪个原点（搭停机坪时换成 ORIGIN_AIR）
local HX, Z0, Z1, HY, RISE = 96, -124, 156, 62, 15   -- 半宽、近端墙、远端墙、檐口高、屋脊比檐口高多少
local FOV = 40

local model = nil    -- 整间厂房
local slot = nil     -- 停在正中的那辆车（TechUI 给的模型）
local shown = false
-- 镜头：yaw / pitch / dist 是要去的，s* 是现在的（慢慢跟过去）；h 看向离地多高；base 这辆车合适的距离
--   at：看向哪一点（底座系，nil 是车正中离地 h；整备点挂点时看挂点），sat 是现在的；tilt：镜头往下压多少（rad，默认 −3.5°：车在画面里偏上）；
--   shift：镜头往右平移多少格（正的：车在画面里往左挪，给右栏让地方）；fly：Stage.focus 正在飞的那一段（缓动，飞完交回上面的慢慢跟）
local TILT0 = math.rad(-3.5)
local view = { yaw = math.pi - 0.62, pitch = 0.15, dist = 58, base = 58, h = 3, t = 0, sy = math.pi - 0.62, sp = 0.15, sd = 58, sh = 3,
  at = nil, sat = V(0, 3, 0), tilt = TILT0, stilt = TILT0, shift = 0, sshift = 0, fly = nil }
-- 每个场景镜头的俯仰范围（rad，正的从上往下看）、眼睛离地至少几格：厂房里只能从上往下看、上面有屋顶；
--   停机坪（用户 11-27 整备）允许从机翼下面往上看（−0.15，看翼下挂点），露天没有屋顶，也能升高到 1.2 往下看机翼上面
local LIM = { ground = { p0 = 0.03, p1 = 0.8, eye = 2.4 }, air = { p0 = -0.15, p1 = 1.2, eye = 0.8 } }

local function part(parent, name, size, cf, color, mat, shape)
  local p = Instance.new("Part")
  p.Name = name
  if shape then p.Shape = shape end
  p.Size = size
  p.CFrame = BUILD_AT * cf
  p.Color = color
  p.Material = mat or MAT.SmoothPlastic
  p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
  p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
  p.Parent = parent
  return p
end

local CONC, CONC2, CONC3 = RGB(126, 122, 112), RGB(100, 97, 90), RGB(138, 133, 122)
local STEEL, SIDING, ROOF = RGB(52, 56, 58), RGB(86, 94, 92), RGB(56, 60, 60)
local YEL, BLACK, RED, OLIVE = RGB(206, 164, 44), RGB(22, 22, 24), RGB(152, 40, 34), RGB(74, 84, 56)
local WARM = RGB(255, 232, 184)

---------------------------------------------------------------- 厂房本体

local function shell(m)
  local function W(name, size, cf, color, mat, shape) return part(m, name, size, cf, color, mat, shape) end
  local LEN, ZC = Z1 - Z0, (Z0 + Z1) / 2
  -- 地面：四块水泥板围着检修地沟（车右边一条 10 × 64 的沟，7 格深）
  local PX0, PX1, PZ0, PZ1, PD = 36, 46, -6, 58, 7
  W("Floor", V(PX0 + HX, 2, LEN), CF((PX0 - HX) / 2, -1, ZC), CONC, MAT.Concrete)
  W("Floor", V(HX - PX1, 2, LEN), CF((PX1 + HX) / 2, -1, ZC), CONC, MAT.Concrete)
  W("Floor", V(PX1 - PX0, 2, PZ0 - Z0), CF((PX0 + PX1) / 2, -1, (Z0 + PZ0) / 2), CONC, MAT.Concrete)
  W("Floor", V(PX1 - PX0, 2, Z1 - PZ1), CF((PX0 + PX1) / 2, -1, (PZ1 + Z1) / 2), CONC, MAT.Concrete)
  local pcx, pcz, pw, pl = (PX0 + PX1) / 2, (PZ0 + PZ1) / 2, PX1 - PX0, PZ1 - PZ0
  W("PitFloor", V(pw + 1.2, 1, pl + 1.2), CF(pcx, -PD - 0.5, pcz), RGB(66, 64, 60), MAT.Concrete)
  W("PitWall", V(0.6, PD - 2, pl + 1.2), CF(PX0 - 0.3, -2 - (PD - 2) / 2, pcz), CONC2, MAT.Concrete)
  W("PitWall", V(0.6, PD - 2, pl + 1.2), CF(PX1 + 0.3, -2 - (PD - 2) / 2, pcz), CONC2, MAT.Concrete)
  W("PitWall", V(pw, PD - 2, 0.6), CF(pcx, -2 - (PD - 2) / 2, PZ0 - 0.3), CONC2, MAT.Concrete)
  W("PitWall", V(pw, PD - 2, 0.6), CF(pcx, -2 - (PD - 2) / 2, PZ1 + 0.3), CONC2, MAT.Concrete)
  for i = 0, 5 do   -- 沟里的台阶（靠近端）
    W("PitStep", V(pw - 1, 1.1, 1.6), CF(pcx, -0.6 - i * 1.15, PZ0 + 1 + i * 1.6), CONC2, MAT.Concrete)
  end
  -- 地上贴的东西分层摆（用户 11-27「开始游戏的那个仓库有些频闪」）：原来分缝、黄线、油渍、轮胎印、排水篦子的顶面一层层只差一两个百分之一格
  --   （九块油渍一块只比一块高 0.0015 格；停车框四角加粗那几块只比框线高 0.012），x = −100000 那儿 32 位浮点本来就只分得出 1/128 格，
  --   镜头又一直微微晃，贴在一起的面前后来回换着画（抢深度）。现在顶面固定几层、层与层差 0.06 格，同一层里的互相不压（交叉处断开、拼着只挨着）：
  --   0 地面 · 0.06 分缝 · 0.12 排水槽、沟边黄线、轮胎印、油渍 · 0.18 黄线（四角的 L 形和框线拼着）、篦子的边框和横档
  --   测试 tools/mock/hangarzfight.lua 把搭出来的零件拆成面两两查（远处那圈平地也算上）
  local Y1, Y2, Y3 = 0.06, 0.12, 0.18
  local function flat(name, sx, sz, x, z, top, color, mat)   -- 贴地的一块：从地面下 0.02 到 top（底下不留缝）
    return W(name, V(sx, top + 0.02, sz), CF(x, (top - 0.02) / 2, z), color, mat)
  end
  for _, e in ipairs({ { PX0 - 0.6, pcz, 0.7, pl + 2.6 }, { PX1 + 0.6, pcz, 0.7, pl + 2.6 }, { pcx, PZ0 - 0.6, pw + 0.5, 0.7 }, { pcx, PZ1 + 0.6, pw + 0.5, 0.7 } }) do
    flat("PitEdge", e[3], e[4], e[1], e[2], Y2, YEL)   -- 沟边一圈黄线
  end
  -- 分缝：纵向五道通长；横向每 31 格一道，在纵向分缝、地沟（连沟边黄线）那儿断开。
  --   横缝比原来往近端挪 0.3 格：原来 z = 93 那道的侧面正好和 z = 96 那根柱子的警示带侧面贴着
  local SEAM, SW = RGB(74, 71, 65), 0.3
  local SX = { -64, -32, 0, 32, 64 }
  local function seamRow(x0, x1, z)
    local a = x0
    for _, sx in ipairs(SX) do
      if sx - SW / 2 > a and sx + SW / 2 < x1 then
        flat("Seam", sx - SW / 2 - a, SW, (a + sx - SW / 2) / 2, z, Y1, SEAM, MAT.Concrete)
        a = sx + SW / 2
      end
    end
    if x1 > a then flat("Seam", x1 - a, SW, (a + x1) / 2, z, Y1, SEAM, MAT.Concrete) end
  end
  for z = Z0 + 30.7, Z1 - 1, 31 do
    if z > PZ0 - 1 and z < PZ1 + 1 then
      seamRow(-HX, PX0 - 1, z)
      seamRow(PX1 + 1, HX, z)
    else
      seamRow(-HX, HX, z)
    end
  end
  for _, x in ipairs(SX) do flat("Seam", SW, LEN, x, ZC, Y1, SEAM, MAT.Concrete) end
  -- 黄线：两条通长的引导线、正中的停车框（四角加粗：L 形的两笔和框线拼着、不叠）、门口的横线。
  --   停车框不透明：原来框线半透明（0.2），压在半透明的轮胎印、油渍上面——两块半透明的叠着，Roblox 按远近排谁先画，镜头一晃来回换、重叠那块颜色跳
  local function line(x, z, sx, sz, tr)
    local p = flat("Line", sx, sz, x, z, Y3, YEL)
    p.Transparency = tr or 0.12
    return p
  end
  line(-27, ZC, 0.8, LEN - 30)
  line(27, ZC, 0.8, LEN - 30)
  for _, s in ipairs({ -1, 1 }) do
    line(s * 21, 0, 0.6, 53.4, 0)   -- 长边：z ±26.7（再往两头是 L 形的竖笔）
    line(0, s * 31, 33.4, 0.6, 0)   -- 短边：x ±16.7（再往两边是 L 形的横笔）
    for _, t in ipairs({ -1, 1 }) do
      line(s * 19.15, t * 31, 4.9, 1.2, 0)   -- L 形横笔：x 16.7～21.6
      line(s * 21, t * 28.55, 1.2, 3.7, 0)   -- L 形竖笔：z 26.7～30.4
    end
  end
  line(0, Z1 - 12, 120, 1.2)
  line(0, Z0 + 12, 76, 1.2)
  -- 油渍：几块发暗的圆斑，摆死在这几处（互相不压，也不压轮胎印、黄线；原来随机摆，Roblox 的圆柱截面是圆的，长短轴那一下本来也没用）
  for _, s in ipairs({ { -9.5, -14, 9, 0.62 }, { 9, -21, 7.5, 0.7 }, { -15.5, 11, 8, 0.66 }, { 13.5, 2.5, 9.5, 0.74 }, { 0.5, 25, 6, 0.6 },
    { 14, 37, 6, 0.72 }, { -14, -36, 5.5, 0.68 }, { 0.5, 1, 10, 0.58 }, { -18, 39, 7, 0.76 } }) do
    local st = W("Stain", V(0.1, s[3], s[3]), CF(s[1], Y2 - 0.05, s[2]) * UP, RGB(46, 44, 40), MAT.SmoothPlastic, Enum.PartType.Cylinder)
    st.Transparency = s[4]
    st.CastShadow = false
  end
  for _, x in ipairs({ -6.2, 6.2 }) do   -- 轮胎印
    local tr = flat("Tread", 3.2, 96, x, 56, Y2, RGB(52, 50, 46))
    tr.Transparency = 0.72
    tr.CastShadow = false
  end
  -- 排水篦子：左边一条（边框比槽两头各长 0.2：端面不对齐）
  flat("Drain", 5, LEN - 40, -47, ZC, Y2, RGB(30, 31, 32), MAT.Metal)
  flat("DrainEdge", 0.5, LEN - 39.6, -49.7, ZC, Y3, RGB(70, 72, 74), MAT.Metal)
  flat("DrainEdge", 0.5, LEN - 39.6, -44.3, ZC, Y3, RGB(70, 72, 74), MAT.Metal)
  for z = Z0 + 24, Z1 - 24, 4.4 do
    local b = flat("DrainBar", 4.8, 1.5, -47, z, Y3, RGB(62, 64, 66), MAT.DiamondPlate)
    b.CastShadow = false
  end

  -- 侧墙：下半截水泥（凸出半格）、上半截钢板，两道横檩，檐口下一条采光带
  for _, s in ipairs({ -1, 1 }) do
    W("WallBase", V(3, 16, LEN + 6), CF(s * (HX + 1), 8, ZC), CONC2, MAT.Concrete)
    W("WallSiding", V(1.2, HY - 16 + RISE, LEN + 6), CF(s * (HX + 0.6), 16 + (HY - 16 + RISE) / 2, ZC), SIDING, MAT.Metal)
    W("WallCap", V(3.6, 0.8, LEN + 6), CF(s * (HX + 0.8), 16.4, ZC), CONC3, MAT.Concrete)
    for _, y in ipairs({ 25, 49 }) do W("Girt", V(0.9, 0.9, LEN), CF(s * (HX - 0.4), y, ZC), STEEL, MAT.Metal) end
    local strip = W("Clerestory", V(0.4, 4.6, LEN - 12), CF(s * (HX - 0.15), HY - 5, ZC), RGB(232, 230, 214), MAT.Neon)
    strip.Transparency = 0.35
    strip.CastShadow = false
  end
  -- 立柱：两侧各七根（底下黄黑警示带、上面托吊车梁的牛腿、挂着的灭火器）
  local COLS = {}
  for k = 0, 6 do table.insert(COLS, Z0 + 20 + k * 40) end
  for ci, z in ipairs(COLS) do
    for _, s in ipairs({ -1, 1 }) do
      local x = s * (HX - 3.5)
      W("Column", V(6, HY, 6), CF(x, HY / 2, z), CONC3, MAT.Concrete)
      W("ColBand", V(6.3, 5, 6.3), CF(x, 2.5, z), YEL)
      W("ColBandK", V(6.5, 0.9, 6.5), CF(x, 1.3, z), BLACK)   -- 黑道比黄带凸出 0.1（原来只凸 0.05）
      W("ColBandK", V(6.5, 0.9, 6.5), CF(x, 3.7, z), BLACK)
      W("Corbel", V(8, 2.2, 5.4), CF(s * (HX - 6.5), HY - 12.2, z), STEEL, MAT.Metal)   -- 比柱子窄 0.6（原来同宽：两个侧面贴在柱子侧面上抢深度）
      if ci % 2 == 0 then   -- 隔一根柱子挂一只灭火器
        W("Extinguisher", V(2.3, 0.95, 0.95), CF(s * (HX - 7), 5.2, z) * UP, RGB(190, 36, 30), MAT.Metal, Enum.PartType.Cylinder)
        W("ExtSign", V(0.2, 1.8, 1.8), CF(s * (HX - 6.55), 8.2, z), RGB(196, 40, 32))
      end
    end
  end
  -- 侧墙的窗：两根柱子之间一樘（深蓝的玻璃、窗框、三根竖梃一根横梃）
  local wr = Random.new(5)
  for i = 1, #COLS - 1 do
    local zc = (COLS[i] + COLS[i + 1]) / 2
    for _, s in ipairs({ -1, 1 }) do
      local x = s * (HX - 0.2)
      local lit = wr:NextNumber() < 0.34
      local pane = W("Window", V(0.5, 15, 26), CF(x, 36, zc), lit and RGB(104, 136, 158) or RGB(48, 74, 98), MAT.Glass)
      pane.Reflectance = 0.18
      W("WinFrame", V(0.8, 0.8, 27.4), CF(x - s * 0.1, 43.9, zc), STEEL, MAT.Metal)
      W("WinFrame", V(0.8, 0.8, 27.4), CF(x - s * 0.1, 28.1, zc), STEEL, MAT.Metal)
      W("WinFrame", V(0.8, 15, 0.8), CF(x - s * 0.1, 36, zc - 13.3), STEEL, MAT.Metal)
      W("WinFrame", V(0.8, 15, 0.8), CF(x - s * 0.1, 36, zc + 13.3), STEEL, MAT.Metal)
      for _, dz in ipairs({ -6.6, 0, 6.6 }) do W("WinBar", V(0.7, 15, 0.45), CF(x - s * 0.1, 36, zc + dz), STEEL, MAT.Metal) end
      W("WinBar", V(0.5, 0.45, 25.8), CF(x - s * 0.1, 36, zc), STEEL, MAT.Metal)   -- 横梃比竖梃薄 0.2、两头收到窗框里（原来和竖梃面贴面）
    end
  end

  -- 两头的墙：大门（两扇推拉门，竖筋、横档、门上的编号）、门两边的墙垛、门上面的墙和一排高窗
  local function endWall(z, dir, dw, dh, num)
    local zo = z + dir * 0.6
    local side = HX - dw / 2
    for _, s in ipairs({ -1, 1 }) do
      local cx = s * (dw / 2 + side / 2)
      W("EndBase", V(side + 2, 16, 3), CF(cx, 8, z + dir * 1), CONC2, MAT.Concrete)
      W("EndSiding", V(side + 2, dh - 16, 1.2), CF(cx, 16 + (dh - 16) / 2, zo), SIDING, MAT.Metal)
      -- 压顶：门边比墙垛多出 0.3、到侧墙的压顶为止（原来两头和墙垛、侧墙压顶的面贴着）
      W("EndCap", V(side + 0.3, 0.8, 3.6), CF(s * (dw / 2 + HX - 2.3) / 2, 16.4, z + dir * 0.8), CONC3, MAT.Concrete)
    end
    W("EndTop", V(2 * HX + 4, HY - dh + RISE, 1.2), CF(0, dh + (HY - dh + RISE) / 2, zo), SIDING, MAT.Metal)
    W("DoorTrack", V(dw + 10, 2.2, 2.6), CF(0, dh + 1.1, z - dir * 1.3), STEEL, MAT.Metal)   -- 整根在墙面里边（原来一截插进门上的墙、底面和墙底面贴着）
    local DOOR = RGB(58, 72, 62)
    for _, s in ipairs({ -1, 1 }) do
      local cx = s * dw / 4
      local leaf = W("Door", V(dw / 2 - 0.3, dh, 1.2), CF(cx, dh / 2, z + dir * 0.3), DOOR, MAT.Metal)
      for k = -3, 3 do W("DoorRib", V(0.9, dh - 1, 0.5), CF(cx + k * (dw / 2 - 4) / 7, dh / 2, z - dir * 0.45), RGB(48, 60, 52), MAT.Metal) end
      for _, y in ipairs({ 1.2, dh * 0.5, dh - 1.2 }) do W("DoorRail", V(dw / 2 - 0.6, 1, 0.6), CF(cx, y, z - dir * 0.5), RGB(46, 56, 50), MAT.Metal) end
      -- 门上的编号（喷的白字，旧了）
      local sg = Instance.new("SurfaceGui")
      sg.Face = (dir > 0) and Enum.NormalId.Front or Enum.NormalId.Back   -- 朝厂房里面的那一面
      sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
      sg.PixelsPerStud = 12
      sg.LightInfluence = 1
      sg.Parent = leaf
      local t = Instance.new("TextLabel")
      t.BackgroundTransparency = 1
      t.Size, t.Position = UDim2.fromScale(0.5, 0.36), UDim2.fromScale(0.25, 0.3)
      t.Font = Enum.Font.BuilderSansExtraBold
      t.TextScaled = true
      t.TextColor3 = RGB(214, 214, 204)
      t.TextTransparency = 0.45
      t.Text = (s * dir > 0) and string.sub(num, 1, 1) or string.sub(num, 2, 2)   -- 从里面看，左边那扇是第一个数字
      t.Parent = sg
    end
    W("DoorGap", V(0.5, dh, 0.5), CF(0, dh / 2, z - dir * 0.36), BLACK, MAT.Metal)
    -- 高窗：门上面一排（泛着外面的天光）
    local wy = (dh + HY) / 2 + 1.5
    local wh = math.max(6, HY - dh - 7)
    local hw = W("HighWindow", V(2 * HX - 36, wh, 0.4), CF(0, wy, z - dir * 0.45), RGB(118, 152, 172), MAT.Neon)
    hw.Transparency = 0.5
    hw.CastShadow = false
    W("HighBack", V(2 * HX - 36, wh, 0.3), CF(0, wy, z - dir * 0.05), RGB(40, 60, 78))
    for x = -(HX - 18), HX - 18, 12 do W("HighBar", V(0.6, wh - 0.6, 0.7), CF(x, wy, z - dir * 0.6), STEEL, MAT.Metal) end   -- 竖的顶到横的为止
    W("HighBar", V(2 * HX - 35, 0.6, 0.7), CF(0, wy + wh / 2, z - dir * 0.6), STEEL, MAT.Metal)   -- 横的比高窗两头各长 0.5（端面不和窗的端面对齐）
    W("HighBar", V(2 * HX - 35, 0.6, 0.7), CF(0, wy - wh / 2, z - dir * 0.6), STEEL, MAT.Metal)
  end
  endWall(Z1, 1, 116, 46, "07")
  endWall(Z0, -1, 72, 38, "12")

  -- 屋面：两坡，底下檩条、采光板；每根柱子上一榀桁架（下弦、上弦、竖杆、斜杆）
  local s = math.sqrt(HX * HX + RISE * RISE)
  local a = math.atan2(RISE, HX)
  for _, sd in ipairs({ -1, 1 }) do
    local base = CF(sd * HX / 2, HY + RISE / 2 + 1.2, ZC) * ANG(0, 0, -sd * a)
    W("Roof", V(s + 3, 1.2, LEN + 8), base, ROOF, MAT.Metal)
    for _, dx in ipairs({ -34, -6, 22 }) do W("Purlin", V(1, 1.1, LEN), base * CF(sd * dx, -1.1, 0), STEEL, MAT.Metal) end
    for i = 1, #COLS - 1 do
      local zc = (COLS[i] + COLS[i + 1]) / 2 - ZC
      local sky = W("Skylight", V(30, 0.3, 24), base * CF(-sd * 10, -0.72, zc), RGB(246, 240, 216), MAT.Neon)
      sky.Transparency = 0.12
      sky.CastShadow = false
      -- 压条比采光板两头各长 0.3（原来端面和采光板端面对齐）；纵的那根薄 0.1（原来和横的底面贴面）
      W("SkyBar", V(30.6, 0.5, 0.6), base * CF(-sd * 10, -0.95, zc - 6), STEEL, MAT.Metal)
      W("SkyBar", V(30.6, 0.5, 0.6), base * CF(-sd * 10, -0.95, zc + 6), STEEL, MAT.Metal)
      W("SkyBar", V(0.6, 0.4, 24.6), base * CF(-sd * 10, -0.9, zc), STEEL, MAT.Metal)
    end
  end
  local function beam(p0, p1, w)
    local d = (p1 - p0).Magnitude
    return W("Web", V(w, w, d), CFrame.lookAt((p0 + p1) / 2, p1), STEEL, MAT.Metal)
  end
  local function hAt(x) return RISE * (1 - math.abs(x) / HX) end
  for _, z in ipairs(COLS) do
    W("Chord", V(2 * HX - 12, 1.6, 1.6), CF(0, HY, z), STEEL, MAT.Metal)
    for _, sd in ipairs({ -1, 1 }) do
      W("Rafter", V(s - 4, 1.4, 1.4), CF(sd * HX / 2, HY + RISE / 2 - 0.4, z) * ANG(0, 0, -sd * a), STEEL, MAT.Metal)
      for k = 1, 3 do
        local x = sd * k * HX / 4
        local h = hAt(x) - 0.4
        W("Post", V(1, h, 1), CF(x, HY + h / 2, z), STEEL, MAT.Metal)
        local xi = sd * (k - 1) * HX / 4
        beam(V(x, HY, z), V(xi, HY + hAt(xi) - 0.6, z), 0.8)   -- 斜杆比竖杆细 0.2（原来只细 0.1）
      end
    end
    W("Post", V(1.2, RISE - 0.4, 1.2), CF(0, HY + (RISE - 0.4) / 2, z), STEEL, MAT.Metal)
  end

  -- 桥式起重机：两条轨道梁搁在牛腿上，一座黄色的桥、小车、垂下来的钢丝绳和吊钩
  local RX, RY = HX - 8.5, HY - 10
  for _, sd in ipairs({ -1, 1 }) do W("CraneRail", V(2, 2.4, LEN - 16), CF(sd * RX, RY, ZC), STEEL, MAT.Metal) end
  local CZ = 74
  for _, dz in ipairs({ -3.6, 3.6 }) do W("CraneBridge", V(2 * RX + 2, 4.4, 2.2), CF(0, RY + 3.6, CZ + dz), RGB(206, 160, 36), MAT.Metal) end
  for _, sd in ipairs({ -1, 1 }) do
    W("CraneTruck", V(3.2, 3, 13), CF(sd * RX, RY + 2.7, CZ), RGB(60, 62, 64), MAT.Metal)
    for _, dz in ipairs({ -3.6, 3.6 }) do
      local st = W("CraneStripe", V(8, 4.5, 0.2), CF(sd * (RX - 8), RY + 3.6, CZ + dz + ((dz > 0) and 1.2 or -1.2)), BLACK)
      st.Transparency = 0.25
    end
  end
  W("Trolley", V(9, 3, 9.6), CF(-24, RY + 6.6, CZ), RGB(64, 66, 70), MAT.Metal)
  W("TrolleyDrum", V(6, 2.6, 2.6), CF(-24, RY + 4.4, CZ), RGB(40, 42, 44), MAT.Metal, Enum.PartType.Cylinder)
  W("Cable", V(19, 0.3, 0.3), CF(-24, RY - 6.4, CZ) * UP, RGB(30, 30, 32), MAT.Metal, Enum.PartType.Cylinder)
  W("HookBlock", V(2.6, 3.4, 1.8), CF(-24, RY - 17.4, CZ), RGB(206, 160, 36), MAT.Metal)
  W("HookBlockK", V(2.8, 0.7, 2.0), CF(-24, RY - 17.4, CZ), BLACK)
  W("Hook", V(0.6, 2.2, 0.6), CF(-24, RY - 20.1, CZ), RGB(36, 36, 38), MAT.Metal)
  W("Hook", V(1.6, 0.6, 0.44), CF(-23.4, RY - 21.2, CZ), RGB(36, 36, 38), MAT.Metal)   -- 底下那一横比两根竖的薄、短（原来几个面对齐）
  W("Hook", V(0.6, 1.2, 0.6), CF(-22.8, RY - 20.6, CZ), RGB(36, 36, 38), MAT.Metal)
end

---------------------------------------------------------------- 灯

local function lights(m)
  local function W(name, size, cf, color, mat, shape) return part(m, name, size, cf, color, mat, shape) end
  local LY = 37   -- 灯口离地
  local function lamp(x, z, shadow, bright)
    W("LampRod", V(0.3, HY - LY - 1.8, 0.3), CF(x, LY + 1.8 + (HY - LY - 1.8) / 2, z), BLACK, MAT.Metal)
    W("LampShade", V(1.8, 6.6, 6.6), CF(x, LY + 0.9, z) * UP, RGB(38, 42, 42), MAT.Metal, Enum.PartType.Cylinder)
    local bulb = W("LampBulb", V(0.3, 4.6, 4.6), CF(x, LY - 0.05, z) * UP, WARM, MAT.Neon, Enum.PartType.Cylinder)
    bulb.CastShadow = false
    local h = W("LampLight", V(1, 1, 1), CF(x, LY - 0.6, z), BLACK)
    h.Transparency = 1
    h.CastShadow = false
    local sl = Instance.new("SpotLight")
    sl.Face = Enum.NormalId.Bottom
    sl.Angle, sl.Range, sl.Brightness = 112, 60, bright or 2.6
    sl.Color = WARM
    sl.Shadows = shadow == true
    sl.Parent = h
    -- 光柱：一条朝镜头的光带，从灯口到地面越来越宽、越来越淡
    local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
    a0.Position, a1.Position = V(0, 0, 0), V(0, -LY + 0.8, 0)
    a0.Parent, a1.Parent = h, h
    local b = Instance.new("Beam")
    b.Attachment0, b.Attachment1 = a0, a1
    b.Width0, b.Width1 = 4, 34
    b.FaceCamera = true
    b.Segments = 1
    b.LightEmission, b.LightInfluence = 1, 0
    b.Color = ColorSequence.new(WARM)
    b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.86), NumberSequenceKeypoint.new(0.6, 0.94), NumberSequenceKeypoint.new(1, 1) })
    b.Parent = h
  end
  for k = 0, 6 do
    local z = Z0 + 20 + k * 40
    lamp(-44, z, false)
    lamp(44, z, false)
  end
  lamp(0, -24, true, 3)   -- 车头、车尾上方各一盏：带影子
  lamp(0, 16, true, 2.6)
  -- 补光：车两侧低处各两盏看不见的灯（夜里外面全黑，车身也得看得清）
  for _, p in ipairs({ { -30, 15, -26 }, { 30, 15, -26 }, { -32, 17, 30 }, { 32, 17, 30 } }) do
    local h = W("Fill", V(1, 1, 1), CF(p[1], p[2], p[3]), BLACK)
    h.Transparency = 1
    h.CastShadow = false
    local pl = Instance.new("PointLight")
    pl.Range, pl.Brightness = 46, 0.7
    pl.Color = RGB(236, 232, 220)
    pl.Parent = h
  end
  -- 空气里的灰：慢慢飘、被灯照亮
  local src = W("Dust", V(150, 1, 200), CF(0, 34, 16), BLACK)
  src.Transparency = 1
  src.CastShadow = false
  local em = Instance.new("ParticleEmitter")
  em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
  em.Color = ColorSequence.new(RGB(255, 244, 220))
  em.LightEmission = 0.7
  em.LightInfluence = 0
  em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.16), NumberSequenceKeypoint.new(1, 0.08) })
  em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.72), NumberSequenceKeypoint.new(0.8, 0.78), NumberSequenceKeypoint.new(1, 1) })
  em.Lifetime = NumberRange.new(12, 18)
  em.Rate = 10
  em.Speed = NumberRange.new(0.3, 0.9)
  em.SpreadAngle = Vector2.new(180, 180)
  em.Acceleration = V(0.05, -0.03, 0.04)
  em.RotSpeed = NumberRange.new(-20, 20)
  em.EmissionDirection = Enum.NormalId.Bottom
  em.Parent = src
end

---------------------------------------------------------------- 杂物

local function props(m)
  local function W(name, size, cf, color, mat, shape) return part(m, name, size, cf, color, mat, shape) end
  -- 油桶：立着的（两道箍、桶盖）、躺着的
  local function barrel(x, z, col, lying, yaw)
    if lying then
      local c = CF(x, 2.15, z) * ANG(0, yaw or 0, 0)
      W("Barrel", V(6.2, 4.3, 4.3), c, col, MAT.Metal, Enum.PartType.Cylinder)
      W("BarrelRing", V(0.3, 4.5, 4.5), c * CF(-1.4, 0, 0), RGB(40, 36, 32), MAT.Metal, Enum.PartType.Cylinder)
      W("BarrelRing", V(0.3, 4.5, 4.5), c * CF(1.4, 0, 0), RGB(40, 36, 32), MAT.Metal, Enum.PartType.Cylinder)
      return
    end
    W("Barrel", V(6.2, 4.3, 4.3), CF(x, 3.1, z) * UP, col, MAT.Metal, Enum.PartType.Cylinder)
    W("BarrelRing", V(0.3, 4.5, 4.5), CF(x, 1.9, z) * UP, RGB(40, 36, 32), MAT.Metal, Enum.PartType.Cylinder)
    W("BarrelRing", V(0.3, 4.5, 4.5), CF(x, 4.3, z) * UP, RGB(40, 36, 32), MAT.Metal, Enum.PartType.Cylinder)
    W("BarrelLid", V(0.12, 3.9, 3.9), CF(x, 6.25, z) * UP, RGB(60, 56, 52), MAT.Metal, Enum.PartType.Cylinder)   -- 盖子顶比桶顶高 0.11（原来只高 0.02）
  end
  barrel(-60, 44, RED)
  barrel(-55.2, 46.6, RED)
  barrel(-58.6, 50.4, RGB(138, 36, 30))
  barrel(-63.5, 49, RGB(34, 34, 36))
  barrel(-68, 38, RGB(104, 78, 48), true, 0.5)
  barrel(70, -52, OLIVE)
  barrel(74.6, -50, OLIVE)
  barrel(66, 118, RED)
  barrel(61.4, 120.6, RGB(34, 34, 36))
  barrel(-74, -84, RGB(60, 86, 120))
  barrel(-78.8, -81, RGB(60, 86, 120))
  -- 木箱、弹药箱：几堆
  local function crate(x, y, z, sx, sy, sz, yaw, col, mat)
    local c = CF(x, y + sy / 2, z) * ANG(0, yaw or 0, 0)
    W("Crate", V(sx, sy, sz), c, col or RGB(122, 98, 62), mat or MAT.WoodPlanks)
    W("CrateBand", V(sx + 0.2, 0.5, sz + 0.2), c * CF(0, sy / 2 - 0.6, 0), RGB(86, 68, 44), MAT.Wood)   -- 箍比箱子每面凸 0.1
    W("CrateBand", V(sx + 0.2, 0.5, sz + 0.2), c * CF(0, -sy / 2 + 0.6, 0), RGB(86, 68, 44), MAT.Wood)
  end
  crate(62, 0, 18, 7, 6, 7, 0.1)
  crate(69.5, 0, 20, 6, 5, 6, -0.2)
  crate(63, 6, 18.5, 5.5, 4.5, 5.5, 0.4)
  crate(66, 0, 27, 9, 3.4, 4.4, 0.05, OLIVE, MAT.Wood)
  crate(66.4, 3.4, 27.2, 9, 3.4, 4.4, 0.12, OLIVE, MAT.Wood)
  crate(-70, 0, 100, 8, 7, 8, 0.2)
  crate(-61, 0, 104, 6, 5, 6, -0.3)
  crate(-70.6, 7, 100.4, 6, 5, 6, 0.5)
  crate(-78, 0, 92, 9, 3.4, 4.4, 1.5, OLIVE, MAT.Wood)
  crate(30, 0, 128, 7, 6, 7, 0.3)
  crate(38, 0, 131, 6, 4.6, 6, -0.1)
  -- 托盘上码的弹药箱
  for i = 0, 1 do
    local px, pz = -40 + i * 15, 122
    W("Pallet", V(12, 0.7, 10), CF(px, 0.35, pz), RGB(134, 108, 70), MAT.WoodPlanks)
    for r = 0, 2 do
      for c = 0, 1 do
        W("AmmoBox", V(5.4, 1.9, 4.2), CF(px - 2.9 + c * 5.8, 1.7 + r * 1.95, pz + ((r % 2 == 0) and -2.3 or 2.2)), OLIVE, MAT.Metal)
        W("AmmoBox", V(5.4, 1.9, 4.2), CF(px - 2.9 + c * 5.8, 1.7 + r * 1.95, pz + ((r % 2 == 0) and 2.3 or -2.2)), RGB(66, 76, 50), MAT.Metal)
      end
    end
  end
  -- 轮胎：摞着的、靠墙立着的
  local function tires(x, z, n)
    for i = 0, n - 1 do
      W("Tire", V(2.1, 7, 7), CF(x + (i % 2) * 0.4, 1.05 + i * 2.12, z) * UP, RGB(24, 24, 26), MAT.Rubber, Enum.PartType.Cylinder)
      W("TireHub", V(2.3, 3.2, 3.2), CF(x + (i % 2) * 0.4, 1.05 + i * 2.12, z) * UP, RGB(58, 60, 58), MAT.Metal, Enum.PartType.Cylinder)   -- 轮毂比胎面两边各凸 0.1（原来 0.03）
    end
  end
  tires(66, -22, 4)
  tires(74, -17, 3)
  tires(72, -27, 2)
  for i = 0, 2 do
    W("Tire", V(2.1, 7, 7), CF(88.6, 3.5, -40 + i * 2.5) * ANG(0, math.pi / 2 + 0.12, 0), RGB(24, 24, 26), MAT.Rubber, Enum.PartType.Cylinder)
  end
  -- 工作台（台面、腿、台钳、一只红工具箱、一盏台灯）、工具柜、靠墙的货架
  do
    local c = CF(-91, 0, -44)
    W("BenchTop", V(7, 0.7, 22), c * CF(0, 5.4, 0), RGB(112, 88, 56), MAT.WoodPlanks)
    for _, d in ipairs({ { -3, -10.4 }, { 3, -10.4 }, { -3, 10.4 }, { 3, 10.4 } }) do W("BenchLeg", V(0.6, 5.1, 0.6), c * CF(d[1], 2.55, d[2]), STEEL, MAT.Metal) end
    W("BenchShelf", V(6.4, 0.4, 20.6), c * CF(0, 1.6, 0), RGB(70, 72, 74), MAT.Metal)
    W("Vice", V(1.6, 1.4, 2.2), c * CF(1.6, 6.45, -7), RGB(40, 60, 96), MAT.Metal)
    W("ViceJaw", V(1.8, 1, 0.5), c * CF(1.6, 7.3, -7.95), RGB(60, 62, 64), MAT.Metal)
    W("Toolbox", V(3, 2, 5.4), c * CF(-0.6, 6.75, 3), RED, MAT.Metal)
    W("ToolboxLid", V(3.1, 0.3, 5.5), c * CF(-0.6, 7.9, 3), RGB(120, 30, 26), MAT.Metal)
    W("Board", V(0.4, 9, 20), c * CF(-3.4, 11, 0), RGB(96, 76, 50), MAT.Wood)   -- 挂工具的板
    for i = 0, 6 do W("Tool", V(0.3, 2.2 + (i % 3) * 0.7, 0.5), c * CF(-3.1, 11.4 - (i % 2) * 1.6, -8 + i * 2.6), RGB(150, 152, 156), MAT.Metal) end
  end
  do
    local c = CF(-91.5, 0, -4)
    W("Cabinet", V(4.4, 9.4, 7.6), c * CF(0, 4.9, 0), RED, MAT.Metal)
    for i = 0, 4 do W("Drawer", V(0.2, 0.2, 7), c * CF(2.25, 1.6 + i * 1.7, 0), RGB(100, 26, 22), MAT.Metal) end
    for i = 0, 4 do W("Handle", V(0.3, 0.3, 3), c * CF(2.4, 2.3 + i * 1.7, 0), RGB(170, 172, 176), MAT.Metal) end
    for _, d in ipairs({ { -1.6, -3.2 }, { 1.6, -3.2 }, { -1.6, 3.2 }, { 1.6, 3.2 } }) do W("Caster", V(0.5, 0.9, 0.9), c * CF(d[1], 0.45, d[2]), BLACK, MAT.Rubber, Enum.PartType.Cylinder) end
  end
  do
    local c = CF(89, 0, 116)
    for _, dz in ipairs({ -14, 0, 14 }) do
      W("RackPost", V(0.7, 24, 0.7), c * CF(-3, 12, dz), RGB(40, 70, 110), MAT.Metal)
      W("RackPost", V(0.7, 24, 0.7), c * CF(3, 12, dz), RGB(40, 70, 110), MAT.Metal)
    end
    local rr = Random.new(23)
    for lv = 0, 3 do
      W("RackShelf", V(6.4, 0.5, 28.4), c * CF(0, 1 + lv * 7, 0), RGB(190, 110, 40), MAT.Metal)   -- 层板比立柱外皮缩进 0.15（原来差 0.05）
      for i = 0, 3 do
        if rr:NextNumber() < 0.8 then
          local h = rr:NextNumber(2.4, 5)
          W("RackBox", V(5, h, rr:NextNumber(4, 6)), c * CF(0, 1.25 + lv * 7 + h / 2, -10.5 + i * 7), (rr:NextNumber() < 0.5) and RGB(150, 122, 82) or OLIVE, MAT.Cardboard)
        end
      end
    end
  end
  -- 黄色的检修梯台：四条腿、平台、栏杆、一跑斜梯
  do
    local c = CF(60, 0, 76) * ANG(0, -0.2, 0)
    local Y = RGB(204, 160, 40)
    for _, d in ipairs({ { -5, -3.4 }, { 5, -3.4 }, { -5, 3.4 }, { 5, 3.4 } }) do W("StandLeg", V(0.6, 11, 0.6), c * CF(d[1], 5.5, d[2]), Y, MAT.Metal) end
    W("StandDeck", V(11, 0.5, 7.6), c * CF(0, 11, 0), RGB(72, 74, 76), MAT.DiamondPlate)
    -- 栏杆比立柱细、两头收在立柱里，立柱高过上面那道（原来同粗、端面和立柱侧面对齐，两道栏杆在角上顶面贴面）
    for _, d in ipairs({ { -5, -3.4 }, { 5, -3.4 }, { -5, 3.4 }, { 5, 3.4 } }) do W("StandPost", V(0.4, 4.6, 0.4), c * CF(d[1], 13.5, d[2]), Y, MAT.Metal) end
    W("StandRail", V(10, 0.24, 0.24), c * CF(0, 15.5, -3.4), Y, MAT.Metal)
    W("StandRail", V(10, 0.24, 0.24), c * CF(0, 13.4, -3.4), Y, MAT.Metal)
    W("StandRail", V(0.24, 0.24, 6.8), c * CF(5, 15.5, 0), Y, MAT.Metal)
    W("StandRail", V(0.24, 0.24, 6.8), c * CF(5, 13.4, 0), Y, MAT.Metal)
    W("StandBrace", V(10.2, 0.4, 0.4), c * CF(0, 4, -3.4) * ANG(0, 0, 0.5), Y, MAT.Metal)
    W("StandBrace", V(10.2, 0.4, 0.4), c * CF(0, 4, 3.4) * ANG(0, 0, -0.5), Y, MAT.Metal)
    for i = 0, 8 do W("StandStep", V(1.9, 0.3, 6.4), c * CF(-6.4 - i * 1.5, 10.4 - i * 1.22, 0), RGB(72, 74, 76), MAT.DiamondPlate) end
    for _, dz in ipairs({ -3.3, 3.3 }) do
      W("StandStringer", V(18, 0.5, 0.4), c * CF(-12.4, 5.5, dz) * ANG(0, 0, 0.683), Y, MAT.Metal)
      W("StandHand", V(18, 0.35, 0.35), c * CF(-12.4, 9.6, dz) * ANG(0, 0, 0.683), Y, MAT.Metal)
    end
  end
  -- 地上盘着的电缆：十四段拼一圈，拖出去一截。每段是圆柱（原来是方条：一圈的顶面同高、首尾压着，抢深度）
  local function coil(x, z, r, tailYaw)
    local n = 14
    for i = 0, n - 1 do
      local a0 = i / n * math.pi * 2
      local seg = W("Cable", V(2 * r * math.sin(math.pi / n) + 0.2, 0.36, 0.36), CF(x + math.cos(a0) * r, 0.2, z + math.sin(a0) * r) * ANG(0, -a0 - math.pi / 2, 0),
        RGB(20, 20, 22), MAT.Rubber, Enum.PartType.Cylinder)
      seg.CastShadow = false
    end
    local t = W("Cable", V(r * 3.4, 0.36, 0.36), CF(x, 0.2, z) * ANG(0, tailYaw, 0) * CF(0, 0, -r * 2.6) * ANG(0, math.pi / 2, 0), RGB(20, 20, 22), MAT.Rubber, Enum.PartType.Cylinder)
    t.CastShadow = false
  end
  coil(-33, 47, 6.5, 0.7)
  coil(31, -47, 5, 2.4)
  coil(-52, -30, 4, -0.5)
  -- 路锥：地沟四角；油壶、千斤顶小车
  local function cone(x, z)
    W("ConeBase", V(0.3, 2.6, 2.6), CF(x, 0.15, z) * UP, RGB(30, 30, 32), MAT.Rubber, Enum.PartType.Cylinder)
    W("Cone", V(1.4, 1.9, 1.9), CF(x, 1, z) * UP, RGB(226, 104, 30), MAT.Plastic, Enum.PartType.Cylinder)
    W("ConeBand", V(0.5, 1.5, 1.5), CF(x, 1.9, z) * UP, RGB(236, 236, 230), MAT.Plastic, Enum.PartType.Cylinder)
    W("Cone", V(1.1, 1, 1), CF(x, 2.7, z) * UP, RGB(226, 104, 30), MAT.Plastic, Enum.PartType.Cylinder)
  end
  cone(33, -9)
  cone(49, -9)
  cone(33, 61)
  cone(49, 61)
  for i = 0, 2 do
    W("JerryCan", V(1.2, 3, 2.3), CF(-51 + i * 1.6, 1.5, 53.5 + (i % 2) * 0.5) * ANG(0, 0.3 * i, 0), (i == 1) and RGB(60, 70, 48) or OLIVE, MAT.Metal)
    W("JerryCap", V(0.5, 0.4, 0.5), CF(-51 + i * 1.6, 3.2, 54.2 + (i % 2) * 0.5), RGB(30, 30, 30), MAT.Metal)
  end
  do
    local c = CF(-31, 0, 12) * ANG(0, 0.5, 0)
    W("Jack", V(3, 1, 7), c * CF(0, 0.9, 0), RED, MAT.Metal)
    W("JackArm", V(1.6, 0.8, 4.4), c * CF(0, 1.9, -0.6) * ANG(0.28, 0, 0), RGB(120, 30, 26), MAT.Metal)
    W("JackPad", V(0.4, 1.6, 1.6), c * CF(0, 2.7, -2.8) * UP, RGB(60, 62, 64), MAT.Metal, Enum.PartType.Cylinder)
    W("JackHandle", V(0.3, 0.3, 7.5), c * CF(0, 3.2, 5.4) * ANG(0.6, 0, 0), RGB(40, 40, 42), MAT.Metal)
    for _, d in ipairs({ { -1.7, -3 }, { 1.7, -3 }, { -1.7, 3 }, { 1.7, 3 } }) do W("JackWheel", V(0.5, 1, 1), c * CF(d[1], 0.5, d[2]), BLACK, MAT.Rubber, Enum.PartType.Cylinder) end
  end
end

local function build()
  local m = Instance.new("Model")
  m.Name = "HangarStage"
  BUILD_AT = ORIGIN
  shell(m)
  lights(m)
  props(m)
  model = m
end

---------------------------------------------------------------- 机场停机坪（看飞机、直升机时）
--   露天：一大片分缝的水泥坪、黄色滑行线和停机框、轮挡；背后一座大机库（波纹钢板墙、敞着的大门、里面暗）、
--   侧后方塔台（玻璃顶）、雷达罩、灯杆（夜里打光）、加油车、牵引车、导流墙、远处一道低山；天空就是游戏的天
local airModel = nil
local mode = "ground"
local APRON = { HX = 380, Z0 = -380, Z1 = 380, HY = 140 }
local function buildAir()
  local m = Instance.new("Model")
  m.Name = "HangarApron"
  BUILD_AT = ORIGIN_AIR
  local function W(name, size, cf, color, mat, shape) return part(m, name, size, cf, color, mat, shape) end
  local C1, C2, LINE = RGB(152, 150, 142), RGB(140, 138, 131), RGB(214, 176, 52)
  -- 水泥坪：大块拼起来（深浅两色错开），缝是细的深色条
  for i = -4, 3 do
    for k = -4, 3 do
      W("Apron", V(100, 2, 100), CF(i * 100 + 50, -1, k * 100 + 50), ((i + k) % 2 == 0) and C1 or C2, MAT.Concrete)
    end
  end
  -- 缝和线分两层（同厂房，用户 11-27「频闪」）：0 水泥坪 · 0.06 缝（横缝在纵缝那儿断开）· 0.12 黄线（拼着、不叠）——
  --   原来缝顶面 0.045、线顶面 0.08，横竖缝交叉处、线和线的角上面贴面
  local J1, J2 = 0.06, 0.12
  local function flat(name, sx, sz, x, z, top, color, mat)   -- 贴地的一块：从地面下 0.02 到 top
    return W(name, V(sx, top + 0.02, sz), CF(x, (top - 0.02) / 2, z), color, mat)
  end
  local JC = RGB(96, 94, 88)
  for i = -4, 4 do flat("Joint", 0.4, 800, i * 100, 0, J1, JC, MAT.Concrete) end
  for k = -4, 4 do
    for i = -4, 3 do flat("Joint", 99.6, 0.4, i * 100 + 50, k * 100, J1, JC, MAT.Concrete) end
  end
  -- 外面一圈更大的地面（远处的草和沙）
  W("Field", V(4000, 1, 4000), CF(0, -1.6, 0), RGB(124, 120, 98), MAT.Ground)
  -- 滑行线（黄）、停机框、机位号
  flat("TaxiLine", 1.2, 760, -60, 0, J2, LINE, MAT.SmoothPlastic)
  flat("TaxiLine", 299.4, 1.2, -210.3, -120, J2, LINE, MAT.SmoothPlastic)   -- 到竖的那条边上为止
  for _, e in ipairs({ { 0, -34 }, { 0, 34 }, { -34, 0 }, { 34, 0 } }) do
    local horiz = e[1] == 0   -- 横的两条通到角上，竖的两条夹在中间
    flat("StandBox", horiz and 69 or 1, horiz and 1 or 67, e[1], e[2], J2, LINE, MAT.SmoothPlastic)
  end
  flat("StandLead", 1, 90, 0, -80, J2, LINE, MAT.SmoothPlastic)
  for _, x in ipairs({ -4, 4 }) do W("Chock", V(1.4, 1.2, 2.4), CF(x, 0.6, -6), RGB(206, 164, 44), MAT.SmoothPlastic) end
  -- 背后的大机库：波纹钢板墙、拱顶（三段斜屋面）、敞开的大门里面暗
  --   钢板用 Metal：Enum.Material 里没有 CorrugatedSteel（原来写的它，搭到这儿就报错，停机坪整个搭不起来、看飞机时退回厂房）
  local HZ, CORR = 230, MAT.Metal
  W("HangarWallL", V(4, 70, 120), CF(-150, 35, HZ + 60), RGB(150, 156, 150), CORR)
  W("HangarWallR", V(4, 70, 120), CF(150, 35, HZ + 60), RGB(150, 156, 150), CORR)
  W("HangarBack", V(296, 70, 4), CF(0, 35, HZ + 120), RGB(140, 146, 140), CORR)   -- 夹在两面侧墙中间（原来两头插进侧墙、顶面贴面）
  W("HangarInside", V(296, 66, 2), CF(0, 33, HZ + 117), RGB(30, 32, 34), MAT.SmoothPlastic)
  W("HangarFloor", V(296, 0.4, 118), CF(0, 0.2, HZ + 60), RGB(70, 72, 72), MAT.Concrete)
  W("HangarHeader", V(304, 16, 6), CF(0, 78, HZ), RGB(120, 126, 122), CORR)
  for i, a in ipairs({ -0.32, 0, 0.32 }) do
    W("HangarRoof", V(108, 4, 130), CF((i - 2) * 100, 86 - math.abs(a) * 20, HZ + 60) * ANG(0, 0, a), RGB(110, 116, 112), CORR)
  end
  for _, x in ipairs({ -150, -50, 50, 150 }) do W("DoorPost", V(6, 70, 6), CF(x, 35, HZ), RGB(90, 94, 92), MAT.Metal) end
  local lamp = W("HangarLamp", V(200, 1, 2), CF(0, 64, HZ + 30), WARM, MAT.Neon)
  lamp.CastShadow = false
  -- 塔台（侧后方）：方塔身 + 玻璃顶 + 栏杆
  W("TowerBase", V(30, 90, 30), CF(-290, 45, 320), RGB(186, 182, 170), MAT.Concrete)
  W("TowerCab", V(40, 16, 40), CF(-290, 98, 320), RGB(60, 80, 84), MAT.Glass).Transparency = 0.25
  W("TowerRoof", V(44, 3, 44), CF(-290, 107.5, 320), RGB(70, 72, 72), MAT.Metal)
  W("TowerMast", V(1, 24, 1), CF(-290, 121, 320), RGB(60, 60, 60), MAT.Metal)
  -- 雷达罩、导流墙、加油车、牵引车
  W("RadarMast", V(4, 40, 4), CF(250, 20, 340), RGB(120, 120, 116), MAT.Metal)
  W("RadarDome", V(24, 24, 24), CF(250, 52, 340), RGB(230, 228, 220), MAT.SmoothPlastic, Enum.PartType.Ball)
  W("BlastWall", V(70, 18, 3), CF(200, 9, 60) * ANG(-0.35, 0, 0), RGB(120, 118, 112), MAT.Metal)
  W("FuelTruckBody", V(10, 9, 30), CF(-90, 5.5, 110), RGB(196, 196, 186), MAT.SmoothPlastic)
  W("FuelTruckCab", V(9.6, 8, 8), CF(-90, 5, 92), RGB(170, 40, 34), MAT.SmoothPlastic)   -- 比罐体窄一点（原来两个侧面和罐体侧面贴面）
  for _, z in ipairs({ 94, 114, 122 }) do
    for _, x in ipairs({ -95.5, -84.5 }) do W("Wheel", V(1.6, 3.4, 3.4), CF(x, 1.7, z) * UP * ANG(0, 0, math.pi / 2), BLACK, MAT.Rubber, Enum.PartType.Cylinder) end
  end
  W("Tug", V(9, 4, 12), CF(60, 2.4, -60), RGB(206, 164, 44), MAT.SmoothPlastic)
  -- 灯杆：四根，夜里往停机位打光
  for _, q in ipairs({ { -120, -120 }, { 120, -120 }, { -120, 140 }, { 120, 140 } }) do
    W("LightPole", V(2, 80, 2), CF(q[1], 40, q[2]), RGB(80, 82, 82), MAT.Metal)
    local head = W("LightHead", V(8, 3, 4), CF(q[1], 80, q[2]), RGB(60, 62, 62), MAT.Metal)
    local sl = Instance.new("SpotLight")
    sl.Face = Enum.NormalId.Bottom
    sl.Angle, sl.Range, sl.Brightness = 90, 160, 3
    sl.Color = WARM
    sl.Parent = head
  end
  -- 滑行道边灯（一排小蓝灯）
  for z = -360, 360, 40 do
    local l = W("EdgeLight", V(1, 1.4, 1), CF(-75, 0.7, z), RGB(70, 120, 255), MAT.Neon)
    l.CastShadow = false
  end
  -- 远处一道低山（只是背景）
  for i = -3, 3 do
    local h = 120 + (i % 3) * 50
    W("Hill", V(900, h, 500), CF(i * 800, h / 2 - 20, 2000 + (i % 2) * 300), RGB(150, 140, 116), MAT.Ground)
  end
  airModel = m
  BUILD_AT = ORIGIN
end

---------------------------------------------------------------- 镜头

local function camCF()
  local v = view
  local yaw = v.sy + math.sin(v.t * 0.11) * 0.03   -- 不动的时候也微微晃
  local pitch = v.sp + math.sin(v.t * 0.17) * 0.006
  local cp = math.cos(pitch)
  local tgt = v.sat
  local eye = tgt + V(math.sin(yaw) * cp, math.sin(pitch), math.cos(yaw) * cp) * v.sd
  local lim = LIM[mode] or LIM.ground
  local cf
  if mode == "air" then
    eye = V(math.clamp(eye.X, -APRON.HX, APRON.HX), math.clamp(eye.Y, lim.eye, APRON.HY), math.clamp(eye.Z, APRON.Z0, APRON.Z1))
    cf = ORIGIN_AIR * CFrame.lookAt(eye, tgt)
  else
    eye = V(math.clamp(eye.X, -HX + 8, HX - 8), math.clamp(eye.Y, lim.eye, HY - 10), math.clamp(eye.Z, Z0 + 8, Z1 - 8))   -- 别钻到墙外面
    cf = ORIGIN * CFrame.lookAt(eye, tgt)
  end
  if v.sshift ~= 0 then cf = cf * CF(v.sshift, 0, 0) end   -- 整备：镜头横着挪（车在画面里让到一边）
  return cf * ANG(v.stilt, 0, 0)   -- 镜头压低一点：车在画面里偏上（底下是阵容卡片）
end
local function wrapPi(a) return (a + math.pi) % (2 * math.pi) - math.pi end

---------------------------------------------------------------- 给 TechUI 的

-- 车摆在哪（底座系：原点在地面正中，车头朝 −Z）
function Stage.floorCF() return (mode == "air") and ORIGIN_AIR or ORIGIN end
-- 换场景："ground" 厂房（坦克、步战车……）/ "air" 机场停机坪（飞机、直升机）
function Stage.mode(k)
  k = (k == "air") and "air" or "ground"
  if k == mode then return end
  mode = k
  if k == "air" and not airModel then
    local ok, err = pcall(buildAir)
    if not ok then
      warn("[全面大战场] 停机坪没搭好：" .. tostring(err))
      BUILD_AT = ORIGIN
      mode = "ground"
      return
    end
  end
  if shown then
    if model then model.Parent = (mode == "ground") and workspace or nil end
    if airModel then airModel.Parent = (mode == "air") and workspace or nil end
  end
  if slot then slot:Destroy() slot = nil end   -- 车 / 飞机按新场景的原点重新摆（TechUI 接着 put）
  local lim = LIM[mode] or LIM.ground   -- 停机坪上从翼下往上看的那个俯仰，回厂房时夹回厂房的范围
  view.pitch = math.clamp(view.pitch, lim.p0, lim.p1)
  view.sp = math.clamp(view.sp, lim.p0, lim.p1)
end
function Stage.modeNow() return mode end

---------------------------------------------------------------- 轮廓高亮（整备：选中挂点上的弹琥珀、鼠标挂着的白色淡轮廓、改装对应的部位）
--   Roblox 一个画面最多同时画 31 个 Highlight（X 光一组组占掉不少：XrayOwn.lua），厂房里最多借 HL_MAX 个：
--   Stage.highlight(零件或模型, o) → 句柄（借完了返回 nil）；Stage.unhighlight(句柄) 还回去，不给句柄全部还；换车（put）、关机库时全部还
--   o：{ fill 填充色, fillT 填充透明度（默认 0.85）, line 描边色, lineT 描边透明度（默认 0）, front = true 隔着东西也画（默认被挡住的不画） }
local HL_MAX = 4
local hlPool = {}   -- [i] = { h = Highlight, used = 借出去了 }
local hlFolder = nil
local function hlRelease(e)
  e.used = false
  pcall(function()
    e.h.Enabled = false
    e.h.Adornee = nil
  end)
end
function Stage.highlight(obj, o)
  if typeof(obj) ~= "Instance" then return nil end
  o = o or {}
  local e = nil
  for _, x in ipairs(hlPool) do if not x.used then e = x break end end
  if not e then
    if #hlPool >= HL_MAX then return nil end
    if not hlFolder then
      hlFolder = Instance.new("Folder")
      hlFolder.Name = "StageHighlights"
    end
    local h = Instance.new("Highlight")
    h.Name = "StageHL" .. (#hlPool + 1)
    h.Enabled = false
    h.Parent = hlFolder
    e = { h = h, used = false }
    table.insert(hlPool, e)
  end
  local ok = pcall(function()
    local h = e.h
    h.FillColor = o.fill or Theme.C.WARN
    h.FillTransparency = o.fillT or 0.85
    h.OutlineColor = o.line or o.fill or Theme.C.WARN
    h.OutlineTransparency = o.lineT or 0
    h.DepthMode = o.front and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
    h.Adornee = obj
    h.Enabled = true
  end)
  if not ok then return nil end
  if hlFolder then hlFolder.Parent = shown and workspace or nil end
  e.used = true
  return e
end
function Stage.unhighlight(e)
  if e == nil then
    for _, x in ipairs(hlPool) do if x.used then hlRelease(x) end end
    return
  end
  for _, x in ipairs(hlPool) do if x == e and x.used then hlRelease(x) end end
end
function Stage.highlightsUsed()   -- 测试用：借出去几个
  local n = 0
  for _, x in ipairs(hlPool) do if x.used then n += 1 end end
  return n
end

-- 打开 / 关上。keep：关的时候镜头已经有人接手了——"all" 一点不动（开了主菜单：它有自己的场景和视场角）；
--   "type" 镜头类型不动、只把视场角还回去（坐进了车 / 飞机、在观战）；不给就整个还给游戏
function Stage.show(on, keep)
  local cam = workspace.CurrentCamera
  if on then
    if not model then
      local ok, err = pcall(build)
      if not ok then
        warn("[全面大战场] 机库厂房没搭好：" .. tostring(err))
        return false
      end
    end
    model.Parent = (mode == "ground") and workspace or nil
    if airModel then airModel.Parent = (mode == "air") and workspace or nil end
    if hlFolder then hlFolder.Parent = workspace end
    shown = true
    if cam then
      cam.CameraType = Enum.CameraType.Scriptable
      cam.FieldOfView = FOV
      cam.CFrame = camCF()
    end
  else
    if model then model.Parent = nil end
    if airModel then airModel.Parent = nil end
    Stage.unhighlight()   -- 关机库：借的高亮全部还回去
    if hlFolder then hlFolder.Parent = nil end
    view.fly = nil
    if shown and cam and keep ~= "all" then
      if keep ~= "type" then cam.CameraType = Enum.CameraType.Custom end
      cam.FieldOfView = 70
    end
    shown = false
  end
  return shown
end

function Stage.active() return shown end

-- 把一辆车（已经摆在 floorCF 上的模型）停进来；dims = { L, W, H }：镜头按车的大小退到合适的距离。
--   keep：同一辆只换了模型（存了新挂载）——镜头不动（整备里正看着某个挂点时不跳回全景）；借出去的高亮照样全还（原来的零件没了）
function Stage.put(m, dims, keep)
  Stage.unhighlight()
  if slot then
    slot:Destroy()
    slot = nil
  end
  if not (m and model) then
    if m then m:Destroy() end
    return
  end
  m.Parent = (mode == "air" and airModel) or model
  slot = m
  local L, Wd, H = (dims and dims.L) or 26, (dims and dims.W) or 12, (dims and dims.H) or 9
  view.base = math.clamp(math.max(L * 1.5, Wd * 2, H * 3.2) + 12, 40, 118)
  view.h = math.clamp(H * 0.3, 2, 6)
  view.dims = { L = L, W = Wd, H = H }
  if keep then return end
  view.dist = view.base
  view.at, view.fly, view.zmin, view.zmax = nil, nil, nil, nil
  view.tilt, view.shift = TILT0, 0
end
function Stage.model() return slot end   -- 停着的那辆（整备找挂点上的弹、做高亮）

function Stage.drag(dx, dy)
  view.fly = nil   -- 正在飞的镜头被拖动打断：从现在的位置接着跟手
  local lim = LIM[mode] or LIM.ground
  view.yaw -= dx * 0.006
  view.pitch = math.clamp(view.pitch + dy * 0.004, lim.p0, lim.p1)
end

function Stage.zoom(k)
  view.fly = nil
  view.dist = math.clamp(view.dist * (1 - 0.1 * k), view.zmin or view.base * 0.55, view.zmax or view.base * 1.5)
end

-- 镜头飞到一处（整备：进整备、点挂点、换页签；docs/style.md「动效」：0.55 秒、两头慢）：
--   o = { at 看向哪一点（底座系 Vector3，同 floorCF 的坐标：飞机的挂点 = CFrame.new(0, gearH, 0) * 挂点位置；不给是车正中）,
--     dist 离那一点多远（格；不给照现在的）, yaw 从哪个方向看（同 drag 的：0 从车尾、π/2 从右边（+X）、π 从车头、−π/2 从左边；按近的那一边转过去）,
--     pitch 俯仰（rad，正的从上往下；按场景夹：停机坪 −0.15～1.2，从翼下往上看 / 往下看机翼上面，厂房 0.03～0.8）, tilt 镜头往下压多少（rad，默认 −3.5°）,
--     shift 镜头往右挪几格（车在画面里往左让）, t 飞几秒（默认 Theme.T.cam；0 = 不缓动，交给平时的慢慢跟） }
--   飞的时候拖动、滚轮直接打断（从当时的位置接着跟手）；飞完以后照常能拖、能缩放（缩放的范围按这辆车）
function Stage.focus(o)
  o = o or {}
  local v = view
  local lim = LIM[mode] or LIM.ground
  local yaw = (o.yaw ~= nil) and (v.sy + wrapPi(o.yaw - v.sy)) or v.yaw
  local pitch = math.clamp((o.pitch ~= nil) and o.pitch or v.pitch, lim.p0, lim.p1)
  local dist = math.max(4, (o.dist ~= nil) and o.dist or v.dist)
  local at = (typeof(o.at) == "Vector3") and o.at or nil
  local tilt = (o.tilt ~= nil) and o.tilt or TILT0
  local shift = (o.shift ~= nil) and o.shift or 0
  v.yaw, v.pitch, v.dist, v.at, v.tilt, v.shift = yaw, pitch, dist, at, tilt, shift
  v.zmin, v.zmax = math.min(v.base * 0.55, dist), math.max(v.base * 1.5, dist)   -- 飞近了（挂点特写）以后滚轮从这里接着缩放，不先跳到整车的范围
  local t = (o.t ~= nil) and o.t or ((Theme.T and Theme.T.cam) or 0.55)
  if t > 0 then
    v.fly = { t0 = v.t, T = t, y0 = v.sy, p0 = v.sp, d0 = v.sd, a0 = v.sat, l0 = v.stilt, s0 = v.sshift }
  else
    v.fly = nil
  end
end
-- 回到这辆车的全景（put 以后那样）
function Stage.home(t)
  Stage.focus({ yaw = math.pi - 0.62, pitch = 0.15, dist = view.base, t = t })
end
-- 现在的镜头（整备、测试用）：yaw / pitch / dist / at 是要去的，sy / sp / sd / sat 是现在的；flying 还在飞
function Stage.viewState()
  local v = view
  return { yaw = v.yaw, pitch = v.pitch, dist = v.dist, at = v.at, sy = v.sy, sp = v.sp, sd = v.sd, sat = v.sat, tilt = v.stilt, shift = v.sshift,
    base = v.base, h = v.h, dims = v.dims, flying = v.fly ~= nil, mode = mode, lim = LIM[mode] }
end

-- 世界坐标 → 屏幕（整备的 3D 挂点标签每帧按它摆）：返回 视口像素的 Vector2（同 IgnoreGuiInset 的 ScreenGui：左上角 0, 0）、深度（格，在镜头前面是正的）、在不在画面里；
--   机库没开时返回 nil。挂在 TechUI 的 Root 里要除以它的 UIScale（G.hangarParts.vw × vh 是缩放后的画布）
function Stage.toScreen(p)
  if not shown or typeof(p) ~= "Vector3" then return nil, nil, false end
  local cam = workspace.CurrentCamera
  if not cam then return nil, nil, false end
  local ok, sp, on = pcall(function() return cam:WorldToViewportPoint(p) end)
  if not ok or not sp then return nil, nil, false end
  return Vector2.new(sp.X, sp.Y), sp.Z, on == true and sp.Z > 0
end
-- 底座系的一点 → 世界（飞机挂点：Stage.world(CFrame.new(0, gearH, 0) * 挂点位置)）
function Stage.world(p) return Stage.floorCF() * p end

function Stage.step(dt)
  if not shown then return end
  local cam = workspace.CurrentCamera
  if not cam then return end
  local v = view
  v.t += dt
  local want = v.at or V(0, v.h, 0)
  local F = v.fly
  if F then   -- Stage.focus：按缓动曲线从起点飞到终点（时间按秒算，不跟帧率走）
    local x = math.clamp((v.t - F.t0) / math.max(F.T, 1e-3), 0, 1)
    local e = Theme.ease and Theme.ease("cam", x) or x
    v.sy = F.y0 + (v.yaw - F.y0) * e
    v.sp = F.p0 + (v.pitch - F.p0) * e
    v.sd = F.d0 + (v.dist - F.d0) * e
    v.sat = F.a0:Lerp(want, e)
    v.sh = v.sat.Y
    v.stilt = F.l0 + (v.tilt - F.l0) * e
    v.sshift = F.s0 + (v.shift - F.s0) * e
    if x >= 1 then v.fly = nil end
  else
    local k = 1 - math.exp(-dt * 7)
    v.sy += (v.yaw - v.sy) * k
    v.sp += (v.pitch - v.sp) * k
    v.sd += (v.dist - v.sd) * k
    v.sh += (v.h - v.sh) * k
    v.sat = v.sat + (want - v.sat) * k
    v.stilt += (v.tilt - v.stilt) * k
    v.sshift += (v.shift - v.sshift) * k
  end
  if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end
  if cam.FieldOfView ~= FOV then cam.FieldOfView = FOV end
  cam.CFrame = camCF()
end

return Stage
