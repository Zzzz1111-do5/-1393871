-- 同 tools/models/airdefs.luau：把 AirDefs 里转换飞机原模型要用的数据导成 JSON（tools/models/air2glb.py 读），没有 Lune 的机器上用模拟器（Lua 5.4）跑
-- 用法（仓库根目录）：python3 tools/mock/run.py tools/models/airdefs.lua > <输出.json>
local R = dofile(MOCK_DIR .. "/rbx.lua")
dofile(MOCK_DIR .. "/load.lua")(R, SRC_DIR)
local AD = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs"))

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

-- JSON：连续整数键（1..n）的表是数组，其余是对象（键排序，输出稳定）
local function enc(x, ind)
  local t = type(x)
  if t == "nil" then return "null" end
  if t == "boolean" then return tostring(x) end
  if t == "number" then
    if x ~= x or x == math.huge or x == -math.huge then return "null" end
    if math.type(x) == "integer" or (x == math.floor(x) and math.abs(x) < 1e15) then return string.format("%d", math.floor(x)) end
    return string.format("%.10g", x)
  end
  if t == "string" then
    return '"' .. x:gsub('[%c"\\]', function(c)
      local m = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\t'] = '\\t', ['\r'] = '\\r' }
      return m[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
  end
  if t ~= "table" then return "null" end
  local pad, pad2 = string.rep("  ", ind), string.rep("  ", ind + 1)
  local n = #x
  local isArr = n > 0
  for k in pairs(x) do
    if math.type(k) ~= "integer" or k < 1 or k > n then isArr = false break end
  end
  local items = {}
  if isArr then
    for i = 1, n do items[i] = pad2 .. enc(x[i], ind + 1) end
    return "[\n" .. table.concat(items, ",\n") .. "\n" .. pad .. "]"
  end
  local keys = {}
  for k in pairs(x) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local val = x[k]
    if val == nil then val = x[tonumber(k)] end
    items[#items + 1] = pad2 .. enc(k, 0) .. ": " .. enc(val, ind + 1)
  end
  if #items == 0 then return "{}" end
  return "{\n" .. table.concat(items, ",\n") .. "\n" .. pad .. "}"
end
io.stdout:write(enc(out, 0), "\n")
