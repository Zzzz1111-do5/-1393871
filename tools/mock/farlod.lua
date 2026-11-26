-- 远景替身（用户 11-26「streaming 太出戏了……很多游戏用了这种优化技术但还是很丝滑能看到远方的场景」）：python3 tools/mock/run.py tools/mock/farlod.lua
--   ① 开服摆完地图：服务器把整栋流进流出的楼、大块地面记成替身清单（ReplicatedStorage.FarLod），楼打标签 FarLod
--   ② 客户端照清单摆替身；真楼在本机（模拟器整个世界都在）时替身都藏着
--   ③ 一栋楼流出去（InstanceRemoved）：它的替身出来，摆的地方、大小跟真楼对得上；不挡人、不挡射线、不投影子；流回来（InstanceAdded）替身又藏起
--   ④ 楼被炸没了：替身跟着去掉，以后流进流出都不再出来
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3 = T.R, T.V3
local check = T.check

R.workspace.StreamingEnabled = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady and G.farLodInfo ~= nil end, 900)
print("① 服务器的清单")
local info = G.farLodInfo or {}
local RS = R.services.ReplicatedStorage
local H = RS:FindFirstChild("FarLod")
check(H ~= nil and (info.models or 0) > 20, string.format("记了 %s 栋楼、%s 块大地面（%s 字，%s 段）", tostring(info.models), tostring(info.parts), tostring(info.bytes), tostring(info.chunks)))
local CS = R.services.CollectionService
local tagged = CS:GetTagged("FarLod")
check(#tagged == H:GetAttribute("Count"), "打了标签的数目 = 清单条数（" .. #tagged .. "）")

local me = T.join("P1", 8801, true)
local C = T.C
T.runUntil(function() return C.farLodStats and C.farLodStats().loaded end, 30)
print("② 客户端摆替身")
local st = C.farLodStats()
check(st.loaded and st.total == #tagged, string.format("替身 %d 个（清单 %d 条）", st.total, #tagged))
check(st.shown == 0, "真楼都在本机：替身都藏着（露出来的 " .. st.shown .. "）")

print("③ 一栋楼流出去 / 流回来")
-- 挑一栋带好几块零件的楼
local m = nil
for _, x in ipairs(tagged) do
  if x.ClassName == "Model" and #x:GetChildren() >= 3 then m = x break end
end
check(m ~= nil, "找到一栋楼（" .. tostring(m and m.Name) .. "）")
local id = m:GetAttribute("FarId")
R.as("client", function() CS:GetInstanceRemovedSignal("FarLod"):Fire(m) end)
R.run(0.1)
st = C.farLodStats()
local px = C.farLodProxy(id)
check(st.shown == 1 and px ~= nil and px.Parent ~= nil, "流出去：替身出来了（露出来的 " .. st.shown .. "）")
if px and px.Parent then
  -- 外框（所有零件八个角的轴对齐包围盒；模拟器没有 Model:GetBoundingBox）
  local function box(o)
    local lo, hi = V3(1e9, 1e9, 1e9), V3(-1e9, -1e9, -1e9)
    for _, p in ipairs(o:GetDescendants()) do
      if p:IsA("BasePart") and p.Transparency < 0.95 and p.Name ~= "Collision" then
        for _, sx in ipairs({ -0.5, 0.5 }) do for _, sy in ipairs({ -0.5, 0.5 }) do for _, sz in ipairs({ -0.5, 0.5 }) do
          local c = p.CFrame * V3(p.Size.X * sx, p.Size.Y * sy, p.Size.Z * sz)
          lo = V3(math.min(lo.X, c.X), math.min(lo.Y, c.Y), math.min(lo.Z, c.Z))
          hi = V3(math.max(hi.X, c.X), math.max(hi.Y, c.Y), math.max(hi.Z, c.Z))
        end end end
      end
    end
    return (lo + hi) / 2, hi - lo
  end
  local c0, s0 = box(m)
  local c1, s1 = box(px)
  local cf0, cf1 = { Position = c0 }, { Position = c1 }
  local dc = (cf0.Position - cf1.Position).Magnitude
  check(dc < math.max(6, s0.Magnitude * 0.25), string.format("替身摆在真楼的地方（中心差 %.1f 格，楼 %.0f×%.0f×%.0f）", dc, s0.X, s0.Y, s0.Z))
  local vol0, vol1 = s0.X * s0.Y * s0.Z, s1.X * s1.Y * s1.Z
  check(vol1 > vol0 * 0.35 and vol1 < vol0 * 1.6, string.format("替身的外框大小跟真楼差不多（%.0f / %.0f）", vol1, vol0))
  local okQ, nPart = true, 0
  for _, p in ipairs(px:GetDescendants()) do
    if p:IsA("BasePart") then
      nPart = nPart + 1
      if p.CanCollide or p.CanQuery or p.CanTouch or p.CastShadow or not p.Anchored then okQ = false end
    end
  end
  check(okQ and nPart > 0, "替身 " .. nPart .. " 块：不挡人、不挡射线、不投影子、不会掉")
end
R.as("client", function() CS:GetInstanceAddedSignal("FarLod"):Fire(m) end)
R.run(0.1)
check(C.farLodStats().shown == 0 and (px == nil or px.Parent == nil), "流回来：替身又藏起来")
-- 导入的写实楼：替身照原网格摆
local meshOk, meshN = nil, 0
for _, x in ipairs(tagged) do
  if x:GetAttribute("Imported") == true then
    local p2 = C.farLodProxy(x:GetAttribute("FarId"))
    for _, q in ipairs(p2 and p2:GetDescendants() or {}) do if q.ClassName == "MeshPart" then meshN = meshN + 1 end end
    meshOk = meshN > 0
    break
  end
end
if meshOk ~= nil then check(meshOk, "导入的写实楼：替身是原网格（" .. meshN .. " 块）") end

print("④ 楼被炸没了")
local g0 = C.farLodStats().gone
R.as("server", function() m:Destroy() end)
R.run(0.3)
st = C.farLodStats()
check(st.gone == g0 + 1, "服务器记了这一栋没了（" .. st.gone .. "）")
R.as("client", function() CS:GetInstanceRemovedSignal("FarLod"):Fire(m) end)
R.run(0.1)
check(C.farLodStats().shown == 0, "炸没了的楼：流出去也不再摆替身")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
