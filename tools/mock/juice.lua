-- 爽感（模拟器）：python3 tools/mock/run.py tools/mock/juice.lua
--   用户：想办法增加玩家体验感和爽感
--   ① 打死小兵：命中叉变大、加分滚动「+60 击杀」；4.5 秒内再打死一个：「双杀！」；爆头：「爆头」一行、脆响；摧毁载具 +200
--   ② 一条命连着打死 5 个：「势不可挡」大横幅；死了清零
--   ③ 挨打：准星周围红弧指向开枪的方向
--   ④ 低血量：屏幕四周发红、画面发灰、心跳
--   ⑤ 服务器：打小兵的头，命中提示是 headkill / head
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.Config.Bots.minPerTeam = 18   -- 要打小兵（正式服关了机器人，用户 11-18）
T.runUntil(function() return G.worldReady end, 120)
local me = T.join("P1", 7001, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = "def"
me.Team = G.TEAM.def
me.Neutral = false
me:SetAttribute("Side", "def")
G.pushOne(P)
R.run(1)
local C = T.C
local sfx = {}
local sfx0 = C.sfx
C.sfx = function(def, pos, o)
  if type(def) == "string" then sfx[def] = (sfx[def] or 0) + 1 end
  return sfx0(def, pos, o)
end
local gui = me.PlayerGui:FindFirstChild("Juice")
check(gui ~= nil, "有爽感界面（Juice）")
local function hit(kind) R.as("client", function() C.onMsg("hit", kind) end) end
local function txt(name)
  local l = gui:FindFirstChild(name, true)
  return l and l.Text or ""
end
local function lines()
  local out = {}
  for _, d in ipairs(gui:GetDescendants()) do if d.Name == "Line" and d.ClassName == "TextLabel" then table.insert(out, d.Text) end end
  return table.concat(out, " | ")
end

print("① 打死、双杀、爆头、摧毁载具：加分滚动")
hit("hit")
R.run(0.1)
check(txt("Total") == "", "打中没打死：不加分")
hit("kill")
R.run(0.1)
local SC = G.Config.Score
check(txt("Total") == "+" .. SC.botKill and lines():find(C.T("juice.kill"), 1, true) ~= nil, "打死一个小兵：+" .. SC.botKill .. "（" .. txt("Total") .. "：" .. lines() .. "）")
R.run(1)
hit("headkill")
R.run(0.1)
check(txt("Banner") == C.T("juice.x2"), "4.5 秒内又打死一个：「" .. txt("Banner") .. "」")
check(lines():find(C.T("juice.head"), 1, true) ~= nil and (sfx.headshot or 0) > 0, "爆头：多一行「爆头」、头盔上叮的一声")
check(txt("Total") == "+" .. (SC.botKill * 2), "两个累计：" .. txt("Total"))
hit("vkill")
R.run(0.1)
check(txt("Total") == "+" .. (SC.botKill * 2 + SC.vehicleKill) and txt("Banner") == C.T("juice.x3"), "摧毁载具 +" .. SC.vehicleKill .. "，三杀（" .. txt("Total") .. "、" .. txt("Banner") .. "）")
R.run(4)
check(txt("Total") == "", "过一会儿加分收起来了")

print("② 一条命连着打死 5 个：大横幅")
hit("kill")
R.run(5)
hit("kill")
R.run(0.1)
local st = C.juiceState()
check(st.life == 5 and txt("Banner") == C.T("juice.s5"), string.format("连续击杀 %d：「%s」", st.life, txt("Banner")))

print("③ 挨打：红弧指向开枪的方向")
T.runUntil(function() return G.round.phase == "battle" end, 60)
T.act("deploy", "rifle", "point.A")
R.run(2)
check(P.alive and me.Character ~= nil, "守方在据点 A 出生")
local cam = R.workspace.CurrentCamera
local ccf = cam.CFrame
R.as("client", function() C.onMsg("hurt", ccf.Position + ccf.RightVector * 50) end)
R.run(0.1)
local arc
for _, d in ipairs(gui:GetChildren()) do if d.Name == "HurtArc" and d.Visible then arc = d end end
check(arc ~= nil and arc.Position.X.Offset > 80 and math.abs(arc.Position.Y.Offset) < 40, "右边来的子弹：红弧在准星右边（" .. (arc and tostring(arc.Position) or "无") .. "）")
R.run(2)
local vis = 0
for _, d in ipairs(gui:GetChildren()) do if d.Name == "HurtArc" and d.Visible then vis = vis + 1 end end
check(vis == 0, "一会儿就淡出了")

print("④ 低血量：四周发红、画面发灰、心跳")
local hum = me.Character:FindFirstChildOfClass("Humanoid")
hum.Health = hum.MaxHealth * 0.15
local beat0 = sfx.heart or 0
R.run(2)
local edges = 0
for _, d in ipairs(gui:GetChildren()) do if d.Name == "LowHp" and d.Visible then edges = edges + 1 end end
local cc = R.game:GetService("Lighting"):FindFirstChild("JuiceLowHp")
check(edges == 4 and cc and cc.Enabled and cc.Saturation < -0.2, "三成血以下：四边发红、画面发灰（饱和度 " .. tostring(cc and cc.Saturation) .. "）")
check((sfx.heart or 0) > beat0, "心跳（" .. ((sfx.heart or 0) - beat0) .. " 下）")
hum.Health = hum.MaxHealth
R.run(0.5)
check(not cc.Enabled, "血回满了就没了")

print("⑤ 服务器：打小兵的头")
local kinds = {}
local hm0 = C.hitMarker
C.hitMarker = function(k) table.insert(kinds, k) return hm0(k) end
local foe
for _, e in ipairs(G.ents) do if e.alive and e.kind == "bot" and e.team == "atk" and e.bot.state ~= "boat" then foe = e break end end
if not foe then
  -- 攻方小兵都还在艇上：直接摆一个
  for _, e in ipairs(G.ents) do if e.alive and e.kind == "bot" and e.team == "atk" then foe = e break end end
end
check(foe ~= nil, "找到一个攻方小兵")
if foe then
  local hb = foe.hit or foe.root
  local top = hb.CFrame.Position + V3(0, hb.Size.Y / 2 - 0.2, 0)
  R.as("server", function() G.hitThing(hb, G.Config.Weapons.m4, 30, { P = P, team = P.team, name = "P1" }, 1.6, top) end)
  R.run(0.2)
  R.as("server", function() G.hitThing(hb, G.Config.Weapons.m4, 500, { P = P, team = P.team, name = "P1" }, 1.6, top) end)
  R.run(0.2)
  check(table.concat(kinds, ","):find("head", 1, true) ~= nil and kinds[#kinds] == "headkill", "命中提示：爆头 head、爆头打死 headkill（" .. table.concat(kinds, ",") .. "）")
end
T.summary()
