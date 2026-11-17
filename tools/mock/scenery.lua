-- 地图实景测试（模拟器）：python3 tools/mock/run.py tools/mock/scenery.lua [v]
--   路网（路面平顺、土路材质、能开车）→ 花草树木摆放（不长在路上、压平的场地、工事旁边、海滩）→ 客户端按距离摆（近处完整的树、中距离简化版、远处公告板、草）→
--   镜头挪走再回来：对象池复用，不会越摆越多 → 导入了模型包：用原模型（假装导入：按元数据摆几块 N_<键>__<块>）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check

-- 假装在 Studio 里导入了模型包的一部分：冷杉 fir1（两块）、草丛 grass_s（两块）
local RS = R.services.ReplicatedStorage
local META_SRC
do
  local f = assert(io.open(SRC_DIR .. "/ReplicatedStorage/SceneryMeta.lua"))
  META_SRC = f:read("a")
  f:close()
end
local META = load(META_SRC)()
local fakeAt = V3(5000, 0, 5000)   -- 导入的模型被 Studio 摆在哪都行：按元数据找回原点
local function fakeImport(key)
  local m = META[key]
  for _, pm in ipairs(m.parts) do
    local p = R.Instance.new("MeshPart")
    p.Name = "N_" .. key .. "__" .. pm.name
    p.Size = V3(pm.s[1], pm.s[2], pm.s[3])
    p.CFrame = CF(fakeAt.X + m.o[1] + pm.c[1], fakeAt.Y + m.o[2] + pm.c[2], fakeAt.Z + m.o[3] + pm.c[3])
    p.Parent = R.services.Workspace
  end
end
fakeImport("fir1")
fakeImport("grass_s")

local G = T.boot()
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 120)
local Map = G.Map

