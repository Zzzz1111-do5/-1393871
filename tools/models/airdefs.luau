--!nocheck
-- 把 AirDefs 里转换飞机原模型要用的数据导成 JSON（tools/models/air2glb.py 读）：尺寸、起落架高度、挂点、短翼、旋翼、尾喷口、起落架位置
-- 用法（仓库根目录）：lune run tools/models/airdefs.luau > <输出.json>
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local env = setmetatable({ Vector3 = roblox.Vector3, CFrame = roblox.CFrame }, { __index = _G })
local AD = luau.load(fs.readFile("src/ReplicatedStorage/AirDefs.lua"), { environment = env, debugName = "AirDefs" })()

local function v(p) return p and { p.X, p.Y, p.Z } or nil end
local out = {}
for id, d in pairs(AD.D) do
	local st = {}
	for i, s in ipairs(d.st or {}) do
		st[i] = { name = s.name, pos = v(s.pos), bay = s.bay }
	end
	local eng = {}
	for i, e in ipairs(d.eng or {}) do eng[i] = { e.x, e.y, e.z, e.r, flat = e.flat, prop = e.prop } end
	out[id] = {
		kind = d.kind, L = d.L, W = d.W, H = d.H, gearH = d.gearH, fold = d.fold, style = d.style,
		wingY = d.wing and d.wing.y, fus = d.fus and { d.fus.len, d.fus.w, d.fus.h, d.fus.y or 0 },
		st = st, eng = eng,
		stub = d.stub and { d.stub.x, d.stub.span, d.stub.y, d.stub.z },
		rotor = d.rotor and { hub = v(d.rotor.hub), r = d.rotor.r }, rotor2 = d.rotor2 and { hub = v(d.rotor2.hub), r = d.rotor2.r },
		tail = d.tail and { hub = v(d.tail.hub), r = d.tail.r },
		gear = d.gear and { nose = d.gear.nose.z, main = { d.gear.main.x, d.gear.main.z } },
	}
end
print(serde.encode("json", out, true))
