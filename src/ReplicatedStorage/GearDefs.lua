-- Roblox全面大战场——手持装备用哪件真模型（Sketchfab 原模型：tools/weapons/optics.json → OpticsMeta / OpticMesh / models/optics/<键>.glb）
--   BY[武器] = 键，或者按阵营 { atk = 解放军, def = 美军 }；MOUNT[键] = 这件枪上装的镜子（键、装在这件的哪个点上）
--   服务器（Weapons.lua）发的工具带属性 Gear = 键、GearMount = 镜子的键：导入了原模型（Imported.Optics.<键>）第三人称就是它，
--   第一人称（FPSView）按这两个属性用同一套模型（导入的，或者没导入时客户端现生成的）
--   「握把坐标」：握把 grip 在原点、+Z 朝前（枪口、筒口）、+Y 朝上，按 hold（度，X → Y → Z）转好；第一人称把它放在 M4 握把的位置（再挪 fpOff）
local GD = {}

GD.BY = {
  sniper = { atk = "qbu88", def = "m40a5" },
  rpg = { atk = "rpg7", def = "at4" },
  manpads = { atk = "qw2", def = "stinger" },
  grenade = "m67", medkit = "ifak", repair = "wrench", c4 = "c4", mortar = "m224", binoc = "binoc",
}
GD.MOUNT = { m40a5 = { key = "atacr", at = "rail" } }
-- 第一人称再挪多少（握把坐标，格）：元数据里没写 fpOff 的用这里的
GD.FP = { binoc = { 0, 0.18, 0.06 } }

function GD.key(id, team)
  local b = GD.BY[id]
  if type(b) == "table" then return b[team] or b.def end
  return b
end

local function v3(t) return Vector3.new(t[1], t[2], t[3]) end

-- 器材坐标 → 握把坐标
function GD.grip(M)
  local P = (M and M.pts) or {}
  local g = P.grip or { 0, 0, 0 }
  local h = P.hold or { 0, 0, 0 }
  return CFrame.Angles(math.rad(h[1]), 0, 0) * CFrame.Angles(0, math.rad(h[2]), 0) * CFrame.Angles(0, 0, math.rad(h[3])) * CFrame.new(-g[1], -g[2], -g[3])
end

-- 第一人称的挪动
function GD.fpOff(key, M)
  local P = (M and M.pts) or {}
  local o = P.fpOff or GD.FP[key]
  return o and v3(o) or Vector3.zero
end

-- 镜子装在枪的哪儿（器材坐标）
function GD.mountAt(key, M)
  local mt = GD.MOUNT[key]
  local p = mt and M and M.pts and M.pts[mt.at]
  return p and CFrame.new(p[1], p[2], p[3]) or CFrame.new()
end

-- 枪口 / 筒口（器材坐标）；没写的返回 nil
function GD.muzzle(M)
  local p = M and M.pts and M.pts.muzzle
  return p and v3(p) or nil
end

return GD
