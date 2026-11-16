-- 舰艇测试（模拟器）：python3 tools/mock/run.py tools/mock/navy.lua [v]
--   码头、舰艇生成点（泊位在深水里、终端柱在岸上）→ 守方在营地崖顶的终端柱生成 DDG-125、直接上舰桥 → 车钟、舵、开船（客户端算、服务器跟） →
--   舰炮跟着准星转、开火 → 反舰导弹框住敌舰、打沉 → 近防炮拦截来袭导弹 → 防空导弹打敌机 → 回码头补弹、修理 → 下船站到终端柱旁 →
--   攻方在登陆平台码头生成 055、下船站在码头上、再按 E 上船 → 爆炸按船体方块算距离 → 击沉（开船的人阵亡、名额冷却、客户端看船下沉）→
--   港口巡逻艇生成点要据点 C → AI 舰艇出来巡逻、开炮
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true   -- 工事先不开火（最后测 AI 舰艇时也不让岸防炮还手，免得测试里的船先被打沉）
G.navyNoAI = true    -- AI 舰艇最后再放出来
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 7001, true)
local foe = T.join("P2", 7002, false)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local function setTeam(pl, team)
  local P = G.P[pl]
  P.team = team
  pl.Team = G.TEAM[team]
  pl.Neutral = false
  pl:SetAttribute("Side", team)
  G.pushOne(P)
end
setTeam(me, "def")
setTeam(foe, "atk")
R.run(1)
local P, PF = G.P[me], G.P[foe]
local C = T.C
local Map = G.Map
local SD = R.require(R.services.ReplicatedStorage:FindFirstChild("ShipDefs"))
local function flat(v) return V3(v.X, 0, v.Z) end

