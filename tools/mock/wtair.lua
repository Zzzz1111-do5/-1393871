-- 战雷式飞机受伤（模拟器）：python3 tools/mock/run.py tools/mock/wtair.lua
--   ① 坐进歼-20：部件血齐全（WtaP 九九九……）、左下损伤图出来
--   ② 打左翼外侧：左翼断了（WtaWing = L），飞控那边知道（G.wtaFlight），打的人收到命中提示
--   ③ 打机身中后段：发动机受损推力打折；打中段：油箱漏油（WtaLeak）、多烧油
--   ④ 打座舱：飞行员昏迷（WtaKO），4 秒后算打下来
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check

local G = T.boot()
G.fortsHold = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 8501, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.picked = true
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
T.actAs(me, "deploy", "rifle", "base")
R.run(1.5)
T.runUntil(function() return G.round.phase == "battle" end, 90)
check(P.alive, "出生了")
local AD = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs"))
local d = AD.get("j20")
local hrp = P.char:FindFirstChild("HumanoidRootPart")
local x, z = hrp.Position.X + 60, hrp.Position.Z
local gy = G.airSurface(x, z)
local e = G.spawnAircraft(P.team, "j20", CF(x, gy + d.gearH + 0.5, z), nil, P)
check(e ~= nil and e.wta ~= nil, "放了一架歼-20，有部件血")
if not e then T.summary() return end
P.char:PivotTo(CF(x + 20, gy + 3.5, z))
R.run(0.3)
T.act("enterVeh", e.id)
R.run(1.2)
local st = C.fly
check(st ~= nil and P.vehicle == e, "坐进了驾驶座")
print("① 部件血：WtaP " .. tostring(e.model:GetAttribute("WtaP")))
check(e.model:GetAttribute("WtaP") == "9999999", "七个部件都满（左翼、右翼、尾翼、发动机、油箱、飞行员、操纵面）")
local hud = nil
for _, dd in ipairs(me.PlayerGui:GetDescendants()) do if dd.Name == "WtAirDamage" then hud = dd end end
check(hud ~= nil and T.visible(hud), "左下飞机损伤图")

-- 打的人：另一队一个假的玩家（只要 P / pl 给命中提示）
local foe = { P = { pl = me, team = (P.team == "atk") and "def" or "atk" }, team = (P.team == "atk") and "def" or "atk" }
local function hitAt(lx, ly, lz, frac)
  G.wtPos = e.root.CFrame * V3(lx, ly, lz)
  G.damageEnt(e, e.wta.maxHp * frac, foe)
  G.wtPos = nil
  R.run(0.3)
end
print("② 打左翼外侧")
hitAt(-d.W * 0.4, 0, 0, 0.45)
print("  左翼 " .. e.wta.p.wingL .. "，WtaWing " .. tostring(e.model:GetAttribute("WtaWing")))
check(e.wta.p.wingL <= 0 and e.model:GetAttribute("WtaWing") == "L", "左翼断了")
local fl = C.wtaFlight and C.wtaFlight(st.em)
check(fl ~= nil and fl.wing == "L", "飞控知道断了左翼")
e.hp = e.wta.maxHp   -- 后面接着打：机身血补满（不然先炸了）
print("③ 发动机、油箱")
hitAt(0, 0, d.L * 0.17, 0.15)   -- 机身中后段（发动机：机身后一半里靠前的那段）
local eng = e.model:GetAttribute("WtaEng")
check(e.wta.p.eng < 100 and eng ~= nil and eng < 1, "发动机受损：推力系数 " .. tostring(eng))
hitAt(0, 0, 0, 0.1)
local leak = e.model:GetAttribute("WtaLeak")
check(leak ~= nil and leak > 0, "油箱打漏：每秒多漏 " .. tostring(leak))
e.hp = e.wta.maxHp
print("④ 打座舱：飞行员昏迷")
hitAt(0, 0.5, -d.L * 0.42, 0.45)
check(e.model:GetAttribute("WtaKO") == true, "飞行员昏迷（飞行员 " .. e.wta.p.pilot .. "）")
R.run(5)
check(not e.alive, "昏迷 4 秒后算打下来")
T.summary()
