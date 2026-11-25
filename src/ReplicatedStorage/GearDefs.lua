-- Roblox全面大战场——手持装备用哪件真模型（Sketchfab 原模型：tools/weapons/optics.json → OpticsMeta / OpticMesh / models/optics/<键>.glb）
--   BY[武器] = 键，或者按阵营 { atk = 解放军, def = 美军 }；MOUNT[键] = 这件枪上装的镜子（键、装在这件的哪个点上）
--   服务器（Weapons.lua）发的工具带属性 Gear = 键、GearMount = 镜子的键：导入了原模型（Imported.Optics.<键>）第三人称就是它，
--   第一人称（FPSView）按这两个属性用同一套模型（导入的，或者没导入时客户端现生成的）
--   「握把坐标」：握把 grip 在原点、+Z 朝前（枪口、筒口）、+Y 朝上，按 hold（度，X → Y → Z）转好；第一人称把它放在 M4 握把的位置（再挪 fpOff）
local GD = {}

GD.BY = {
  sniper = { atk = "qbu88", def = "m40a5" },
  -- 各兵种的枪（用户 11-24：「各种角色配备各种武器」）：同一种枪两边各用自己的制式（解放军 / 美军）
  qbz191 = "qbz191",                              -- 解放军 QBZ-191 步枪（自己选的主武器；两边都能用）
  lmg = { atk = "qjy88", def = "m249" },          -- 机枪手：QJY-88 通用机枪 / M249 轻机枪
  smg = { atk = "qcw05", def = "mp7" },           -- 冲锋枪：QCW-05 / MP7A1
  shotgun = { atk = "qbs09", def = "m1014" },     -- 霰弹枪：QBS-09 / M1014
  pistol = { atk = "qsz92", def = "m17" },        -- 手枪（副武器）：QSZ-92 / M17
  rpg = { atk = "rpg7", def = "at4" },
  manpads = { atk = "qw2", def = "stinger" },
  grenade = "m67", medkit = "ifak", repair = "wrench", c4 = "c4", mortar = "m224", binoc = "binoc",
}
GD.MOUNT = { m40a5 = { key = "atacr", at = "rail" } }
-- 第一人称再挪多少（握把坐标，格）：元数据里没写 fpOff 的用这里的
--   手枪：比步枪的握把位置靠前、靠中间一点（两手往前伸着端），冲锋枪略靠前
GD.FP = { binoc = { 0, 0.18, 0.06 }, qsz92 = { -0.08, 0.1, -0.22 }, m17 = { -0.08, 0.1, -0.22 }, qcw05 = { 0, 0.02, -0.06 }, mp7 = { 0, 0.02, -0.06 } }
-- 单手握把（手枪）：第一人称左手托着右手，不按步枪的姿势伸到护木那儿
GD.PISTOL = { qsz92 = true, m17 = true }

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

-- 机械瞄具（器材坐标）：照门 sightR、准星 sightF——第一人称开镜时这条线对到屏幕正中；没写的返回 nil
function GD.sights(M)
  local P = M and M.pts
  if not (P and P.sightR and P.sightF) then return nil end
  return v3(P.sightR), v3(P.sightF)
end

-- 枪口 / 筒口（器材坐标）；没写的返回 nil
function GD.muzzle(M)
  local p = M and M.pts and M.pts.muzzle
  return p and v3(p) or nil
end

return GD
