--!nocheck
-- 宣传图用的场景导出：盖满所有楼（居民楼、工厂、银行升到 Lv.5）、造一批兵，导出几个时刻的场景（给 render 预览页画成背景图）：
--   promo_base.json   基地全景（展示飞机停好）
--   promo_battle.json 沙漠战区打到一半
--   promo_missile.json 巡航导弹在天上飞（拖着白烟）
--   promo_launch.json 巡航导弹刚从发射井升空（井盖开着、冒烟）
--   promo_boom.json   巡航导弹刚落地（大火球）
-- 用法：lune run promo_export.luau <rbxlx> <输出目录>
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local H = require("./harness")
H.quietWarn = true
H.followCam = true
H.tweenLerp = true   -- 特效的变大、变淡按时间插值（不然导出时都是刚生成的样子）
H.boot(process.args[1])
H.run(2)
local outDir = process.args[2]
local p1 = H.addPlayer("P1", 9001)
H.run(6)
local G = H.Gs.server
local st = G.states[p1]
local C1 = H.Gs.P1
local function act(...)
	local a = table.pack(...)
	local co = coroutine.create(function() C1.R.Action:FireServer(table.unpack(a, 1, a.n)) end)
	H.ctx = p1
	coroutine.resume(co)
	H.ctx = nil
end

local function rot(cf)
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return { r00, r01, r02, r10, r11, r12, r20, r21, r22 }
end
local function c3(c) return { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) } end
local function export(name)
	local out = { parts = {}, terrain = {}, origin = { st.plot.origin.X, st.plot.origin.Y, st.plot.origin.Z } }
	for _, d in H.workspace:GetDescendants() do
		if d:IsA("BasePart") and d.ClassName ~= "Terrain" and d.Transparency < 0.99 and not H.destroyed[d] and d.Name ~= "TeamRing" then   -- 宣传图不画部队脚下的队伍色圈
			local ok, e = pcall(function()
				local cf = H.worldCF(d)
				local okL, ltm = pcall(function() return d.LocalTransparencyModifier end)
				if okL and ltm and ltm > 0.5 then return nil end
				local shape = "Block"
				if d.ClassName == "Part" then
					local okS, sh = pcall(function() return d.Shape end)
					shape = okS and sh and sh.Name or "Block"
				elseif d.ClassName == "WedgePart" then
					shape = "Wedge"
				end
				return { p = { cf.X, cf.Y, cf.Z }, r = rot(cf), s = { d.Size.X, d.Size.Y, d.Size.Z }, c = c3(d.Color), t = d.Transparency, sh = shape, m = d.Material.Name }
			end)
			if ok and e then table.insert(out.parts, e) end
		end
	end
	for _, op in H.terrainOps do
		local cf = op.cf
		table.insert(out.terrain, { k = op.k, p = { cf.X, cf.Y, cf.Z }, r = rot(cf), s = op.size and { op.size.X, op.size.Y, op.size.Z } or nil, rad = op.r, h = op.h, m = op.m })
	end
	out.light = { clock = H.game:GetService("Lighting").ClockTime }
	fs.writeFile(outDir .. "/" .. name, serde.encode("json", out))
	print(string.format("导出 %s：零件 %d 个", name, #out.parts))
end

-- 盖满楼、升级、造兵
st.data.cash = 1e10
local plotF = H.workspace.Plots["Plot" .. st.plot.index]
H.click(p1, "^领取")
for _ = 1, 22 do
	local any = false
	for _, b in G.Config.Buildings do
		local m = plotF.Pads:FindFirstChild("Pad_" .. b.id)
		if m and not st.data.owned[b.id] then
			H.ev(m.Pad, "Touched"):Fire(p1.Character.HumanoidRootPart)
			any = true
		end
	end
	H.run(1.3)
	if not any then break end
end
for _ = 1, 3 do act("hq") H.run(0.3) end
for _ = 1, 10 do act("tech") H.run(0.15) end
for _, id in { "house1", "house2", "house3", "bank", "factory1", "factory2", "factory3" } do
	for _ = 1, 4 do
		act("upgrade", id)
		H.run(0.25)
	end
end
for _, t in { "tank", "tank", "tank", "heavytank", "ifv", "ifv", "td", "aa", "spaag", "sam", "heli", "heli", "transport", "attacker", "fighter", "bomber",
	"arty", "mlrs", "howitzer", "inf", "inf", "inf", "medic", "at", "mg", "sniper" } do
	act("buy", t)
	H.run(0.25)
end
H.run(40)
for _, sh in pairs(C1.shows or {}) do sh.t = 1 end   -- 机场、直升机场的展示飞机停好
H.run(0.05)
export("promo_base.json")

-- 沙漠战区开一仗
st.data.level = 15
G.makeEnemy(st)
H.run(1)
act("battle")
H.run(2)
local B = st.battle
if B then   -- 敌人血加厚一点，免得几秒就打完（只为了截到打得正热闹的时候）
	for _, u in B.units do
		if u.team == 2 then
			u.hp *= 15
			u.max *= 15
		end
	end
end
H.run(7)
export("promo_battle.json")
-- 巡航导弹：瞄着敌人扎堆的地方
B = st.battle
if B then
	local tx, tz, n = 0, 0, 0
	for _, u in B.units do
		if u.team == 2 and u.alive and not u.def.air then tx, tz, n = tx + u.x, tz + u.z, n + 1 end
	end
	tx, tz = tx / math.max(1, n), tz / math.max(1, n)
	act("skill", "cruise", tx, tz)
	H.run(1.3)
	export("promo_launch.json")   -- 井盖开着、井口冒烟、导弹刚升空
	H.run(2.3)
	export("promo_missile.json")
	H.run(2.52)
	export("promo_boom.json")     -- 刚落地，火球最亮的时候
end
H.summary()
