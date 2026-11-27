-- 雪山（MapSnow.lua，用户 11-26 晚「我要求你做一个雪山地图 一定要做到极高质量」）：python3 tools/mock/run.py tools/mock/snow.lua
--   ① 开服定雪山：两边主基地、房子（导没导入模型都有，编号齐）、桥、交战区四周的墙；② 地形：谷底起伏、山脚的壳（体素只写一层、底下空）；
--   ③ 高度：山体高度图（飞机撞山、射线打到山上）、谷里没有山体伸进来；海上的冰岛：岛外是海、湖在高台上；
--   ④ 进服开打：客户端换成雪山，山体模型按摆法表在本机摆（假装导入一座）；⑤ 没有报错
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local typeof = R.typeof
local check = T.check

T.wtMode = true
T.mapName = "snow"
R.voxelLog = {}
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local Map = G.Map
print("① 开服")
check(G.mapId == "snow" and Map.SNOW == true, "开的是雪山（" .. tostring(G.mapId) .. "）")
check(G.fobParts and G.fobParts.atk ~= nil and G.fobParts.def ~= nil, "两边主基地（带跑道）都建了")
local sc = R.workspace:FindFirstChild("Map") and R.workspace.Map:FindFirstChild("Scenery")
local sf = sc and sc:FindFirstChild("Snow")
check(sf ~= nil, "雪山的东西都在 Map.Scenery.Snow 里")
local nb, ids = 0, {}
if sf and sf:FindFirstChild("Buildings") then
  for _, m in ipairs(sf.Buildings:GetChildren()) do
    local ci = m:GetAttribute("CityIdx")
    if ci then nb = nb + 1 ids[ci] = true end
  end
