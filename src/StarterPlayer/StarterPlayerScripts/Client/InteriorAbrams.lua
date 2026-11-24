-- Roblox全面大战场（客户端）——M1A1 原模型自带的炮塔内饰搬进各车（InteriorDefs 末尾调：require(...)(Defs, 共用件)）
--   用户 11-24：「把 m1a1 内饰部分插件搬到 a2 和 m3 布雷德利里」「自己找 m1a2sepv2 内饰截图，应该和目前 a1 大差不差，按钮什么的实现功能，
--   实现现实中那几块屏幕所有的功能」
--   · 原模型：Sketchfab 上 Muhamad Mirza Arrafi 的 M1A1（带炮塔内饰，CC-BY）。炮塔内饰原来是一整块网格，tools/models/intsplit.py 按连通块拆成 15 块
--     （Int_Shell 炮塔壳、Int_Breech 炮尾、Int_Gun 摇架防危板辅助瞄准镜、Int_GpsEye 炮长目镜、Int_GPanel 目镜右边的控制面板、Int_GHousing 主瞄准镜镜体、
--     Int_Gch 炮长双握把、Int_GSeat、Int_Ccp 炮长右手边的计算机控制面板、Int_Gpse 车长延伸目镜、Int_Cdu 车长两块屏的机壳、Int_Cch 车长操纵握把、
--     Int_CBox 车长右后的控制盒、Int_CSeat、Int_Loader 装填手那一侧），导入后在 ReplicatedStorage.Imported.Veh.m1a1i 里（V_m1a1i__Int_*）
--   · 内饰把这些块克隆进来，按组摆：炮塔、炮（摇架跟着俯仰）、recoil（炮尾环、炮闩：开炮后坐 0.305 米）、gch（双握把跟着炮塔转、炮俯仰的速度摆）
--   · M1A1：原样。M1A2 SEPv2：整套借过来，照 SEPv2 改——车长两块屏是独立热像仪 CITV 和战术显示器（蓝军跟踪、指挥通信、本车状态），
--     两屏之间、右边、下边是 SEPv2 车长显示单元的键；炮长右手边那台计算机换成炮长控制显示面板 GCDP 的软件（主菜单、弹种、装定距离、调整、激光、极性、
--     倍率、火控方式、战斗瞄准、炮口基准、自检）
--   · 原模型上的屏幕、键盘、旋钮、握把上的按钮：我们的显示面、能按的键帽、能转的旋钮盖在原来的位置上（坐标是在原模型上量的，格），
--     每一个都接到真的功能上（Interior 的动作 → Drive.lua 的火控：激光首 / 末回波、火控方式、稳定器、战斗瞄准距离、炮管热弯曲和炮口基准更新、
--     校炮偏差、分划亮度、符号亮度、热像增益 / 电平、视场……）
--   · M2A3 布雷德利：Defs.donorIfv——炮长目镜、目镜旁的面板、车长延伸目镜、车长两块屏、操纵握把、座椅（InteriorAFV 的步战车炮塔调它）
--   · 没导入新的 m1a1i.glb（拆好的块）：A1 / A2 照旧用零件拼的内饰（Defs.m1a2proc），布雷德利照旧
local RS = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent:WaitForChild("InteriorKit"))
local V, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local RGB = Color3.fromRGB
local MAT = Enum.Material
local C = Kit.C
local S = Kit.S
local rad, PI = math.rad, math.pi

local IM = nil
local function meta()
  if IM == nil then
    local ok, r = pcall(function() return require(RS:WaitForChild("ImportedMeta", 3)) end)
    IM = (ok and type(r) == "table") and r or false
  end
  return IM or nil
end
local function v3(t) return V(t[1], t[2], t[3]) end

---------------------------------------------------------------- 供体：导入的原模型块 + 元数据

-- 拆好的块齐了（Int_Shell、Int_Breech……）就用拆好的；只导过拆之前那版（一整块 Int_2）的退回整块（不能借给布雷德利、炮尾不能动）
local function donor(key)
  local M = meta()
  local info = M and M.m and M.m[key]
  if not info then return nil end
  local imp = RS:FindFirstChild("Imported")
  local veh = imp and imp:FindFirstChild("Veh")
  local f = veh and veh:FindFirstChild(key)
  if not f then return nil end
  local n = f:GetAttribute("N")
  if n and #f:GetChildren() < n then return nil end
  local parts = {}
  for name, p in pairs(info.parts) do
    if p.k == "int" then
      local src = f:FindFirstChild("V_" .. key .. "__" .. name)
      if src and src:IsA("BasePart") then parts[name] = { src = src, p = p } end
    end
  end
  local split = parts.Int_Shell ~= nil and parts.Int_Breech ~= nil and parts.Int_GpsEye ~= nil
  if split then parts.Int_2 = nil elseif not parts.Int_2 then return nil end
  return { key = key, info = info, parts = parts, split = split, tur = v3(info.tur), gun = v3(info.gun) }
end

-- 摆一块：组 g；at(c) 把块中心（格，供体坐标）换成组里的位置（米）；rot 转向；k 缩放
local function put(b, D, name, g, at, rot, k)
  local it = D.parts[name]
  if not it then return nil end
  k = k or 1
  local p = b:mesh(g, it.src, v3(it.p.s) * k / S, CF(at(v3(it.p.c))) * (rot or CF()))
  p.CastShadow = true
  return p
end

---------------------------------------------------------------- 原模型上量的点（格，供体 m1a1i 的坐标：原点车底中心，X 右、Y 上、−Z 朝前）

