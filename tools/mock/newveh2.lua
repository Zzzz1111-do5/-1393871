-- 11-28 补的车（模拟器）：python3 tools/mock/run.py tools/mock/newveh2.lua
--   用户 11-28「你把德国的各种载具全部补齐……包括坦克」「中国当年买过的坦克你也找模型」：
--   ① 新车都有 VehDefs、模型元数据（ImportedMeta）、科技树、名字、装甲、弹（Ballistics 的弹种、WtDamage 的穿深）、写实车图、驾驶界面剪影：
--      T-34-85（中系引进，一级）、KPz 70（德系二级，豹 2A0 的前置）；借现成模型的 T-80U（中系引进）、米格-29G（德系第一架固定翼）
--   ② 引进的车不当起步车：中系白送的照旧是 59 式，德系照旧是豹 1
--   ③ 试驾 T-34-85、KPz 70：坐得进、开得了火（85 毫米、152 毫米炮的弹打得出去）
--   ①b 黄鼠狼 1A3（德系步兵战车，四级、「步兵战车」一列打头）：20 毫米 Rh 202 + 「米兰」+ 并列机枪；弹药栏的图借现成的（25 毫米、筒装导弹）
--   ④ SU-100（中系引进，没有炮塔）：炮只在左右 8° 里转（VehDefs turret.arc）；瞄出射界车体自己转过去对准，
--      瞄准线留在瞄的地方（没有稳定器的车原来瞄准线跟着车体转——自己转的那一下不跟，不然越转越偏、转个不停）；
--      服务器那边的炮角也夹在射界里；电脑开的 SU-100 目标在侧面时原地转车头
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

T.wtMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8421, true)
T.runUntil(function() return G.round ~= nil end, 30)
local P = G.P[me]
local C = T.C
T.leaveMenu()
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
R.run(1)
local RS = R.services.ReplicatedStorage
local VD = R.require(RS:FindFirstChild("VehDefs"))
local IM = R.require(RS:FindFirstChild("ImportedMeta"))
local TT = R.require(RS:FindFirstChild("TechTree"))
local W = R.require(RS:FindFirstChild("WtDamage"))
local B = R.require(RS:FindFirstChild("Ballistics"))
local VP = R.require(RS:FindFirstChild("VehPics"))
local HI = R.require(RS:FindFirstChild("HudIcons"))