print("① 路网")
check(#Map.ROADS >= 8, "路 " .. #Map.ROADS .. " 条")
local worst, onGround, total = 0, 0, 0
for _, r in ipairs(Map.ROADS) do
  -- 沿路按弧长每 4 格取一点
  local pts, acc = { { r.x[1], r.z[1] } }, 0
  for i = 1, #r.x - 1 do
    local ax, az, bx2, bz2 = r.x[i], r.z[i], r.x[i + 1], r.z[i + 1]
    local L = math.sqrt((bx2 - ax) ^ 2 + (bz2 - az) ^ 2)
    local t = 4 - acc
    while L > 0 and t <= L do
      table.insert(pts, { ax + (bx2 - ax) * t / L, az + (bz2 - az) * t / L })
      t = t + 4
    end
    acc = (L > 0) and (L - (t - 4)) or acc
  end
  local prev
  for _, p in ipairs(pts) do
    local h = Map.height(p[1], p[2])
    if prev then worst = math.max(worst, math.abs(h - prev) / 4) end
    prev = h
    total = total + 1
    if Map.material(p[1], p[2], h, Map.slope(p[1], p[2])) == T.Enum.Material.Ground then onGround = onGround + 1 end
  end
end
check(worst < 0.8, string.format("路面最陡 %.0f°（车能开上去：< 39°）", math.deg(math.atan(worst))))
check(onGround / total > 0.95, string.format("路面是土路材质：%.0f%%", onGround / total * 100))

print("② 花草树木摆在哪")
local Flora = R.require(RS.Flora)
local bad = { road = 0, flat = 0, beach = 0, fort = 0 }
local n = { tree = 0, bush = 0, rock = 0, grass = 0, flower = 0 }
local forts = {}
for _, f in ipairs(R.require(RS.FortDefs).layout(Map)) do table.insert(forts, f.cf.Position) end
for cz = -36, -12 do
  for cx = -22, 22, 2 do
    for _, layer in ipairs({ "tree", "bush", "rock", "grass", "flower" }) do
      for _, it in ipairs(Flora.cell(cx, cz, layer)) do
        n[layer] = n[layer] + 1
        local rd, _, rw = Map.roadNear(it.x, it.z)
        if rd and rd < rw * 0.5 + 1 then bad.road = bad.road + 1 end
        if Map.flatW(it.x, it.z) > 0.31 then bad.flat = bad.flat + 1 end
        if Map.height(it.x, it.z) < 3.5 then bad.beach = bad.beach + 1 end
        if layer == "tree" then
          for _, p in ipairs(forts) do if (V3(p.X, 0, p.Z) - V3(it.x, 0, it.z)).Magnitude < 25 then bad.fort = bad.fort + 1 end end
        end
      end
    end
  end
end
check(n.tree > 500 and n.grass > 2000 and n.flower > 100, string.format("抽样的格子里：树 %d、灌木 %d、石头 %d、草丛 %d、花丛 %d", n.tree, n.bush, n.rock, n.grass, n.flower))
check(bad.road == 0, "没有长在路面上的：" .. bad.road)
check(bad.flat == 0, "没有长在压平的场地里的：" .. bad.flat)
check(bad.beach == 0, "没有长在海滩、水里的：" .. bad.beach)
check(bad.fort == 0, "工事旁边没有树：" .. bad.fort .. "（工事 " .. #forts .. " 处）")

print("③ 客户端按距离摆")
local me = T.join("P1", 5001, true)
R.run(1)
local C = T.C
check(C.sceneryUpdate ~= nil, "客户端有摆花草树木的模块")
check(RS:FindFirstChild("Imported") and RS.Imported:FindFirstChild("Scenery") and RS.Imported.Scenery:FindFirstChild("fir1"), "导入的模型包收进了 Imported.Scenery")
-- 找一片林子：从岛中间往外找树最密的格子
local best, bx, bz = 0, 0, 0
for cz = -34, -14, 2 do
  for cx = -18, 18, 2 do
    local k = #Flora.cell(cx, cz, "tree")
    if k > best then best, bx, bz = k, (cx + 0.5) * Flora.CELL, (cz + 0.5) * Flora.CELL end
  end
end
local cam = R.services.Workspace.CurrentCamera
local gy = Map.ground(bx, bz)
cam.CFrame = CF(bx, gy + 6, bz)
local t0 = os.clock()
for _ = 1, 40 do R.as("client", function() C.sceneryUpdate(1000) end) end
local dt = os.clock() - t0
local st = C.sceneryStats
check(st.live > 300, string.format("林子里（x %.0f z %.0f，一格 %d 棵）摆出来 %d 株，生成了 %d 个、算了 %d 格（模拟器里 %.1f 秒）", bx, bz, best, st.live, st.made, st.cells, dt))
local folder = R.services.Workspace:FindFirstChild("Scenery")
local parts, collide, query, mesh = 0, 0, 0, 0
local kinds = {}
for _, p in ipairs(folder:GetChildren()) do
  if p.CFrame.Position.Y > -1000 then
    parts = parts + 1
    if p.CanCollide then collide = collide + 1 end
    if p.CanQuery then query = query + 1 end
    if p.ClassName == "MeshPart" then mesh = mesh + 1 end
  end
end
check(parts > 300 and collide == 0 and query == 0, string.format("看得见的零件 %d 个，都不挡人（%d）、不挡子弹（%d）", parts, collide, query))
check(mesh > 0, "导入了的冷杉、草丛用原模型（MeshPart " .. mesh .. " 块）")
do
  local near, mid, far, grass = 0, 0, 0, 0
  for k, v in pairs(st.byKey) do
    if k:match("_m$") then mid = mid + v elseif k:match("_f$") then far = far + v
    elseif k:match("^grass") or k == "flowers" or k == "weeds" then grass = grass + v else near = near + v end
  end
  print(string.format("    近处完整的树和灌木石头 %d、中距离简化版 %d、远处公告板 %d、草丛花丛 %d；全换成原模型共 %.1f 万个三角形", near, mid, far, grass, st.tris / 1e4))
  local top = {}
  for k, v in pairs(st.byKey) do table.insert(top, { k, v, v * ((META[k] and META[k].tris) or 0) }) end
  table.sort(top, function(a, b) return a[3] > b[3] end)
  local s2 = {}
  for i = 1, math.min(8, #top) do s2[#s2 + 1] = string.format("%s×%d=%.0f万", top[i][1], top[i][2], top[i][3] / 1e4) end
  print("    最占三角形的：" .. table.concat(s2, "，"))
  check(st.tris < 2.6e6, "原模型的三角形总数不超过 260 万")
end
local D = C.sceneryDist
check(D.near < D.mid and D.mid < D.far and D.grass < D.near, string.format("距离：近 %.0f、中 %.0f、远 %.0f、草 %.0f 格", D.near, D.mid, D.far, D.grass))

print("④ 镜头挪走再回来：对象池复用")
local made0 = st.made
cam.CFrame = CF(bx + 900, gy + 6, bz)
for _ = 1, 40 do R.as("client", function() C.sceneryUpdate(1000) end) end
cam.CFrame = CF(bx, gy + 6, bz)
for _ = 1, 40 do R.as("client", function() C.sceneryUpdate(1000) end) end
local live1 = st.live
cam.CFrame = CF(bx + 900, gy + 6, bz)
for _ = 1, 40 do R.as("client", function() C.sceneryUpdate(1000) end) end
cam.CFrame = CF(bx, gy + 6, bz)
for _ = 1, 40 do R.as("client", function() C.sceneryUpdate(1000) end) end
check(math.abs(st.live - live1) <= live1 * 0.02, string.format("回到原地摆的一样多（%d / %d）", st.live, live1))
check(st.made < made0 * 3, string.format("模型生成了 %d 个（第一次 %d），来回挪不会越生越多", st.made, made0))

print("⑤ 正常跑几秒（每帧步骤）")
R.run(3)

print("⑥ 远海：跟着镜头铺到雾的尽头；地形海水那一片里不摆（不和地形水面打架）")
local Map = G.Map
check(Map.K and Map.K > 1 and Map.R >= 6144, string.format("地图放大 %.1f 倍，地形范围 ±%d 格", Map.K or 1, Map.R))
check(Map.PLAY > Map.R * 2 and Map.SEA_LIM > Map.R, string.format("飞机作战区 ±%d 格（约 %.1f 公里）、船能开到 ±%d 格", Map.PLAY, Map.PLAY / 2.8 / 1000, Map.SEA_LIM))
cam.CFrame = CF(0, 300, 0)
R.run(0.2)
local n0 = C.oceanTiles()
cam.CFrame = CF(Map.PLAY - 500, 900, 300)
R.run(0.2)
local n1 = C.oceanTiles()
check(n0 == 49 - 36 and n1 == 49, string.format("岛上空：远海 %d 块（地形海水外面一圈）；飞到作战区边上：%d 块（四周全是海）", n0, n1))
local ocean = R.services.Workspace:FindFirstChild("Ocean")
local far = 0
for _, p in ipairs(ocean and ocean:GetChildren() or {}) do far = math.max(far, math.abs(p.Position.X - cam.CFrame.Position.X)) end
check(far > 5200 + 1024, string.format("远海铺到镜头外 %.0f 格（雾 5200 格就看不见了）", far))
T.summary()
