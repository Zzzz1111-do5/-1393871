-- 11-27 补的三辆地面车（模拟器）：python3 tools/mock/run.py tools/mock/newveh.lua
--   用户 11-27「德国目前没飞机 包括很多缺的载具全部做一下」：BRDM-2（俄 1 级侦察车）、9K31 箭-1（俄 2 级防空车）、87 式侦察警戒车（日 4 级）
--   ① 三型都有：VehDefs、模型元数据（ImportedMeta）、科技树（不是起步车：侦察车不算坦克）、名字、装甲
--   ② BRDM-2 的 KPVT、87 式的 25 毫米炮：坐上去开火，打得出去
--   ③ 箭-1：没锁不发；Q 锁住敌机发一枚 9M31，追着锁住的那架，4 枚少一枚；9M31 是红外弹（热诱弹骗得了）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local function clamp(x, a, b) return x < a and a or (x > b and b or x) end

T.wtMode = true   -- 战雷式：不能当步兵出去，从机库试驾（同 wtreal.lua）
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8411, true)
T.runUntil(function() return G.round ~= nil end, 30)
local P = G.P[me]
local C = T.C
T.leaveMenu()
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)   -- 开火只在开战以后（Armor.lua fire），同 wtreal.lua
R.run(1)
local RS = R.services.ReplicatedStorage
local VD = R.require(RS:FindFirstChild("VehDefs"))
local IM = R.require(RS:FindFirstChild("ImportedMeta"))
local TT = R.require(RS:FindFirstChild("TechTree"))
local W = R.require(RS:FindFirstChild("WtDamage"))
local AD = R.require(RS:FindFirstChild("AirDefs"))
local Map = G.Map
local cam = R.workspace.CurrentCamera

print("① 三型都在")
local KEYS = { brdm2 = "ru_brdm2", strela1 = "ru_strela1", type87rcv = "jp_type87rcv" }
for vk, tk in pairs(KEYS) do
  local d = VD.get(vk)
  local it = TT.get(tk)
  local mk = IM.alias and IM.alias[vk]
  check(d ~= nil and it ~= nil and it.veh == vk, string.format("%s：VehDefs、科技树（%s）都有", vk, tk))
  check(mk ~= nil and IM.m and IM.m[mk] ~= nil, string.format("%s：模型元数据（%s）", vk, tostring(mk)))
  check(W.PROF[vk] ~= nil, vk .. "：装甲表 WtDamage.PROF")
  check(C.T("veh." .. vk) ~= "veh." .. vk, vk .. "：有名字（" .. C.T("veh." .. vk) .. "）")
  for _, w in ipairs(d and d.weapons or {}) do
    if w ~= "coax" then check(VD.W[w] ~= nil, string.format("%s 的武器 %s 有定义", vk, w)) end
  end
end
check(TT.starter("ru", "ground").key ~= "ru_brdm2", "俄系起步车不是 BRDM-2（侦察车不算坦克）：" .. TT.starter("ru", "ground").key)
check(TT.starter("jp", "ground").key ~= "jp_type87rcv", "日系起步车不是 87 式侦察警戒车：" .. TT.starter("jp", "ground").key)

-- 试驾一型（科技树的 key），坐进去；上一辆先下车回机库
local function ride(key)
  if P.vehicle then T.remoteAs(me, "Drive", { op = "exit", hangar = true }) end
  T.runUntil(function() return not P.alive end, 15)
  R.run(1.5)
  T.act("testDrive", key)
  T.runUntil(function() return P.alive and P.vehicle ~= nil end, 20)
  R.run(1.5)
  T.runUntil(function() return C.drive ~= nil end, 8)
  local e = P.vehicle
  return e, e and e.def, C.drive
end
-- 按住开火 sec 秒（同 wtreal.lua：客户端的 driveTryFire，每帧试一次）
local function fireFor(sec)
  local n = math.max(1, math.floor(sec * 30))
  for _ = 1, n do
    R.as("client", function() C.driveTryFire() end)
    R.run(1 / 30)
  end
end
local function lookAt(st, p)
  local d = (p - cam.CFrame.Position).Unit
  st.camYaw = math.atan2(-d.X, -d.Z)
  st.camPitch = clamp(math.asin(d.Y), -0.75, 0.6)
end

print("② BRDM-2、87 式开火")
local shots = {}
local launch0, bot0 = G.launch, G.botShot
G.launch = function(s)
  table.insert(shots, s)
  return launch0(s)
