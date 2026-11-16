-- Roblox全面大战场——舰艇的型号数据（服务器、客户端共用）：尺寸、速度、转向、血量、武器（主炮、副炮 / 机枪、反舰 / 对陆导弹、防空导弹、近防炮）、样子
--   尺寸按真船的 0.6 倍（1 米 = 1.68 格；地图上固定的航母、两栖攻击舰平台也是缩过的，舰艇照真比例会比岛还大）
--   坐标：原点在船的正中、水线上（Y = 0 是水面），X 右、Y 上、−Z 朝船头；服务器的命中盒是 W × H × L 的方块，底在水线下 draft 格
--   炮：pos 炮塔转轴、trav 每秒转几度、arc 能转到正前方 / 正后方左右各几度（aft 为真：正后方的炮）、elev 俯仰、len 炮管长
local ShipDefs = {}
local V = Vector3.new

-- 武器：kind shell 炮弹（有弹道）、gun 机枪（射线）、missile 反舰 / 对陆导弹（玩家锁定发射）；sam 防空导弹、ciws 近防炮（都自动）
ShipDefs.W = {
  g130 = { kind = "shell", dmg = 620, speed = 1000, gscale = 0.45, splash = 17, rate = 2.2, range = 4200,
    vs = { inf = 1, light = 1.4, armor = 0.9, air = 0.3, ship = 1.3, fort = 1.2 }, fx = "tank" },
  g127 = { kind = "shell", dmg = 580, speed = 950, gscale = 0.45, splash = 16, rate = 2.4, range = 4000,
    vs = { inf = 1, light = 1.4, armor = 0.9, air = 0.3, ship = 1.3, fort = 1.2 }, fx = "tank" },
  g76 = { kind = "shell", dmg = 280, speed = 1000, gscale = 0.45, splash = 11, rate = 0.9, range = 3500,
    vs = { inf = 1, light = 1.3, armor = 0.6, air = 0.6, ship = 1.2, fort = 1 }, fx = "tank" },
  g57 = { kind = "shell", dmg = 170, speed = 1050, gscale = 0.45, splash = 9, rate = 0.45, range = 3200,
    vs = { inf = 1, light = 1.2, armor = 0.45, air = 0.8, ship = 1.1, fort = 0.8 }, fx = "ac" },
  g30 = { kind = "gun", dmg = 36, rate = 0.07, range = 1900, spread = 0.35,   -- 30 毫米加特林：射速高，按射线算（每发一个飞行中的弹太费）
    vs = { inf = 1, light = 0.9, armor = 0.15, air = 2, ship = 0.4, fort = 0.35 }, fx = "ac" },
  m2x2 = { kind = "gun", dmg = 40, rate = 0.07, range = 1000, spread = 0.6,
    vs = { inf = 1, light = 0.5, armor = 0.04, air = 0.4, ship = 0.12, fort = 0.1 }, fx = "lmg" },
  asm = { kind = "missile", dmg = 1500, splash = 20, speed = 320, range = 5400, turn = 40, cruise = 22,
    vs = { inf = 1, light = 2, armor = 1.4, air = 0, ship = 1.5, fort = 1.5 } },
  sam = { kind = "sam", dmg = 260, splash = 14, speed = 520, range = 3400, rate = 4,
    vs = { inf = 0, light = 0, armor = 0, air = 4, ship = 0, fort = 0 } },
  ciws = { kind = "ciws", range = 950, dmg = 26, rate = 0.1, kill = 0.55,   -- kill：一座近防炮拦一发来袭导弹 / 炸弹能打掉的概率（两座都拦，漏过来约两成）
    vs = { inf = 0.5, light = 0.3, armor = 0, air = 2, ship = 0, fort = 0 } },
}
for id, w in pairs(ShipDefs.W) do w.id = id end

local GREY_PLA, GREY_USN, DARK = Color3.fromRGB(128, 134, 138), Color3.fromRGB(108, 116, 122), Color3.fromRGB(52, 56, 60)

local D = {}
ShipDefs.D = D