print("① 码头、舰艇生成点")
local shipPads = {}
for _, p in ipairs(G.pads) do if p.kind == "ship" then shipPads[#shipPads + 1] = p end end
check(#shipPads == 8, "舰艇生成点 " .. #shipPads .. " 个（攻方 3、守方 4、港口 1）")
local piers = R.workspace.Map:FindFirstChild("Piers")
check(piers ~= nil and #piers:GetChildren() > 60, "码头零件 " .. (piers and #piers:GetChildren() or 0) .. " 个")
local wet, dry, built = 0, 0, 0
for _, p in ipairs(shipPads) do
  local d = SD.get(p.vid)
  local ok = true
  for _, o in ipairs({ { 0, -d.L / 2 }, { 0, d.L / 2 }, { d.W / 2, 0 }, { -d.W / 2, 0 }, { 0, 0 }, { d.W / 2, d.L / 2 }, { -d.W / 2, d.L / 2 } }) do
    local q = (p.base * CF(o[1], 0, o[2])).Position
    if Map.height(q.X, q.Z) > -d.draft * 0.35 then ok = false end
  end
  if ok then wet = wet + 1 else print("    浅水：" .. p.vid) end
  local ty = p.ty or Map.ground(p.term.X, p.term.Z)
  if ty >= 0.5 then dry = dry + 1 else print("    终端柱在水里：" .. p.vid) end
  if p.model and p.prompt then built = built + 1 end
end
check(wet == #shipPads, "泊位都在够深的水里（" .. wet .. "/" .. #shipPads .. "）")
check(dry == #shipPads, "终端柱都在岸上、码头上（" .. dry .. "/" .. #shipPads .. "）")
check(built == #shipPads, "终端柱、按键都摆好了")
-- 同一边的泊位两两不重叠（船体方块中心距离比两个半宽之和大）
local overlap = 0
for i = 1, #shipPads do
  for j = i + 1, #shipPads do
    local a, b = shipPads[i], shipPads[j]
    local da, db = SD.get(a.vid), SD.get(b.vid)
    local dd = flat(a.base.Position) - flat(b.base.Position)
    if math.abs(dd.X) < (da.W + db.W) / 2 + 2 and math.abs(dd.Z) < (da.L + db.L) / 2 then overlap = overlap + 1 end
  end
end
check(overlap == 0, "泊位互不重叠")
check(C.S.vehAvail and C.S.vehAvail.ship and C.S.vehAvail.ship.cap >= 0, "客户端拿到舰艇名额：" .. tostring(C.S.vehAvail and C.S.vehAvail.ship and C.S.vehAvail.ship.cap))

print("② 守方在营地出生，走到崖顶的舰艇终端柱按 E：DDG-125 生成在崖下码头，人直接上舰桥")
G.Config.VehicleCats.ship.min = 2   -- 测试只有两个人：名额按人数算是 0，这里放开
T.act("deploy", "rifle", "camp")
R.run(2)
check(P.alive and me.Character ~= nil, "守方在营地出生")
local pd = T.pad("ddg125")
local e = pd and T.usePad(me, pd)
check(e ~= nil and e.ship and e.sd.id == "ddg125", "生成了 DDG-125")
check(e ~= nil and e.driver == P and P.vehicle == e, "生成的人直接坐上舰桥")
R.run(1)
check(C.sail ~= nil and e ~= nil and C.sail.id == e.id, "客户端接管开船")
check(C.drive == C.sail, "步兵操作让出来（G.drive）")
local v
for em, vv in pairs(C.views or {}) do if e and em == e.model then v = vv end end
check(v ~= nil and v.M ~= nil and #v.M.items > 60, "客户端拼好了舰艇：" .. (v and v.M and #v.M.items or 0) .. " 个零件")
local nOk = 0
for id in pairs(SD.D) do
  local ok, M = pcall(C.buildShipModel, SD.get(id), "def")
  if ok and M and #M.items > 12 then
    nOk = nOk + 1
    M.model:Destroy()
  else
    print("    拼不出来：" .. id .. " " .. tostring(M))
  end
end
check(nOk == 7, "七型舰艇的模型都拼得出来（" .. nOk .. "/7）")

print("③ 开船：车钟加到前进四，往北开；左舵转向，松开回舵")
local p0 = e.root.CFrame.Position
for _ = 1, 4 do T.tap(Enum.KeyCode.W) end
R.run(0.2)
check(C.sail.order == 4, "车钟：" .. C.T("ship.order." .. C.sail.order))
R.run(10)
local p1 = e.root.CFrame.Position
local moved = (flat(p1) - flat(p0)).Magnitude
check(moved > 80, string.format("开出去 %.0f 格（服务器上的船跟着走）", moved))
check(p1.Z < p0.Z - 60, "朝北开（离开岸边）")
check((C.sail.pos - flat(p1)).Magnitude < 25, "客户端、服务器位置一致")
check(e.speed > 10 and math.abs(e.speed - C.sail.speed) < 6, string.format("航速 %.0f 格/秒（%s）", e.speed, C.T("ship.kn", math.floor(e.speed / 2.8 * 1.944))))
local yaw0 = C.sail.yaw
T.key(Enum.KeyCode.A, true)
R.run(5)
check(C.sail.rudder < -0.5, "舵打过去了")
T.key(Enum.KeyCode.A, false)
local dyaw = math.deg(C.sail.yaw - yaw0)
check(dyaw > 8, string.format("左舵转了 %.0f°", dyaw))
R.run(2)
check(math.abs(C.sail.rudder) < 0.3, "松开回正舵")
local st = C.sail

print("④ 开战：舰炮跟着准星转、开火")
T.runUntil(function() return G.round.phase == "battle" end, 60)
st.order = 0
st.camYaw, st.camPitch = st.yaw, -0.06
R.run(3)
local nx0 = e.next[1]
T.mouse(true)
R.run(0.05)
local rec = v.rec[1]
R.run(0.25)
T.mouse(false)
R.run(0.3)
local shell = false
for _, s in ipairs(G.shots) do if s.byEnt == e.id and s.kind == "shell" then shell = true end end
check(e.next[1] > nx0 and shell, "主炮打出一发（炮弹在飞）")
check(math.abs(e.ty[1] - st.ty[1]) < 3 and math.abs(e.gp[1] - st.gp[1]) < 3, string.format("服务器的炮塔角跟客户端一致（方位 %.0f°、俯仰 %.0f°）", e.ty[1], e.gp[1]))
check(rec > 0.3, string.format("客户端：炮管后坐 %.1f 格", rec))

print("⑤ 反舰导弹：准星对着敌舰自动框住，左键发射，打沉")
local fp = (e.root.CFrame * CF(0, 0, -1500)).Position
local fbase = R.CFrame.lookAt(V3(fp.X, 0, fp.Z), V3(fp.X + 1, 0, fp.Z))
local foeShip = G.spawnShip("atk", "t022", fbase, nil)
check(foeShip ~= nil, "正前方 1500 格放一艘攻方 022")
R.run(1)
local rel = flat(foeShip.root.CFrame.Position) - st.pos
st.camYaw, st.camPitch = math.atan(-rel.X, -rel.Z), -0.04
T.tap(Enum.KeyCode.Two)
R.run(0.6)
check(st.wi == 2, "换到反舰导弹")
check(st.lock ~= nil and st.lock.id == foeShip.id, "框住了敌舰")
local msl0 = e.msl
T.mouse(true)
R.run(0.1)
T.mouse(false)
R.run(0.5)
check(e.msl == msl0 - 1, string.format("发射了一枚（%d → %d）", msl0, e.msl))
T.runUntil(function() return not foeShip.alive end, 15)
check(not foeShip.alive, "打沉了敌舰")
T.tap(Enum.KeyCode.One)

print("⑥ 近防炮拦截来袭的反舰导弹（这里把命中率设成必中 / 必不中各打一发）")
local bp = (e.root.CFrame * CF(-300, 0, -1800)).Position
local foe2 = G.spawnShip("atk", "t022", R.CFrame.lookAt(V3(bp.X, 0, bp.Z), V3(bp.X, 0, bp.Z - 1)), nil)
R.run(0.5)
local hp0 = e.hp
SD.W.ciws.kill = 1
check(G.navyFireMissile(foe2, e.id), "敌舰朝我发射")
R.run(12)
check(e.hp >= hp0 - 1, string.format("近防炮打掉了（血 %.0f → %.0f）", hp0, e.hp))
SD.W.ciws.kill = 0
R.run(1.5)
check(G.navyFireMissile(foe2, e.id), "再发一枚")
R.run(12)
check(e.hp < hp0 - 100, string.format("近防炮没拦住，挨了一发（血 %.0f）", e.hp))
SD.W.ciws.kill = 0.55
G.removeEnt(foe2)

print("⑦ 防空导弹打敌机")
local ap = (e.root.CFrame * CF(0, 0, -900)).Position + V3(0, 600, 0)
local jet = G.spawnAircraft("atk", "j20", R.CFrame.lookAt(ap, ap + V3(1, 0, 0)), nil, nil)
check(jet ~= nil, "头顶 900 格外放一架攻方歼-20")
if jet then
  jet.onGround = false
  local sam0 = e.samN
  R.run(1)
  check(e.samN < sam0, string.format("发射了防空导弹（%d → %d）", sam0, e.samN))
  T.runUntil(function() return jet.lastHitBy ~= nil end, 10)
  check(jet.lastHitBy ~= nil and jet.lastHitBy.team == "def", "打中了敌机")
end

print("⑧ 回码头停稳：导弹补满、修理")
local hb = pd.base
st.pos = flat(hb.Position)
st.yaw = math.atan(-hb.LookVector.X, -hb.LookVector.Z)
st.speed, st.order = 0, 0
st.cf = R.CFrame.lookAt(st.pos, st.pos + hb.LookVector)
G.moveEnt(e, hb * CF(0, e.sd.H / 2 - e.sd.draft, 0))
e.lastSync, e.speed = os.clock(), 0
local hpA = e.hp
R.run(8)
check(e.msl == e.sd.missiles.n and e.samN == e.sd.sam.n, string.format("导弹补满（反舰 %d、防空 %d）", e.msl, e.samN))
check(e.hp > hpA, string.format("在修（血 %.0f → %.0f）", hpA, e.hp))

print("⑨ 下船：站到崖顶的终端柱旁边")
T.tap(Enum.KeyCode.F)
R.run(1)
check(P.vehicle == nil and me.Character and not me.Character.HumanoidRootPart.Anchored, "下船了，能走")
local hp = me.Character.HumanoidRootPart.Position
check((flat(hp) - flat(pd.term)).Magnitude < 8 and hp.Y > 40, string.format("站在崖顶终端柱旁（高 %.0f）", hp.Y))
check(C.sail == nil and C.drive == nil, "客户端退出开船")

print("⑩ 攻方：登陆平台码头生成 055，下船站在码头上，再按 E 上船")
T.actAs(foe, "deploy", "rifle", "barge")
R.run(2)
local p5 = T.pad("t055")
local e5 = p5 and T.usePad(foe, p5)
check(e5 ~= nil and e5.driver == PF, "攻方生成 055、上了舰桥")
if e5 then
  T.remoteAs(foe, "Drive", { op = "exit" })
  R.run(0.5)
  check(PF.vehicle == nil, "下船")
  local fp2 = foe.Character.HumanoidRootPart.Position
  check(math.abs(fp2.Y - (Map.BARGE.top + 3.5)) < 2 and (flat(fp2) - flat(p5.term)).Magnitude < 8, "站在码头上终端柱旁")
  T.actAs(foe, "enterVeh", e5.id)
  R.run(0.3)
  check(PF.vehicle == e5 and e5.driver == PF, "在码头上按 E 又上了船")
end

print("⑪ 爆炸按船体方块算距离")
if e5 then
  local W = { dmg = 300, splash = 30, vs = { ship = 1, inf = 0 } }
  local hp1 = e5.hp
  G.explode((e5.root.CFrame * CF(e5.sd.W / 2 + 45, 0, -e5.sd.L * 0.3)).Position, W, { team = "def" })
  check(e5.hp == hp1, "船舷外 45 格（离船中心不到船长一半）的爆炸不伤船")
  G.explode((e5.root.CFrame * CF(e5.sd.W / 2 + 4, 0, e5.sd.L * 0.4)).Position, W, { team = "def" })
  check(e5.hp < hp1, "贴着船舷的爆炸伤到了")
end

print("⑫ 击沉：开船的人阵亡、名额冷却、客户端看到船沉下去")
if e5 then
  local used0 = G.vehAvail("atk").ship.u
  G.damageEnt(e5, 1e6, { P = P, team = "def", name = "P1" })
  R.run(1)
  check(not e5.alive and e5.wreck, "被击沉")
  check(not PF.alive, "开船的人阵亡")
  check(G.vehAvail("atk").ship.u == used0, "名额还占着（冷却中）")
  local v5
  for em, vv in pairs(C.views or {}) do if em == e5.model then v5 = vv end end
  R.run(3)
  check(v5 ~= nil and (v5.sinkT or 0) > 2, "客户端：船在往下沉")
end

print("⑬ 港口的巡逻艇生成点：据点 C 丢了就不能用")
local portPad
for _, p in ipairs(shipPads) do if p.need == "C" then portPad = p end end
check(portPad ~= nil and G.padOpen(portPad, "def"), "港口巡逻艇生成点开着")
local own0 = G.points.C.owner
G.points.C.owner = "atk"
check(portPad ~= nil and not G.padOpen(portPad, "def"), "据点 C 丢了：关了")
G.points.C.owner = own0

print("⑭ AI 舰艇：攻方 054A 在南面近海巡逻、炮击岸上；守方巡逻艇在港湾里")
G.navyNoAI = false
local function aiOf(team)
  for _, x in ipairs(G.ships) do if x.ai and x.team == team and x.alive then return x end end
  return nil
end
T.runUntil(function() return aiOf("atk") ~= nil and aiOf("def") ~= nil end, 5)
local ai, aiD = aiOf("atk"), aiOf("def")
check(ai ~= nil and ai.sd.id == "t054a", "攻方 AI 054A 出来了")
check(aiD ~= nil and aiD.sd.id == "pbr", "守方 AI 巡逻艇出来了")
if ai then
  local fired = 0
  local launch0 = G.launch
  G.launch = function(s)
    if s.byEnt == ai.id then fired = fired + 1 end
    return launch0(s)
  end
  local a0 = ai.root.CFrame.Position
  R.run(25)
  G.launch = launch0
  check((ai.root.CFrame.Position - a0).Magnitude > 100, string.format("在巡逻（走了 %.0f 格）", (ai.root.CFrame.Position - a0).Magnitude))
  check(fired >= 2, "炮击了岸上目标 " .. fired .. " 发")
end
T.summary()
