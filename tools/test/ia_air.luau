--!nocheck
-- 飞机测试：航母甲板上部署歼-35 → 滑到弹射器卡上 → 油门推满按空格弹射 → 爬升、收起落架 → 锁定打霹雳-15（守方空中出发一架 F-22 当靶子）→
--   热诱弹、航炮、炸弹 → 机场岛降落、停稳补弹 → 航母拦阻索着舰 → 跳伞；直升机：旋翼转起来、起飞、火箭；
--   挂载编辑器：点挂点、换弹、保存；飞出去的导弹按型号拼零件
-- 用法（仓库根目录）：lune run tools/test/ia_air.luau <rbxlx> [v]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")
local V3, CF, Enum = roblox.Vector3, roblox.CFrame, roblox.Enum
H.quietWarn = process.args[2] ~= "v"
H.boot(process.args[1], { ds = "mock" })

local fails = 0
local function check(ok, what)
	print((ok and "  通过 " or "  不对 ") .. what)
	if not ok then fails += 1 end
end
local function as(pl, f)
	local prev = H.ctx
	H.ctx = pl
	local co = coroutine.create(f)
	coroutine.resume(co)
	H.ctx = prev
end
local function act(pl, ...)
	local a = table.pack(...)
	as(pl, function() H.Gs[pl.Name].R.Act:FireServer(table.unpack(a, 1, a.n)) end)
end

H.run(0.5)
local G = H.Gs.server
G.fortsHold = true
G.Config.Bots.minPerTeam = 0
H.runUntil(function() return G.worldReady end, 120)
local p1, p2 = H.addPlayer("P1", 6001), H.addPlayer("P2", 6002)
H.run(2)
local atk = (G.P[p1].team == "atk") and p1 or p2
local def = (atk == p1) and p2 or p1
local PA, PD = G.P[atk], G.P[def]
local CA, CD = H.Gs[atk.Name], H.Gs[def.Name]
local AirDefs = CA.AD

-- 服务器、客户端两边一起挪飞机（测试里瞬移；只挪一边，服务器会当成作弊拉回去）
local function teleport(pl, cf, spd, ground)
	local P = G.P[pl]
	local e = P.vehicle
	local st = H.Gs[pl.Name].fly
	H.run(0.1)   -- 先把路上的位置同步送完（不然一条旧位置到了服务器，会当成作弊把飞机拉回去、带回旧速度）
	e.root.CFrame = cf
	e.lastSync = os.clock()
	e.vel = cf.LookVector * (spd or 0)
	e.onGround = ground == true
	if st then
		st.cf = cf
		local look = cf.LookVector
		st.yaw = math.atan2(-look.X, -look.Z)
		st.spd = spd or st.spd
		st.vel = look * (spd or 0)
		st.hv = V3.new(st.vel.X, 0, st.vel.Z)
		st.ground = ground == true
		st.sink, st.pr, st.rr, st.yr = 0, 0, 0, 0
		st.aimYaw, st.aimPitch = st.yaw, math.asin(math.clamp(look.Y, -1, 1))
		st.crashed = false
		st.cat, st.trap = nil, nil
	end
end

print("① 航母甲板上出生，走到歼-35 的生成点按 E：弹出挂载编辑器，点挂点、换弹、生成")
act(atk, "deploy", "rifle", "cv")
H.run(2)
local hrpA = atk.Character and atk.Character:FindFirstChild("HumanoidRootPart")
check(PA.alive and hrpA and math.abs(hrpA.Position.Y - 30.5 - 3) < 2, string.format("步兵在航母甲板上出生（高 %.1f）", hrpA and hrpA.Position.Y or -1))
local jp = H.pad(G, "j35")
check(jp ~= nil and jp.kind == "air", "航母甲板上有歼-35 的生成点")
H.usePad(G, atk, jp)
local hg = atk.PlayerGui:FindFirstChild("Hangar")
check(hg and hg.Enabled, "按 E 弹出了挂载编辑器")
local HS = CA.hangarState and CA.hangarState()
local nParts = 0
if HS and HS.M then for _ in pairs(HS.M.items) do nParts += 1 end end
check(HS and HS.M and nParts > 100, "3D 飞机拼好了：" .. nParts .. " 个零件")
local spots = 0
for _, b in ipairs(hg and hg:GetDescendants() or {}) do if b.Name:match("^Spot%d") and b.Visible then spots += 1 end end
check(spots >= 4, "挂点白圈 " .. spots .. " 个")
-- 点翼下内侧挂点（wingI），换成雷霆-2（左右对称时一对只画离镜头近的那个圈）
local idx, hidden = nil, 0
for i, s in ipairs(HS.d.st) do
	if s.name == "wingI" then
		local b = hg:FindFirstChild("Spot" .. i, true)
		if b and b.Visible then idx = idx or i else hidden += 1 end
	end
