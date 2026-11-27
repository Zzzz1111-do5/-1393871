-- 全面大战场——地图分区（ReplicatedStorage.Zones）：一台服务器里几块互不相连的区块，各是各的地图
--   用户 11-26 晚：「把训练场单独做一张地图吧」「目前游戏里的几个地图是连起来的 不行 我需要每个地图单独一个区块或者说单独一个服务器」——
--   原来机库厂房、机库停机坪、主菜单场景搭在 (±9000, 900, ±9000)：钢城地形铺到 ±12288、飞机作战区 ±24576，几处场景就悬在战场上空、
--   开飞机看得见；试驾在战场边上（钢城东边丘陵）打靶，开出去就进了战场。现在分成三块，中间隔着几万格（雾、地平线早就盖住了）：
--   · 战场 battle：中心在原点（钢城 / 沙海 / 雪山……一台服务器开一张，开服投票定，init.server.lua）
--   · 训练场 range：自己的一张图（MapRange.lua：靶道、靶场、跑道、直升机坪、四周丘陵），中心 (0, 0, 100352)——
--     离最大的沙海作战区边上（±36864）还有五万多格；试驾（Tech.lua）都在这里
--   · 大厅 lobby：主菜单场景、机库厂房、机库停机坪（只在本机画，MenuStage / HangarStage），x = −100000 那一片，三处各隔三万格
--   地图的高度、材质这些函数（Map.height……）按坐标落在哪块分派（Map.lua 的 zoneWrap）：训练场里的点问 MapRange，别处照旧问战场那张图
local Z = {}

Z.RANGE = {
  name = "range",
  x = 0, z = 100352,   -- 中心（世界坐标；2048 的倍数：远处那圈平地按 2048 一块拼，正好对齐）
  R = 12288,           -- 地形铺到中心 ±R（再往外是客户端跟着镜头的一圈平地，Scenery.lua）
  PLAY = 20000,        -- 飞机作战区 ±PLAY（再往外自动掉头）
}
Z.LOBBY = { name = "lobby", x = -100000, z = 0 }
-- 大厅里的三处场景（只在本机）：原点（场景里的零件按它摆）
Z.HANGAR = CFrame.new(-100000, 900, 0)
Z.HANGAR_AIR = CFrame.new(-100000, 900, -30000)
Z.MENU = CFrame.new(-100000, 900, 30000)

local abs = math.abs
local RX, RZ, RB = Z.RANGE.x, Z.RANGE.z, Z.RANGE.PLAY + 8000

-- 这一点在不在训练场那一块（作战区再往外 8000 格都算：掉头的弯、炮弹飞出去也还是训练场）
function Z.inRange(x, z)
  return abs(x - RX) <= RB and abs(z - RZ) <= RB
end
-- 一点在哪块："range" / "lobby" / "battle"
function Z.of(x, z)
  if abs(x - RX) <= RB and abs(z - RZ) <= RB then return "range" end
  if x < -60000 then return "lobby" end
  return "battle"
end
function Z.ofPos(p) return Z.of(p.X, p.Z) end
-- 区块中心
function Z.center(name)
  if name == "range" then return RX, RZ end
  if name == "lobby" then return Z.LOBBY.x, Z.LOBBY.z end
  return 0, 0
end
-- 相对区块中心的坐标（边界检查都按它）
function Z.rel(x, z)
  local n = Z.of(x, z)
  local cx, cz = Z.center(n)
  return x - cx, z - cz, n
end
-- 飞机作战区的半边长（Fly.lua 出界掉头、Air.lua 服务器不认）
function Z.play(name, Map)
  if name == "range" then return Z.RANGE.PLAY end
  return (Map and Map.PLAY) or 20000
end
-- 地面车、炮弹能到的半边长（Armor.lua 同步检查、Ents.lua 收掉飞出地图的炮弹）
function Z.land(name, Map)
  if name == "range" then return Z.RANGE.R end
  return (Map and Map.R) or 12288
end

return Z
