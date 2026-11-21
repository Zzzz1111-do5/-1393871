-- 改枪（模拟器）：python3 tools/mock/run.py tools/mock/gunsmith.lua [v]
--   进服写好属性（默认配件、等级、Studio 全开）→ 部署界面的「改枪」按钮 → 改枪界面：点改装位、卡片换配件、预览时性能条变、
--   推荐改装、改枪码粘贴应用、存方案 → 「完成」发给服务器存好 → 出击：工具带 Build 属性、服务器那份武器表按配件
--   （消音、弹鼓 60 发、换弹时间）、客户端 G.W 一样 → 开枪：消音的不上雷达（fx q）、伤害按距离衰减 →
--   第一人称：视图模型上装着配件（消音器的枪口往前、红点的光轴开镜对正）、激光 → 枪械经验：打死人加经验、升级提示；
--   没解锁的（关掉 Studio 全开）服务器不认
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 7301, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
local C = T.C
local GM = R.require(R.services.ReplicatedStorage:FindFirstChild("GunMods"))
T.leaveMenu()
R.run(1)

print("① 进服：玩家属性（下次出击装的、等级、Studio 全开）")
local b0 = GM.decode(me:GetAttribute("Gun_m4"))
check(b0.optic == "acog" and b0.mag == "mag_std", "默认 M4：ACOG、原装弹匣（" .. tostring(me:GetAttribute("Gun_m4")) .. "）")
check(me:GetAttribute("GunAll") == true, "Studio 里配件全部解锁（GunAll）")
check(me:GetAttribute("GunXp_m4") == 0, "枪械经验从 0 开始")

print("② 部署界面：主武器那格有「改枪」按钮")
R.as("client", function()
  C.deploySel.pageUser = "kit"
  C.refreshDeploy()
end)
R.run(0.2)
local gsb = T.findButton("^" .. C.T("gm.open") .. "$")
check(gsb ~= nil, "看得见「改枪」按钮")
if gsb then T.press(gsb) end
R.run(0.5)
local gui = me.PlayerGui:FindFirstChild("Gunsmith")
check(gui and gui.Enabled == true and C.gunsmithOpen(), "点了打开改枪界面")
for _ = 1, 40 do R.run(0.25) end   -- 配件模型排队现生成
local labels = T.texts()
local function has(s)
  for _, t in ipairs(labels) do if t:find(s, 1, true) then return true end end
  return false
end
check(has(C.T("weapon.m4")) and has(C.T("gm.st.vrec")) and has(C.T("gm.st.hand")) and has(C.T("gm.presets")) and has(C.T("gm.saves")),
  "标题、性能（垂直后坐力控制、操控速度……）、推荐改装、我的方案都有")
local codeBox
for _, d in ipairs(gui:GetDescendants()) do if d.ClassName == "TextBox" then codeBox = d end end
check(codeBox and codeBox.Text == GM.code("m4", b0), "改枪码框里是现在这一套的码：" .. tostring(codeBox and codeBox.Text))

print("③ 点改装位「枪口」→ 底下一排配件卡片 → 点 SOCOM 消音器")
local slotBtn = nil
for _, d in ipairs(gui:GetDescendants()) do
  if d.ClassName == "TextLabel" and d.Text == C.T("gm.slot.muzzle") and d.Parent and d.Parent.ClassName == "TextButton" then slotBtn = d.Parent end
end
check(slotBtn ~= nil and T.visible(slotBtn), "枪上有「枪口」标签")
if slotBtn then T.press(slotBtn) end
R.run(0.3)
local cards = {}
for _, d in ipairs(gui:GetDescendants()) do
  if d.ClassName == "TextLabel" and d.Parent and d.Parent.ClassName == "TextButton" and d.Parent.Size.X.Offset == 158 then
    if d.Text == C.T("gm.item.sup_socom") then cards.socom = d.Parent end
    if d.Text == C.T("gm.item.muz_comp") then cards.comp = d.Parent end
  end
