-- Roblox全面大战场——子弹打在什么上面（弹着点的样子、声音按它出；用户：枪打在坦克上要有火花）：
--   服务器发枪响特效时带上（Weapons.lua 的 KIND.gun、G.botShot），自己开的枪客户端照同样的规则判（Fx.lua）
--   a 装甲车辆（坦克、步战车、自行火炮：钢甲火花、叮当声、跳弹）  l 轻型车辆（悍马、卡车）  m 飞机、金属物件  s 舰艇
--   c 工事（混凝土碎屑）  f 人  w 水  n 沙  d 泥土  v 草地  i 雪  j 冰  r 石头、水泥、砖  o 木头  g 玻璃
--   （11-27：雪、冰、草地从「泥土」「石头」里分出来——雪山整张图的弹着点原来都是褐色土花、打在冰面上迸火星；服务器只看 METAL，别的代号原样转给客户端）
local HitSurf = {}

local CAT = { armor = "a", light = "l", air = "m", ship = "s", fort = "c", inf = "f" }   -- 实体的伤害类别（Ents.lua 的 Cat 属性）

-- 材质 → 代号（按名字查：模拟器 / 旧版本缺的材质就跳过）
local function byName(t)
  local out = {}
  for name, code in pairs(t) do
    local ok, e = pcall(function() return Enum.Material[name] end)
    if ok and e then out[e] = code end
  end
  return out
end
local TERRAIN = byName({ Water = "w", Sand = "n", Sandstone = "n", Salt = "n",
  Grass = "v", LeafyGrass = "v", Ground = "d", Mud = "d", Snow = "i",
  Rock = "r", Basalt = "r", Slate = "r", Concrete = "r", Asphalt = "r", Pavement = "r", Limestone = "r", Cobblestone = "r",
  Brick = "r", Granite = "r", CrackedLava = "r", Glacier = "j", Ice = "j" })
local PART = byName({ Metal = "m", DiamondPlate = "m", CorrodedMetal = "m", Foil = "m",
  Wood = "o", WoodPlanks = "o", Glass = "g", Sand = "n", Grass = "v", Ground = "d", Mud = "d", Fabric = "d", LeafyGrass = "v", Snow = "i", Ice = "j", Glacier = "j" })

-- inst：射线打中的零件；material：射线结果的材质（地形按它分）
function HitSurf.of(inst, material)
  if not inst then return nil end
  if inst:IsA("Terrain") then return TERRAIN[material] or "d" end
  local m = inst
  while m and m ~= workspace do
    if m:IsA("Model") then
      local c = m:GetAttribute("Cat")
      if c then return CAT[c] or "m" end
      if m:FindFirstChildOfClass("Humanoid") then return "f" end
    end
    m = m.Parent
  end
  return PART[material or inst.Material] or "r"
end

-- 金属面（出火花）
HitSurf.METAL = { a = true, l = true, m = true, s = true }

return HitSurf
