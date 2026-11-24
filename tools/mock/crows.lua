-- 坦克不带机枪（模拟器；用户 11-22：「坦克不要弄哪个机枪」）：python3 tools/mock/run.py tools/mock/crows.lua
--   以前这里测 M1A2 车长的 CROWS 遥控武器站；现在主战坦克一挺机枪都不带（VehDefs.TANK_MG = false）：
--   ① 型号表：所有坦克只剩主炮（没有并列机枪、车顶遥控武器站 / 手动重机枪）；步战车、轮式车、轻型车的机枪照旧
--   ② M1A2 画出来：车顶没有 M2（原模型拆出来的机枪零件不画、没有会转的武器站），车长指挥塔（座圈、观察镜）还在、焊在炮塔上
--   ③ 进车内（坦克锁在炮长位），按 T：开的是车长的 CITV、不是 CROWS（不开机枪屏、不换武器）；车里那块 CROWS 屏只剩摄像头（NO WPN、没有弹数）
--   ④ 开火：打出去的是 120 毫米主炮，从炮口出；按 2 / 滚轮换不到机枪
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local VEH = "m1a2"

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8301, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = "def"
me.Team = G.TEAM.def
me.Neutral = false
me:SetAttribute("Side", "def")
G.pushOne(P)
R.run(1)
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
T.actAs(me, "deploy", "rifle", "camp")
R.run(1.5)
local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))
local Map = G.Map
local def = VD.get(VEH)

print("① 型号表：坦克只剩主炮，别的车机枪照旧")
check(VD.TANK_MG == false, "坦克不带机枪的开关是关的（VehDefs.TANK_MG）")
local bad, tanks = {}, 0
for id, d in pairs(VD.D) do
  if d.cat == "tank" then
    tanks = tanks + 1
    local mg = d.rws ~= nil
    for _, wid in ipairs(d.weapons or {}) do if wid == "coax" or wid == "hmg" then mg = true end end
    if mg or not d.noRoofMg or #(d.weapons or {}) ~= 1 then table.insert(bad, id .. "（" .. table.concat(d.weapons or {}, "+") .. "）") end
  end