end
check(idx ~= nil and hidden == 1, "对称的一对挂点只画一个圈（看得见的是 " .. tostring(idx) .. "）")
local spotBtn = hg:FindFirstChild("Spot" .. idx, true)
if spotBtn then H.press(atk, spotBtn) end
H.run(0.8)
check(HS.sel == idx, "选中了挂点 " .. tostring(HS.sel))
local pick = nil
for _, b in ipairs(hg:GetDescendants()) do
	if b:IsA("TextButton") and b.Parent and b.Parent:IsA("Frame") then
		for _, l in ipairs(b:GetChildren()) do
			if l:IsA("TextLabel") and l.Text == CA.T("aw.lt2") then pick = b end
		end
	end
end
check(pick ~= nil, "列表里有雷霆-2")
if pick then H.press(atk, pick) end
H.run(0.3)
local mate = nil
for i, s in ipairs(HS.d.st) do if s.name == "wingI" and i ~= idx then mate = i end end
check(HS.load[idx] == "lt2" and HS.load[mate] == "lt2", "左右对称换成了雷霆-2：" .. tostring(HS.load[idx]) .. " / " .. tostring(HS.load[mate]))
local lt2Parts = 0
for _, it in ipairs(HS.M.stores[idx] or {}) do lt2Parts += 1 end
check(lt2Parts >= 10, "挂架上的雷霆-2 按型号拼了 " .. lt2Parts .. " 个零件")
local save = H.findButton(atk, "^" .. CA.T("pad.spawn") .. "$")
check(save ~= nil, "编辑器右下的按钮是「生成」")
if save then H.press(atk, save) end
H.run(1)
check(not hg.Enabled, "编辑器关了")
local e = nil
for _, x in ipairs(G.aircraft) do if x.padId == jp.id and x.alive then e = x end end
check(e ~= nil and e.def.id == "j35" and e.driver == nil, "歼-35 停在甲板的停机位上（空着）")

print("② 走过去按 E 坐进歼-35（挂载照编辑器选的）")
act(atk, "enterVeh", e and e.id)
H.run(1.5)
check(e ~= nil and PA.vehicle == e, "坐进了 " .. tostring(e and e.def.id))
check(e and e.load[idx] == "lt2", "服务器按保存的挂载挂弹：" .. tostring(e and e.model:GetAttribute("Load")))
local st = CA.fly
check(st ~= nil and st.pilot and st.ground, "客户端接管驾驶、在甲板上")
local p0 = e and e.root.CFrame.Position
check(p0 and G.Map and math.abs(p0.Y - 30.5 - e.def.gearH) < 1, string.format("停在航母甲板上（高 %.1f）", p0 and p0.Y or -1))

