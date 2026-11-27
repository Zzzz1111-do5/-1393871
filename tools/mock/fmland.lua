-- 起飞、降落（模拟器）：python3 tools/mock/run.py tools/mock/fmland.lua [id=j10]
--   飞行物理（FlightModel，用户 11-26 晚「每个飞机要有不同的参数」）换上以后，在钢城自家跑道上真飞一遍起降：
--   ① 跑道头开加力：滑跑加速照推重比（战斗机几百米就到抬头速度），到 vRot 拉杆离地，离地后接着爬、起落架自己收
--   ② 3° 下滑道进近（起落架、襟翼放着，1.3 倍着陆构型的失速速度）：教官把航迹压向接地点，油门按速度调——接地不摔、下沉率不大，
--      落在跑道上，收油门自动刹车，在跑道上停住
--   （air.lua 里起降那段在召唤位那一步就断了：老代码一样断，起降一直没测到）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local ID = TEST_ARGS:match("id=(%w+)") or "j10"
local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end

T.mapName = "city"
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.allowInfantry = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 9811, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
R.run(1)
local C = T.C
local CFr = R.CFrame
if C.menuShown and C.menuShown() then C.menuEnter() end
T.runUntil(function() return G.round.phase == "battle" end, 400, 1 / 10)   -- 等开战（准备阶段转开战时客户端会重起一份飞行状态）
G.round.endsAt = (G.round.endsAt or 0) + 1e6   -- 模拟器里没有对手：开战阶段时间一到就判守方赢、回合结束、人全收回机库（后面全在旧状态上测）——这一局不结束
T.actAs(me, "deploy", "rifle", "base")
T.runUntil(function() return P.alive and P.char ~= nil end, 15)
R.run(1)
local Map = G.Map
local AF = Map.BASES.atk.airfield   -- 攻方跑道：东西向（FOB.lua airfield 沿基地的 x 轴铺）
local FM = R.require(R.services.ReplicatedStorage:FindFirstChild("FlightModel"))
local M = 2.8
local DT = 1 / 30
local function run(sec, each)
  local t = 0
  while t < sec - 1e-6 do
    R.run(DT)
    t = t + DT
    if each and each(t) then return t end
  end
  return t
end
local function gnd(x, z) return G.airSurface and G.airSurface(x, z) or math.max(Map.ground(x, z), 0) end

-- ① 起飞
print("① " .. ID .. "：跑道头开加力滑跑、到抬头速度拉杆离地")
local x0 = AF.x + AF.len / 2 - 150
local gy = gnd(x0, AF.z)
local AD = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs"))
local d = AD.get(ID)
local pos = V3(x0, gy + d.gearH, AF.z)
local jet = G.spawnAircraft("atk", ID, CFr.lookAt(pos, pos + V3(-1, 0, 0)), nil, P)
P.char:PivotTo(CF(pos.X, pos.Y, pos.Z + 12))
T.act("enterVeh", jet.id)
R.run(0.5)
local cerr = {}
local se0 = C.showError
C.showError = function(msg)   -- 客户端回调出错只写在红条上（init.client.lua 的 pcall 接住）：也收下来
  if #cerr < 5 then print("  客户端报错：" .. tostring(msg)) end
  table.insert(cerr, tostring(msg))
  if se0 then se0(msg) end
end
local st = C.fly
check(st ~= nil and st.pilot and st.ground == true and st.fmD ~= nil, "坐进停在跑道上的 " .. ID .. "（地上、有自己的飞行物理数据）")
if not st then T.summary() return end
C.flyMouseAim(false)
local D = st.fmD
local hasAB = D.Ta and D.Ta > D.Tm
st.thr = hasAB and 130 or 100
local p0 = st.cf.Position
local rollT, rollD, vLift = nil, nil, nil
local pulled = false
run(60, function(t)
  if not pulled and st.spd >= d.vRot then
    pulled = true
    T.key(Enum.KeyCode.S, true)
  end
  if not st.ground then
    rollT, rollD, vLift = t, (st.cf.Position - p0).Magnitude / M, st.spd / M
    return true
  end
end)
check(rollD ~= nil, string.format("离地了（滑跑 %s 米、%s 秒、离地速度 %s 米 / 秒，抬头速度 %.0f）", rollD and string.format("%.0f", rollD) or "?",
  rollT and string.format("%.1f", rollT) or "?", vLift and string.format("%.0f", vLift) or "?", d.vRot / M))
-- 照推重比估的滑跑距离：v² / 2a，a ≈ 推力 / 质量 − 滚动阻力（阻力在离地前不大，按一成估）——实测在它的 0.75～1.6 倍以内
if rollD then
  local m = C.flyMass and C.flyMass() or (D.m0 + D.fi)
  local T0 = FM.thrust(D, 1, hasAB and 1 or 0, 0.15, 1.2, 50)
  local a = T0 / m * 0.9 - 0.03 * 9.81
  local est = vLift ^ 2 / (2 * a)   -- 加速到离地速度的距离（抬头那几秒也在加速）
  check(rollD > est * 0.75 and rollD < est * 1.6, string.format("滑跑 %.0f 米：照推重比（%.2f）估 %.0f 米", rollD, T0 / (m * 9.81), est))
  local fighter = (D.nzP or 0) >= 6
  if fighter then check(rollD < 1200, string.format("战斗机滑跑一千二百米以内（%.0f 米）", rollD)) end