local PT = {
  gps = V(1.653, 5.090, -2.300),       -- 炮长主瞄准镜目镜的后端（护额垫 c160、目镜圈 c169）
  gpse = V(1.352, 6.084, -0.246),      -- 车长的主瞄准镜延伸目镜（目镜筒 c154 的后端、护额垫 c147）
  gasEnd = V(0.902, 4.230, -1.821),    -- 辅助瞄准镜（c121：装在摇架右边的长筒，后端是目镜）
  hub = V(1.484, 3.740, -2.022),       -- 炮长双握把的毂（c165）
  -- 炮长右手边的计算机控制面板（c192 显示窗的框、c206 键盘、c193 面板）：面朝左下（对着炮长），u 人看过去向右、v 向上、w 朝人
  ccp = V(2.519, 4.770, -1.716), ccpU = V(0, 0, 1), ccpV = V(-0.428, 0.904, 0).Unit, ccpW = V(-0.904, -0.428, 0).Unit,
  pad = V(2.484, 4.816, -1.140),
  -- 车长两块屏（原模型的 Int_3 上、Int_1 下：面朝后，对着车长），机壳正面 z −0.306
  scrUp = V(2.193, 6.462, -0.381), scrLow = V(2.194, 5.630, -0.380), housingZ = -0.306,
  cch = V(2.624, 5.159, 0.102),        -- 车长操纵握把（c203 黄色握把），顶上两个按钮 c204、c205
  cchB1 = V(2.543, 5.326, 0.157), cchB2 = V(2.554, 5.381, 0.140),
  palmL = V(1.272, 3.764, -1.976), palmR = V(1.678, 3.764, -1.976),   -- 双握把上的两个拇指按钮（c151、c172）
}

-- 炮长目镜两边面板上的旋钮、拨杆（原模型的件；c 是件的中心，z 用件的正面，dia 米）：
--   原模型面板上的字看不清，功能照 M1A1 / M1A2 炮长位的控制面板（主瞄准镜 / 热像仪控制面板、计算机控制面板、炮长控制面板）分配，
--   每一个都真起作用；旁边贴一条小标签
local KNOBS = {
  -- 目镜右边：热像仪 / 主瞄准镜控制面板
  { id = "RETICLE", c = V(2.061, 4.962, -2.612), dia = 0.034, style = "round", n = 4, step = 60, on = "reticle",
    label = { "分划亮度", "RETICLE BRIGHTNESS" }, pos = { "最亮", "亮", "暗", "最暗" }, posEn = { "MAX", "HIGH", "LOW", "DIM" } },
  { id = "SYMB", c = V(2.504, 4.962, -2.612), dia = 0.034, style = "round", n = 4, step = 60, on = "symb",
    label = { "符号亮度", "SYMBOLOGY BRIGHTNESS" }, pos = { "最亮", "亮", "暗", "关" }, posEn = { "MAX", "HIGH", "LOW", "OFF" } },
  { id = "GAIN", c = V(2.337, 4.766, -2.612), dia = 0.034, style = "round", n = 5, step = 50, on = "gain", state = 2,
    label = { "热像增益（对比度）", "TIS GAIN" }, pos = { "-2", "-1", "0", "+1", "+2" } },
  { id = "LEVEL", c = V(2.503, 4.766, -2.612), dia = 0.034, style = "round", n = 5, step = 50, on = "level", state = 2,
    label = { "热像电平（亮度）", "TIS LEVEL" }, pos = { "-2", "-1", "0", "+1", "+2" } },
  { id = "POL", c = V(2.097, 4.459, -2.623), dia = 0.050, style = "bar", n = 2, step = 60, on = "polaritySet", sync = "pol",
    label = { "热像极性", "TIS POLARITY" }, pos = { "白热", "黑热" }, posEn = { "WHT", "BLK" } },
  { id = "FOV", c = V(2.368, 4.481, -2.583), dia = 0.050, style = "big", n = 5, step = 45, on = "zoomSet", sync = "zoom",
    label = { "视场（倍率）", "FIELD OF VIEW" } },
  { id = "VIS", c = V(2.589, 4.481, -2.583), dia = 0.050, style = "big", n = 2, step = 60, on = "thermalSet", sync = "vis",
    label = { "视野选择", "VISION SELECT" }, pos = { "昼光", "热像" }, posEn = { "DAY", "TIS" } },
  -- 目镜右上：弹种选择、激光回波
  { id = "AMMO", c = V(2.252, 5.507, -2.639), dia = 0.040, style = "bar", n = 4, step = 45, on = "ammoIdx", sync = "ammo",
    label = { "弹种选择", "AMMUNITION SELECT" }, pos = { "穿甲", "破甲", "多用途", "霰弹" }, posEn = { "SABOT", "HEAT", "MPAT", "CAN" } },
  { id = "LRFR", c = V(2.254, 5.244, -2.612), dia = 0.034, style = "round", n = 2, step = 60, on = "lrf", sync = "lrf",
    label = { "激光回波选择", "LRF RETURN" }, pos = { "末回波", "首回波" }, posEn = { "LAST", "FIRST" } },
  -- 目镜下面、左边：火控方式、战斗瞄准、炮口基准更新、稳定器、激光保险、分划夜间照明、自检
  { id = "FCS", c = V(1.622, 4.392, -2.639), dia = 0.040, style = "bar", n = 3, step = 45, on = "fcsSet", sync = "fcs",
    label = { "火控方式", "FCS MODE" }, pos = { "正常", "应急", "手动" }, posEn = { "NORMAL", "EMERG", "MANUAL" } },
  { id = "BSGT", c = V(1.542, 4.740, -2.667), dia = 0.030, style = "push", on = "battlesight",
    label = { "战斗瞄准（距离回到战斗瞄准距离）", "BATTLESIGHT" } },
  { id = "MRSU", c = V(1.659, 4.738, -2.667), dia = 0.030, style = "push", on = "mrs",
    label = { "炮口基准更新（修正炮管热弯曲）", "MRS UPDATE" } },
  { id = "STAB", c = V(1.678, 4.527, -2.675), dia = 0.014, style = "toggle", on = "stab", sync = "stab",
    label = { "稳定器", "STABILIZATION" }, pos = { "开", "关" }, posEn = { "ON", "OFF" } },
  { id = "ARM", c = V(1.848, 4.492, -2.675), dia = 0.014, style = "toggle", on = "lrfArm", sync = "arm",
    label = { "激光测距机", "LRF" }, pos = { "待命", "保险" }, posEn = { "ARMED", "SAFE" } },
  { id = "RETN", c = V(1.566, 5.454, -2.645), dia = 0.034, style = "round", n = 2, step = 60, on = "retNight", sync = "retn",
    label = { "分划照明", "RETICLE ILLUMINATION" }, pos = { "白天（亮红）", "夜间（暗红）" }, posEn = { "DAY", "NIGHT" } },
  { id = "BIT", c = V(1.566, 5.576, -2.665), dia = 0.020, style = "push", on = "bit",
    label = { "火控自检", "FCS BIT" } },
}

