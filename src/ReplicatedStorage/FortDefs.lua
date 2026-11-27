-- Roblox全面大战场——守方工事的型号与摆放（服务器、客户端共用）：地图自带，每局开局时系统摆好，玩家不用（也不能）自己部署
--   工事：机枪碉堡（12.7 毫米机枪，从射孔里打，左右各 60°）、岸防炮（127 毫米舰炮改的岸炮，打登陆艇、舰艇，也打滩上的车）、
--     高炮（双联 35 毫米，近炸引信，只打飞机）、M777 榴弹炮阵地（155 毫米，山脊后面，曲射）；
--     没人操作时 AI 打，自己队的玩家走过去按 E 就能接手操作（F 离开）；能被打掉（伤害类别 fort：步枪几乎打不动，要火箭筒、炸药包、坦克炮、炮击、炸弹）；
--     据点被攻方拿下后，挨着这个据点的工事归攻方
--   障碍：钢刺猬（滩头水线一带，挡车）、铁丝网（滩后，人走进去慢、车压过去就压坏、炸一下就炸断、工兵能剪开）、
--     雷区（滩后两侧，有警示牌；只炸攻方，炮弹落在附近会被引爆，工兵能探出来、排掉）
--   单位：格（1 米约 2.8 格）。工事的坐标系同车辆：原点在底面中心（着地），X 右、Y 上、−Z 朝前（射孔、炮口的默认朝向）
--   摆放按 Map 算，每局一样：服务器开局时照 FortDefs.layout(Map) 建；客户端只按实体属性画样子
local FortDefs = {}
local V = Vector3.new

-- 武器：kind gun 直射（射线判定）、shell 有弹道的炮弹、flak 高炮弹（近炸引信）
--   rate 两发间隔、burst 一个点射几发、pause 点射之间歇多久；range 射程；spread 散布（度）、spreadPer 每格距离多几度
FortDefs.W = {
  hmg = { kind = "gun", dmg = 34, rate = 0.12, burst = { 5, 9 }, pause = { 1.0, 1.8 }, range = 820, spread = 1.2, spreadPer = 0.0035,
    vs = { inf = 1, light = 0.5, armor = 0.04, air = 0.4, ship = 0.05, fort = 0.12 }, fx = "lmg", head = 1 },
  naval127 = { kind = "shell", dmg = 520, speed = 950, gscale = 0.5, splash = 15, rate = 10, range = 3300, minR = 160,   -- rate 原来 8：攻方还没有舰艇压制岸防炮
    vs = { inf = 1, light = 1.4, armor = 0.9, air = 0, ship = 1.4, fort = 1 }, fx = "tank" },
  flak35 = { kind = "flak", dmg = 70, speed = 1150, gscale = 0.15, splash = 11, rate = 0.25, range = 2300, fuse = 9, spread = 1.1,
    vs = { inf = 0.6, light = 0.4, armor = 0.05, air = 2.2, ship = 0.1, fort = 0.2 }, fx = "ac" },
  how155 = { kind = "arty", dmg = 340, splash = 26, rate = 8, minR = 300, maxR = 3800, flight = 6, scatter = 14,
    vs = { inf = 1, light = 1, armor = 0.6, air = 0, ship = 0.5, fort = 1.2 } },
}
for id, w in pairs(FortDefs.W) do w.id = id end
-- 玩家操作时：弹匣（打空了换弹）；AI 打不用换弹
FortDefs.MAG = { hmg = { mag = 100, reload = 5 }, flak35 = { mag = 40, reload = 6 } }