end
local yL = st.cf.Position.Y
-- 离地后接着带杆 2.5 秒（飞行员把机头拉到爬升姿态），再松杆：电传保持航迹接着爬
local back = false
run(2.5, function() if st.ground then back = true end end)
T.key(Enum.KeyCode.S, false)
local minAgl, gearUp = 1e9, false
run(8, function()
  local p = st.cf.Position
  minAgl = math.min(minAgl, p.Y - d.gearH - gnd(p.X, p.Z))
  if (st.gearWant or 1) < 0.5 then gearUp = true end
  if st.ground then back = true end
end)
check(not back, "离地以后没再落回跑道")
check(not st.crashed and st.cf.Position.Y > yL + 40 * M, string.format("离地后接着爬（10 秒爬了 %.0f 米，松杆后最低离地 %.0f 格）", (st.cf.Position.Y - yL) / M, minAgl))
check(gearUp, "爬过 15 米起落架自己收")

-- ② 降落：3° 下滑道
print("② 3° 下滑道进近、接地、刹停")
local TD = V3(AF.x + AF.len / 2 - 420, gnd(AF.x + AF.len / 2 - 420, AF.z), AF.z)   -- 东头的瞄准点（往西落）
local mass = C.flyMass and C.flyMass() or (D.m0 + 0.5 * D.fi)
local rho = FM.atmo(TD.Y / M)
local vsL = math.sqrt(2 * mass * 9.81 / (rho * D.S * (D.CLm + (D.flapCL or 0))))
local Vt = 1.3 * vsL * M
local dist0 = 5200
local glide = math.rad(3)
local start = TD + V3(dist0, dist0 * math.tan(glide) + d.gearH, 0)
local look = V3(-math.cos(glide), -math.sin(glide), 0)
local function place()
  st.ground = false
  st.cf = CFr.lookAt(start, start + look)
  st.vdir, st.spd, st.vel = look, Vt, look * Vt
  st.pr, st.rr, st.yr = 0, 0, 0
  st.thr, st.thrE = 60, 60
  st.kP, st.kR, st.kY = 0, 0, 0
  st.gear, st.gearWant, st.gearAuto = 1, 1, true
  st.flapK = 1
  G.moveEnt(jet, st.cf)
  jet.vel = st.vel
  jet.syncT, jet.syncSlack = os.clock(), 160
end
place()
C.flyMouseAim(true)
local sinkTD, tdPos, vTD, lastVy = nil, nil, nil, 0
local tLand = run(60, function()
  local p = st.cf.Position
  -- 教官：航迹压向接地点（低于 30 格以后只管对准跑道，下沉交给拉平）
  local aim = TD - p
  if p.Y - TD.Y < 30 then aim = V3(-1, -0.02, 0) end
  aim = aim.Unit
  st.aimYaw = math.atan2(-aim.X, -aim.Z)
  st.aimPitch = math.asin(clamp(aim.Y, -1, 1))
  -- 自动油门（测试里当飞行员）：按速度误差调
  st.thr = clamp(55 + (Vt - st.spd) / M * 4, 0, 100)
  if not st.ground then lastVy = st.vel.Y end
  if st.ground or st.crashed then
    sinkTD, tdPos, vTD = -lastVy, p, st.spd
    return true
  end
end)
check(not st.crashed and st.ground == true, string.format("接地了、没摔（%.1f 秒；进近速度 %.0f 米 / 秒 = 1.3 倍着陆构型失速速度）", tLand, Vt / M))
if tdPos then
  local onRwy = math.abs(tdPos.Z - AF.z) < AF.wid / 2 and math.abs(tdPos.X - AF.x) < AF.len / 2
  check(onRwy, string.format("落在跑道上（离中线 %.0f 格、离瞄准点 %.0f 格）", tdPos.Z - AF.z, tdPos.X - TD.X))
  check(sinkTD < 30, string.format("接地下沉率 %.1f 格 / 秒（30 以上判摔）", sinkTD))
  check(vTD < d.landMax, string.format("接地速度 %.0f 格 / 秒（着陆最快 %.0f）", vTD, d.landMax))
end
st.thr = 0
local tStop = run(40, function() return st.spd < 1 end)
local pe = st.cf.Position
check(st.spd < 1 and math.abs(pe.Z - AF.z) < AF.wid / 2 and math.abs(pe.X - AF.x) < AF.len / 2,
  string.format("收油门刹车，%.1f 秒停在跑道上（滑了 %.0f 米）", tStop, tdPos and (tdPos - pe).Magnitude / M or -1))
check(#R.errors == 0 and #cerr == 0, "没有报错：" .. table.concat(R.errors, " | ", 1, math.min(#R.errors, 3)) .. table.concat(cerr, " | ", 1, math.min(#cerr, 3)))
T.summary()
