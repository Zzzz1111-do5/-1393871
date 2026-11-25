-- 试驾场里不该出对局的界面（用户 11-25 晚：「训练场为什么会有missionfailed 还有一堆乱七八糟的据点占领啥的」）：
--   python3 tools/mock/run.py tools/mock/tdshots.lua [dir=<截图目录>]
--   ① 试驾时：据点栏、据点标记、对局提示都收起；② 主战场那一局打完（结算）时还在试驾：不弹「任务失败 / 任务完成」结算页
--   拍的 JSON 用 tools/mock/hud_render.py 画成图看
local T = dofile(MOCK_DIR .. "/common.lua")
local R, Enum = T.R, T.Enum
local check = T.check
local dir = TEST_ARGS:match("dir=(%S+)")
local dump = dofile(MOCK_DIR .. "/uidump.lua")

T.wtMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)

local me = T.join("P1", 9601, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
T.leaveMenu()
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
R.run(1)
local C = T.C

T.act("testDrive", "de_leo2a6")
T.runUntil(function() return P.vehicle ~= nil and P.vehicle.testDrive end, 15)
R.run(3)
check(P.vehicle ~= nil and P.vehicle.testDrive, "坐在试驾的车里")
check(C.inTestDrive and C.inTestDrive() == true, "客户端知道在试驾")

-- 屏幕上显示着的、名字或字里带「据点 / 占领 / 任务」一类的元素
local function matchUi()
  local bad = {}
  for _, d in ipairs(me.PlayerGui:GetDescendants()) do
    if d:IsA("GuiObject") then
      local vis = true
      local o = d
      while o and o ~= me.PlayerGui do
        if o:IsA("GuiObject") and not o.Visible then vis = false break end
        if (o:IsA("ScreenGui") or o:IsA("BillboardGui") or o:IsA("SurfaceGui")) and not o.Enabled then vis = false break end
        o = o.Parent
      end
      if vis and (d:IsA("TextLabel") or d:IsA("TextButton")) then
        local t = d.Text or ""
        if t:find("据点") or t:find("占领") or t:find("MISSION") or t:find("任务失败") or t:find("任务完成") or t:find("CAPTUR")
          or t:find("进攻") or t:find("防守") or t:find("拿下") or t:find("兵力") or t:find("阶段") or t:find("胜利") then
          table.insert(bad, d:GetFullName():gsub("^.-PlayerGui%.", "") .. "「" .. t:sub(1, 40) .. "」")
        end
      end
    end
  end
  return bad
end
if dir then dump(T, me, dir .. "/td1_drive.json", true) end
local function shownNamed(nm)
  for _, d in ipairs(me.PlayerGui:GetDescendants()) do
    if d.Name == nm and d:IsA("GuiObject") then
      local o, vis = d, true
      while o and o ~= me.PlayerGui do
        if o:IsA("GuiObject") and not o.Visible then vis = false break end
        if o:IsA("ScreenGui") and not o.Enabled then vis = false break end
        o = o.Parent
      end
      if vis then return true end
    end
  end
  return false
end
check(not shownNamed("ScoreBar"), "试驾时顶上的比分条（兵力、倒计时、A～E 据点）不画")
check(not (C.operationHudVisible and C.operationHudVisible()), "试驾时作战简报、占点进度不画")
local b1 = matchUi()
check(#b1 == 0, "试驾时屏幕上没有据点 / 占领 / 任务字样（" .. table.concat(b1, "；"):sub(1, 400) .. "）")

-- ② 主战场那一局打完：还在试驾的人不弹结算页
G.roundFinish("def")
R.run(2)
if dir then dump(T, me, dir .. "/td2_end.json", true) end
local res = nil
for _, d in ipairs(me.PlayerGui:GetDescendants()) do
  if d:IsA("TextLabel") and (d.Text == "任务失败" or d.Text == "MISSION FAILED" or d.Text == "任务完成" or d.Text == "MISSION ACCOMPLISHED") then res = d end
end
local shown = false
if res then
  shown = true
  local o = res
  while o and o ~= me.PlayerGui do
    if o:IsA("GuiObject") and not o.Visible then shown = false break end
    if o:IsA("ScreenGui") and not o.Enabled then shown = false break end
    o = o.Parent
  end
end
check(not shown, "一局打完时还在试驾：不弹「任务失败 / 任务完成」")
local b2 = matchUi()
check(#b2 == 0, "结算时试驾画面上也没有据点 / 任务字样（" .. table.concat(b2, "；"):sub(1, 400) .. "）")
T.summary()