end
G.botShot = function(a, b, w, src, ...)
  table.insert(shots, { kind = "gun", w = w, src = src })
  return bot0(a, b, w, src, ...)
end
for _, vk in ipairs({ "brdm2", "type87rcv" }) do
  local e, def, st = ride(KEYS[vk])
  check(e ~= nil and e.def.id == vk and st ~= nil, "坐上了 " .. vk .. "（" .. tostring(e and e.def.id) .. "）")
  if st then
    C.driveWeapon(1)
    R.run(0.3)
    local w1 = def.weapons[1]
    local mag0 = e.wst[w1] and e.wst[w1].mag
    shots = {}
    fireFor(0.8)
    R.run(0.3)
    local mine = 0
    for _, s in ipairs(shots) do if s.w == VD.W[w1] or (s.w and s.w.id == w1) then mine = mine + 1 end end
    check(mine >= 2, string.format("%s 的 %s 打出去 %d 发（弹匣 %s → %s）", vk, w1, mine, tostring(mag0), tostring(e.wst[w1] and e.wst[w1].mag)))
  end
end

print("③ 箭-1")
local e, def, st = ride(KEYS.strela1)
check(e ~= nil and e.def.id == "strela1" and st ~= nil, "坐上了箭-1")
if st then
  local base = st.root * CF(0, -def.H / 2, 0)
  local fwd = V3(base.LookVector.X, 0, base.LookVector.Z).Unit
  local right = V3(-fwd.Z, 0, fwd.X)
  local vp = e.root.Position
  local gy = Map.height(vp.X, vp.Z)
  local p0 = V3(vp.X, gy + 300, vp.Z) + fwd * 800 - right * 100
  local foe = G.newEnt({ kind = "air", team = (e.team == "atk") and "def" or "atk", cat = "air", hp = 900, size = V3(16, 6, 24), cf = R.CFrame.lookAt(p0, p0 + right), air = true })
  foe.model:SetAttribute("Model", "j20")
  local fly = { p = p0, v = right * 60 }
  local conn = R.Heartbeat:Connect(function(dt)
    if foe.alive then
      fly.p = fly.p + fly.v * dt
      G.moveEnt(foe, R.CFrame.lookAt(fly.p, fly.p + fly.v))
    end
  end)
  lookAt(st, fly.p)
  R.run(0.5)
  local samI
  for i, w in ipairs(def.weapons) do if w == "s9m31" then samI = i end end
  C.driveWeapon(samI)
  R.run(0.2)
  local launched = {}
  G.launch = function(s)
    if s.kind == "missile" and s.byEnt == e.id then table.insert(launched, s) end
    return launch0(s)
  end
  local fs = C.aaFcsState and C.aaFcsState()
  if fs and fs.lockId then T.tap(Enum.KeyCode.Q) R.run(0.1) end
  fireFor(0.3)
  R.run(0.3)
  check(#launched == 0, "没锁住：一枚都没发（" .. #launched .. "）")
  lookAt(st, fly.p)
  R.run(0.3)
  T.tap(Enum.KeyCode.Q)
  R.run(0.2)
  fs = C.aaFcsState and C.aaFcsState()
  check(fs and fs.lockId == foe.id, "Q 锁住了靶机（" .. tostring(fs and fs.lockId) .. "）")
  local mag0 = e.wst.s9m31.mag
  R.run(1.5)   -- 发射架转过去、抬起来
  fireFor(0.1)
  R.run(0.3)
  check(#launched == 1 and launched[1].tgt == foe, string.format("发了 %d 枚 9M31，目标是锁住的那架", #launched))
  check(e.wst.s9m31.mag == mag0 - 1 and mag0 == 4, string.format("发射架上 %d → %d 枚", mag0, e.wst.s9m31.mag))
  local m = launched[1]
  check(m and m.w == AD.W.s9m31 and m.w.seeker == "ir", "飞的是 AirDefs.W.s9m31、红外导引（热诱弹骗得了：Air.lua flare 看 seeker == ir 的地空弹）")
  local hp0 = foe.hp
  T.runUntil(function() return not foe.alive or foe.hp < hp0 end, 10)
  check(not foe.alive or foe.hp < hp0, string.format("打中了：靶机血量 %d → %d", hp0, math.floor(foe.alive and foe.hp or 0)))
  conn:Disconnect()
end
G.launch, G.botShot = launch0, bot0
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