---------------------------------------------------------------- 艾布拉姆斯（A1 / SEPv2）

return function(Defs, Hp)
  local procM1A2 = Defs.m1a2
  Defs.m1a2proc = procM1A2

  -- 一个能转、能按的东西（盖在原模型的件上）：cf 是件的正面（−Z 朝人），样子按 style；spec 给 Interior 的可动部件（B:mov）
  local function control(b, g, cf, K, zh)
    b.ctlN = (b.ctlN or 0) + 1
    local gn = "ctl" .. b.ctlN
    b:group(gn, g, cf)
    local d = K.dia
    local kind, hit
    if K.style == "round" or K.style == "big" then   -- 旋钮：黑色圆柱 + 白色指示线（大的带一圈裙边）
      if K.style == "big" then b:cylZ(gn, 0.006, d * 1.18, CF(0, 0, -0.003), RGB(34, 34, 36), MAT.Metal) end
      b:cylZ(gn, 0.012, d, CF(0, 0, -0.008), C.black, MAT.SmoothPlastic)
      b:box(gn, V(0.0025, d * 0.42, 0.002), CF(0, d * 0.22, -0.0145), C.white)
      kind, hit = "knob", { size = V(d * 1.5, d * 1.5, 0.03), cf = CF(0, 0, -0.01) }
    elseif K.style == "bar" then   -- 选择开关：一根带白线的指针形旋钮
      b:cylZ(gn, 0.006, d * 0.85, CF(0, 0, -0.003), RGB(34, 34, 36), MAT.Metal)
      b:box(gn, V(d * 0.30, d * 1.10, 0.012), CF(0, 0, -0.010), C.black, MAT.SmoothPlastic)
      b:box(gn, V(0.002, d * 0.48, 0.002), CF(0, d * 0.26, -0.0165), C.white)
      kind, hit = "knob", { size = V(d * 1.4, d * 1.4, 0.03), cf = CF(0, 0, -0.01) }
    elseif K.style == "toggle" then   -- 拨动开关：拨杆上下两档
      b:box(gn, V(0.012, 0.012, 0.006), CF(0, 0, -0.003), C.steel, MAT.Metal)
      b:group(gn .. "l", gn, CF(0, 0, -0.006))
      b:tube(gn .. "l", V(0, 0, 0), V(0, 0.010, -0.018), 0.005, C.lgray, MAT.Metal)
      kind, hit = "hinge", { size = V(0.026, 0.034, 0.034), cf = CF(0, 0.002, -0.01) }
    else   -- 按钮：按下去、弹回来
      b:cylZ(gn, 0.006, d * 1.25, CF(0, 0, -0.003), RGB(34, 34, 36), MAT.Metal)
      b:cylZ(gn, 0.008, d, CF(0, 0, -0.008), (K.id == "BSGT" or K.id == "BIT") and RGB(40, 40, 40) or RGB(150, 40, 34), MAT.SmoothPlastic)
      kind, hit = "push", { size = V(d * 1.6, d * 1.6, 0.03), cf = CF(0, 0, -0.008) }
    end
    local mv = b:mov((kind == "hinge") and (gn .. "l") or gn, {
      kind = kind, axis = (kind == "hinge") and V(1, 0, 0) or V(0, 0, 1), step = K.step or 45, n = K.n or 2,
      a0 = 0, a1 = -55, d = 0.004, t = (kind == "push") and 0.08 or 0.12, snd = (kind == "push") and "button" or ((kind == "hinge") and "toggle" or "knob"),
      hit = (kind == "hinge") and { size = hit.size, cf = CF(0, 0.002, -0.004) } or hit,
      label = K.label, on = K.on, sync = K.sync, state = K.state or 0, posNames = zh and K.pos or (K.posEn or K.pos), id = K.id,
    })
    -- 小标签（白底黑字，贴在旋钮下面）
    local tw = math.max(0.03, d * 1.6)
    b:placard(g, tw, 0.008, cf * CF(0, -d * 0.75 - 0.006, -0.0005), zh and K.label[1] or K.label[2], { bg = RGB(222, 222, 214), fg = RGB(20, 20, 20), ppm = 2200 })
    return mv
  end

  -- 炮长目镜、车长延伸目镜的镜片（凸透镜 + 增透膜，B:lens）；目镜朝 +Z（对着坐在后面的人）
  local function lenses(b, T, P)
    b:lens(T, CF(P(PT.gps + V(0, 0, -0.07))), 0.060, { face = 1 })
    b:lens(T, CF(P(PT.gpse + V(0, 0, -0.06))), 0.055, { face = 1 })
  end

  -- 一套「供体坐标（格）→ 内饰坐标（米）」的摆法：X(p) 位置，rot 转向（供体里的方向转到内饰里），k 尺寸的倍数
  --   （M1A1 / M1A2 原样 1:1；布雷德利炮塔又小又矮，挪到对应的乘员位上、缩小、有的转个方向）
  local function placer(X, rot, k)
    rot = rot or CF()
    local function cfAt(p, n, up)
      local q = X(p)
      local nn = rot:VectorToWorldSpace(n or V(0, 0, 1))
      local uu = rot:VectorToWorldSpace(up or V(0, 1, 0))
      return CFrame.lookAt(q, q + nn, uu)
    end
    return { X = X, rot = rot, k = k or 1, cf = cfAt }
  end
  -- 目镜旁边面板上的旋钮、拨杆（面板朝 +Z：对着炮长）
  local function knobsBuild(b, T, Pl, list, zh)
    for _, K in ipairs(list) do
      local K2 = K
      if Pl.k ~= 1 then K2 = setmetatable({ dia = K.dia * Pl.k }, { __index = K }) end
      control(b, T, Pl.cf(K.c), K2, zh)
    end
  end
  -- 双握把上的拇指按钮：左手激光回波首 / 末、右手激光测距（gx(p)：供体的点 → 握把组里的位置，米）
  local function palmButtons(b, gx)
    for i, K in ipairs({ { at = PT.palmL, id = "PALML", on = "lrfToggle", label = { "激光回波首 / 末", "LRF FIRST/LAST" } },
      { at = PT.palmR, id = "PALMR", on = "lase", label = { "激光测距", "LASE" } } }) do
      local p = gx(K.at + V(0, 0, 0.03))
      b:group("palm" .. i, "gch", CFrame.lookAt(p, p + V(0, 0, 1)))
      b:cylZ("palm" .. i, 0.008, 0.016, CF(0, 0, -0.004), (i == 2) and RGB(180, 36, 30) or C.black, MAT.SmoothPlastic)
      b:mov("palm" .. i, { kind = "push", axis = V(0, 0, 1), d = 0.004, t = 0.08, snd = "button", hit = { size = V(0.03, 0.03, 0.03), cf = CF(0, 0, -0.006) },
        label = K.label, on = K.on, id = K.id })
    end
  end
  -- 车长两块屏 + 键（原模型的机壳上）：上屏热像（M1A2 SEPv2 的 CITV、布雷德利的 CIV）、下屏战术显示器（蓝军跟踪 / 指挥通信 / 本车状态）；
  --   键排在两屏之间（管上屏：符号、指示、白热 / 黑热、宽 / 窄视场、手动 / 自动扫描、随炮 / 看主瞄准镜）、上屏右边（亮度、扫描扇区左右边、收回）、
  --   下屏右边（本车状态、指挥通信、4 × 4 字母数字键盘）、左下方向键、下屏下边 8 个横杠键（地图、导航、坐标、放大、缩小、叠加、亮度）
  local function cduBuild(b, T, Pl, tag)
    local k = Pl.k
    local function onScr(x, y) return Pl.cf(V(x, y, PT.housingZ + 0.006)) end
    local function scrCF(c) return Pl.cf(V(c.X, c.Y, PT.housingZ - 0.012)) end   -- 显示面在机壳正面后面一点（原模型的屏凹在里面）
    local sUp = b:screen(T, 0.74 / S * k, 0.55 / S * k, scrCF(PT.scrUp), "citv",
      { noBack = true, propShell = true, bezel = 0.006, keys = {}, pickM = 0.12, lightK = 0.3, lightColor = RGB(110, 230, 130), ppm = 1500 })
    local dash = {}
    for i, nm in ipairs({ "MAP", "NAV", "POS", "ZOOM+", "ZOOM-", "OVLY", "BRT+", "BRT-" }) do dash[i] = { nm, (i - 0.5) / 8 } end
    local sLow = b:screen(T, 0.74 / S * k, 0.53 / S * k, scrCF(PT.scrLow), "cid",
      { noBack = true, propShell = true, bezel = 0.006, keys = {}, pickM = 0.16, paper = true, lightK = 0.3, lightColor = RGB(220, 226, 232), ppm = 1500, dash = dash })
    local ROW = { "SYM", "DESIG", "WHT", "BLK", "WFOV", "NFOV", "MAN", "AUTO", "GUN LOS", "GPS LOS" }
    local LED = RGB(70, 255, 110)
    for i, nm in ipairs(ROW) do
      local x = 1.845 + (i - 1) * 0.0775
      b:keyCap(T, sUp, onScr(x, 6.04), 0.066 / S * k, 0.085 / S * k, nm, (i >= 9) and "dark" or "blue", { side = "row", idx = i })
      b:led(T, onScr(x - 0.024, 5.99) * CF(0, 0, -0.005), LED, 0.004, "key", { s = sUp, k = nm })
    end
    for i, nm in ipairs({ "BRT+", "BRT-", "SCAN L", "SCAN R", "STOW" }) do
      b:keyCap(T, sUp, onScr(2.73, 6.72 - (i - 1) * 0.115), 0.20 / S * k, 0.085 / S * k, nm, "blue", { side = "left", idx = i })
    end
    for i, kk in ipairs({ "_PWR", "_SCAN", "_DES" }) do b:led(T, onScr(2.90 + (i - 1) * 0.07, 6.82) * CF(0, 0, -0.004), LED, 0.005, "key", { s = sUp, k = kk }) end
    for i, nm in ipairs({ "VEH SYS", "C3" }) do b:keyCap(T, sLow, onScr(2.69, 5.86 - (i - 1) * 0.115), 0.15 / S * k, 0.085 / S * k, nm, "orange", { side = "left", idx = i }) end
    b:led(T, onScr(2.61, 5.745) * CF(0, 0, -0.004), LED, 0.004, "key", { s = sLow, k = "_MSG" })
    local PAD4 = { { "1", "ABC" }, { "2", "DEF" }, { "3", "GHI" }, { "CLR" }, { "4", "JKL" }, { "5", "MNO" }, { "6", "PQR" }, { "LTR" },
      { "7", "STU" }, { "8", "VWX" }, { "9", "YZ" }, { "NEXT", nil, ">" }, { "." }, { "0" }, { "-" }, { "ENT" } }
    for i, q in ipairs(PAD4) do
      local ci, ri = (i - 1) % 4, math.floor((i - 1) / 4)
      b:keyCap(T, sLow, onScr(2.83 + ci * 0.115, 5.88 - ri * 0.11), 0.098 / S * k, 0.090 / S * k, q[1], "pad", { sub = q[2], text = q[3], side = "pad", idx = i })
    end
    for _, q in ipairs({ { "UP", 0, 0, 1 }, { "DOWN", 180, 0, -1 }, { "LEFT", 270, -1, 0 }, { "RIGHT", 90, 1, 0 } }) do
      b:keyCap(T, sLow, onScr(2.70 + q[3] * 0.075, 5.36 + q[4] * 0.075), 0.07 / S * k, 0.07 / S * k, q[1], "arrow", { dir = q[2], side = "arrow" })
    end
    for i, nm in ipairs({ "MAP", "NAV", "POS", "ZOOM+", "ZOOM-", "OVLY", "BRT+", "BRT-" }) do
      b:keyCap(T, sLow, onScr(1.86 + (i - 1) * 0.0957, 5.255), 0.08 / S * k, 0.06 / S * k, nm, "dash", { side = "bot", idx = i })
    end
    b:led(T, onScr(3.20, 5.25) * CF(0, 0, -0.004), LED, 0.004, "key", { s = sLow, k = "_PWR" })
    b:placard(T, 0.12 * k, 0.014 * k, onScr(2.20, 6.86), tag or "CITV", { bg = RGB(44, 48, 66), fg = C.white })
    return sUp, sLow
  end
  -- 车长操纵握把顶上的两个按钮：指示（猎-歼，炮塔转到热像仪看的方向）、热像仪激光测距并报告敌情（敌人标到全队的地图上）
  local function cchButtons(b, T, Pl)
    for i, K in ipairs({ { at = PT.cchB1, id = "CDES", on = "designate", label = { "指示（猎-歼）", "DESIGNATE" } },
      { at = PT.cchB2, id = "CLASE", on = "citvLase", label = { "车长热像仪激光测距 + 敌情报告", "CITV LASE / SPOT" } } }) do
      b:group("cbtn" .. i, T, Pl.cf(K.at + V(0, 0.02, 0), V(0, 1, 0), V(0, 0, -1)))
      b:cylZ("cbtn" .. i, 0.008, 0.015, CF(0, 0, -0.004), (i == 1) and RGB(190, 40, 32) or C.black, MAT.SmoothPlastic)
      b:mov("cbtn" .. i, { kind = "push", axis = V(0, 0, 1), d = 0.004, t = 0.08, snd = "button", hit = { size = V(0.03, 0.03, 0.03), cf = CF(0, 0, -0.006) },
        label = K.label, on = K.on, id = K.id })
    end
  end

  local function abrams(b, ctx, variant)
    local D = donor("m1a1i")
    if not D or not D.split then return nil end   -- 没导入拆好的新块：照旧零件拼
    local T, G = "turret", "gun"
    local sep = variant == "sep2"
    local zh = false
    local gpM = (ctx.gpiv or Vector3.zero) / S   -- 炮耳轴（炮塔坐标，米）
    local function P(p) return (p - D.tur) / S end   -- 供体的格 → 炮塔坐标的米（座圈中心对座圈中心，真实尺寸 1:1）
    local function inT(p) return P(p) end
    local function inG(p) return P(p) - gpM end
    local hubM = P(PT.hub)
    -- 原模型的块
    for _, name in ipairs({ "Int_Shell", "Int_Loader", "Int_GpsEye", "Int_GPanel", "Int_GHousing", "Int_GSeat", "Int_Ccp", "Int_Gpse", "Int_Cdu", "Int_Cch", "Int_CBox", "Int_CSeat" }) do
      if not (sep and name == "Int_Cdu") then put(b, D, name, T, inT) end   -- SEPv2 的车长显示单元换成钢铁猛兽那台（下面）
    end
    b:group("gch", T, CF(hubM))
    put(b, D, "Int_Gch", "gch", function(c) return P(c) - hubM end)
    put(b, D, "Int_Gun", G, inG)
    b:group("recoil", G, CF())
    put(b, D, "Int_Breech", "recoil", inG)
    lenses(b, T, P)

    -- 炮长右手边的计算机：显示窗（A1 计算机控制面板 CCP / SEPv2 炮长控制显示面板 GCDP）、3 × 4 键盘、两排软键
    local W = PT.ccpW
    local function onCcp(du, dv, dw) return P(PT.ccp + PT.ccpU * du + PT.ccpV * dv + W * (dw or 0)) end
    local function ccpCF(p) return CFrame.lookAt(p, p + W, PT.ccpV) end
    local page = sep and "gcdp2" or "ccp"
    local sc = b:screen(T, 0.56 / S, 0.42 / S, ccpCF(onCcp(0, 0.011, 0.016)), page,   -- 贴在原模型显示窗的框前面（框正面在 +0.011 格）
      { noBack = true, propShell = true, bezel = 0.006, keys = {}, pickM = 0.20, lightK = 0.25, lightColor = sep and RGB(110, 230, 130) or RGB(255, 110, 50), ppm = 1700 })
    local PAD = { { "1" }, { "2" }, { "3" }, { "4" }, { "5" }, { "6" }, { "7" }, { "8" }, { "9" }, { "CLR" }, { "0" }, { "ENT" } }
    local padC = PT.pad + W * 0.024
    for i, q in ipairs(PAD) do
      local ci, ri = (i - 1) % 3, math.floor((i - 1) / 3)
      local p = P(padC + PT.ccpU * ((ci - 1) * 0.105) + PT.ccpV * (0.135 - ri * 0.09))
      b:keyCap(T, sc, ccpCF(p), 0.085 / S, 0.068 / S, "CCP " .. q[1], "pad", { text = q[1], side = "pad", idx = i })
    end
    local rowA = sep and { "MAIN", "AMMO", "RANGE", "ADJUST", "LRF" } or { "SABOT", "HEAT", "MPAT", "CAN", "DATA" }
    local rowB = sep and { "WHT/BLK", "3X/10X", "FCS", "BSGT", "MRS" } or { "TEST", "MRS", "BSGT", "FCS", "LRF" }
    local rowC = sep and { "BIT", "RESET" } or { "AMMO", "DAY/TIS" }
    for i, nm in ipairs(rowA) do b:keyCap(T, sc, ccpCF(onCcp((i - 3) * 0.15, -0.29, 0.03)), 0.125 / S, 0.075 / S, nm, sep and "dark" or "orange", { side = "a", idx = i }) end
    for i, nm in ipairs(rowB) do b:keyCap(T, sc, ccpCF(onCcp((i - 3) * 0.15, -0.42, 0.03)), 0.125 / S, 0.075 / S, nm, sep and "dark" or "orange", { side = "b", idx = i }) end
    for i, nm in ipairs(rowC) do b:keyCap(T, sc, ccpCF(onCcp(0.50 + (i - 1) * 0.16, -0.355, 0.03)), 0.135 / S, 0.08 / S, nm, sep and "blue" or "orange", { side = "c", idx = i }) end
    b:placard(T, 0.10, 0.012, ccpCF(onCcp(-0.25, 0.27, 0.03)), sep and "GCDP" or "COMPUTER CONTROL PANEL", { bg = C.black, fg = C.white })

    -- 目镜两边的旋钮、拨杆（每一个都真起作用，见 KNOBS）；目镜下面的小绿灯：热像通道开着
    local Pl = placer(P, CF(), 1)
    knobsBuild(b, T, Pl, KNOBS, zh)
    b:led(T, CF(P(V(2.680, 4.746, -2.633))), RGB(90, 255, 120), 0.009, "tis")
    -- 双握把上的拇指按钮：左手激光回波首 / 末、右手激光测距（握把真车上：掌压开关、右手拇指激光按钮、食指扳机）
    palmButtons(b, function(q) return P(q) - hubM end)

    -- 车长那两块屏
    if sep then
      -- SEPv2：上屏独立热像仪 CITV、下屏战术显示器（蓝军跟踪 / 指挥通信 / 本车状态）——
      --   用户 11-24 又发来钢铁猛兽 M1A2 车长位的截图（11-23 那套「严格按照这个图」）：左边一列蓝键、两屏之间一排蓝键、右边橙色字母数字键盘、
      --   下边橙色横杠键、左下橙色方向键。用零件拼的 M1A2 那台（Defs.sbCdu：ip_cdus 机壳 + CdusLayout 版面，功能一样），
      --   摆在原模型机壳正面的位置，往车长那边转 15°
      local front = P(V(2.28, 6.047, PT.housingZ))   -- 原机壳中心 x 2.483：这台窄一点、转过来，右边会插进炮塔壁，往左挪 7 厘米
      local th = rad(-15)
      if Defs.sbCdu then
        Defs.sbCdu(b, T, CFrame.lookAt(front, front + V(math.sin(th), 0, math.cos(th))))
      else
        put(b, D, "Int_Cdu", T, inT)
        cduBuild(b, T, Pl, "CITV")
      end
      cchButtons(b, T, Pl)
    else
      -- A1：原模型这两块屏的版面（FLIR、PWR、CITV、SGF、CEU、FCEU、CCHA 七格）是车长的状态显示器
      b:screen(T, 0.74 / S, 0.55 / S, Pl.cf(V(PT.scrUp.X, PT.scrUp.Y, PT.housingZ - 0.012)), "m1stat", { noBack = true, propShell = true, bezel = 0.006, lightK = 0.25, lightColor = RGB(120, 150, 220), ppm = 1500 })
      b:screen(T, 0.74 / S, 0.53 / S, Pl.cf(V(PT.scrLow.X, PT.scrLow.Y, PT.housingZ - 0.012)), "m1stat", { noBack = true, propShell = true, bezel = 0.006, lightK = 0.25, lightColor = RGB(120, 150, 220), ppm = 1500 })
    end

    -- 灯：炮塔两盏顶灯、开炮时从观察镜透进来的火光、挨打时的红色告警
    b:light(T, CF(P(V(-1.40, 6.70, 0.40))), "dome", RGB(255, 244, 228), 3.4, 1.1)
    b:light(T, CF(P(V(1.60, 6.60, -1.30))), "dome", RGB(255, 244, 228), 3.0, 1.0)
    b:light(T, CF(P(V(1.30, 6.90, 0.50))), "flash", RGB(255, 196, 120), 4.0, 0)
    b:light(T, CF(P(V(0.40, 5.60, -1.40))), "warn", RGB(255, 40, 30), 3.0, 0)

    -- 乘员位（坦克锁在炮长位：Interior 按 lock 锁；车长的主观瞄挪到炮长位的 T）
    local gEye = P(V(1.653, 5.330, -1.720))
    local cEye = P(V(1.352, 6.150, 0.300))
    local lEye = P(V(-1.720, 6.200, 0.400))
    local gas = PT.gasEnd
    local stations = {
      gunner = { g = T, eye = gEye, look = V(0.05, -0.22, -1), yaw = 125, up = 50, down = 62, crew = "gunner", sight = true, scope = P(PT.gps),
        optics = { primary = { kind = "gps" },
          alt = { kind = "gas", name = "GAS  M920  8X", g = G, pos = inG(gas + V(0, 0, 0.05)), dir = "gun", fovs = { 8.5 }, ret = "gas", look = "day", shape = "circle", useSight = true } } },
      commander = { g = T, eye = cEye, look = V(0.05, -0.30, -1), yaw = 160, up = 70, down = 70, crew = "commander", scope = P(PT.gpse),
        optics = sep and { primary = { kind = "citv", name = "CITV  2ND GEN FLIR", g = T, pos = V(-0.45, 1.05, -0.75), dir = "citv", fovs = { 23.3, 11.7, 5.4, 2.8, 1.4 },
          ret = "citv", look = "whot", shape = "rect" }, alt = { kind = "gps" } } or { primary = { kind = "gps" } } },
      loader = { g = T, eye = lEye, look = V(0.45, -0.20, -1), yaw = 170, up = 70, down = 75, crew = "loader",
        optics = { primary = { kind = "lscope", name = "LOADER'S PERISCOPE", g = T, pos = V(-0.62, 0.92, -0.12), dir = "free360", fovs = { 38 }, ret = "none", look = "day", shape = "slot" } } },
    }
    -- 坐在车里时外模型里伸进乘员舱的块不画（Interior 的 extHide）：炮塔壳的框（炮塔坐标，格）往里收 0.3 格
    local sh = D.parts.Int_Shell.p
    local box = { c = v3(sh.c) - D.tur, s = v3(sh.s) - V(0.6, 0.6, 0.6) }
    return {
      gunK = 0.305,   -- M256 后坐行程
      loader = "m256",
      modelInt = true, carved = true, crewBox = box,
      stations = stations,
      order = { "gunner", "commander", "loader" },
      lock = "gunner",
      crew = {},
      abrams = variant,
    }
  end

  ---------------------------------------------------------------- 布雷德利（M2A3）：借炮长 / 车长位那几件
  -- 炮塔又小又矮（座圈上面只有半米多净高）、炮长在左、车长在右、中间是 25 毫米炮的炮尾——M1A1 的件挪到对应的乘员位上、缩小，目镜旁的面板转过来贴在左边炮塔壁上；
  --   旋钮按布雷德利的功能分（炮长的综合瞄准具 IBAS 控制：视野、极性、视场、增益、电平、分划 / 符号亮度；射速 高速 / 低速 / 单发、武器选择 25 毫米炮 / 并列机枪、
  --   武器总开关、稳定器、分划照明）；车长两块屏是独立热像观察仪 CIV + 战术显示器（同 SEPv2 那套键），握把上指示、CIV 激光测距 + 敌情报告
  local function byId(id) for _, K in ipairs(KNOBS) do if K.id == id then return K end end end
  local IFV_PANEL = { byId("RETICLE"), byId("SYMB"), byId("GAIN"), byId("LEVEL"), byId("POL"), byId("FOV"), byId("VIS"),
    { id = "ROF", c = V(2.252, 5.507, -2.639), dia = 0.040, style = "bar", n = 3, step = 45, on = "rof", sync = "rof",
      label = { "射速选择", "RATE SELECT" }, pos = { "高速（每分 200 发）", "低速（每分 100 发）", "单发" }, posEn = { "HI 200", "LO 100", "SS" } },
    { id = "WPN", c = V(2.254, 5.244, -2.612), dia = 0.034, style = "round", n = 2, step = 60, on = "weapon", sync = "wpn",
      label = { "武器选择", "WEAPON SELECT" }, pos = { "25 毫米炮", "并列机枪" }, posEn = { "25MM", "COAX" } } }
  local IFV_EYE = { byId("STAB"), byId("RETN"),
    { id = "ARMG", c = V(1.622, 4.392, -2.639), dia = 0.040, style = "bar", n = 2, step = 60, on = "armGun", sync = "armg",
      label = { "武器总开关", "ARM / SAFE" }, pos = { "待发", "保险" }, posEn = { "ARM", "SAFE" } } }
  -- geo：InteriorAFV 步战车炮塔的尺寸和乘员位（米）：gs 炮长在哪边（−1 左）、gx、gEye、cxp、cEye、TH 炮塔净高、tw 炮塔半宽；
  --   返回 { gScope 炮长目镜, cScope 车长目镜 }（乘员位用），没导入拆好的 m1a1i 返回 nil（照旧零件拼）
  function Defs.donorIfv(b, ctx, geo)
    local D = donor("m1a1i")
    if not D or not D.split then return nil end
    local T = "turret"
    local gs = geo.gs or -1
    local function mapper(from, to, rot, k)
      rot = rot or CF()
      return function(p) return to + rot:VectorToWorldSpace((p - from) / S * k) end
    end
    local function putM(name, g, X, rot, k, base)
      local it = D.parts[name]
      if not it then return end
      b:mesh(g, it.src, v3(it.p.s) * k / S, CF(X(v3(it.p.c)) - (base or Vector3.zero)) * (rot or CF()))
    end
    -- 炮长：目镜对着炮长的眼睛（缩到 0.75：顶上那块高面板不顶出炮塔）
    local kG = 0.75
    local gScope = V(geo.gx, geo.TH - 0.23, geo.gEye.Z - 0.14)
    local XG = mapper(PT.gps, gScope, CF(), kG)
    putM("Int_GpsEye", T, XG, CF(), kG)
    putM("Int_GSeat", T, mapper(V(1.46, 2.64, -1.49), V(geo.gx, geo.gEye.Y - 0.80, geo.gEye.Z + 0.10), CF(), 0.8), CF(), 0.8)
    local hub = XG(PT.hub)
    b:group("gch", T, CF(hub))
    putM("Int_Gch", "gch", XG, CF(), kG, hub)
    b:lens(T, CF(XG(PT.gps + V(0, 0, -0.07))), 0.060 * kG, { face = 1 })
    knobsBuild(b, T, placer(XG, CF(), kG), IFV_EYE, false)
    palmButtons(b, function(q) return XG(q) - hub end)
    -- 目镜旁的控制面板：转 90° 贴在炮长外侧的炮塔壁上，面朝炮长
    local rotP = ANG(0, (gs < 0) and PI / 2 or -PI / 2, 0)
    local panC = v3(D.parts.Int_GPanel.p.c)
    local XP = mapper(panC, V(gs * (geo.tw - 0.10), math.min(0.20, geo.TH - 0.30), geo.gEye.Z - 0.12), rotP, kG)
    putM("Int_GPanel", T, XP, rotP, kG)
    knobsBuild(b, T, placer(XP, rotP, kG), IFV_PANEL, false)
    b:led(T, CF(XP(V(2.680, 4.746, -2.633))), RGB(90, 255, 120), 0.007, "tis")
    -- 炮长的综合瞄准具显示器（用户 11-24 发来的 M3 车内截图：目镜右下一块四周一圈方键的显示器，绿色热像、括号分划）：
    --   夹在目镜和炮尾护栏之间（护栏已经收窄到 25 毫米炮的宽度），正对炮长的眼睛；上下两排键是屏幕自带的，左右各三个方键
    local eyeG = gScope + V(0, 0.06, 0.26)
    local dp = V(gScope.X - gs * 0.16, gScope.Y - 0.068, gScope.Z - 0.11)   -- 左边离目镜块、右边离护栏都留几毫米
    local dcf = CFrame.lookAt(dp, eyeG)
    local IW, IH, IB = 0.13, 0.10, 0.018
    local ibas = b:screen(T, IW, IH, dcf, "ibas", { keys = { top = { "FOV", "POL", "GAIN", "LVL", "SYM" }, bottom = { "TIS", "LRF", "F/L", "RET", "TEST" } },
      bezel = IB, lightK = 0.25, lightColor = RGB(110, 230, 130) })
    for i, nm in ipairs({ "ROF", "WPN", "ARM" }) do   -- 人看过去的左边是屏幕的 +X
      b:keyCap(T, ibas, dcf * CF(IW / 2 + IB * 0.6, 0.03 - (i - 1) * 0.03, -0.004), 0.014, 0.014, nm, "dark", { side = "left", idx = i })
    end
    for i, nm in ipairs({ "BSGT", "STAB", "BRT" }) do
      b:keyCap(T, ibas, dcf * CF(-(IW / 2 + IB * 0.6), 0.03 - (i - 1) * 0.03, -0.004), 0.014, 0.014, nm, "dark", { side = "right", idx = i })
    end
    -- 车长：延伸目镜（看炮长综合瞄准具的画面）
    --   人（连目镜、座椅）往炮那边挪 6 厘米：右前方给两块屏的机壳腾地方，不然机壳贴着炮塔壁也躲不开目镜的护额垫
    local kC = 0.8
    local cx = geo.cxp + gs * 0.06
    local cScope = V(cx, geo.TH - 0.20, geo.cEye.Z - 0.14)
    local XC = mapper(PT.gpse, cScope, CF(), kC)
    putM("Int_Gpse", T, XC, CF(), kC)
    b:lens(T, CF(XC(PT.gpse + V(0, 0, -0.06))), 0.055 * kC, { face = 1 })
    -- 延伸目镜两边（用户 11-24 的 M3 截图）：右边一个圆表盘，左边一块小面板——两个红灯（电源、热像），两个旋钮（视野选择、极性，跟炮长那边同步）
    local gpE = XC(PT.gpse)
    local dialC = gpE + V(0.115, -0.025, -0.06)
    b:cylZ(T, 0.03, 0.078, CF(dialC), RGB(30, 32, 34), MAT.Metal)
    b:cylZ(T, 0.004, 0.062, CF(dialC + V(0, 0, 0.016)), RGB(10, 12, 12), MAT.Glass)
    b:box(T, V(0.003, 0.026, 0.002), CF(dialC + V(0, 0.005, 0.019)) * ANG(0, 0, rad(-35)), RGB(232, 232, 226))
    local pc = gpE + V(-0.125, -0.03, -0.06)
    b:box(T, V(0.07, 0.09, 0.022), CF(pc), RGB(34, 36, 36), MAT.SmoothPlastic)
    b:led(T, CF(pc + V(-0.016, 0.03, 0.012)), RGB(255, 40, 30), 0.008)
    b:led(T, CF(pc + V(0.016, 0.03, 0.012)), RGB(255, 40, 30), 0.008, "tis")
    for i, K in ipairs({
      { id = "CVIS", dia = 0.024, style = "round", n = 2, step = 60, on = "thermalSet", sync = "vis", label = { "延伸目镜：视野选择", "SIGHT EXT  DAY / TIS" }, pos = { "昼光", "热像" }, posEn = { "DAY", "TIS" } },
      { id = "CPOL", dia = 0.024, style = "bar", n = 2, step = 60, on = "polaritySet", sync = "pol", label = { "延伸目镜：极性", "SIGHT EXT  POLARITY" }, pos = { "白热", "黑热" }, posEn = { "WHT", "BLK" } } }) do
      local kp = pc + V((i == 1) and -0.016 or 0.016, -0.012, 0.011)
      control(b, T, CFrame.lookAt(kp, kp + V(0, 0, 1)), K, false)
    end
    -- 两块屏的机壳：车长右前方（看过去偏右 52°）、比眼睛略低，转过来对着车长——
    --   延伸目镜就在眼前（护额垫左右各挡 ~23°），机壳放在它正后面会把上面那块 CIV 屏挡掉；屏的左边要在 ~30° 以外；外边贴着炮塔壁（壁内面 tw − 0.02）
    local cE = cScope + V(0, 0.05, 0.24)   -- 车长位的眼睛（InteriorAFV 的 stations.commander.eye）
    local kD = 0.52
    local aD, rD = rad(52), 0.34
    local lim = geo.tw - 0.19
    local dc = V(math.clamp(cE.X - gs * rD * math.sin(aD), -lim, lim), cE.Y - 0.05, cE.Z - rD * math.cos(aD))
    local rotD = ANG(0, math.atan2(cE.X - dc.X, cE.Z - dc.Z), 0)
    local XD = mapper(v3(D.parts.Int_Cdu.p.c), dc, rotD, kD)
    putM("Int_Cdu", T, XD, rotD, kD)
    cduBuild(b, T, placer(XD, rotD, kD), "CIV")
    -- 车长操纵握把（右手边，机壳底下）、座椅
    local kH = 0.72
    local XH = mapper(PT.cch, V(-gs * (geo.tw - 0.20), geo.cEye.Y - 0.48, geo.cEye.Z + 0.02), CF(), kH)
    putM("Int_Cch", T, XH, CF(), kH)
    cchButtons(b, T, placer(XH, CF(), kH))
    putM("Int_CSeat", T, mapper(V(1.46, 4.03, 1.05), V(cx, geo.cEye.Y - 0.78, geo.cEye.Z + 0.12), CF(), 0.8), CF(), 0.8)
    return { gScope = gScope, cScope = cScope }
  end

  Defs.m1a1 = function(b, ctx) return abrams(b, ctx, "a1") or procM1A2(b, ctx) end
  Defs.m1a2 = function(b, ctx) return abrams(b, ctx, "sep2") or procM1A2(b, ctx) end
  Defs.m10 = procM1A2   -- M10 布克：照旧借零件拼的 M1A2 内饰（四人、手动装填，火控同源）
  Defs.donor, Defs.donorPut, Defs.donorPT, Defs.donorControl, Defs.donorKnobs = donor, put, PT, control, KNOBS
end