-- look：客户端拼样子用（ShipView.lua）——sup 上层建筑 { 前 z, 后 z, 宽, 高, 底在多高 }（第一块是主上层建筑、第二块是舰桥）、mast 桅杆底（mastH 高、mastW 宽）、
--   funnel 烟囱 { 位置, 尺寸, … }、panel 相控阵雷达（桅杆四面）、vls 垂发 { 前 z, 后 z }、heli 直升机甲板 { 前 z, 后 z }、canisters 斜置的导弹发射箱、
--   num 舷号、hulls 双体 / 三体、open 小艇（没有上层建筑）、stealth 隐身外形（上层建筑、炮塔斜面）
D.t055 = { cat = "ship", L = 302, W = 34, H = 52, draft = 9, deck = 11, speed = 40, accel = 3.5, turn = 5, hp = 4800,
  guns = { { w = "g130", pos = V(0, 12, -104), trav = 40, arc = 150, elev = { -5, 60 }, len = 14, size = V(9, 6, 13), stealth = true } },
  missiles = { w = "asm", n = 8, pos = V(0, 12, -82), name = "yj18" }, sam = { n = 16, pos = V(0, 12, 33) },
  ciws = { V(0, 38.5, -58), V(0, 24.5, 70) },
  look = { color = GREY_PLA, sup = { { -70, 20, 24, 16, 11 }, { -64, -14, 20, 10, 27 }, { 46, 84, 22, 12, 11 } }, mast = V(0, 37, -40), mastH = 16, mastW = 14,
    funnel = { V(0, 30, 2), V(12, 9, 14) }, panel = true, vls = { { -92, -72 }, { 24, 42 } }, heli = { 100, 148 }, num = "101", stealth = true } }
D.t054a = { cat = "ship", L = 225, W = 27, H = 42, draft = 7, deck = 9, speed = 40, accel = 4, turn = 6, hp = 3000,
  guns = { { w = "g76", pos = V(0, 9, -78), trav = 55, arc = 150, elev = { -10, 80 }, len = 7, size = V(6, 4, 8), stealth = true } },
  missiles = { w = "asm", n = 8, pos = V(0, 23, -8), name = "yj83" }, sam = { n = 8, pos = V(0, 10, -62) },
  ciws = { V(-6, 24, 22), V(6, 24, 22) },
  look = { color = GREY_PLA, sup = { { -52, 30, 18, 13, 9 }, { -48, -16, 15, 8, 22 }, { 34, 66, 16, 10, 9 } }, mast = V(0, 30, -32), mastH = 13, mastW = 9,
    funnel = { V(0, 25, 6), V(10, 8, 14) }, vls = { { -68, -56 } }, heli = { 70, 108 }, num = "532", canisters = { z = -8, y = 22, n = 4 }, stealth = true } }
D.t022 = { cat = "ship", L = 72, W = 20, H = 16, draft = 3, deck = 4, speed = 58, accel = 10, turn = 14, hp = 1200,
  guns = { { w = "g30", pos = V(0, 10, -15), trav = 120, arc = 160, elev = { -10, 85 }, len = 3, size = V(3, 2.2, 3), gatling = true } },
  missiles = { w = "asm", n = 8, pos = V(0, 7, 24), name = "yj83" },
  look = { color = Color3.fromRGB(96, 118, 116), hulls = 2, sup = { { -20, 12, 14, 6, 4 } }, mast = V(0, 10, -6), mastH = 6, mastW = 4, num = "2208",
    canisters = { z = 26, y = 4, n = 4 }, stealth = true } }
D.ddg125 = { cat = "ship", L = 260, W = 34, H = 50, draft = 9, deck = 10, speed = 40, accel = 3.5, turn = 5, hp = 4200,
  guns = { { w = "g127", pos = V(0, 11, -96), trav = 30, arc = 150, elev = { -5, 65 }, len = 13, size = V(8, 5, 12), stealth = true } },
  missiles = { w = "asm", n = 8, pos = V(0, 11, -75), name = "tlam" }, sam = { n = 16, pos = V(0, 11, 85) },
  ciws = { V(0, 26.5, -60), V(0, 22.5, 70) },
  look = { color = GREY_USN, sup = { { -62, 30, 24, 15, 10 }, { -58, -18, 20, 9, 25 }, { 40, 76, 20, 11, 10 } }, mast = V(0, 34, -36), mastH = 15, mastW = 6,
    funnel = { V(0, 28, 0), V(11, 8, 16), V(0, 25, 50), V(11, 8, 14) }, panel = true, vls = { { -86, -64 }, { 78, 92 } }, heli = { 96, 128 }, num = "125" } }
