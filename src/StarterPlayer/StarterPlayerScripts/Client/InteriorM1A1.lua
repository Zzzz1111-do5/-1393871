-- Roblox全面大战场（客户端）——M1A1 艾布拉姆斯的车内：用原模型自带的炮塔内饰（tools/models/blveh.py 转的 m1a1i，块的 k = "int"）
--   用户 11-23：「有一个带内饰的 m1a1 里面的电脑 观瞄设备和 m1a2 的很像 可以把 m1a1 换成那个 给那个电脑和观瞄设备实现现实中的功能」
--   「你直接用这 m1」「原模型也换成这个」；11-24：「这个圆圈里面是一个镜片 要有光学效果的凸透镜 反光和镀膜做出来」
--   车壳、座椅、炮尾、电台、面板都是模型自己的（VehModels 平时藏着、坐进车里 Interior 显示），这里只在模型的器材上加能用的东西：
--   · 炮长主瞄准镜 GPS：目镜里的凸透镜（B:lens：镀膜、反光、出瞳）；Shift 进镜（Drive 的瞄准镜：昼光 / 热像、3× / 10×、激光测距）
--   · 计算机控制面板 CCP（炮长右手边斜挂的黑盒子）：左边显示窗是活的（InteriorScreens 的 ccp 页），右边 3 × 4 数字键盘每个键都能按
--     （打四位数按 ENT 手动装定距离——弹道计算机按它算超高角）
--   · 目镜右边两块控制面板：倍率拨杆（3X/10X）、视野选择旋钮（DAY/TIS 昼光 / 热像）、热像极性旋钮（WHT/BLK）、弹种选择拨杆（AMMO）——
--     准心对准、左键（看不见的点选块盖在模型的旋钮上，提示条写着是什么）
--   · 辅助瞄准镜 GAS（G）、车长武器站的瞄准镜（T）；车长位：延伸目镜 GPSE 的镜片、两块显示器（上屏战术地图、下屏分系统状态）
--   器材位置都是在原模型里量的（glTF 坐标，米：X 朝车的左边、Y 上、Z 朝前；tools/models/ 下的量法见 docs/interior.md），
--   按元数据的 src 矩阵换到车上（格），再换成内饰坐标（米，相对炮塔座圈中心，X 右、Y 上、−Z 朝前）
local Kit = require(script.Parent:WaitForChild("InteriorKit"))
local V, CF = Vector3.new, CFrame.new
local RGB = Color3.fromRGB
local S = Kit.S

