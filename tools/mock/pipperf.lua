-- 瞄准镜画中画的开销（模拟器，Lua 5.4，比真 Luau 慢一些）：python3 tools/mock/run.py tools/mock/pipperf.lua
--   开局几个机器人、开着镜左右扫：G.pipStep 每帧多少毫秒、后台生成地形每帧多少、克隆了多少块
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local G = T.boot()
G.Config.Bots.minPerTeam = 6
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 7901, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local C = T.C
local P = G.P[me]
T.actAs(me, "deploy", { primary = "m4", gadget = "medkit", throw = "grenade" }, P.team == "atk" and "fleet" or "camp")
R.run(3)
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
T.runUntil(function() local v = C.fps return v and v.optic and v.items[1] and v.items[1][1].ClassName == "MeshPart" end, 40)
-- 后台生成：量 frameConn 里 maintain 的时间（生成在 task 里跑，按 BUDGET 让出）
local t0 = os.clock()
T.runUntil(function() return C.pipReady and C.pipReady() end, 30)
print(string.format("画中画准备好：%.1f 秒（墙钟，含模拟器其它开销）", os.clock() - t0))
do
  local st0 = C.pipDebug()
  print("  ok", st0.ok, "busy", st0.busy, "far", st0.far, "lv1", st0.lv[1] and (st0.lv[1].cx .. "," .. st0.lv[1].cz) or "-", "lv2", st0.lv[2] and "有" or "-",
    "fpActive", tostring(C.fpActive), "started", tostring(st0.started))
  local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
  if hrp then print("  人在", hrp.Position) end
end
local step0 = C.pipStep
local acc, n, worst = 0, 0, 0
local slow = {}
C.pipStep = function(...)
  local a = os.clock()
  local r = step0(...)
  local d = os.clock() - a
  acc, n, worst = acc + d, n + 1, math.max(worst, d)
  if d > 0.01 then
    local _, _, _, _, dyn = C.pipDebug()
    local nd, np = 0, 0
    for _, e in pairs(dyn) do nd = nd + 1 np = np + #e.sp end
    slow[#slow + 1] = string.format("第 %d 帧 %.1f 毫秒（镜像 %d 个、%d 块零件）", n, d * 1000, nd, np)
  end
  return r
end
T.mouse(true, nil, nil, Enum.UserInputType.MouseButton2)
R.run(1)
local cam = R.workspace.CurrentCamera
-- 正前方摆一批东西压一压：30 个「人」（每个 16 块零件，放在 ClientFx：会动的，每帧镜像）、400 块墙（Map：静态的，按格子克隆）
local look, o = cam.CFrame.LookVector, cam.CFrame.Position
local right = cam.CFrame.RightVector
local fx = R.workspace:FindFirstChild("ClientFx")
for i = 1, 30 do
  local m = R.make("Model")
  m._p.Name = "Probe" .. i
  local base = o + look * (100 + i * 20) + right * ((i % 5) - 2) * 3
  for k = 1, 16 do
    local p = R.make("Part")
    p.Size, p.CFrame, p.Anchored = V3(1, 1, 1), CF(base + V3(0, k * 0.4, 0)), true
    p.Parent = m
  end
  m.Parent = fx
end
local map = R.workspace:FindFirstChild("Map")
for i = 1, 400 do
  local p = R.make("Part")
  p.Size, p.CFrame, p.Anchored = V3(6, 4, 1), CF(o + look * (200 + (i % 40) * 15) + right * (math.floor(i / 40) - 5) * 4 + V3(0, 2, 0)), true
  p.Parent = map
end
for i = 1, 120 do
  R.run(1 / 30)
end
local st = C.pipDebug()
local _, _, _, _, dynAll = C.pipDebug()
local nd, np = 0, 0
for _, e in pairs(dynAll) do nd = nd + 1 np = np + #e.sp end
print(string.format("G.pipStep：%d 帧，平均 %.2f 毫秒，最长 %.2f 毫秒；克隆的静态零件 %d 块，镜像 %d 个（%d 块零件）", n, acc / math.max(1, n) * 1000, worst * 1000, st.nClones, nd, np))
for _, l in ipairs(slow) do print("  慢：" .. l) end
check(n > 100 and acc / n < 0.004, "画中画每帧平均不到 4 毫秒（模拟器）")
T.summary()
