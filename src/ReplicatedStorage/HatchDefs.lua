-- 全面大战场——载具的舱盖、车门、跳板（用户 11-24：「坦克舱门开合动画」「你记得按照现实中不同坦克的舱门开合模式去做哈」）
--   客户端 Hatch.lua 照这张表在原模型上加能动的舱盖（原模型的舱盖和车身是一整块网格，掀不起来：盖一块同样大小的板，开的时候板掀开、
--   下面垫一块黑的当舱口）；车长探出舱口的小人、上下车时开的门也在那里
--   位置：原模型坐标（格，models/veh/<键>.glb 的坐标：原点车底中心，X 右、Y 上、−Z 朝前），tools/models/hatchmeasure.py 在模型上量的高度；
--     炮塔上的（g = "turret"）客户端再减去炮塔转轴；r 圆舱盖半径、w × h 方的
--   动法（照真车，出处见每一行；没查到的写明是照同一系的车推的）：
--     abrams    后铰链往后掀到 105°；另有「打开保护位」：舱盖只掀开 9°，车长从缝里往外看（M1 系列车长舱盖能锁在全开和「open, protected」两个位置）
--     rear      后铰链往后掀到 105°
--     front     前铰链往前掀到 95°（掀开立在前面当挡板：T-72 / T-90 的车长、炮长舱盖都能锁在往前开的位置）
--     liftswing 先往上抬一点再横着转开（驾驶员舱盖：炮管在头顶，掀不起来，抬起来往一边转；side 1 往右、−1 往左）
--     ramp      车尾跳板：下沿铰链往外放倒，放到跳板尖着地（布雷德利是液压跳板、左边开一扇小门；斯特赖克同样是尾部跳板）
--     door      竖铰链的门往外开 105°（hinge = "L" 左边是铰链、"R" 右边；BMP-3 车尾两扇门往左右两边开）
--     flap      车顶舱盖外沿铰链往上往外翻 110°（BMP-3 载员舱顶两块大舱盖）
--   crew：这个舱口是谁的（commander 车长、loader 装填手：没打仗时探出来的小人站这里）；use：pass 乘客上下车时开、drv 驾驶员上下车时开
local V = Vector3.new

local H = {}

-- 位置都在模型上量过（tools/mock/hatch_view.cjs 的 grid：正上方看、叠 1 格的网格；高度 tools/models/hatchmeasure.py，取舱盖中心最上面那层——
--   开着时垫的黑底要盖住原模型自己那块关着的舱盖）。驾驶员舱盖 pv 是模型上看得见的转轴（舱盖抬起来绕它横着转开），w × h 是方的（长圆的按方的画）