end
check(cards.socom ~= nil and cards.comp ~= nil, "枪口的卡片：SOCOM 消音器、战术补偿器……")
-- 鼠标移到补偿器上：预览（性能条上「垂直后坐力控制」变好，写着 +10）
if cards.comp then R.as("client", function() cards.comp.MouseEnter:Fire() end) end
R.run(0.2)
local plus = T.texts("^%+10$")
check(#plus >= 1, "预览补偿器：垂直后坐力控制 +10（绿色）")
if cards.comp then R.as("client", function() cards.comp.MouseLeave:Fire() end) end
if cards.socom then T.press(cards.socom) end
R.run(0.2)
check(codeBox.Text == GM.code("m4", { muzzle = "sup_socom", optic = "acog", grip = "grip_none", mag = "mag_std", tac = "tac_none" }), "装上消音器：改枪码跟着变（" .. codeBox.Text .. "）")

print("④ 改枪码：粘贴一串（弹鼓 + 全息 + 激光）点「应用」")
local want = { muzzle = "sup_socom", optic = "opt_holo", grip = "grip_rvg", mag = "mag_drum", tac = "tac_peq" }
codeBox.Text = string.lower(GM.code("m4", want))
T.click("^" .. C.T("gm.apply") .. "$")
R.run(0.2)
check(codeBox.Text == GM.code("m4", want), "套用了改枪码（小写也认）")
codeBox.Text = "M4A1-1ZZZZZ"
T.click("^" .. C.T("gm.apply") .. "$")
R.run(0.2)
check(codeBox.Text == "M4A1-1ZZZZZ", "抄错的码不认：框里留着让人改")
R.as("client", function() C.gunsmithRefresh() end)
check(codeBox.Text == GM.code("m4", want), "装的那一套没变")

print("⑤ 存方案 1，「完成」→ 服务器存好")
local saveB = T.findButton("^" .. C.T("gm.saveBtn") .. "$")
if saveB then T.press(saveB) end
R.run(1)
local saves = me:GetAttribute("GunSaves_m4") or ""
check(saves:find("mag_drum", 1, true) ~= nil, "方案 1 存好了（" .. saves:sub(1, 60) .. "…）")
T.click("^" .. C.T("gm.done") .. "$")
R.run(0.5)
check(not C.gunsmithOpen(), "关上了")
local b1 = GM.decode(me:GetAttribute("Gun_m4"))
check(b1.mag == "mag_drum" and b1.muzzle == "sup_socom" and b1.optic == "opt_holo" and b1.tac == "tac_peq", "服务器存好：下次出击装的变了")
check(P.data and P.data.guns and P.data.guns.m4 and P.data.guns.m4.b:find("mag_drum", 1, true) ~= nil, "写进存档数据（P.data.guns）")

print("⑥ 出击：工具带 Build、武器表按配件（服务器、客户端一样）")
T.actAs(me, "deploy", { primary = "m4", gadget = "medkit", throw = "grenade" }, P.team == "atk" and "fleet" or "camp")
R.run(2.5)
check(P.alive, "出生了")
local tool = nil
for _, holder in ipairs({ me.Character, me:FindFirstChildOfClass("Backpack") }) do
  if holder then for _, t in ipairs(holder:GetChildren()) do if t.ClassName == "Tool" and t:GetAttribute("Weapon") == "m4" then tool = t end end end
end
check(tool and (tool:GetAttribute("Build") or ""):find("mag_drum", 1, true) ~= nil, "M4 工具的 Build 属性：" .. tostring(tool and tool:GetAttribute("Build")))
local ws = G.wOf(P, "m4")
check(ws.mag == 60 and ws.quiet == true and ws.reload > G.Config.Weapons.m4.reload, string.format("服务器那份：60 发、消音、换弹 %.2f 秒", ws.reload))
local wc = C.W.m4
check(wc.mag == 60 and wc.quiet == true and math.abs(wc.reload - ws.reload) < 1e-6 and wc.laser == true, "客户端 G.W 一样（还有激光）")
check(G.ammoOf(P, "m4").n == 60, "弹匣里 60 发")
check(math.abs(me.Character:FindFirstChildOfClass("Humanoid").WalkSpeed - G.Config.Soldier.speed * ws.mobK) < 0.01 and ws.mobK < 1,
  string.format("弹鼓重：走路速度 ×%.3f", ws.mobK))
local scope = nil
for _, c in ipairs(tool:GetChildren()) do if c.Name:sub(1, 5) == "Scope" then scope = c end end
check(scope == nil, "换了瞄具：工具上原来那具 ACOG 拿掉了")
local mag = tool:FindFirstChild("Mag")
check(mag and mag.Transparency == 1, "换了弹匣：零件拼的弹匣藏起来")

print("⑦ 开枪：消音的不上雷达、伤害远了往下掉")
T.runUntil(function() return G.round.phase == "battle" end, 200)
R.run(0.5)
local fx = {}
local oldFx = G.fx
G.fx = function(e) table.insert(fx, e) return oldFx(e) end
R.as("server", function() G.shoot(P, "m4", me.Character.Head.Position + V3(0, 0, -200)) end)
G.fx = oldFx
local shot = nil
for _, e in ipairs(fx) do if e.k == "gun" then shot = e end end
check(shot and shot.q == true, "开枪的特效带 q（消音）：客户端雷达不闪、声音闷")
check(GM.dmgAt(ws, 30) == ws.dmg and GM.dmgAt(ws, ws.range) < ws.dmg * 0.8, "伤害衰减：近处满伤、射程尽头七成多")

print("⑧ 第一人称：视图模型上装着配件")
for _ = 1, 30 do R.run(0.2) end
local vm = C.fps
check(vm ~= nil and vm.id == "m4", "镜头前有 M4")
if vm then
  local mz = vm.mzOff.Position
  check(mz.Z > 1.6, string.format("消音器：枪口往前挪到消音器前端（z %.2f）", mz.Z))
  check(vm.optic and vm.optic.kind == "dot" and vm.optic.dot == "holo", "全息瞄具：开镜看着枪、画全息圈")
  check(vm.tac and vm.tac.kind == "laser" and vm.beam ~= nil, "激光：有一道光")
  -- 用户 11-21：那个指示灯是对着我自己照的——激光原来顺着枪身骨骼的 LookVector（−Z，朝后）打；光束要在出光口前面、顺着镜头朝向
  if vm.beam and vm.tacWorld then
    local camCF = R.workspace.CurrentCamera.CFrame
    local fwd = (vm.beam.CFrame.Position - vm.tacWorld.Position):Dot(camCF.LookVector)
    check(fwd > 0.5, string.format("激光朝前打出去，不照自己（光束中点在出光口前方 %.1f 格）", fwd))
  end
  local n = 0
  for _, it in ipairs(vm.items) do if it[1].Name:find("O_mag_drum", 1, true) then n = n + 1 end end
  check(n >= 2, "弹鼓装在两条弹匣骨骼上（枪上的、换弹时手里的）")
end
check(vm and vm.quiet == true, "消音：枪口焰很淡")

print("⑨ 枪械经验：打死人加经验，升级提示解锁")
local msgs = {}
local oldMsg = G.msg
G.msg = function(pl, kind, key, ...) table.insert(msgs, key) return oldMsg(pl, kind, key, ...) end
G.gunXp(P, "m4", 520)
G.msg = oldMsg
local lv = GM.level("m4", me:GetAttribute("GunXp_m4"))
check(lv == 3, "520 经验：Lv.3（属性 GunXp_m4 = " .. tostring(me:GetAttribute("GunXp_m4")) .. "）")
local saw = false
for _, k in ipairs(msgs) do if k == "gm.lvUp" then saw = true end end
check(saw, "升级提示（gm.lvUp）")

print("⑩ 关掉 Studio 全开：没解锁的服务器不认")
G.gunAll = false
local Gs = R.require(R.services.ServerScriptService:FindFirstChild("Main"):FindFirstChild("Gunsmith"))
-- 直接按等级核对：3 级时弹鼓（14 级）、SR8（13 级）不认
local got = GM.clean("m4", { mag = "mag_drum", muzzle = "sup_sr8", grip = "grip_rvg" }, 3, false)
check(got.mag == "mag_std" and got.muzzle == "fh_a2" and got.grip == "grip_rvg", "3 级：弹鼓、SR8 换成默认，RVG（2 级）能装")

check(#R.errors == 0, "没有报错" .. ((#R.errors > 0) and ("：" .. tostring(R.errors[1])) or ""))
print(T.fails == 0 and "全部通过" or ("有 " .. T.fails .. " 项不对"))