end
check(tanks >= 5 and #bad == 0, string.format("%d 辆坦克都只剩主炮%s", tanks, #bad > 0 and ("：没去干净 " .. table.concat(bad, "、")) or ""))
check(def.rws == nil and #def.weapons == 1 and def.weapons[1] == "gun120", "M1A2：只有 120 毫米炮（" .. table.concat(def.weapons, "+") .. "）")
local function has(id, wid)
  local d = VD.get(id)
  for _, w in ipairs(d and d.weapons or {}) do if w == wid then return true end end
  return false
end
check(has("jltv", "hmg") and has("hmmwv", "hmg"), "JLTV、悍马的 12.7 毫米机枪还在")
check(has("m2a3", "coax"), "步战车的并列机枪还在")

print("② M1A2 画出来：车顶没有 M2，指挥塔还在")
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or V3(Map.CAMP.x, 0, Map.CAMP.z)
local cx, cz = hp.X + 16, hp.Z
for k = 0, 23 do
  local a = k / 24 * math.pi * 2
  local x, z = hp.X + math.cos(a) * 18, hp.Z + math.sin(a) * 18
  if Map.isLand(x, z) and Map.slope(x, z) < 0.25 then cx, cz = x, z break end
end
-- 模拟器里没有 Studio 导入的原模型：照元数据摆一套同名的块（ReplicatedStorage.Imported.Veh.m1a2dc），走原模型那条路
local IM = R.require(R.services.ReplicatedStorage:FindFirstChild("ImportedMeta"))
local ikey = IM.alias and IM.alias[VEH]
local info = ikey and IM.m[ikey]
if info then
  local RS = R.services.ReplicatedStorage
  local imp = RS:FindFirstChild("Imported") or R.Instance.new("Folder")
  imp.Name = "Imported"
  imp.Parent = RS
  local vf = imp:FindFirstChild("Veh") or R.Instance.new("Folder")
  vf.Name = "Veh"
  vf.Parent = imp
  if not vf:FindFirstChild(ikey) then
    local f = R.Instance.new("Folder")
    f.Name = ikey
    local n = 0
    for name, p in pairs(info.parts) do
      local b = R.Instance.new("MeshPart")
      b.Name = "V_" .. ikey .. "__" .. name
      b.Size = V3(p.s[1], p.s[2], p.s[3])
      b.Parent = f
      n = n + 1
    end
    f:SetAttribute("N", n)
    f.Parent = vf
  end
end
local e = G.newVehicle("def", VEH, G.vehBaseAt(def, cx, cz, V3(0, 0, -1)))
R.run(0.8)
local v
for em, vv in pairs(C.views or {}) do if em == e.model then v = vv end end
check(v ~= nil, "客户端画出了这辆车")
check(v and v.rF == nil and v.rgF == nil, "没有会转的武器站（rF / rgF 都没有）")
local nGun, nRing, nTur = 0, 0, 0
local mdl = v and (v.model or v.m)
if mdl then
  for _, p in ipairs(mdl:GetDescendants()) do
    if p:IsA("BasePart") then
      if p.Name:find("__RwsGun_", 1, true) then nGun = nGun + 1
      elseif p.Name:find("__Rws_", 1, true) then nRing = nRing + 1
      elseif p.Name:find("__Turret_", 1, true) then nTur = nTur + 1 end
    end
  end
end
if nTur > 0 then   -- 模拟器里有原模型的零件：机枪那几块不画，座圈那几块还在
  check(nGun == 0, "原模型里的 M2 不画（剩 " .. nGun .. " 块）")
  check(nRing > 0, "车长指挥塔（座圈、观察镜）还在（" .. nRing .. " 块）")
else
  print("  （模拟器里没有原模型零件，跳过零件检查）")
end

print("③ 进车内、换到车长位，按 T：CROWS 这一位空着")
R.run(0.3)
T.act("enterVeh", e.id)
R.run(1)
local st = C.drive
check(P.vehicle == e and st ~= nil, "坐上了 M1A2")
if not st then T.summary() return end
T.runUntil(function() return G.round.phase == "battle" end, 60)
T.tap(Enum.KeyCode.C)
R.run(0.6)
local I = C.interiorState()
-- 坦克默认炮长位（用户 11-24 起 F2～F5 能换别的位置）：炮长位的 T 是车长的主观瞄（CITV），不是 CROWS
check(I.station == "gunner" and I.cur ~= nil and I.cur.spec.order[1] == "gunner", "坐进车里就是炮长位（默认）")
local wi0 = st.wi
T.tap(Enum.KeyCode.T)
R.run(0.8)
local op = C.interiorOpticState()
check(op == nil or op.o.kind ~= "crows", "按 T 没开 CROWS（" .. tostring(op and op.o.kind) .. "）")
check(st.wi == wi0 and st.d.weapons[st.wi] == "gun120", "武器还是主炮：" .. tostring(st.d.weapons[st.wi]))
check(st.rwsPt == nil, "鼠标没交给武器站")
if op then T.tap(Enum.KeyCode.T) R.run(0.5) end
-- 车里那块 CROWS 屏：只剩车顶摄像头
R.run(0.6)
local noWpn = T.texts("NO WPN")
local m2 = T.texts("CROWS  M2")
check(#m2 == 0, "车里没有「CROWS  M2」的机枪屏（" .. #m2 .. " 处）")
if #noWpn == 0 then print("  （模拟器里没摆出 CROWS 屏，跳过屏幕文字检查）") else check(true, "CROWS 屏写着「" .. noWpn[1] .. "」") end
T.tap(Enum.KeyCode.C)   -- 出车内
R.run(0.6)

print("④ 开火：打出去的是主炮；换武器换不到机枪")
T.tap(Enum.KeyCode.Two)
R.run(0.3)
check(st.d.weapons[st.wi] == "gun120", "按 2 还是主炮（" .. tostring(st.d.weapons[st.wi]) .. "）")
local shots, shells = {}, {}
local bs0, la0 = G.botShot, G.launch
G.botShot = function(from, to, w, ...) table.insert(shots, { from = from, to = to, w = w }) return bs0(from, to, w, ...) end
G.launch = function(s, ...) s.p0 = s.pos table.insert(shells, s) return la0(s, ...) end   -- 发射那一刻的位置（之后 pos 跟着飞）
R.as("client", function() C.driveTryFire() end)
R.run(0.4)
G.botShot, G.launch = bs0, la0
local mgShots = 0
for _, s in ipairs(shots) do if s.w == VD.W.hmg or s.w == VD.W.coax then mgShots = mgShots + 1 end end
for _, s in ipairs(shells) do if s.w == VD.W.hmg or s.w == VD.W.coax then mgShots = mgShots + 1 end end
local main = nil
for _, s in ipairs(shells) do if s.w == VD.W.gun120 or (s.w and s.w.base == VD.W.gun120) then main = s end end   -- 坦克炮按弹种另有一份武器表（base 指回原来的）
check(mgShots == 0, "没有机枪子弹（" .. mgShots .. " 发）")
check(main ~= nil, string.format("开了一炮 120 毫米（炮弹 %d 发）", #shells))
if main then
  local bse = G.vehBaseOf and G.vehBaseOf(e) or (e.root.CFrame * CF(0, -def.H / 2, 0))
  local mz = VD.muzzle(def, bse, e.ty, e.gp, "gun")
  local p0 = main.p0
  if p0 then
    local off = (p0 - mz.Position).Magnitude
    check(off < 1.5, string.format("炮弹从主炮炮口出（差 %.2f 格）", off))
  end
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
