-- 会转的履带（模拟器）：python3 tools/mock/run.py tools/mock/tracks.lua
--   用户 11-25「坦克履带也要能动」：原模型（假装导入了 T-72B3）外面贴一串履带板（Tracks.lua，轮廓 TrackLoops），
--   ① 镜头附近的履带车有履带板（左右两条、下面一段 + 上面一段）
--   ② 车往前开：履带板相对车身在走（下面一段往后、上面一段往前），贴地那段相对地面基本不动
--   ③ 原地左转：右边（外侧）往前走、左边往后走
--   ④（11-26「坦克履带动画也有 bug」）整圈连着走：一帧里没有哪块板跳一大截（原来走到头一下跳回另一头）、相邻两块间距一样（原来有个空档跟着走）
--   ⑤ 槽位会回收：最多 8 辆有履带板，开远了的 2 秒后让出来，后来的坦克也有（原来一占就不放，开一会儿新坦克履带全不动）
--   ⑥（11-26「履带 bug 是坦克同时有两副履带，一副会动」）原模型自己的履带块（TrackLoops 的 trk）在履带板出来时藏起来、
--     开远了板收起来时放回来；履带板连成一整条（板缝里不露底下那副）；履带和车身一块网格的车（豹 2A7V）什么都不藏、照样有履带板
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
local RS = R.services.ReplicatedStorage
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local KEY = "t72b3"
local nFake = T.fakeImport(KEY)
check(nFake > 0, "假装导入了 " .. KEY .. " 的原模型（" .. nFake .. " 块）")
local KEY2 = "leo2a7v"   -- 履带和车身是一块网格：藏不掉，只能盖住
T.fakeImport(KEY2)
local me = T.join("P1", 8101, true)
R.run(2)
local C = T.C
local TL = R.require(RS:FindFirstChild("TrackLoops"))
check(TL[KEY] ~= nil and #TL[KEY].pts >= 8, KEY .. " 量好了履带轮廓")
local VD = R.require(RS:FindFirstChild("VehDefs"))
local cam = R.workspace.CurrentCamera
local cp = cam.CFrame.Position
local Map = G.Map
local def = VD.get(KEY)
local x0, z0 = cp.X + 40, cp.Z
local e = G.newVehicle("def", KEY, G.vehBaseAt(def, x0, z0, V3(0, 0, -1)))
R.run(1.5)
cam.CFrame = CF(x0 + 30, Map.height(x0, z0) + 12, z0 + 30)
R.run(0.5)
local v = C.views and C.views[e.model]
local links = {}
if v and v.model then
  for _, p in ipairs(v.model:GetDescendants()) do if p.Name == "TrackLink" then table.insert(links, p) end end
end
print("  （原模型 " .. tostring(v and v.M and v.M.imported) .. "，履带板 " .. #links .. " 块）")
check(#links >= 40, "镜头附近的履带车有履带板（" .. #links .. " 块）")
if #links == 0 then T.summary() return end

print("⑥ 原模型自己的履带块藏起来（不然看着是两副履带）")
local function origState(vv, key)
  local trk = TL[key].trk or {}
  local hid, tot = 0, 0
  for _, nm in ipairs(trk) do
    local q = vv.model:FindFirstChild("V_" .. key .. "__" .. nm)
    if q then
      tot = tot + 1
      if q.Transparency >= 0.99 then hid = hid + 1 end
    end
  end
  return hid, tot, #trk
end
do
  local hid, tot, n = origState(v, KEY)
  check(n > 0 and tot == n and hid == tot, string.format("%s：原来的履带块（%s）有履带板时都藏起来了（%d / %d）", KEY, table.concat(TL[KEY].trk or {}, "、"), hid, n))
  local sh = C.tracksShape(KEY)
  check(sh ~= nil and type(TL[KEY].loop) == "table" and sh.total > 30, string.format("整圈按原履带块的外轮廓走（一圈 %.1f 格）", sh and sh.total or 0))
  check(links[1].Size.Z >= sh.sp * 0.95, string.format("履带板连成一整条：板长 %.2f、节距 %.2f（原来板长只有节距的 0.74，缝里露出不动的原履带）", links[1].Size.Z, sh.sp))
  local w = TL[KEY].bxo - TL[KEY].bxi
  check(links[1].Size.X >= w, string.format("履带板比原履带宽（%.2f ≥ %.2f）", links[1].Size.X, w))
end

print("② 往前开")
local function rel(p) return v.hullF:PointToObjectSpace(p.Position) end
local r0 = {}
for i, p in ipairs(links) do r0[i] = rel(p) end
local w0 = links[1].Position
local jump, prev = 0, {}
for i, p in ipairs(links) do prev[i] = rel(p) end
for k = 1, 30 do   -- 1 秒往前（−Z）开 10 格
  G.moveEnt(e, G.vehBaseAt(def, x0, z0 - k * (10 / 30), V3(0, 0, -1)))
  R.run(1 / 30)
  if k > 3 then   -- 头几帧还在起步
    for i, p in ipairs(links) do
      local q = rel(p)
      jump = math.max(jump, (q - prev[i]).Magnitude)
      prev[i] = q
    end
  else
    for i, p in ipairs(links) do prev[i] = rel(p) end
  end
end
local moved, back, fwd = 0, 0, 0
local _ = w0
for i, p in ipairs(links) do
  local d = rel(p) - r0[i]
  if d.Magnitude > 0.3 then moved = moved + 1 end
  if d.Z > 0.3 and r0[i].Y < 1 then back = back + 1 end   -- 下面一段（贴地）：相对车身往后（+Z）
  if d.Z < -0.3 and r0[i].Y > 2 then fwd = fwd + 1 end    -- 上面一段：往前（−Z）
end
check(moved > #links * 0.6, "开起来履带板在走（" .. moved .. " / " .. #links .. " 块动了）")
check(back > 4, "贴地那段相对车身往后走（" .. back .. " 块）")
check(TL[KEY].z0 == nil or fwd > 4, "上面一段往前走（" .. fwd .. " 块）")

check(jump < 0.75, string.format("整圈连着走：一帧里最多挪 %.2f 格（车速 10 格 / 秒，一帧 0.33 格；原来走到头一下跳十几格）", jump))
do   -- 相邻两块的间距（同一边按一圈的顺序排的）
  local sh = C.tracksShape and C.tracksShape(KEY)
  local nl = sh and sh.nl or (#links / 2)
  local mn, mx = math.huge, 0
  for side = 0, 1 do
    for i = 1, nl do
      local a, b = links[side * nl + i], links[side * nl + (i % nl) + 1]
      local d = (a.Position - b.Position).Magnitude
      mn, mx = math.min(mn, d), math.max(mx, d)
    end
  end
  print(string.format("  一圈 %.1f 格、每边 %d 块、间距 %.2f～%.2f 格", sh and sh.total or 0, nl, mn, mx))
  check(sh ~= nil and mx < sh.sp * 1.12 and mn > sh.sp * 0.55, string.format("相邻两块间距均匀（%.2f～%.2f，板距 %.2f）", mn, mx, sh and sh.sp or 0))
end

print("③ 原地左转")
local rs = {}
for i, p in ipairs(links) do rs[i] = rel(p) end
local zEnd = z0 - 10
for k = 1, 20 do
  local a = k * math.rad(2)
  G.moveEnt(e, G.vehBaseAt(def, x0, zEnd, V3(-math.sin(a), 0, -math.cos(a))))
  R.run(1 / 30)
end
local rightFwd, leftBack = 0, 0
for i, p in ipairs(links) do
  local d = rel(p) - rs[i]
  if rs[i].Y < 1 and rs[i].X > 0 and d.Z > 0.2 then rightFwd = rightFwd + 1 end   -- 右边贴地那段相对车身往后 = 履带往前转
  if rs[i].Y < 1 and rs[i].X < 0 and d.Z < -0.2 then leftBack = leftBack + 1 end
end
check(rightFwd > 2 and leftBack > 2, string.format("左转：右边往前、左边往后（%d / %d 块）", rightFwd, leftBack))

print("⑤ 槽位回收")
local function hasLinks(ent)
  local vv = C.views and C.views[ent.model]
  if not vv or not vv.model then return false end
  for _, p in ipairs(vv.model:GetDescendants()) do if p.Name == "TrackLink" and p.Transparency < 0.5 then return true end end
  return false
end
local camF = CF(x0 + 30, Map.height(x0, z0) + 12, z0 + 30)
local ents = { e }
for i = 1, 9 do   -- 再摆 9 辆，离镜头 50～190 格
  local xx, zz = x0 + 30 - 14 * i, z0 + 30 - 14 * i
  table.insert(ents, G.newVehicle("def", KEY, G.vehBaseAt(def, xx, zz, V3(0, 0, -1))))
end
for _ = 1, 20 do cam.CFrame = camF R.run(1 / 20) end
local n0 = 0
for _, en in ipairs(ents) do if hasLinks(en) then n0 = n0 + 1 end end
local _, nAct = C.tracksActive()
check(n0 == 8 and nAct == 8, string.format("十辆在镜头附近：最多 8 辆有履带板（%d 辆，占着 %d 个槽）", n0, nAct))
-- 有板的开走 5 辆（开到 1000 格外），等 3 秒：剩下的都该有板了
local gone, rest = 0, {}
for _, en in ipairs(ents) do
  if hasLinks(en) and gone < 5 then
    gone = gone + 1
    G.moveEnt(en, G.vehBaseAt(def, x0 + 1000 + gone * 30, z0 + 1000, V3(0, 0, -1)))
  else
    table.insert(rest, en)
  end
end
for _ = 1, 60 do cam.CFrame = camF R.run(1 / 20) end
local n1 = 0
for _, en in ipairs(rest) do if hasLinks(en) then n1 = n1 + 1 end end
local _, nAct2 = C.tracksActive()
check(n1 == #rest, string.format("开远了的让出槽位：留在镜头附近的 %d 辆都有履带板（%d 辆有，占着 %d 个槽）", #rest, n1, nAct2))
do   -- 开远了的：履带板收了，原来的履带放回来（远处看是原模型的履带，不是没履带）
  local back, cnt = 0, 0
  for _, en in ipairs(ents) do
    local vv = C.views and C.views[en.model]
    if vv and vv.model and not hasLinks(en) then
      cnt = cnt + 1
      local hid = origState(vv, KEY)
      if hid == 0 then back = back + 1 end
    end
  end
  check(cnt >= 5 and back == cnt, string.format("开远了的 %d 辆：原来的履带都放回来了（%d 辆）", cnt, back))
end
do   -- 履带和车身一块网格的（豹 2A7V）：什么都不藏、照样有履带板
  local def2 = VD.get(KEY2)
  local e2 = def2 and G.newVehicle("def", KEY2, G.vehBaseAt(def2, x0 + 20, z0 + 20, V3(0, 0, -1)))
  for _ = 1, 30 do cam.CFrame = camF R.run(1 / 20) end
  local vv = e2 and C.views and C.views[e2.model]
  local hidden = 0
  if vv and vv.model then
    for _, q in ipairs(vv.model:GetDescendants()) do
      if q:IsA("BasePart") and tostring(q.Name):match("^V_" .. KEY2 .. "__Body") and q.Transparency >= 0.99 then hidden = hidden + 1 end
    end
  end
  check(e2 ~= nil and vv ~= nil and vv.M and vv.M.imported == KEY2, KEY2 .. "：拼出来了（原模型）")
  check(TL[KEY2].trk == nil and hidden == 0, string.format("%s：履带和车身是一块网格，什么都不藏（藏了 %d 块）", KEY2, hidden))
  check(e2 ~= nil and hasLinks(e2), KEY2 .. "：照样有履带板（连成一条盖住原来的）")
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