print("③ 滑到弹射器：甲板上滑不快，到起点对正就卡上")
H.key(atk, Enum.KeyCode.W, true)
H.run(3)
H.key(atk, Enum.KeyCode.W, false)
check(st.spd <= 28.5, string.format("甲板上限速（%.0f 格 / 秒）", st.spd))
-- 直接摆到斜角甲板那条弹射器的起点前一点（自己滑过去的路这里不测）
local start, dir = AirDefs.cat(G.Map, 3)
teleport(atk, CF.lookAt(start - dir * 6 + V3.new(0, e.def.gearH, 0), start - dir * 6 + V3.new(0, e.def.gearH, 0) + dir), 4, true)
st.thr = 10
H.run(1)
check(st.cat ~= nil and st.cat.state == "hooked", "卡上了弹射器 " .. tostring(st.cat and st.cat.i))
local zBefore = e.root.CFrame.Position.Z
H.key(atk, Enum.KeyCode.W, true)
local launched = H.runUntil(function() return st.cat == nil or st.cat.state == "launch" end, 6)
check(st.thr >= 90, string.format("油门推满（%.0f）", st.thr))
check(launched, "推满油门一会儿自动弹射（不用按键、不出提示）")
H.runUntil(function() return not st.ground end, 8)
H.run(0.5)
check(not st.ground and st.spd >= e.def.vRot, string.format("弹射离舰（%.0f 格 / 秒，起飞速度 %.0f）", st.spd, e.def.vRot))
check(zBefore - e.root.CFrame.Position.Z > 150, string.format("服务器跟着飞出去了 %.0f 格", zBefore - e.root.CFrame.Position.Z))

print("④ 爬升、收起落架")
st.aimPitch = 0.25
local y0 = e.root.CFrame.Position.Y
H.run(6)
check(e.root.CFrame.Position.Y > y0 + 60, string.format("爬升了 %.0f 格", e.root.CFrame.Position.Y - y0))
H.key(atk, Enum.KeyCode.G, true) H.key(atk, Enum.KeyCode.G, false)
H.run(3.5)
check((e.model:GetAttribute("Gear") or 1) < 0.1, "起落架收起来了（服务器属性 Gear " .. tostring(e.model:GetAttribute("Gear")) .. "）")
check(e.alive, "飞机还好好的")

print("⑤ 开战后：守方在机场（据点 D）出生、生成一架 F-22 坐上去（摆到天上当靶子），攻方锁定、打霹雳-15")
H.runUntil(function() return G.round.phase == "battle" end, 60)
act(def, "deploy", "rifle", "point.D")
H.run(2)
local fp = H.pad(G, "f22")
check(fp ~= nil and fp.need == "D", "机场停机坪有 F-22 的生成点（据点 D 在守方手里才能用）")
H.usePad(G, def, fp)
local hgD = def.PlayerGui:FindFirstChild("Hangar")
check(hgD and hgD.Enabled, "守方也弹出了挂载编辑器")
local goD = H.findButton(def, "^" .. CD.T("pad.spawn") .. "$")
if goD then H.press(def, goD) end
H.run(1)
local eD = nil
for _, x in ipairs(G.aircraft) do if x.padId == fp.id and x.alive then eD = x end end
check(eD ~= nil and eD.onGround, "F-22 停在机场停机坪上")
act(def, "enterVeh", eD and eD.id)
H.run(1)
check(eD and PD.vehicle == eD, "守方坐进了 F-22")
if eD then
	local sky = V3.new(0, 900, -900)
	teleport(def, CF.lookAt(sky, sky + V3.new(1, 0, 0)), 300, false)
	H.run(0.5)
