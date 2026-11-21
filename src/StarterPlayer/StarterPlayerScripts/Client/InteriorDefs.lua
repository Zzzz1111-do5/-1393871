-- Roblox全面大战场（客户端）——各型载具的内饰（真实布局、真实尺寸，米）。InteriorKit 拼零件，Interior.lua 让它动起来
--   坐标：原点在炮塔座圈中心、座圈平面上；X 右、Y 上、−Z 朝前（同 VehDefs）。组：hull 车体（不随炮塔转）、turret 炮塔、gun 炮耳轴（随炮俯仰）
--   每型返回 { stations 乘员位（镜头）, crew 乘员（姿势）, gunK 炮的后坐（米）, anim 动画用的子组名, lights / screens 由 Kit 记 }
--   资料：公开的照片、视频、剖视图与手册插图（M1A2：TM 9-2350-288 系列插图、美军开放日照片；99A：央视节目和阅兵车内镜头）；
--     看不到的地方按同类车的通常做法补（标了「推测」）
local Kit = require(script.Parent:WaitForChild("InteriorKit"))
local V, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local RGB = Color3.fromRGB
local MAT = Enum.Material
local C = Kit.C
local rad = math.rad
local PI = math.pi

local Defs = {}

-- 一圈环（按 n 段直板拼，y 平面上、半径 r，宽 w、厚 t）：座圈、观察镜座、炮塔篮栏杆
local function ring(b, g, cx, cy, cz, r, n, w, t, col, mat, a0, a1)
  a0, a1 = a0 or 0, a1 or 2 * PI
  local seg = (a1 - a0) / n
  local len = 2 * r * math.sin(seg / 2) * 1.04
  for i = 0, n - 1 do
    local a = a0 + (i + 0.5) * seg
    b:box(g, V(len, t, w), CF(cx + math.sin(a) * r, cy, cz + math.cos(a) * r) * ANG(0, a, 0), col, mat)
  end
end
Defs.ring = ring

-- 一圈竖着的环（x 平面上，绕 X 轴）：用在舱盖手轮
local function hring(b, g, cf, r, n, t, col, mat)
  local seg = 2 * PI / n
  local len = 2 * r * math.sin(seg / 2) * 1.05
  for i = 0, n - 1 do
    local a = (i + 0.5) * seg
    b:box(g, V(len, t, t), cf * CF(math.cos(a) * r, math.sin(a) * r, 0) * ANG(0, 0, a + PI / 2), col, mat)
  end
end

-- 120 毫米 / 125 毫米炮弹（米，弹底朝 +Z 的话 dir = 1）：可燃药筒 + 金属底缘 + 底火；长弹（脱壳穿甲弹）多一截弹芯
local function round120(b, g, cf, opt)
  opt = opt or {}
  local L = opt.len or 0.98
  local caseL = L * 0.68
  local base = b:cylZ(g, 0.045, 0.152, cf * CF(0, 0, -0.022), RGB(150, 128, 82), MAT.Metal)   -- 金属底缘（钢 / 黄铜色）
  b:cylZ(g, 0.004, 0.03, cf * CF(0, 0, 0.001), RGB(176, 150, 92), MAT.Metal)                 -- 底火
  local case = b:cylZ(g, caseL, 0.13, cf * CF(0, 0, -0.045 - caseL / 2), opt.caseCol or RGB(176, 160, 118), MAT.SmoothPlastic)   -- 可燃药筒
  local tip
  if opt.sabot ~= false then
    tip = b:cylZ(g, L - caseL - 0.045, 0.11, cf * CF(0, 0, -0.045 - caseL - (L - caseL - 0.045) / 2), opt.tipCol or RGB(42, 42, 40), MAT.Metal)
  end
  return { base, case, tip }
end
Defs.round120 = round120

---------------------------------------------------------------- M1A2 SEPv3（艾布拉姆斯）
-- 美国陆军 M1A2C（SEPv3）：四人车组。驾驶员在车体前部中间，扣上舱盖时半躺（三具潜望镜 + 驾驶员视觉增强器 DVE）；
--   炮塔里炮长在右前（主瞄准镜 GPS 的目镜和护额垫、"凯迪拉克" 双握把 GCH、炮长控制显示面板 GCDP、辅助瞄准镜 GAS），
--   车长在右后高位（六具观察镜的指挥塔、独立热像仪 CITV 的显示器、指挥综合显示器 CID / 联合作战指挥平台 JBC-P、车长操纵握把 CCH、
--   主瞄准镜延伸目镜 GPSE、CROWS-LP 遥控武器站的屏幕和握把），装填手在左（折叠座椅、装填手潜望镜、电台、膝动开门开关）；
--   炮塔尾舱用装甲滑门隔开，左右各 18 发待发弹（弹底朝乘员舱），M256 120 毫米炮立楔式炮闩、后坐 0.305 米，右边并列 M240 机枪
local WHITE = RGB(226, 226, 218)   -- 艾布拉姆斯车内是白漆
local WHITE2 = RGB(206, 206, 198)
local FLOOR = RGB(56, 58, 56)
local OD = RGB(84, 90, 66)
local GBOX = RGB(64, 68, 62)