-- M1A2 SEPv2（m1a2dc）：车长舱盖在八边形指挥塔顶上（四周一圈透明防弹板），装填手舱盖在左边；
--   驾驶员舱盖在车体正前方炮塔底下（前沿三具潜望镜），右后方一根转轴：抬起来往右转开
H.m1a2dc = {
  { id = "cmd", g = "turret", at = V(1.57, 7.56, 1.24), r = 0.95, m = "abrams", crew = "commander" },
  { id = "ldr", g = "turret", at = V(-1.2, 6.93, 0.93), r = 0.78, m = "rear", crew = "loader" },
  { id = "drv", g = "hull", at = V(-0.1, 4.21, -5.79), w = 2.0, h = 1.1, m = "liftswing", side = 1, pv = V(1.12, 0, -5.57), use = "drv" },
}
-- M1A1（m1a1i）：原模型的车长舱盖本来就是开着的（orig = "open"：不另画舱盖，只有车长探身 / 缩回去）
H.m1a1i = {
  { id = "cmd", g = "turret", at = V(1.51, 7.6, 1.08), r = 0.9, m = "abrams", crew = "commander", orig = "open" },
  { id = "ldr", g = "turret", at = V(-1.36, 7.22, 0.94), r = 0.85, m = "rear", crew = "loader" },
  { id = "drv", g = "hull", at = V(0, 4.64, -6.0), w = 2.0, h = 1.3, m = "liftswing", side = 1, pv = V(1.05, 0, -5.6), use = "drv" },
}
H.m1a1 = H.m1a1i
-- 99A（ztz99a2）：车长（右边，舱盖四周一圈潜望镜）、炮长（左边）都是单片舱盖往后开（tank-afv.com 的 Type 99：两个都是 single piece hatch opening to the rear）；
--   驾驶员舱盖在车体中线（长圆形，前面一排潜望镜），转轴在右后方——照模型上的转轴往右转开（资料说 99 式往左开，99A 挪了位置，没查到准的）
H.ztz99a2 = {
  { id = "cmd", g = "turret", at = V(1.5, 6.75, -0.05), r = 0.95, m = "rear", crew = "commander" },
  { id = "gnr", g = "turret", at = V(-1.4, 6.62, -0.15), r = 0.85, m = "rear" },
  { id = "drv", g = "hull", at = V(0, 4.10, -5.66), w = 1.75, h = 1.15, m = "liftswing", side = 1, pv = V(0.68, 0, -5.27), use = "drv" },
}
-- 96 式（ztz96）：从 88 式一路改过来的苏式布局——车长（右）、炮长（左）舱盖往前开、锁在前面当挡板；
--   驾驶员在车体左前方（不在中线），舱盖左后方有铰链座：抬起来往左（车外侧）转开（同 T-54 / 55 一系）
H.ztz96 = {
  { id = "cmd", g = "turret", at = V(1.53, 6.87, 0.05), r = 0.95, m = "front", crew = "commander" },
  { id = "gnr", g = "turret", at = V(-1.28, 6.35, -0.2), r = 0.85, m = "front" },
  { id = "drv", g = "hull", at = V(-1.89, 4.31, -5.27), r = 0.8, m = "liftswing", side = -1, pv = V(-2.43, 0, -4.88), use = "drv" },
}
-- T-90M（t90m）：车长指挥塔在右后（一圈观察窗，舱盖在塔顶），炮长舱盖在左边（炮长瞄准镜后面），都往前开（T-72 / T-90 一系）；
--   驾驶员舱盖在车体中线（前面潜望镜座），右后方转轴：抬起来往右转开
H.t90m = {
  { id = "cmd", g = "turret", at = V(1.95, 6.60, 0.76), r = 0.72, m = "front", crew = "commander" },
  { id = "gnr", g = "turret", at = V(-1.86, 6.35, -0.25), r = 0.75, m = "front" },
  { id = "drv", g = "hull", at = V(0.08, 4.18, -4.78), w = 1.75, h = 1.07, m = "liftswing", side = 1, pv = V(0.64, 0, -4.54), use = "drv" },
}
-- M2A3 布雷德利：车尾液压跳板（斜面：下沿 y 1.6 / z 7.9，上沿 y 5.5 / z 8.77）
H.m2a3 = {
  { id = "ramp", g = "hull", m = "ramp", at = V(0, 1.6, 7.9), top = V(0, 5.5, 8.77), w = 4.6, use = "pass" },
}
-- ZBD-05（zbd97 的模型）：车尾一扇大门，右边铰链（模型上门右边两个铰链座）
H.zbd97 = {
  { id = "door", g = "hull", m = "door", hinge = "R", at = V(0, 1.7, 9.17), top = V(0, 5.4, 9.17), w = 3.8, use = "pass" },
}
-- ZSL-92B（借 LAV-25 的模型）：LAV 车尾两扇门往两边开（斜面）
H.lav25 = {
  { id = "doorL", g = "hull", m = "door", hinge = "L", at = V(-0.85, 2.1, 7.95), top = V(-0.85, 4.9, 8.86), w = 1.6, use = "pass" },
  { id = "doorR", g = "hull", m = "door", hinge = "R", at = V(0.85, 2.1, 7.95), top = V(0.85, 4.9, 8.86), w = 1.6, use = "pass" },
}
-- M1117（借 M-ATV 的模型）：车尾一扇门，左边铰链
H.matv = {
  { id = "door", g = "hull", m = "door", hinge = "L", at = V(0, 2.4, 7.63), top = V(0, 6.4, 7.63), w = 2.2, use = "pass" },
}

-- 没有原模型（零件拼的车）或者表里没有的型号：按型号表的尺寸摆一套通用的——坦克车长舱盖在 cupola（往后开）、驾驶员舱盖往右转开；
--   有乘客座位的车车尾一扇门（右边铰链）
function H.generic(d)
  local list = {}
  if d.cat == "tank" and d.cupola then
    table.insert(list, { id = "cmd", g = "turretLocal", at = d.cupola, r = 0.9, m = "rear", crew = "commander" })
  end
  if d.cat == "tank" then
    table.insert(list, { id = "drv", g = "hull", at = V(0, d.hullH, -d.L * 0.36), r = 0.8, m = "liftswing", side = 1, use = "drv" })
  end
  if (d.seats or 1) > 1 then
    local zr = d.L / 2 - 0.05
    table.insert(list, { id = "door", g = "hull", m = "door", hinge = "R", at = V(0, (d.clear or 1.2) + 0.4, zr), top = V(0, d.hullH - 0.4, zr), w = math.min(2.6, d.W * 0.3), use = "pass" })
  end
  return list
end

-- ---------------------------------------------------------------- 几何（客户端 Hatch.lua 和测试共用：只用 Vector3 / CFrame）
local CF, ANG, rad = CFrame.new, CFrame.Angles, math.rad
local function clamp(x, a, b) return x < a and a or (x > b and b or x) end
H.TH = 0.18                                   -- 舱盖板厚（格）
H.UPRIGHT = ANG(0, 0, math.pi / 2)            -- 圆柱的轴（X）转到竖直
H.ABRAMS_OP = rad(9) / rad(105)               -- 艾布拉姆斯「打开保护位」占全开的多少