-- 型号：size 命中盒（也挡人）；turret.pivot 转轴（相对底面中心）、trav 每秒转几度、arc 能转到正前方左右各几度（180 = 一圈）、elev 俯仰范围；
--   gun.pivot 耳轴（相对转轴）、len 炮管长；sight 看多远；targets 打哪些目标（inf 步兵、veh 地面车辆、boat 艇和舰、air 飞机）
FortDefs.D = {
  bunker = { hp = 1400, size = V(16, 7.2, 14), weapon = "hmg", sight = 820,
    turret = { pivot = V(0, 4.6, -5.2), trav = 70, arc = 60, elev = { -14, 18 } }, gun = { pivot = V(0, 0, 0), len = 4.4 },
    targets = { inf = true, veh = true } },
  coastal = { hp = 2600, size = V(20, 9, 20), weapon = "naval127", sight = 3300,
    turret = { pivot = V(0, 4.6, 0.6), trav = 18, arc = 150, elev = { -6, 40 } }, gun = { pivot = V(0, 1.6, -4.4), len = 20 },
    targets = { boat = true, veh = true } },
  aaa = { hp = 900, size = V(14, 6, 14), weapon = "flak35", sight = 2300,
    turret = { pivot = V(0, 2.4, 0), trav = 85, arc = 180, elev = { -4, 85 } }, gun = { pivot = V(0, 1.4, -0.6), len = 7.6 },
    targets = { air = true } },
  howitzer = { hp = 1000, size = V(12, 5, 22), weapon = "how155", sight = 3800,
    turret = { pivot = V(0, 3.0, 1.0), trav = 20, arc = 25, elev = { 0, 70 } }, gun = { pivot = V(0, 0.3, 0), len = 14.5 },
    targets = { arty = true } },
}
-- 玩家走到哪儿能接手（相对底面中心）：碉堡后门、炮塔后面、炮架旁边、大架尾巴
FortDefs.MAN = { bunker = V(0, 3, 8.2), coastal = V(0, 2, 11), aaa = V(5.5, 1.5, 3), howitzer = V(3.5, 1.5, 9) }
for id, d in pairs(FortDefs.D) do d.id = id end

function FortDefs.get(id) return FortDefs.D[id] end

-- 炮塔、炮口的世界坐标：base 是底面中心的 CFrame（−Z 朝前）；ty 方位（度，正数往右）、gp 俯仰（度，正数往上）
function FortDefs.turretCF(d, base, ty)
  return base * CFrame.new(d.turret.pivot) * CFrame.Angles(0, -math.rad(ty or 0), 0)
end
function FortDefs.gunCF(d, base, ty, gp)
  return FortDefs.turretCF(d, base, ty) * CFrame.new(d.gun.pivot) * CFrame.Angles(math.rad(gp or 0), 0, 0)
end
function FortDefs.muzzle(d, base, ty, gp)
  return FortDefs.gunCF(d, base, ty, gp) * CFrame.new(0, 0, -d.gun.len)
end

-- 障碍
FortDefs.WIRE = { len = 16, slow = 0.35, r = 4.5 }          -- 一段铁丝网多长、人在里面走路速度乘多少、离铁丝网多近算在里面
FortDefs.MINE = {
  ap = { dmg = 150, splash = 9, vs = { inf = 1, light = 0.5, armor = 0.1, air = 0, ship = 0, fort = 0 }, trig = 3.2 },     -- 防步兵雷
  at = { dmg = 300, splash = 10, vs = { inf = 0.8, light = 3.5, armor = 3.2, air = 0, ship = 0, fort = 0 }, trig = 6.5 },   -- 防坦克雷（只有车压上去才炸）
  chain = 11,   -- 爆炸离雷多近会把它引爆（炮火准备能开出通路）
}

---------------------------------------------------------------- 摆放

-- (x, z) 附近找一块放工事的平地：陆地、四角高差小；返回 x, z（找不到就原地）
local function siteNear(Map, x, z, r, size)
  local best, bx, bz = 1e9, x, z
  local hx, hz = size.X * 0.5, size.Z * 0.5
  for i = 0, 30 do
    local a, rr = i * 2.39996, r * math.sqrt(i / 30)
    local px, pz = x + math.cos(a) * rr, z + math.sin(a) * rr
    local h0 = Map.height(px, pz)
    if h0 > 1.5 then
      local lo, hi = h0, h0
      for _, o in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
        local h = Map.height(px + o[1] * hx, pz + o[2] * hz)
        if h < lo then lo = h end
        if h > hi then hi = h end
      end
      local s = (hi - lo) + rr * 0.015 + ((lo < 1) and 50 or 0)
      if s < best then best, bx, bz = s, px, pz end
    end
  end
  return bx, bz
end
FortDefs.siteNear = siteNear

-- 朝向：从 (x, z) 看向 (tx, tz) 的 CFrame（原点在地面上）
local function faceCF(Map, x, z, tx, tz)
  local y = Map.ground(x, z)
  local p = V(x, y, z)
  local look = V(tx - x, 0, tz - z)
  if look.Magnitude < 0.1 then look = V(0, 0, 1) end
  return CFrame.lookAt(p, p + look.Unit)
end

