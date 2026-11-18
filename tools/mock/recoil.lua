-- 开枪手感（模拟器）：python3 tools/mock/run.py tools/mock/recoil.lua
--   用户 11-18：提高手感。Roblox 自带的镜头（步行时）每帧从现在的朝向接着算——模拟器的镜头也是（没人重置 cam.CFrame），正好测这个
--   ① 震屏：步行时晃完视线回到原处（原来每帧加全量，晃一下准星就被甩走）；开车的脚本镜头每帧重新摆，晃动不累积
--   ② 后坐：一发踢一下又回来、留下的上抬很小；一梭子 30 发上抬有数（原来四五十度）；开镜更稳；点射头一发最轻
--   ③ 散布：Config.gunSpread——开镜收紧、跑起来 / 跳起来变散、连射越打越散；服务器开枪按它（P.bloom 攒着、停手收回）
--   ④ 准星：四条线，站着窄、跑起来张开
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check

local G = T.boot()
G.fortsHold = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 7101, true)
R.run(1)
local C = T.C
if C.menuShown and C.menuShown() then
  C.menuEnter()
  R.run(0.5)
end
local cam = R.services.Workspace.CurrentCamera
local W = G.Config.Weapons
local Enum = T.Enum

local function pitchYaw(cf)
  local lv = cf.LookVector
  return math.deg(math.asin(math.max(-1, math.min(1, lv.Y)))), math.deg(math.atan2(-lv.X, -lv.Z))
end
local BASE = CF(0, 400, 0) * R.CFrame.Angles(math.rad(-5), math.rad(30), 0)
local function reset()
  cam.CameraType = Enum.CameraType.Custom
  cam.CFrame = BASE
end
local p0, y0 = pitchYaw(BASE)

print("① 震屏")
reset()
R.run(1, 1 / 60)
local pb, yb = pitchYaw(cam.CFrame)
local still = math.abs(pb - p0) < 0.01 and math.abs(yb - y0) < 0.01
check(still, string.format("不晃的时候没人动镜头（俯仰 %.3f°、偏航 %.3f°）", pb - p0, yb - y0))
reset()
C.shake(0.9)
local maxD = 0
for _ = 1, 12 do
  R.run(1 / 60, 1 / 60)
  local p, y = pitchYaw(cam.CFrame)
  maxD = math.max(maxD, math.abs(p - p0) + math.abs(y - y0))
end
R.run(2.5, 1 / 60)
local p1, y1 = pitchYaw(cam.CFrame)
check(maxD > 0.3, string.format("炸一下镜头晃了（最大偏 %.2f°）", maxD))
check(math.abs(p1 - p0) < 0.05 and math.abs(y1 - y0) < 0.05, string.format("步行时晃完视线回到原处（差 俯仰 %.3f°、偏航 %.3f°）", p1 - p0, y1 - y0))
-- 开车：脚本镜头每帧自己摆到 BASE，晃动加在上面、不累积；晃完正好是 BASE
reset()
cam.CameraType = Enum.CameraType.Scriptable
C.shake(0.9)
local maxS = 0
for _ = 1, 150 do
  cam.CFrame = BASE
  R.run(1 / 60, 1 / 60)
  local p, y = pitchYaw(cam.CFrame)
  maxS = math.max(maxS, math.abs(p - p0) + math.abs(y - y0))
end
cam.CFrame = BASE
R.run(1 / 60, 1 / 60)
local p2, y2 = pitchYaw(cam.CFrame)
check(maxS > 0.3 and maxS < 6, string.format("脚本镜头：晃动加在每帧摆好的位置上（最大偏 %.2f°，不越晃越偏）", maxS))
check(math.abs(p2 - p0) < 0.01 and math.abs(y2 - y0) < 0.01, "脚本镜头：晃完就是它自己摆的位置")

print("② 后坐")
local function burst(n, ads, id)
  reset()
  R.run(0.5, 1 / 60)
  local peak = 0
  for i = 1, n do
    C.kick(W[id or "m4"], ads, id or "m4")
    local steps = math.floor(((W[id or "m4"].rate or 0.08) * 60) + 0.5)
    for _ = 1, math.max(1, steps) do
      R.run(1 / 60, 1 / 60)
      local p = pitchYaw(cam.CFrame)
      peak = math.max(peak, p - p0)
    end
  end
  local pEnd = pitchYaw(cam.CFrame)
  R.run(1.2, 1 / 60)
  local pRest, yRest = pitchYaw(cam.CFrame)
  R.run(0.5, 1 / 60)
  local pRest2 = pitchYaw(cam.CFrame)
  return pRest - p0, peak, pEnd - p0, math.abs(pRest2 - pRest), yRest - y0