function Defs.m1a2(b, ctx)
  local T, H, G = "turret", "hull", "gun"
  local function bx(g, sx, sy, sz, x, y, z, col, mat, rx, ry, rz)
    return b:box(g, V(sx, sy, sz), CF(x, y, z) * ANG(rad(rx or 0), rad(ry or 0), rad(rz or 0)), col, mat)
  end
  local function look(p, at) return CFrame.lookAt(p, at) end

  ---------------- 车体（不随炮塔转）
  local FY = -1.05   -- 车底地板（座圈平面下 1.05 米）
  bx(H, 1.94, 0.04, 4.40, 0, FY - 0.02, -1.0, FLOOR, MAT.DiamondPlate)                         -- 地板
  for _, s in ipairs({ -1, 1 }) do
    bx(H, 0.04, 0.52, 4.40, s * 0.99, FY + 0.26, -1.0, WHITE2)                                   -- 履带上方的内侧板（侧裙里面是负重轮）
    bx(H, 0.70, 0.04, 2.30, s * 1.33, -0.55, -0.02, WHITE2)                                      -- 侧凸台的平台
    bx(H, 0.04, 0.55, 2.30, s * 1.66, -0.28, -0.02, WHITE2)                                      -- 侧凸台外壁
    -- 侧凸台上的东西（隔着炮塔篮的栏杆看得见）：左边油箱、右边蓄电池和三防装置（推测）
    if s < 0 then
      bx(H, 0.58, 0.46, 1.10, -1.33, -0.30, -0.55, OD)
      bx(H, 0.58, 0.40, 0.90, -1.33, -0.33, 0.62, OD)
      b:placard(H, 0.20, 0.07, CF(-1.03, -0.22, -0.55) * ANG(0, -PI / 2, 0), "FUEL", { bg = RGB(230, 210, 60) })
    else
      for i = 0, 2 do bx(H, 0.34, 0.30, 0.36, 1.30, -0.38, -0.80 + i * 0.42, GBOX) end
      bx(H, 0.56, 0.44, 0.70, 1.33, -0.31, 0.75, RGB(150, 150, 140))
      b:placard(H, 0.18, 0.07, CF(1.03, -0.20, 0.75) * ANG(0, PI / 2, 0), "NBC", { bg = RGB(230, 210, 60) })
    end
  end
  -- 发动机舱隔板（后面是 AGT1500 燃气轮机）
  bx(H, 3.34, 1.05, 0.05, 0, FY + 0.525, 1.18, WHITE2)
  for i = -2, 2 do bx(H, 0.42, 0.05, 0.02, i * 0.5, -0.45, 1.155, C.dark) end   -- 隔板上的通风格栅
  bx(H, 0.70, 0.40, 0.22, 0.55, -0.78, 1.05, RGB(140, 140, 132))                       -- 车体网络盒（推测）
  bx(H, 0.40, 0.30, 0.20, -0.62, -0.83, 1.06, OD)
  b:cable(H, { V(0.55, -0.58, 1.05), V(0.3, -0.4, 1.12), V(-0.4, -0.4, 1.12), V(-0.62, -0.68, 1.08) }, 0.03)
  -- 车顶（座圈外面那一圈，从炮塔篮里抬头偶尔看得见）
  for i = 0, 15 do
    local a = (i + 0.5) * PI / 8
    bx(H, 0.50, 0.04, 0.64, math.sin(a) * 1.36, -0.02, math.cos(a) * 1.36, WHITE2, nil, 0, math.deg(a) + 90, 0)
  end
  -- 座圈（齿圈）
  ring(b, H, 0, -0.05, 0, 1.09, 32, 0.06, 0.08, C.steel, MAT.Metal)
  ring(b, H, 0, -0.10, 0, 1.06, 32, 0.03, 0.03, C.dark, MAT.Metal)

  -- 驾驶舱：两边是前油箱（驾驶员夹在中间），前面是首上装甲的内壁
  local DZ = -1.85   -- 驾驶员头的位置（舱盖下）
  for _, s in ipairs({ -1, 1 }) do
    bx(H, 0.50, 1.00, 2.00, s * 0.75, FY + 0.50, -2.15, OD)                     -- 前油箱
    bx(H, 0.02, 0.80, 1.60, s * 0.495, FY + 0.50, -2.15, RGB(96, 102, 76))
  end
  bx(H, 1.00, 0.05, 1.20, 0, -0.38, -2.75, WHITE2, nil, -32, 0, 0)               -- 首上装甲内壁（斜）
  bx(H, 1.00, 0.70, 0.05, 0, FY + 0.35, -3.22, WHITE2)                           -- 前壁
  bx(H, 1.00, 0.04, 0.28, 0, -0.04, -2.06, WHITE2)                               -- 驾驶舱顶（舱盖前面，挂潜望镜）
  bx(H, 1.00, 0.04, 0.12, 0, -0.04, -1.27, WHITE2)
  for _, s in ipairs({ -1, 1 }) do bx(H, 0.22, 0.04, 0.62, s * 0.39, -0.04, -1.62, WHITE2) end
  -- 舱盖（从里面看：圆盖 + 手柄 + 锁定杆），可抬起转开
  b:group("dhatch", H, CF(0, -0.02, -1.62))
  b:cylY("dhatch", 0.05, 0.58, CF(0, -0.03, 0), WHITE, MAT.SmoothPlastic)
  b:grab("dhatch", V(-0.12, -0.06, 0.05), V(0.12, -0.06, 0.05), V(0, -0.06, 0), 0.02, C.black)
  bx("dhatch", 0.30, 0.03, 0.04, 0.10, -0.07, -0.12, C.red)
  -- 三具潜望镜（前面一具正对，两边各斜 30°）+ 中间下面挂着驾驶员视觉增强器 DVE 的显示器
  local eyeD = V(0, -0.24, DZ)
  for i = -1, 1 do
    local a = rad(i * 32)
    local p = V(math.sin(a) * 0.22, -0.13, DZ - 0.18 - math.cos(a) * 0.06)
    b:periscope(H, look(p, p + V(math.sin(a), 0, -math.cos(a))), 0.17, 0.09, 0.10)
  end
  local dve = b:screen(H, 0.16, 0.12, look(V(0, -0.36, DZ - 0.30), eyeD), "dve", { lightColor = RGB(200, 200, 200), lightK = 0.25 })
  bx(H, 0.20, 0.04, 0.10, 0, -0.27, DZ - 0.32, C.black)
  -- 驾驶员座椅（扣盖驾驶：靠背放倒）
  b:seat(H, CF(0, FY + 0.22, -2.28) * ANG(rad(6), 0, 0), { w = 0.44, d = 0.40, back = 0.60, recline = 34, head = true, col = RGB(52, 50, 44) })
  bx(H, 0.30, 0.20, 0.30, 0, FY + 0.10, -2.28, C.gray, MAT.Metal)
  -- T 形操纵把（摩托车式把手：两端拧把油门，中间换挡）、转向柱
  b:group("tbar", H, CF(0, FY + 0.48, -2.72))
  b:tube("tbar", V(-0.26, 0, 0), V(0.26, 0, 0), 0.035, C.dark, MAT.Metal)
  b:cyl("tbar", 0.11, 0.05, CF(-0.27, 0, 0), C.rubber, MAT.Fabric)
  b:cyl("tbar", 0.11, 0.05, CF(0.27, 0, 0), C.rubber, MAT.Fabric)
  bx("tbar", 0.10, 0.06, 0.08, 0, 0.02, 0, C.black)
  bx("tbar", 0.03, 0.08, 0.03, 0.04, 0.07, 0, RGB(200, 40, 30))                 -- 换挡杆
  b:tube(H, V(0, FY + 0.48, -2.72), V(0, FY + 0.05, -2.95), 0.06, C.gray, MAT.Metal)
  bx(H, 0.18, 0.04, 0.12, 0.10, FY + 0.06, -2.95, C.dark, MAT.DiamondPlate, -25, 0, 0)   -- 刹车踏板
  bx(H, 0.14, 0.04, 0.12, -0.12, FY + 0.06, -2.98, C.dark, MAT.DiamondPlate, -25, 0, 0)  -- 搁脚板
  -- 驾驶员综合显示器 DID（左前）+ 主开关面板（左）+ 右边的辅助面板
  b:screen(H, 0.20, 0.15, look(V(-0.33, -0.48, -2.42), eyeD), "did", { keys = { top = { "MAIN MENU", "STATUS", "W/C/A", "NAV", "MAINT" }, bottom = { "PUSH TO START", "SHUT OFF", "TAC IDLE", "LAMP TEST", "ALARM ACK" } }, lightK = 0.3 })
  b:panel(H, 0.16, 0.30, look(V(-0.44, -0.66, -2.10), V(0, -0.6, -2.0)), 4, 2, RGB(70, 72, 70), { guard = true })
  b:panel(H, 0.14, 0.22, look(V(0.44, -0.62, -2.15), V(0, -0.6, -2.05)), 3, 2, RGB(70, 72, 70))
  b:placard(H, 0.10, 0.03, look(V(-0.44, -0.48, -2.10), V(0, -0.48, -2.0)) * CF(0, 0, -0.002), "MASTER", { bg = C.black, fg = C.white })
  -- 灭火瓶（哈龙，驾驶员后面两瓶）
  b:extinguisher(H, CF(-0.36, FY + 0.25, -1.30), 0.48, 0.15)
  b:extinguisher(H, CF(0.36, FY + 0.25, -1.30), 0.48, 0.15)
  b:placard(H, 0.12, 0.05, CF(-0.36, FY + 0.40, -1.22) * ANG(0, PI, 0), "HALON", { bg = C.red, fg = C.white })
  b:light(H, CF(0, -0.10, -1.40), "dome", RGB(255, 240, 220), 2.8, 0.9)

  ---------------- 炮塔（随炮塔转）
  local RY = 0.80   -- 炮塔顶内表面（座圈平面上 0.8 米）
  -- 炮塔篮：地板、中间的导电滑环、四周栏杆（前面留出去驾驶舱的口子）
  b:cylY(T, 0.03, 1.96, CF(0, FY + 0.06, 0), FLOOR, MAT.DiamondPlate)
  b:cylY(T, 0.22, 0.30, CF(0, FY + 0.18, 0.05), C.dark, MAT.Metal)
  b:cylY(T, 0.06, 0.40, CF(0, FY + 0.32, 0.05), C.steel, MAT.Metal)
  for i = 0, 11 do
    local a = (i + 0.5) * PI / 6
    if not (a > PI * 0.80 and a < PI * 1.20) then   -- 正前方（−Z）留口子
      b:tube(T, V(math.sin(a) * 0.98, FY + 0.06, math.cos(a) * 0.98), V(math.sin(a) * 0.98, -0.36, math.cos(a) * 0.98), 0.03, C.lgray, MAT.Metal)
    end
  end
  ring(b, T, 0, -0.36, 0, 0.98, 12, 0.03, 0.03, C.lgray, MAT.Metal, -PI * 0.80, PI * 0.80)
  ring(b, T, 0, -0.72, 0, 0.98, 12, 0.03, 0.03, C.lgray, MAT.Metal, -PI * 0.80, PI * 0.80)
  -- 炮塔底板（座圈外面到炮塔壁那一圈）
  for i = 0, 15 do
    local a = (i + 0.5) * PI / 8
    bx(T, 0.52, 0.03, 0.60, math.sin(a) * 1.30, 0.0, math.cos(a) * 1.30, WHITE2, nil, 0, math.deg(a) + 90, 0)
  end
  -- 炮塔壁（从里面看：白漆钢板，前角切斜）、前面炮的凹槽、尾舱隔板
  for _, s in ipairs({ -1, 1 }) do
    bx(T, 0.05, RY, 1.86, s * 1.26, RY / 2, 0.17, WHITE)                                      -- 侧壁
    local p0, p1 = V(s * 1.26, 0, -0.76), V(s * 0.46, 0, -1.26)
    local mid = (p0 + p1) / 2
    local len = (p1 - p0).Magnitude
    b:box(T, V(len, RY, 0.05), CF(mid.X, RY / 2, mid.Z) * ANG(0, math.atan2(-(p1.Z - p0.Z), p1.X - p0.X), 0), WHITE)   -- 斜的前角
    bx(T, 0.05, RY, 0.36, s * 0.44, RY / 2, -1.43, WHITE2)                                    -- 炮槽两侧
  end
  bx(T, 0.92, RY, 0.05, 0, RY / 2, -1.62, WHITE2)                                            -- 炮槽前壁（炮从这里穿出去）
  -- 炮塔顶：几块板，留出车长指挥塔、装填手舱盖、炮长主瞄准镜的口子
  bx(T, 2.56, 0.05, 0.62, 0, RY + 0.025, 0.86, WHITE)                                        -- 后段
  bx(T, 0.46, 0.05, 0.60, -0.05, RY + 0.025, 0.28, WHITE)                                    -- 中段（两个舱口之间）
  bx(T, 0.34, 0.05, 0.60, 1.11, RY + 0.025, 0.28, WHITE)
  bx(T, 0.34, 0.05, 0.60, -1.11, RY + 0.025, 0.28, WHITE)
  bx(T, 2.56, 0.05, 0.50, 0, RY + 0.025, -0.27, WHITE)                                       -- 中前段
  bx(T, 1.70, 0.05, 0.78, -0.43, RY + 0.025, -0.91, WHITE)                                   -- 前段（左）
  bx(T, 0.86, 0.05, 0.78, 0.85, RY + 0.025, -0.91, WHITE)                                    -- 前段（右，主瞄准镜从这里穿上去）
  ring(b, T, 0.56, RY + 0.035, 0.34, 0.47, 16, 0.24, 0.03, WHITE2)                           -- 指挥塔、装填手舱口四周的座板（盖住方口子的四个角）
  ring(b, T, -0.62, RY + 0.035, 0.28, 0.42, 16, 0.22, 0.03, WHITE2)
  bx(T, 0.92, 0.05, 0.38, 0, RY + 0.025, -1.43, WHITE)                                       -- 炮槽顶
  -- 加强筋、螺栓排（车内到处是）
  for _, z in ipairs({ -0.55, 0.0, 0.55 }) do bx(T, 2.5, 0.04, 0.05, 0, RY - 0.02, z, WHITE2) end
  for i = 0, 9 do b:ball(T, 0.018, CF(-1.235, 0.72, -0.6 + i * 0.2), C.lgray, MAT.Metal) b:ball(T, 0.018, CF(1.235, 0.72, -0.6 + i * 0.2), C.lgray, MAT.Metal) end

  -- 尾舱隔板 + 两扇装甲滑门（左：装填手的待发弹 18 发，右：18 发）
  local BZ = 1.10
  bx(T, 2.50, 0.10, 0.06, 0, 0.04, BZ, WHITE2)
  bx(T, 2.50, 0.08, 0.06, 0, RY - 0.04, BZ, WHITE2)
  bx(T, 0.20, RY, 0.06, 0, RY / 2, BZ, WHITE2)
  bx(T, 0.20, RY, 0.06, -1.15, RY / 2, BZ, WHITE2)
  bx(T, 0.20, RY, 0.06, 1.15, RY / 2, BZ, WHITE2)
  local racks = {}
  for side, s in pairs({ L = -1, R = 1 }) do
    local cx = s * 0.55
    -- 门（子组，开的时候往外侧滑）
    local gname = "door" .. side
    b:group(gname, T, CF(cx, RY / 2 + 0.02, BZ - 0.035))
    b:box(gname, V(0.90, 0.64, 0.05), CF(), RGB(196, 198, 190), MAT.Metal)
    b:box(gname, V(0.86, 0.04, 0.02), CF(0, 0.22, -0.03), RGB(170, 172, 164), MAT.Metal)
    b:box(gname, V(0.86, 0.04, 0.02), CF(0, -0.22, -0.03), RGB(170, 172, 164), MAT.Metal)
    b:grab(gname, V(-s * 0.30, 0.10, -0.03), V(-s * 0.30, -0.10, -0.03), V(0, 0, -0.05), 0.022, C.black)
    b:placard(gname, 0.30, 0.08, CF(0, 0.10, -0.028), "AMMO DOOR", { bg = RGB(230, 200, 40) })
    b:placard(gname, 0.42, 0.06, CF(0, -0.04, -0.028), "KEEP CLOSED EXCEPT WHEN LOADING", { bg = RGB(230, 200, 40) })
    -- 弹架：3 排 × 6 列，弹底朝前（朝乘员舱）
    racks[side] = {}
    bx(T, 0.92, 0.66, 0.02, cx, RY / 2 + 0.02, BZ + 0.06, C.dark, MAT.Metal)   -- 弹架面板（门开了才看得见）
    for r = 0, 2 do
      for c = 0, 5 do
        local p = V(cx - 0.375 + c * 0.15, 0.18 + r * 0.21, BZ + 0.07)
        local rd = round120(b, T, CF(p) * ANG(0, PI, 0), { len = 0.98, caseCol = (r == 0 and c < 2) and RGB(150, 150, 140) or RGB(176, 160, 118) })
        table.insert(racks[side], rd)
      end
    end
  end
  b:name("racks", racks)
  -- 装填手的膝动开门开关（地板上靠左门）
  b:group("knee", T, CF(-0.58, FY + 0.40, 0.92))
  b:box("knee", V(0.18, 0.05, 0.10), CF(), RGB(200, 170, 40), MAT.Metal)
  bx(T, 0.08, 0.34, 0.06, -0.58, FY + 0.22, 0.96, C.gray, MAT.Metal)

  ---------------- 主炮：M256 120 毫米滑膛炮（炮耳轴原点；recoil 子组后坐，blk 炮闩下落）
  b:box(G, V(0.40, 0.36, 0.86), CF(0, 0, -0.12), RGB(98, 102, 96), MAT.Metal)                -- 摇架
  for _, s in ipairs({ -1, 1 }) do
    b:cylZ(G, 0.72, 0.085, CF(s * 0.14, 0.22, -0.05), C.steel, MAT.Metal)                       -- 驻退复进机
    b:cylZ(G, 0.10, 0.11, CF(s * 0.14, 0.22, 0.30), C.dark, MAT.Metal)
  end
  b:cylZ(G, 0.14, 0.16, CF(0.22, -0.12, -0.10), C.dark, MAT.Metal)                              -- 高低机连接（推测）
  b:group("recoil", G, CF())
  b:cylZ("recoil", 0.85, 0.26, CF(0, 0, -0.18), RGB(70, 74, 72), MAT.Metal)                     -- 炮管尾段（隔热套里面那截）
  b:box("recoil", V(0.52, 0.48, 0.60), CF(0, -0.02, 0.62), RGB(64, 66, 64), MAT.Metal)         -- 炮尾环
  b:box("recoil", V(0.54, 0.06, 0.62), CF(0, 0.24, 0.62), RGB(78, 80, 78), MAT.Metal)
  b:cylZ("recoil", 0.04, 0.20, CF(0, 0.02, 0.935), RGB(90, 92, 90), MAT.Metal)                  -- 药室口
  b:box("recoil", V(0.08, 0.30, 0.10), CF(-0.31, -0.05, 0.70), C.dark, MAT.Metal)              -- 开闩把手座（装填手一侧）
  b:group("blk", "recoil", CF(0, -0.02, 0.62))
  b:box("blk", V(0.30, 0.34, 0.30), CF(0, 0, 0), RGB(120, 122, 118), MAT.Metal)                 -- 立楔式炮闩（开闩时下落）
  b:box("blk", V(0.20, 0.06, 0.02), CF(0, 0.05, 0.155), RGB(40, 40, 40), MAT.Metal)
  b:group("brk", "recoil", CF(-0.33, 0.05, 0.70))
  b:tube("brk", V(0, 0, 0), V(-0.06, -0.28, 0.10), 0.03, C.dark, MAT.Metal)                     -- 开闩手柄
  b:ball("brk", 0.05, CF(-0.06, -0.28, 0.10), C.black)
  -- 防危板 / 后坐防护栏（跟着炮俯仰，不跟着后坐）：两侧挡板、后横杆、底下的药筒底盘收集袋
  for _, s in ipairs({ -1, 1 }) do
    b:box(G, V(0.04, 0.56, 0.86), CF(s * 0.40, -0.06, 0.88), RGB(96, 100, 86), MAT.Metal)
    b:box(G, V(0.05, 0.08, 0.86), CF(s * 0.40, 0.24, 0.88), RGB(230, 196, 40), MAT.SmoothPlastic)
  end
  b:tube(G, V(-0.40, 0.18, 1.30), V(0.40, 0.18, 1.30), 0.04, RGB(230, 196, 40), MAT.Metal)
  b:tube(G, V(-0.40, -0.30, 1.30), V(0.40, -0.30, 1.30), 0.04, C.lgray, MAT.Metal)
  b:box(G, V(0.70, 0.12, 0.50), CF(0, -0.40, 1.02), RGB(86, 84, 66), MAT.Fabric)                -- 底盘收集袋
  b:placard(G, 0.34, 0.07, CF(-0.425, -0.02, 0.88) * ANG(0, PI / 2, 0), "DANGER  RECOIL AREA", { bg = RGB(230, 196, 40) })
  b:placard(G, 0.34, 0.07, CF(0.425, -0.02, 0.88) * ANG(0, -PI / 2, 0), "DANGER  RECOIL AREA", { bg = RGB(230, 196, 40) })
  -- 装填手的保险（防护栏左边的 ARM / SAFE 拨杆）
  b:group("arm", G, CF(-0.43, 0.14, 0.62))
  b:box("arm", V(0.03, 0.14, 0.04), CF(0, 0.06, 0), C.red, MAT.SmoothPlastic)
  b:placard(G, 0.10, 0.04, CF(-0.425, 0.04, 0.62) * ANG(0, PI / 2, 0), "ARM  SAFE", { bg = C.black, fg = C.white })
  -- 并列 M240 机枪（炮右边，跟着炮俯仰）+ 供弹槽 + 弹箱
  b:box(G, V(0.10, 0.13, 0.78), CF(0.33, 0.02, -0.02), RGB(40, 42, 42), MAT.Metal)
  b:box(G, V(0.14, 0.06, 0.20), CF(0.33, 0.10, 0.10), RGB(50, 52, 52), MAT.Metal)
  b:box(G, V(0.08, 0.10, 0.12), CF(0.33, -0.06, 0.28), RGB(30, 30, 30), MAT.Metal)
  b:cable(G, { V(0.40, 0.08, 0.10), V(0.55, 0.02, 0.20), V(0.62, -0.30, 0.32) }, 0.07, RGB(70, 72, 60))   -- 供弹槽
  b:box(T, V(0.30, 0.30, 0.42), CF(0.70, -0.50, -0.95), OD, MAT.SmoothPlastic)                  -- 并列机枪弹箱
  b:placard(T, 0.18, 0.06, CF(0.70, -0.42, -0.735) * ANG(0, PI, 0), "7.62MM  COAX", { bg = OD, fg = C.white })

  ---------------- 炮长位（右前）
  local gEye = V(0.52, 0.30, -0.76)
  -- 主瞄准镜 GPS：吊在炮塔顶上的镜体、双目目镜和黑色护额垫
  bx(T, 0.30, 0.46, 0.42, 0.62, 0.56, -1.02, RGB(52, 54, 56))
  bx(T, 0.24, 0.20, 0.14, 0.55, 0.36, -0.92, RGB(40, 42, 44))
  for _, s in ipairs({ -1, 1 }) do b:cylZ(T, 0.06, 0.05, CF(0.55 + s * 0.035, 0.33, -0.845), C.rubber, MAT.Fabric) end
  b:box(T, V(0.26, 0.06, 0.08), CF(0.55, 0.43, -0.86), C.rubber, MAT.Fabric)                     -- 护额垫
  b:led(T, CF(0.55 + 0.035, 0.33, -0.81), RGB(80, 255, 120), 0.012, "gpsEye")                   -- 目镜里的光（热像是绿的）
  b:led(T, CF(0.55 - 0.035, 0.33, -0.81), RGB(80, 255, 120), 0.012, "gpsEye")
  b:placard(T, 0.12, 0.04, CF(0.62, 0.56, -0.805) * ANG(0, PI, 0), "GPS", { bg = C.black, fg = C.white })
  -- 炮长控制显示面板 GCDP（右边斜着对炮长）
  b:screen(T, 0.20, 0.15, look(V(0.88, 0.20, -0.86), gEye + V(0, -0.1, 0.1)), "gcdp", { keys = { top = { "MAIN", "AMMO", "RANGE", "ADJUST", "LRF" }, bottom = { "WHT/BLK", "3X/10X", "FCS", "BSGT", "MRS" } }, lightK = 0.28 })
  b:panel(T, 0.22, 0.12, look(V(0.92, 0.00, -0.78), gEye + V(0, -0.3, 0.1)), 2, 5, RGB(66, 68, 66), { kinds = { "b", "b", "b", "l", "t" } })
  -- "凯迪拉克" 双握把 GCH（底座立柱 + 左右两个握把；握把跟着炮塔转、炮俯仰的速度转动）
  b:tube(T, V(0.55, FY + 0.06, -0.70), V(0.55, -0.15, -0.72), 0.06, C.gray, MAT.Metal)
  bx(T, 0.30, 0.09, 0.12, 0.55, -0.10, -0.74, RGB(54, 56, 58))
  b:group("gch", T, CF(0.55, -0.08, -0.74))
  for _, s in ipairs({ -1, 1 }) do
    b:box("gch", V(0.05, 0.14, 0.05), CF(s * 0.14, 0.08, 0.0) * ANG(rad(-20), 0, 0), C.black, MAT.SmoothPlastic)
    b:box("gch", V(0.055, 0.03, 0.06), CF(s * 0.14, 0.16, -0.01), RGB(40, 40, 40), MAT.SmoothPlastic)
    b:button("gch", CF(s * 0.14, 0.155, -0.04) * ANG(rad(-70), 0, 0), C.red, 0.012)             -- 激光测距按钮
  end
  -- 辅助瞄准镜 GAS（装在炮的摇架上，跟着炮俯仰）
  b:cylZ(G, 0.55, 0.07, CF(0.24, 0.12, 0.10), RGB(46, 48, 50), MAT.Metal)
  b:cylZ(G, 0.06, 0.06, CF(0.24, 0.12, 0.40), C.rubber, MAT.Fabric)
  -- 手动方向机、高低机（手轮）
  for _, p in ipairs({ V(0.30, -0.12, -0.92), V(0.82, -0.18, -0.62) }) do
    b:cylZ(T, 0.03, 0.16, CF(p) * ANG(rad(20), 0, 0), C.dark, MAT.Metal)
    b:tube(T, p, p + V(0.05, -0.05, 0.06), 0.022, C.black)
  end
  b:seat(T, CF(0.55, -0.40, -0.40), { w = 0.36, d = 0.32, back = 0.36, recline = 4, post = 0.55, col = RGB(52, 50, 44) })
  bx(T, 0.18, 0.04, 0.24, 0.55, FY + 0.12, -0.80, C.dark, MAT.DiamondPlate, -20, 0, 0)          -- 搁脚
  bx(T, 0.20, 0.18, 0.05, 0.55, -0.10, -0.98, RGB(52, 50, 44), MAT.Fabric)                       -- 护胸垫

  ---------------- 车长位（右后，坐得高）
  local cEye = V(0.56, 0.60, 0.02)
  -- 指挥塔：座圈、六具观察镜、舱盖内面
  ring(b, T, 0.56, RY + 0.02, 0.34, 0.36, 18, 0.06, 0.06, WHITE2, MAT.Metal)
  for i = 0, 5 do
    local a = rad(i * 60)
    local d = V(math.sin(a), 0, -math.cos(a))
    local p = V(0.56, RY - 0.03, 0.34) + d * 0.30
    b:periscope(T, look(p, p + d), 0.13, 0.07, 0.08, { pad = false })
  end
  b:group("chatch", T, CF(0.56, RY + 0.10, 0.34))
  b:cylY("chatch", 0.05, 0.62, CF(), WHITE, MAT.SmoothPlastic)
  b:grab("chatch", V(-0.12, -0.03, 0.10), V(0.12, -0.03, 0.10), V(0, -0.05, 0), 0.02, C.black)
  -- 独立热像仪显示器（CITV）、指挥综合显示器（CID / JBC-P）、CROWS 遥控武器站屏幕和握把、车长操纵握把 CCH、主瞄准镜延伸目镜 GPSE
  bx(T, 0.70, 0.30, 0.06, 0.62, 0.36, -0.40, RGB(58, 60, 58), nil, -12, 0, 0)                     -- 显示器支架板
  b:screen(T, 0.21, 0.16, look(V(0.42, 0.42, -0.34), cEye), "citv", { keys = { top = { "WHT", "BLK", "WFOV", "NFOV", "SYM" }, bottom = { "MAN", "AUTO", "GUN LOS", "GPS LOS", "DESIG" } }, lightK = 0.3 })
  b:screen(T, 0.26, 0.20, look(V(0.76, 0.40, -0.33), cEye), "cid", { keys = { top = { "MAP", "MSG", "STAT", "NAV", "POS" }, bottom = { "ZOOM+", "ZOOM-", "OVLY", "BRT+", "BRT-" } }, lightColor = RGB(150, 190, 230), lightK = 0.35 })
  b:screen(T, 0.17, 0.13, look(V(1.02, 0.50, -0.06), cEye), "crows", { keys = { top = { "ARM", "SAFE", "THERM" }, bottom = { "ZOOM", "LASE", "SLAVE" } }, lightK = 0.25 })
  b:tube(T, V(1.04, 0.22, 0.06), V(0.98, 0.32, 0.02), 0.03, C.dark, MAT.Metal)
  b:box(T, V(0.06, 0.12, 0.06), CF(0.97, 0.38, 0.01) * ANG(rad(-15), 0, 0), C.black)             -- CROWS 握把
  b:group("cch", T, CF(0.78, 0.12, -0.12))
  b:box("cch", V(0.05, 0.13, 0.05), CF(0, 0.07, 0) * ANG(rad(-15), 0, 0), C.black)
  b:button("cch", CF(0, 0.14, -0.03) * ANG(rad(-70), 0, 0), C.yellow, 0.012)
  b:tube(T, V(0.78, -0.30, -0.12), V(0.78, 0.10, -0.12), 0.04, C.gray, MAT.Metal)
  b:cylZ(T, 0.10, 0.07, CF(0.56, 0.52, -0.42), RGB(42, 44, 46), MAT.Metal)                        -- GPSE 目镜
  b:cylZ(T, 0.05, 0.075, CF(0.56, 0.52, -0.36), C.rubber, MAT.Fabric)
  b:led(T, CF(0.56, 0.52, -0.33), RGB(80, 255, 120), 0.014, "gpsEye")
  b:tube(T, V(0.56, 0.52, -0.47), V(0.60, 0.56, -0.82), 0.06, RGB(52, 54, 56), MAT.Metal)
  b:seat(T, CF(0.58, -0.08, 0.30), { w = 0.38, d = 0.34, back = 0.34, recline = 6, post = 0.80, col = RGB(52, 50, 44) })
  bx(T, 0.36, 0.04, 0.30, 0.58, -0.52, 0.02, C.dark, MAT.DiamondPlate)                            -- 车长搁脚台
  b:radio(T, 0.22, 0.12, 0.18, look(V(1.20, 0.30, 0.45), V(0, 0.3, 0.45)), RGB(60, 64, 56))      -- 车长车内通话盒（推测）

  ---------------- 装填手位（左）
  local lEye = V(-0.60, 0.56, 0.10)
  ring(b, T, -0.62, RY + 0.02, 0.28, 0.32, 16, 0.06, 0.06, WHITE2, MAT.Metal)
  b:group("lhatch", T, CF(-0.62, RY + 0.10, 0.28))
  b:cylY("lhatch", 0.05, 0.56, CF(), WHITE, MAT.SmoothPlastic)
  b:grab("lhatch", V(-0.11, -0.03, 0.10), V(0.11, -0.03, 0.10), V(0, -0.05, 0), 0.02, C.black)
  -- 装填手潜望镜（能转）
  b:group("lscope", T, CF(-0.62, RY - 0.05, -0.12))
  b:periscope("lscope", CF(0, 0, 0) * ANG(0, 0, 0), 0.18, 0.09, 0.12)
  b:grab("lscope", V(-0.10, -0.06, 0.06), V(0.10, -0.06, 0.06), V(0, -0.06, 0), 0.016, C.black)
  -- 装填手面板（主炮状态：READY / ARMED，炮塔动力）、电台架、灭火器、折叠座椅
  b:panel(T, 0.26, 0.20, look(V(-1.21, 0.36, -0.22), V(0, 0.36, -0.22)), 3, 4, RGB(66, 68, 66), { ledRole = "ready" })
  b:placard(T, 0.20, 0.04, look(V(-1.215, 0.48, -0.22), V(0, 0.48, -0.22)), "LOADER'S PANEL", { bg = C.black, fg = C.white })
  b:radio(T, 0.36, 0.16, 0.30, look(V(-1.21, 0.30, 0.62), V(0, 0.30, 0.62)), RGB(70, 76, 58))      -- SINCGARS 电台 ×2
  b:radio(T, 0.36, 0.16, 0.30, look(V(-1.21, 0.48, 0.62), V(0, 0.48, 0.62)), RGB(70, 76, 58))
  b:harness(T, { V(-1.05, 0.62, 0.62), V(-0.95, 0.74, 0.40), V(-0.20, 0.74, 0.35), V(0.40, 0.74, 0.05) }, 3, 0.022)
  b:extinguisher(T, CF(-1.18, 0.12, 0.05), 0.36, 0.12)
  b:seat(T, CF(-1.12, 0.10, 0.40) * ANG(0, PI / 2, 0) * ANG(rad(-80), 0, 0), { w = 0.34, d = 0.30, back = 0, col = RGB(52, 50, 44) })   -- 折起来的座椅
  b:box(T, V(0.30, 0.22, 0.44), CF(-0.95, -0.48, -0.70), OD)                                      -- 机枪弹箱
  b:box(T, V(0.30, 0.22, 0.44), CF(-0.95, -0.72, -0.70), OD)
  -- 炮塔里的电缆
  b:harness(T, { V(0.10, RY - 0.06, -1.10), V(0.40, RY - 0.06, -0.60), V(0.95, RY - 0.06, -0.40), V(1.10, 0.40, -0.30) }, 4, 0.02)
  b:harness(T, { V(0, FY + 0.30, 0.05), V(0.30, -0.40, 0.20), V(0.95, -0.10, 0.40), V(1.10, 0.25, 0.40) }, 3, 0.025)
  b:harness(T, { V(-0.95, -0.20, 0.95), V(-1.15, 0.05, 0.70), V(-1.18, 0.20, 0.40) }, 3, 0.02)
  -- 灯：炮塔两盏顶灯（白 / 夜里红或蓝绿）、开炮时从观察镜透进来的火光、挨打时的红色告警
  b:light(T, CF(-0.25, RY - 0.06, 0.55), "dome", RGB(255, 244, 228), 3.4, 1.1)
  b:light(T, CF(0.70, RY - 0.06, -0.30), "dome", RGB(255, 244, 228), 3.2, 1.0)
  b:light(T, CF(0.56, RY - 0.05, 0.34), "flash", RGB(255, 196, 120), 4.0, 0)
  b:light(T, CF(-0.30, 0.40, -0.50), "warn", RGB(255, 40, 30), 3.0, 0)
  for _, p in ipairs({ V(-0.25, RY - 0.02, 0.55), V(0.70, RY - 0.02, -0.30) }) do
    b:box(T, V(0.14, 0.04, 0.10), CF(p), C.dark, MAT.Metal)
    b:led(T, CF(p - V(0, 0.025, 0)), RGB(255, 236, 210), 0.05, "domeLamp")
  end

  return {
    gunK = 0.305,   -- M256 后坐行程
    loader = "m256",
    stations = {
      -- optics：Shift 主镜、G 备用镜、T 第三个；kind = "gps" 是炮长主瞄准镜（Drive.lua 的瞄准镜）
      driver = { g = H, eye = eyeD, look = V(0, 0.15, -1), yaw = 110, up = 35, down = 55, crew = "driver",
        optics = { primary = { kind = "dve", name = "DVE  AN/VAS-5", g = H, pos = V(0, 0.06, -2.25), dir = "hull", fovs = { 40 }, ret = "dve", look = "bhot", shape = "rect" },
          alt = { kind = "rear", name = "RVSS  REAR", g = H, pos = V(1.25, 0.10, 3.45), dir = "rear", fovs = { 52 }, ret = "rear", look = "whot", shape = "rect" } } },
      gunner = { g = T, eye = gEye + V(0.02, 0.06, 0.16), look = V(0, -0.18, -1), yaw = 120, up = 45, down = 60, crew = "gunner", sight = true, scope = V(0.55, 0.33, -0.80),
        optics = { primary = { kind = "gps" },
          alt = { kind = "gas", name = "GAS  M920  8X", g = G, pos = V(0.24, 0.12, 0.40), dir = "gun", fovs = { 8.5 }, ret = "gas", look = "day", shape = "circle", useSight = true } } },
      commander = { g = T, eye = cEye, look = V(-0.05, -0.30, -1), yaw = 160, up = 70, down = 70, crew = "commander", scope = V(0.56, 0.52, -0.40),
        optics = { primary = { kind = "citv", name = "CITV", g = T, pos = V(-0.45, 1.05, -0.75), dir = "citv", fovs = { 22, 7 }, ret = "citv", look = "whot", shape = "rect" },
          alt = { kind = "gps" },
          third = { kind = "crows", name = "CROWS-LP  M2", g = T, pos = V(0.62, 1.40, 0.20), dir = "free", fovs = { 30, 9 }, ret = "crows", look = "day", shape = "rect" } } },
      loader = { g = T, eye = lEye, look = V(0.45, -0.20, -1), yaw = 170, up = 70, down = 75, crew = "loader",
        optics = { primary = { kind = "lscope", name = "LOADER'S PERISCOPE", g = T, pos = V(-0.62, 0.92, -0.12), dir = "free360", fovs = { 38 }, ret = "none", look = "day", shape = "slot" } } },
    },
    order = { "driver", "gunner", "commander", "loader" },
    crew = {
      driver = { dress = "tank_us", g = H, eye = eyeD, lean = 34, yaw = 0, look = V(0, 0.1, -1),
        hands = { l = { "tbar", V(-0.27, 0.0, 0) }, r = { "tbar", V(0.27, 0.0, 0) } },
        feet = { l = { H, V(-0.12, FY + 0.10, -2.92) }, r = { H, V(0.10, FY + 0.10, -2.90) } } },
      gunner = { dress = "tank_us", g = T, eye = gEye + V(0, -0.02, 0.02), lean = -24, yaw = 0, look = V(0, -0.12, -1),
        hands = { l = { "gch", V(-0.14, 0.12, 0.0) }, r = { "gch", V(0.14, 0.12, 0.0) } },
        feet = { l = { T, V(0.45, FY + 0.16, -0.82) }, r = { T, V(0.66, FY + 0.16, -0.80) } } },
      commander = { dress = "tank_us", g = T, eye = cEye, lean = -10, yaw = 0, look = V(0, -0.35, -1),
        hands = { l = { T, V(0.70, 0.30, -0.32) }, r = { "cch", V(0, 0.10, 0) } },
        feet = { l = { T, V(0.50, -0.48, -0.02) }, r = { T, V(0.68, -0.48, -0.02) } } },
      loader = { dress = "tank_us", g = T, eye = lEye, lean = -6, yaw = -28, look = V(0.5, -0.25, -1), stand = true,
        hands = { l = { G, V(-0.40, 0.24, 0.70) }, r = nil },
        feet = { l = { T, V(-0.72, FY + 0.16, 0.12) }, r = { T, V(-0.44, FY + 0.16, 0.18) } } },
    },
  }