-- 沙漠图（沙海，没有海）：攻方从南边来（+Z），工事都朝南。边境沙墙开口（据点 A 南边）两侧碉堡交叉火力，
--   各据点南面碉堡、高炮；没有岸防炮；三处 M777 阵地各在一个据点北边约 600 格（够得着自己据点南面的攻击出发阵地，又在最小射程外）
local function layoutDesert(Map)
  local out = {}
  local n = 0
  local function add(kind, x, z, tx, tz, pt, tag, r)
    local d = FortDefs.D[kind]
    local sx, sz = siteNear(Map, x, z, r or 26, d.size)
    n += 1
    table.insert(out, { id = "f" .. n, kind = kind, cf = faceCF(Map, sx, sz, tx, tz), pt = pt, tag = tag })
  end
  local P = {}
  for _, p in ipairs(Map.POINTS) do P[p.id] = p end
  -- 边境：沙墙开口（x = A.x）北侧左右各一座，躲在 11 格高的沙墙后面、斜着封住开口的出口（交叉火力；隔着沙墙往南打不着）；据点 A 南面再两座
  local bz = Map.bermZ(P.A.x)
  add("bunker", P.A.x - 130, bz - 90, P.A.x + 40, bz - 10, "A", "border")
  add("bunker", P.A.x + 130, bz - 90, P.A.x - 40, bz - 10, "A", "border")
  add("bunker", P.A.x - 70, P.A.z + 90, P.A.x - 40, P.A.z + 500, "A", "outpost")
  add("bunker", P.A.x + 70, P.A.z + 90, P.A.x + 40, P.A.z + 500, "A", "outpost")
  add("bunker", P.B.x - 90, P.B.z + 110, P.B.x - 120, P.B.z + 520, "B", "oil")
  add("bunker", P.B.x + 80, P.B.z + 115, P.B.x + 100, P.B.z + 520, "B", "oil")
  add("bunker", P.C.x - 110, P.C.z + 230, P.C.x - 140, P.C.z + 700, "C", "town")
  add("bunker", P.C.x + 120, P.C.z + 225, P.C.x + 150, P.C.z + 700, "C", "town")
  add("bunker", P.D.x, P.D.z + 150, P.D.x, P.D.z + 600, "D", "airfield")
  add("bunker", P.E.x - 70, P.E.z + 70, P.E.x - 120, P.E.z + 500, "E", "command")
  add("bunker", P.E.x + 70, P.E.z + 70, P.E.x + 120, P.E.z + 500, "E", "command")
  -- 高炮：机场两座，各据点一座，后方营地一座
  local A = Map.AIRFIELD
  local ax = math.min(1100, A.len * 0.3) + 60
  add("aaa", A.x - ax, A.z - A.wid / 2 - 70, A.x - ax, A.z + 400, "D", "airfield")
  add("aaa", A.x + ax, A.z - A.wid / 2 - 70, A.x + ax, A.z + 400, "D", "airfield")
  add("aaa", P.E.x + 55, P.E.z - 45, P.E.x, P.E.z + 400, "E", "command")
  add("aaa", P.C.x + 95, P.C.z - 55, P.C.x, P.C.z + 400, "C", "town")
  add("aaa", P.A.x + 55, P.A.z - 40, P.A.x, P.A.z + 400, "A", "outpost")
  add("aaa", P.B.x - 60, P.B.z - 55, P.B.x, P.B.z + 400, "B", "oil")
  if Map.BASES then
    -- 两边主基地（FOB.lua）：营区两侧、机场两头各一门高炮，炮口朝战场；home 写明是哪边的（Forts.lua 按它定归属，据点丢了也不换）
    for side, HB in pairs(Map.BASES) do
      for _, o in ipairs({ { -500, -100 }, { 500, 0 }, { -1500, 900 }, { 1500, 900 } }) do
        local x, z = Map.baseW(HB, o[1], o[2])
        local tx, tz = Map.baseW(HB, o[1], o[2] - 2000)
        add("aaa", x, z, tx, tz, nil, "base_" .. side)
        out[#out].home = side
      end
    end
  else
    add("aaa", Map.CAMP.x - 95, Map.CAMP.z + 15, Map.CAMP.x, Map.CAMP.z + 400, nil, "camp")
  end
  -- M777：A、C、E 北边各两门，炮口朝南
  for _, id in ipairs({ "A", "C", "E" }) do
    local p = P[id]
    local x, z = p.x + 160, p.z - 600
    add("howitzer", x, z, x, z + 1000, id, "battery", 40)
    add("howitzer", x + 36, z + 8, x + 36, z + 1008, id, "battery", 40)
  end
  return out
end

-- 沙漠图的障碍：边境沙墙开口里一排钢刺猬（留两条车道）、开口北边两道铁丝网、开口两侧沙墙后面各一片雷区；据点 B、C 南面也各一道铁丝网
local function obstaclesDesert(Map)
  local rng = Random.new(20261122)
  local hog, wire, mines, signs = {}, {}, {}, {}
  local A
  for _, p in ipairs(Map.POINTS) do if p.id == "A" then A = p end end
  local bx = A.x
  local bz = Map.bermZ(bx)
  -- 钢刺猬：开口（沙墙缺口约 ±60 格）里两排，中间和 ±33 留车道
  for x = bx - 54, bx + 54, 12 do
    for row = 0, 1 do
      local xx = x + row * 6
      local rel = math.abs(xx - bx)
      if rel >= 15 and not (rel > 22 and rel < 42) then table.insert(hog, { x = xx, z = bz + 6 - row * 13, rot = rng:NextNumber(0, math.pi) }) end
    end
  end
  -- 铁丝网：开口北边 45、72 格两道（隔段留缺口）；B、C 南面 160 格一道
  local function wireLine(x0, x1, z, skip, tag)
    local i, x = 0, x0
    while x + FortDefs.WIRE.len <= x1 do
      i += 1
      if i % 3 ~= skip then table.insert(wire, { a = V(x, 0, z), b = V(x + FortDefs.WIRE.len, 0, z), beach = tag }) end
      x += FortDefs.WIRE.len
    end
  end
  wireLine(bx - 120, bx + 120, bz - 45, 2, "border")
  wireLine(bx - 112, bx + 128, bz - 72, 0, "border")
  for _, p in ipairs(Map.POINTS) do
    if p.id == "B" or p.id == "C" then wireLine(p.x - 160, p.x + 160, p.z + 160, 1, p.id) end
  end
  -- 雷区：开口两侧、沙墙北边（离开口 90～150 格），四角警示牌朝南
  for fi, side in ipairs({ -1, 1 }) do
    local cx, cz = bx + side * 120, bz - 40
    local field = { w = 50, d = 36 }
    for _ = 1, 10 do
      local x = cx + rng:NextNumber(-field.w / 2, field.w / 2)
      local z = cz + rng:NextNumber(-field.d / 2, field.d / 2)
      table.insert(mines, { x = x, z = z, at = rng:NextNumber() < 0.4, field = fi })
    end
    for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
      table.insert(signs, { x = cx + c[1] * (field.w / 2 + 3), z = cz + c[2] * (field.d / 2 + 3), face = 1 })
    end
  end
  return { hog = hog, wire = wire, mines = mines, signs = signs }
end

-- 城市图（钢城，MapCity.lua）：两边对称，城里不摆碉堡、榴弹炮（城里的掩护是楼）；只有两边主基地各四门高炮（营区两侧、跑道两头）
local function layoutCity(Map)
  local out = {}
  local n = 0
  for side, HB in pairs(Map.BASES) do
    for _, o in ipairs({ { -500, -100 }, { 500, 0 }, { -1500, 900 }, { 1500, 900 } }) do
      local x, z = Map.baseW(HB, o[1], o[2])
      local tx, tz = Map.baseW(HB, o[1], o[2] - 2000)
      local d = FortDefs.D.aaa
      local sx, sz = siteNear(Map, x, z, 26, d.size)
      n += 1
      table.insert(out, { id = "f" .. n, kind = "aaa", cf = faceCF(Map, sx, sz, tx, tz), tag = "base_" .. side, home = side })
    end
  end
  return out
end

-- 全部工事：{ id, kind（bunker / coastal / aaa）, cf（底面中心，−Z 朝前）, pt（附近的据点：据点被攻方拿下后这处工事就废了）, tag（位置名） }
function FortDefs.layout(Map)
  if Map.CITY or Map.SNOW then return layoutCity(Map) end   -- 钢城、雪山：两边主基地的防空阵地
  if Map.LANDONLY then return layoutDesert(Map) end
  local out = {}
  local n = 0
  local function add(kind, x, z, tx, tz, pt, tag, r)
    local d = FortDefs.D[kind]
    local sx, sz = siteNear(Map, x, z, r or 26, d.size)
    n += 1
    table.insert(out, { id = "f" .. n, kind = kind, cf = faceCF(Map, sx, sz, tx, tz), pt = pt, tag = tag })
  end
  -- 南岸四处海滩：每处两座机枪碉堡，在滩后高处、离岸约 100 格，射孔斜对着滩中间（交叉火力）
  for _, b in ipairs(Map.BEACHES) do
    if not b.north then
      local w = b.x1 - b.x0
      for _, f in ipairs({ 0.12, 0.88 }) do
        local x = b.x0 + w * f
        local zc = Map.coastS(x) or b.z
        add("bunker", x, zc - 105, b.cx, b.z + 40, nil, b.id)
      end
    else   -- 东北侧翼滩：一座，朝北
      local x = b.cx + 30
      local zc = Map.coastN(x) or b.z
      add("bunker", x, zc + 95, b.cx, b.z - 40, nil, b.id)
    end
  end
  -- 港湾：湾口两侧各一座，对着湾里
  local BAY = Map.BAY
  for s = -1, 1, 2 do
    local x = BAY.x + s * (BAY.w + 55)
    local zc = Map.coastS(x) or Map.PORT.z
    add("bunker", x, zc - 45, BAY.x, (Map.coastS(BAY.x) or Map.PORT.z) + 160, "C", "port")
  end
  -- 据点
  local P = {}
  for _, p in ipairs(Map.POINTS) do P[p.id] = p end
  add("bunker", P.A.x - 75, P.A.z + 95, P.A.x - 40, P.A.z + 400, "A", "outpost")
  add("bunker", P.A.x + 75, P.A.z + 95, P.A.x + 40, P.A.z + 400, "A", "outpost")
  add("bunker", P.B.x - 90, P.B.z + 120, P.B.x - 120, P.B.z + 500, "B", "lighthouse")
  add("bunker", P.B.x + 60, P.B.z + 125, P.B.x + 80, P.B.z + 500, "B", "lighthouse")
  add("bunker", P.D.x, P.D.z + 150, P.D.x, P.D.z + 600, "D", "airfield")
  add("bunker", P.E.x - 70, P.E.z + 70, P.E.x - 120, P.E.z + 500, "E", "command")
  add("bunker", P.E.x + 70, P.E.z + 70, P.E.x + 120, P.E.z + 500, "E", "command")
  -- 岸防炮：东西两个岬角的崖顶、西礁岛炮台、灯塔岛西南角；炮口朝南（舰队、登陆艇来的方向）
  for _, cape in ipairs(Map.CAPES) do
    local cx = cape.x
    local zc = Map.coastS(cx) or -700
    add("coastal", cx, zc - 48, cx * 0.6, zc + 1200, nil, "cape", 20)
  end
  local WR = Map.WESTREEF
  add("coastal", WR.x + 40, WR.z + 60, WR.x + 900, WR.z + 1000, nil, "westreef", 18)
  local LH = Map.LIGHTHOUSE
  add("coastal", LH.x - 130, LH.z + 110, LH.x - 900, LH.z + 1100, "B", "lighthouse", 20)
  -- 高炮：机场两座、指挥所、港口、两座小岛据点、后方营地
  local A = Map.AIRFIELD
  local ax = math.min(1100, A.len * 0.3) + 60   -- 跑道两头停机坪外（飞机生成点在跑道中间偏西，别挡着）
  add("aaa", A.x - ax, A.z - A.wid / 2 - 70, A.x - ax, A.z + 400, "D", "airfield")
  add("aaa", A.x + ax, A.z - A.wid / 2 - 70, A.x + ax, A.z + 400, "D", "airfield")
  add("aaa", P.E.x + 55, P.E.z - 45, P.E.x, P.E.z + 400, "E", "command")
  add("aaa", P.C.x + 95, P.C.z - 55, P.C.x, P.C.z + 400, "C", "port")
  add("aaa", P.A.x + 55, P.A.z - 40, P.A.x, P.A.z + 400, "A", "outpost")
  add("aaa", P.B.x - 60, P.B.z - 55, P.B.x, P.B.z + 400, "B", "lighthouse")
  add("aaa", Map.CAMP.x - 95, Map.CAMP.z + 15, Map.CAMP.x, Map.CAMP.z + 400, nil, "camp")
  -- M777 榴弹炮阵地：指挥所东北、山脊背面（从海上看不见），两门炮口朝南，够得着南岸各处海滩
  local C = Map.COMMAND
  add("howitzer", C.x + 150, C.z - 70, C.x + 150, C.z + 1000, "E", "battery", 30)
  add("howitzer", C.x + 185, C.z - 62, C.x + 185, C.z + 1000, "E", "battery", 30)
  return out
end

-- 滩头的通道：中间一条清空的（登陆艇、气垫艇冲滩的地方），两侧各一个钢刺猬缺口；缺口后面不埋雷（雷区在滩的两翼）
--   （钢刺猬间隔 12 格、两排错开 6 格：缺口在离滩中间 22～42 格之间，两排都空出来的地方中心约在 ±33）
FortDefs.LANE = { half = 15, gap0 = 22, gap1 = 42, gapC = 33 }
function FortDefs.lanes(b)
  if not b.x0 then return { b.cx } end
  local g = FortDefs.LANE.gapC
  return { b.cx, b.cx - g, b.cx + g }
end

-- 滩头障碍：钢刺猬（水线一带两排，留出通道和缺口）、铁丝网（两道、隔段留缺口）、雷区（滩的两翼各一片）；用固定种子，每局一样
function FortDefs.obstacles(Map)
  if Map.CITY or Map.SNOW then return { hog = {}, wire = {}, mines = {}, signs = {} } end   -- 钢城：没有滩头障碍、雷区（城里的掩护是楼、车厢、水泥墩）
  if Map.LANDONLY then return obstaclesDesert(Map) end   -- 沙海：边境沙墙前的钢刺猬、铁丝网、雷区
  local rng = Random.new(20240611)
  local L = FortDefs.LANE
  local hog, wire, mines, signs = {}, {}, {}, {}
  for bi, b in ipairs(Map.BEACHES) do
    local coast = b.north and Map.coastN or Map.coastS
    local inland = b.north and 1 or -1   -- 往岛里是 +Z（北岸）还是 −Z（南岸）
    -- 钢刺猬：两排，前排在水线外 6 格（浅水里），后排在滩上 7 格、错开半格
    for x = b.x0 + 6, b.x1 - 6, 12 do
      for row = 0, 1 do
        local xx = x + row * 6
        local rel = math.abs(xx - b.cx)
        if rel >= L.half and not (rel > L.gap0 and rel < L.gap1) and xx <= b.x1 - 4 then
          local zc = coast(xx)
          if zc then
            local rot = rng:NextNumber(0, math.pi)
            -- 前排在水线外 6 格；坡缓的滩那里已经两格多深（原来夹在 −1.4 格高，整个浮在水面上——用户 11-18：这些建筑漂在水里），
            --   太深就往岸边挪，挪到水深两格以内：立在海底，尖头露出水面
            local off = (row == 0) and 6 or -7
            while off > 0 and Map.height(xx, zc - inland * off) < -2 do off -= 1 end
            table.insert(hog, { x = xx, z = zc - inland * off, rot = rot })
          end
        end
      end
    end
    -- 铁丝网：离岸 45 格、72 格两道，各隔段留缺口
    for line = 0, 1 do
      local d = (line == 0) and 45 or 72
      local i = 0
      local x = b.x0 + (line == 0 and 0 or 8)
      while x + FortDefs.WIRE.len <= b.x1 + 10 do
        i += 1
        if i % 3 ~= ((line == 0) and 2 or 0) then
          local xa, xb = x, x + FortDefs.WIRE.len
          local za, zb = coast(xa), coast(xb)
          if za and zb then
            table.insert(wire, { a = V(xa, 0, za + inland * d), b = V(xb, 0, zb + inland * d), beach = b.id })
          end
        end
        x += FortDefs.WIRE.len
      end
    end
    -- 雷区：滩的两翼（离岸 48～88 格），四角立警示牌
    for _, side in ipairs({ -1, 1 }) do
      local cx = (side < 0) and (b.x0 + 22) or (b.x1 - 22)
      local zc = coast(cx)
      if zc then
        local cz = zc + inland * 68
        local field = { w = 32, d = 40 }
        for _ = 1, 8 do
          local x = cx + rng:NextNumber(-field.w / 2, field.w / 2)
          local z = cz + rng:NextNumber(-field.d / 2, field.d / 2)
          if Map.isLand(x, z) then table.insert(mines, { x = x, z = z, at = rng:NextNumber() < 0.35, field = bi * 2 + (side > 0 and 1 or 0) }) end
        end
        for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
          table.insert(signs, { x = cx + c[1] * (field.w / 2 + 3), z = cz + c[2] * (field.d / 2 + 3), face = -inland })
        end
      end
    end
  end
  return { hog = hog, wire = wire, mines = mines, signs = signs }
end

return FortDefs
