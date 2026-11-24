-- 把 ImportedMeta.lua（或别的纯数据 Lua 模块）转成 JSON 打出来（carve.py 用）：lune run tools/models/meta2json.luau src/ReplicatedStorage/ImportedMeta.lua
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local process = require("@lune/process")
local path = process.args[1] or "src/ReplicatedStorage/ImportedMeta.lua"
local src = fs.readFile(path)
local t = luau.load(src, { debugName = path })()
print(serde.encode("json", t, false))
