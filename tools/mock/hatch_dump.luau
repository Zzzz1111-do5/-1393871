--!nocheck
-- 舱盖预览的数据：按 HatchDefs 算每辆车每块舱盖在关 / 半开 / 全开时的位置（模型坐标：车体不动，炮塔朝前），写成 JSON 给 tools/mock/hatch_view.cjs 画
--   用法（仓库根目录）：lune run tools/mock/hatch_dump.luau <输出.json> [键 ...]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local env = setmetatable({ Vector3 = roblox.Vector3, CFrame = roblox.CFrame }, { __index = _G })
local HD = luau.load(fs.readFile("src/ReplicatedStorage/HatchDefs.lua"), { debugName = "HatchDefs", environment = env })()
local IM = luau.load(fs.readFile("src/ReplicatedStorage/ImportedMeta.lua"), { debugName = "ImportedMeta", environment = env })()
local V, CF = roblox.Vector3.new, roblox.CFrame.new
local out = process.args[1]
local keys = {}
for i = 2, #process.args do table.insert(keys, process.args[i]) end
if #keys == 0 then keys = { "m1a2dc", "m1a1i", "ztz99a2", "ztz96", "t90m", "m2a3", "stryker", "bmp3", "zbd97", "lav25", "matv" } end
local function comp(cf)
  local t = { cf:GetComponents() }
  return t
end
local data = {}
for _, key in ipairs(keys) do
  local info = IM.m[key]
  local tpiv = info and info.tur and V(info.tur[1], info.tur[2], info.tur[3]) or V()
  local list = {}
  for _, d in ipairs(HD[key] or {}) do
    local h = HD.prep(d, tpiv)
    local frame = (h.g == "hull") and CF() or CF(tpiv)
    local e = { id = h.id, m = h.m, g = h.g, shape = h.shape, size = { h.size.X, h.size.Y, h.size.Z }, holeSize = { h.holeSize.X, h.holeSize.Y, h.holeSize.Z },
      hole = comp(frame * h.holeCF), at = {} }
    for _, p in ipairs({ 0, 0.25, 0.5, 0.75, 1 }) do table.insert(e.at, comp(frame * HD.lidCF(h, p))) end
    if h.m == "abrams" then e.op = comp(frame * HD.lidCF(h, HD.ABRAMS_OP)) end
    table.insert(list, e)
  end
  data[key] = { tur = { tpiv.X, tpiv.Y, tpiv.Z }, hatches = list }
end
fs.writeFile(out, serde.encode("json", data))
print("写好 " .. out)
