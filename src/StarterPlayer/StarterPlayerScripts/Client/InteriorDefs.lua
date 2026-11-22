-- Roblox全面大战场（客户端）——各型载具的内饰（真实布局、真实尺寸，米）。InteriorKit 拼零件，Interior.lua 让它动起来
--   坐标：原点在炮塔座圈中心、座圈平面上；X 右、Y 上、−Z 朝前（同 VehDefs）。组：hull 车体（不随炮塔转）、turret 炮塔、gun 炮耳轴（随炮俯仰）
--   每型返回 { stations 乘员位（镜头）, crew 乘员（姿势）, gunK 炮的后坐（米）, anim 动画用的子组名, lights / screens 由 Kit 记 }
--   资料：公开的照片、视频、剖视图与手册插图（M1A2：TM 9-2350-288 系列插图、美军开放日照片；99A：央视节目和阅兵车内镜头）；
--     看不到的地方按同类车的通常做法补（标了「推测」）
local Kit = require(script.Parent:WaitForChild("InteriorKit"))
local V, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
-- 平显原模型的元数据（tools/weapons/hud.mjs 生成：每块的中心、大小，组合玻璃多大）
local HUDM = nil
do
  local ok, r = pcall(function() return require(game:GetService("ReplicatedStorage"):WaitForChild("HudMeta", 3)) end)
  if ok and type(r) == "table" then HUDM = r end