end
check(eD ~= nil and eD.air and not eD.onGround, "F-22 在天上：" .. tostring(eD and eD.def.id))
-- 把歼-35 摆到 F-22 后面 1800 格、同一高度，机头对着它
local tp = eD.root.CFrame.Position
local from = tp + eD.root.CFrame.LookVector * -1800 + V3.new(0, 10, 0)
teleport(atk, CF.lookAt(from, tp), 320, false)
st.wi = 0
for i, wid in ipairs(st.wl) do if wid == "pl15" then st.wi = i end end
check(st.wi > 0, "选中霹雳-15（武器 " .. st.wi .. " / " .. #st.wl .. "）")
H.run(2.8)
check(st.lock ~= nil and st.lock.id == eD.id, "锁定了 F-22：" .. tostring(st.lock and st.lock.id))
check(st.lockT >= 2, string.format("锁定时间够了（%.1f 秒）", st.lockT))
local nShots = #G.shots
H.mouseDown(atk, 640, 360)
H.run(0.15)
H.mouseUp(atk, 640, 360)
H.run(0.2)
local msl = nil
for _, s in ipairs(G.shots) do if s.kind == "missile" and s.tgt == eD then msl = s end end
check(msl ~= nil, "霹雳-15 出架、追着 F-22")
-- 客户端：飞出去的导弹按型号拼
local cfx = nil
for _, c in ipairs(H.workspace:GetChildren()) do if c.Name == "ClientFx" then cfx = c end end
check(cfx ~= nil and #cfx:GetChildren() > 8, "客户端画了导弹（特效零件 " .. (cfx and #cfx:GetChildren() or 0) .. " 个）")
print("⑥ F-22 放热诱弹；航炮")
local fl0 = eD.flares
local stD = CD.fly
H.key(def, Enum.KeyCode.X, true) H.key(def, Enum.KeyCode.X, false)
H.run(0.4)
check(eD.flares < fl0, string.format("热诱弹 %d → %d", fl0, eD.flares))
H.runUntil(function() return msl == nil or not table.find(G.shots, msl) end, 12)
check(true, "导弹飞完了（命中、被骗走或者自毁）：F-22 血量 " .. tostring(eD.hp) .. " / " .. tostring(eD.maxHp))
if eD.alive and stD then
	stD.wi = 1
	local g0 = eD.gunAmmo
	H.mouseDown(def, 640, 360)
	H.run(0.6)
	H.mouseUp(def, 640, 360)
	H.run(0.3)
	check(eD.gunAmmo < g0, string.format("F-22 航炮打了 %d 发", g0 - eD.gunAmmo))
end

print("⑦ 歼-35 投雷霆-2")
st.wi = 0
for i, wid in ipairs(st.wl) do if wid == "lt2" then st.wi = i end end
local before = e.stores[idx] + e.stores[mate]
H.run(0.3)
H.mouseDown(atk, 640, 360)
H.run(0.15)
H.mouseUp(atk, 640, 360)
H.run(0.5)
local bombs = 0
for _, s in ipairs(G.shots) do if s.kind == "bomb" then bombs += 1 end end
check(bombs >= 1 and e.stores[idx] + e.stores[mate] == before - 1, "投出一枚雷霆-2（还剩 " .. (e.stores[idx] + e.stores[mate]) .. "）")

print("⑧ 机场岛降落、停稳补弹")
H.key(atk, Enum.KeyCode.W, false)   -- 弹射时推的油门松开
local A2 = G.Map.AFIELD2
local gy = G.airSurface(A2.x + A2.len / 2 - 60, A2.z)
local tdP = V3.new(A2.x + A2.len / 2 - 60, gy + e.def.gearH, A2.z)
local appr = tdP + V3.new(260, 18, 0)
teleport(atk, CF.lookAt(appr, appr + V3.new(-1, -0.06, 0)), e.def.stall * 1.15, false)
st.gearWant, st.gear = 1, 1
st.thr = 35
st.aimYaw = math.atan2(1, 0)
st.aimPitch = -0.06
local landed = H.runUntil(function() return st.ground or st.crashed end, 15)
check(landed and st.ground and not st.crashed, "落在跑道上" .. (st.crashed and "（摔了）" or ""))
st.thr = 0
H.key(atk, Enum.KeyCode.B, true)
H.runUntil(function() return st.spd < 2 end, 20)
H.key(atk, Enum.KeyCode.B, false)
H.run(7)
check(e.stores[idx] + e.stores[mate] == before, "停稳 5 秒补满了弹（雷霆-2 " .. (e.stores[idx] + e.stores[mate]) .. "）")

print("⑨ 航母拦阻索着舰")
local base = AirDefs.carrierCF(G.Map)
local Wd = { x = -20, z = 200 }
local td = (base * CF.new(Wd.x, 0, Wd.z)).Position + V3.new(0, e.def.gearH, 0)
local ldir = base:VectorToWorldSpace(V3.new(-math.sin(math.rad(8)), 0, -math.cos(math.rad(8))))
local a0 = td - ldir * 140 + V3.new(0, 9, 0)
teleport(atk, CF.lookAt(a0, a0 + ldir + V3.new(0, -0.06, 0)), e.def.stall * 1.2, false)
st.gearWant, st.gear = 1, 1
st.thr = 30
st.aimYaw = math.atan2(-ldir.X, -ldir.Z)
st.aimPitch = -0.06
H.runUntil(function() return st.ground or st.crashed end, 10)
check(st.ground and st.trap, "尾钩挂上拦阻索" .. (st.crashed and "（摔了）" or ""))
local pA = st.cf.Position
H.runUntil(function() return not st.trap end, 8)
check(st.spd < 2 and (st.cf.Position - pA).Magnitude < 110, string.format("被拉停（滑了 %.0f 格）", (st.cf.Position - pA).Magnitude))

print("⑩ 跳伞")
local up = st.cf.Position + V3.new(0, 500, -200)
teleport(atk, CF.lookAt(up, up + ldir), 300, false)
H.run(0.5)
H.key(atk, Enum.KeyCode.F, true) H.key(atk, Enum.KeyCode.F, false)
H.run(1)
check(PA.vehicle == nil and PA.chute ~= nil, "弹射跳伞（降落伞 " .. tostring(PA.chute ~= nil) .. "）")
check(CA.fly == nil, "客户端交还操作")
H.runUntil(function() return not e.alive end, 30)
check(not e.alive, "没人开的飞机掉下去摔了")

print("⑪ 直升机：营地停机坪，旋翼转起来、起飞、火箭")
-- 守方 F-22 先坠了换直升机（直接让它阵亡）
if PD.vehicle then G.damageEnt(PD.vehicle, 1e6, { team = "atk" }) end
H.run(G.Config.RespawnDelay + 1)
act(def, "deploy", "rifle", "camp")
H.run(2)
local hp = H.pad(G, "ah64e")
check(hp ~= nil, "营地有阿帕奇的停机坪")
H.usePad(G, def, hp)
local back = H.findButton(def, "^" .. CD.T("hangar.back") .. "$")   -- 挂载界面先关掉，直接按「地狱火 + 火箭」那套生成
if back then H.press(def, back) end
act(def, "padSpawn", hp.id, AirDefs.presetLoad(AirDefs.get("ah64e"), "mix"))
H.run(1)
local eH = nil
for _, x in ipairs(G.aircraft) do if x.padId == hp.id and x.alive then eH = x end end
act(def, "enterVeh", eH and eH.id)
H.run(1.5)
local sh = CD.fly
check(eH ~= nil and eH.def.id == "ah64e" and sh ~= nil, "坐进了阿帕奇")
check(sh and sh.rpm < 50, "旋翼刚开始转")
H.run(5)
check(sh and sh.rpm >= 92, string.format("旋翼转起来了（%d%%）", sh and math.floor(sh.rpm) or -1))
H.key(def, Enum.KeyCode.Space, true)
H.run(3)
H.key(def, Enum.KeyCode.Space, false)
local agl = eH.root.CFrame.Position.Y - G.airSurface(eH.root.CFrame.Position.X, eH.root.CFrame.Position.Z)
check(agl > 40, string.format("起飞了（离地 %.0f 格）", agl))
H.key(def, Enum.KeyCode.W, true)
H.run(3)
H.key(def, Enum.KeyCode.W, false)
check(sh.hv.Magnitude > 40, string.format("往前飞（%.0f 格 / 秒）", sh.hv.Magnitude))
sh.wi = 0
for i, wid in ipairs(sh.wl) do if wid == "hydra" then sh.wi = i end end
if sh.wi > 0 then
	local n0 = 0
	for i, s in ipairs(eH.def.st) do if eH.load[i] == "hydra" then n0 += eH.stores[i] end end
	H.mouseDown(def, 640, 360)
	H.run(0.6)
	H.mouseUp(def, 640, 360)
	H.run(0.2)
	local n1 = 0
	for i, s in ipairs(eH.def.st) do if eH.load[i] == "hydra" then n1 += eH.stores[i] end end
	check(n1 < n0, string.format("火箭打出去 %d 发", n0 - n1))
else
	check(true, "这套挂载没有火箭（跳过）")
end

H.summary()
for _, w in ipairs(H.warns) do print("  警告：" .. w.side .. " " .. w.msg:sub(1, 160)) end
print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
