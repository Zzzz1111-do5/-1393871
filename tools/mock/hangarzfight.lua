-- 机库厂房、露天停机坪、主菜单场景「抢深度」（z-fighting）检查（用户 11-27「开始游戏的那个仓库有些频闪」）：
--   python3 tools/mock/run.py tools/mock/hangarzfight.lua [list]（list：每一类贴在一起的面都列出来，带位置）
--   频闪 = 两个朝向一样的面贴得太近，深度缓冲分不出谁在前面，镜头一晃（HangarStage 的镜头不动的时候也微微晃）前后来回换。
--   这里把三处场景搭出来的零件按世界坐标拆成面：方块的六个面、圆柱两头的圆面（按 24 边形算）、同轴同半径的圆柱侧面；
--   坐标先照 Roblox 存成 32 位浮点（大厅在 x = −100000：那里 x 只分得出 1/128 格）。两两找
--   「法线同向、两个平面离得 < 0.04 格、在平面上重叠（面积 > 0.001 平方格、宽过 0.02 格）」的对数，除掉两种看不见的：
--   · 背面：镜头能到的地方（各处场景 camCF 把镜头夹在里面的那个盒子）全在这个面的背后（贴地零件的底面、墙里那一面……）
--   · 压住：重叠的那一块整个压在第三个不透明方块底下、那个方块朝外的面离得够远（墙裙压顶盖住墙裙和端墙的顶面……）
--   两块半透明的一层叠一层（同向、离得 < 0.5 格、重叠）也算错：Roblox 按远近排半透明的谁先画，镜头一晃来回换，重叠那块颜色跳。
--   ① 机库厂房（HangarStage）+ 远处那圈平地（Scenery.lua 的 Ocean：镜头在大厅时这圈平地也跟到大厅）
--   ② 露天停机坪（HangarApron：出击阵容里选中飞机时 TechUI 调 Stage.mode("air")，这里直接调）
--   ③ 主菜单场景（MenuStage：机库顶栏「主菜单」）
--   ④ 远处那圈平地在各处场景最低的零件底下（不跟地面抢、不盖住厂房的检修地沟）
--   0.04～0.08 格之间的「挨得近」只打印；士兵手里的枪（ToolPreview，枪模型那边搭的）只打印、不算
local T = dofile(MOCK_DIR .. "/common.lua")
local R, Enum = T.R, T.Enum
local check = T.check
local LIST = TEST_ARGS:match("%f[%w]list%f[%W]") ~= nil

