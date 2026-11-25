-- 阵亡效果（模拟器；用户 11-23：「死亡不要瞬间切到部署画面」；11-25：「包括死亡也别再用之前那个gta的动画了」）：python3 tools/mock/run.py tools/mock/deathfx.lua
--   ① 一下打死（不倒地）：阵亡效果马上开始——部署界面、平显都不出来；画面颜色照旧（不褪黑白、不模糊、声音不发闷、没有「WASTED」）；
--      屏幕下方牌子「阵亡」，凶手的名字、距离写在下面一行（killcam 消息）；镜头是脚本控制的、往后往上退开一点
--   ② 四秒多以后：效果收掉、画面颜色恢复、镜头还给原来的方式，部署界面出来；黑幕随后淡开
--   ③ 倒地以后才死（流血到时间 / 放弃）：效果短一点
--   ④ 效果中途新角色出生（重新部署）：马上停
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 9201, true)
local foe = T.join("P3", 9203, false)
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
local C = T.C
T.leaveMenu()
local P1, P3 = G.P[me], G.P[foe]
T.runUntil(function() return G.round.phase == "battle" end, G.Config.Round.prep + 10)
check(G.round.phase == "battle", "开战")

local function deploy(pl, local_)
  local P = G.P[pl]
  if P.alive then return end
  T.runUntil(function() return R.clock() >= (P.canDeployAt or 0) end, 20)
  local sp = "base"   -- 沙海（11-24 起只剩这张图）：两边都从自己的主基地出生
  if local_ then T.act("deploy", {}, sp) else T.actAsRemote(pl, "deploy", {}, sp) end
  T.runUntil(function() return P.alive and P.char ~= nil and P.char:FindFirstChild("HumanoidRootPart") ~= nil end, 10)
  R.run(0.5)
end
local function hrpOf(pl) return pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") end
local function shoot(victimPl, amt)
  local part = victimPl.Character and victimPl.Character:FindFirstChild("HumanoidRootPart")
  return G.hurtChar(victimPl.Character, amt, { P = P3, team = "atk", name = foe.DisplayName, wid = "m4" }, part)
end
local function find(name, under)
  local root = me.PlayerGui
  if under then root = me.PlayerGui:FindFirstChild(under) or root end
  for _, d in ipairs(root:GetDescendants()) do if d.Name == name then return d end end
  if root.Name == name then return root end
  return nil
end
local function deployShown() local d = find("Deploy") return d ~= nil and d.Visible end
local function grade()
  local L = R.services.Lighting
  return L:FindFirstChild("DeathGrade"), L:FindFirstChild("DeathBlur")
end

deploy(me, true)
deploy(foe, false)
check(P1.alive and P3.alive, "两边都出生了")
local h1, h3 = hrpOf(me), hrpOf(foe)
if h1 and h3 then foe.Character:PivotTo(CF(h1.Position.X + 60, h1.Position.Y, h1.Position.Z)) end
R.run(0.3)
check(not C.deathFxOn(), "活着：没有阵亡效果")

print("① 一下打死：阵亡效果")
local n0 = C.deathFxState().n
local cam = R.workspace.CurrentCamera
local body = hrpOf(me).Position
cam.CFrame = R.CFrame.lookAt(body + V3(0, 4, 12), body)   -- 真游戏里镜头跟着人（第三人称在身后）；模拟器的镜头不跟，先摆过去
shoot(me, 100 + G.Config.Revive.overkill + 60)
R.run(0.15)
check(not P1.alive, "阵亡了")
check(C.deathFxOn() and C.deathFxState().n == n0 + 1, "阵亡效果开始了")
check(not deployShown(), "部署界面先不出来")
local d1 = (cam.CFrame.Position - body).Magnitude
local y1 = cam.CFrame.Position.Y
R.run(1.4)
local cc, blur = grade()
check(cc == nil and blur == nil, "画面颜色照旧：不褪黑白、不模糊（GTA 那套去掉了）")
local title = find("Title", "DeathFx")
check(title ~= nil and title.Text == C.T("death.title") and title.Text ~= "WASTED" and title.TextTransparency < 0.2, "下方牌子「" .. C.T("death.title") .. "」（透明度 " .. tostring(title and title.TextTransparency) .. "）")
local plate = find("Plate", "DeathFx")
check(plate ~= nil and plate.Position.Y.Scale > 0.6, "牌子在屏幕下方，不是正中的横条大字")
local sub = find("Sub", "DeathFx")
check(sub ~= nil and sub.Text:find(foe.DisplayName, 1, true) ~= nil, "下面写着凶手：「" .. tostring(sub and sub.Text) .. "」")
check(C.muffle() < 0.05, "声音不发闷（" .. string.format("%.2f", C.muffle()) .. "）")
check(cam.CameraType == Enum.CameraType.Scriptable, "镜头由阵亡效果接管")
local d2 = (cam.CFrame.Position - body).Magnitude
check(d2 > d1 + 1 and cam.CFrame.Position.Y > y1, string.format("镜头往后、往上退开一点（%.1f → %.1f 格）", d1, d2))
check(d2 < 40, "还看得见身体（" .. string.format("%.1f", d2) .. " 格）")
check(not deployShown(), "放着效果时部署界面一直没出来")

print("② 放完：部署界面出来")
T.runUntil(function() return not C.deathFxOn() end, 6)
check(not C.deathFxOn(), "阵亡效果放完了")
local t1 = R.clock()
R.run(0.3)
check(deployShown(), "部署界面出来了")
cc, blur = grade()
check(cc == nil and blur == nil, "画面颜色、模糊恢复")
check(cam.CameraType ~= Enum.CameraType.Scriptable, "镜头还回去了")
R.run(0.6)
local fade = me.PlayerGui:FindFirstChild("DeathFade")
check(fade ~= nil and not fade.Enabled, "黑幕淡开了")
check(C.muffle() < 0.05, "声音不闷了")

print("③ 倒地以后才死：短一点")
deploy(me, true)
check(not C.deathFxOn(), "重新出生：没有阵亡效果")
shoot(me, 130)
R.run(0.5)
check(P1.downed ~= nil and P1.alive, "先倒地")
check(not C.deathFxOn(), "倒地不是阵亡：不放")
shoot(me, 30)
R.run(0.2)
check(not P1.alive, "补一枪：阵亡")
check(C.deathFxOn(), "阵亡效果开始了")
local dur = C.deathFxState().dur
check(dur and dur < 3.5, "比直接打死的短（" .. tostring(dur) .. " 秒）")
T.runUntil(function() return not C.deathFxOn() end, 5)
check(not C.deathFxOn(), "放完了")

print("④ 效果中途重新出生：马上停")
deploy(me, true)
shoot(me, 100 + G.Config.Revive.overkill + 60)
R.run(0.3)
check(C.deathFxOn(), "又开始了")
P1.canDeployAt = 0
T.act("deploy", {}, "base")
T.runUntil(function() return P1.alive and P1.char ~= nil end, 10)
R.run(0.4)
check(P1.alive and not C.deathFxOn(), "新角色出来，效果停了")
cc, blur = grade()
check(cc == nil and blur == nil, "画面恢复")

T.summary()
