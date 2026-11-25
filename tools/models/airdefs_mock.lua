-- 和 tools/models/airdefs.luau 一样把 AirDefs 导成 JSON（tools/models/air2glb.py、sf_air.py 读），给没有 Lune 的机器用：模拟器的 Lua 跑
--   python3 tools/mock/run.py tools/models/airdefs_mock.lua out=<输出.json>
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local out = TEST_ARGS:match("out=(%S+)")
T.boot()
local AD = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs"))
local function enc(x)
  local t = type(x)
  if t == "nil" then return "null" end
  if t == "boolean" then return tostring(x) end
  if t == "number" then if x ~= x or x == math.huge or x == -math.huge then return "null" end return string.format("%.10g", x) end
  if t == "string" then return '"' .. x:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
  if t == "table" then
    local n = #x
    local isArr = n > 0
    if isArr then for k in pairs(x) do if type(k) ~= "number" then isArr = false break end end end
    local parts = {}
    if isArr then for i = 1, n do parts[i] = enc(x[i]) end return "[" .. table.concat(parts, ",") .. "]" end
    for k, v in pairs(x) do if v ~= nil then table.insert(parts, enc(tostring(k)) .. ":" .. enc(v)) end end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "null"
end
local function v(p) return p and { p.X, p.Y, p.Z } or nil end
local res = {}
for id, d in pairs(AD.D) do
  local st = {}
  for i, s in ipairs(d.st or {}) do st[i] = { name = s.name, pos = v(s.pos), bay = s.bay } end
  local eng = {}
  for i, e in ipairs(d.eng or {}) do eng[i] = { e.x, e.y, e.z, e.r, flat = e.flat, prop = e.prop } end
  -- 和 airdefs.luau 一样：eng 每项是数组 + flat / prop 两个键——JSON 里 Lune 会写成对象；air2glb 读的是 e[0..3]
  for i, e in ipairs(eng) do eng[i] = { ["1"] = e[1], ["2"] = e[2], ["3"] = e[3], ["4"] = e[4], flat = e.flat, prop = e.prop } end
  res[id] = {
    kind = d.kind, L = d.L, W = d.W, H = d.H, gearH = d.gearH, fold = d.fold, style = d.style,
    wingY = d.wing and d.wing.y, fus = d.fus and { d.fus.len, d.fus.w, d.fus.h, d.fus.y or 0 },
    st = st, eng = eng,
    stub = d.stub and { d.stub.x, d.stub.span, d.stub.y, d.stub.z },
    rotor = d.rotor and { hub = v(d.rotor.hub), r = d.rotor.r }, rotor2 = d.rotor2 and { hub = v(d.rotor2.hub), r = d.rotor2.r },
    tail = d.tail and { hub = v(d.tail.hub), r = d.tail.r },
    gear = d.gear and { nose = d.gear.nose.z, main = { d.gear.main.x, d.gear.main.z } },
  }
end
local f = io.open(out, "w")
f:write(enc(res))
f:close()
print("写好了 " .. out)
