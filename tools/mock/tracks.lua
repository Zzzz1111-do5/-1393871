-- 会转的履带（模拟器）：python3 tools/mock/run.py tools/mock/tracks.lua
--   用户 11-25「坦克履带也要能动」：原模型（假装导入了 T-72B3）外面贴一串履带板（Tracks.lua，轮廓 TrackLoops），
--   ① 镜头附近的履带车有履带板（左右两条、下面一段 + 上面一段）
--   ② 车往前开：履带板相对车身在走（下面一段往后、上面一段往前），贴地那段相对地面基本不动
--   ③ 原地左转：右边（外侧）往前走、左边往后走
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

print("② 往前开")
local function rel(p) return v.hullF:PointToObjectSpace(p.Position) end
local r0 = {}
for i, p in ipairs(links) do r0[i] = rel(p) end
local w0 = links[1].Position
for k = 1, 30 do   -- 1 秒往前（−Z）开 10 格
  G.moveEnt(e, G.vehBaseAt(def, x0, z0 - k * (10 / 30), V3(0, 0, -1)))
  R.run(1 / 30)
end
local moved, back, fwd = 0, 0, 0
for i, p in ipairs(links) do
  local d = rel(p) - r0[i]
  if d.Magnitude > 0.3 then moved = moved + 1 end
  if d.Z > 0.3 and r0[i].Y < 1 then back = back + 1 end   -- 下面一段（贴地）：相对车身往后（+Z）
  if d.Z < -0.3 and r0[i].Y > 2 then fwd = fwd + 1 end    -- 上面一段：往前（−Z）
end
check(moved > #links * 0.6, "开起来履带板在走（" .. moved .. " / " .. #links .. " 块动了）")
check(back > 4, "贴地那段相对车身往后走（" .. back .. " 块）")
check(TL[KEY].z0 == nil or fwd > 4, "上面一段往前走（" .. fwd .. " 块）")

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
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
