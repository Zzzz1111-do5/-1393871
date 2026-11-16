--!nocheck
-- 把 ShipDefs 里转换舰艇原模型要用的数据导成 JSON（tools/models/ship2glb.py 读）：尺寸、吃水、甲板高、炮位、上层建筑（夜航灯的位置）
-- 用法（仓库根目录）：lune run tools/models/shipdefs.luau > <输出.json>
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local env = setmetatable({ Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Color3 = roblox.Color3 }, { __index = _G })
local SD = luau.load(fs.readFile("src/ReplicatedStorage/ShipDefs.lua"), { environment = env, debugName = "ShipDefs" })()

local function v(p) return p and { p.X, p.Y, p.Z } or nil end
local out = {}
for id, d in pairs(SD.D) do
	local guns = {}
	for i, g in ipairs(d.guns or {}) do guns[i] = { pos = v(g.pos), size = v(g.size), len = g.len, aft = g.aft == true } end
	local ciws = {}
	for i, p in ipairs(d.ciws or {}) do ciws[i] = v(p) end
	local L = d.look or {}
	out[id] = { L = d.L, W = d.W, H = d.H, draft = d.draft, deck = d.deck, guns = guns, ciws = ciws, sup = L.sup, mast = v(L.mast), mastH = L.mastH, open = L.open == true }
end
print(serde.encode("json", out, true))