end

---------------------------------------------------------------- ZTZ-99A（99A 式主战坦克）
-- 解放军 99A：三人车组（自动装弹机代替装填手）。驾驶员在车体前部中间（方向盘、数字仪表、三具潜望镜），
--   炮塔里炮长在左（主瞄准镜目镜、火控计算机面板、操纵台、炮长显示器）、车长在右（周视瞄准镜目镜和显示器、综合显示终端、超越操纵手柄）；
--   ZPT-98A 125 毫米滑膛炮立楔式炮闩在中间，右边并列机枪；炮塔篮下面是转盘式自动装弹机：22 个弹盒径向排一圈，
--   下层弹丸、上层药筒（分装式）。装弹：转盘转到选的弹种 → 炮尾后面的提弹机把弹盒提到炮尾 → 链式推弹机先推弹丸、再推药筒 → 关闩；
--   打完的药筒底盘从炮塔顶后部的抛壳窗抛出去。车里漆白绿色，标牌是中文（布局照 T-72 / 96 系一脉相承的做法和公开镜头，细节有推测）
local CNW = RGB(214, 224, 210)    -- 车内漆：浅绿白
local CNW2 = RGB(190, 202, 186)
local CNG = RGB(72, 84, 70)

function Defs.ztz99a(b, ctx)
  local T, H, G = "turret", "hull", "gun"
  local function bx(g, sx, sy, sz, x, y, z, col, mat, rx, ry, rz)
    return b:box(g, V(sx, sy, sz), CF(x, y, z) * ANG(rad(rx or 0), rad(ry or 0), rad(rz or 0)), col, mat)
  end
  local function look(p, at) return CFrame.lookAt(p, at) end
  local FY = -1.05
  local RY = 0.78

  ---------------- 车体
  bx(H, 1.90, 0.04, 4.20, 0, FY - 0.02, -1.0, FLOOR, MAT.DiamondPlate)
  for _, s in ipairs({ -1, 1 }) do
    bx(H, 0.04, 0.50, 4.20, s * 0.97, FY + 0.25, -1.0, CNW2)
    bx(H, 0.62, 0.04, 2.30, s * 1.28, -0.55, -0.02, CNW2)
    bx(H, 0.04, 0.55, 2.30, s * 1.58, -0.28, -0.02, CNW2)
    -- 侧凸台上：油箱、蓄电池、电台（推测）
    bx(H, 0.52, 0.44, 1.00, s * 1.30, -0.31, -0.55, CNG)
    bx(H, 0.50, 0.38, 0.80, s * 1.30, -0.34, 0.62, (s < 0) and RGB(60, 64, 60) or CNG)
  end
  b:placard(H, 0.20, 0.07, CF(-1.03, -0.22, -0.55) * ANG(0, -PI / 2, 0), "燃油箱", { bg = RGB(230, 210, 60) })
  b:placard(H, 0.20, 0.07, CF(1.03, -0.22, -0.55) * ANG(0, PI / 2, 0), "燃油箱", { bg = RGB(230, 210, 60) })
  bx(H, 3.20, 1.05, 0.05, 0, FY + 0.525, 1.20, CNW2)                 -- 动力舱隔板
  for i = -2, 2 do bx(H, 0.40, 0.05, 0.02, i * 0.48, -0.45, 1.175, C.dark) end
  for i = 0, 15 do
    local a = (i + 0.5) * PI / 8
    bx(H, 0.50, 0.04, 0.64, math.sin(a) * 1.36, -0.02, math.cos(a) * 1.36, CNW2, nil, 0, math.deg(a) + 90, 0)
  end
  ring(b, H, 0, -0.05, 0, 1.10, 32, 0.06, 0.08, C.steel, MAT.Metal)
  -- 驾驶舱
  local DZ = -1.80
  for _, s in ipairs({ -1, 1 }) do
    bx(H, 0.50, 1.00, 1.90, s * 0.74, FY + 0.50, -2.15, CNG)
    bx(H, 0.02, 0.80, 1.50, s * 0.49, FY + 0.50, -2.15, RGB(96, 110, 92))
  end
  bx(H, 0.98, 0.05, 1.20, 0, -0.38, -2.72, CNW2, nil, -32, 0, 0)
  bx(H, 0.98, 0.70, 0.05, 0, FY + 0.35, -3.18, CNW2)
  bx(H, 0.98, 0.04, 0.28, 0, -0.04, -2.02, CNW2)
  bx(H, 0.98, 0.04, 0.12, 0, -0.04, -1.24, CNW2)
  for _, s in ipairs({ -1, 1 }) do bx(H, 0.22, 0.04, 0.62, s * 0.38, -0.04, -1.58, CNW2) end
  b:group("dhatch", H, CF(0, -0.02, -1.58))
  b:cylY("dhatch", 0.05, 0.56, CF(0, -0.03, 0), CNW, MAT.SmoothPlastic)
  b:grab("dhatch", V(-0.12, -0.06, 0.05), V(0.12, -0.06, 0.05), V(0, -0.06, 0), 0.02, C.black)
  local eyeD = V(0, -0.24, DZ)
  for i = -1, 1 do
    local a = rad(i * 32)
    local p = V(math.sin(a) * 0.22, -0.13, DZ - 0.18 - math.cos(a) * 0.06)
    b:periscope(H, look(p, p + V(math.sin(a), 0, -math.cos(a))), 0.16, 0.09, 0.10)
  end
  b:seat(H, CF(0, FY + 0.22, -2.24) * ANG(rad(6), 0, 0), { w = 0.44, d = 0.40, back = 0.58, recline = 32, head = true, col = RGB(46, 50, 44) })
  -- 方向盘（99 式起用的方向盘操纵、液力机械综合传动）
  b:group("wheel", H, CF(0, FY + 0.50, -2.66) * ANG(rad(-55), 0, 0))
  Defs.ring(b, "wheel", 0, 0, 0, 0.17, 16, 0.03, 0.03, C.black, MAT.SmoothPlastic)
  b:tube("wheel", V(-0.17, 0, 0), V(0.17, 0, 0), 0.025, C.black)
  b:cylY("wheel", 0.04, 0.08, CF(), C.dark, MAT.Metal)
  b:tube(H, V(0, FY + 0.50, -2.66), V(0, FY + 0.05, -2.95), 0.06, C.gray, MAT.Metal)
  bx(H, 0.16, 0.04, 0.12, 0.12, FY + 0.06, -2.95, C.dark, MAT.DiamondPlate, -25, 0, 0)   -- 油门
  bx(H, 0.16, 0.04, 0.12, -0.10, FY + 0.06, -2.97, C.dark, MAT.DiamondPlate, -25, 0, 0)  -- 制动
  bx(H, 0.05, 0.16, 0.05, 0.30, FY + 0.30, -2.40, C.dark, MAT.Metal, -20, 0, 0)          -- 挡位手柄
  b:ball(H, 0.05, CF(0.30, FY + 0.40, -2.43), C.red)
  b:screen(H, 0.22, 0.14, look(V(-0.05, -0.42, -2.48), eyeD), "drvcn", { keys = { top = { "主菜单", "状态", "故障", "导航", "维护" }, bottom = { "起动", "熄火", "怠速", "灯检", "消音" } }, lightK = 0.3 })   -- 驾驶员数字仪表
  b:panel(H, 0.16, 0.28, look(V(-0.44, -0.64, -2.08), V(0, -0.6, -2.0)), 4, 2, RGB(60, 66, 60), { guard = true })
  b:placard(H, 0.10, 0.03, look(V(-0.44, -0.48, -2.08), V(0, -0.48, -2.0)) * CF(0, 0, -0.002), "电源", { bg = C.black, fg = C.white })
  b:extinguisher(H, CF(-0.34, FY + 0.25, -1.30), 0.46, 0.14)
  b:extinguisher(H, CF(0.34, FY + 0.25, -1.30), 0.46, 0.14)
  b:placard(H, 0.12, 0.05, CF(0.34, FY + 0.40, -1.22) * ANG(0, PI, 0), "灭火瓶", { bg = C.red, fg = C.white })
  b:light(H, CF(0, -0.10, -1.40), "dome", RGB(255, 240, 220), 2.8, 0.9)

  ---------------- 转盘式自动装弹机（跟着炮塔转，自己还能转）
  b:group("carousel", T, CF(0, FY + 0.03, 0))
  bx("carousel", 0.05, 0.05, 0.05, 0, 0, 0, C.dark)
  b:cylY("carousel", 0.03, 2.10, CF(0, 0.0, 0), RGB(60, 64, 60), MAT.Metal)        -- 转盘底盘
  b:cylY("carousel", 0.30, 0.50, CF(0, 0.15, 0), C.dark, MAT.Metal)               -- 中间的轴、电机
  local cassettes = {}
  for i = 0, 21 do
    local a = (i + 0.5) / 22 * 2 * PI
    local cf = ANG(0, a, 0) * CF(0, 0, 0)
    local rr = 0.66
    -- 弹盒：径向摆，弹底朝中间
    local tray = cf * CF(0, 0.07, -rr)
    local parts = {}
    table.insert(parts, b:box("carousel", V(0.15, 0.025, 0.70), tray, RGB(84, 90, 82), MAT.Metal))
    local kind = (i % 11 < 5) and "ap" or ((i % 11 < 8) and "heat" or ((i % 11 < 10) and "he" or "gl"))
    local tip = (kind == "ap") and RGB(40, 40, 40) or ((kind == "heat") and RGB(70, 80, 60) or ((kind == "he") and RGB(80, 86, 64) or RGB(60, 70, 80)))
    table.insert(parts, b:cylZ("carousel", 0.58, 0.125, tray * CF(0, 0.07, -0.02), tip, MAT.Metal))                     -- 下层：弹丸
    table.insert(parts, b:cylZ("carousel", 0.52, 0.125, tray * CF(0, 0.20, 0.01), RGB(170, 156, 112), MAT.SmoothPlastic)) -- 上层：药筒
    table.insert(parts, b:cylZ("carousel", 0.03, 0.13, tray * CF(0, 0.20, 0.28), RGB(150, 128, 82), MAT.Metal))          -- 药筒底盘
    cassettes[i + 1] = { parts = parts, a = a, kind = kind }
  end
  b:name("cassettes", cassettes)
  -- 炮塔篮地板（盖在转盘上面，中间有口子：从里面能看见弹盒）
  for i = 0, 11 do
    local a = (i + 0.5) * PI / 6
    if i % 3 ~= 1 then bx(T, 0.52, 0.03, 0.56, math.sin(a) * 0.80, FY + 0.38, math.cos(a) * 0.80, FLOOR, MAT.DiamondPlate, 0, math.deg(a) + 90, 0) end
  end
  ring(b, T, 0, -0.38, 0, 1.02, 12, 0.03, 0.03, C.lgray, MAT.Metal, -PI * 0.80, PI * 0.80)
  -- 提弹机（炮尾后面）：竖着的导轨、提弹架（子组 lift），链式推弹机
  bx(T, 0.06, 1.10, 0.06, -0.20, -0.45, 0.95, C.steel, MAT.Metal)
  bx(T, 0.06, 1.10, 0.06, 0.20, -0.45, 0.95, C.steel, MAT.Metal)
  b:group("lift", T, CF(0, FY + 0.20, 0.80))
  b:box("lift", V(0.42, 0.04, 0.70), CF(), RGB(110, 114, 106), MAT.Metal)
  b:box("lift", V(0.04, 0.30, 0.70), CF(-0.19, 0.15, 0), RGB(110, 114, 106), MAT.Metal)
  b:box("lift", V(0.04, 0.30, 0.70), CF(0.19, 0.15, 0), RGB(110, 114, 106), MAT.Metal)
  bx(T, 0.20, 0.16, 0.40, 0, 0.40, 1.18, C.dark, MAT.Metal)            -- 推弹机电机和链盒
  b:group("rammer", T, CF(0, 0.24, 1.10))
  b:box("rammer", V(0.08, 0.08, 0.50), CF(), RGB(60, 60, 58), MAT.Metal)
  b:cylZ("rammer", 0.04, 0.12, CF(0, 0, -0.26), C.steel, MAT.Metal)

  ---------------- 炮塔壳
  for i = 0, 15 do
    local a = (i + 0.5) * PI / 8
    bx(T, 0.52, 0.03, 0.60, math.sin(a) * 1.30, 0.0, math.cos(a) * 1.30, CNW2, nil, 0, math.deg(a) + 90, 0)
  end
  for _, s in ipairs({ -1, 1 }) do
    bx(T, 0.05, RY, 1.70, s * 1.20, RY / 2, 0.25, CNW)
    local p0, p1 = V(s * 1.20, 0, -0.60), V(s * 0.46, 0, -1.18)
    local mid = (p0 + p1) / 2
    b:box(T, V((p1 - p0).Magnitude, RY, 0.05), CF(mid.X, RY / 2, mid.Z) * ANG(0, math.atan2(-(p1.Z - p0.Z), p1.X - p0.X), 0), CNW)
    bx(T, 0.05, RY, 0.36, s * 0.44, RY / 2, -1.36, CNW2)
  end
  bx(T, 0.92, RY, 0.05, 0, RY / 2, -1.55, CNW2)
  bx(T, 2.44, RY, 0.05, 0, RY / 2, 1.10, CNW2)                          -- 炮塔后壁
  -- 顶：车长舱口（右）、炮长舱口（左），后部的抛壳窗（子组 stubport）
  bx(T, 2.44, 0.05, 0.40, 0, RY + 0.025, 0.90, CNW)
  bx(T, 0.40, 0.05, 0.60, 0, RY + 0.025, 0.40, CNW)
  bx(T, 0.30, 0.05, 0.60, 1.07, RY + 0.025, 0.40, CNW)
  bx(T, 0.30, 0.05, 0.60, -1.07, RY + 0.025, 0.40, CNW)
  bx(T, 2.44, 0.05, 0.50, 0, RY + 0.025, -0.15, CNW)
  bx(T, 2.44, 0.05, 0.80, 0, RY + 0.025, -0.80, CNW)
  bx(T, 0.92, 0.05, 0.38, 0, RY + 0.025, -1.37, CNW)
  ring(b, T, 0.58, RY + 0.035, 0.40, 0.44, 16, 0.24, 0.03, CNW2)
  ring(b, T, -0.58, RY + 0.035, 0.40, 0.42, 16, 0.22, 0.03, CNW2)
  for _, s in ipairs({ -1, 1 }) do
    local hn = (s > 0) and "chatch" or "ghatch"
    ring(b, T, s * 0.58, RY + 0.02, 0.40, 0.33, 16, 0.06, 0.06, CNW2, MAT.Metal)
    b:group(hn, T, CF(s * 0.58, RY + 0.10, 0.40))
    b:cylY(hn, 0.05, 0.58, CF(), CNW, MAT.SmoothPlastic)
    b:grab(hn, V(-0.11, -0.03, 0.10), V(0.11, -0.03, 0.10), V(0, -0.05, 0), 0.02, C.black)
  end
  b:group("stubport", T, CF(0, RY + 0.03, 0.95))
  b:box("stubport", V(0.26, 0.03, 0.22), CF(), RGB(170, 176, 166), MAT.Metal)
  for _, z in ipairs({ -0.45, 0.10, 0.65 }) do bx(T, 2.4, 0.04, 0.05, 0, RY - 0.02, z, CNW2) end

  ---------------- 主炮：ZPT-98A 125 毫米
  b:box(G, V(0.40, 0.36, 0.80), CF(0, 0, -0.10), RGB(100, 106, 98), MAT.Metal)
  for _, s in ipairs({ -1, 1 }) do b:cylZ(G, 0.66, 0.085, CF(s * 0.15, 0.21, -0.02), C.steel, MAT.Metal) end
  b:group("recoil", G, CF())
  b:cylZ("recoil", 0.80, 0.26, CF(0, 0, -0.16), RGB(70, 76, 72), MAT.Metal)
  b:box("recoil", V(0.50, 0.46, 0.56), CF(0, -0.02, 0.58), RGB(66, 70, 66), MAT.Metal)
  b:cylZ("recoil", 0.04, 0.21, CF(0, 0.0, 0.875), RGB(90, 94, 90), MAT.Metal)
  b:group("blk", "recoil", CF(0, -0.02, 0.58))
  b:box("blk", V(0.30, 0.34, 0.28), CF(), RGB(122, 126, 120), MAT.Metal)
  for _, s in ipairs({ -1, 1 }) do
    b:box(G, V(0.04, 0.50, 0.78), CF(s * 0.38, -0.06, 0.82), RGB(96, 104, 90), MAT.Metal)
    b:box(G, V(0.05, 0.07, 0.78), CF(s * 0.38, 0.21, 0.82), RGB(230, 196, 40), MAT.SmoothPlastic)
  end
  b:placard(G, 0.30, 0.07, CF(-0.405, -0.02, 0.82) * ANG(0, PI / 2, 0), "后坐危险区", { bg = RGB(230, 196, 40) })
  b:placard(G, 0.30, 0.07, CF(0.405, -0.02, 0.82) * ANG(0, -PI / 2, 0), "后坐危险区", { bg = RGB(230, 196, 40) })
  b:box(G, V(0.10, 0.13, 0.74), CF(0.32, 0.02, -0.02), RGB(40, 42, 42), MAT.Metal)        -- 并列机枪
  b:box(T, V(0.28, 0.26, 0.40), CF(0.70, -0.50, -0.92), CNG)
  b:placard(T, 0.18, 0.06, CF(0.70, -0.42, -0.715) * ANG(0, PI, 0), "并列机枪弹", { bg = CNG, fg = C.white })

  ---------------- 炮长位（左）
  local gEye = V(-0.52, 0.30, -0.70)
  bx(T, 0.30, 0.44, 0.40, -0.62, 0.56, -0.96, RGB(46, 50, 48))                    -- 主瞄准镜镜体
  bx(T, 0.22, 0.18, 0.14, -0.55, 0.36, -0.86, RGB(36, 38, 40))
  b:cylZ(T, 0.07, 0.06, CF(-0.55, 0.33, -0.78), C.rubber, MAT.Fabric)
  b:box(T, V(0.24, 0.06, 0.08), CF(-0.55, 0.43, -0.80), C.rubber, MAT.Fabric)
  b:led(T, CF(-0.55, 0.33, -0.74), RGB(80, 255, 120), 0.014, "gpsEye")
  b:placard(T, 0.14, 0.04, CF(-0.62, 0.56, -0.755) * ANG(0, PI, 0), "主瞄准镜", { bg = C.black, fg = C.white })
  b:screen(T, 0.20, 0.15, look(V(-0.86, 0.22, -0.80), gEye + V(0, -0.1, 0.1)), "fcscn", { keys = { top = { "主菜单", "弹种", "测距", "校炮", "激光" }, bottom = { "极性", "倍率", "火控", "自检", "复位" } }, lightK = 0.28 })   -- 火控计算机面板
  b:screen(T, 0.18, 0.13, look(V(-0.30, 0.52, -0.92), gEye), "gunsight", { lightK = 0.25 })                          -- 炮长显示器（热像）
  b:tube(T, V(-0.55, FY + 0.40, -0.66), V(-0.55, -0.15, -0.68), 0.06, C.gray, MAT.Metal)
  bx(T, 0.30, 0.09, 0.12, -0.55, -0.10, -0.70, RGB(46, 48, 50))
  b:group("gch", T, CF(-0.55, -0.08, -0.70))
  for _, s in ipairs({ -1, 1 }) do
    b:box("gch", V(0.05, 0.14, 0.05), CF(s * 0.14, 0.08, 0) * ANG(rad(-20), 0, 0), C.black)
    b:button("gch", CF(s * 0.14, 0.155, -0.04) * ANG(rad(-70), 0, 0), C.red, 0.012)
  end
  b:seat(T, CF(-0.55, -0.40, -0.36), { w = 0.36, d = 0.32, back = 0.36, recline = 4, post = 0.25, col = RGB(46, 50, 44) })
  bx(T, 0.20, 0.18, 0.05, -0.55, -0.10, -0.92, RGB(46, 50, 44), MAT.Fabric)

  ---------------- 车长位（右）
  local cEye = V(0.56, 0.52, -0.10)
  bx(T, 0.30, 0.38, 0.34, 0.62, 0.62, -0.50, RGB(46, 50, 48))                     -- 周视瞄准镜下部
  b:cylZ(T, 0.07, 0.06, CF(0.56, 0.52, -0.30), C.rubber, MAT.Fabric)
  b:led(T, CF(0.56, 0.52, -0.26), RGB(80, 255, 120), 0.014, "gpsEye")
  b:screen(T, 0.26, 0.19, look(V(0.82, 0.30, -0.42), cEye), "cnmap", { keys = { top = { "地图", "消息", "态势", "导航", "坐标" }, bottom = { "放大", "缩小", "标绘", "亮+", "亮-" } }, lightColor = RGB(150, 190, 230), lightK = 0.35 })   -- 综合显示终端
  b:screen(T, 0.18, 0.13, look(V(0.36, 0.28, -0.46), cEye), "citvcn", { keys = { top = { "白热", "黑热", "宽视场", "窄视场" }, bottom = { "手动", "扫描", "随炮", "指示" } }, lightK = 0.25 })                                    -- 周视镜热像
  b:group("cch", T, CF(0.86, 0.02, -0.18))
  b:box("cch", V(0.05, 0.13, 0.05), CF(0, 0.07, 0) * ANG(rad(-15), 0, 0), C.black)
  b:tube(T, V(0.86, -0.40, -0.18), V(0.86, 0.0, -0.18), 0.04, C.gray, MAT.Metal)
  b:panel(T, 0.24, 0.18, look(V(1.15, 0.36, 0.10), V(0, 0.36, 0.10)), 3, 4, RGB(60, 66, 60))
  b:radio(T, 0.34, 0.15, 0.28, look(V(1.15, 0.18, 0.55), V(0, 0.18, 0.55)), RGB(64, 72, 60))
  b:seat(T, CF(0.58, -0.16, 0.30), { w = 0.38, d = 0.34, back = 0.34, recline = 6, post = 0.30, col = RGB(46, 50, 44) })
  b:extinguisher(T, CF(-1.12, 0.10, 0.50), 0.36, 0.12)
  b:harness(T, { V(0.10, RY - 0.06, -1.05), V(0.40, RY - 0.06, -0.55), V(0.95, RY - 0.06, -0.35), V(1.10, 0.40, -0.25) }, 4, 0.02)
  b:harness(T, { V(-0.10, RY - 0.06, -1.05), V(-0.40, RY - 0.06, -0.55), V(-0.95, RY - 0.06, -0.35), V(-1.10, 0.40, -0.25) }, 3, 0.02)
  b:light(T, CF(0, RY - 0.06, 0.40), "dome", RGB(255, 244, 228), 3.4, 1.1)
  b:light(T, CF(-0.60, RY - 0.06, -0.30), "dome", RGB(255, 244, 228), 3.0, 0.9)
  b:light(T, CF(0.58, RY - 0.05, 0.40), "flash", RGB(255, 196, 120), 4.0, 0)
  b:light(T, CF(0.30, 0.40, -0.40), "warn", RGB(255, 40, 30), 3.0, 0)
  for _, p in ipairs({ V(0, RY - 0.02, 0.40), V(-0.60, RY - 0.02, -0.30) }) do
    b:box(T, V(0.14, 0.04, 0.10), CF(p), C.dark, MAT.Metal)
    b:led(T, CF(p - V(0, 0.025, 0)), RGB(255, 236, 210), 0.05, "domeLamp")
  end

  return {
    gunK = 0.30,   -- 125 毫米炮后坐行程约 300 毫米
    loader = "carousel",
    stations = {
      driver = { g = H, eye = eyeD, look = V(0, 0.15, -1), yaw = 110, up = 35, down = 55, crew = "driver",
        optics = { primary = { kind = "nv", name = "驾驶员微光夜视仪", g = H, pos = V(0, 0.06, -2.2), dir = "hull", fovs = { 42 }, ret = "none", look = "nv", shape = "rect" } } },
      gunner = { g = T, eye = gEye + V(-0.02, 0.06, 0.16), look = V(0, -0.18, -1), yaw = 120, up = 45, down = 60, crew = "gunner", sight = true, scope = V(-0.55, 0.33, -0.76),
        optics = { primary = { kind = "gps" },
          alt = { kind = "gas", name = "备用瞄准镜  8倍", g = G, pos = V(-0.24, 0.12, 0.40), dir = "gun", fovs = { 8 }, ret = "gascn", look = "day", shape = "circle", useSight = true } } },
      commander = { g = T, eye = cEye, look = V(0, -0.25, -1), yaw = 160, up = 70, down = 70, crew = "commander", scope = V(0.56, 0.52, -0.28),
        optics = { primary = { kind = "pano", name = "车长周视瞄准镜", g = T, pos = V(0.62, 1.15, -0.50), dir = "citv", fovs = { 20, 6 }, ret = "pano", look = "whot", shape = "circle" },
          alt = { kind = "gps" } } },
    },
    order = { "driver", "gunner", "commander" },
    crew = {
      driver = { dress = "tank_cn", g = H, eye = eyeD, lean = 32, yaw = 0, look = V(0, 0.1, -1),
        hands = { l = { "wheel", V(-0.16, 0.0, 0) }, r = { "wheel", V(0.16, 0.0, 0) } },
        feet = { l = { H, V(-0.10, FY + 0.10, -2.92) }, r = { H, V(0.12, FY + 0.10, -2.90) } } },
      gunner = { dress = "tank_cn", g = T, eye = gEye + V(0, -0.02, 0.02), lean = -24, yaw = 0, look = V(0, -0.12, -1),
        hands = { l = { "gch", V(-0.14, 0.12, 0.0) }, r = { "gch", V(0.14, 0.12, 0.0) } },
        feet = { l = { T, V(-0.66, FY + 0.46, -0.78) }, r = { T, V(-0.44, FY + 0.46, -0.76) } } },
      commander = { dress = "tank_cn", g = T, eye = cEye, lean = -14, yaw = 0, look = V(0, -0.30, -1),
        hands = { l = { T, V(0.70, 0.22, -0.40) }, r = { "cch", V(0, 0.10, 0) } },
        feet = { l = { T, V(0.48, FY + 0.46, -0.10) }, r = { T, V(0.68, FY + 0.46, -0.10) } } },
    },
  }
