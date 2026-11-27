--!nocheck
-- 飞机座舱眼位（用户 11-24：「飞机座舱眼位修好」）：ImportedAir 里没量 pit 的 7 个原模型（AirModels.lua PIT_FIX 补上）——
--   ① 假装导入了这几个原模型，客户端拼出来的飞机认得补的眼位（M.imp.info.pit）
--   ② 外模型里的飞行员按眼位挪进座舱（两座的两个都在），头在机身外壳里面：正上方是座舱盖 / 舱顶、正下方有机身
--   ③ 眼位不在退回去猜的那个点（V(0, H*0.35, -L*0.3)：UH-60 那里是机舱顶上）
-- 用法（仓库根目录）：lune run tools/test/ia_pit.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local H = require("./harness")
local V3, CF, Inst = roblox.Vector3, roblox.CFrame, roblox.Instance
H.quietWarn = true

local IA = luau.load(fs.readFile("src/ReplicatedStorage/ImportedAir.lua"), { debugName = "ImportedAir" })()
-- 型号 → 模型键（直-20 借 UH-60 的模型）
local TYPES = { a10c = "a10_v3", ah64e = "ah64_v2", uh60 = "uh60", ch47 = "ch47", h6k = "h6k_v3", b2 = "b2_v3", z20 = "uh60" }
local KEYS = {}
for _, k in pairs(TYPES) do KEYS[k] = true end

H.boot(process.args[1], { ds = "mock", before = function(game)
	for k in pairs(KEYS) do
		local m = Inst.new("Model")
		m.Name = "A_" .. k
		for name, p in pairs(IA.m[k].parts) do
			local mp = Inst.new("MeshPart")
			mp.Name = "A_" .. k .. "__" .. name
			mp.Size = V3.new(p.s[1], p.s[2], p.s[3])
			mp.CFrame = CF.new(900 + p.c[1], 200 + p.c[2], 900 + p.c[3])
			mp.Anchored = true
			mp.Parent = m
		end
		m.Parent = game:GetService("Workspace")
	end
end })

local fails = 0
local function check(ok, what)
	print((ok and "  通过 " or "  不对 ") .. what)
	if not ok then fails += 1 end
end

H.run(0.5)
local G = H.Gs.server
G.fortsHold = true
G.Config.Bots.minPerTeam = 0
H.runUntil(function() return G.worldReady end, 120)
local p1 = H.addPlayer("P1", 7101)
H.run(2)
local RS = H.game:GetService("ReplicatedStorage")
local prev = H.ctx
H.ctx = p1
local AM = H.require(p1.PlayerScripts.Client.AirModels)
local AD = H.require(RS.AirDefs)
H.ctx = prev

-- 原模型的包围盒（模型坐标）：头要在里面
local function box(k)
	local lo, hi = V3.new(1e9, 1e9, 1e9), V3.new(-1e9, -1e9, -1e9)
	for _, p in pairs(IA.m[k].parts) do
		local c, s = V3.new(p.c[1], p.c[2], p.c[3]), V3.new(p.s[1], p.s[2], p.s[3]) / 2
		lo, hi = lo:Min(c - s), hi:Max(c + s)
	end
	return lo, hi
end

print("① 补的眼位认得上；② 飞行员挪进座舱；③ 不在猜的那个点")
for id, k in pairs(TYPES) do
	local d = AD.get(id)
	local M = d and AM.build(d, "atk", AD.presetLoad and AD.presetLoad(d, "ag") or nil)
	local imp = M and M.imp
	local pit = imp and imp.info and imp.info.pit
	check(imp ~= nil and imp.key == k, string.format("%s 用原模型 %s", id, tostring(imp and imp.key)))
	check(pit ~= nil and pit == AM.PIT_FIX[k], string.format("%s 认得补的眼位（%d 个座位）", id, pit and #pit or 0))
	if pit then
		local lo, hi = box(k)
		local O = imp.O
		local nPilot = 0
		for seat, e in ipairs(pit) do
			local eye = V3.new(e[1], e[2], e[3])
			local inside = eye.X > lo.X and eye.X < hi.X and eye.Y > lo.Y + 1 and eye.Y < hi.Y and eye.Z > lo.Z and eye.Z < hi.Z
			check(inside, string.format("  %s %d 号座位的眼睛 (%.1f, %.1f, %.1f) 在机身包围盒里", id, seat, e[1], e[2], e[3]))
			local cf = AM.seatCF(M, seat)
			if cf then
				nPilot += 1
				local head = cf.Position - O
				check((head - eye).Magnitude < 2.5, string.format("  %s %d 号座位的飞行员挪到眼位旁边（差 %.1f 格）", id, seat, (head - eye).Magnitude))
			end
		end
		check(nPilot >= 1, string.format("  %s 座舱里有飞行员（%d 个）", id, nPilot))
		local guess = V3.new(0, d.H * 0.35, -d.L * 0.3) - O   -- 退回去猜的那个点（换成模型坐标）
		local mine = pit[(id == "ah64e" or id == "uh60" or id == "ch47") and 2 or 1]
		local far = (V3.new(mine[1], mine[2], mine[3]) - guess).Magnitude
		check(far > 1.0, string.format("  %s 眼位离原来猜的点 %.1f 格", id, far))
	end
end

print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
process.exit(fails == 0 and 0 or 1)
