-- 改枪：配件装在第一人称 M4 上的位置导出成 JSON（给 tools/weapons/gunrender.mjs 拍图核对：消音器对不对得上枪管、瞄具光轴、弹匣、握把、激光）
--   python3 tools/mock/run.py tools/mock/gunmount.lua out=<文件.json>
--   每套配件：M4 各块（待机姿势、枪身骨骼坐标，同 FPSView 的 G.m4Model）+ 每样配件的器材原点（GunMods.m4Mount）+ 瞄具光轴
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
T.scripts = dofile(MOCK_DIR .. "/load.lua")(R, SRC_DIR)
local RS = R.services.ReplicatedStorage
local GM = R.require(RS:FindFirstChild("GunMods"))
local OM = R.require(RS:FindFirstChild("OpticsMeta"))
local A = R.require(RS:FindFirstChild("FPSAnim"))
local CF, V = R.CFrame.new, R.Vector3.new
local out = TEST_ARGS:match("out=(%S+)") or "gunmount.json"

local function quatCF(x, y, z, qx, qy, qz, qw)
  local xx, yy, zz = qx * qx, qy * qy, qz * qz
  local xy, xz, yz = qx * qy, qx * qz, qy * qz
  local wx, wy, wz = qw * qx, qw * qy, qw * qz
  return R.CFrame.fromMatrix(V(x, y, z), V(1 - 2 * (yy + zz), 2 * (xy + wz), 2 * (xz - wy)),
    V(2 * (xy - wz), 1 - 2 * (xx + zz), 2 * (yz + wx)), V(2 * (xz + wy), 2 * (yz - wx), 1 - 2 * (xx + yy)))
end
local function idle(track)
  local arr = A.clips.Idle.t[track]
  return quatCF(arr[1], arr[2], arr[3], arr[4], arr[5], arr[6], arr[7])
end
local g0 = idle("gun"):Inverse()
local function trackCF(track) return g0 * idle(track) end
local function arr(cf)
  local c = { cf:GetComponents() }
  for i = 1, #c do c[i] = math.floor(c[i] * 1e5 + 0.5) / 1e5 end
  return c
end
local function v3(v) return { v.X, v.Y, v.Z } end

local custom = TEST_ARGS:match("build=(%S+)")   -- 只导这一套（"muzzle=sup_socom;optic=opt_holo;..."）
local BUILDS = custom and { { name = "custom", b = GM.decode(custom) } } or {
  { name = "default", b = GM.default("m4") },
  { name = "socom_holo_rvg_p40_peq", b = { muzzle = "sup_socom", optic = "opt_holo", grip = "grip_rvg", mag = "mag_pmag40", tac = "tac_peq" } },
  { name = "comp_rds_afg_drum_light", b = { muzzle = "muz_comp", optic = "opt_rds", grip = "grip_afg", mag = "mag_drum", tac = "tac_light" } },
  { name = "sr8_acog6_p20", b = { muzzle = "sup_sr8", optic = "opt_acog6", grip = "grip_rvg", mag = "mag_pmag20", tac = "tac_none" } },
  { name = "brake_romeo_hex30", b = { muzzle = "muz_brake", optic = "opt_romeo", grip = "grip_none", mag = "mag_hex30", tac = "tac_peq" } },
  { name = "wrap_iron", b = { muzzle = "sup_wrap", optic = "iron", grip = "grip_afg", mag = "mag_std", tac = "tac_light" } },
}

local res = { m4 = {}, builds = {}, meta = {}, sightIron = { rear = { 0.005, 0.215, -0.14 }, front = { 0.005, 0.215, 0.975 } } }
for name, info in pairs(A.mesh) do
  table.insert(res.m4, { node = name, piece = info.piece, cf = arr(trackCF(info.piece)), c = info.c })
end
for _, B in ipairs(BUILDS) do
  local b = GM.clean("m4", B.b)
  local e = { name = B.name, build = b, att = {}, skipMag = b.mag ~= "mag_std" }
  for _, slot in ipairs(GM.SLOTS) do
    local id = b[slot]
    local it = GM.ITEM[id]
    local M = it and it.model and OM[it.model]
    local mt = M and GM.m4Mount(id, M)
    if mt then
      local tracks = (mt.track == "mag") and { "mag1" } or { "gun" }
      for _, tr in ipairs(tracks) do
        local at = trackCF(tr) * mt.cf
        local a = { slot = slot, item = id, model = it.model, cf = arr(at) }
        if it.glass then
          a.glass = {}
          for k in pairs(it.glass) do table.insert(a.glass, k) end
        end
        a.adsD = it.adsD
        if mt.mz then a.mz = v3(mt.mz) end
        if mt.riser then a.riser = mt.riser end
        if slot == "optic" then
          local sg = GM.sightOf(id, M)
          if sg then a.eye, a.obj, a.r = v3(at * sg.eye), v3(at * sg.obj), sg.r end
          a.zoom = it.zoom
          a.K = it.lensK   -- 开镜时目镜占屏幕高度的几成（瞄准镜）
          a.kind = it.scope and "scope" or "dot"
        end
        table.insert(e.att, a)
        res.meta[it.model] = res.meta[it.model] or { parts = M.parts, size = M.size, inner = M.inner }
      end
    end
  end
  table.insert(res.builds, e)
end

-- 简单的 JSON（只有表、数、字符串、布尔）
local function enc(x)
  local t = type(x)
  if t == "number" then return (x == math.floor(x) and math.abs(x) < 1e15) and string.format("%d", x) or string.format("%.6g", x) end
  if t == "string" then return '"' .. x:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"' end
  if t == "boolean" then return tostring(x) end
  if t == "table" then
    if #x > 0 or next(x) == nil then
      local p = {}
      for i = 1, #x do p[i] = enc(x[i]) end
      return "[" .. table.concat(p, ",") .. "]"
    end
    local p = {}
    for k, v in pairs(x) do p[#p + 1] = enc(tostring(k)) .. ":" .. enc(v) end
    return "{" .. table.concat(p, ",") .. "}"
  end
  return "null"
end
local f = io.open(out, "w")
f:write(enc(res))
f:close()
print("写到 " .. out .. "：" .. #res.builds .. " 套")