end

---------------------------------------------------------------- 战斗机座舱（对标 DCS）：按机型的布局参数拼，原点在飞行员眼位，−Z 朝前
-- 共用：座舱浴盆（地板、两侧壁、后隔框）、两侧操纵台（开关面板朝上）、主仪表板、遮光罩、平显（组合玻璃 + 投影仪）、座舱盖框和玻璃
--   （玻璃有划痕、能反光，Interior.lua 再加迎着日月光时的眩光）、弹射座椅（头靠 / 降落伞箱、坐垫、救生包、弹射拉环、肩带）、
--   驾驶杆（中央杆 / 侧杆，跟着杆量动）、油门（跟着油门走）、脚蹬（跟着方向舵）、起落架手柄（跟着起落架收放，三个绿灯）、
--   主告警 / 注意灯、备份仪表（姿态、高度、空速）
--   L = { disp = "pano" / "f22" / "mfd4" / "a10", hud = true / false, stick = "center" / "side", seats = 1 / 2, cn = 中文标签, frame = 风挡有框 }
-- 各型资料：歼-20 —— 一块大尺寸宽幅触摸屏 + 两块上前显示器 + 广角平显，中央驾驶杆；F-35 —— 20×8 英寸全景座舱显示器、没有平显（头盔显示器）、
--   右侧杆；F-22 —— 中间 8×8 英寸主显示器、三块 6.25 英寸副显示器、两块上前显示器、平显、右侧杆；歼-16 —— 前后舱各四块多功能显示器、平显、
--   中央杆；A-10C —— 两块 5×5 英寸多功能彩显 + 一排机械仪表、平显、中央杆
local PIT = RGB(46, 50, 54)      -- 座舱漆：深灰
local PIT2 = RGB(36, 39, 42)
local GLARE = RGB(24, 25, 27)