end
local c1, pk1, _, drift1 = burst(1)
check(c1 > 0.08 and c1 < 0.3 and pk1 > c1 + 0.4, string.format("一发：踢一下（最高 %.2f°）又回来，留下的上抬 %.2f°（原来一下 1～1.7°、不回来）", pk1, c1))
check(drift1 < 0.01, string.format("停手以后镜头不再动（%.3f°）", drift1))
local c30, pk30, end30, _, side30 = burst(30)
check(c30 > 5 and c30 < 14, string.format("一梭子 30 发：上抬 %.1f°（要自己往下压；原来四五十度），左右飘 %.1f°", c30, side30))
check(end30 >= c30 - 0.05, string.format("打完那一刻踢的那份还没回来（%.1f° → 停下 %.1f°）", end30, c30))
local a30 = burst(30, true)
check(a30 < c30 * 0.6, string.format("开着镜：30 发上抬 %.1f°（腰射 %.1f°）", a30, c30))
local s1, spk = burst(1, false, "sniper")
check(s1 > 0.6 and spk > 2, string.format("狙击枪一枪：踢得重（最高 %.1f°），留下 %.2f°", spk, s1))

print("③ 散布")
local m4, sn = W.m4, W.sniper
local gs = G.Config.gunSpread
check(math.abs(gs(m4, false, 0, false, 0) - 0.55) < 1e-6, "M4 站着腰射 0.55°（和原来一样）")
check(gs(m4, true, 0, false, 0) < 0.25, string.format("开镜 %.2f°", gs(m4, true, 0, false, 0)))
check(gs(m4, false, 16, false, 0) > 0.9, string.format("跑起来腰射 %.2f°", gs(m4, false, 16, false, 0)))
check(gs(m4, false, 0, true, 0) > 1.1, string.format("跳在半空 %.2f°", gs(m4, false, 0, true, 0)))
check(math.abs(gs(sn, true, 0, false, 0) - 0.03) < 0.002 and gs(sn, false, 0, false, 0) > 2, string.format("狙击枪开镜 %.3f°、腰射 %.1f°", gs(sn, true, 0, false, 0), gs(sn, false, 0, false, 0)))
-- 服务器：开枪攒散布、停手收回
local P = G.P[me]
P.team = "def"
me:SetAttribute("Side", "def")
T.actAsRemote(me, "deploy", "rifle", "camp")
R.run(1)
T.runUntil(function() return G.round.phase == "battle" end, G.Config.Round.prep + 5)
R.run(1)
local char = me.Character
local hrp = char and char:FindFirstChild("HumanoidRootPart")
check(hrp ~= nil and P.alive, "出生了")
-- 拿上 M4（同 hitreg.lua：模拟器里客户端换枪不一定来得及）
local tool = char and (char:FindFirstChildOfClass("Tool") or me.Backpack:FindFirstChild("m4"))
if tool and tool.Parent ~= char then tool.Parent = char end
R.run(0.5)
local spreads = {}
local orig = G.Config.gunSpread
G.Config.gunSpread = function(w, ads, speed, air, bloom)
  local s = orig(w, ads, speed, air, bloom)
  if debug.traceback():find("Weapons.lua", 1, true) then table.insert(spreads, { s = s, ads = ads, bloom = bloom }) end   -- 只记服务器开枪的（客户端准星每帧也算）
  return s
end
if hrp then
  local aim = hrp.Position + V3(0, 1, -200)
  for _ = 1, 10 do
    T.remoteAs(me, "Shoot", "m4", aim)
    R.run(0.09)
  end
  R.run(1)
  T.remoteAs(me, "Shoot", "m4", aim, "ads")
  R.run(0.1)
end
G.Config.gunSpread = orig
local n = #spreads
check(n == 11, "服务器开了 " .. n .. " 枪（都按 Config.gunSpread 算）")
if n >= 11 then
  check(spreads[1].bloom == 0 and spreads[10].bloom > 0.3, string.format("连射越打越散：第一发多 %.2f°、第十发多 %.2f°", spreads[1].bloom, spreads[10].bloom))
  check(spreads[n].ads == true and spreads[n].bloom < 0.05 and spreads[n].s < 0.25, string.format("停一秒收回了、开镜那一枪 %.2f°", spreads[n].s))
end

print("④ 准星")
local cross = me.PlayerGui:FindFirstChild("Crosshair", true)
check(cross ~= nil, "有准星（四条线）")
if cross and hrp then
  R.run(0.5)
  local function gap()
    local top = cross:GetChildren()
    local g = 0
    for _, f in ipairs(top) do
      if f:IsA("Frame") and f.Size.Y.Offset > f.Size.X.Offset then g = math.max(g, math.abs(f.Position.Y.Offset)) end
    end
    return g
  end
  local g0 = gap()
  hrp.AssemblyLinearVelocity = V3(16, 0, 0)
  for _ = 1, 20 do
    hrp.AssemblyLinearVelocity = V3(16, 0, 0)
    R.run(1 / 30, 1 / 30)
  end
  local g1 = gap()
  check(cross.Visible and g0 > 0 and g1 >= g0 + 5, string.format("站着 %d 像素、跑起来张开到 %d 像素", g0, g1))
end

T.summary()