end
check(#Map.BLD > 80 and nb == #Map.BLD, string.format("房子都盖了、都带编号（%d / %d 座）", nb, #Map.BLD))
local ruins = 0
for _, b in ipairs(Map.BLD) do if b.ruin then ruins = ruins + 1 end end
check(ruins >= 20, "被打坏的房子 " .. ruins .. " 座（用户：再加点坏掉的屋子）")
check(sf and sf:FindFirstChild("Bridges") and #sf.Bridges:GetChildren() == #Map.BRIDGES and #Map.BRIDGES >= 3, "过河的地方都有桥（" .. #Map.BRIDGES .. " 座）")
local nw = 0
if sf and sf:FindFirstChild("Bounds") then
  for _, p in ipairs(sf.Bounds:GetChildren()) do
    if p.Transparency == 1 and p.CanCollide and not p.CanQuery then nw = nw + 1 end
  end
end
check(nw > 40, "交战区四周看不见的墙（" .. nw .. " 块：挡人挡车，射线穿得过）")
local dish = nil
for _, d in ipairs(sf and sf:GetDescendants() or {}) do if d:GetAttribute("Anim") == "spin" then dish = d break end end
check(dish ~= nil and typeof(dish:GetAttribute("Pivot")) == "Vector3", "雷达站的天线会转（Anim = spin）")

print("② 地形")
check(math.abs(Map.ground(0, 6656) - Map.PLAIN) < 0.01, "攻方基地是平的（" .. string.format("%.2f", Map.ground(0, 6656)) .. "）")
local lo, hi = 1e9, -1e9
for i = 0, 40 do
  local x, z = -2400 + i * 120, 1700 - i * 20
  if not Map.bldAt(x, z, 160) and not Map.onRoad(x, z, 60) and Map.riverDist(x, z) > 480 then
    local h = Map.ground(x, z)
    lo, hi = math.min(lo, h), math.max(hi, h)
  end
end
check(hi - lo > 45, string.format("谷底起伏（一条线上 %.0f～%.0f 格）：丘、梁、冲沟", lo, hi))
-- 坡：大多坦克爬得上，也有陡的（梁的陡面、冲沟、岩石包）
do
  local n, steep, wall = 0, 0, 0
  for x = -2800, 2800, 70 do
    for z = -5400, 5400, 90 do
      if Map.valleyD(x, z) < 0.95 and not Map.inBase(x, z, 200) then
        local sl = Map.slope(x, z)
        n = n + 1
        if sl > 0.3 then steep = steep + 1 end
        if sl > 0.85 then wall = wall + 1 end
      end
    end
  end
  -- （测试台的 math.noise 是另一套实现，起伏比游戏里的大一些：游戏里同样的统计是陡过 40° 的约 1%）
  check(steep / n > 0.06 and steep / n < 0.3 and wall / n < 0.06, string.format("坡：陡过 17° 的 %.0f%%，陡过 40°（上不去）的 %.1f%%", steep / n * 100, wall / n * 100))
end
check(Map.ground(Map.POINTS[2].x, Map.POINTS[2].z) > Map.ground(0, 0) + 40, string.format("雷达站（B）在台地上（%.0f 格，山村 %.0f 格）", Map.ground(Map.POINTS[2].x, Map.POINTS[2].z), Map.ground(0, 0)))
do   -- 据点都有高度（11-27：原来没写 p.y，占领数人、客户端判断在不在点里一减就报错）
  local bad = {}
  for _, p in ipairs(Map.POINTS) do
    if type(p.y) ~= "number" or math.abs(p.y - Map.ground(p.x, p.z)) > 0.01 then bad[#bad + 1] = p.id .. "=" .. tostring(p.y) end
  end
  check(#bad == 0, "据点都有高度 p.y（= 地面）" .. ((#bad > 0) and ("：不对的 " .. table.concat(bad, " ")) or ""))
end
do
  local L = Map.LAKE
  check(Map.inLake(L.x, L.z) and math.abs(Map.ground(L.x, L.z) - L.y) < 0.01 and L.y > Map.PLAIN + 20, string.format("湖在高台上（湖面 %.0f 格）", L.y))
  local hd = Map.ground(Map.POINTS[4].x, Map.POINTS[4].z)
  check(hd < L.y - 15, string.format("水电站（D）在坝下（%.0f 格，湖面 %.0f）", hd, L.y))
end
-- 海上的冰岛（用户 11-26 夜）：岛外是海，两侧往外落进海里
check(not Map.isLand(30000, 30000) and Map.ground(30000, 30000) < 0 and Map.isLand(0, 0), "岛外是海（" .. string.format("%.0f", Map.ground(30000, 30000)) .. " 格）")
do
  local k, L, M = Map.chunkKind(16384, 16384)
  check(k == "flat" and L == 0 and M == R.Enum.Material.Water, "外海按平的海铺（海水 + 海底）")
  local coast = nil
  for x = 3000, 9000, 40 do
    if not coast and Map.floorH(x, 2400) < 0 then coast = x end
  end
  check(coast ~= nil and coast < 7000, "往东走到海边（x = " .. tostring(coast) .. "）")
end
-- 找一处山脚的壳：谷边、山体模型盖着、比平地高很多
local sx, sz = nil, nil
for x = 4200, 6000, 64 do
  for z = -3000, 3000, 256 do
    local h = Map.voxelHeight(x, z)
    if not sx and Map.shellCol(x, z, h) and h > Map.PLAIN + 200 then sx, sz = x, z end
  end
end
check(sx ~= nil, "谷边找得到山脚（体素写成壳）" .. (sx and string.format("：(%d, %d) 高 %.0f", sx, sz, Map.voxelHeight(sx, sz)) or ""))
if sx then
  local x0, z0 = math.floor(sx / 256) * 256, math.floor(sz / 256) * 256
  local n0 = #R.voxelLog
  local v = G.World.writeChunk(R.workspace.Terrain, x0, z0)
  local calls, maxV = #R.voxelLog - n0, 0
  for i = n0 + 1, #R.voxelLog do maxV = math.max(maxV, R.voxelLog[i].v) end
  check(Map.hollowAt(x0, z0) and calls == 16, "山脚的块拆成 16 份写（" .. calls .. " 次 WriteVoxels）")
  local hmin, hmax = 1e9, -1e9
  for i = 0, 63 do
    for k = 0, 63, 7 do
      local h = Map.voxelHeight(x0 + i * 4 + 2, z0 + k * 4 + 2)
      hmin, hmax = math.min(hmin, h), math.max(hmax, h)
    end
  end
  local solid = 64 * 64 * math.ceil((hmax + 8) / 4)   -- 整块实心要写多少
  check(v < solid * 0.6, string.format("只写一层壳：%d 个体素（实心要 %d 个；这一块地面 %.0f～%.0f 格）", v, solid, hmin, hmax))
end
local mats = R.voxelMats or {}
check((mats.Snow or 0) > 0 and (mats.Grass or 0) == 0, "地面是雪（Snow " .. tostring(mats.Snow) .. "），没有草叶")

-- 打过仗的痕迹（用户 11-27）：弹坑、战壕挖在地形里，沙袋、铁丝网、篱笆、电线杆、木料堆、残骸都摆了
do
  local W = G.snowWar and G.snowWar()
  check(W and W.craters > 1500 and W.trenches >= 8 and W.wrecks >= 12 and W.parts > 1500,
    string.format("打过仗的痕迹：弹坑 %s 个、战壕 %s 条、残骸 %s 辆、零件 %s 个", tostring(W and W.craters), tostring(W and W.trenches), tostring(W and W.wrecks), tostring(W and W.parts)))
  local c = Map.CRATERS[1]
  local dh, mud = Map.warAt(c[1], c[2])
  check(dh < -1 and mud and Map.material(c[1], c[2], Map.ground(c[1], c[2]), 0) == R.Enum.Material.Ground, string.format("弹坑挖下去了（%.1f 格），坑底露泥", dh))
  local nT = 0
  for x = -2600, 2600, 23 do for z = -5000, 5000, 97 do if Map.onTrack(x, z) then nT = nT + 1 end end end
  check(#Map.TRACKS > 40 and nT > 50, "田野里的履带辙（" .. #Map.TRACKS .. " 条）")
end
print("③ 高度：山体")
local pk, px = 0, 0
for x = 3000, 12000, 250 do
  local h = Map.ground(x, -800)
  if h > pk then pk, px = h, x end
end
check(pk > 800, string.format("谷边的山（x = %d 一带 %.0f 格高）", px, pk))
local nHit = 0
for z = -6000, 6000, 1500 do
  for _, sx in ipairs({ -1, 1 }) do
    local hit = Map.rayGround(V3(0, 700, z), V3(sx * 30000, 0, 0))
    if hit and math.abs(hit.X) > 2500 and Map.ground(hit.X, hit.Z) > Map.PLAIN + 300 then nHit = nHit + 1 end
  end
end
check(nHit >= 12, "谷里往东西两边平飞，多数撞到谷边的山上（" .. nHit .. " / 18）")
do   -- 谷里（交战区）没有山体模型伸进来：山体都比地面低（埋在地下）
  local bad, n = 0, 0
  for x = -3000, 3000, 150 do
    for z = -9000, 9000, 150 do
      if Map.valleyD(x, z) < 0.97 then
        n = n + 1
        local p = Map.peakH(x, z)
        if p and p > Map.floorH(x, z) + 2 then bad = bad + 1 end
      end
    end
  end
  check(bad == 0, string.format("谷里没有山体伸进来（%d 处查过，%d 处伸进来）", n, bad))
end
check(Map.ground(0, 0) < Map.PLAIN + 20, "山村（C）还在谷底（" .. string.format("%.1f", Map.ground(0, 0)) .. "）")

print("④ 进服开打：客户端")
-- 假装导入了一座山体（icy）：照 SnowPeaksMeta 摆一套同名、同尺寸的块
local RS = R.services.ReplicatedStorage
local PM = R.require(RS:FindFirstChild("SnowPeaksMeta"))
local imp = RS:FindFirstChild("Imported") or R.Instance.new("Folder")
imp.Name = "Imported"
imp.Parent = RS
local pf = imp:FindFirstChild("Peaks") or R.Instance.new("Folder")
pf.Name = "Peaks"
pf.Parent = imp
local kf = R.Instance.new("Folder")
kf.Name = "icy"
for _, ch in ipairs(PM.icy.chunks) do
  local b = R.Instance.new("MeshPart")
  b.Name = "P_icy__" .. ch[1]
  b.Size = V3(ch[5], ch[6], ch[7])
  b.Parent = kf
end
kf.Parent = pf
-- 假装导入了冬季树包（models/scenery/winter.glb）里两块地面贴图的载体：带 SurfaceAppearance（贴图已经上传成资源）
local sc = imp:FindFirstChild("Scenery") or R.Instance.new("Folder")
sc.Name = "Scenery"
sc.Parent = imp
-- 云（models/snow/clouds.glb：三块切片）
do
  local f = R.Instance.new("Folder")
  f.Name = "cloud"
  for _, k in ipairs({ "X", "Y", "Z" }) do
    local b = R.Instance.new("MeshPart")
    b.Name = "N_cloud__" .. k
    b.Size = V3(1, 1, 1)
    b.Parent = f
  end
  f.Parent = sc
end
for i, key in ipairs({ "snowtex", "slushtex", "skyft", "skybk", "skylf", "skyrt", "skyup", "skydn", "moontex", "suntex" }) do
  local f = R.Instance.new("Folder")
  f.Name = key
  local b = R.Instance.new("MeshPart")
  b.Name = "N_" .. key .. "__Body"
  local sa = R.Instance.new("SurfaceAppearance")
  sa.ColorMap = "rbxassetid://" .. (100 + i)
  sa.NormalMap = "rbxassetid://" .. (200 + i)
  sa.Parent = b
  b.Parent = f
  f.Parent = sc
end
local me = T.join("P1", 9901, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
T.leaveMenu()
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
R.run(1)
local C = T.C
check(C.Map and C.Map.id == "snow", "客户端也换成雪山（" .. tostring(C.Map and C.Map.id) .. "）")
T.runUntil(function() local s = C.snowPeaksStats and C.snowPeaksStats() return s and s.queued == 0 end, 120, 1 / 10)
local st = C.snowPeaksStats and C.snowPeaksStats()
local nIcy = 0
for _, I in ipairs(Map.PEAKS) do if I.key == "icy" then nIcy = nIcy + 1 end end
check(st and st.want > 400, "要摆的山体块（" .. tostring(st and st.want) .. " 块）")
check(st and st.placed == nIcy * #PM.icy.chunks, string.format("导入了的那座（icy）全摆了：%d 块（%d 座 × %d 块）", st and st.placed or -1, nIcy, #PM.icy.chunks))
local miss = st and table.concat(st.missing, "、") or ""
check(st and #st.missing == 2 and not miss:find("icy"), "没导入的两座记着缺（" .. miss .. "）")
-- 摆的位置：挑一块，模型坐标转回去应该落在那座山的高度图上
local fol = R.workspace:FindFirstChild("SnowPeaks")
local ok, bad = 0, 0
for _, p in ipairs(fol and fol:GetChildren() or {}) do
  if p.CanCollide == false and p.CanQuery == false and p.Anchored then ok = ok + 1 else bad = bad + 1 end
end
check(ok > 0 and bad == 0, "山体块不挡人、不挡射线（" .. ok .. " 块）")

-- 地面雪贴图（冬季树包的雪）、下雪
check(C.snowLookApplied and C.snowLookApplied() == 2 and R.overrides.Snow == "WinterSnow" and R.overrides.Ground == "WinterSlush",
  "地形的雪、泥地换成冬季树包的贴图（Snow → " .. tostring(R.overrides.Snow) .. "，Ground → " .. tostring(R.overrides.Ground) .. "）")
local mv = R.services.MaterialService:FindFirstChild("WinterSnow")
check(mv ~= nil and mv.ColorMap == "rbxassetid://101" and mv.NormalMap == "rbxassetid://201" and mv.BaseMaterial == R.Enum.Material.Snow, "WinterSnow 用的是导入的贴图（颜色、法线）")
check(C.snowFallOn and C.snowFallOn(), "在下雪")
local sky = R.services.Lighting:FindFirstChildOfClass("Sky")
local L = R.services.Lighting
local on0 = C.snowSkyOn and C.snowSkyOn()
check(on0 and sky and sky.MoonTextureId == "rbxassetid://109" and sky.SunTextureId == "rbxassetid://110", "月亮换成木卫三、太阳换成 The Sun（" .. tostring(sky and sky.MoonTextureId) .. "）")
-- 天黑了挂银河天空盒、天亮换回去（DayNight 在走钟：这里直接拨钟看）
R.workspace:SetAttribute("DayFix", 23)   -- 钟点钉在半夜（DayClock 认这个属性，DayNight 照着拨 Lighting.ClockTime）
R.run(1.5)
local fNight = sky and sky.SkyboxFt
R.workspace:SetAttribute("DayFix", 12)
R.run(1.5)
local fDay = sky and sky.SkyboxFt
R.workspace:SetAttribute("DayFix", nil)
check(fNight == "rbxassetid://103" and fDay ~= "rbxassetid://103", "夜里是银河天空盒（" .. tostring(fNight) .. "），白天换回原来的（" .. tostring(fDay) .. "）")
-- 云：这个测试里人还在机库（镜头在大厅那块，不摆云）——按镜头在岛上空走几拍
for _ = 1, 8 do if C.snowCloudTick then C.snowCloudTick(V3(0, 900, 2000)) end end
local cs = C.snowCloudStats and C.snowCloudStats()
check(cs and cs.imported and cs.puffs > 400 and cs.live > 20, string.format("天上的云：%s 朵，镜头附近摆了 %s 朵（建了 %s 次、%s 拍、摆过 %s 朵，镜头 %s）", tostring(cs and cs.puffs), tostring(cs and cs.live),
  tostring(cs and cs.builds), tostring(cs and cs.ticks), tostring(cs and cs.spawned), tostring(cs and cs.cam)))
-- 树：冬季树包的树、灌木，谷里也有（交战区里撞得倒的）
local inValley, shrubs = 0, 0
for _, t in ipairs(Map.TREES) do
  if Map.valleyD(t.x, t.z) < 0.9 then inValley = inValley + 1 end
  if t.k:sub(1, 2) == "ws" then shrubs = shrubs + 1 end
end
check(#Map.TREES > 8000 and inValley > 1500 and shrubs > 1000, string.format("树 %d 棵（谷里 %d，灌木 %d）", #Map.TREES, inValley, shrubs))
check(C.snowWrecks and C.snowWrecks() > 30, "车辆残骸摆出来了（" .. tostring(C.snowWrecks and C.snowWrecks()) .. " 个零件）")
print("⑤ 没有报错")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