function Defs.jet(b, ctx, L)
  local H = "hull"
  local function bx(sx, sy, sz, x, y, z, col, mat, rx, ry, rz)
    return b:box(H, V(sx, sy, sz), CF(x, y, z) * ANG(rad(rx or 0), rad(ry or 0), rad(rz or 0)), col, mat)
  end
  local eye = V(0, 0, 0)
  local function look(p, at) return CFrame.lookAt(p, at or eye) end
  local cn = L.cn
  -- 浴盆
  bx(0.84, 0.03, 2.0, 0, -1.06, -0.35, PIT2, MAT.DiamondPlate)
  for _, s in ipairs({ -1, 1 }) do
    bx(0.03, 0.78, 2.0, s * 0.44, -0.67, -0.35, PIT)
    bx(0.04, 0.05, 1.7, s * 0.45, -0.29, -0.25, PIT2, MAT.Metal)                 -- 座舱盖导轨（舱沿）
    -- 两侧操纵台：台面上一块块开关面板（朝上偏向飞行员）
    bx(0.17, 0.10, 0.86, s * 0.345, -0.62, -0.04, PIT)
    for i = 0, 3 do
      local z = -0.38 + i * 0.21
      b:panel(H, 0.15, 0.17, CFrame.lookAt(V(s * 0.345, -0.565, z), V(s * 0.345 - s * 0.05, 0.4, z + 0.12)), 3, 3, RGB(54, 58, 62), { guard = (i == 1) })
    end
  end
  bx(0.86, 1.3, 0.04, 0, -0.42, 0.66, PIT2)                                      -- 后隔框
  bx(0.86, 0.04, 0.6, 0, -0.30, 0.94, PIT2, nil, -18, 0, 0)                     -- 座舱盖后面的整流罩里面
  -- 脚蹬（跟着方向舵前后）
  for _, s in ipairs({ -1, 1 }) do
    local gname = (s < 0) and "pedL" or "pedR"
    b:group(gname, H, CF(s * 0.13, -0.96, -1.05))
    b:box(gname, V(0.10, 0.20, 0.03), CF() * ANG(rad(-20), 0, 0), RGB(40, 42, 44), MAT.Metal)
    b:box(gname, V(0.10, 0.03, 0.10), CF(0, -0.10, 0.04), RGB(60, 62, 64), MAT.DiamondPlate)
  end
  -- 主仪表板 + 遮光罩
  b:box(H, V(0.80, 0.46, 0.06), look(V(0, -0.46, -0.77), V(0, -0.1, 0.3)), PIT)
  bx(0.78, 0.05, 0.26, 0, -0.205, -0.73, GLARE, MAT.Fabric, 4, 0, 0)
  bx(0.78, 0.30, 0.04, 0, -0.74, -0.95, PIT2, nil, 30, 0, 0)                   -- 膝下的面板（伸向脚蹬）
  -- 主告警、注意灯（遮光罩上，挨打 / 失速时闪）
  b:led(H, CF(-0.30, -0.17, -0.66), RGB(255, 40, 30), 0.022, "mwarn")
  b:led(H, CF(0.30, -0.17, -0.66), RGB(255, 180, 30), 0.022, "mcaut")
  b:placard(H, 0.07, 0.016, look(V(-0.30, -0.185, -0.645)), cn and "主告警" or "MASTER WARN", { bg = C.black, fg = RGB(255, 80, 70) })
  b:placard(H, 0.07, 0.016, look(V(0.30, -0.185, -0.645)), cn and "主注意" or "MASTER CAUT", { bg = C.black, fg = RGB(255, 190, 60) })
  -- 显示器
  local K = cn and { top = { "姿态", "雷达", "态势", "武器", "发动机" }, bottom = { "油量", "检查", "目标", "通信", "菜单" } }
    or { top = { "PFD", "RDR", "SA", "SMS", "ENG" }, bottom = { "FUEL", "CHK", "TGT", "COM", "MENU" } }
  local disp = L.disp or "pano"
  if disp == "pano" then
    b:screen(H, 0.50, 0.21, look(V(0, -0.44, -0.735)), "pano", { keys = K, lightK = 0.45, lightColor = RGB(140, 180, 220) })
    b:screen(H, 0.10, 0.07, look(V(-0.21, -0.27, -0.71)), "ufd", { lightK = 0.2 })
    b:screen(H, 0.10, 0.07, look(V(0.21, -0.27, -0.71)), "ufd2", { lightK = 0.2 })
  elseif disp == "f22" then
    b:screen(H, 0.20, 0.20, look(V(0, -0.45, -0.74)), "mfd_sa", { keys = K, lightK = 0.4 })
    b:screen(H, 0.15, 0.15, look(V(-0.24, -0.47, -0.72)), "mfd_pfd", { keys = K, lightK = 0.3 })
    b:screen(H, 0.15, 0.15, look(V(0.24, -0.47, -0.72)), "mfd_sms", { keys = K, lightK = 0.3 })
    b:screen(H, 0.15, 0.12, look(V(0, -0.64, -0.80)), "mfd_eng", { lightK = 0.25 })
    b:screen(H, 0.09, 0.07, look(V(-0.13, -0.27, -0.70)), "ufd", { lightK = 0.2 })
    b:screen(H, 0.09, 0.07, look(V(0.13, -0.27, -0.70)), "ufd2", { lightK = 0.2 })
  elseif disp == "mfd4" then
    b:screen(H, 0.15, 0.15, look(V(-0.17, -0.38, -0.74)), "mfd_pfd", { keys = K, lightK = 0.3 })
    b:screen(H, 0.15, 0.15, look(V(0.17, -0.38, -0.74)), "mfd_sa", { keys = K, lightK = 0.3 })
    b:screen(H, 0.13, 0.13, look(V(-0.17, -0.58, -0.77)), "mfd_sms", { keys = K, lightK = 0.25 })
    b:screen(H, 0.13, 0.13, look(V(0.17, -0.58, -0.77)), "mfd_eng", { keys = K, lightK = 0.25 })
  else   -- a10：两块多功能彩显 + 机械仪表
    b:screen(H, 0.13, 0.13, look(V(-0.20, -0.42, -0.74)), "mfd_sa", { keys = K, lightK = 0.3 })
    b:screen(H, 0.13, 0.13, look(V(0.20, -0.42, -0.74)), "mfd_sms", { keys = K, lightK = 0.3 })
    b:screen(H, 0.20, 0.13, look(V(0, -0.60, -0.78)), "gauges", { lightK = 0.15, light = false })
  end
  -- 备份仪表（姿态、高度、空速）：主显示器下面一排小圆表
  b:screen(H, 0.065, 0.065, look(V(-0.08, -0.66, -0.78)), "adi", { light = false, ppm = 2200 })
  b:screen(H, 0.055, 0.055, look(V(0.0, -0.66, -0.78)), "asi", { light = false, ppm = 2200 })
  b:screen(H, 0.055, 0.055, look(V(0.08, -0.66, -0.78)), "alt", { light = false, ppm = 2200 })
  -- 平显：投影仪 + 组合玻璃（符号按眼睛的位置算，真像在无穷远：Interior 的 hud 页）
  if L.hud ~= false then
    bx(0.20, 0.08, 0.22, 0, -0.165, -0.66, RGB(30, 32, 34), MAT.Metal)
    for _, sx in ipairs({ -1, 1 }) do bx(0.012, 0.15, 0.012, sx * 0.085, -0.07, -0.67, RGB(30, 32, 34), MAT.Metal) end
    local hs = b:screen(H, 0.17, 0.14, CFrame.lookAt(V(0, -0.055, -0.66), V(0, -0.03, 0.2)), "hud", { light = false, glow = 2.2, ppm = 3000, bezel = 0.004, depth = 0.004, frame = RGB(30, 32, 34) })
    hs.part.Material = MAT.Glass
    hs.part.Transparency = 0.86
    hs.part.Color = RGB(150, 200, 170)
    hs.root.BackgroundTransparency = 1
    b:name("hud", hs)
  end
  -- 驾驶杆
  if L.stick == "side" then
    b:group("stick", H, CF(0.33, -0.56, -0.10))
    b:box("stick", V(0.045, 0.12, 0.05), CF(0, 0.07, 0) * ANG(rad(-12), 0, 0), C.black)
    b:box("stick", V(0.05, 0.03, 0.06), CF(0, 0.14, -0.01), RGB(40, 40, 40))
    b:button("stick", CF(0, 0.155, -0.035) * ANG(rad(-70), 0, 0), C.red, 0.012)
    bx(0.08, 0.04, 0.12, 0.33, -0.575, -0.08, PIT2, MAT.Metal)
    bx(0.07, 0.03, 0.16, 0.30, -0.53, 0.06, RGB(40, 42, 44), MAT.Fabric)        -- 手臂托
  else
    b:group("stick", H, CF(0, -0.98, -0.33))
    b:tube("stick", V(0, 0, 0), V(0, 0.34, -0.05), 0.03, C.dark, MAT.Metal)
    b:box("stick", V(0.05, 0.13, 0.055), CF(0, 0.40, -0.06) * ANG(rad(-10), 0, 0), C.black)
    b:box("stick", V(0.055, 0.03, 0.065), CF(0, 0.47, -0.07), RGB(40, 40, 40))
    b:button("stick", CF(0, 0.485, -0.10) * ANG(rad(-70), 0, 0), C.red, 0.012)
    b:box("stick", V(0.012, 0.035, 0.012), CF(0, 0.40, -0.095), RGB(60, 60, 60))   -- 扳机
    b:cylY(H, 0.06, 0.12, CF(0, -1.0, -0.33), RGB(30, 30, 30), MAT.Fabric)      -- 杆根的防尘罩
  end
  -- 油门（左侧操纵台上，跟着油门推）
  b:group("thr", H, CF(-0.33, -0.57, 0.02))
  b:box("thr", V(0.03, 0.10, 0.03), CF(0, 0.05, 0) * ANG(rad(-25), 0, 0), C.dark, MAT.Metal)
  b:box("thr", V(0.07, 0.05, 0.08), CF(0, 0.11, -0.03), C.black)
  b:button("thr", CF(-0.025, 0.13, -0.05) * ANG(0, 0, 0), C.dark, 0.01)
  bx(0.04, 0.012, 0.22, -0.33, -0.565, -0.02, RGB(20, 20, 20))                    -- 油门滑槽
  -- 起落架手柄（主仪表板左边，带轮子形状的头）+ 三个绿灯
  b:group("gearh", H, CF(-0.37, -0.43, -0.70))
  b:box("gearh", V(0.015, 0.10, 0.015), CF(0, 0.05, 0), C.lgray, MAT.Metal)
  b:cyl("gearh", 0.025, 0.05, CF(0, 0.11, 0), C.white)
  for i = -1, 1 do b:led(H, CF(-0.33 + i * 0.022, -0.34, -0.705), RGB(80, 255, 110), 0.012, "gear") end
  b:placard(H, 0.06, 0.016, look(V(-0.37, -0.32, -0.70)), cn and "起落架" or "LDG GEAR", { bg = C.black, fg = C.white })
  -- 弹射座椅
  local SC = RGB(54, 58, 54)
  b:seat(H, CF(0, -0.80, 0.14), { w = 0.46, d = 0.44, back = 0.70, recline = 16, head = false, col = RGB(58, 62, 56), frame = RGB(44, 46, 48) })
  bx(0.36, 0.30, 0.16, 0, 0.06, 0.36, SC, nil, 16, 0, 0)                          -- 头靠 / 降落伞箱
  bx(0.40, 0.08, 0.14, 0, 0.24, 0.40, RGB(36, 38, 40), nil, 16, 0, 0)
  bx(0.48, 0.12, 0.44, 0, -0.90, 0.14, RGB(70, 72, 60))                            -- 救生包
  for _, s in ipairs({ -1, 1 }) do
    bx(0.04, 0.95, 0.06, s * 0.26, -0.42, 0.34, SC, MAT.Metal, 16, 0, 0)            -- 座椅导轨
    bx(0.03, 0.03, 0.30, s * 0.20, -0.25, 0.06, RGB(60, 70, 50), MAT.Fabric, -50, 0, 0)   -- 肩带
  end
  -- 弹射拉环（黄黑相间，坐垫前面两腿之间）
  for i = 0, 3 do bx(0.025, 0.025, 0.02, -0.04 + i * 0.027, -0.80, -0.11, (i % 2 == 0) and C.yellow or C.black) end
  b:placard(H, 0.10, 0.022, CF(0, -0.765, -0.10) * ANG(rad(-60), 0, 0), cn and "弹射" or "EJECT", { bg = C.yellow, fg = C.black })
  -- 座舱盖框、玻璃（有划痕；Interior 迎着日月光加眩光）
  local glass = {}
  local R0, cy0 = 0.52, -0.24
  for i = 0, 7 do   -- 八条弧形玻璃，从左舱沿翻过头顶到右舱沿
    local a0, a1 = rad(-82 + i * 20.5), rad(-82 + (i + 1) * 20.5)
    local am = (a0 + a1) / 2
    local x, y = math.sin(am) * R0, cy0 + math.cos(am) * R0
    local wdt = 2 * R0 * math.sin((a1 - a0) / 2) * 1.04
    local g = b:box(H, V(wdt, 0.006, 1.5), CF(x, y, -0.18) * ANG(0, 0, -am), RGB(170, 190, 200), MAT.Glass)
    g.Transparency, g.Reflectance, g.CastShadow = 0.9, 0.08, false
    table.insert(glass, g)
  end
  -- 风挡（前面三块斜的）
  for i = -1, 1 do
    local g = b:box(H, V(0.30, 0.006, 0.56), CF(i * 0.29, 0.02, -0.98) * ANG(rad(-58), rad(i * 26), 0), RGB(170, 190, 200), MAT.Glass)
    g.Transparency, g.Reflectance, g.CastShadow = 0.9, 0.1, false
    table.insert(glass, g)
  end
  b:name("glass", glass)
  if L.frame then   -- 风挡框、后视镜
    for _, s in ipairs({ -1, 1 }) do bx(0.03, 0.55, 0.04, s * 0.30, 0.0, -0.92, RGB(40, 42, 44), MAT.Metal, -40, 0, s * 12) end
    bx(0.62, 0.03, 0.05, 0, 0.26, -0.80, RGB(40, 42, 44), MAT.Metal)
    for i = -1, 1 do
      local m = bx(0.10, 0.045, 0.01, i * 0.16, 0.22, -0.78, RGB(200, 210, 215), MAT.Glass, 10, 0, 0)
      m.Reflectance = 0.6
    end
  else
    bx(0.90, 0.04, 0.05, 0, 0.30, 0.48, RGB(40, 42, 44), MAT.Metal)               -- 后拱框
  end
  -- 座舱灯（夜间：仪表泛光照明，泛绿白）
  b:light(H, CF(0, -0.30, -0.55), "dome", RGB(200, 230, 255), 1.6, 0.25)
  b:light(H, CF(-0.36, -0.40, -0.10), "dome", RGB(200, 230, 255), 1.0, 0.18)
  b:light(H, CF(0.36, -0.40, -0.10), "dome", RGB(200, 230, 255), 1.0, 0.18)
  b:light(H, CF(0, -0.10, -0.50), "warn", RGB(255, 40, 30), 1.6, 0)
  local dress = cn and "pilot_cn" or "pilot_us"
  local crew = {
    pilot = { dress = dress, g = H, eye = eye, lean = 4, yaw = 0, look = V(0, -0.05, -1),
      hands = { r = { "stick", (L.stick == "side") and V(0, 0.10, 0.0) or V(0, 0.42, -0.06) }, l = { "thr", V(0, 0.12, -0.02) } },
      feet = { l = { "pedL", V(0, -0.04, 0.06) }, r = { "pedR", V(0, -0.04, 0.06) } } },
  }
  local stations = { pilot = { g = H, eye = eye, look = V(0, -0.02, -1), yaw = 150, up = 80, down = 60, crew = "pilot" } }
  local order = { "pilot" }
  if L.seats == 2 then   -- 后舱（武器系统官）：高一截、往后 1.15 米；同样的显示器
    local ry, rz = 0.22, 1.15
    bx(0.84, 0.03, 1.1, 0, -1.06 + ry, rz - 0.1, PIT2, MAT.DiamondPlate)
    for _, sx in ipairs({ -1, 1 }) do bx(0.03, 0.78, 1.1, sx * 0.44, -0.67 + ry, rz - 0.1, PIT) end
    b:screen(H, 0.15, 0.15, look(V(-0.17, -0.40 + ry, rz - 0.72), V(0, ry, rz)), "mfd_sa", { keys = K, lightK = 0.25 })
    b:screen(H, 0.15, 0.15, look(V(0.17, -0.40 + ry, rz - 0.72), V(0, ry, rz)), "mfd_sms", { keys = K, lightK = 0.25 })
    b:seat(H, CF(0, -0.80 + ry, rz + 0.14), { w = 0.46, d = 0.44, back = 0.70, recline = 16, col = RGB(58, 62, 56), frame = RGB(44, 46, 48) })
    bx(0.36, 0.30, 0.16, 0, 0.06 + ry, rz + 0.36, SC, nil, 16, 0, 0)
    crew.wso = { dress = dress, g = H, eye = V(0, ry, rz), lean = 4, yaw = 0, look = V(0, -0.1, -1),
      hands = { l = { H, V(-0.12, -0.45 + ry, rz - 0.35) }, r = { H, V(0.12, -0.45 + ry, rz - 0.35) } },
      feet = { l = { H, V(-0.12, -0.98 + ry, rz - 0.75) }, r = { H, V(0.12, -0.98 + ry, rz - 0.75) } } }
    stations.wso = { g = H, eye = V(0, ry, rz), look = V(0, -0.05, -1), yaw = 150, up = 80, down = 60, crew = "wso" }
    table.insert(order, "wso")
  end
  return { air = true, stations = stations, order = order, crew = crew, cn = cn, glass = glass }
end

Defs.j20 = function(b, ctx) return Defs.jet(b, ctx, { disp = "pano", hud = true, stick = "center", cn = true }) end
Defs.j35 = function(b, ctx) return Defs.jet(b, ctx, { disp = "pano", hud = true, stick = "side", cn = true }) end
Defs.j50 = function(b, ctx) return Defs.jet(b, ctx, { disp = "pano", hud = true, stick = "side", cn = true }) end
Defs.j16 = function(b, ctx) return Defs.jet(b, ctx, { disp = "mfd4", hud = true, stick = "center", seats = 2, frame = true, cn = true }) end
Defs.j15t = function(b, ctx) return Defs.jet(b, ctx, { disp = "mfd4", hud = true, stick = "center", frame = true, cn = true }) end
Defs.f35 = function(b, ctx) return Defs.jet(b, ctx, { disp = "pano", hud = false, stick = "side" }) end
Defs.f22 = function(b, ctx) return Defs.jet(b, ctx, { disp = "f22", hud = true, stick = "side" }) end
Defs.a10c = function(b, ctx) return Defs.jet(b, ctx, { disp = "a10", hud = true, stick = "center", frame = true }) end

return Defs