print("① 新车的数据都齐")
local NEW = { t3485 = "cn_t3485", kpz70 = "de_kpz70", su100 = "cn_su100", marder1a3 = "de_marder1a3" }
local AP = R.require(RS:FindFirstChild("AmmoPics"))
for vk, tk in pairs(NEW) do
  local d = VD.get(vk)
  local it = TT.get(tk)
  local mk = IM.alias and IM.alias[vk]
  check(d ~= nil and it ~= nil and it.veh == vk, string.format("%s：VehDefs、科技树（%s）都有", vk, tk))
  check(mk ~= nil and IM.m and IM.m[mk] ~= nil, string.format("%s：模型元数据（%s）", vk, tostring(mk)))
  check(W.PROF[vk] ~= nil, vk .. "：装甲表")
  check(C.T("veh." .. vk) ~= "veh." .. vk, vk .. "：有名字（" .. C.T("veh." .. vk) .. "）")
  check(VP.veh and VP.veh[vk] ~= nil and VP.pics[VP.veh[vk]] ~= nil, vk .. "：科技树的写实车图")
  check(HI["veh_" .. vk] ~= nil, vk .. "：驾驶界面的剪影")
  for _, w in ipairs(d and d.weapons or {}) do
    local wd = VD.W[w]
    if w ~= "coax" and wd and wd.fx ~= "tank" then   -- 机关炮、导弹：没有坦克炮那种弹道表；弹药栏要有图
      check(C.T("vw." .. w) ~= "vw." .. w, string.format("%s 的 %s（%s）有名字：%s", vk, w, wd.kind, C.T("vw." .. w)))
      check(AP.w and AP.w[w] ~= nil and AP.pics[AP.w[w]] ~= nil, string.format("%s：弹药栏有图（%s）", w, tostring(AP.w and AP.w[w])))
    elseif w ~= "coax" then
      check(VD.W[w] ~= nil and C.T("vw." .. w) ~= "vw." .. w, string.format("%s 的炮 %s 有定义、有名字", vk, w))
      local list = B.GUN and B.GUN[w]
      check(list ~= nil and #list >= 2, string.format("%s 的弹种 %d 种", w, list and #list or 0))
      for _, a in ipairs(list or {}) do
        check(B.AMMO and B.AMMO[a] ~= nil and W.AMMO and W.AMMO[a] ~= nil, string.format("弹 %s：弹道、穿深都有", a))
      end
    end
  end
end
local t80 = TT.get("cn_t80u")
local mig = TT.get("de_mig29g")
check(t80 ~= nil and t80.veh == "t80u" and t80.nostart, "中系的 T-80U（引进）借俄系 T-80U")
check(mig ~= nil and mig.veh == "mig29" and mig.branch == "air", "德系第一架固定翼：米格-29G（借米格-29）")
local l2 = TT.get("de_leo2a0")
check(l2 ~= nil and l2.prev == "de_kpz70", "KPz 70 是豹 2A0 的前置（" .. tostring(l2 and l2.prev) .. "）")
check(TT.get("cn_t3485").rank == 1 and TT.get("cn_t3485").prev == nil, "T-34-85 一级、没有前置")
local md = TT.get("de_marder1a3")
check(md ~= nil and md.rank == 4 and md.col == 4 and md.prev == nil, "黄鼠狼 1A3：四级、「步兵战车」一列打头")
local su = TT.get("cn_su100")
check(su ~= nil and su.rank == 1 and su.col == 3 and su.prev == nil and su.nostart, "SU-100：一级、「轻型 / 歼击车」一列打头、不当起步车")

print("② 起步车没变")
check(TT.starter("cn", "ground").key == "cn_59", "中系白送的照旧是 59 式（" .. TT.starter("cn", "ground").key .. "）")
check(TT.starter("de", "ground").key == "de_leo1", "德系白送的照旧是豹 1（" .. TT.starter("de", "ground").key .. "）")

print("③ 试驾、开火")
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
shots = {}
local launch0 = G.launch
G.launch = function(s)
  table.insert(shots, s)
  return launch0(s)
end
for vk, tk in pairs(NEW) do
  local e, def = ride(tk)
  check(e ~= nil and def ~= nil and def.id == vk, string.format("试驾坐进了 %s（%s）", vk, tostring(def and def.id)))
  if e then
    shots = {}
    for _ = 1, 30 do
      R.as("client", function() C.driveTryFire() end)
      R.run(1 / 30)
    end
    R.run(0.5)
    local main = 0
    for _, s in ipairs(shots) do if s.kind == "shell" or (s.w and VD.W[s.w] and VD.W[s.w].kind == "shell") then main = main + 1 end end
    check(main >= 1, string.format("%s：主炮打出去了（%d 发）", vk, main))
  end
end

print("④ SU-100 没有炮塔：炮只在射界里转，瞄出射界车体自己转过去")
local V2 = R.Vector2.new
local function rel(a) return ((a + 180) % 360) - 180 end
local e, def, st = ride("cn_su100")
check(e ~= nil and st ~= nil and def and def.turret.arc ~= nil, "坐进了 SU-100（炮的射界 " .. tostring(def and def.turret.arc and def.turret.arc[2]) .. "°）")
if e and st then
  R.run(1)
  local function hullYaw() local lv = st.root.LookVector return math.deg(math.atan2(-lv.X, -lv.Z)) end
  local h0, c0 = hullYaw(), math.deg(st.camYaw)
  for _ = 1, 15 do
    R.mouseDelta = V2(40, 0)   -- 往右拨鼠标
    R.run(1 / 30)
  end
  R.mouseDelta = V2(0, 0)
  local swing = rel(c0 - math.deg(st.camYaw))
  check(swing > 30, string.format("镜头往右转了 %.0f°", swing))
  R.run(0.2)
  check(math.abs(rel(st.ty)) <= 8.05, string.format("炮夹在射界里（%.1f°）", rel(st.ty)))
  local cam1 = math.deg(st.camYaw)
  R.run(6)
  local turned = rel(h0 - hullYaw())
  check(turned > 20, string.format("车体自己往右转过去了 %.0f°", turned))
  check(math.abs(rel(math.deg(st.camYaw) - cam1)) < 3, string.format("瞄准线留在瞄的地方（偏了 %.1f°）", rel(math.deg(st.camYaw) - cam1)))
  check(math.abs(rel(math.deg(st.camYaw) - hullYaw())) < 10, string.format("车头对准了瞄的方向（差 %.1f°）", rel(math.deg(st.camYaw) - hullYaw())))
  local h1 = hullYaw()
  R.run(2)
  check(math.abs(rel(hullYaw() - h1)) < 2, string.format("对准以后不再转（又转了 %.1f°）", rel(hullYaw() - h1)))
  check(math.abs(rel(e.ty or 0)) <= 8.05, string.format("服务器那边的炮角也在射界里（%.1f°）", rel(e.ty or 0)))
  -- 客户端发来射界外的炮角：服务器夹住
  T.remoteAs(me, "Drive", { op = "state", cf = e.root.CFrame, ty = 40, gp = 0 })
  check(math.abs(rel(e.ty or 0)) <= 8.05, string.format("客户端报 40°：服务器夹到 %.1f°", rel(e.ty or 0)))
end

print("⑤ 电脑开的 SU-100：目标在侧面，原地转车头")
if G.aiVehThink then
  local d = VD.get("su100")
  local p0 = P.char and P.char:FindFirstChild("HumanoidRootPart") and P.char.HumanoidRootPart.Position or V3(0, 0, 0)
  local ax, az = p0.X + 120, p0.Z + 120
  local ae = G.newVehicle("def", "su100", G.vehBaseAt(d, ax, az, V3(0, 0, -1)))
  local tgt = G.newVehicle("atk", "t3485", G.vehBaseAt(VD.get("t3485"), ax + 160, az, V3(0, 0, -1)))
  R.run(0.3)
  local function yawOf(x) local lv = x.root.CFrame.LookVector return math.deg(math.atan2(-lv.X, -lv.Z)) end
  local y0 = yawOf(ae)
  ae.ai = { state = "hold", goal = nil, hold = ae.root.CFrame.Position, tgt = { pos = tgt.root.CFrame.Position, kind = "veh", ref = tgt },
    seekT = math.huge, aimT = 0, stuckT = 0, lastP = ae.root.CFrame.Position, holdT = os.clock() + 1e6, sideT = 0, crew = { name = "AI" } }
  local ticks = 0
  for i = 1, 80 do   -- 每 0.1 秒想一次（转速 30°/秒 → 一次 3°）；转到射界里就停
    G.aiVehThink(ae, 0.1)
    R.run(0.1)
    ticks = i
    if ae.ai.arcOver == 0 then break end
  end
  local t1 = rel(y0 - yawOf(ae))
  local tgtOk = ae.ai.tgt ~= nil and tgt.alive
  check(t1 > 70, string.format("目标在右边 90°：%d 次转了 %.0f°（射界外还差 %s°、状态 %s、能动 %s、目标还在 %s）", ticks, t1,
    tostring(ae.ai.arcOver), tostring(ae.ai.state), tostring(not (ae.wt and ae.wt.mob == false)), tostring(tgtOk)))
  check(math.abs(rel(ae.ty or 0)) <= 8.05, string.format("炮角在射界里（%.1f°）", rel(ae.ty or 0)))
else
  check(false, "AIVeh 没给 G.aiVehThink")
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