D.cg47 = { cat = "ship", L = 290, W = 28, H = 54, draft = 9, deck = 10, speed = 38, accel = 3.2, turn = 4.5, hp = 4500,
  guns = { { w = "g127", pos = V(0, 11, -110), trav = 30, arc = 150, elev = { -5, 65 }, len = 13, size = V(8, 5, 12) },
    { w = "g127", pos = V(0, 11, 118), trav = 30, arc = 150, elev = { -5, 65 }, len = 13, size = V(8, 5, 12), aft = true } },
  missiles = { w = "asm", n = 10, pos = V(0, 11, 76), name = "harpoon" }, sam = { n = 20, pos = V(0, 11, 93) },
  ciws = { V(10, 27.5, -20), V(-10, 27.5, 50) },
  look = { color = GREY_USN, sup = { { -70, 70, 22, 16, 10 }, { -66, -20, 18, 12, 26 }, { 16, 64, 18, 10, 26 } }, mast = V(0, 38, -42), mastH = 16, mastW = 6,
    funnel = { V(0, 29.5, -6), V(10, 7, 14), V(0, 39.5, 30), V(10, 7, 12) }, panel = true, vls = { { -98, -82 }, { 84, 102 } }, num = "52",
    canisters = { z = 77, y = 10, n = 4 } } }
D.lcs2 = { cat = "ship", L = 213, W = 53, H = 40, draft = 6, deck = 9, speed = 55, accel = 7, turn = 8, hp = 1800,
  guns = { { w = "g57", pos = V(0, 9, -62), trav = 60, arc = 150, elev = { -10, 77 }, len = 8, size = V(5, 4, 7), stealth = true } },
  missiles = { w = "asm", n = 8, pos = V(0, 10, -52), name = "nsm" }, ciws = { V(0, 24.5, 10) },
  look = { color = Color3.fromRGB(122, 128, 132), hulls = 3, sup = { { -48, 30, 30, 14, 9 }, { -42, -6, 24, 9, 23 } }, mast = V(0, 32, -20), mastH = 10, mastW = 5,
    heli = { 40, 104 }, num = "2", canisters = { z = -52, y = 9, n = 4 }, stealth = true } }
D.pbr = { cat = "ship", L = 16, W = 6, H = 6, draft = 1, deck = 1.6, speed = 50, accel = 12, turn = 28, hp = 750,
  guns = { { w = "m2x2", pos = V(0, 2.4, -5.2), trav = 140, arc = 150, elev = { -15, 50 }, len = 3.2, size = V(1.6, 1.2, 1.4), twin = true } },
  look = { color = Color3.fromRGB(78, 94, 72), open = true, num = "" } }

for id, d in pairs(D) do
  d.id = id
  d.size = V(d.W, d.H, d.L)
end

-- 有原模型的舰艇（ImportedShip：网页版的舰艇模型原样转的，游戏比例）：主炮的炮塔转轴、炮管长照原模型——炮弹从看得见的炮口出去、
--   炮塔转起来不跑偏；不管导没导入都一样（服务器和客户端算出来一致）。原模型上的炮位比上面零件拼的船靠后十几二十格
do
  local ok, IS = pcall(function()
    local m = script and script.Parent and script.Parent:FindFirstChild("ImportedShip")
    return m and require(m) or nil
  end)
  if ok and type(IS) == "table" and IS.m then
    for id, d in pairs(D) do
      local info = IS.m[id]
      for gi, g in ipairs(d.guns or {}) do
        local G = info and info.guns and info.guns[gi]
        if G then
          g.pos = V(G.piv[1], G.piv[2], G.piv[3])
          if G.tip and G.tip > 1 then g.len = math.max(1, G.tip - g.size.Z * 0.35) end   -- 炮口：耳轴（转轴往前 0.35 个炮塔长）再往前 len
        end
      end
    end
  end
end

function ShipDefs.get(id) return D[id] end

-- 炮塔、炮口的世界坐标：cf 是船（水线中心）的 CFrame；ty 方位（度，相对正前方，正数往右；船尾的炮相对正后方）、gp 俯仰
function ShipDefs.turretCF(d, cf, gi, ty)
  local g = d.guns[gi]
  local base = cf * CFrame.new(g.pos)
  if g.aft then base = base * CFrame.Angles(0, math.pi, 0) end
  return base * CFrame.Angles(0, -math.rad(ty or 0), 0)
end
function ShipDefs.gunCF(d, cf, gi, ty, gp)
  local g = d.guns[gi]
  return ShipDefs.turretCF(d, cf, gi, ty) * CFrame.new(0, g.size.Y * 0.35, -g.size.Z * 0.35) * CFrame.Angles(math.rad(gp or 0), 0, 0)
end
function ShipDefs.muzzle(d, cf, gi, ty, gp)
  return ShipDefs.gunCF(d, cf, gi, ty, gp) * CFrame.new(0, 0, -d.guns[gi].len)
end

-- 车钟：几档（−2 全速后退 … 5 全速前进），对应额定航速的几成
ShipDefs.ORDERS = { [-2] = -0.5, [-1] = -0.25, [0] = 0, [1] = 0.2, [2] = 0.4, [3] = 0.6, [4] = 0.8, [5] = 1 }

return ShipDefs
