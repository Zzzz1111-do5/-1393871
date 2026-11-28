-- T-90A 的「窗帘-1」（模拟器）：python3 tools/mock/run.py tools/mock/shtora.lua
--   用户 11-28：「t90我记得有一对红色的车灯 这个一定要还原的跟原车一样」
--   ① 出厂的 T-90A：改装里光电对抗位默认「窗帘-1」；车模型炮两边各一个大圆灯（在炮塔组里——跟着炮塔转），左右对称、在炮塔正面；
--      开着的样子（用户 11-28 给的图「它开起来是这个效果」）：中心白热、外圈橙红（霓虹）、一团光晕、往前照的光；打爆了灯灭
--   ② T-90M（换了新炮塔，真车没有）：没有这对灯
--   ③ 管用：指令制导的反坦克弹（陶式这一类）冲着它来，进到告警距离时约一半被骗偏；冲着 T-90M 的一发都不偏；激光制导的照样报警、自动打烟
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
T.fakeImport("t90m")
local me = T.join("P1", 8721, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
R.run(1)
local RS = R.services.ReplicatedStorage
local VD = R.require(RS:FindFirstChild("VehDefs"))
local TM = R.require(RS:FindFirstChild("TankMods"))
local Map = G.Map
local cam = R.workspace.CurrentCamera
local hp = cam.CFrame.Position
local function spot(r)
  for k = 0, 35 do
    local a = k / 36 * math.pi * 2
    local x, z = hp.X + math.cos(a) * r, hp.Z + math.sin(a) * r
    if Map.isLand(x, z) and Map.slope(x, z) < 0.2 then return x, z end
  end
  return hp.X + r, hp.Z
end
local function newVeh(id, r)
  local x, z = spot(r)
  return G.newVehicle("atk", id, G.vehBaseAt(VD.get(id), x, z, V3(0, 0, -1)))
end
local function viewOf(e)
  for em2, vv in pairs(C.views or {}) do if em2 == e.model then return vv end end
end
local function lenses(v)
  local out = {}
  for _, it in ipairs(v and v.M and v.M.parts or {}) do
    local p = it[1]
    if p.Name == "ShtoraLens" then out[#out + 1] = { p = p, g = it[2], off = it[3] } end
  end
  return out
end

print("① 出厂的 T-90A：两个红色的大圆灯")
local a = newVeh("t90a", 60)
R.run(2)
check(a.def.kit ~= nil and a.def.kit.ew == "shtora", "T-90A 出厂的光电对抗是「窗帘-1」（" .. tostring(a.def.kit and a.def.kit.ew) .. "）")
check(TM.FOR.t90a and TM.FOR.t90a.ew[1] == "shtora", "改装里这一位默认「窗帘-1」，能换成别的")
local va = viewOf(a)
local L = lenses(va)
check(#L == 2, "车模型上两个干扰灯（" .. #L .. "）")
local okLook, sym = true, false
for _, l in ipairs(L) do
  local c = l.p.Color
  if not (l.p.Material == R.Enum.Material.Neon and c.R > 0.9 and c.G < 0.45 and c.B < 0.2 and l.g == "turret") then okLook = false end
end
check(okLook, "外圈橙红的霓虹、在炮塔组里（跟着炮塔转）")
local nCore, nHalo, nLight = 0, 0, 0
for _, x in ipairs(va and va.model and va.model:GetDescendants() or {}) do
  if x.Name == "ShtoraCore" and x.Material == R.Enum.Material.Neon and x.Color.R > 0.95 and x.Color.G > 0.9 then nCore = nCore + 1 end
  if x.Name == "ShtoraHalo" and x.Enabled and x.LockedToPart then nHalo = nHalo + 1 end
  if x.Name == "ShtoraLight" and x.Enabled and x.Face == R.Enum.NormalId.Front and not x.Shadows then nLight = nLight + 1 end
end
check(nCore == 2 and nHalo == 2 and nLight == 2, string.format("开着：中心白热（%d）、光晕（%d）、往前照的光（%d）", nCore, nHalo, nLight))
if #L == 2 then
  local p1, p2 = L[1].off.Position, L[2].off.Position
  sym = math.abs((p1.X + p2.X) / 2 - (-0.094 - 0.02)) < 0.4 and math.abs(p1.X - p2.X) > 2.5 and math.abs(p1.Y - p2.Y) < 0.01 and math.abs(p1.Z - p2.Z) < 0.01
  print(string.format("    两个灯（炮塔坐标）：(%.2f, %.2f, %.2f) / (%.2f, %.2f, %.2f)", p1.X, p1.Y, p1.Z, p2.X, p2.Y, p2.Z))
  check(sym, "左右对称地分在炮的两边")
  check(p1.Z < -4.5 and p1.Y > 1, "在炮塔正面（往前 4.5 格以外、座圈以上）")
end

print("② T-90M：没有这对灯")
local m = newVeh("t90m", 110)
R.run(2)
check(#lenses(viewOf(m)) == 0 and (m.def.kit == nil or m.def.kit.ew ~= "shtora"), "T-90M 没有「窗帘-1」")

print("③ 干扰灯骗偏指令制导的反坦克弹")
local function shot(target, guide)
  local tp = target.root.CFrame.Position
  return { w = { guide = guide }, pos = tp + V3(0, 3, -700), vel = V3(0, 0, 300) }
end
local nA, nM = 0, 0
for _ = 1, 200 do
  if G.kitLaser(shot(a, "cmd"), a, 0.1) then nA = nA + 1 end
  if G.kitLaser(shot(m, "cmd"), m, 0.1) then nM = nM + 1 end
end
check(nA >= 70 and nA <= 130, string.format("冲着 T-90A 的 200 发指令制导弹：%d 发被骗偏（约一半）", nA))
check(nM == 0, "冲着 T-90M 的：一发都不偏（" .. nM .. "）")
local s1 = shot(a, "cmd")
local r1 = G.kitLaser(s1, a, 0.1)
local same = true
for _ = 1, 5 do if G.kitLaser(s1, a, 0.1) ~= r1 then same = false end end
check(same, "同一发只掷一次（骗偏了一直偏、没骗到就一直没骗到）")
local far = shot(a, "cmd")
far.pos = a.root.CFrame.Position + V3(0, 3, -3000)
check(G.kitLaser(far, a, 0.1) == false and far.irJam == nil, "还远（3000 格）：不掷")
local w0 = G.lwsWarns or 0
G.kitLaser(shot(a, "laser"), a, 0.1)
check((G.lwsWarns or 0) == w0 + 1, "激光制导的：照样激光告警、自动打烟")
print("④ 打爆了：灯灭")
a.model:SetAttribute("WtWhy", "crew")
a.wtWhy = "crew"
G.wtRaw = true
G.damageEnt(a, 1e9, nil)
G.wtRaw = false
R.run(1.5)
local lit = 0
for _, x in ipairs(va.model:GetDescendants()) do
  if (x.Name == "ShtoraLens" or x.Name == "ShtoraCore") and x.Material == R.Enum.Material.Neon then lit = lit + 1 end
  if (x.Name == "ShtoraHalo" or x.Name == "ShtoraLight") and x.Enabled then lit = lit + 1 end
end
check(not a.alive and lit == 0, "残骸上的干扰灯灭了（还亮着 " .. lit .. " 处）")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | ", 1, math.min(#R.errors, 3)))
T.summary()
