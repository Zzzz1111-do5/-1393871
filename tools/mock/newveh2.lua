-- 11-28 补的车（模拟器）：python3 tools/mock/run.py tools/mock/newveh2.lua
--   用户 11-28「你把德国的各种载具全部补齐……包括坦克」「中国当年买过的坦克你也找模型」：
--   ① 新车都有 VehDefs、模型元数据（ImportedMeta）、科技树、名字、装甲、弹（Ballistics 的弹种、WtDamage 的穿深）、写实车图、驾驶界面剪影：
--      T-34-85（中系引进，一级）、KPz 70（德系二级，豹 2A0 的前置）；借现成模型的 T-80U（中系引进）、米格-29G（德系第一架固定翼）
--   ② 引进的车不当起步车：中系白送的照旧是 59 式，德系照旧是豹 1
--   ③ 试驾 T-34-85、KPz 70：坐得进、开得了火（85 毫米、152 毫米炮的弹打得出去）
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
local NEW = { t3485 = "cn_t3485", kpz70 = "de_kpz70" }
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
    if w ~= "coax" then
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
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