-- 表里的一行 → 算好的舱盖（挂在车体还是炮塔、在那个坐标系里的位置）：tpiv 炮塔转轴（原模型坐标）
function H.prep(d, tpiv)
  tpiv = tpiv or V()
  local h = { id = d.id, m = d.m, g = (d.g == "hull") and "hull" or "turret", r = d.r, w = d.w, side = d.side, hinge = d.hinge,
    crew = d.crew, use = d.use, orig = d.orig }
  local sh = (d.g == "turret") and tpiv or V()   -- turretLocal：已经是炮塔坐标
  h.loc = d.at - sh
  if d.pv then h.pv = d.pv - V(sh.X, 0, sh.Z) end
  if d.m == "ramp" or d.m == "door" then   -- 车尾斜面上的板：下沿 at、上沿 top
    local base, top = d.at - sh, d.top - sh
    local u = top - base
    h.L = u.Magnitude
    h.t0 = math.atan2(u.Z, u.Y)   -- 往后倾多少（绕 X 轴）
    h.base = base
    if d.m == "ramp" then h.open = clamp(math.acos(clamp(-base.Y / h.L, -1, 1)) - h.t0, rad(60), rad(150)) end   -- 放倒到尖着地
    h.shape, h.size = "block", V(h.w, h.L, H.TH)
    h.holeSize = V(h.w * 0.94, h.L * 0.94, 0.06)
    h.holeCF = CF(base) * ANG(h.t0, 0, 0) * CF(0, h.L / 2, 0.04)
  elseif d.w and d.h then   -- 方的（BMP-3 车顶舱盖、长圆的驾驶员舱盖）
    h.h = d.h
    h.shape, h.size = "block", V(h.w, H.TH, h.h)
    h.holeSize = V(h.w * 0.92, 0.06, h.h * 0.92)
    h.holeCF = CF(h.loc + V(0, 0.04, 0))
  else
    h.shape, h.size = "round", V(H.TH, h.r * 2, h.r * 2)
    h.holeSize = V(0.06, h.r * 1.84, h.r * 1.84)
    h.holeCF = CF(h.loc + V(0, 0.04, 0)) * H.UPRIGHT
  end
  return h
end

-- 舱盖在车体 / 炮塔坐标里的样子（p：开的程度 0～1）。板都摆在原模型表面外面一点（不和原模型的舱盖抢同一个面闪）
function H.lidCF(h, p)
  local m, C, TH = h.m, h.loc, H.TH
  local up = TH / 2 + 0.01
  local rot = (h.shape == "round") and H.UPRIGHT or CF()
  local hd = h.h and h.h / 2 or h.r       -- 前后半长（铰链离中心多远）
  if m == "rear" or m == "abrams" then   -- 后铰链：铰链在舱盖后沿（+Z 朝后），往后掀
    local a = rad(105) * p
    return CF(C + V(0, 0, hd)) * ANG(a, 0, 0) * CF(0, up, -hd) * rot
  elseif m == "front" then               -- 前铰链：往前掀、立在前面
    local a = rad(95) * p
    return CF(C + V(0, 0, -hd)) * ANG(-a, 0, 0) * CF(0, up, hd) * rot
  elseif m == "liftswing" then           -- 先抬 0.22 格，再绕竖轴（pv，没给就在侧边）转开 160°；side 1 从前面转到右边，−1 转到左边
    local lift = clamp(p / 0.25, 0, 1) * 0.22
    local ang = clamp((p - 0.25) / 0.75, 0, 1) * rad(160)
    local s = h.side or 1
    local pv = h.pv and V(h.pv.X, C.Y, h.pv.Z) or (C + V(s * (h.w and h.w / 2 or h.r), 0, 0))
    return CF(pv + V(0, lift, 0)) * ANG(0, -s * ang, 0) * CF((C - pv) + V(0, up, 0)) * rot
  elseif m == "ramp" then                -- 下沿铰链往后放倒
    return CF(h.base) * ANG(h.t0 + h.open * p, 0, 0) * CF(0, h.L / 2, up)
  elseif m == "door" then                -- 竖铰链（斜面上的门按斜面倾着转）
    local left = h.hinge == "L"
    local hx = left and -h.w / 2 or h.w / 2
    return CF(h.base) * ANG(h.t0, 0, 0) * CF(hx, 0, up) * ANG(0, (left and -1 or 1) * rad(105) * p, 0) * CF(-hx, h.L / 2, 0)
  elseif m == "flap" then                -- 外沿铰链往上往外翻
    local s = h.side or 1
    return CF(C + V(s * h.w / 2, 0, 0)) * ANG(0, 0, -s * rad(110) * p) * CF(-s * h.w / 2, up, 0)
  end
  return CF(C)
end

return H
