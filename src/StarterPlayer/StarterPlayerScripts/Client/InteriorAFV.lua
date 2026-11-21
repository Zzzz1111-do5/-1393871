-- Roblox全面大战场（客户端）——步战车、装甲车、突击炮、自行火炮、自行高炮、轮式车、卡车的内饰（InteriorDefs 末尾调：require(...)(Defs, 共用件)）
--   用户 11-21：所有载具都要有内饰，所有观瞄设备都要找资料一一实现。
--   按各型的车体尺寸摆（VehDefs 的长宽高、离地间隙、炮塔座圈位置）：原点在炮塔座圈中心、座圈平面上（同主战坦克），X 右、Y 上、−Z 朝前；
--   从前往后：驾驶员（左前）和发动机舱（右前）→ 战斗室（炮塔篮）→ 载员舱（两排长凳、后跳板 / 后门）
-- 资料（公开的照片、视频、剖视图）：M2A3 —— 左前驾驶员（四具潜望镜、驾驶员视觉增强器）、双人炮塔（炮长左：综合瞄准具 ISU 目镜和炮长显示器；车长右：
--   独立热像观察仪 CIV、指挥终端）、M242 25 毫米炮的双向供弹、后部动力跳板带小门、载员六人；斯特赖克 —— 驾驶员左前、车长在后面操作遥控武器站
--   （CROWS 显示器和握把）、九名载员、后跳板；ZBD-05 / ZSL-92B —— 驾驶员左前、双人 30 毫米炮塔、载员舱后门；ZTD-05 / PTL-02 —— 三人炮塔，105 毫米炮手动装填
--   （炮尾、防危板、弹架）；M109A7 / PLZ-07 —— 大炮塔，炮长左前（周视瞄准镜 + 直瞄镜）、车长右前、两名装填手在后面，炮塔尾舱两边弹架和药筒架、输弹机；
--   PGZ-07 —— 炮长、车长，搜索雷达和跟踪雷达的显示器、光电跟踪器画面；悍马 / JLTV —— 四座、风挡、仪表台、方向盘、中间电台，射手站在后面的炮塔环里
--   （JLTV 是遥控武器站）；卡车（PGL-625、LD-2000、C-RAM、爱国者、M270）—— 驾驶室：风挡、仪表台、方向盘、操作员的显示控制台
local Kit = require(script.Parent:WaitForChild("InteriorKit"))
local V, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local RGB = Color3.fromRGB
local MAT = Enum.Material
local C = Kit.C
local rad, PI = math.rad, math.pi
local S = Kit.S