end
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
          third = { kind = "crows", name = "CROWS-LP  M2", g = T, pos = V(0.62, 1.40, 0.20), dir = "free", fovs = { 30, 9 }, ret = "crows", look = "day", shape = "rect",
            rws = true, eye = V(-0.75, 0.30, 0.10) } } },   -- 摄像头在 M2 托架左边（格，相对机枪耳轴），跟着武器站转、俯仰
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
  -- 炮长显示器（热像）：原来在 (-0.30, 0.52)，跑到了炮闩左边那块防护板（x = -0.38，顶到 0.55 以上）里边，炮长隔着防护板看不见
  --   （用户 11-22：屏幕会被挡住）——挪到炮长这边、主瞄准镜目镜下面（tools/mock/interior_occ.lua 查：眼睛到屏幕中间没有东西）
  b:screen(T, 0.18, 0.13, look(V(-0.50, 0.10, -0.92), gEye), "gunsight", { lightK = 0.25 })
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
  -- 周视镜热像：原来 x = 0.36，在炮闩右边防护板（x = 0.38）里边，车长隔着防护板看（用户 11-22：屏幕会被挡住）——挪到车长这边
  b:screen(T, 0.18, 0.13, look(V(0.50, 0.28, -0.46), cEye), "citvcn", { keys = { top = { "白热", "黑热", "宽视场", "窄视场" }, bottom = { "手动", "扫描", "随炮", "指示" } }, lightK = 0.25 })
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
--   L = { disp = "j20" / "f35" / "f22" / "j16" / "j15t" / "a10" / "pano", hud = true / false, hudW / hudH = 平显组合玻璃宽高,
--         hudFrame = "tall"（两根立柱 + 顶梁）/ "box"（厚圆角黑框）/ "wide"（歼-20：两根粗立柱往外斜）, hoop = { z, th, mirrors, struts, compass } 座舱盖前面那道拱框,
--         goldGlass = 座舱盖镀金（隐身机）, stick = "center" / "side",
--         seats = 1 / 2, cn = 中文标签, frame = 风挡有框, minScreens = 这一型真有几块屏（测试按它查，默认 5）, noRadar = 没有雷达（A-10C） }
-- 各型的屏幕块数、尺寸、摆法照网上查到的资料（docs/cockpit_research.md，出处写在里面；查不到的歼-35、歼-50 用 pano 整块大屏）
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
  local disp = L.disp or "pano"
  -- 平显下面有正前方控制板（UFC / ICP）的机型（用户 11-21 给的歼-20、歼-16、歼-15T 第一人称参考图，F-22 真机照片）：
  --   遮光罩中间让开控制板那么宽，平显投影仪改浅（原来往后伸到离眼 0.55 米，挡住控制板上半截），主显示器往下挪
  local UFCW = ({ j20 = 0.21, j16 = 0.20, j15t = 0.21, f22 = 0.17 })[disp]
  b:box(H, V(0.80, 0.46, 0.06), look(V(0, -0.46, -0.77), V(0, -0.1, 0.3)), PIT)
  bx(0.78, 0.05, 0.16, 0, -0.205, -0.78, GLARE, MAT.Fabric, 4, 0, 0)   -- 遮光罩：前沿离眼 0.70 米（原来 0.60，挡住下面小屏的上沿）
  -- 贴着仪表板面摆（显示器和面板同一个斜度，往外凸 m 米；原来朝着眼睛摆，往下挪了以后上半截埋进面板里）
  local PN, PU = V(0, 0.319, 0.948), V(0, 0.948, -0.319)   -- 面板法线（朝人）、面板的上
  local function flush(x, y, m)
    local p = V(x, y, -0.7416 - (y + 0.4504) * 0.3365) + PN * (m or 0.012)
    return CFrame.lookAt(p, p + PN, PU)
  end
  -- 上控制台（平显下面往人这边凸出来的一块，参考图里控制板、小圆表、备份姿态都装在它上面）：cons(x, y) 是它面上的一点（x 人看来往右）
  local CONSW = ({ j20 = 0.56, j16 = 0.56, j15t = 0.42, f22 = 0.56, pano = 0.56, a10 = 0.20 })[disp]
  local CONS = CONSW and CFrame.lookAt(V(0, -0.30, -0.7575), eye)
  if CONS then b:box(H, V(CONSW, 0.12, 0.085), CONS, PIT) end
  local function cons(x, y) return CONS * CF(-x, (y + 0.30) / 0.929, -0.0435) end
  bx(0.78, 0.30, 0.04, 0, -0.74, -0.95, PIT2, nil, 30, 0, 0)                   -- 膝下的面板（伸向脚蹬）
  -- 主告警、注意灯（遮光罩上，挨打 / 失速时闪）
  b:led(H, CF(-0.30, -0.17, -0.72), RGB(255, 40, 30), 0.022, "mwarn")
  b:led(H, CF(0.30, -0.17, -0.72), RGB(255, 180, 30), 0.022, "mcaut")
  b:placard(H, 0.07, 0.016, look(V(-0.30, -0.205, -0.697)), cn and "主告警" or "MASTER WARN", { bg = C.black, fg = RGB(255, 80, 70) })
  b:placard(H, 0.07, 0.016, look(V(0.30, -0.205, -0.697)), cn and "主注意" or "MASTER CAUT", { bg = C.black, fg = RGB(255, 190, 60) })
  -- 显示器
  local K = cn and { top = { "姿态", "雷达", "态势", "武器", "发动机" }, bottom = { "油量", "检查", "目标", "通信", "菜单" } }
    or { top = { "PFD", "RDR", "SA", "SMS", "ENG" }, bottom = { "FUEL", "CHK", "TGT", "COM", "MENU" } }
  -- 按机型照资料和参考图摆（docs/cockpit_research.md）；standby = 主显示器下面一排三个小圆表（备份姿态、空速、高度），有独立备份显示器的机型不要
  local standby = true
  -- 一排带字的键（平显下面的综合控制面板 ICP、正前方控制器 UFC）：rows = { { "COM1", … }, … }
  local function keypad(cf, w, rows)
    local base = b:box(H, V(w, 0.016 + #rows * 0.019, 0.03), cf * CF(0, 0, 0.016), RGB(30, 32, 34), MAT.Metal)
    base.CastShadow = false
    for r, row in ipairs(rows) do
      local n = #row
      for i, t in ipairs(row) do
        local kx = w / 2 - (i - 0.5) * w / n   -- 同屏幕边的键：第一个在人看来最左边
        b:placard(H, w / n * 0.82, 0.015, cf * CF(kx, (#rows + 1) / 2 * 0.019 - r * 0.019, -0.002), t, { bg = RGB(52, 55, 58), fg = RGB(225, 228, 222) })
      end
    end
  end
  local KC, KF = RGB(52, 55, 58), RGB(225, 228, 222)
  -- 正前方控制板（UFC / ICP）：底座 + 一块小液晶 + 四周的键；o = { sw, sh 小屏宽高, sy 小屏中心比底座中心高多少, page,
  --   top 上排键, left / right 两侧的键（人看来的左右）, cols 每侧几列, pad 小屏下面几排数字键, knobs 最下面几个旋钮 }
  local function ufcBox(cf, w, h, o)
    local base = b:box(H, V(w, h, 0.035), cf * CF(0, 0, 0.0175), RGB(30, 32, 34), MAT.SmoothPlastic)
    base.CastShadow = false
    local sw, sh, sy = o.sw, o.sh, o.sy or 0
    b:screen(H, sw, sh, cf * CF(0, sy, -0.0015), o.page or "ufcc", { lightK = 0.18, bezel = 0.004, depth = 0.004, ppm = 1800 })
    local function key(x, y, kw, kh, t) b:placard(H, kw, kh, cf * CF(x, y, -0.002), t, { bg = KC, fg = KF }) end
    local top = o.top or {}
    for i, t in ipairs(top) do key(sw / 2 - (i - 0.5) * sw / #top, sy + sh / 2 + 0.012, sw / #top * 0.8, 0.013, t) end
    local cols = o.cols or 1
    for _, side in ipairs({ 1, -1 }) do   -- 局部 +X 是人看来的左边
      local list = (side == 1) and (o.left or {}) or (o.right or {})
      local per = math.max(1, math.ceil(#list / cols))
      for i, t in ipairs(list) do
        local col, row = math.floor((i - 1) / per), (i - 1) % per
        key(side * (sw / 2 + 0.013 + col * 0.021), sy + sh / 2 - (row + 0.5) * sh / per, 0.017, math.min(0.012, sh / per * 0.82), t)
      end
    end
    for r, row in ipairs(o.pad or {}) do
      for i, t in ipairs(row) do key(sw / 2 - (i - 0.5) * sw / #row, sy - sh / 2 - 0.012 - (r - 1) * 0.016, sw / #row * 0.78, 0.013, t) end
    end
    local nk = o.knobs or 0
    for i = 1, nk do b:knob(H, cf * CF(w / 2 - (i - 0.5) * w / nk, -h / 2 + 0.013, 0), 0.015) end
  end
  if disp == "j20" then
    -- 歼-20（用户 11-21 给的真机座舱照片 + 资料：24 × 9 英寸触摸大屏、广角全息平显）：底下横贯一整块大屏，黑框很厚、上下一排螺钉
    --   （左窗上面一排小表 + 圆形雷达 + 目标表，中间飞机俯视挂弹，右半地图）；平显下面正中一块触摸屏控制板（蓝紫底 4 × 4 触摸键，
    --   装在厚黑框里，框两边几个小键）；控制板右边一块方形小屏（下面一排 4 个键），左边一块小开关板（大旋钮、小旋钮、方按钮、拨动开关）
    local KT = { top = { "态势", "雷达", "武器", "发动机", "油量" }, bottom = { "姿态", "通信", "导航", "检查", "菜单" } }
    local mcf = flush(0, -0.525)
    b:screen(H, 0.61, 0.23, mcf, "j20_main", { keys = KT, touch = true, touchH = 0.07, bezel = 0.024, frame = RGB(18, 18, 20), lightK = 0.5, lightColor = RGB(140, 180, 220) })
    for i = 0, 7 do
      for _, sy in ipairs({ -1, 1 }) do b:cylZ(H, 0.006, 0.009, mcf * CF(-0.29 + i * 0.58 / 7, sy * 0.127, -0.003), RGB(70, 72, 74), MAT.Metal) end
    end
    local ucf = cons(0, -0.305)   -- 控制板：厚黑框 + 触摸屏 + 框两边各三个小键（局部 +X 是人看来的左边）
    b:box(H, V(0.19, 0.135, 0.03), ucf * CF(0, 0, -0.015), RGB(20, 20, 22), MAT.SmoothPlastic)
    b:screen(H, 0.16, 0.105, ucf * CF(0, 0, -0.031), "ufct", { lightK = 0.25, bezel = 0.002, depth = 0.002, ppm = 1800, lightColor = RGB(150, 140, 230) })
    for _, sx in ipairs({ -1, 1 }) do
      for i = 0, 2 do b:button(H, ucf * CF(sx * 0.0875, 0.03 - i * 0.03, -0.031), RGB(44, 46, 48), 0.009) end
    end
    b:box(H, V(0.085, 0.10, 0.02), cons(0.175, -0.30) * CF(0, 0, -0.01), RGB(20, 20, 22), MAT.SmoothPlastic)   -- 右边方形小屏 + 4 个键
    b:screen(H, 0.062, 0.062, cons(0.175, -0.29) * CF(0, 0, -0.021), "sfd", { lightK = 0.2, ppm = 2200, bezel = 0.003, depth = 0.003 })
    for i = 0, 3 do b:button(H, cons(0.175 + (i - 1.5) * 0.017, -0.337) * CF(0, 0, -0.021), RGB(44, 46, 48), 0.011) end
    local lcf = cons(-0.18, -0.30)   -- 左边小开关板
    b:box(H, V(0.13, 0.075, 0.015), lcf * CF(0, 0, -0.0075), RGB(26, 27, 29), MAT.SmoothPlastic)
    b:knob(H, lcf * CF(0.04, -0.008, -0.015), 0.034)
    b:knob(H, lcf * CF(0.005, -0.008, -0.015), 0.018)
    b:button(H, lcf * CF(-0.025, -0.008, -0.015), RGB(40, 42, 44), 0.02)
    b:toggle(H, lcf * CF(-0.05, -0.008, -0.015))
    standby = false
  elseif disp == "f35" then
    -- F-35（用户 11-21 给的真机照片 + 资料：20 × 8 英寸全景屏，两块 10 × 8 英寸拼成，触摸，没有边框键；没有平显）：全景屏在仪表板最上面，
    --   两边斜的外壳；备份飞行显示器在大屏下面正中的竖立台上（台上还有一排小开关、旋钮、一块 3 × 3 按钮）；大屏正上方三个圆灯；右边黄黑条纹应急手柄
    b:screen(H, 0.254, 0.203, flush(-0.128, -0.44), "f35l", { keys = { top = { "TSD", "RDR", "FLT", "DAS", "TFLIR" } }, touch = true, touchH = 0.09, bezel = 0.006, lightK = 0.4, lightColor = RGB(140, 180, 220) })
    b:screen(H, 0.254, 0.203, flush(0.128, -0.44), "f35r", { keys = { top = { "FUEL", "ENG", "SMS", "CNI", "ICAWS" } }, touch = true, touchH = 0.09, bezel = 0.006, lightK = 0.4, lightColor = RGB(140, 180, 220) })
    for _, s in ipairs({ -1, 1 }) do
      b:box(H, V(0.045, 0.21, 0.05), flush(s * 0.283, -0.44, 0.02) * ANG(0, rad(-s * 28), 0), RGB(36, 38, 40), MAT.SmoothPlastic)
    end
    b:box(H, V(0.13, 0.28, 0.08), flush(0, -0.69, 0.045), RGB(52, 56, 60), MAT.SmoothPlastic)   -- 竖立台（贴着面板下半截往人这边凸）
    b:panel(H, 0.12, 0.035, flush(0, -0.575, 0.087), 1, 6, RGB(40, 43, 46), { depth = 0.02, kinds = { "t" } })
    b:panel(H, 0.045, 0.06, flush(-0.036, -0.635, 0.087), 2, 1, RGB(40, 43, 46), { depth = 0.02, kinds = { "k", "l" } })
    b:screen(H, 0.058, 0.058, flush(0.03, -0.635, 0.09), "sfd", { lightK = 0.2, ppm = 2400, bezel = 0.006, depth = 0.02 })
    b:panel(H, 0.10, 0.075, flush(0, -0.725, 0.087), 3, 3, RGB(40, 43, 46), { depth = 0.02, kinds = { "b" }, labels = false })
    b:box(H, V(0.09, 0.028, 0.03), flush(0, -0.315, 0.015), RGB(30, 32, 34), MAT.SmoothPlastic)   -- 大屏正上方三个圆灯
    for i = -1, 1 do b:led(H, flush(i * 0.026, -0.315, 0.032), RGB(235, 235, 225), 0.016) end
    for i = 0, 5 do b:box(H, V(0.03, 0.012, 0.03), flush(0.36, -0.40 - i * 0.012, 0.015), (i % 2 == 0) and C.yellow or C.black, MAT.SmoothPlastic) end
    standby = false
  elseif disp == "f22" then
    -- F-22（用户 11-21 给的真机照片 + 资料）：平显下 ICP（上排功能键、左边数字键、右边一列摇臂开关），两边上前显示器（左告警文字、
    --   右边就是备份飞行显示，所以没有单独的机械备份表）；下面一排三块：中间 8 × 8 英寸主显示器、两边 6.25 英寸副显示器一样高；膝间第四块
    local K1 = { top = { "TSD", "RDR", "SMS", "ENG", "CHK" }, bottom = { "RNG", "FLT", "FUEL", "COM", "MENU" } }
    b:screen(H, 0.203, 0.203, flush(0, -0.52), "f22_tsd", { keys = K1, lightK = 0.4 })
    b:screen(H, 0.159, 0.159, flush(-0.265, -0.50, 0.016), "f22_sms", { keys = K, lightK = 0.3 })   -- 左
    b:screen(H, 0.159, 0.159, flush(0.265, -0.50, 0.016), "f22_eng", { keys = K, lightK = 0.3 })    -- 右
    b:box(H, V(0.24, 0.30, 0.09), flush(0, -0.80, 0.05), RGB(40, 42, 44), MAT.SmoothPlastic)              -- 两膝之间的竖立台
    b:screen(H, 0.159, 0.159, flush(0, -0.775, 0.097), "mfd_pfd", { keys = K, lightK = 0.25 })
    b:screen(H, 0.085, 0.07, cons(-0.165, -0.30), "icaws", { lightK = 0.2 })
    b:screen(H, 0.085, 0.07, cons(0.165, -0.30), "sfd", { lightK = 0.2, ppm = 2200 })
    -- ICP（真机照片：没有屏幕）：上排 5 个功能键，左边 4 × 3 数字键，右边一列 5 个摇臂开关（局部 +X 是人看来的左边）
    local ic = cons(0, -0.30)
    local ib = b:box(H, V(0.16, 0.12, 0.035), ic * CF(0, 0, 0.0175), RGB(30, 32, 34), MAT.SmoothPlastic)
    ib.CastShadow = false
    for i, t in ipairs({ "COM1", "COM2", "NAV", "STPT", "IFF" }) do b:placard(H, 0.027, 0.013, ic * CF(0.064 - (i - 1) * 0.032, 0.05, -0.002), t, { bg = KC, fg = KF }) end
    for r, row in ipairs({ { "1", "2", "3" }, { "4", "5", "6" }, { "7", "8", "9" }, { "ENT", "0", "CLR" } }) do
      for i, t in ipairs(row) do b:placard(H, 0.024, 0.017, ic * CF(0.068 - (i - 1) * 0.028, 0.026 - (r - 1) * 0.022, -0.002), t, { bg = KC, fg = KF }) end
    end
    for r = 0, 4 do b:box(H, V(0.05, 0.010, 0.012), ic * CF(-0.045, 0.03 - r * 0.018, -0.006), RGB(60, 62, 64), MAT.SmoothPlastic) end
    standby = false
  elseif disp == "j16" then
    -- 歼-16（用户 11-21 给的「J-16 座舱环视」第一人称参考图；资料：下方几块多功能显示器换成了一整块大屏）：横贯一整块大屏
    --   （飞行 / 雷达 / 态势 / 告警四个窗口，上下各一条触摸菜单）；平显下面一块方的控制屏；左上开关板、右上备份姿态；
    --   大屏右边一块圆的告警屏和一块航向表，左边一竖条告警灯
    b:screen(H, 0.50, 0.215, flush(0, -0.51), "j16_main", { keys = K, touch = true, touchH = 0.085, bezel = 0.014, lightK = 0.45, lightColor = RGB(140, 180, 220) })
    ufcBox(cons(0, -0.30), 0.19, 0.13, { sw = 0.155, sh = 0.11, sy = 0, page = "ufc" })
    b:panel(H, 0.14, 0.08, cons(-0.19, -0.30), 2, 4, RGB(40, 43, 46), { depth = 0.03 })
    b:screen(H, 0.065, 0.065, cons(0.18, -0.30), "sfd", { lightK = 0.2, ppm = 2200, bezel = 0.008 })
    b:screen(H, 0.065, 0.065, flush(0.325, -0.43), "rwr", { lightK = 0.15, ppm = 2200, bezel = 0.01 })
    b:screen(H, 0.07, 0.07, flush(0.325, -0.55), "hsi", { light = false, ppm = 2200, bezel = 0.01 })
    b:box(H, V(0.05, 0.17, 0.03), flush(-0.315, -0.50, 0.015), RGB(30, 32, 34), MAT.SmoothPlastic)   -- 告警灯竖条
    for i = 0, 5 do
      for j = 0, 1 do
        b:led(H, flush(-0.315 + (j - 0.5) * 0.02, -0.43 - i * 0.027, 0.033), (i < 2) and RGB(255, 70, 50) or RGB(255, 190, 60), 0.013)
      end
    end
    standby = false
  elseif disp == "j15t" then
    -- 歼-15T（用户 11-21 给的第一人称参考图；查到的资料说换了整块大屏，用户给的图是三块屏，照图做）：三块带边框键的多功能显示器
    --   （左飞行、中雷达、右发动机）；平显下正前方控制板（液晶、两侧各两列键、上排键、5 个旋钮），左右各一个小圆表；
    --   三块屏下面一排机械备份表；左边竖条开关板（红保险盖），右边告警灯格栅
    b:screen(H, 0.13, 0.13, flush(-0.21, -0.50), "mfd_pfd", { keys = K, lightK = 0.3 })
    b:screen(H, 0.13, 0.13, flush(0, -0.50), "mfd_rdr", { keys = K, lightK = 0.3 })
    b:screen(H, 0.13, 0.13, flush(0.21, -0.50), "mfd_eng", { keys = K, lightK = 0.3 })
    ufcBox(cons(0, -0.30), 0.20, 0.13, { sw = 0.10, sh = 0.055, sy = 0.012, cols = 2,
      top = { "通1", "通2", "导航", "敌我", "高度", "自驾" }, left = { "1", "2", "3", "4", "5", "6" }, right = { "7", "8", "9", "0", "清", "输" }, knobs = 5 })
    b:screen(H, 0.05, 0.05, cons(-0.16, -0.30), "adi", { light = false, ppm = 2400, bezel = 0.008 })
    b:screen(H, 0.05, 0.05, cons(0.16, -0.30), "gmeter", { light = false, ppm = 2400, bezel = 0.008 })
    b:panel(H, 0.06, 0.16, flush(-0.36, -0.58), 4, 2, RGB(40, 43, 46), { depth = 0.03, guard = true })
    b:box(H, V(0.06, 0.16, 0.03), flush(0.36, -0.50, 0.015), RGB(30, 32, 34), MAT.SmoothPlastic)   -- 右边告警灯格栅
    for i = 0, 7 do b:box(H, V(0.05, 0.006, 0.004), flush(0.36, -0.43 - i * 0.02, 0.032), RGB(70, 72, 70), MAT.SmoothPlastic) end
    standby = { flush(0.10, -0.635), flush(0.17, -0.635), flush(0.24, -0.635) }
  elseif disp == "a10" then   -- A-10C：两块 4.9 英寸 MFCD（左 TAD、右外挂）、中间一列机械表、右下发动机表、平显下 UFC、右侧 CDU
    local KA = { top = { "TAD", "TGP", "DSMS", "MSG", "STAT" }, bottom = { "CDU", "HUD", "SYS", "LOAD", "MENU" } }
    b:screen(H, 0.124, 0.124, flush(-0.245, -0.47), "mfd_tad", { keys = KA, lightK = 0.3 })
    b:screen(H, 0.124, 0.124, flush(0.245, -0.47), "mfd_dsms", { keys = KA, lightK = 0.3 })
    b:screen(H, 0.085, 0.085, flush(0, -0.425), "adi", { light = false, ppm = 2200 })
    b:screen(H, 0.085, 0.085, flush(0, -0.55), "hsi", { light = false, ppm = 2200 })
    b:screen(H, 0.045, 0.045, flush(-0.105, -0.41), "asi", { light = false, ppm = 2200 })
    b:screen(H, 0.045, 0.045, flush(0.105, -0.41), "alt", { light = false, ppm = 2200 })
    b:screen(H, 0.045, 0.045, flush(0.105, -0.52), "vvi", { light = false, ppm = 2200 })
    b:screen(H, 0.18, 0.09, flush(0.20, -0.635), "gauges", { lightK = 0.15, light = false })
    b:screen(H, 0.09, 0.075, look(V(0.32, -0.52, -0.56)), "cdu", { lightK = 0.15 })
    keypad(cons(0, -0.30), 0.16, { { "1", "2", "3", "FUNC", "HACK" }, { "4", "5", "6", "LTR", "MK" }, { "7", "8", "9", "0", "ENT" } })
    standby = false
  else   -- pano（歼-35、歼-50）：整块触摸大屏（资料只到「大横屏」），两边上前显示器照旧
    b:screen(H, 0.50, 0.21, flush(0, -0.505), "pano", { keys = K, touch = true, touchH = 0.09, lightK = 0.45, lightColor = RGB(140, 180, 220) })
    b:screen(H, 0.10, 0.07, cons(-0.17, -0.30), "ufd", { lightK = 0.2 })
    b:screen(H, 0.10, 0.07, cons(0.17, -0.30), "ufd2", { lightK = 0.2 })
  end
  -- 备份仪表（姿态、高度、空速）：主显示器下面一排小圆表
  if standby then
    local sp = (type(standby) == "table") and standby or { flush(-0.08, -0.635), flush(0.0, -0.635), flush(0.08, -0.635) }
    b:screen(H, 0.065, 0.065, sp[1], "adi", { light = false, ppm = 2200 })
    b:screen(H, 0.055, 0.055, sp[2], "asi", { light = false, ppm = 2200 })
    b:screen(H, 0.055, 0.055, sp[3], "alt", { light = false, ppm = 2200 })
  end
  -- 平显：投影仪 + 组合玻璃（符号按眼睛的位置算，真像在无穷远：Interior 的 hud 页）；歼-20 是广角平显，组合玻璃宽一些
  if L.hud ~= false then
    local hw, hh = L.hudW or 0.17, L.hudH or 0.14
    local HC = RGB(30, 32, 34)
    local gy = -0.125 + hh / 2   -- 组合玻璃中心（下沿贴着投影仪上面）
    -- 平显原模型（用户 11-22：「把飞机驾驶舱的光学瞄准屏直接搬来用」「j15t 原模型自带内饰」）：歼-15T 原模型自带座舱里的那套——
    --   黑色弧形框、上下两层组合玻璃、底座（tools/weapons/hud.mjs 抠出来，models/optics/hud15.glb）。L.hudModel 的机型导入了就换上，
    --   按组合玻璃的宽高对上符号那块屏（符号屏照旧正对着人、在玻璃中间：符号不变形）；底座沉进仪表板太多就整个往上挪一点
    local hm = L.hudModel and HUDM and HUDM[L.hudModel]
    local hf = hm and Kit.imported(L.hudModel)
    if hm and hf then
      local k = math.clamp(math.max(hw * 1.1 / hm.glass.w, hh * 1.05 / hm.glass.h), 0.7, 1.2)
      local fr = hm.parts.Frame
      local low = gy + (fr.c[2] - fr.s[2] / 2) * k
      if low < -0.23 then gy += -0.23 - low end
      local hcf = CF(0, gy, -0.66)
      for name, p in pairs(hm.parts) do
        local src = hf:FindFirstChild("O_" .. L.hudModel .. "__" .. name)
        if src and src:IsA("BasePart") then
          local mp = b:mesh(H, src, V(p.s[1], p.s[2], p.s[3]) * k, hcf * CF(V(p.c[1], p.c[2], p.c[3]) * k))
          if name == "Glass" then   -- 组合玻璃：几乎透明、一点绿（原模型的玻璃是半透明的黑，在 Roblox 里太暗）
            mp.CastShadow = false
            mp.Transparency = 0.9
            mp.Color = RGB(150, 205, 165)
          end
          b.hudModel = (b.hudModel or 0) + 1
        end
      end
    end
    if b.hudModel then
      -- 原模型：零件拼的投影仪、框不要
    else
    if UFCW then bx(hw + 0.03, 0.08, 0.16, 0, -0.165, -0.70, HC, MAT.Metal)
    else bx(hw + 0.03, 0.08, 0.22, 0, -0.165, -0.66, HC, MAT.Metal) end
    if L.hudFrame == "box" then   -- 歼-15T 参考图：一圈厚圆角黑框，左边一个小摄像盒
      local t = 0.022
      for _, sx in ipairs({ -1, 1 }) do bx(t, hh + t, 0.03, sx * (hw / 2 + t / 2), gy + t / 2, -0.665, HC, MAT.SmoothPlastic) end
      bx(hw + t * 2, t, 0.03, 0, gy + hh / 2 + t / 2, -0.665, HC, MAT.SmoothPlastic)
      for _, sx in ipairs({ -1, 1 }) do bx(0.03, 0.03, 0.03, sx * (hw / 2 - 0.004), gy + hh / 2 - 0.004, -0.665, HC, MAT.SmoothPlastic, 0, 0, 45) end   -- 圆角
      bx(0.022, 0.07, 0.03, -(hw / 2 + 0.04), gy - 0.01, -0.665, RGB(26, 26, 28), MAT.SmoothPlastic)
    elseif L.hudFrame == "wide" then   -- 歼-20 真机照片：广角平显，两根粗立柱往外斜，上面没有顶梁
      for _, sx in ipairs({ -1, 1 }) do bx(0.022, hh + 0.05, 0.02, sx * (hw / 2 + 0.014), gy + 0.012, -0.672, HC, MAT.SmoothPlastic, 0, 0, -sx * 10) end
    elseif L.hudFrame == "tall" then   -- 歼-16 参考图，F-22 真机：两根立柱 + 顶梁
      for _, sx in ipairs({ -1, 1 }) do bx(0.014, hh + 0.03, 0.014, sx * (hw / 2 + 0.006), gy + 0.008, -0.67, HC, MAT.Metal) end
      bx(hw + 0.026, 0.012, 0.014, 0, gy + hh / 2 + 0.018, -0.67, HC, MAT.Metal)
    else
      for _, sx in ipairs({ -1, 1 }) do bx(0.012, 0.15, 0.012, sx * (hw / 2), -0.07, -0.67, HC, MAT.Metal) end
    end
    end
    local hs = b:screen(H, hw, hh, CFrame.lookAt(V(0, gy, -0.66), V(0, gy + 0.025, 0.2)), "hud", { light = false, glow = 2.2, ppm = 3000, bezel = 0.004, depth = 0.004, noBack = true })
    hs.part.Material = MAT.Glass   -- 组合玻璃：真透明、带一点绿（原来后面垫着一块不透明黑底板）
    hs.part.Transparency = 0.93   -- 参考图：组合玻璃几乎看不见，只看得见框、一点反光和绿色符号
    hs.part.Reflectance = 0.06
    hs.part.Color = RGB(150, 205, 165)
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
  --   F-22 两边副显示器占满了仪表板左边，手柄挪到左边那块的左上角外面
  local gp = (disp == "f22") and V(-0.39, -0.40, -0.745) or V(-0.37, -0.43, -0.735)
  b:group("gearh", H, CF(gp))
  b:box("gearh", V(0.015, 0.10, 0.015), CF(0, 0.05, 0), C.lgray, MAT.Metal)
  b:cyl("gearh", 0.025, 0.05, CF(0, 0.11, 0), C.white)
  for i = -1, 1 do b:led(H, CF(gp + V(0.04 + i * 0.022, 0.09, -0.005)), RGB(80, 255, 110), 0.012, "gear") end
  b:placard(H, 0.06, 0.016, look(gp + V(0, 0.11, 0)), cn and "起落架" or "LDG GEAR", { bg = C.black, fg = C.white })
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
  -- 座舱盖玻璃（有划痕；Interior 迎着日月光加眩光）。用户 11-21：原来八条平板拼的，看着是多边形；进游戏像塑料——
  --   改成截面半圆的管子（一圈 24 条窄条）+ 往前收成弹头形的风挡曲面（5 圈），看不出棱；
  --   Roblox 画质低时玻璃材质没有折射、按塑料受光，原来的浅灰蓝受光后发白发灰像塑料膜：颜色压暗、更透、加一点反光；
  --   隐身机的座舱盖镀了一层金（goldGlass），从里面看微微发暖
  local glass, panes = {}, {}
  local R0, cy0 = 0.52, -0.24
  local zf, zr, Lf = -0.80, 0.57, 0.30
  local GC = L.goldGlass and RGB(72, 62, 44) or RGB(54, 62, 68)
  local function pane(cf, w, l)
    local g = b:box(H, V(w, 0.006, l), cf, GC, MAT.Glass)
    g.Transparency, g.Reflectance, g.CastShadow = 0.9, 0.12, false
    table.insert(panes, g)
    return g
  end
  local NG = 24
  for i = 0, NG - 1 do   -- 管子：从左舱沿翻过头顶到右舱沿
    local a0, a1 = rad(-90 + i * 180 / NG), rad(-90 + (i + 1) * 180 / NG)
    local am = (a0 + a1) / 2
    local rc = R0 * math.cos((a1 - a0) / 2)
    local g = pane(CF(math.sin(am) * rc, cy0 + math.cos(am) * rc, (zf + zr) / 2) * ANG(0, 0, -am), 2 * R0 * math.sin((a1 - a0) / 2), zr - zf)   -- 正好拼上不重叠（重叠的地方透明度叠两层，看着是一道道细线）
    if (i - NG / 2) % 3 == 0 then table.insert(glass, 1 + ((i == NG / 2) and 0 or #glass), g) end   -- 带划痕的几条（正上方那条排第一）
  end
  -- 风挡：管子前端往前收成弹头形（t = 0 管口，1 尖）；每圈每条一块，四个角取在曲面上
  local function ring(t) return zf - Lf * math.sin(t * PI / 2), R0 * math.cos(t * PI / 2) ^ 0.6 end
  local function onRing(a, z, r) return V(math.sin(a) * r, cy0 + math.cos(a) * r, z) end
  local MG = 5
  for k = 0, MG - 1 do
    local z0, r0 = ring(k / MG)
    local z1, r1 = ring((k + 1) / MG)
    for i = 0, NG - 1 do
      local a0, a1 = rad(-90 + i * 180 / NG), rad(-90 + (i + 1) * 180 / NG)
      local A, B, C2, D = onRing(a0, z0, r0), onRing(a1, z0, r0), onRing(a0, z1, r1), onRing(a1, z1, r1)
      local xv = ((B - A) + (D - C2)) / 2
      local mv = (C2 + D) / 2 - (A + B) / 2
      local X = xv.Unit
      local Z = (mv - X * mv:Dot(X)).Unit
      local Y = Z:Cross(X)
      local w = math.max((B - A).Magnitude, (D - C2).Magnitude)
      local g = pane(CFrame.fromMatrix((A + B + C2 + D) / 4, X, Y, X:Cross(Y)), w, mv.Magnitude)
      if k == 1 and math.abs(i - NG / 2 + 0.5) < 3 then table.insert(glass, g) end   -- 正前方几块也带划痕（迎着太阳看得见）
    end
  end
  b:name("glass", glass)
  if L.hoop then
    local R1, cyh, th, z = 0.50, -0.24, L.hoop.th or 0.05, L.hoop.z or -0.80
    local n = 16
    for i = 0, n - 1 do
      local a0, a1 = rad(-96 + i * 192 / n), rad(-96 + (i + 1) * 192 / n)
      local am = (a0 + a1) / 2
      local len = 2 * R1 * math.sin((a1 - a0) / 2) * 1.08
      bx(len, th, 0.045, math.sin(am) * R1, cyh + math.cos(am) * R1, z, RGB(32, 34, 36), MAT.SmoothPlastic, 0, 0, -math.deg(am))
    end
    for _, ad in ipairs(L.hoop.mirrors or {}) do   -- 后视镜：挂在拱框里沿，镜面朝着人
      local a = rad(ad)
      local r = R1 - th / 2 - 0.03
      local pm = V(math.sin(a) * r, cyh + math.cos(a) * r, z + 0.03)
      b:tube(H, V(math.sin(a) * (R1 - th / 2), cyh + math.cos(a) * (R1 - th / 2), z), pm, 0.01, RGB(40, 42, 44), MAT.Metal)
      local m = b:box(H, V(0.11, 0.042, 0.008), CFrame.lookAt(pm, eye) * ANG(0, 0, a), RGB(200, 210, 215), MAT.Glass)
      m.Reflectance, m.CastShadow = 0.6, false
    end
    for _, sx in ipairs(L.hoop.struts and { -1, 1 } or {}) do   -- 两根斜撑：遮光罩两角斜着连到拱框
      local a = rad(sx * 44)
      b:tube(H, V(sx * 0.13, -0.18, -0.72), V(math.sin(a) * (R1 - th / 2), cyh + math.cos(a) * (R1 - th / 2), z), 0.016, RGB(36, 38, 40), MAT.Metal)
    end
    if L.hoop.compass then   -- 备用磁罗盘：吊在拱框右上
      local a = rad(36)
      local pc = V(math.sin(a) * (R1 - th / 2 - 0.06), cyh + math.cos(a) * (R1 - th / 2 - 0.06), z + 0.03)
      b:tube(H, V(math.sin(a) * (R1 - th / 2), cyh + math.cos(a) * (R1 - th / 2), z), pc, 0.012, RGB(40, 42, 44), MAT.Metal)
      b:cylZ(H, 0.04, 0.056, CF(pc + V(0, -0.035, 0)), RGB(34, 36, 38), MAT.SmoothPlastic)
      local face = b:cylZ(H, 0.004, 0.044, CF(pc + V(0, -0.035, 0.021)), RGB(225, 222, 200), MAT.SmoothPlastic)
      face.CastShadow = false
    end
  end
  if L.frame and not L.hoop then   -- 风挡框、后视镜
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
  return { air = true, stations = stations, order = order, crew = crew, cn = cn, glass = glass, minScreens = L.minScreens, noRadar = L.noRadar }
end

-- 各型照 docs/cockpit_research.md：minScreens 这一型真有几块屏（测试按它查）、noRadar 没有雷达（A-10C）
Defs.j20 = function(b, ctx) return Defs.jet(b, ctx, { hudModel = "hud15", disp = "j20", hud = true, hudW = 0.21, hudH = 0.16, hudFrame = "wide", stick = "center", cn = true, goldGlass = true, minScreens = 4,
  hoop = { z = -0.80, th = 0.05, mirrors = { 0, -52, 52 }, struts = true } }) end
Defs.j35 = function(b, ctx) return Defs.jet(b, ctx, { hudModel = "hud15", disp = "pano", hud = true, stick = "side", cn = true, goldGlass = true }) end
Defs.j50 = function(b, ctx) return Defs.jet(b, ctx, { hudModel = "hud15", disp = "pano", hud = true, stick = "side", cn = true, goldGlass = true }) end
Defs.j16 = function(b, ctx) return Defs.jet(b, ctx, { hudModel = "hud15", disp = "j16", hud = true, hudW = 0.16, hudH = 0.17, hudFrame = "tall", stick = "center", seats = 2, frame = true, cn = true }) end
Defs.j15t = function(b, ctx) return Defs.jet(b, ctx, { hudModel = "hud15", disp = "j15t", hud = true, hudW = 0.16, hudH = 0.15, hudFrame = "box", stick = "center", frame = true, cn = true,
  hoop = { z = -0.78, th = 0.075, compass = true } }) end
Defs.f35 = function(b, ctx) return Defs.jet(b, ctx, { disp = "f35", hud = false, stick = "side", minScreens = 3, goldGlass = true }) end
Defs.f22 = function(b, ctx) return Defs.jet(b, ctx, { disp = "f22", hud = true, hudW = 0.15, hudH = 0.17, hudFrame = "tall", stick = "side", goldGlass = true }) end
Defs.a10c = function(b, ctx) return Defs.jet(b, ctx, { disp = "a10", hud = true, stick = "center", frame = true, noRadar = true }) end

---------------------------------------------------------------- 直升机、轰炸机座舱共用件
-- 平显（投影仪 + 组合玻璃，符号按眼睛的位置投：Interior 的 hud 页）；p 是组合玻璃中心，at 是眼睛
local function hudUnit(b, g, p, at)
  b:box(g, V(0.18, 0.07, 0.20), CF(p + V(0, -0.11, 0.01)), RGB(30, 32, 34), MAT.Metal)
  for _, sx in ipairs({ -1, 1 }) do b:box(g, V(0.012, 0.13, 0.012), CF(p + V(sx * 0.08, -0.02, -0.005)), RGB(30, 32, 34), MAT.Metal) end
  local hs = b:screen(g, 0.15, 0.12, CFrame.lookAt(p, at + V(0, 0.02, 0)), "hud", { light = false, glow = 2.2, ppm = 3000, bezel = 0.004, depth = 0.004, noBack = true })
  hs.part.Material = MAT.Glass   -- 组合玻璃：真透明（原来后面垫着一块不透明黑底板）
  hs.part.Transparency = 0.93
  hs.part.Reflectance = 0.06
  hs.part.Color = RGB(150, 205, 165)
  hs.root.BackgroundTransparency = 1
  b:name("hud", hs)
  return hs
end
-- 备份仪表（姿态、空速、高度三个小圆表）：c 是中间那个的位置，at 是眼睛
local function standby(b, g, c, at, dx)
  dx = dx or 0.075
  b:screen(g, 0.06, 0.06, CFrame.lookAt(c + V(-dx, 0, 0), at), "adi", { light = false, ppm = 2200 })
  b:screen(g, 0.05, 0.05, CFrame.lookAt(c, at), "asi", { light = false, ppm = 2200 })
  b:screen(g, 0.05, 0.05, CFrame.lookAt(c + V(dx, 0, 0), at), "alt", { light = false, ppm = 2200 })
end
-- 一块平板玻璃（座舱窗）：四个角 a b c d（顺着转一圈），玻璃按长方形近似；加进 glass 表（Interior 贴划痕）
local function pane(b, g, glass, ctr, w, h, rot, trans)
  local p = b:box(g, V(w, h, 0.008), CF(ctr) * rot, RGB(170, 190, 200), MAT.Glass)
  p.Transparency, p.Reflectance, p.CastShadow = trans or 0.9, 0.08, false
  table.insert(glass, p)
  return p
end
-- 窗框条：从 a 到 b 的一根方管
local function bar(b, g, a, c, t, col)
  local len = (c - a).Magnitude
  return b:box(g, V(t, t, len), CFrame.lookAt((a + c) / 2, c), col or RGB(40, 42, 44), MAT.Metal)
end
-- 一个面朝 n 的窗（中心 ctr、宽 w、高 h、up 是窗的「上」方向），带四边框条
local function window(b, g, glass, ctr, n, up, w, h, frame, trans)
  local r = up:Cross(n).Unit
  local u = n:Cross(r).Unit
  local rot = CFrame.fromMatrix(V(), r, u, n)
  pane(b, g, glass, ctr, w, h, rot, trans)
  if frame then
    local t = frame
    local c1, c2 = ctr + r * (w / 2) + u * (h / 2), ctr - r * (w / 2) + u * (h / 2)
    local c3, c4 = ctr - r * (w / 2) - u * (h / 2), ctr + r * (w / 2) - u * (h / 2)
    bar(b, g, c1, c2, t) bar(b, g, c2, c3, t) bar(b, g, c3, c4, t) bar(b, g, c4, c1, t)
  end
end
-- 一块雨刷（风挡下沿的转轴 + 刷臂 + 刷片）
local function wiper(b, g, base, len, ang, n)
  b:cyl(g, 0.03, 0.03, CF(base) * ANG(0, PI / 2, 0), RGB(30, 30, 30), MAT.Metal)
  local tip = base + (CFrame.Angles(0, 0, rad(ang)) * V(0, len, 0))
  local q = base:Lerp(tip, 0.5)
  b:box(g, V(0.012, len, 0.008), CFrame.lookAt(q, q + n) * ANG(0, 0, rad(-ang)), RGB(30, 30, 30), MAT.Metal)
end
-- 一套手柄类操纵件的组名（左右两座各一套：我这一座不带后缀，另一座带 2）
local function sfx(me) return me and "" or "2" end

---------------------------------------------------------------- 并排双座：通用直升机（黑鹰、直-20、支奴干）、轰炸机（轰-6K、B-2）
-- 原点在「我」的眼位；另一座在 x = 2·cx（cx 是座舱中线）。
--   L = { half 座位中心到中线（米）, me = "R"（美军直升机机长坐右座）/ "L"（轰炸机、我军直升机机长坐左座）, ctrl = "heli"（周期变距杆 + 总距杆）/ "yoke"（驾驶盘）/ "stick"（中央杆）,
--     disp = 显示器布局, hud = 机长前面有平显, cn = 中文, win = "heli"（大风挡 + 门窗 + 顶窗，chin 加下视窗）/ "bomber"（小窗、粗框）, thr = 油门杆数,
--     thrSide = 油门每座一组在各自左手边（B-2）, dress = 着装 }
-- 资料：UH-60M —— 四块 6×8 英寸多功能显示器横排、中间操纵台两台飞行管理计算机键盘、头顶操纵台上两根发动机功率控制杆和两个灭火 T 形手柄、
--   下视窗、雨刷、磁罗盘；CH-47F 通用航电座舱（CAAS）—— 五块多功能显示器；直-20 —— 四块大屏 + 中间一块；轰-6K —— 玻璃化座舱、驾驶盘、平显；
--   B-2 —— 两名机组并排、每人四块彩色多功能显示器、中央杆、四根油门各座一组在左手边、窗小框粗（docs/cockpit_research.md）
function Defs.side(b, ctx, L)
  local H = "hull"
  local hf = L.half or 0.52
  local sg = (L.me == "L") and 1 or -1   -- 中线在我的哪一边
  local cx, ox = sg * hf, 2 * sg * hf    -- 中线、另一座的 x
  local cn = L.cn
  local heli = L.ctrl == "heli"
  local W = 2 * hf + (heli and 0.95 or 1.05)   -- 座舱内宽
  local x0, x1 = cx - W / 2, cx + W / 2
  local FY = heli and -1.12 or -1.10           -- 地板
  local eye = V()
  local function bx(sx, sy, sz, x, y, z, col, mat, rx, ry, rz)
    return b:box(H, V(sx, sy, sz), CF(x, y, z) * ANG(rad(rx or 0), rad(ry or 0), rad(rz or 0)), col, mat)
  end
  local function look(p, at) return CFrame.lookAt(p, at or eye) end
  local glass = {}
  local P1, P2 = heli and RGB(52, 56, 58) or PIT, heli and RGB(40, 43, 45) or PIT2
  -- 地板、下半截侧壁（门的下半）、后隔框
  bx(W, 0.03, 2.2, cx, FY, -0.30, P2, MAT.DiamondPlate)
  for _, x in ipairs({ x0, x1 }) do bx(0.04, 0.62, 1.6, x, FY + 0.31, -0.25, P1) end
  bx(W, 1.5, 0.04, cx, FY + 0.75, 0.62, P2)
  -- 顶棚
  local RY = heli and 0.42 or 0.36
  bx(W, 0.03, 1.2, cx, RY, 0.02, P2)
  -- 主仪表板 + 遮光罩（横贯两座）
  local PZ = heli and -0.80 or -0.78
  b:box(H, V(W - 0.16, 0.46, 0.06), CF(cx, -0.47, PZ) * ANG(rad(-12), 0, 0), P1)
  bx(W - 0.16, 0.05, 0.28, cx, -0.225, PZ + 0.06, GLARE, MAT.Fabric, 4, 0, 0)
  bx(W - 0.30, 0.30, 0.04, cx, -0.80, PZ - 0.10, P2, nil, 35, 0, 0)    -- 膝下面板
  -- 主告警 / 注意灯（遮光罩上两座各一对）、磁罗盘（风挡中间框上）
  for _, x in ipairs({ 0, ox }) do
    b:led(H, CF(x - 0.18, -0.19, PZ + 0.10), RGB(255, 40, 30), 0.022, "mwarn")
    b:led(H, CF(x + 0.18, -0.19, PZ + 0.10), RGB(255, 180, 30), 0.022, "mcaut")
    b:placard(H, 0.07, 0.016, look(V(x - 0.18, -0.205, PZ + 0.115), V(x, 0, 0)), cn and "主告警" or "MASTER WARN", { bg = C.black, fg = RGB(255, 80, 70) })
    b:placard(H, 0.07, 0.016, look(V(x + 0.18, -0.205, PZ + 0.115), V(x, 0, 0)), cn and "主注意" or "MASTER CAUT", { bg = C.black, fg = RGB(255, 190, 60) })
  end
  bx(0.07, 0.06, 0.07, cx, 0.26, PZ - 0.10, RGB(20, 20, 20))
  b:ball(H, 0.05, CF(cx, 0.26, PZ - 0.135), RGB(230, 225, 200), MAT.Glass)
  -- 显示器
  local K = cn and { top = { "姿态", "雷达", "态势", "武器", "发动机" }, bottom = { "油量", "检查", "目标", "通信", "菜单" } }
    or { top = { "PFD", "RDR", "SA", "SMS", "ENG" }, bottom = { "FUEL", "CHK", "TGT", "COM", "MENU" } }
  local function mfd(x, y, w, h, page, keys)
    local p = V(x, y, PZ + 0.035 + (y + 0.47) * math.tan(rad(12)) * -1)
    b:screen(H, w, h, CFrame.lookAt(p, V(cx, 0, 0.3)) , page, { keys = keys and K or nil, lightK = 0.3 })
  end
  local disp = L.disp
  if disp == "uh60m" then   -- 四块竖着的 6×8 英寸：我 PFD / ND，另一座 ND / PFD
    for i, page in ipairs({ "mfd_pfd", "mfd_sa", "mfd_sa", "mfd_pfd" }) do
      local x = cx + sg * (-0.60 + (i - 1) * 0.40) * -1
      mfd(x, -0.47, 0.15, 0.20, page, true)
    end
  elseif disp == "ch47f" then   -- 五块：两座各两块 + 中间发动机
    for i, page in ipairs({ "mfd_pfd", "mfd_sa", "mfd_eng", "mfd_sa", "mfd_pfd" }) do
      local x = cx - sg * (-0.68 + (i - 1) * 0.34)
      mfd(x, -0.47, 0.15, 0.20, page, i ~= 3)
    end
  elseif disp == "z20" then   -- 四块横着的大屏 + 中间一块小的
    for i, page in ipairs({ "mfd_pfd", "mfd_sa", "mfd_sa", "mfd_pfd" }) do
      local x = cx - sg * (-0.62 + (i - 1) * 0.36 + ((i > 2) and 0.16 or 0))
      mfd(x, -0.46, 0.20, 0.15, page, true)
    end
    mfd(cx, -0.50, 0.12, 0.10, "mfd_eng", false)
  elseif disp == "h6k" then   -- 六块（人民日报 2016）：每座三块（姿态 / 导航 / 武器），另一座的第三块是发动机
    for _, base in ipairs({ 0, ox }) do
      for j, page in ipairs({ "mfd_pfd", "mfd_sa", (base == 0) and "mfd_sms" or "mfd_eng" }) do
        mfd(base + (j - 2) * 0.17, -0.47, 0.15, 0.15, page, j ~= 3)
      end
    end
  else   -- b2：每人 2×2 四块
    for _, base in ipairs({ 0, ox }) do
      for j, page in ipairs({ "mfd_pfd", "mfd_sa", "mfd_sms", "mfd_eng" }) do
        local col, row = (j - 1) % 2, math.floor((j - 1) / 2)
        mfd(base + (col - 0.5) * 0.18, -0.38 - row * 0.18, 0.15, 0.15, page, row == 0)
      end
    end
  end
  standby(b, H, V(cx, -0.31, PZ + 0.07), eye)
  if L.hud then hudUnit(b, H, V(0, -0.07, PZ + 0.14), eye) end
  -- 中间操纵台（两座之间，从仪表板往后伸）：电台、飞行管理计算机键盘（小屏 + 键）、自动驾驶面板；油门杆（固定翼）
  local CW = heli and 0.30 or 0.36
  b:box(H, V(CW, 0.40, 0.95), CF(cx, FY + 0.20, PZ + 0.42), P1)
  b:box(H, V(CW, 0.04, 0.95), CF(cx, FY + 0.42, PZ + 0.42) * ANG(rad(8), 0, 0), P2)
  for i = 0, 2 do
    b:panel(H, CW - 0.04, 0.18, CFrame.lookAt(V(cx, FY + 0.445, PZ + 0.18 + i * 0.25), V(cx, FY + 1.4, PZ + 0.5 + i * 0.25)), 3, 4, RGB(54, 58, 62))
  end
  for _, s in ipairs({ -1, 1 }) do   -- 两台键盘（中间操纵台前端两边）
    local p = V(cx + s * 0.075, FY + 0.47, PZ + 0.10)
    b:screen(H, 0.10, 0.05, CFrame.lookAt(p, V(cx + s * 0.075, 0, 0.2)), "ufd", { lightK = 0.15 })
  end
  if not heli then   -- 油门杆（跟着油门推）：一般一组在中间操纵台；B-2 每座一组、在各自左手边（thrSide，另一座那组叫 thr2）
    local n = L.thr or 2
    local function quad(g, at, dx)
      b:group(g, H, at)
      for i = 1, n do
        local x = (i - (n + 1) / 2) * dx
        b:box(g, V(0.014, 0.12, 0.014), CF(x, 0.06, 0) * ANG(rad(-20), 0, 0), C.dark, MAT.Metal)
        b:box(g, V(dx * 0.8, 0.03, 0.035), CF(x, 0.12, -0.02), C.black)
      end
    end
    if L.thrSide then
      for _, mine in ipairs({ true, false }) do
        local x = (mine and 0 or ox) - 0.33
        bx(0.16, 0.10, 0.62, x, -0.66, -0.02, P1)                                  -- 左侧台
        bx(0.15, 0.012, 0.24, x, -0.605, -0.04, RGB(20, 20, 20))                   -- 油门槽
        quad(mine and "thr" or "thr2", CF(x, -0.60, -0.02), 0.034)
      end
    else
      quad("thr", CF(cx, FY + 0.47, PZ + 0.62), 0.05)
      bx(0.04 * n + 0.04, 0.012, 0.24, cx, FY + 0.455, PZ + 0.62, RGB(20, 20, 20))
    end
  end
  -- 头顶操纵台：开关面板朝下，直升机两根发动机功率控制杆、两个灭火 T 形手柄
  b:box(H, V(0.42, 0.10, 0.70), CF(cx, RY - 0.06, -0.20), P1)
  for i = 0, 2 do
    b:panel(H, 0.38, 0.20, CFrame.lookAt(V(cx, RY - 0.115, -0.45 + i * 0.22), V(cx, -0.6, -0.30 + i * 0.22)), 3, 4, RGB(54, 58, 62), { guard = i == 0 })
  end
  if heli then
    for _, s in ipairs({ -1, 1 }) do
      b:box(H, V(0.016, 0.10, 0.016), CF(cx + s * 0.05, RY - 0.17, -0.60) * ANG(rad(20), 0, 0), C.lgray, MAT.Metal)
      b:box(H, V(0.05, 0.02, 0.03), CF(cx + s * 0.05, RY - 0.22, -0.62), C.black)
      b:box(H, V(0.06, 0.018, 0.018), CF(cx + s * 0.13, RY - 0.13, -0.66), C.red)   -- 灭火 T 形手柄
      b:box(H, V(0.012, 0.04, 0.012), CF(cx + s * 0.13, RY - 0.10, -0.66), C.red)
    end
  end
  -- 两座：座椅、操纵件、脚蹬
  local dress = L.dress or (heli and (cn and "heli_cn" or "heli_us") or (cn and "pilot_cn" or "pilot_us"))
  local crew, stations, order = {}, {}, {}
  for _, mine in ipairs({ true, false }) do
    local x = mine and 0 or ox
    local q = sfx(mine)
    -- 座椅：直升机是防弹座椅（两侧装甲翼板）、轰炸机是弹射座椅
    b:seat(H, CF(x, -0.80, 0.16), { w = 0.48, d = 0.46, back = 0.72, recline = heli and 12 or 14, head = not heli, col = RGB(64, 66, 58), frame = RGB(44, 46, 48) })
    if heli then
      for _, s in ipairs({ -1, 1 }) do bx(0.03, 0.55, 0.40, x + s * 0.27, -0.52, 0.30, RGB(70, 72, 64), MAT.SmoothPlastic, 12, 0, 0) end
      bx(0.36, 0.20, 0.10, x, 0.02, 0.42, RGB(58, 60, 54), MAT.Fabric, 12, 0, 0)
    else
      bx(0.36, 0.28, 0.16, x, 0.06, 0.38, RGB(54, 58, 54), nil, 14, 0, 0)
      for i = 0, 3 do bx(0.025, 0.025, 0.02, x - 0.04 + i * 0.027, -0.80, -0.10, (i % 2 == 0) and C.yellow or C.black) end
    end
    for _, s in ipairs({ -1, 1 }) do bx(0.03, 0.03, 0.30, x + s * 0.20, -0.25, 0.08, RGB(60, 70, 50), MAT.Fabric, -50, 0, 0) end
    -- 脚蹬
    for _, s in ipairs({ -1, 1 }) do
      local gname = ((s < 0) and "pedL" or "pedR") .. q
      b:group(gname, H, CF(x + s * 0.15, FY + 0.16, -1.02))
      b:box(gname, V(0.10, 0.20, 0.03), CF() * ANG(rad(-20), 0, 0), RGB(40, 42, 44), MAT.Metal)
    end
    local hands
    if heli then
      -- 周期变距杆（两腿之间，从地板伸上来，握把上一排按钮）
      b:group("stick" .. q, H, CF(x, FY + 0.04, -0.36))
      b:tube("stick" .. q, V(0, 0, 0), V(0, 0.50, 0.04), 0.03, C.dark, MAT.Metal)
      b:box("stick" .. q, V(0.05, 0.14, 0.05), CF(0, 0.57, 0.05) * ANG(rad(-8), 0, 0), C.black)
      b:button("stick" .. q, CF(0, 0.645, 0.03) * ANG(rad(-70), 0, 0), C.red, 0.012)
      b:box("stick" .. q, V(0.012, 0.035, 0.012), CF(0, 0.57, 0.02), RGB(60, 60, 60))
      b:cylY(H, 0.06, 0.13, CF(x, FY + 0.03, -0.36), RGB(30, 30, 30), MAT.Fabric)
      -- 总距杆（座椅左边，后端铰链，前端握把上一盒开关；提总距时前端抬起）
      b:group("coll" .. q, H, CF(x - 0.30, -0.80, 0.18))
      b:tube("coll" .. q, V(0, 0, 0), V(0, 0.02, -0.46), 0.035, C.dark, MAT.Metal)
      b:box("coll" .. q, V(0.06, 0.07, 0.12), CF(0, 0.04, -0.50), C.black)
      b:button("coll" .. q, CF(0.0, 0.08, -0.52) * ANG(rad(-90), 0, 0), C.dark, 0.014)
      b:cyl("coll" .. q, 0.10, 0.045, CF(0, 0.02, -0.40) * ANG(0, PI / 2, 0), RGB(30, 30, 30), MAT.Fabric)   -- 油门旋转握把
      hands = { r = { "stick" .. q, V(0, 0.58, 0.05) }, l = { "coll" .. q, V(0, 0.05, -0.48) } }
    elseif L.ctrl == "yoke" then
      -- 驾驶盘：驾驶柱从地板伸上来（推拉俯仰），盘绕柱转（滚转）；羊角形两个握把
      b:group("stick" .. q, H, CF(x, FY + 0.02, -0.58))
      b:tube("stick" .. q, V(0, 0, 0), V(0, 0.56, 0.02), 0.06, C.dark, MAT.Metal)
      b:group("wheel" .. q, "stick" .. q, CF(0, 0.60, 0.03))
      b:box("wheel" .. q, V(0.32, 0.035, 0.04), CF(), C.black)
      for _, s in ipairs({ -1, 1 }) do
        b:box("wheel" .. q, V(0.035, 0.11, 0.04), CF(s * 0.16, 0.04, 0) * ANG(0, 0, rad(s * -12)), C.black)
        b:button("wheel" .. q, CF(s * 0.165, 0.10, -0.02), C.red, 0.01)
      end
      b:box("wheel" .. q, V(0.08, 0.05, 0.03), CF(0, 0, -0.025), RGB(60, 62, 64))
      hands = { r = { "wheel" .. q, V(0.16, 0.06, 0) }, l = { "wheel" .. q, V(-0.16, 0.06, 0) } }
    else
      b:group("stick" .. q, H, CF(x, FY + 0.06, -0.38))
      b:tube("stick" .. q, V(0, 0, 0), V(0, 0.36, -0.04), 0.03, C.dark, MAT.Metal)
      b:box("stick" .. q, V(0.05, 0.13, 0.055), CF(0, 0.42, -0.05) * ANG(rad(-10), 0, 0), C.black)
      b:button("stick" .. q, CF(0, 0.49, -0.08) * ANG(rad(-70), 0, 0), C.red, 0.012)
      hands = { r = { "stick" .. q, V(0, 0.42, -0.05) }, l = { H, V(x - 0.22, -0.55, 0.0) } }
    end
    if not heli and mine then hands.l = { "thr", V(0, 0.12, 0) } end
    if not heli and not mine and L.thrSide then hands.l = { "thr2", V(0, 0.12, 0) } end
    local key = mine and "pilot" or "copilot"
    crew[key] = { dress = dress, g = H, eye = V(x, 0, 0), lean = 2, yaw = 0, look = V(0, -0.05, -1), hands = hands,
      feet = { l = { "pedL" .. q, V(0, -0.04, 0.06) }, r = { "pedR" .. q, V(0, -0.04, 0.06) } } }
    stations[key] = { g = H, eye = V(x, 0, 0), look = V(0, -0.03, -1), yaw = 150, up = 70, down = 65, crew = key }
    table.insert(order, key)
  end
  -- 窗：直升机大风挡（每座一块 + 中柱）、门窗、顶窗、下视窗；轰炸机小风挡 + 侧窗，框粗
  local FR = heli and 0.035 or 0.06
  if L.win == "heli" then
    for _, x in ipairs({ 0, ox }) do
      window(b, H, glass, V(x, 0.07, PZ - 0.26), V(0, -0.45, 1).Unit, V(0, 1, 0.5).Unit, 0.78, 0.66, FR)
      if L.chin then window(b, H, glass, V(x, FY + 0.10, -1.20), V(0, 0.6, 1).Unit, V(0, 0.5, -1).Unit, 0.46, 0.36, FR) end
      window(b, H, glass, V(x, RY + 0.01, -0.32), V(0, -1, 0), V(0, 0, -1), 0.40, 0.36, FR, 0.86)   -- 顶窗（带一点茶色）
      wiper(b, H, V(x, -0.24, PZ - 0.06), 0.36, 18, V(0, 0.45, -1).Unit)
    end
    bar(b, H, V(cx, -0.24, PZ - 0.08), V(cx, RY, -0.52), 0.06)                           -- 中柱
    for _, x in ipairs({ x0, x1 }) do
      local sgn = (x > cx) and 1 or -1
      window(b, H, glass, V(x, -0.08, -0.20), V(-sgn, 0, 0), V(0, 1, 0), 0.95, 0.80, FR)   -- 门窗
      bar(b, H, V(x, -0.50, PZ - 0.10), V(x, RY, -0.55), 0.05)                              -- 风挡边柱
    end
  else   -- 轰炸机：每座一块正风挡 + 一块往外斜的侧风挡 + 上面一块眉窗，两边侧窗；框粗
    for _, x in ipairs({ 0, ox }) do
      local out = (x - cx > 0) and 1 or -1   -- 这一座在中线哪边（侧风挡往那边斜）
      window(b, H, glass, V(x - out * 0.05, 0.02, PZ - 0.22), V(0, -0.55, 1).Unit, V(0, 1, 0.55).Unit, 0.46, 0.40, FR)
      window(b, H, glass, V(x + out * 0.36, 0.02, PZ - 0.10), V(-out * 0.7, -0.4, 0.8).Unit, V(0, 1, 0.4).Unit, 0.30, 0.38, FR)
      window(b, H, glass, V(x - out * 0.05, RY - 0.02, PZ + 0.02), V(0, -1, 0.35).Unit, V(0, 0.3, -1).Unit, 0.40, 0.18, FR, 0.88)
    end
    for _, x in ipairs({ x0, x1 }) do
      local sgn = (x > cx) and 1 or -1
      window(b, H, glass, V(x, 0.02, -0.30), V(-sgn, 0, 0.2).Unit, V(0, 1, 0), 0.40, 0.32, FR)
      bx(0.04, 0.70, 1.2, x, 0.05, 0.20, P1)   -- 窗后面的侧壁
    end
    bar(b, H, V(cx, -0.22, PZ - 0.10), V(cx, RY, -0.60), 0.10)
    -- 起落架手柄 + 三个绿灯（中间仪表板，两个飞行员都够得着）
    local gx = cx - sg * 0.13
    b:group("gearh", H, CF(gx, -0.56, PZ + 0.02))
    b:box("gearh", V(0.015, 0.10, 0.015), CF(0, 0.05, 0), C.lgray, MAT.Metal)
    b:cyl("gearh", 0.025, 0.05, CF(0, 0.11, 0), C.white)
    for i = -1, 1 do b:led(H, CF(gx + i * 0.022, -0.47, PZ + 0.0), RGB(80, 255, 110), 0.012, "gear") end
    b:placard(H, 0.06, 0.016, look(V(gx, -0.45, PZ + 0.005)), cn and "起落架" or "LDG GEAR", { bg = C.black, fg = C.white })
  end
  -- 灯：夜视兼容的绿白泛光、告警红灯
  b:light(H, CF(cx, RY - 0.12, -0.40), "dome", RGB(190, 230, 210), 2.0, 0.28)
  b:light(H, CF(0, -0.30, PZ + 0.20), "dome", RGB(190, 230, 210), 1.2, 0.18)
  b:light(H, CF(ox, -0.30, PZ + 0.20), "dome", RGB(190, 230, 210), 1.2, 0.18)
  b:light(H, CF(cx, -0.10, PZ + 0.20), "warn", RGB(255, 40, 30), 1.6, 0)
  b:name("glass", glass)
  return { air = true, heli = heli, yoke = L.ctrl == "yoke", stations = stations, order = order, crew = crew, cn = cn, glass = glass,
    seat = L.seat, eyeShift = L.eyeShift }
end

---------------------------------------------------------------- 串列双座武装直升机（阿帕奇、直-10）：我坐后座（飞行员，高一截），前座射手在前下方
--   L = { cn, hud = 后座有平显（直-10）, ihadss = 头盔单目显示（阿帕奇：Interior 把平显画在眼前） }
-- 资料：AH-64D/E 后座 —— 两块 6.24 英寸多功能显示器、上前显示器（EUFD）、备份仪表、左边总距杆和两根发动机功率杆、右边通信面板；
--   座舱盖是平板玻璃（前后座中间一块透明防爆隔板），后座右边是门；前座（AH-64E）的目标截获显示器（TEDAC）带两个握把
function Defs.tandem(b, ctx, L)
  local H = "hull"
  local cn = L.cn
  local eye = V()
  local function bx(sx, sy, sz, x, y, z, col, mat, rx, ry, rz)
    return b:box(H, V(sx, sy, sz), CF(x, y, z) * ANG(rad(rx or 0), rad(ry or 0), rad(rz or 0)), col, mat)
  end
  local function look(p, at) return CFrame.lookAt(p, at or eye) end
  local glass = {}
  local P1, P2 = RGB(48, 52, 50), RGB(38, 41, 40)
  local FY = -1.10
  local FE = V(0, -0.45, -1.70)   -- 前座眼位（外模型两个飞行员差 1.7 米、低 0.43 米）
  -- 后座：浴盆、侧台
  bx(0.90, 0.03, 1.5, 0, FY, -0.20, P2, MAT.DiamondPlate)
  for _, s in ipairs({ -1, 1 }) do
    bx(0.03, 0.70, 1.5, s * 0.46, FY + 0.35, -0.20, P1)
    bx(0.16, 0.10, 0.80, s * 0.37, -0.64, -0.05, P1)
    for i = 0, 3 do
      b:panel(H, 0.14, 0.17, CFrame.lookAt(V(s * 0.37, -0.585, -0.38 + i * 0.20), V(s * 0.32, 0.4, -0.26 + i * 0.20)), 3, 3, RGB(54, 58, 62), { guard = i == 1 })
    end
  end
  bx(0.90, 1.4, 0.04, 0, -0.42, 0.55, P2)
  -- 仪表板（窄、高）、遮光罩
  local PZ = -0.66
  b:box(H, V(0.62, 0.42, 0.06), CF(0, -0.44, PZ) * ANG(rad(-10), 0, 0), P1)
  bx(0.62, 0.05, 0.22, 0, -0.215, PZ + 0.05, GLARE, MAT.Fabric, 4, 0, 0)
  local K = cn and { top = { "姿态", "雷达", "态势", "武器", "发动机" }, bottom = { "油量", "检查", "目标", "通信", "菜单" } }
    or { top = { "PFD", "RDR", "SA", "SMS", "ENG" }, bottom = { "FUEL", "CHK", "TGT", "COM", "MENU" } }
  b:screen(H, 0.16, 0.16, look(V(-0.135, -0.47, PZ - 0.03)), "mfd_sa", { keys = K, lightK = 0.3 })
  b:screen(H, 0.16, 0.16, look(V(0.135, -0.47, PZ - 0.03)), cn and "mfd_pfd" or "mfd_rdr", { keys = K, lightK = 0.3 })
  b:screen(H, 0.12, 0.05, look(V(-0.18, -0.30, PZ + 0.0)), "ufd2", { lightK = 0.15 })   -- 上前显示器（告警、油量、起落）
  standby(b, H, V(0.12, -0.30, PZ + 0.0), eye, 0.06)
  b:led(H, CF(-0.06, -0.19, PZ + 0.08), RGB(255, 40, 30), 0.02, "mwarn")
  b:led(H, CF(0.06, -0.19, PZ + 0.08), RGB(255, 180, 30), 0.02, "mcaut")
  b:placard(H, 0.07, 0.016, look(V(-0.06, -0.205, PZ + 0.095)), cn and "主告警" or "MSTR WARN", { bg = C.black, fg = RGB(255, 80, 70) })
  b:placard(H, 0.07, 0.016, look(V(0.06, -0.205, PZ + 0.095)), cn and "主注意" or "MSTR CAUT", { bg = C.black, fg = RGB(255, 190, 60) })
  if L.hud then hudUnit(b, H, V(0, -0.09, PZ + 0.10), eye) end
  -- 座椅（防弹座椅，侧翼装甲板）
  b:seat(H, CF(0, -0.80, 0.14), { w = 0.46, d = 0.44, back = 0.70, recline = 12, col = RGB(66, 68, 60), frame = RGB(44, 46, 48) })
  for _, s in ipairs({ -1, 1 }) do bx(0.03, 0.55, 0.38, s * 0.26, -0.52, 0.28, RGB(70, 72, 64), nil, 12, 0, 0) end
  bx(0.34, 0.20, 0.10, 0, 0.02, 0.40, RGB(58, 60, 54), MAT.Fabric, 12, 0, 0)
  for _, s in ipairs({ -1, 1 }) do bx(0.03, 0.03, 0.30, s * 0.19, -0.25, 0.08, RGB(60, 70, 50), MAT.Fabric, -50, 0, 0) end
  -- 周期变距杆、总距杆、两根发动机功率杆、脚蹬
  b:group("stick", H, CF(0, FY + 0.04, -0.34))
  b:tube("stick", V(0, 0, 0), V(0, 0.50, 0.04), 0.03, C.dark, MAT.Metal)
  b:box("stick", V(0.05, 0.14, 0.05), CF(0, 0.57, 0.05) * ANG(rad(-8), 0, 0), C.black)
  b:button("stick", CF(0, 0.645, 0.03) * ANG(rad(-70), 0, 0), C.red, 0.012)
  b:box("stick", V(0.012, 0.035, 0.012), CF(0, 0.57, 0.02), RGB(60, 60, 60))
  b:group("coll", H, CF(-0.30, -0.80, 0.16))
  b:tube("coll", V(0, 0, 0), V(0, 0.02, -0.44), 0.035, C.dark, MAT.Metal)
  b:box("coll", V(0.06, 0.07, 0.12), CF(0, 0.04, -0.48), C.black)
  b:button("coll", CF(0, 0.08, -0.50) * ANG(rad(-90), 0, 0), C.dark, 0.014)
  for _, s in ipairs({ 0, 1 }) do   -- 发动机功率杆（左侧台前端）
    bx(0.012, 0.07, 0.012, -0.36 + s * 0.03, -0.56, -0.40, C.lgray, MAT.Metal, -20, 0, 0)
    bx(0.022, 0.02, 0.03, -0.36 + s * 0.03, -0.52, -0.42, C.black)
  end
  for _, s in ipairs({ -1, 1 }) do
    local gname = (s < 0) and "pedL" or "pedR"
    b:group(gname, H, CF(s * 0.14, FY + 0.16, -0.98))
    b:box(gname, V(0.10, 0.20, 0.03), CF() * ANG(rad(-20), 0, 0), RGB(40, 42, 44), MAT.Metal)
  end
  -- 前座（射手）：从后座越过仪表板、透过防爆隔板看得到——浴盆、两侧台、仪表板、目标截获显示器（TEDAC）和两个握把、侧杆、总距杆、座椅
  local fz = FE.Z
  local FF = FE.Y - 1.10   -- 前座地板
  window(b, H, glass, V(0, 0.06, -0.78), V(0, 0, 1), V(0, 1, 0), 0.82, 0.52, 0.03, 0.88)   -- 防爆隔板（透明，仪表板上沿到座舱盖顶）
  bx(0.84, 0.03, 1.5, 0, FF, fz - 0.30, P2, MAT.DiamondPlate)
  for _, s in ipairs({ -1, 1 }) do
    bx(0.03, 0.70, 1.5, s * 0.43, FF + 0.35, fz - 0.30, P1)
    bx(0.15, 0.10, 0.70, s * 0.35, FE.Y - 0.64, fz - 0.10, P1)
    for i = 0, 2 do
      b:panel(H, 0.13, 0.17, CFrame.lookAt(V(s * 0.35, FE.Y - 0.585, fz - 0.36 + i * 0.20), V(s * 0.30, FE.Y + 0.4, fz - 0.24 + i * 0.20)), 3, 3, RGB(54, 58, 62))
    end
  end
  bx(0.84, 0.60, 0.04, 0, FE.Y - 0.85, fz + 0.50, P2)   -- 前座后面的隔框（后座脚蹬前面）
  b:seat(H, CF(0, FE.Y - 0.80, fz + 0.14), { w = 0.44, d = 0.42, back = 0.66, recline = 12, col = RGB(66, 68, 60), frame = RGB(44, 46, 48) })
  bx(0.34, 0.20, 0.10, 0, FE.Y + 0.02, fz + 0.40, RGB(58, 60, 54), MAT.Fabric, 12, 0, 0)
  b:box(H, V(0.56, 0.36, 0.06), CF(0, FE.Y - 0.42, fz - 0.62) * ANG(rad(-14), 0, 0), P1)
  local tw, th = 0.20, 0.15
  if L.ihadss then tw, th = 0.127, 0.127 end   -- AH-64E 的 TEDAC：5 × 5 英寸液晶（docs/cockpit_research.md）
  b:box(H, V(tw + 0.10, th + 0.07, 0.16), CF(0, FE.Y - 0.16, fz - 0.52), RGB(34, 36, 36))      -- 目标截获显示器机箱
  b:screen(H, tw, th, look(V(0, FE.Y - 0.14, fz - 0.435), FE), "gunsight", { lightK = 0.25 })
  for _, s in ipairs({ -1, 1 }) do bx(0.05, 0.12, 0.06, s * 0.20, FE.Y - 0.30, fz - 0.42, C.black, nil, -20, 0, 0) end   -- 两个握把
  bx(0.04, 0.12, 0.05, 0.33, FE.Y - 0.56, fz - 0.10, C.black, nil, -12, 0, 0)                  -- 射手的侧杆（右侧台）
  bx(0.035, 0.035, 0.40, -0.30, FE.Y - 0.78, fz - 0.10, C.dark, MAT.Metal, 4, 0, 0)            -- 射手的总距杆（左边）
  for _, s in ipairs({ -1, 1 }) do bx(0.10, 0.20, 0.03, s * 0.13, FF + 0.16, fz - 0.95, RGB(40, 42, 44), MAT.Metal, -20, 0, 0) end
  -- 座舱盖：平板玻璃。后座：两侧（右边是门）、顶上、前面一块斜的（越过前座看出去）；前座：前风挡（带雨刷）、两侧
  window(b, H, glass, V(-0.47, -0.02, -0.20), V(1, 0, 0), V(0, 1, 0), 1.10, 0.62, 0.035)
  window(b, H, glass, V(0.47, -0.02, -0.20), V(-1, 0, 0), V(0, 1, 0), 1.10, 0.62, 0.035)
  window(b, H, glass, V(0, 0.34, -0.25), V(0, -1, 0), V(0, 0, -1), 0.80, 0.95, 0.035, 0.86)
  window(b, H, glass, V(0, 0.12, -0.86), V(0, -0.55, 1).Unit, V(0, 1, 0.55).Unit, 0.84, 0.48, 0.035)
  window(b, H, glass, V(0, FE.Y + 0.05, fz - 0.80), V(0, -0.5, 1).Unit, V(0, 1, 0.5).Unit, 0.72, 0.52, 0.04)
  wiper(b, H, V(0, FE.Y - 0.18, fz - 0.84), 0.40, 14, V(0, 0.5, -1).Unit)
  for _, s in ipairs({ -1, 1 }) do
    window(b, H, glass, V(s * 0.43, FE.Y + 0.02, fz - 0.15), V(-s, 0, 0.15).Unit, V(0, 1, 0), 0.95, 0.60, 0.035)
    bar(b, H, V(s * 0.45, -0.32, 0.34), V(s * 0.45, 0.34, 0.34), 0.05)
    bar(b, H, V(s * 0.45, 0.34, 0.34), V(s * 0.42, 0.34, -0.80), 0.05)
  end
  -- 灯
  b:light(H, CF(0, 0.20, -0.30), "dome", RGB(190, 230, 210), 1.6, 0.25)
  b:light(H, CF(0, -0.30, PZ + 0.18), "dome", RGB(190, 230, 210), 1.0, 0.16)
  b:light(H, CF(0, FE.Y + 0.20, fz - 0.20), "dome", RGB(190, 230, 210), 1.2, 0.16)
  b:light(H, CF(0, -0.10, PZ + 0.20), "warn", RGB(255, 40, 30), 1.4, 0)
  b:name("glass", glass)
  local dress = cn and "heli_cn" or "heli_us"
  local crew = {
    pilot = { dress = dress, g = H, eye = eye, lean = 2, yaw = 0, look = V(0, -0.05, -1),
      hands = { r = { "stick", V(0, 0.58, 0.05) }, l = { "coll", V(0, 0.05, -0.46) } },
      feet = { l = { "pedL", V(0, -0.04, 0.06) }, r = { "pedR", V(0, -0.04, 0.06) } } },
    gunner = { dress = dress, g = H, eye = FE, lean = 6, yaw = 0, look = V(0, -0.25, -1),
      hands = { l = { H, FE + V(-0.20, -0.26, -0.40) }, r = { H, FE + V(0.20, -0.26, -0.40) } },
      feet = { l = { H, FE + V(-0.12, -0.95, -0.80) }, r = { H, FE + V(0.12, -0.95, -0.80) } } },
  }
  local stations = {
    pilot = { g = H, eye = eye, look = V(0, -0.03, -1), yaw = 150, up = 70, down = 65, crew = "pilot" },
    gunner = { g = H, eye = FE, look = V(0, -0.10, -1), yaw = 150, up = 60, down = 60, crew = "gunner" },
  }
  return { air = true, heli = true, stations = stations, order = { "pilot", "gunner" }, crew = crew, cn = cn, glass = glass,
    seat = 2, ihadss = L.ihadss }
end

Defs.z10 = function(b, ctx) return Defs.tandem(b, ctx, { cn = true, hud = true }) end
Defs.ah64e = function(b, ctx) return Defs.tandem(b, ctx, { ihadss = true }) end
Defs.uh60 = function(b, ctx) return Defs.side(b, ctx, { half = 0.50, me = "R", ctrl = "heli", disp = "uh60m", win = "heli", chin = true, seat = 2 }) end
Defs.ch47 = function(b, ctx) return Defs.side(b, ctx, { half = 0.60, me = "R", ctrl = "heli", disp = "ch47f", win = "heli", chin = true, seat = 2 }) end
Defs.z20 = function(b, ctx) return Defs.side(b, ctx, { half = 0.50, me = "L", ctrl = "heli", disp = "z20", win = "heli", chin = true, cn = true, seat = 1 }) end
Defs.h6k = function(b, ctx) return Defs.side(b, ctx, { half = 0.55, me = "L", ctrl = "yoke", disp = "h6k", win = "bomber", cn = true, hud = true, thr = 2, eyeShift = -0.55 }) end
Defs.b2 = function(b, ctx) return Defs.side(b, ctx, { half = 0.62, me = "L", ctrl = "stick", disp = "b2", win = "bomber", thr = 4, thrSide = true, eyeShift = -0.62 }) end

-- 步战车、装甲车、自行火炮、自行高炮、轮式车、卡车（InteriorAFV.lua）
require(script.Parent:WaitForChild("InteriorAFV"))(Defs, { window = window, pane = pane, bar = bar, wiper = wiper, standby = standby, hudUnit = hudUnit })

return Defs