T.wtMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local RS = R.services.ReplicatedStorage
local Zones = R.require(RS:FindFirstChild("Zones"))
local me = T.join("P1", 9931, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
R.run(1)
T.leaveMenu()
R.run(1)
T.runUntil(function() return type(me:GetAttribute("Tree")) == "string" end, 20)   -- 科技树存档到了（出击阵容按它排）
R.run(0.5)
local C = T.C
local HS
R.as("client", function() HS = R.require(R.services.StarterPlayer:FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client"):FindFirstChild("HangarStage")) end)

---------------------------------------------------------------- 几何

local THR, NEAR, AREA, MINW = 0.04, 0.08, 1e-3, 0.02   -- MINW：重叠那一块窄过 0.02 格的不算（x = −100000 处 32 位浮点一格 0.0078，挨着的两块会被凑成压着一条缝）
-- 两块半透明的一层叠一层（离得 < 0.5 格、在平面上重叠）：Roblox 按零件远近给半透明的排先后，镜头一晃两块谁先画来回换，重叠那一块颜色跳（另一种闪）
local TWIN = 0.5
local function translucent(p) return p.Transparency > 0.001 and p.Transparency < 0.999 end
local function f32(x) return (string.unpack("<f", string.pack("<f", x))) end
local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function mul(a, k) return { a[1] * k, a[2] * k, a[3] * k } end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
local function unit(a)
  local m = math.sqrt(dot(a, a))
  return { a[1] / m, a[2] / m, a[3] / m }
end

-- 零件 → 位置、三根轴（世界）、尺寸，都照 Roblox 存成 32 位浮点
local function frameOf(p)
  local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = p.CFrame:GetComponents()
  local s = p.Size
  return {
    pos = { f32(x), f32(y), f32(z) },
    ax = { { f32(r00), f32(r10), f32(r20) }, { f32(r01), f32(r11), f32(r21) }, { f32(r02), f32(r12), f32(r22) } },
    size = { f32(s.X), f32(s.Y), f32(s.Z) },
  }
end

local function meshed(p)
  for _, c in ipairs(p:GetChildren()) do
    local k = c.ClassName
    if k == "SpecialMesh" or k == "BlockMesh" or k == "CylinderMesh" or k == "FileMesh" then return true end
  end
  return false
end

-- 收零件：只算 Part（MeshPart、带 SpecialMesh 的形状不是方块 / 圆柱）、看得见的（全透明的灯座、发射器托不算）
local function collect(list, root, deep)
  for _, p in ipairs(deep and root:GetDescendants() or root:GetChildren()) do
    if p.ClassName == "Part" and p.Transparency < 0.999 and not meshed(p) then list[#list + 1] = p end
  end
end

-- 一处场景：parts 零件，O 原点（世界），cam = { lo, hi } 镜头能到的盒子（相对原点）
local function analyze(label, parts, O, cam)
  local faces, cyls, covers = {}, {}, {}
  for idx, p in ipairs(parts) do
    local fr = frameOf(p)
    local P0, A, S = fr.pos, fr.ax, fr.size
    local function face(n, vs)
      for k, v in ipairs(vs) do vs[k] = { f32(v[1]), f32(v[2]), f32(v[3]) } end   -- 顶点也是 32 位（GPU 里按世界坐标算）
      local d = 0
      for _, v in ipairs(vs) do d = d + dot(n, v) end
      faces[#faces + 1] = { part = idx, n = n, vs = vs, d = d / #vs }
    end
    if p.Shape == Enum.PartType.Block then
      for a = 1, 3 do
        local b, c = a % 3 + 1, (a + 1) % 3 + 1
        for _, sg in ipairs({ -1, 1 }) do
          local n = mul(A[a], sg)
          local ctr = add(P0, mul(n, S[a] / 2))
          local hb, hc = mul(A[b], S[b] / 2), mul(A[c], S[c] / 2)
          face(n, { add(add(ctr, hb), hc), add(sub(ctr, hb), hc), sub(sub(ctr, hb), hc), sub(add(ctr, hb), hc) })
        end
      end
      if p.Transparency == 0 then covers[#covers + 1] = { part = idx, fr = fr } end
    elseif p.Shape == Enum.PartType.Cylinder then
      local r = math.min(S[2], S[3]) / 2
      for _, sg in ipairs({ -1, 1 }) do
        local n = mul(A[1], sg)
        local ctr = add(P0, mul(n, S[1] / 2))
        local vs = {}
        for k = 0, 23 do
          local th = k / 24 * math.pi * 2
          vs[#vs + 1] = add(ctr, add(mul(A[2], math.cos(th) * r), mul(A[3], math.sin(th) * r)))
        end
        face(n, vs)
      end
      cyls[#cyls + 1] = { part = idx, c = P0, a = A[1], half = S[1] / 2, r = r }
    end
  end
  -- 盖板的世界包围盒（先粗筛）
  for _, cv in ipairs(covers) do
    local lo, hi = { 1e18, 1e18, 1e18 }, { -1e18, -1e18, -1e18 }
    for k = 1, 3 do
      local e = 0
      for a = 1, 3 do e = e + math.abs(cv.fr.ax[a][k]) * cv.fr.size[a] / 2 end
      lo[k], hi[k] = cv.fr.pos[k] - e, cv.fr.pos[k] + e
    end
    cv.lo, cv.hi = lo, hi
  end
  local camLo, camHi = add(O, cam[1]), add(O, cam[2])
  local function seen(n, d)   -- 镜头盒子里有没有一处在这个面正面
    local m = 0
    for k = 1, 3 do m = m + math.max(n[k] * camLo[k], n[k] * camHi[k]) end
    return m > d + 1e-4
  end
  local function inside(fr, pt)
    local w = sub(pt, fr.pos)
    for a = 1, 3 do
      if math.abs(dot(w, fr.ax[a])) > fr.size[a] / 2 + 0.01 then return false end
    end
    return true
  end
  -- 平面上的凸多边形：Sutherland–Hodgman 裁剪求重叠、鞋带公式求面积
  local function area(poly)
    local s = 0
    for i = 1, #poly do
      local a, b = poly[i], poly[i % #poly + 1]
      s = s + a[1] * b[2] - a[2] * b[1]
    end
    return s / 2
  end
  local function ccw(poly)
    if area(poly) < 0 then
      local r = {}
      for i = #poly, 1, -1 do r[#r + 1] = poly[i] end
      return r
    end
    return poly
  end
  local function clip(subj, cp)
    local out = subj
    for i = 1, #cp do
      local a, b = cp[i], cp[i % #cp + 1]
      local inp = out
      out = {}
      if #inp == 0 then break end
      local function side(q) return (b[1] - a[1]) * (q[2] - a[2]) - (b[2] - a[2]) * (q[1] - a[1]) end
      local function cut(p1, p2)
        local s1, s2 = side(p1), side(p2)
        local t = s1 / (s1 - s2)
        return { p1[1] + (p2[1] - p1[1]) * t, p1[2] + (p2[2] - p1[2]) * t }
      end
      local s = inp[#inp]
      for _, e in ipairs(inp) do
        if side(e) >= 0 then
          if side(s) < 0 then out[#out + 1] = cut(s, e) end
          out[#out + 1] = e
        elseif side(s) >= 0 then
          out[#out + 1] = cut(s, e)
        end
        s = e
      end
    end
    return out
  end
  -- 法线分组（同一个转法的零件法线完全一样）
  local groups = {}
  for _, f in ipairs(faces) do
    local key = string.format("%d|%d|%d", math.floor(f.n[1] * 4096 + 0.5), math.floor(f.n[2] * 4096 + 0.5), math.floor(f.n[3] * 4096 + 0.5))
    local g = groups[key]
    if not g then
      g = { n = f.n, list = {} }
      groups[key] = g
    end
    g.list[#g.list + 1] = f
  end
  local pairsBad, pairsNear, pairsTrans = {}, {}, {}
  local hiddenBack, hiddenCover = 0, 0
  for _, g in pairs(groups) do
    local N = unit(g.n)
    local ref = (math.abs(N[1]) < 0.9) and { 1, 0, 0 } or { 0, 1, 0 }
    local u = unit(cross(N, ref))
    local v = cross(N, u)
    for _, f in ipairs(g.list) do
      local poly, lo1, hi1, lo2, hi2 = {}, 1e18, -1e18, 1e18, -1e18
      for _, q in ipairs(f.vs) do
        local w = sub(q, O)
        local x, y = dot(w, u), dot(w, v)
        poly[#poly + 1] = { x, y }
        lo1, hi1, lo2, hi2 = math.min(lo1, x), math.max(hi1, x), math.min(lo2, y), math.max(hi2, y)
      end
      f.poly, f.bb = ccw(poly), { lo1, hi1, lo2, hi2 }
    end
    table.sort(g.list, function(a, b) return a.d < b.d end)
    local L = g.list
    for i = 1, #L do
      local fi = L[i]
      local j = i + 1
      while j <= #L and L[j].d - fi.d < TWIN do
        local fj = L[j]
        local both = translucent(parts[fi.part]) and translucent(parts[fj.part])
        if fj.part ~= fi.part and dot(fi.n, fj.n) > 0.99999 and (L[j].d - fi.d < NEAR or both) then
          local a, b = fi.bb, fj.bb
          if a[1] < b[2] and b[1] < a[2] and a[3] < b[4] and b[3] < a[4] then
            local ov = clip(fi.poly, fj.poly)
            local ar = (#ov >= 3) and math.abs(area(ov)) or 0
            local wmin = 0
            if ar > AREA then
              local x0, x1, y0, y1 = 1e18, -1e18, 1e18, -1e18
              for _, q in ipairs(ov) do x0, x1, y0, y1 = math.min(x0, q[1]), math.max(x1, q[1]), math.min(y0, q[2]), math.max(y1, q[2]) end
              wmin = math.min(x1 - x0, y1 - y0)
            end
            if ar > AREA and wmin >= MINW then
              local sep = fj.d - fi.d
              if not seen(N, (fi.d + fj.d) / 2) then
                hiddenBack = hiddenBack + 1
              else
                -- 第三个不透明方块整个压住重叠的那一块，而且它朝外的面离这两个面够远
                local dm = (fi.d + fj.d) / 2
                local function at3(q) return add(add(O, add(mul(u, q[1]), mul(v, q[2]))), mul(N, dm - dot(N, O))) end
                local pts = {}
                local plo, phi = { 1e18, 1e18, 1e18 }, { -1e18, -1e18, -1e18 }
                for _, q in ipairs(ov) do
                  local base = at3(q)
                  local p1, p2 = add(base, mul(N, 0.015)), add(base, mul(N, THR + 0.02))
                  pts[#pts + 1] = p1
                  pts[#pts + 1] = p2
                  for k = 1, 3 do
                    plo[k], phi[k] = math.min(plo[k], p1[k], p2[k]), math.max(phi[k], p1[k], p2[k])
                  end
                end
                local covered = false
                for _, cv in ipairs(covers) do
                  if cv.part ~= fi.part and cv.part ~= fj.part and cv.lo[1] <= plo[1] + 0.01 and cv.hi[1] >= phi[1] - 0.01
                    and cv.lo[2] <= plo[2] + 0.01 and cv.hi[2] >= phi[2] - 0.01 and cv.lo[3] <= plo[3] + 0.01 and cv.hi[3] >= phi[3] - 0.01 then
                    local all = true
                    for _, pt in ipairs(pts) do
                      if not inside(cv.fr, pt) then all = false break end
                    end
                    if all then covered = true break end
                  end
                end
                if covered then
                  hiddenCover = hiddenCover + 1
                else
                  local na, nb = parts[fi.part].Name, parts[fj.part].Name
                  local rec = { a = fi.part, b = fj.part, sep = sep, area = ar, at = at3(ov[1]) }
                  rec.key = (na < nb) and (na .. " ~ " .. nb) or (nb .. " ~ " .. na)
                  if sep < NEAR then table.insert((sep < THR) and pairsBad or pairsNear, rec) end
                  if both then table.insert(pairsTrans, rec) end
                end
              end
            end
          end
        end
        j = j + 1
      end
    end
  end
  -- 同轴、同半径的圆柱侧面
  for i = 1, #cyls do
    for j = i + 1, #cyls do
      local c1, c2 = cyls[i], cyls[j]
      if c1.part ~= c2.part and math.abs(dot(c1.a, c2.a)) > 0.99999 and math.abs(c1.r - c2.r) < NEAR then
        local w = sub(c2.c, c1.c)
        local t = dot(w, c1.a)
        local perp = sub(w, mul(c1.a, t))
        if math.sqrt(dot(perp, perp)) < 0.01 then
          local ov = math.min(c1.half, t + c2.half) - math.max(-c1.half, t - c2.half)
          if ov > 0.01 then
            local na, nb = parts[c1.part].Name, parts[c2.part].Name
            local sep = math.abs(c1.r - c2.r)
            local rec = { a = c1.part, b = c2.part, sep = sep, area = ov * 2 * math.pi * c1.r, at = c1.c }
            rec.key = "侧面 " .. ((na < nb) and (na .. " ~ " .. nb) or (nb .. " ~ " .. na))
            table.insert((sep < THR) and pairsBad or pairsNear, rec)
          end
        end
      end
    end
  end
  -- 按零件名字归类打印
  local function show(list, what)
    local byKey, order = {}, {}
    for _, r in ipairs(list) do
      local k = byKey[r.key]
      if not k then
        k = { n = 0, minSep = 1e9, area = 0, ex = r }
        byKey[r.key] = k
        order[#order + 1] = r.key
      end
      k.n = k.n + 1
      k.area = k.area + r.area
      if r.sep < k.minSep then k.minSep, k.ex = r.sep, r end
    end
    table.sort(order, function(x, y) return byKey[x].area > byKey[y].area end)
    for i, key in ipairs(order) do
      if i > (LIST and 200 or 14) then
        print(string.format("      ……还有 %d 类", #order - i + 1))
        break
      end
      local k = byKey[key]
      local at = sub(k.ex.at, O)
      print(string.format("      %s：%d 对，最近 %.4f 格，重叠 %.2f 平方格（例：%.1f, %.2f, %.1f）", key, k.n, k.minSep, k.area, at[1], at[2], at[3]))
    end
    local _ = what
  end
  print(string.format("  %s：%d 个零件、%d 个面；贴在一起（< %.2f 格）%d 对，挨得近（%.2f～%.2f 格）%d 对，两块半透明叠着（< %.1f 格）%d 对；看不见的不算：背面 %d 对、压住 %d 对",
    label, #parts, #faces, THR, #pairsBad, THR, NEAR, #pairsNear, TWIN, #pairsTrans, hiddenBack, hiddenCover))
  if #pairsBad > 0 then
    print("    贴在一起的：")
    show(pairsBad)
  end
  if #pairsNear > 0 then
    print("    挨得近的（只打印）：")
    show(pairsNear)
  end
  if #pairsTrans > 0 then
    print("    两块半透明叠着的：")
    show(pairsTrans)
  end
  return #pairsBad, #pairsTrans
end

-- 远处那圈平地（Scenery.lua 的 Ocean）露着的块：顶面高、块数
local function farTop()
  local oc = R.workspace:FindFirstChild("Ocean")
  local top, n = nil, 0
  local list = {}
  for _, p in ipairs(oc and oc:GetChildren() or {}) do
    local y = p.CFrame.Position.Y
    if y > -1000 then
      top = y + p.Size.Y / 2
      n = n + 1
      list[#list + 1] = p
    end
  end
  return top, n, list
end
local function camZone()
  local c = R.workspace.CurrentCamera.CFrame.Position
  return Zones.of(c.X, c.Z)
end
-- 镜头到了这处场景（远处那圈平地按镜头所在的 2048 格子摆，镜头不在这儿时底下没有）
local function camAt(cf)
  return (R.workspace.CurrentCamera.CFrame.Position - cf.Position).Magnitude < 400
end
local function lowest(parts)
  local m = 1e18
  for _, p in ipairs(parts) do
    local fr = frameOf(p)
    local e = 0
    for a = 1, 3 do e = e + math.abs(fr.ax[a][2]) * fr.size[a] / 2 end
    m = math.min(m, fr.pos[2] - e)
  end
  return m
end
local function originOf(cf) return { cf.Position.X, cf.Position.Y, cf.Position.Z } end

---------------------------------------------------------------- ① 机库厂房

print("① 机库厂房（HangarStage）")
local hg = C.hangarGui
check(hg ~= nil and hg.Visible, "机库开着")
T.runUntil(function() return camAt(Zones.HANGAR) end, 10)
R.run(0.5)
check(camZone() == "lobby" and camAt(Zones.HANGAR), "镜头在厂房里（大厅那一块）")
local hm = R.workspace:FindFirstChild("HangarStage")
check(hm ~= nil, "厂房搭在 workspace 里")
local top, nTiles, tiles = farTop()
check(nTiles > 0, string.format("镜头在大厅：远处那圈平地露着 %d 块，顶面 %s 格高", nTiles, tostring(top)))
local hangarParts = {}
if hm then collect(hangarParts, hm, false) end
local sceneH = {}
for _, p in ipairs(hangarParts) do sceneH[#sceneH + 1] = p end
for _, p in ipairs(tiles) do sceneH[#sceneH + 1] = p end
local bad1, tr1 = analyze("厂房 + 远处平地", sceneH, originOf(Zones.HANGAR), { { -88, 2.4, -116 }, { 88, 52, 148 } })
check(bad1 == 0, "厂房里没有贴在一起抢深度的面（" .. bad1 .. " 对）")
check(tr1 == 0, "厂房里没有两块半透明一层叠一层的（" .. tr1 .. " 对）")
local lowH = lowest(hangarParts)
check(top ~= nil and top < lowH - 0.5, string.format("远处平地顶面 %s 在厂房最低的零件底面（地沟底 %.2f）底下", tostring(top), lowH))

---------------------------------------------------------------- ② 露天停机坪

print("② 露天停机坪（HangarApron）")
-- 选中飞机 / 直升机时 TechUI 调 Stage.mode("air")（模拟器里科技树存档的阵容是空的、按默认排全是地面车）：这里直接切
R.as("client", function() if HS and HS.mode then HS.mode("air") end end)
R.run(0.4)
local am0 = R.workspace:FindFirstChild("HangarApron")
local airOk = am0 ~= nil and am0.Parent == R.workspace and HS.modeNow() == "air"
check(airOk, "切到露天停机坪（Stage.mode(\"air\")）")
T.runUntil(function() return camAt(Zones.HANGAR_AIR) end, 10)
R.run(0.5)
check(camAt(Zones.HANGAR_AIR), "镜头在停机坪上")
local am = R.workspace:FindFirstChild("HangarApron")
local apronParts = {}
if am then collect(apronParts, am, false) end
top, nTiles, tiles = farTop()
local sceneA = {}
for _, p in ipairs(apronParts) do sceneA[#sceneA + 1] = p end
for _, p in ipairs(tiles) do sceneA[#sceneA + 1] = p end
local bad2, tr2 = analyze("停机坪 + 远处平地", sceneA, originOf(Zones.HANGAR_AIR), { { -380, 2.4, -380 }, { 380, 140, 380 } })
check(airOk and bad2 == 0, "停机坪上没有贴在一起抢深度的面（" .. bad2 .. " 对）")
check(tr2 == 0, "停机坪上没有两块半透明一层叠一层的（" .. tr2 .. " 对）")
local fieldBottom, apronBottom = 1e18, 1e18
for _, p in ipairs(apronParts) do
  if p.Name == "Field" or p.Name == "Apron" then
    local b = p.CFrame.Position.Y - p.Size.Y / 2
    if p.Name == "Field" then fieldBottom = math.min(fieldBottom, b) else apronBottom = math.min(apronBottom, b) end
  end
end
check(top ~= nil and #apronParts > 0 and top < math.min(fieldBottom, apronBottom) - 0.5,
  string.format("远处平地顶面 %s 在水泥坪（底 %.2f）、外圈地面（底 %.2f）底下", tostring(top), apronBottom, fieldBottom))
-- 切回厂房
R.as("client", function() if HS and HS.mode then HS.mode("ground") end end)
R.run(0.3)
local h2 = R.workspace:FindFirstChild("HangarStage")
check(h2 ~= nil and h2.Parent == R.workspace and R.workspace:FindFirstChild("HangarApron") == nil, "切回厂房：停机坪收起来")

---------------------------------------------------------------- ③ 主菜单场景

print("③ 主菜单场景（MenuStage）")
R.as("client", function() C.showMenu() end)
R.run(0.5)
local mm = R.workspace:FindFirstChild("MenuStage")
check(mm ~= nil and C.menuShown and C.menuShown(), "机库顶栏「主菜单」：主菜单和背后的场景开着")
T.runUntil(function() return camAt(Zones.MENU) end, 10)
R.run(0.5)
check(camAt(Zones.MENU), "镜头对着主菜单场景")
-- 士兵手里的枪是游戏里的枪模型（服务器放在 ReplicatedStorage.ToolPreview 的工具，WeaponModels 那边搭的）：不算主菜单场景的，单独列出来看看
local menuParts, rifleParts = {}, {}
local rifle = mm and mm:FindFirstChild("Rifle", true)
if mm then
  for _, p in ipairs(mm:GetDescendants()) do
    if p.ClassName == "Part" and p.Transparency < 0.999 and not meshed(p) then
      if rifle and p:IsDescendantOf(rifle) then rifleParts[#rifleParts + 1] = p else menuParts[#menuParts + 1] = p end
    end
  end
end
top, nTiles, tiles = farTop()
local sceneM = {}
for _, p in ipairs(menuParts) do sceneM[#sceneM + 1] = p end
for _, p in ipairs(tiles) do sceneM[#sceneM + 1] = p end
local MCAM = { { 1.95, 2.98, -11.5 }, { 2.45, 3.22, -11.5 } }
local bad3, tr3 = analyze("主菜单 + 远处平地", sceneM, originOf(Zones.MENU), MCAM)
check(bad3 == 0, "主菜单场景里没有贴在一起抢深度的面（" .. bad3 .. " 对）")
check(tr3 == 0, "主菜单场景里没有两块半透明一层叠一层的（" .. tr3 .. " 对）")
if #rifleParts > 0 then analyze("（只看看）士兵手里的枪（ToolPreview）", rifleParts, originOf(Zones.MENU), MCAM) end
local lowM = lowest(menuParts)
check(top ~= nil and top < lowM - 0.5, string.format("远处平地顶面 %s 在主菜单场景最低的零件底面（%.2f）底下", tostring(top), lowM))
T.leaveMenu()
R.run(0.5)

check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | ", 1, math.min(#R.errors, 3)))
T.summary()