return function(Defs, Hp)
  local window, bar = Hp.window, Hp.bar
  -- 方向盘的轮缘：在组的 XY 平面上、绕 Z 轴一圈（组的 −Z 对着驾驶员；Defs.ring 是水平的圈，做轮缘会侧着对人）
  local function zring(b, g, r, n, t, col, mat)
    local seg = 2 * PI / n
    local len = 2 * r * math.sin(seg / 2) * 1.05
    for i = 0, n - 1 do
      local a = (i + 0.5) * seg
      b:box(g, V(len, t, t), CF(math.sin(a) * r, math.cos(a) * r, 0) * ANG(0, 0, -a), col, mat)
    end
  end

  -- 屏幕边的键（同坦克）
  local KEY = {
    did = { top = { "MAIN MENU", "STATUS", "W/C/A", "NAV", "MAINT" }, bottom = { "PUSH TO START", "SHUT OFF", "TAC IDLE", "LAMP TEST", "ALARM ACK" } },
    drvcn = { top = { "主菜单", "状态", "故障", "导航", "维护" }, bottom = { "起动", "熄火", "怠速", "灯检", "消音" } },
    citv = { top = { "WHT", "BLK", "WFOV", "NFOV", "SYM" }, bottom = { "MAN", "AUTO", "GUN LOS", "GPS LOS", "DESIG" } },
    citvcn = { top = { "白热", "黑热", "宽视场", "窄视场" }, bottom = { "手动", "扫描", "随炮", "指示" } },
    cid = { top = { "MAP", "MSG", "STAT", "NAV", "POS" }, bottom = { "ZOOM+", "ZOOM-", "OVLY", "BRT+", "BRT-" } },
    cnmap = { top = { "地图", "消息", "态势", "导航", "坐标" }, bottom = { "放大", "缩小", "标绘", "亮+", "亮-" } },
    crows = { top = { "ARM", "SAFE", "THERM" }, bottom = { "ZOOM", "LASE", "SLAVE" } },
  }

  ---------------------------------------------------------------- 装甲车（履带 / 轮式），参数：
  --   L = { cn, wheeled, drv = { x, z（相对前壁）, ctrl = "tbar" / "wheel" }, tur = "ifv" / "wedge" / "sph" / "spaag" / "rws" / nil, gunL（炮长在左）,
  --     troops = 载员数, door = "ramp" / "door", eng = 发动机舱长（右前，米）, gunK = 炮的后坐（米）, gunCal = 炮尾大小, opt = 各乘员位的观瞄设备 }
  function Defs.afv(b, ctx, L)
    local d = ctx.def
    local T, H, G = "turret", "hull", "gun"
    local piv = ctx.piv or d.turret.pivot   -- 座圈中心（同 Interior 的 frames）
    local cn = L.cn
    local WALL = cn and RGB(178, 196, 178) or RGB(222, 222, 212)
    local WALL2 = cn and RGB(152, 170, 152) or RGB(196, 196, 186)
    local OD = cn and RGB(74, 92, 70) or RGB(84, 90, 66)
    local FLOOR = RGB(56, 58, 56)
    local function bx(g, sx, sy, sz, x, y, z, col, mat, rx, ry, rz)
      return b:box(g, V(sx, sy, sz), CF(x, y, z) * ANG(rad(rx or 0), rad(ry or 0), rad(rz or 0)), col, mat)
    end
    local function look(p, at) return CFrame.lookAt(p, at) end
    -- 车体里面的范围（米）
    local zF = (-d.L / 2 - piv.Z) / S + 0.30
    local zR = (d.L / 2 - piv.Z) / S - 0.25
    local FY = (d.clear - piv.Y) / S + 0.10
    local RY = (d.hullH - piv.Y) / S - 0.05
    local HW = d.W / S * 0.40
    local RR = math.min(HW - 0.20, d.turret.size.X / S * 0.42)
    local TH = math.max(0.45, d.turret.size.Y / S - 0.10)   -- 炮塔里的净高（座圈平面以上）
    local hgt = RY - FY

    ---------------- 车体：地板、侧壁、车顶、前壁、后壁
    bx(H, HW * 2, 0.04, zR - zF, 0, FY - 0.02, (zF + zR) / 2, FLOOR, MAT.DiamondPlate)
    for _, s in ipairs({ -1, 1 }) do
      bx(H, 0.04, hgt, zR - zF, s * HW, (FY + RY) / 2, (zF + zR) / 2, WALL2)
      if not L.wheeled then bx(H, 0.30, 0.04, zR - zF, s * (HW - 0.15), FY + 0.42, (zF + zR) / 2, WALL2) end   -- 履带上方的台阶
    end
    -- 车顶（座圈那块留口子）
    local rf0, rf1 = -RR - 0.05, RR + 0.05
    bx(H, HW * 2, 0.04, rf0 - zF, 0, RY, (zF + rf0) / 2, WALL)
    bx(H, HW * 2, 0.04, zR - rf1, 0, RY, (rf1 + zR) / 2, WALL)
    for _, s in ipairs({ -1, 1 }) do bx(H, HW - RR - 0.05, 0.04, rf1 - rf0, s * (HW + RR + 0.05) / 2, RY, 0, WALL) end
    bx(H, HW * 2, hgt, 0.04, 0, (FY + RY) / 2, zF - 0.02, WALL2)
    if not L.tur or L.tur ~= "sph" or true then
      -- 座圈
      Defs.ring(b, H, 0, RY - 0.03, 0, RR + 0.03, 24, 0.05, 0.06, C.steel, MAT.Metal)
    end

    ---------------- 驾驶员（左前）
    local drv = L.drv or {}
    local dx = drv.x or -(HW - 0.42)
    local dz = zF + (drv.z or 0.95)
    local eyeD = V(dx, RY - 0.22, dz)
    -- 驾驶舱的隔板（右边是发动机舱，后面通战斗室）
    local engLen = L.eng or 1.7
    local ex0 = dx + 0.34
    if engLen > 0 then
      bx(H, HW - ex0, hgt, engLen, (ex0 + HW) / 2, (FY + RY) / 2, zF + engLen / 2, OD)                     -- 发动机舱（右前）
      bx(H, 0.03, hgt * 0.9, engLen, ex0 - 0.015, (FY + RY) / 2, zF + engLen / 2, WALL2)                    -- 隔热板（对着驾驶员）
      for i = 0, 3 do bx(H, 0.01, 0.10, engLen * 0.8, ex0 - 0.035, FY + 0.30 + i * 0.18, zF + engLen / 2, C.dark) end
      b:placard(H, 0.18, 0.06, CF(ex0 - 0.04, RY - 0.30, zF + engLen * 0.6) * ANG(0, -PI / 2, 0), cn and "动力舱 注意高温" or "ENGINE  HOT", { bg = C.yellow, fg = C.black })
    end
    -- 三具潜望镜 + 舱盖
    for i = -1, 1 do
      local a = rad(i * 30)
      local p = V(dx + math.sin(a) * 0.20, RY - 0.10, dz - 0.16 - math.cos(a) * 0.05)
      b:periscope(H, look(p, p + V(math.sin(a), 0, -math.cos(a))), 0.15, 0.08, 0.09)
    end
    b:cylY(H, 0.04, 0.56, CF(dx, RY - 0.01, dz + 0.20), WALL, MAT.SmoothPlastic)
    b:grab(H, V(dx - 0.10, RY - 0.05, dz + 0.24), V(dx + 0.10, RY - 0.05, dz + 0.24), V(0, -0.05, 0), 0.02, C.black)
    -- 座椅、操纵件、踏板
    b:seat(H, CF(dx, eyeD.Y - 0.78, dz + 0.10), { w = 0.44, d = 0.42, back = 0.58, recline = 22, head = true, col = RGB(54, 52, 46) })
    local ctrl = drv.ctrl or (L.wheeled and "wheel" or (cn and "wheel" or "tbar"))
    if ctrl == "tbar" then
      b:group("tbar", H, CF(dx, eyeD.Y - 0.50, dz - 0.40))
      b:tube("tbar", V(-0.24, 0, 0), V(0.24, 0, 0), 0.035, C.dark, MAT.Metal)
      b:cyl("tbar", 0.10, 0.05, CF(-0.25, 0, 0), C.rubber, MAT.Fabric)
      b:cyl("tbar", 0.10, 0.05, CF(0.25, 0, 0), C.rubber, MAT.Fabric)
      b:box("tbar", V(0.10, 0.06, 0.08), CF(0, 0.02, 0), C.black)
      b:tube(H, V(dx, eyeD.Y - 0.50, dz - 0.40), V(dx, FY + 0.05, dz - 0.62), 0.06, C.gray, MAT.Metal)
    else   -- 方向盘：转向柱斜着伸向驾驶员，方向盘跟着转向转
      local wc = V(dx, eyeD.Y - 0.42, dz - 0.40)
      b:group("swheel", H, look(wc, wc + V(0, -0.55, 1)))
      zring(b, "swheel", 0.19, 16, 0.03, C.rubber, MAT.Fabric)
      b:box("swheel", V(0.36, 0.025, 0.03), CF(0, 0, 0), C.dark, MAT.Metal)
      b:box("swheel", V(0.025, 0.18, 0.03), CF(0, -0.09, 0), C.dark, MAT.Metal)
      b:cyl("swheel", 0.05, 0.07, CF(0, 0, 0.02) * ANG(0, PI / 2, 0), C.black)
      b:tube(H, wc, wc + V(0, -0.30, -0.42), 0.05, C.gray, MAT.Metal)
    end
    -- 踏板 + 换挡
    bx(H, 0.10, 0.04, 0.14, dx + 0.10, FY + 0.06, dz - 0.70, C.dark, MAT.DiamondPlate, -30, 0, 0)
    bx(H, 0.12, 0.04, 0.14, dx - 0.10, FY + 0.06, dz - 0.72, C.dark, MAT.DiamondPlate, -30, 0, 0)
    bx(H, 0.025, 0.16, 0.025, dx + 0.26, eyeD.Y - 0.62, dz - 0.10, C.black, MAT.Metal, -15, 0, 0)
    -- 仪表板：驾驶员显示器 + 开关面板
    local dpage = cn and "drvcn" or "did"
    b:screen(H, 0.18, 0.13, look(V(dx - 0.05, eyeD.Y - 0.18, dz - 0.52), eyeD), dpage, { keys = KEY[dpage], lightK = 0.28 })
    b:panel(H, 0.15, 0.24, look(V(dx - 0.32, eyeD.Y - 0.38, dz - 0.30), eyeD + V(0.2, -0.3, 0)), 4, 2, RGB(70, 72, 70), { guard = true })
    if drv.dve ~= false then
      b:screen(H, 0.14, 0.10, look(V(dx + 0.16, eyeD.Y - 0.10, dz - 0.40), eyeD), "dve", { lightColor = RGB(200, 200, 200), lightK = 0.2 })
    end
    b:extinguisher(H, CF(dx - 0.30, FY + 0.25, dz + 0.45), 0.42, 0.13)
    b:light(H, CF(dx, RY - 0.12, dz + 0.1), "dome", RGB(255, 240, 220), 2.4, 0.7)

    ---------------- 战斗室 / 炮塔
    local stations = {
      driver = { g = H, eye = eyeD, look = V(0, 0.08, -1), yaw = 110, up = 40, down = 60, crew = "driver",
        optics = { primary = (L.opt and L.opt.driver) or { kind = cn and "nv" or "dve", name = cn and "驾驶员微光夜视仪" or "DVE  AN/VAS-5", g = H,
          pos = V(dx, RY + 0.06, dz - 0.25), dir = "hull", fovs = { 40 }, ret = cn and "none" or "dve", look = cn and "nv" or "bhot", shape = "rect" } } },
    }
    local dress = cn and "tank_cn" or "tank_us"
    local crew = {
      driver = { dress = dress, g = H, eye = eyeD, lean = 20, yaw = 0, look = V(0, 0.05, -1),
        hands = (ctrl == "tbar") and { l = { "tbar", V(-0.25, 0, 0) }, r = { "tbar", V(0.25, 0, 0) } } or { l = { "swheel", V(-0.17, 0.03, 0) }, r = { "swheel", V(0.17, 0.03, 0) } },
        feet = { l = { H, V(dx - 0.10, FY + 0.10, dz - 0.70) }, r = { H, V(dx + 0.10, FY + 0.10, dz - 0.68) } } },
    }
    local order = { "driver" }
    local tur = L.tur
    local gs = L.gunL and -1 or 1   -- 炮长在哪边（−1 左）
    if tur == "ifv" or tur == "wedge" or tur == "sph" or tur == "spaag" then
      local big = tur == "sph"
      local TR = big and math.max(RR, 1.05) or RR
      -- 炮塔篮：地板、栏杆、中间滑环
      b:cylY(T, 0.03, TR * 1.9, CF(0, FY + 0.06, 0), FLOOR, MAT.DiamondPlate)
      b:cylY(T, 0.20, 0.26, CF(0, FY + 0.17, 0.05), C.dark, MAT.Metal)
      for i = 0, 9 do
        local a = (i + 0.5) * PI / 5
        if not (a > PI * 0.75 and a < PI * 1.25) then
          b:tube(T, V(math.sin(a) * TR * 0.95, FY + 0.06, math.cos(a) * TR * 0.95), V(math.sin(a) * TR * 0.95, RY - 0.06, math.cos(a) * TR * 0.95), 0.03, C.lgray, MAT.Metal)
        end
      end
      -- 炮塔壁、顶（从里面看）
      local tw = d.turret.size.X / S * 0.46
      local tl = d.turret.size.Z / S * 0.46
      for _, s in ipairs({ -1, 1 }) do bx(T, 0.04, TH, tl * 2, s * tw, TH / 2, 0, WALL) end
      bx(T, tw * 2, TH, 0.04, 0, TH / 2, tl, WALL2)
      bx(T, tw * 2, TH, 0.04, 0, TH / 2, -tl, WALL2)
      bx(T, tw * 2, 0.04, tl * 2, 0, TH, 0, WALL)
      -- 炮尾（随炮俯仰，开炮后坐）：小口径机关炮短、105 / 122 / 155 毫米大
      local cal = L.gunCal or (big and 0.40 or ((tur == "wedge") and 0.30 or 0.16))
      local gp = (ctx.gpiv or d.gun.pivot) / S   -- 炮耳轴（炮塔坐标，同 Interior 的 frames）
      local blen = big and 1.10 or ((tur == "wedge") and 0.85 or 0.60)
      b:group("recoil", G, CF())
      bx("recoil", cal * 1.3, cal * 1.3, blen, 0, 0, blen / 2 + 0.10, C.gun, MAT.Metal)
      bx("recoil", cal * 1.5, cal * 0.5, blen * 0.4, 0, -cal * 0.85, blen * 0.55, C.dark, MAT.Metal)   -- 反后坐装置
      if tur ~= "spaag" then   -- 炮尾防护栏（黄色钢管框：后坐时人别站在里面）
        for _, s in ipairs({ -1, 1 }) do
          local x = s * cal * 1.2
          b:tube(G, V(x, cal * 0.9, 0.15), V(x, cal * 0.9, blen + 0.45), 0.035, C.yellow, MAT.Metal)
          b:tube(G, V(x, -cal * 0.9, 0.15), V(x, -cal * 0.9, blen + 0.45), 0.035, C.yellow, MAT.Metal)
          b:tube(G, V(x, cal * 0.9, blen + 0.45), V(x, -cal * 0.9, blen + 0.45), 0.035, C.yellow, MAT.Metal)
        end
        b:tube(G, V(-cal * 1.2, cal * 0.9, blen + 0.45), V(cal * 1.2, cal * 0.9, blen + 0.45), 0.035, C.yellow, MAT.Metal)
      end
      if tur == "ifv" then   -- 机关炮：两边的弹箱、供弹槽（双向供弹）
        for _, s in ipairs({ -1, 1 }) do
          bx(T, 0.20, 0.30, 0.50, s * 0.18, gp.Y - 0.40, gp.Z + 0.45, OD)
          b:cable(T, { V(s * 0.18, gp.Y - 0.25, gp.Z + 0.45), V(s * 0.10, gp.Y - 0.08, gp.Z + 0.30), V(s * 0.05, gp.Y, gp.Z + 0.25) }, 0.06, C.steel, MAT.Metal)
        end
        b:placard(T, 0.14, 0.05, CF(0, gp.Y - 0.20, gp.Z + 0.71) * ANG(0, PI, 0), cn and "弹药" or "AMMO", { bg = C.yellow, fg = C.black })
      end
      -- 乘员位：炮长（gs 那边）、车长（另一边，高一点）
      local gx, cxp = gs * 0.40, -gs * 0.42
      local gEye = V(gx, math.min(TH - 0.16, 0.42), -0.20)
      local cEye = V(cxp, math.min(TH - 0.10, 0.52), 0.05)
      if big then gEye, cEye = V(gs * 0.55, math.min(TH - 0.20, 0.50), -0.55), V(-gs * 0.58, math.min(TH - 0.12, 0.62), -0.40) end
      -- 炮长：瞄准镜目镜（护额垫 + 橡胶眼罩）、炮长显示器、双握把
      bx(T, 0.18, 0.20, 0.32, gx, gEye.Y + 0.02, gEye.Z - 0.30, RGB(40, 42, 40))
      bx(T, 0.16, 0.05, 0.05, gx, gEye.Y + 0.09, gEye.Z - 0.13, C.rubber, MAT.Fabric)
      for _, s in ipairs({ -1, 1 }) do b:cylZ(T, 0.05, 0.045, CF(gx + s * 0.032, gEye.Y, gEye.Z - 0.135), C.rubber, MAT.Fabric) end
      b:screen(T, 0.16, 0.12, look(V(gx - gs * 0.20, gEye.Y - 0.18, gEye.Z - 0.30), gEye), big and "afcs" or "gunsight", { lightK = 0.25 })
      b:group("gch", T, CF(gx, gEye.Y - 0.40, gEye.Z - 0.28))
      bx("gch", 0.30, 0.04, 0.05, 0, 0, 0, C.dark, MAT.Metal)
      for _, s in ipairs({ -1, 1 }) do bx("gch", 0.04, 0.12, 0.05, s * 0.15, 0.05, 0, C.rubber, MAT.Fabric) end
      b:seat(T, CF(gx, gEye.Y - 0.80, gEye.Z + 0.12), { w = 0.40, d = 0.36, back = 0.42, recline = 8, col = RGB(52, 50, 44), post = 0.30 })
      -- 车长：观察镜一圈、显示器、握把
      for i = 0, 5 do
        local a = (i - 2.5) * rad(40)
        local p = V(cxp + math.sin(a) * 0.30, cEye.Y + 0.08, cEye.Z - math.cos(a) * 0.30)
        b:periscope(T, look(p, p + V(math.sin(a), 0, -math.cos(a))), 0.14, 0.08, 0.09, { pad = false })
      end
      local cpage = (L.opt and L.opt.cpage) or (cn and "citvcn" or "citv")
      b:screen(T, 0.18, 0.13, look(V(cxp + gs * 0.10, cEye.Y - 0.22, cEye.Z - 0.36), cEye), cpage, { keys = KEY[cpage], lightK = 0.28 })
      local mpage = cn and "cnmap" or "cid"
      b:screen(T, 0.20, 0.15, look(V(cxp - gs * 0.30, cEye.Y - 0.28, cEye.Z - 0.12), cEye), mpage, { keys = KEY[mpage], lightColor = RGB(150, 190, 230), lightK = 0.3 })
      b:group("cch", T, CF(cxp, cEye.Y - 0.44, cEye.Z - 0.30))
      bx("cch", 0.06, 0.12, 0.06, 0, 0.05, 0, C.black)
      b:seat(T, CF(cxp, cEye.Y - 0.80, cEye.Z + 0.12), { w = 0.40, d = 0.36, back = 0.40, recline = 8, col = RGB(52, 50, 44), post = 0.30 })
      b:radio(T, 0.24, 0.18, 0.20, CF(-gs * (tw - 0.14), 0.22, tl - 0.15) * ANG(0, PI, 0), OD)
      -- 车长、炮长的舱盖（从里面看）
      b:cylY(T, 0.04, 0.54, CF(cxp, TH + 0.01, cEye.Z), WALL, MAT.SmoothPlastic)
      b:light(T, CF(0, TH - 0.10, 0.10), "dome", RGB(255, 240, 220), 2.4, 0.7)
      b:light(T, CF(0, 0.10, -0.40), "flash", RGB(255, 170, 80), 4, 0)
      stations.gunner = { g = T, eye = gEye + V(0, 0.04, 0.14), look = V(0, -0.15, -1), yaw = 110, up = 45, down = 60, crew = "gunner", sight = true,
        scope = V(gx, gEye.Y, gEye.Z - 0.14),
        optics = { primary = { kind = "gps" }, alt = (L.opt and L.opt.gunnerAlt) or nil } }
      stations.commander = { g = T, eye = cEye, look = V(0, -0.25, -1), yaw = 160, up = 70, down = 70, crew = "commander",
        scope = V(gx, gEye.Y, gEye.Z - 0.14),
        optics = { primary = (L.opt and L.opt.commander) or { kind = "citv", name = cn and "车长周视热像仪" or "CIV", g = T, pos = V(cxp, TH + 0.35, cEye.Z - 0.20),
          dir = "citv", fovs = { 20, 6 }, ret = cn and "pano" or "citv", look = "whot", shape = cn and "circle" or "rect" },
          alt = { kind = "gps" } } }
      crew.gunner = { dress = dress, g = T, eye = gEye, lean = -18, yaw = 0, look = V(0, -0.12, -1),
        hands = { l = { "gch", V(-0.15, 0.08, 0) }, r = { "gch", V(0.15, 0.08, 0) } },
        feet = { l = { T, V(gx - 0.10, FY + 0.14, gEye.Z - 0.35) }, r = { T, V(gx + 0.10, FY + 0.14, gEye.Z - 0.35) } } }
      crew.commander = { dress = dress, g = T, eye = cEye, lean = -10, yaw = 0, look = V(0, -0.30, -1),
        hands = { l = { T, cEye + V(gs * 0.20, -0.40, -0.25) }, r = { "cch", V(0, 0.10, 0) } },
        feet = { l = { T, V(cxp - 0.10, FY + 0.14, cEye.Z - 0.25) }, r = { T, V(cxp + 0.10, FY + 0.14, cEye.Z - 0.25) } } }
      table.insert(order, "gunner")
      table.insert(order, "commander")
      if tur == "wedge" or tur == "sph" then
        -- 装填手（后面）：弹架（尾舱两边竖着一排排的弹）、药筒架；自行火炮还有输弹机托盘
        local lEye = V(-gs * 0.30, math.min(TH - 0.12, 0.55), big and 0.75 or 0.50)
        for _, s in ipairs({ -1, 1 }) do
          for i = 0, (big and 7 or 4) do
            local z = (big and 0.30 or 0.25) + i * 0.16
            if z < tl - 0.08 then
              b:cylY(T, big and 0.62 or 0.50, cal * 0.95, CF(s * (tw - 0.10), TH * 0.45, z), RGB(70, 80, 60), MAT.Metal)
              b:ball(T, cal * 0.95, CF(s * (tw - 0.10), TH * 0.45 + (big and 0.31 or 0.25), z), RGB(160, 140, 60), MAT.Metal)
            end
          end
          bx(T, 0.04, TH * 0.9, tl - 0.25, s * (tw - 0.22), TH * 0.45, (tl + 0.25) / 2, C.dark, MAT.Metal)   -- 弹架的立柱
        end
        if big then   -- 输弹机托盘（炮尾后面）+ 药筒架
          bx(G, 0.22, 0.06, 0.90, 0, -0.10, blen + 0.60, C.steel, MAT.Metal)
          for i = 0, 3 do b:cylZ(T, 0.40, 0.17, CF(gs * 0.55, 0.05 + i * 0.18, tl - 0.30), RGB(150, 130, 80), MAT.SmoothPlastic) end
        end
        stations.loader = { g = T, eye = lEye, look = V(0.3 * gs, -0.25, -1), yaw = 170, up = 60, down = 75, crew = "loader",
          optics = { primary = { kind = "lscope", name = cn and "装填手潜望镜" or "LOADER'S PERISCOPE", g = T, pos = V(lEye.X, TH + 0.10, lEye.Z - 0.15),
            dir = "free360", fovs = { 38 }, ret = "none", look = "day", shape = "slot" } } }
        crew.loader = { dress = dress, g = T, eye = lEye, lean = 8, yaw = 0, look = V(0, -0.3, -1),
          hands = { l = { T, lEye + V(-0.20, -0.45, -0.30) }, r = { T, lEye + V(0.20, -0.45, -0.30) } },
          feet = { l = { T, V(lEye.X - 0.12, FY + 0.10, lEye.Z) }, r = { T, V(lEye.X + 0.12, FY + 0.10, lEye.Z) } } }
        table.insert(order, "loader")
        if tur == "sph" then   -- 炮长的周视瞄准镜（间接瞄准、米位刻度）、直瞄镜
          stations.gunner.optics.primary = { kind = "pantel", name = cn and "周视瞄准镜" or "PANORAMIC TELESCOPE  M137A2", g = T,
            pos = V(gEye.X, TH + 0.40, gEye.Z - 0.15), dir = "free", fovs = { 10 }, ret = "mil", look = "day", shape = "circle" }
          stations.gunner.optics.alt = { kind = "gps" }
          stations.gunner.sight = nil
        end
      end
      if tur == "spaag" then   -- 搜索雷达、跟踪雷达显示器，光电跟踪器画面
        b:screen(T, 0.22, 0.22, look(V(gx - gs * 0.05, gEye.Y - 0.30, gEye.Z - 0.42), gEye), "ppi", { lightColor = RGB(120, 230, 140), lightK = 0.35 })
        b:screen(T, 0.20, 0.20, look(V(cxp + gs * 0.06, cEye.Y - 0.30, cEye.Z - 0.42), cEye), "ppi", { lightColor = RGB(120, 230, 140), lightK = 0.35 })
      end
    elseif tur == "vulcan" then
      -- 敞开的炮塔（M163「火神」：炮手坐在 20 毫米加特林左边，前面是陀螺测速瞄准具，右边测距雷达的显示器，脚下是弹鼓）
      local gE = V(-0.42, 0.95, -0.05)
      b:cylY(T, 0.04, RR * 1.9, CF(0, 0.02, 0), FLOOR, MAT.DiamondPlate)
      for i = 0, 7 do   -- 炮塔四周的低装甲板（上面敞开）
        local a = (i + 0.5) * PI / 4
        bx(T, RR * 0.85, 0.60, 0.04, math.sin(a) * RR, 0.32, math.cos(a) * RR, WALL2, nil, 0, math.deg(a), 0)
      end
      b:cylY(T, 0.50, 0.70, CF(0.25, 0.30, 0.25), C.gun, MAT.Metal)                        -- 弹鼓
      b:cable(T, { V(0.25, 0.55, 0.25), V(0.22, 0.80, -0.10), V(0.10, 0.90, -0.30) }, 0.08, C.steel, MAT.Metal)
      b:seat(T, CF(gE.X, gE.Y - 0.75, gE.Z + 0.12), { w = 0.42, d = 0.38, back = 0.45, recline = 12, col = RGB(52, 50, 44), post = 0.30 })
      bx(T, 0.16, 0.18, 0.26, gE.X, gE.Y + 0.02, gE.Z - 0.30, RGB(40, 42, 40))             -- 瞄准具
      b:screen(T, 0.10, 0.10, look(V(gE.X + 0.22, gE.Y - 0.12, gE.Z - 0.32), gE), "ppi", { lightColor = RGB(120, 230, 140), lightK = 0.25 })
      b:group("gch", T, CF(gE.X, gE.Y - 0.38, gE.Z - 0.28))
      bx("gch", 0.30, 0.04, 0.05, 0, 0, 0, C.dark, MAT.Metal)
      for _, s in ipairs({ -1, 1 }) do bx("gch", 0.04, 0.12, 0.05, s * 0.15, 0.05, 0, C.rubber, MAT.Fabric) end
      stations.gunner = { g = T, eye = gE + V(0, 0.04, 0.12), look = V(0, -0.1, -1), yaw = 150, up = 80, down = 50, crew = "gunner", sight = true,
        scope = V(gE.X, gE.Y, gE.Z - 0.16), optics = { primary = { kind = "gps" } } }
      crew.gunner = { dress = dress, g = T, eye = gE, lean = -6, yaw = 0, look = V(0, 0, -1),
        hands = { l = { "gch", V(-0.15, 0.08, 0) }, r = { "gch", V(0.15, 0.08, 0) } },
        feet = { l = { T, V(gE.X - 0.12, 0.05, gE.Z - 0.35) }, r = { T, V(gE.X + 0.12, 0.05, gE.Z - 0.35) } } }
      table.insert(order, "gunner")
    elseif tur == "rws" then
      -- 遥控武器站：车长坐在车里（座圈下面），看显示器、握操纵手柄
      local cEye = V(0, RY - 0.30, 0.20)
      b:screen(H, 0.22, 0.16, look(V(0, cEye.Y - 0.20, cEye.Z - 0.42), cEye), "crows", { keys = KEY.crows, lightK = 0.3 })
      b:box(H, V(0.30, 0.10, 0.20), CF(0, cEye.Y - 0.46, cEye.Z - 0.30), C.dark)
      b:group("cch", H, CF(0.10, cEye.Y - 0.40, cEye.Z - 0.30))
      bx("cch", 0.06, 0.14, 0.06, 0, 0.06, 0, C.black)
      b:seat(H, CF(0, cEye.Y - 0.80, cEye.Z + 0.10), { w = 0.42, d = 0.38, back = 0.50, recline = 10, col = RGB(52, 50, 44) })
      local mpage = cn and "cnmap" or "cid"
      b:screen(H, 0.20, 0.15, look(V(-0.32, cEye.Y - 0.22, cEye.Z - 0.30), cEye), mpage, { keys = KEY[mpage], lightColor = RGB(150, 190, 230), lightK = 0.3 })
      stations.commander = { g = H, eye = cEye, look = V(0, -0.2, -1), yaw = 160, up = 70, down = 70, crew = "commander",
        optics = { primary = { kind = "crows", name = "CROWS  M153", g = T, pos = V(0, 0.45, -0.10), dir = "free", fovs = { 30, 9 }, ret = "crows", look = "day", shape = "rect", rws = true } } }
      crew.commander = { dress = dress, g = H, eye = cEye, lean = -6, yaw = 0, look = V(0, -0.25, -1),
        hands = { l = { H, cEye + V(-0.15, -0.42, -0.32) }, r = { "cch", V(0, 0.12, 0) } },
        feet = { l = { H, V(-0.10, FY + 0.10, cEye.Z - 0.40) }, r = { H, V(0.10, FY + 0.10, cEye.Z - 0.40) } } }
      table.insert(order, "commander")
    end

    ---------------- 载员舱（两排长凳面对面，后跳板 / 后门）
    local n = L.troops or 0
    if n > 0 then
      local z0 = math.max(RR + 0.30, (tur == "rws") and 0.70 or 0)
      local per = math.ceil(n / 2)
      local span = zR - z0 - 0.15
      local pitch = math.min(0.60, span / math.max(per, 1))
      local seatY = FY + 0.42
      for _, s in ipairs({ -1, 1 }) do
        for i = 0, per - 1 do
          local z = z0 + 0.30 + i * pitch
          local x = s * (HW - 0.26)
          bx(H, 0.40, 0.07, 0.44, x, seatY, z, RGB(60, 64, 56), MAT.Fabric)                         -- 坐垫
          bx(H, 0.06, 0.50, 0.42, s * (HW - 0.05), seatY + 0.30, z, RGB(60, 64, 56), MAT.Fabric)     -- 靠背（贴在侧壁上）
          b:cable(H, { V(s * (HW - 0.08), seatY + 0.55, z - 0.12), V(x, seatY + 0.30, z - 0.10), V(x, seatY + 0.08, z) }, 0.03, RGB(60, 70, 50))   -- 安全带
        end
        bx(H, 0.05, 0.05, span, s * (HW - 0.10), RY - 0.10, z0 + span / 2 + 0.15, C.lgray, MAT.Metal)   -- 顶上的扶手杆
        for i = 0, per - 1 do   -- 射击孔 / 观察窗
          local z = z0 + 0.30 + i * pitch
          b:periscope(H, look(V(s * (HW - 0.04), RY - 0.22, z), V(s * 3, RY - 0.22, z)), 0.10, 0.07, 0.06, { pad = false })
        end
      end
      -- 后跳板（带小门）/ 后门
      if L.door == "ramp" then
        bx(H, HW * 1.7, hgt * 0.92, 0.08, 0, (FY + RY) / 2, zR, WALL2)
        bx(H, 0.62, hgt * 0.75, 0.03, 0.30, FY + hgt * 0.42, zR - 0.055, WALL)
        b:grab(H, V(0.50, FY + hgt * 0.5, zR - 0.08), V(0.50, FY + hgt * 0.62, zR - 0.08), V(0, 0, -0.05), 0.02, C.black)
        b:placard(H, 0.20, 0.06, CF(-0.40, FY + hgt * 0.6, zR - 0.05) * ANG(0, PI, 0), "RAMP", { bg = C.yellow, fg = C.black })
      else
        bx(H, HW * 2, hgt, 0.06, 0, (FY + RY) / 2, zR, WALL2)
        bx(H, 0.70, hgt * 0.85, 0.04, 0, FY + hgt * 0.45, zR - 0.05, WALL)
        b:grab(H, V(0.28, FY + hgt * 0.45, zR - 0.08), V(0.28, FY + hgt * 0.60, zR - 0.08), V(0, 0, -0.05), 0.02, C.black)
        b:periscope(H, look(V(0, FY + hgt * 0.70, zR - 0.06), V(0, FY + hgt * 0.70, zR + 2)), 0.12, 0.08, 0.06, { pad = false })
      end
      -- 载员舱的东西：电台架、水桶、杂物袋、灭火瓶、灯
      b:radio(H, 0.30, 0.22, 0.24, CF(-(HW - 0.20), RY - 0.25, z0 + 0.05), OD)
      bx(H, 0.18, 0.30, 0.12, HW - 0.15, FY + 0.20, zR - 0.20, RGB(60, 80, 50))
      b:extinguisher(H, CF(HW - 0.16, FY + 0.70, z0 + 0.10), 0.40, 0.12)
      b:light(H, CF(0, RY - 0.08, (z0 + zR) / 2), "dome", RGB(255, 240, 220), 2.6, 0.7)
      b:light(H, CF(0, RY - 0.08, zR - 0.4), "dome", RGB(255, 240, 220), 1.6, 0.4)
      -- 两名载员（坐着，枪立在腿间）
      local tz = z0 + 0.30
      for k, s in ipairs({ -1, 1 }) do
        local key = (k == 1) and "troop" or "troop2"
        local e = V(s * (HW - 0.30), seatY + 0.80, tz + (k - 1) * pitch)
        crew[key] = { dress = cn and "crew_cn" or "crew_us", g = H, eye = e, lean = 4, yaw = 0, look = V(-s, -0.15, 0),
          hands = { l = { H, e + V(-s * 0.35, -0.55, -0.10) }, r = { H, e + V(-s * 0.35, -0.45, 0.08) } },
          feet = { l = { H, V(e.X - s * 0.45, FY + 0.10, e.Z - 0.12) }, r = { H, V(e.X - s * 0.45, FY + 0.10, e.Z + 0.12) } } }
        if k == 1 then
          stations.troop = { g = H, eye = e, look = V(-s, -0.1, 0), yaw = 150, up = 50, down = 60, crew = key,
            optics = { primary = { kind = "port", name = cn and "射击孔观察窗" or "VISION BLOCK", g = H, pos = V(s * (HW + 0.05), RY - 0.22, e.Z),
              dir = "free", fovs = { 40 }, ret = "none", look = "day", shape = "slot" } } }
          table.insert(order, "troop")
        end
      end
    end
    return { stations = stations, order = order, crew = crew, gunK = L.gunK or 0.12, cn = cn }
  end

  ---------------------------------------------------------------- 轮式车 / 卡车的驾驶室
  --   L = { cn, seats = 2 / 4, ring = 后面有射手的炮塔环（悍马）, rws = 遥控武器站显示器（JLTV）, armored = 装甲车（窗小框粗）,
  --     console = 操作员控制台（防空车、火箭炮：雷达 / 火控屏）, gunnerTurret = 一人炮塔（M1117） }
  -- 驾驶室在座圈前面：前风挡在 zF 附近，驾驶员左座、车长右座
  function Defs.cab(b, ctx, L)
    local d = ctx.def
    local H, T = "hull", "turret"
    local piv = ctx.piv or d.turret.pivot   -- 座圈中心（同 Interior 的 frames）
    local cn = L.cn
    local function bx(g, sx, sy, sz, x, y, z, col, mat, rx, ry, rz)
      return b:box(g, V(sx, sy, sz), CF(x, y, z) * ANG(rad(rx or 0), rad(ry or 0), rad(rz or 0)), col, mat)
    end
    local function look(p, at) return CFrame.lookAt(p, at) end
    local DASH = RGB(40, 42, 40)
    local TRIM = L.armored and RGB(196, 196, 186) or RGB(70, 74, 64)
    local glass = {}
    -- 驾驶室范围：车头往后 L.cabZ 米是风挡，宽按车宽
    local zNose = (-d.L / 2 - piv.Z) / S
    local zW = zNose + (L.hood or 1.4)                 -- 风挡下沿
    local FY = (d.clear - piv.Y) / S + 0.25            -- 驾驶室地板
    local HW = d.W / S * 0.43
    local seatZ = zW + 0.95
    local eyeY = FY + 1.15
    local RY = eyeY + 0.30
    local zB = seatZ + ((L.seats == 4) and 1.25 or 0.55)   -- 驾驶室后壁
    local hx = HW * 0.50                                -- 两座的 x
    bx(H, HW * 2, 0.04, zB - zW + 0.5, 0, FY, (zW + zB) / 2 - 0.2, RGB(50, 52, 50), MAT.DiamondPlate)
    bx(H, HW * 2, 0.04, zB - zW, 0, RY, (zW + zB) / 2 + 0.1, TRIM)
    bx(H, HW * 2, RY - FY, 0.05, 0, (FY + RY) / 2, zB, TRIM)
    if L.ring then   -- 悍马的炮塔环（车顶中间的圆口，射手站在后座中间）
      Defs.ring(b, H, 0, RY - 0.02, seatZ + 0.55, 0.42, 20, 0.06, 0.06, C.steel, MAT.Metal)
    end
    -- 仪表台 + 遮光罩 + 中间的电台
    bx(H, HW * 2, 0.30, 0.42, 0, eyeY - 0.55, zW + 0.22, DASH, nil, -8, 0, 0)
    bx(H, HW * 2, 0.04, 0.25, 0, eyeY - 0.38, zW + 0.12, RGB(28, 28, 28), MAT.Fabric)
    b:radio(H, 0.26, 0.20, 0.30, CF(0, eyeY - 0.62, zW + 0.55), cn and RGB(74, 92, 70) or RGB(84, 90, 66))
    b:radio(H, 0.26, 0.16, 0.30, CF(0, eyeY - 0.80, zW + 0.55), cn and RGB(74, 92, 70) or RGB(84, 90, 66))
    bx(H, 0.30, 0.42, 0.70, 0, FY + 0.21, zW + 0.75, DASH)   -- 中间的发动机罩鼓包 / 中控台
    -- 风挡：两块（中间一根柱），侧窗
    local FR = L.armored and 0.07 or 0.04
    for _, s in ipairs({ -1, 1 }) do
      window(b, H, glass, V(s * hx, eyeY + 0.02, zW - 0.02), V(0, -0.25, 1).Unit, V(0, 1, 0.25).Unit, HW * 0.92, L.armored and 0.34 or 0.48, FR)
      window(b, H, glass, V(s * HW, eyeY - 0.02, seatZ - 0.25), V(-s, 0, 0), V(0, 1, 0), 0.60, L.armored and 0.30 or 0.42, FR)
      if L.seats == 4 then window(b, H, glass, V(s * HW, eyeY - 0.02, seatZ + 0.75), V(-s, 0, 0), V(0, 1, 0), 0.55, L.armored and 0.28 or 0.40, FR) end
      bx(H, 0.04, RY - FY, 0.05, s * HW, (FY + RY) / 2, zW - 0.04, TRIM)   -- 风挡边柱
    end
    bar(b, H, V(0, eyeY - 0.24, zW), V(0, RY, zW + 0.08), FR)
    -- 驾驶员：方向盘（跟着转向转）、仪表、踏板；车长：手扶把、电台话筒
    local dX = -hx
    local wc = V(dX, eyeY - 0.40, seatZ - 0.42)
    b:group("swheel", H, look(wc, wc + V(0, -0.6, 1)))
    zring(b, "swheel", 0.20, 16, 0.03, C.rubber, MAT.Fabric)
    b:box("swheel", V(0.38, 0.025, 0.03), CF(), C.dark, MAT.Metal)
    b:box("swheel", V(0.025, 0.19, 0.03), CF(0, -0.095, 0), C.dark, MAT.Metal)
    b:tube(H, wc, wc + V(0, -0.25, -0.35), 0.05, C.gray, MAT.Metal)
    b:screen(H, 0.20, 0.10, look(V(dX, eyeY - 0.34, zW + 0.36), V(dX, eyeY, seatZ)), cn and "drvcn" or "did", { keys = KEY[cn and "drvcn" or "did"], lightK = 0.2 })
    bx(H, 0.10, 0.04, 0.14, dX + 0.12, FY + 0.06, seatZ - 0.85, C.dark, MAT.DiamondPlate, -30, 0, 0)
    bx(H, 0.12, 0.04, 0.14, dX - 0.06, FY + 0.06, seatZ - 0.87, C.dark, MAT.DiamondPlate, -30, 0, 0)
    bx(H, 0.025, 0.20, 0.025, 0.10, FY + 0.48, seatZ - 0.20, C.black, MAT.Metal, -15, 0, 0)   -- 换挡杆
    b:grab(H, V(hx - 0.15, eyeY - 0.40, zW + 0.42), V(hx + 0.15, eyeY - 0.40, zW + 0.42), V(0, 0.06, 0), 0.025, C.black)
    -- 座椅
    local SC = cn and RGB(64, 76, 60) or RGB(92, 86, 66)
    for _, s in ipairs({ -1, 1 }) do
      b:seat(H, CF(s * hx, FY + 0.42, seatZ), { w = 0.46, d = 0.44, back = 0.62, recline = 12, head = true, col = SC })
      if L.seats == 4 then b:seat(H, CF(s * hx, FY + 0.42, seatZ + 0.95), { w = 0.46, d = 0.44, back = 0.60, recline = 10, head = true, col = SC }) end
    end
    -- 操作员控制台（防空车 / 火箭炮 / 爱国者：右座前面一块大屏 + 一块火控屏）
    if L.console then
      b:screen(H, 0.24, 0.18, look(V(hx, eyeY - 0.30, zW + 0.42), V(hx, eyeY, seatZ)), L.console, { lightColor = RGB(120, 230, 140), lightK = 0.3 })
      b:screen(H, 0.16, 0.12, look(V(hx - 0.26, eyeY - 0.36, zW + 0.44), V(hx, eyeY, seatZ)), "afcs", { lightK = 0.2 })
    end
    if L.rws then
      b:screen(H, 0.22, 0.16, look(V(hx, eyeY - 0.32, zW + 0.42), V(hx, eyeY, seatZ)), "crows", { keys = KEY.crows, lightK = 0.3 })
      b:group("cch", H, CF(hx + 0.18, eyeY - 0.58, seatZ - 0.30))
      bx("cch", 0.06, 0.14, 0.06, 0, 0.06, 0, C.black)
    end
    -- 驾驶员面前的一排机械仪表（转速、车速、水温、油压、油量、电压）
    b:screen(H, 0.30, 0.07, look(V(dX, eyeY - 0.24, zW + 0.30), V(dX, eyeY, seatZ)), "gauges", { light = false, ppm = 1800 })
    -- 车门内板（扶手、门把手、摇窗把）、遮阳板、安全带、头顶的开关面板、后窗、枪架、灭火瓶、急救包
    local doors = (L.seats == 4) and { seatZ, seatZ + 0.95 } or { seatZ }
    for _, s in ipairs({ -1, 1 }) do
      for _, z in ipairs(doors) do
        bx(H, 0.05, 0.55, 0.80, s * (HW - 0.02), FY + 0.55, z - 0.15, TRIM)
        bx(H, 0.08, 0.05, 0.36, s * (HW - 0.07), FY + 0.70, z - 0.15, RGB(40, 40, 38))             -- 扶手
        bx(H, 0.03, 0.03, 0.10, s * (HW - 0.07), FY + 0.84, z - 0.42, C.steel, MAT.Metal)          -- 门把手
        b:cyl(H, 0.04, 0.05, CF(s * (HW - 0.06), FY + 0.60, z - 0.30) * ANG(0, 0, PI / 2), C.black) -- 摇窗把
      end
      bx(H, 0.40, 0.02, 0.20, s * hx, RY - 0.05, zW + 0.18, RGB(60, 62, 56), MAT.Fabric, 18, 0, 0)  -- 遮阳板
      b:cable(H, { V(s * (hx + 0.24), eyeY + 0.12, seatZ + 0.22), V(s * (hx - 0.05), eyeY - 0.25, seatZ - 0.08), V(s * (hx - 0.24), FY + 0.48, seatZ + 0.05) }, 0.035, RGB(40, 44, 36))
    end
    b:panel(H, 0.30, 0.14, CFrame.lookAt(V(0, RY - 0.04, seatZ - 0.35), V(0, FY, seatZ - 0.10)), 2, 4, RGB(54, 58, 62))
    window(b, H, glass, V(0, eyeY + 0.05, zB - 0.03), V(0, 0, -1), V(0, 1, 0), 0.50, 0.22, FR)          -- 后窗
    for i = 0, 1 do   -- 两支步枪的枪架（前座之间）
      local x = -0.05 + i * 0.10
      b:box(H, V(0.04, 0.70, 0.08), CF(x, FY + 0.65, seatZ + 0.25) * ANG(rad(-12), 0, 0), RGB(30, 30, 30))
      bx(H, 0.08, 0.03, 0.10, x, FY + 0.40, seatZ + 0.22, C.dark, MAT.Metal)
    end
    b:extinguisher(H, CF(-HW + 0.12, FY + 0.22, zB - 0.20), 0.36, 0.11)
    bx(H, 0.24, 0.16, 0.10, HW - 0.16, RY - 0.12, zB - 0.08, RGB(70, 90, 60))
    b:placard(H, 0.12, 0.06, CF(HW - 0.16, RY - 0.12, zB - 0.135) * ANG(0, PI, 0), cn and "急救" or "FIRST AID", { bg = RGB(70, 90, 60), fg = C.white })
    for _, s in ipairs({ -1, 1 }) do bx(H, 0.40, 0.01, 0.50, s * hx, FY + 0.025, seatZ - 0.60, RGB(28, 28, 28), MAT.Fabric) end   -- 脚垫
    -- 指挥终端（美军车上仪表台中间的 JBC-P 蓝军跟踪终端；我军的北斗指挥终端）
    local mp = cn and "cnmap" or "cid"
    b:screen(H, 0.22, 0.15, look(V(0.02, eyeY - 0.30, zW + 0.40), V(0, eyeY, seatZ)), mp, { keys = KEY[mp], lightColor = RGB(150, 190, 230), lightK = 0.3 })
    b:light(H, CF(0, RY - 0.06, seatZ), "dome", RGB(255, 240, 220), 2.4, 0.6)
    b:name("glass", glass)
    local dress = cn and "crew_cn" or "crew_us"
    local eyeL, eyeR = V(-hx, eyeY, seatZ + 0.02), V(hx, eyeY, seatZ + 0.02)
    local stations = {
      driver = { g = H, eye = eyeL, look = V(0, -0.05, -1), yaw = 150, up = 50, down = 60, crew = "driver" },
      commander = { g = H, eye = eyeR, look = V(0, -0.05, -1), yaw = 150, up = 50, down = 60, crew = "commander" },
    }
    local crew = {
      driver = { dress = dress, g = H, eye = eyeL, lean = 6, yaw = 0, look = V(0, -0.05, -1),
        hands = { l = { "swheel", V(-0.18, 0.04, 0) }, r = { "swheel", V(0.18, 0.04, 0) } },
        feet = { l = { H, V(dX - 0.06, FY + 0.10, seatZ - 0.85) }, r = { H, V(dX + 0.12, FY + 0.10, seatZ - 0.83) } } },
      commander = { dress = dress, g = H, eye = eyeR, lean = 4, yaw = 0, look = V(0, -0.08, -1),
        hands = { l = { H, eyeR + V(-0.18, -0.52, -0.30) }, r = { H, eyeR + V(0.18, -0.52, -0.30) } },
        feet = { l = { H, V(hx - 0.12, FY + 0.10, seatZ - 0.70) }, r = { H, V(hx + 0.12, FY + 0.10, seatZ - 0.70) } } },
    }
    local order = { "driver", "commander" }
    if L.rws then
      crew.commander.hands.r = { "cch", V(0, 0.12, 0) }
      stations.commander.optics = { primary = { kind = "crows", name = "CROWS  M153", g = T, pos = V(0, 0.40, -0.10), dir = "free", fovs = { 30, 9 }, ret = "crows", look = "day", shape = "rect", rws = true } }
    end
    if L.ring then   -- 射手站在后面，上半身伸出炮塔环（吊带座）
      local gE = V(0, RY + 0.35, seatZ + 0.55)
      bx(H, 0.30, 0.04, 0.20, 0, FY + 0.70, seatZ + 0.55, RGB(40, 40, 40), MAT.Fabric)   -- 吊带座
      for _, s in ipairs({ -1, 1 }) do b:tube(H, V(s * 0.14, FY + 0.70, seatZ + 0.55), V(s * 0.30, RY - 0.05, seatZ + 0.55), 0.02, C.black, MAT.Fabric) end
      crew.gunner = { dress = dress, g = T, eye = (CF(-piv / S) * CF(gE)).Position, lean = 0, yaw = 0, look = V(0, -0.05, -1),
        hands = { l = { T, V(-0.20, gE.Y - 0.25 - piv.Y / S, -0.55) }, r = { T, V(0.20, gE.Y - 0.25 - piv.Y / S, -0.55) } },
        feet = { l = { H, V(-0.12, FY + 0.10, seatZ + 0.50) }, r = { H, V(0.12, FY + 0.10, seatZ + 0.60) } } }
      crew.gunner = nil   -- 射手的身子大半在车外（外模型上已经有射手）：车里不画
    end
    if L.gunnerTurret then   -- 一人炮塔（M1117：炮塔里的射手，Mk19 / M2 的瞄准具）
      local gE = V(0, 0.30, 0.0)
      b:cylY(T, 0.03, 1.10, CF(0, gE.Y - 1.10, 0), RGB(50, 52, 50), MAT.DiamondPlate)
      bx(T, 0.18, 0.18, 0.30, 0, gE.Y + 0.02, gE.Z - 0.30, RGB(40, 42, 40))
      b:seat(T, CF(0, gE.Y - 0.80, gE.Z + 0.12), { w = 0.40, d = 0.36, back = 0.40, recline = 8, col = RGB(52, 50, 44), post = 0.30 })
      b:group("gch", T, CF(0, gE.Y - 0.40, gE.Z - 0.28))
      bx("gch", 0.30, 0.04, 0.05, 0, 0, 0, C.dark, MAT.Metal)
      stations.gunner = { g = T, eye = gE + V(0, 0.04, 0.12), look = V(0, -0.15, -1), yaw = 110, up = 45, down = 60, crew = "gunner", sight = true,
        scope = V(0, gE.Y, gE.Z - 0.14), optics = { primary = { kind = "gps" } } }
      crew.gunner = { dress = dress, g = T, eye = gE, lean = -10, yaw = 0, look = V(0, -0.1, -1),
        hands = { l = { "gch", V(-0.15, 0.08, 0) }, r = { "gch", V(0.15, 0.08, 0) } },
        feet = { l = { T, V(-0.12, gE.Y - 1.05, gE.Z - 0.30) }, r = { T, V(0.12, gE.Y - 1.05, gE.Z - 0.30) } } }
      table.insert(order, 2, "gunner")
    end
    return { stations = stations, order = order, crew = crew, gunK = 0.05, cn = cn, glass = glass, cab = true }
  end

  ---------------------------------------------------------------- 各型
  local US, CN = false, true
  local function afv(o) return function(b, ctx) return Defs.afv(b, ctx, o) end end
  local function cab(o) return function(b, ctx) return Defs.cab(b, ctx, o) end end
  Defs.m2a3 = afv({ cn = US, tur = "ifv", gunL = true, troops = 6, door = "ramp", eng = 1.5, gunK = 0.08, drv = { ctrl = "tbar", z = 0.85 },
    opt = { gunnerAlt = { kind = "gas", name = "ISU  DAY  4X", g = "gun", pos = V(0.30, 0.15, 0.30), dir = "gun", fovs = { 18 }, ret = "gas", look = "day", shape = "circle", useSight = true } } })
  Defs.zbd05 = afv({ cn = CN, tur = "ifv", gunL = false, troops = 8, door = "door", eng = 1.6, gunK = 0.08, drv = { z = 0.90 } })
  Defs.zsl92b = afv({ cn = CN, wheeled = true, tur = "ifv", gunL = false, troops = 7, door = "door", eng = 1.5, gunK = 0.08 })
  Defs.ztd05 = afv({ cn = CN, tur = "wedge", gunL = true, eng = 1.7, gunK = 0.30, gunCal = 0.30 })
  Defs.ptl02 = afv({ cn = CN, wheeled = true, tur = "wedge", gunL = true, eng = 1.6, gunK = 0.30, gunCal = 0.30 })
  Defs.stryker = afv({ cn = US, wheeled = true, tur = "rws", troops = 9, door = "ramp", eng = 1.4 })
  Defs.m1150 = afv({ cn = US, tur = "rws", eng = 0, drv = { ctrl = "tbar", z = 1.05 } })
  Defs.mshorad = afv({ cn = US, wheeled = true, tur = "spaag", gunL = true, eng = 1.4, gunK = 0.06, gunCal = 0.16 })
  Defs.pgz07 = afv({ cn = CN, tur = "spaag", gunL = true, eng = 1.6, gunK = 0.0, gunCal = 0.12 })
  Defs.plz07 = afv({ cn = CN, tur = "sph", gunL = true, eng = 1.7, gunK = 0.55, gunCal = 0.36 })
  Defs.m109a7 = afv({ cn = US, tur = "sph", gunL = true, eng = 1.7, gunK = 0.60, gunCal = 0.40, drv = { ctrl = "tbar" } })
  Defs.m163 = afv({ cn = US, tur = "vulcan", eng = 1.5, drv = { ctrl = "tbar" } })
  Defs.hmmwv = cab({ cn = US, seats = 4, ring = true, hood = 1.25 })
  Defs.jltv = cab({ cn = US, seats = 4, rws = true, armored = true, hood = 1.35 })
  Defs.m1117 = cab({ cn = US, seats = 2, armored = true, gunnerTurret = true, hood = 1.10 })
  Defs.pgl625 = cab({ cn = CN, seats = 2, console = "ppi", hood = 0.30 })
  Defs.ld2000 = cab({ cn = CN, seats = 2, console = "ppi", hood = 0.30 })
  Defs.cram = cab({ cn = US, seats = 2, console = "ppi", hood = 0.30 })
  Defs.patriot = cab({ cn = US, seats = 2, console = "ppi", hood = 0.30 })
  Defs.m270 = cab({ cn = US, seats = 2, console = "afcs", armored = true, hood = 0.25 })
end