return function(Defs)
  function Defs.m1a1(b, ctx)
    local T, G = "turret", "gun"
    local M = ctx.meta
    local A = M and M.src
    assert(A, "M1A1：原模型的元数据里没有 src（没导入 m1a1i？）")
    local piv = ctx.piv
    -- 原模型 glTF 坐标（米）→ 内饰坐标（米，相对炮塔座圈中心）；D 是方向
    local function P(x, y, z)
      local g = V(A[1][1] * x + A[1][2] * y + A[1][3] * z + A[1][4], A[2][1] * x + A[2][2] * y + A[2][3] * z + A[2][4],
        A[3][1] * x + A[3][2] * y + A[3][3] * z + A[3][4])
      return (g - piv) / S
    end
    local function D(x, y, z)
      return V(A[1][1] * x + A[1][2] * y + A[1][3] * z, A[2][1] * x + A[2][2] * y + A[2][3] * z, A[3][1] * x + A[3][2] * y + A[3][3] * z).Unit
    end
    local function face(p, n, up) return CFrame.lookAt(p, p + n, up or V(0, 1, 0)) end   -- LookVector（−Z）= n：屏幕、键帽的正面朝 n
    local BACK = D(0, 0, -1)   -- 原模型里朝后（对着坐在后面的人）：目镜、控制面板、车长显示器都朝这边

    ---------------- 目镜的镜片（原模型的目镜筒：护眼罩里一个圆孔，GPS 半径 2.6 厘米、GPSE 2.4 厘米，深 5 ～ 6 毫米）
    b:lens(T, CF(P(-0.6045, 1.0148, 0.423)), 0.050, { k = 0.26 })    -- 炮长主瞄准镜 GPS
    b:lens(T, CF(P(-0.4977, 1.3707, -0.341)), 0.046, { k = 0.26 })   -- 车长延伸目镜 GPSE

    ---------------- 计算机控制面板 CCP：面板斜着挂（面朝炮长、往下倾 25°），量的是面板平面里的坐标
    --   u 炮长看过去往右、v 沿面板往上、w 离面板平面（原模型里 0.903x − 0.43y = w 的那一族平面：面板正面 −1.217、显示窗底 −1.221、键盘正面 −1.201）
    local nG, uG = { 0.903, -0.430, 0 }, { 0.430, 0.9028, 0 }
    local function onCCP(u, v, w)
      return P(v * uG[1] + w * nG[1], v * uG[2] + w * nG[2], -u)
    end
    local nC, upC = D(nG[1], nG[2], nG[3]), D(uG[1], uG[2], uG[3])
    -- 显示窗：框里 21.9 × 17.3 厘米（显示面比框里小一圈，贴在窗底前 2 毫米：不和模型抢深度）
    local ccp = b:screen(T, 0.212, 0.166, face(onCCP(-0.17435, 0.42415, -1.219), nC, upC), "ccp",
      { noBack = true, propShell = true, bezel = 0.004, keys = {}, pickM = 0.16, lightK = 0.15, lightRange = 0.7, lightColor = RGB(255, 110, 60) })
    -- 键盘：原模型 12.1 × 15.0 厘米，上面一条是插槽，下面 3 列 × 4 行键；键帽盖在原来的键上（印上字），凸出键盘面 1.5 毫米
    local PAD = { { "1", "2", "3" }, { "4", "5", "6" }, { "7", "8", "9" }, { "CLR", "0", "ENT" } }
    for j, row in ipairs(PAD) do
      for i, t in ipairs(row) do
        local u = -0.0273 + (i - 0.5) * 0.0363
        local v = 0.490 - (j - 0.5) * 0.0295
        b:keyCap(T, ccp, face(onCCP(u, v, -1.1995), nC, upC), 0.031, 0.0245, "CCP " .. t, "dark", { text = t, side = "pad", idx = (j - 1) * 3 + i })
      end
    end

    ---------------- 目镜右边两块控制面板上的旋钮、拨杆：看不见的点选块（按下去也走 CCP 那块屏的按键处理）
    local function hot(x, y, z, w, h, label)
      local key = b:keyCap(T, ccp, face(P(x, y, z), BACK), w, h, label, "dark", { side = "panel" })
      key.Transparency = 1
      for _, ch in ipairs(key:GetChildren()) do if ch:IsA("SurfaceGui") then ch.Enabled = false end end
    end
    hot(-0.819, 1.1645, 0.505, 0.050, 0.060, "3X/10X")    -- 右上面板的拨杆：主瞄准镜倍率
    hot(-0.8195, 1.070, 0.494, 0.045, 0.045, "DAY/TIS")   -- 右上面板的旋钮：视野选择（昼光 / 热像）
    hot(-0.939, 0.798, 0.485, 0.060, 0.060, "WHT/BLK")    -- 右下面板带护圈的大旋钮：热像极性
    hot(-0.7635, 0.790, 0.499, 0.055, 0.065, "AMMO")      -- 右下面板的拨杆：弹种选择开关

    ---------------- 车长面前的两块显示器（原模型这两块屏贴的是同一张分系统状态图）：上屏换成战术地图、下屏是活的分系统状态
    b:screen(T, 0.278, 0.206, face(P(-0.80, 1.505, -0.300), BACK), "cid", { noBack = true, bezel = 0.004, lightK = 0.2, lightColor = RGB(200, 210, 230) })
    b:screen(T, 0.278, 0.196, face(P(-0.80, 1.210, -0.300), BACK), "m1stat", { noBack = true, bezel = 0.004, lightK = 0.2, lightColor = RGB(160, 190, 230) })

    ---------------- 灯：炮塔顶两盏顶灯（白 / 夜里红或蓝绿，L 换）、开炮时从观察镜透进来的火光、挨打时的红色告警
    b:light(T, CF(P(-0.05, 1.68, -0.35)), "dome", RGB(255, 244, 228), 3.2, 1.0)
    b:light(T, CF(P(-0.62, 1.62, 0.20)), "dome", RGB(255, 244, 228), 2.6, 0.8)
    b:light(T, CF(P(-0.55, 1.78, -0.68)), "flash", RGB(255, 196, 120), 4.0, 0)
    b:light(T, CF(P(-0.30, 1.20, 0.10)), "warn", RGB(255, 40, 30), 3.0, 0)

    ---------------- 乘员位
    local gEye = P(-0.6045, 1.030, 0.240)       -- 炮长：目镜后 18 厘米（坐着往前探）
    local cEye = P(-0.4977, 1.400, -0.520)      -- 车长：延伸目镜后 18 厘米
    -- 辅助瞄准镜 GAS（M1A1：8 倍望远镜，装在炮盾右边、跟着炮俯仰）；车长武器站的瞄准镜（指挥塔前面，T 开：鼠标转着看）
    local GAS = { kind = "gas", name = "GAS  8X", g = G, pos = V(0.30, 0.10, 0.05), dir = "gun", fovs = { 8.5 }, ret = "gas", look = "day", shape = "circle", useSight = true }
    local CWS = { kind = "cws", name = "CWS  3X", g = T, pos = P(-0.55, 2.00, -0.45), dir = "free360", fovs = { 28, 9.5 }, ret = "mil", look = "day", shape = "rect" }
    return {
      gunK = 0.305,          -- M256 后坐行程
      carved = true,         -- 坐在乘员位上外壳照样画、显示原模型的车内（Interior 的 extHide）
      modelInt = true,
      stations = {
        gunner = { g = T, eye = gEye, look = V(0, -0.06, -1), yaw = 140, up = 60, down = 60, crew = "gunner", sight = true,
          scope = P(-0.6045, 1.0148, 0.405), optics = { primary = { kind = "gps" }, alt = GAS, third = CWS } },
        commander = { g = T, eye = cEye, look = V(0, -0.12, -1), yaw = 160, up = 70, down = 70, crew = "commander",
          scope = P(-0.4977, 1.3707, -0.360), optics = { primary = { kind = "gps" }, alt = CWS } },
      },
      order = { "gunner", "commander" },
      lock = "gunner",   -- 坦克只锁定在炮长位（同 M1A2）
      crew = {},
    }
  end
end
