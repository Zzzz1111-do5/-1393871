-- 全面大战场（客户端）——整备的「挂载」页（飞机、直升机；外壳是 Workshop.lua，零件是 WsKit.lua）
--   用户 11-27：「整个给载具配置武器的系统 做的很粗糙 我需要非常艺术经验的效果 参考战雷」——照同类写实军事游戏的做法（按挂点一个个配、换了 3D 马上跟着变、
--   写清楚正在改的是哪一套、重量和阻力数字比条重要），用我们自己的界面美术（docs/style.md）：
--   舞台就是机库的停机坪（HangarStage：真光照、Highlight 描轮廓），起落架放着、弹舱打开、直升机旋翼停着；界面压在上面：
--   · 底部条：航炮（固定）│ 挂点卡（从左翼尖排到右翼尖；左右对称时一对合成一张、手机上横着滚）│ 左右对称开关、干扰弹（没研究锁住，点了去改装页）
--   · 机身上每个挂点：6 像素的点、一根引线、一张小标签「3 · 霹雳-15」（每帧按 HangarStage.toScreen 摆，标签排在飞机下面一条线上、互相不压；
--     空挂点淡色空心圈「空」；选中的琥珀；镜头那一侧对面的挂点淡一点）
--   · 左栏：方案（这一型的预设 + 三个「我的方案」，照哪套改过写「已改」）、选中挂点能挂的武器卡（最后一张虚线框「不挂」）；
--     鼠标挂在一张上：3D 先换上（停一下才换，扫过去不来回重搭）、右栏显示变化（琥珀）、旁边浮出这枚弹的资料；点一下装上（3D 里从挂架下滑上去、
--     琥珀轮廓亮一下淡掉）；左右对称时一对一起换（同 Hangar.lua）
--   · 右栏：这一套的外挂重量、阻力（ΔCD0）、起飞重量；性能对比空挂（极速、推重比、持续转弯、爬升、翼载）；内油四档——
--     全部用飞行物理同一套算（FlightModel.loadout / perf：开飞机 Fly.lua 用的就是 loadout），不另编数；外挂重量上限仓库里没有数据，先不画上限。
--     直升机没有喷气机的飞行物理：只写重量（Fly.lua 直升机用的 AD.heavy）、续航（AD.fuelMin）、极速（副油箱的阻力，同 Fly.lua 的式子）
--   · 镜头：全景从左前下方看（按飞机大小、两栏中间那一段算距离），点一个挂点飞到它那一侧（偏航 ±125°，弹舱从下往上看）；没选挂点、几秒没动时慢慢转
--   改动即时存（Tech.lua treeLoad，不弹提示）：出击、试驾都按它；「我的方案」存在 treeLoadSet
local RS = game:GetService("ReplicatedStorage")

local WsArms = {}

function WsArms.new(G, ws)
  local K = ws.K
  local TH = K.TH
  local C, A, S = TH.C, TH.A, TH.S
  local AD = require(RS:WaitForChild("AirDefs"))
  local WMd = require(RS:WaitForChild("WtMods"))
  local FMok, FM = pcall(function() return require(RS:WaitForChild("FlightModel", 10)) end)
  if not FMok then FM = nil end
  local T = ws.T
  local LAY = ws.LAY
  local compact = ws.compact
  local UD2, V2, V3 = UDim2.new, Vector2.new, Vector3.new
  local RIGHT, CENTER = Enum.TextXAlignment.Right, Enum.TextXAlignment.Center

  local P = { name = "arms" }
  local st = nil   -- 打开着的这一架（见 P.open）

  ---------------------------------------------------------------- 字

  -- 武器的短名（卡片上）：aws.<型号>，没有就用全名
  local function wname(wid)
    if not wid then return T("ws.none") end
    local s = T("aws." .. wid)
    if s == "aws." .. wid then s = T("aw." .. wid) end
    if s == "aw." .. wid then s = string.upper(wid) end
    return s
  end
  local function catOf(w)
    if w.kind == "tank" then return "tank" end
    if w.arm then return "arm" end
    if w.kind == "bomb" then return w.guided and "gbomb" or "bomb" end
    return w.kind
  end
  -- 「空空导弹 · 主动雷达」（长）/「空空 · 雷达」（短）
  local function subOf(w, short)
    local c = T((short and "wcs." or "wcat.") .. catOf(w))
    if w.kind == "tank" or w.kind == "rkt" or w.kind == "gun" then return c end
    local g = w.guide or "none"
    return c .. " · " .. T((short and "gds." or "guide.") .. g)
  end
  local function km(v) return string.format("%.1f", (v or 0) / AD.M / 1000) end
  local function f1(v) return string.format("%.1f", v) end
  local function f2(v) return string.format("%.2f", v) end
  -- 卡片上那一行数：射程、锁定、一个挂点几枚（火箭巢写几发、副油箱写加几成油）
  local function numsOf(s, wid)
    local w = AD.W[wid]
    if not w then return "" end
    local n = AD.count(s, wid)
    if w.kind == "tank" then return T("ws.tankAdd", math.floor(w.fuel * n * 100 + 0.5)) end
    local parts = {}
    if w.kind == "rkt" then
      table.insert(parts, T("ws.tubes", w.tubes or n))
      if w.range then table.insert(parts, km(w.range) .. " km") end
      return table.concat(parts, " · ")
    end
    if w.range then table.insert(parts, km(w.range) .. " km") end
    if w.lockTime and w.lockTime > 0 then table.insert(parts, T("ws.lockS", f1(w.lockTime))) end
    if n > 1 then table.insert(parts, "×" .. n) end
    if #parts == 0 then table.insert(parts, T("gds." .. (w.guide or "none"))) end
    return table.concat(parts, " · ")
  end
  -- 挂点在哪（翼尖 / 外侧 / 中段 / 内侧 / 机腹……）：按挂点名字；弹舱按 bay
  local POS = { tip = "tip", outer = "outer", wingO = "outer", pylO = "outer", railO = "outer", mid = "mid", pylM = "mid",
    inner = "inner", wingI = "inner", pylI = "inner", railI = "inner", wing = "wing", pylon = "wing", gloveO = "glove", gloveI = "glove",
    ctr = "ctr", body = "body", duct = "duct", stub = "stub", tunF = "tun", tunA = "tun", fusF = "fus", fusA = "fus" }
  local function posName(s)
    if s.bay then return T((s.bay == "main") and "ws.pos.bay" or "ws.pos.bayS") end
    return T("ws.pos." .. (POS[s.name] or "gen"))
  end

  ---------------------------------------------------------------- 挂载、性能

  local function sigOf(load)
    local s = {}
    for i = 1, #(st.d.st or {}) do s[i] = (load and load[i]) or "" end
    return table.concat(s, ",")
  end
  local function same(a, b)
    for i = 1, #(st.d.st or {}) do if ((a and a[i]) or false) ~= ((b and b[i]) or false) then return false end end
    return true
  end
  -- 直升机挂副油箱以后的极速（格 / 秒）：同 Fly.lua 直升机的式子——桨盘前倾到底时水平拉力 GS·tan(最大倾角) = 0.05·v + cq·(1 + 阻力)·v²，
  --   cq 按「不挂副油箱正好飞到型号表的 vMax」定
  local function heliTop(d, drag)
    local GS = AD.GRAV or 27.5
    local C0 = GS * math.tan(math.rad(d.tilt or 22))
    local vM = d.vMax or 90
    local cq0 = math.max(1e-5, (C0 - 0.05 * vM) / (vM * vM))
    local cq = cq0 * (1 + (drag or 0))
    return (-0.05 + math.sqrt(0.0025 + 4 * cq * C0)) / (2 * cq)
  end
  -- 一套挂载的数（按挂载 + 内油记着：同一套不重算）
  local function perfOf(load, fuel)
    local key = sigOf(load) .. "|" .. string.format("%.2f", fuel)
    local c = st.perf[key]
    if c then return c end
    local Lo = { ext = 0, xf = 0, dS = 0 }
    if FM and FM.loadout then
      local ok, r = pcall(FM.loadout, st.d, load, fuel, { key = st.key, AD = AD })
      if ok and r then Lo = r end
    end
    c = { Lo = Lo }
    if st.D and Lo.m and FM and FM.perf then
      local ok, p = pcall(FM.perf, st.D, Lo.m, Lo.dCD0)
      if ok then c.p = p end
    end
    local tf, drag = AD.tankFuel(st.d, load)
    c.tf, c.drag = tf, drag
    c.heavy = AD.heavy(st.d, fuel, tf)
    c.min = AD.fuelMin(st.d, fuel + tf)
    c.minX = (tf > 0) and AD.fuelMin(st.d, tf) or 0
    if st.d.kind == "heli" then c.vh = heliTop(st.d, drag) end
    st.perf[key] = c
    return c
  end
  G.wsPerfOf = function(load, fuel) return st and perfOf(load, fuel) end   -- 测试用：界面上的数按这个写

  ---------------------------------------------------------------- 卡片分组、编号

  -- 挂点编号：照真飞机从左翼尖到右翼尖 1、2、3……（同一个横坐标的前面的先）
  local function numberStations()
    local d = st.d
    local order = {}
    for i in ipairs(d.st or {}) do order[#order + 1] = i end
    table.sort(order, function(a, b)
      local pa, pb = d.st[a].pos, d.st[b].pos
      if math.abs(pa.X - pb.X) > 1e-3 then return pa.X < pb.X end
      return pa.Z < pb.Z
    end)
    st.num = {}
    for k, i in ipairs(order) do st.num[i] = k end
  end
  -- 底部的卡：左右对称时同名的一对合成一张（从翼尖往里排、机腹中线的在最后）；不对称时一个挂点一张（从左翼尖排到右翼尖）
  local function makeGroups()
    local d = st.d
    local out, byName = {}, {}
    for i, s in ipairs(d.st or {}) do
      local g = st.sym and byName[s.name] or nil
      if not g then
        g = { st = {}, name = s.name }
        if st.sym then byName[s.name] = g end
        table.insert(out, g)
      end
      table.insert(g.st, i)
    end
    for _, g in ipairs(out) do
      table.sort(g.st, function(a, b) return d.st[a].pos.X < d.st[b].pos.X end)
      local s0 = d.st[g.st[1]]
      g.x, g.z, g.bay = s0.pos.X, s0.pos.Z, s0.bay
      local nums = {}
      for _, i in ipairs(g.st) do table.insert(nums, tostring(st.num[i])) end
      g.label = table.concat(nums, "·")
    end
    table.sort(out, function(a, b)
      if math.abs(a.x - b.x) > 1e-3 then return a.x < b.x end
      return a.z < b.z
    end)
    st.cards = out
  end
  local function cardOfStation(i)
    for ci, g in ipairs(st.cards or {}) do
      for _, j in ipairs(g.st) do if j == i then return ci end end
    end
    return nil
  end
  -- 这张卡现在挂的（一对里两边不一样时 mixed）
  local function cardWeapon(g, load)
    load = load or st.load
    local w0 = load[g.st[1]] or false
    local mixed = false
    for _, i in ipairs(g.st) do if (load[i] or false) ~= w0 then mixed = true end end
    return w0, mixed
  end
  local function previewLoad()
    if not (st.sel and st.hoverOpt ~= nil) then return nil end
    local g = st.cards[st.sel]
    local l = table.clone(st.load)
    for _, j in ipairs(g.st) do
      local wid = st.hoverOpt
      l[j] = (wid and table.find(st.d.st[j].opts, wid)) and wid or false
    end
    return l
  end

  ---------------------------------------------------------------- 3D：挂点的位置、高亮、装上的动效、弹舱

  local Stage = ws.Stage
  -- 每个挂点在飞机里的位置（模型坐标）：挂着弹的用弹的中心（零件的平均位置），空着的用挂架（AirModels 记的 stPos）
  local function computeAnchors(A0)
    st.anchor = {}
    local M = A0 and A0.M
    for i, s in ipairs(st.d.st or {}) do
      local p = nil
      local grp = st.groups3d and st.groups3d[i]
      if grp and A0 then
        local sum, n = V3(), 0
        for _, x in ipairs(grp:GetChildren()) do
          if x:IsA("BasePart") then
            sum += A0.cf:PointToObjectSpace(x.Position)
            n += 1
          end
        end
        if n > 0 then p = sum / n end
      end
      st.anchor[i] = p or (M and M.stPos and M.stPos[i]) or s.pos
    end
  end
  -- 挂点上的弹的零件收进一个模型（Station<i>）：一个 Highlight 罩住一整个挂点
  local function groupParts(A0)
    st.groups3d = {}
    local M = A0 and A0.M
    if not M or not M.stores then return end
    for i, list in pairs(M.stores) do
      if #list > 0 then
        local m = M.model:FindFirstChild("Station" .. i) or Instance.new("Model")
        m.Name = "Station" .. i
        m.Parent = M.model
        for _, it in ipairs(list) do
          if it.p then it.p.Parent = m end
        end
        st.groups3d[i] = m
      end
    end
  end
  local HL_SEL = { fill = C.WARN, fillT = 0.85, line = C.WARN, lineT = 0 }
  local HL_HOV = { fill = C.TEXT, fillT = 0.94, line = C.TEXT, lineT = 0.55 }
  local function applyHL()
    if not Stage then return end
    Stage.unhighlight()
    st.hlSel = {}
    local function hl(ci, o, keep)
      local g = ci and st.cards[ci]
      if not g then return end
      for _, i in ipairs(g.st) do
        local grp = st.groups3d and st.groups3d[i]
        if grp and grp.Parent then
          local h = Stage.highlight(grp, o)
          if h and keep then table.insert(keep, h) end
        end
      end
    end
    if st.sel then hl(st.sel, HL_SEL, st.hlSel) end
    if st.hov and st.hov ~= st.sel then hl(st.hov, HL_HOV) end
  end
  -- 装上：新挂的弹从挂架下 1.2 格滑上去（带一点回弹），选中的琥珀轮廓亮一下、0.5 秒淡回平时的样子
  local function mountAnim(stations)
    local A0 = G.hangarAir and G.hangarAir()
    if not A0 or not stations then return end
    local parts = {}
    for _, i in ipairs(stations) do
      local grp = st.groups3d and st.groups3d[i]
      if grp then
        for _, p in ipairs(grp:GetChildren()) do
          if p:IsA("BasePart") then table.insert(parts, { p = p, cf = p.CFrame }) end
        end
      end
    end
    if #parts > 0 then
      local down = A0.cf.UpVector * -1.2
      K.anim("wsMount", TH.T.mount, "back", function(e)
        for _, x in ipairs(parts) do
          if x.p.Parent then x.p.CFrame = x.cf + down * (1 - e) end
        end
      end)
    end
    local hs = st.hlSel or {}
    if #hs > 0 then
      K.anim("wsFlash", 0.5, "out", function(e)
        for _, h in ipairs(hs) do
          pcall(function() h.h.FillTransparency = 0.5 + (HL_SEL.fillT - 0.5) * e end)
        end
      end)
    end
  end
  -- 换上（或者还原）3D 里挂的：TechUI 重新搭飞机（同一架只换模型、镜头不动），搭好回调 onAir
  local function show3d(load)
    if G.hangarAirLoad then return G.hangarAirLoad(load) end
    return false
  end
  local function onAir(A0)
    if not st or not A0 or A0.key ~= st.key then return end
    groupParts(A0)
    computeAnchors(A0)
    applyHL()
    if st.pendingMount then
      local m = st.pendingMount
      st.pendingMount = nil
      mountAnim(m)
    end
  end
  local function poseBay(k)
    if G.hangarAirPose then G.hangarAirPose({ gear = 1, bay = k, bayS = k, thr = 0 }) end
  end

  ---------------------------------------------------------------- 镜头

  -- 镜头竖直半视场的 tan：照镜头现在的视场角算（HangarStage 定 40°；Play.lua 每帧往 70° 拉一下，实际跟着帧率在 42～52° 之间）
  local function tanV()
    local cam = workspace.CurrentCamera
    local fov = cam and cam.FieldOfView or 40
    return math.tan(math.rad(math.clamp(fov, 20, 90)) / 2)
  end
  local function free3d()   -- 两栏中间留给 3D 的那一段（Root 坐标）：左、右
    local vw = ws.vw()
    return LAY.M + LAY.LW + LAY.GAP, vw - LAY.M - LAY.RW - LAY.GAP
  end
  -- 全景的距离：飞机在这个偏航 / 俯仰下的投影正好放进两栏中间那一段（留一成边）
  --   飞机是十字形（机身 × 机翼），斜着看时投影最宽的是翼尖或机头，不是外接方盒的角：按两者里大的那个 × 1.18 算；直升机的宽按旋翼
  local function fitDist(d, yaw, pitch)
    local vw, vh = ws.vw(), ws.vh()
    local tv = tanV()
    local tanH = tv * vw / math.max(vh, 1)
    local x0, x1 = free3d()
    local fx = math.max(0.25, (x1 - x0) / vw) * 0.9
    local fy = math.max(0.3, ws.colH() / vh) * 0.62
    local L, W, H = d.L or 40, d.W or 30, (d.H or 12)
    if d.kind == "heli" and d.rotor then W = math.max(W, d.rotor.r * 1.6) end
    local ay, ap = math.abs(math.sin(yaw)), math.abs(math.cos(yaw))
    local extX = math.max(W / 2 * ap, L / 2 * ay) * 1.18
    local extY = H / 2 * math.cos(pitch) + math.max(W / 2 * ay, L / 2 * ap) * math.abs(math.sin(pitch))
    return math.max(extX / (fx * tanH), extY / (fy * tv)) * 1.08
  end
  -- 镜头横着挪多少格，让 at 那一点落在画面的 sx（Root 坐标）上
  local function shiftFor(dist, sx)
    local vw, vh = ws.vw(), ws.vh()
    local tanH = tanV() * vw / math.max(vh, 1)
    return -(sx - vw / 2) / (vw / 2) * dist * tanH
  end
  local function overview(t)
    local d = st.d
    local yaw, pitch = math.rad(-150), -0.06
    local dist = fitDist(d, yaw, pitch)
    local x0, x1 = free3d()
    if Stage then
      Stage.focus({ at = V3(0, (d.gearH or 6) * 0.92, 0), dist = dist, yaw = yaw, pitch = pitch, shift = shiftFor(dist, (x0 + x1) / 2), t = t })
    end
    st.idle = 0
  end
  local function stationView(ci, t)
    local g = st.cards[ci]
    if not (g and Stage) then return end
    local d = st.d
    local vs = Stage.viewState()
    local camSide = (math.sin(vs.sy or vs.yaw or 0) >= 0) and 1 or -1
    local pick = g.st[1]
    for _, i in ipairs(g.st) do if ((d.st[i].pos.X >= 0) and 1 or -1) == camSide then pick = i end end
    local s = d.st[pick]
    local a = (st.anchor and st.anchor[pick]) or s.pos
    local side = (math.abs(s.pos.X) < 0.5) and camSide or ((s.pos.X >= 0) and 1 or -1)
    -- 离多远：画面里看得见这一侧的大半个机翼（按视场角换算：视场宽了就近一点，框住的一样多）；直升机机身长、短翼短：从侧前方远一点看
    local heli = d.kind == "heli"
    local dist = (heli and math.max((d.L or 40) * 0.36, 14) or math.max(d.L or 40, d.W or 30) * 0.27) / tanV()
    local yawS = heli and math.rad(100) or math.rad(125)
    local x0, x1 = free3d()
    -- 挂点落在哪：桌面上左边浮着这枚弹的资料卡（左栏右边 300 宽），挂点放到资料卡和右栏中间；手机放在两栏中间
    local sx = compact and (x0 + x1) / 2 or (x0 + LAY.DW + LAY.GAP + x1) / 2
    Stage.focus({ at = V3(0, d.gearH or 6, 0) + a, dist = dist, yaw = side * yawS, pitch = s.bay and -0.15 or (heli and -0.04 or -0.08),
      shift = shiftFor(dist, sx), t = t })
    st.idle = 0
  end

  ---------------------------------------------------------------- 界面零件（左栏、右栏、底部条、标签层、资料卡）：每次打开按这一架重建

  local ui = {}
  -- 清空一块（只删界面零件：面板自己的 UIGradient / UIStroke / UICorner 留着）
  local function clear(f) for _, c in ipairs(f:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end end

  -- 左栏：方案（预设 + 我的方案）、照哪套改的、选中的挂点、武器卡
  local CH = compact and 62 or 74   -- 武器卡的高
  local PW, PH = compact and 76 or 104, compact and 30 or 40   -- 卡上那块图
  local refreshAll, selectCard, setHover, buildList, updateRight, refreshChips   -- 下面定义

  local function applyLoad(newLoad)
    local changed = {}
    for i = 1, #(st.d.st or {}) do
      local a, b = st.load[i] or false, newLoad[i] or false
      if a ~= b and b then table.insert(changed, i) end
    end
    st.load = newLoad
    st.pendingMount = (#changed > 0) and changed or nil
    local rebuilt = show3d(st.load)
    if not rebuilt and st.pendingMount then
      local m = st.pendingMount
      st.pendingMount = nil
      mountAnim(m)
    end
    if G.treeSaveLoad then G.treeSaveLoad(st.key, st.load, st.pk, st.fuel, true) end
    st.idle = 0
    refreshAll()
  end

  local function presetMod()   -- 照哪套预设改的、改了几个挂点
    if not st.pk then return nil, 0 end
    local pl = AD.presetLoad(st.d, st.pk)
    local n = 0
    for i = 1, #(st.d.st or {}) do if (pl[i] or false) ~= (st.load[i] or false) then n += 1 end end
    return pl, n
  end
  local function setOf(i)
    local t = G.treeState and G.treeState()
    local sets = t and t.sets and t.sets[st.key]
    local v = sets and sets[tostring(i)]
    if type(v) == "table" and type(v.l) == "table" then return { l = AD.cleanLoad(st.d, v.l), f = AD.cleanFuel(v.f) } end
    return nil
  end

  local function buildLeft()
    local Lf = ws.left
    clear(Lf)
    local w = LAY.LW - 24
    local y = 10
    ui.chips, ui.mine = {}, {}
    local presets = st.d.presets or {}
    local schemeBox = K.frame(Lf, UD2(1, 0, 0, 10), nil, nil, 1)
    schemeBox.Name = "Schemes"
    ui.schemeBox = schemeBox
    K.header(schemeBox, T("ws.schemes"), y, w)
    y += 22
    local cols = 3
    local CW, CHh, G6 = math.floor((w - (cols - 1) * 6) / cols), compact and 32 or 28, 6
    for k, p in ipairs(presets) do
      local r, c = math.floor((k - 1) / cols), (k - 1) % cols
      local ch = K.chip(schemeBox, T("preset." .. p.key), UD2(0, CW, 0, CHh), UD2(0, 12 + c * (CW + G6), 0, y + r * (CHh + G6)), {
        name = "Preset_" .. p.key,
        onClick = function()
          st.pk, st.mine = p.key, nil
          applyLoad(AD.presetLoad(st.d, p.key))
        end })
      ui.chips[p.key] = ch
    end
    y += math.max(1, math.ceil(#presets / cols)) * (CHh + G6) + 6
    K.header(schemeBox, T("ws.mine"), y, w)
    y += 22
    for i = 1, 3 do
      local ch
      ch = K.chip(schemeBox, "", UD2(0, CW, 0, CHh), UD2(0, 12 + (i - 1) * (CW + G6), 0, y), {
        name = "Mine_" .. i,
        onClick = function()
          local v = setOf(i)
          if v then
            st.pk, st.mine = nil, i
            st.fuel = v.f
            applyLoad(v.l)
          else   -- 空着：把现在这一套存进去
            if G.treeSaveSet then G.treeSaveSet(st.key, i, st.load, st.fuel) end
            st.mine = i
            if ws.flash then ws.flash(T("ws.mineSaved", i)) end
            refreshChips()
          end
        end })
      -- 存（覆盖成现在这一套）：小块右边一个小键
      local sv = Instance.new("TextButton")
      sv.Name = "Save"
      sv.Text = T("ws.mineSave")
      sv.Font = TH.F.cond
      sv.TextSize = S.tiny
      sv.TextColor3 = C.MUTE
      sv.AutoButtonColor = false
      sv.BackgroundTransparency = 1
      sv.Size = UD2(0, 22, 1, 0)
      sv.Position = UD2(1, -24, 0, 0)
      sv.ZIndex = 3
      sv.Parent = ch.f
      sv.Activated:Connect(function()
        if G.treeSaveSet then G.treeSaveSet(st.key, i, st.load, st.fuel) end
        st.mine = i
        if ws.flash then ws.flash(T("ws.mineSaved", i)) end
        refreshChips()
      end)
      ch.save = sv
      ch.dashF = K.dashed(ch.f, CW, CHh, C.LINE, 0.6)   -- 空着时虚线框
      ui.mine[i] = ch
    end
    y += CHh + 8
    ui.status = K.text(schemeBox, "", S.tiny, "bold", C.MUTE, UD2(0, w, 0, 16), UD2(0, 12, 0, y))
    ui.status.Name = "LoadStatus"
    y += 24
    schemeBox.Size = UD2(1, 0, 0, y)
    ui.schemeH = y
    -- 挂点：标题（挂点 3·9 · 翼下 · 弹舱）、武器卡（卷动）
    local sbox = K.frame(Lf, UD2(1, 0, 1, -y), UD2(0, 0, 0, y), nil, 1)
    sbox.Name = "StationBox"
    ui.sbox = sbox
    if compact then   -- 手机：选了挂点时方案那一块收起，挂点占满左栏（左上一个「‹ 方案」回去）
      local bk = Instance.new("TextButton")
      bk.Name = "BackToSchemes"
      bk.Text = ""
      bk.AutoButtonColor = false
      bk.BackgroundTransparency = 1
      bk.Size = UD2(0, 90, 0, 30)
      bk.Position = UD2(0, 8, 0, 2)
      bk.Parent = sbox
      K.chevron(bk, 4, 9, 12, C.MUTE)
      K.text(bk, T("ws.schemes"), S.small, "bold", C.MUTE, UD2(1, -22, 1, 0), UD2(0, 20, 0, 0)).Name = "Label"
      bk.Activated:Connect(function() if selectCard then selectCard(nil) end end)
      ui.backSchemes = bk
    end
    local hy = compact and 32 or 2
    ui.stHead = K.text(sbox, "", S.body, "bold", C.TEXT, UD2(0, w - 56, 0, 20), UD2(0, 12, 0, hy))
    ui.stHead.Name = "StationHead"
    ui.stPos = K.text(sbox, "", S.small, "cond", C.MUTE, UD2(0, w, 0, 16), UD2(0, 12, 0, hy + 20))
    ui.stPos.Name = "StationPos"
    ui.bayTag = K.frame(sbox, UD2(0, 40, 0, 16), UD2(1, -12, 0, hy + 2), C.PANEL, 1, V2(1, 0))
    ui.bayTag.Name = "BayTag"
    TH.stroke(ui.bayTag).Transparency = 0.65
    TH.corner(ui.bayTag)
    K.text(ui.bayTag, T("ws.bay"), S.tiny, "cond", C.MUTE, UD2(1, 0, 1, 0), nil, CENTER).Name = "Text"
    local list = Instance.new("ScrollingFrame")
    list.Name = "Weapons"
    list.BackgroundTransparency = 1
    list.BorderSizePixel = 0
    list.ScrollBarThickness = 3
    list.ScrollBarImageColor3 = C.MUTE
    list.ScrollingDirection = Enum.ScrollingDirection.Y
    list.ClipsDescendants = true
    list.CanvasSize = UD2(0, 0, 0, 0)
    list.Size = UD2(1, -16, 1, -(hy + 44))
    list.Position = UD2(0, 12, 0, hy + 42)
    list.Parent = sbox
    ui.list = list
    ui.listY = hy + 42
    -- 全景（没选挂点）时这一块放「这一套挂了什么」；最底下一行淡字提示怎么换
    ui.manifest = K.frame(sbox, UD2(1, 0, 1, -34), UD2(0, 0, 0, 4), nil, 1)   -- 只在没选挂点时出来（那时手机的「‹ 方案」也不在）
    ui.manifest.Name = "Manifest"
    ui.hint = K.text(sbox, T(compact and "ws.pickTouch" or "ws.pick"), S.tiny, "body", C.FAINT, UD2(0, w, 0, 16), UD2(0, 12, 1, -22))
    ui.hint.Name = "PickHint"
  end

  -- 这一套挂了什么（全景时左栏下半）：航炮在最前，然后按类（空空、空地、炸弹、火箭巢、副油箱），一种一行：小图、短名、几枚
  local CAT_ORDER = { aam = 1, agm = 2, bomb = 3, rkt = 4, tank = 5 }
  local function buildManifest()
    local box = ui.manifest
    if not box then return end
    clear(box)
    local w = LAY.LW - 24
    local d = st.d
    local rows = {}
    if d.gun then table.insert(rows, { gun = d.gun, n = d.gunAmmo or 0 }) end
    local cnt, order = {}, {}
    for i, s0 in ipairs(d.st or {}) do
      local wid = st.load[i]
      local Wd = wid and AD.W[wid]
      if Wd then
        if not cnt[wid] then
          cnt[wid] = 0
          table.insert(order, wid)
        end
        cnt[wid] += (Wd.kind == "rkt") and 1 or AD.count(s0, wid)
      end
    end
    table.sort(order, function(a, b)
      local ka, kb = CAT_ORDER[AD.W[a].kind] or 9, CAT_ORDER[AD.W[b].kind] or 9
      if ka ~= kb then return ka < kb end
      return a < b
    end)
    for _, wid in ipairs(order) do table.insert(rows, { wid = wid, n = cnt[wid] }) end
    K.header(box, T("ws.manifest"), 0, w)
    local RH = compact and 24 or 30
    local PWm, PHm = compact and 48 or 64, compact and 16 or 20
    local maxRows = math.max(1, math.floor((ws.colH() - (ui.schemeH or 0) - 52) / RH))
    local all = {}
    for _, r in ipairs(rows) do if r.wid then all[#all + 1] = r.wid end end
    local px = K.artScale(all, PWm, PHm, 2)
    for k, r in ipairs(rows) do
      if k > maxRows then break end
      local row = K.frame(box, UD2(0, w, 0, RH - 4), UD2(0, 12, 0, 22 + (k - 1) * RH), nil, 1)
      row.Name = "Man_" .. (r.wid or r.gun)
      local pl = K.plate(row, UD2(0, PWm, 0, PHm), UD2(0, 0, 0.5, -PHm / 2))
      if r.gun then K.gunArt(pl, r.gun, PWm, PHm) else K.weaponArt(pl, r.wid, PWm, PHm, { px = px }) end
      local Wd = r.wid and AD.W[r.wid]
      K.text(row, r.gun and wname(r.gun) or wname(r.wid), S.small, "bold", C.TEXT, UD2(0, w - PWm - 110, 1, 0), UD2(0, PWm + 10, 0, 0)).Name = "Name"
      local cat = r.gun and T("wcs.gun") or T("wcs." .. catOf(Wd))
      K.text(row, cat, S.tiny, "cond", C.MUTE, UD2(0, 64, 1, 0), UD2(1, -46, 0, 0), RIGHT, V2(1, 0)).Name = "Cat"
      local cntT = r.gun and tostring(r.n) or ("×" .. r.n)
      K.text(row, cntT, S.small, "mono", C.TEXT, UD2(0, 40, 1, 0), UD2(1, 0, 0, 0), RIGHT, V2(1, 0)).Name = "Count"
    end
    if #order == 0 then
      K.text(box, T("ws.manifestEmpty"), S.small, "body", C.FAINT, UD2(0, w, 0, 18), UD2(0, 12, 0, 22 + #rows * RH)).Name = "Empty"
    end
  end

  -- 武器卡（左栏）：左边 104 × 40 的图、标题、「类别 · 导引」、数（射程、锁定、一个挂点几枚）；装着的绿色条 +「已装」
  local function weaponCard(parent, k, wid, s, px, cur)
    local y = (k - 1) * (CH + 6) + 3
    local wcard = K.card(parent, UD2(1, -8, 0, CH), UD2(0, 2, 0, y), {
      name = "Opt_" .. (wid or "none"),
      onEnter = function() if setHover then setHover(wid, true) end end,
      onLeave = function() if setHover then setHover(wid, false) end end,
      onClick = function()
        if not st or not st.sel then return end
        local g = st.cards[st.sel]
        local l = table.clone(st.load)
        for _, j in ipairs(g.st) do l[j] = (wid and table.find(st.d.st[j].opts, wid)) and wid or false end
        st.hoverOpt = nil
        if ui.detail then ui.detail.Visible = false end
        applyLoad(l)
      end })
    local f = wcard.f
    local w = wid and AD.W[wid]
    local px0 = compact and 8 or 10
    if w then
      local plate = K.plate(f, UD2(0, PW, 0, PH), UD2(0, px0, 0.5, -PH / 2))
      K.weaponArt(plate, wid, PW, PH, { px = math.min(px * 1.5, K.artScale({ wid }, PW, PH, 4)), n = AD.count(s, wid) > 1 and w.kind ~= "rkt" and 2 or 1 })
      local tx = px0 + PW + 10
      local t1 = K.text(f, wname(wid), compact and S.small or S.body, "bold", C.TEXT, UD2(1, -(tx + 40), 0, 18), UD2(0, tx, 0, compact and 5 or 7))
      t1.Name = "Name"
      local t2 = K.text(f, subOf(w, compact), compact and S.tiny or S.small, "cond", C.MUTE, UD2(1, -(tx + 8), 0, 16), UD2(0, tx, 0, compact and 23 or 27))
      t2.Name = "Sub"
      local t3 = K.text(f, numsOf(s, wid), S.tiny, "mono", C.TEXT, UD2(1, -(tx + 8), 0, 16), UD2(0, tx, 0, compact and 40 or 48))
      t3.Name = "Nums"
    else   -- 不挂：虚线框
      wcard.st.Transparency = 1
      K.dashed(f, LAY.LW - 24, CH, C.LINE, 0.55)
      local t1 = K.text(f, T("ws.none"), S.body, "bold", C.TEXT, UD2(1, -24, 0, 18), UD2(0, 16, 0, CH / 2 - 18))
      t1.Name = "Name"
      local t2 = K.text(f, T("ws.noneSub"), S.small, "cond", C.MUTE, UD2(1, -24, 0, 16), UD2(0, 16, 0, CH / 2 + 2))
      t2.Name = "Sub"
    end
    local on = (cur or false) == (wid or false)
    local tag = K.text(f, T("ws.equipped"), S.tiny, "cond", C.GOOD, UD2(0, 40, 0, 14), UD2(1, -8, 0, 6), RIGHT, V2(1, 0))
    tag.Name = "Equipped"
    tag.Visible = on
    wcard:setState(on and "own" or nil)
    wcard.wid = wid
    return wcard
  end

  buildList = function()
    if not ui.list then return end
    clear(ui.list)
    ui.opts = {}
    local g = st.sel and st.cards[st.sel]
    local showSchemes = not (compact and g)
    if ui.schemeBox then ui.schemeBox.Visible = showSchemes end
    if ui.sbox then
      ui.sbox.Position = showSchemes and UD2(0, 0, 0, ui.schemeH) or UD2(0, 0, 0, 0)
      ui.sbox.Size = showSchemes and UD2(1, 0, 1, -ui.schemeH) or UD2(1, 0, 1, 0)
    end
    if ui.backSchemes then ui.backSchemes.Visible = g ~= nil end
    ui.hint.Visible = g == nil
    ui.manifest.Visible = g == nil
    if not g then buildManifest() end
    ui.stHead.Visible, ui.stPos.Visible, ui.list.Visible = g ~= nil, g ~= nil, g ~= nil
    ui.bayTag.Visible = g ~= nil and g.bay ~= nil
    if not g then return end
    local d = st.d
    local s = d.st[g.st[1]]
    ui.stHead.Text = T("ws.station", g.label)
    ui.stPos.Text = posName(s) .. ((#g.st > 1) and ("  ·  " .. T("ws.pairNote")) or "")
    local opts = table.clone(s.opts)
    table.insert(opts, false)
    local px = K.artScale(s.opts, PW, PH, 4)
    local cur, mixed = cardWeapon(g)
    for k, wid in ipairs(opts) do
      local cd = weaponCard(ui.list, k, wid, s, px, (not mixed) and cur or nil)
      table.insert(ui.opts, cd)
      K.reveal(cd.f, k)
    end
    ui.list.CanvasSize = UD2(1, 0, 0, #opts * (CH + 6) + 6)
    ui.list.CanvasPosition = V2(0, 0)
  end
  -- 武器卡上的「已装」跟着挂载走（不重建：鼠标还挂在卡上，重建了悬停就断了）
  local function refreshList()
    local g = st.sel and st.cards[st.sel]
    if not g then return end
    local cur, mixed = cardWeapon(g)
    for _, cd in ipairs(ui.opts or {}) do
      local on = (not mixed) and (cur or false) == (cd.wid or false)
      cd:setState(on and "own" or nil)
      local tg = cd.f:FindFirstChild("Equipped")
      if tg then tg.Visible = on end
    end
  end

  refreshChips = function()
    local _, nMod = presetMod()
    for key, ch in pairs(ui.chips or {}) do
      local on = st.mine == nil and st.pk == key
      ch:set(on, (on and nMod > 0) and T("ws.modTag") or nil)
    end
    for i, ch in ipairs(ui.mine or {}) do
      local v = setOf(i)
      local on = st.mine == i
      local modded = on and v ~= nil and not (same(v.l, st.load) and math.abs(v.f - st.fuel) < 1e-6)
      ch.t.Text = v and T("ws.mineN", i) or T("ws.mineEmpty")
      ch.dash = v == nil
      ch.dashF.Visible = v == nil
      ch:set(on and v ~= nil, modded and T("ws.modTag") or nil)
      ch.save.Visible = v ~= nil
      ch.save.TextColor3 = (on and v ~= nil) and C.BG or C.MUTE
      ch.t.Size = UD2(1, (v ~= nil) and (ch.mod.Visible and -66 or -32) or -16, 1, 0)
      if ch.mod.Visible then ch.mod.Position = UD2(1, -26, 0, 0) end
    end
    -- 「照『对地』改过 2 个挂点」/「对地 · 预设」/「我的 1」/「自己配的」
    local txt, col = "", C.MUTE
    if st.mine then
      local v = setOf(st.mine)
      local modded = v and not (same(v.l, st.load) and math.abs(v.f - st.fuel) < 1e-6)
      txt, col = modded and T("ws.mineModded", st.mine) or T("ws.mineN", st.mine), modded and C.WARN or C.MUTE
    elseif st.pk then
      local _, n = presetMod()
      local pn = T("preset." .. st.pk)
      if n > 0 then txt, col = T("ws.presetModded", pn, n), C.WARN else txt = T("ws.presetExact", pn) end
    else
      txt = T("ws.custom")
    end
    if ui.status then
      ui.status.Text = txt
      ui.status.TextColor3 = col
    end
  end

  ---------------------------------------------------------------- 右栏：这一套、性能对比、内油

  local function buildRight()
    local Rf = ws.right
    clear(Rf)
    ui.cmp = {}
    local w = LAY.RW - 24
    local y = compact and 8 or 10
    K.header(Rf, T("ws.thisSet"), y, w)
    y += compact and 20 or 22
    local function stat(key, label)
      local row = K.frame(Rf, UD2(0, w, 0, 20), UD2(0, 12, 0, y), nil, 1)
      row.Name = "Stat_" .. key
      K.text(row, label, S.small, "cond", C.MUTE, UD2(0.5, 0, 1, 0), nil).Name = "Name"
      local v = K.text(row, "", compact and S.small or S.body, "mono", C.TEXT, UD2(0.6, 0, 1, 0), UD2(1, 0, 0, 0), RIGHT, V2(1, 0))
      v.Name = "Val"
      y += 22
      return v
    end
    ui.vExt = stat("ext", T("ws.ext"))
    if st.jet then
      ui.vDrag = stat("drag", T("ws.drag"))
      ui.vMass = (not compact) and stat("mass", T("ws.mass")) or nil   -- 手机：右栏只有 300 高，起飞重量不写（内油那一栏下面有）
      ui.vHeavy = nil
    else
      ui.vDrag, ui.vMass = nil, nil
      ui.vHeavy = stat("heavy", T("ws.heavy"))
    end
    y += compact and 4 or 8
    K.header(Rf, T(st.jet and "ws.perf" or "ws.perfHeli"), y, w)
    y += compact and 20 or 22
    local rows
    if st.jet then
      rows = { { "vAB", "ws.vAB" }, { "vMil", "ws.vMil" }, { "tw", "ws.tw" }, { "str", "ws.str" }, { "roc", "ws.roc" }, { "wl", "ws.wl" } }
      if st.D and not (st.D.Ta > st.D.Tm) then table.remove(rows, 2) end   -- 没有加力：只有一个极速
      if compact then rows = { rows[1], { "tw", "ws.tw" }, { "str", "ws.str" }, { "roc", "ws.roc" } } end
    else
      rows = { { "vh", "ws.vMax" }, { "min", "ws.endurRow" } }
    end
    for _, r in ipairs(rows) do
      ui.cmp[r[1]] = K.compare(Rf, y, w, T(r[2]), nil, compact)
      ui.cmp[r[1]].f.Name = "Cmp_" .. r[1]
      y += compact and 28 or 32
    end
    if not compact then   -- 手机放不下这一行说明
      local note = K.text(Rf, T(st.jet and "ws.perfNote" or "ws.heliNote"), S.tiny, "body", C.FAINT, UD2(0, w, 0, 16), UD2(0, 12, 0, y - 2))
      note.Name = "Note"
      y += 22
    end
    K.header(Rf, T("ws.fuel"), y, w)
    y += compact and 20 or 22
    local opts = {}
    for _, f in ipairs(AD.FUEL_OPTS) do
      local pc = math.floor(f * 100 + 0.5)
      table.insert(opts, { key = f, text = pc .. "%", name = "Fuel" .. pc })
    end
    ui.fuel = K.seg(Rf, opts, UD2(0, w, 0, compact and 34 or 30), UD2(0, 12, 0, y), { name = "FuelSeg", onPick = function(f)
      st.fuel = f
      st.idle = 0
      if G.treeSaveLoad then G.treeSaveLoad(st.key, st.load, st.pk, st.fuel, true) end
      refreshAll()
    end })
    y += (compact and 34 or 30) + 6
    ui.fuel1 = K.text(Rf, "", S.tiny, "mono", C.TEXT, UD2(0, w, 0, 16), UD2(0, 12, 0, y))
    ui.fuel1.Name = "Endurance"
    ui.fuel2 = K.text(Rf, "", S.tiny, "mono", C.MUTE, UD2(0, w, 0, 16), UD2(0, 12, 0, y + 17))
    ui.fuel2.Name = "FuelWeight"
    ui.fuel2.Visible = not compact
  end

  updateRight = function()
    if not st or not ui.vExt then return end
    local cur = perfOf(st.load, st.fuel)
    local empty = perfOf(st.empty, st.fuel)
    local pl = previewLoad()
    local pv = pl and perfOf(pl, st.fuel) or nil
    -- 这一套
    do
      local x = (pv or cur).Lo
      K.roll(ui.vExt, "wsExt", st.shown.ext, x.ext, function(v) return K.int(v) .. " kg" end)
      st.shown.ext = x.ext
      ui.vExt.TextColor3 = pv and C.WARN or C.TEXT
      if ui.vDrag then
        local dc = x.dCD0 or 0
        K.roll(ui.vDrag, "wsDrag", st.shown.drag, dc, function(v) return "+" .. string.format("%.4f", v) end)
        st.shown.drag = dc
        ui.vDrag.TextColor3 = pv and C.WARN or C.TEXT
      end
      if ui.vMass and x.m then
        K.roll(ui.vMass, "wsMass", st.shown.mass, x.m, function(v) return K.int(v) .. " kg" end)
        st.shown.mass = x.m
        ui.vMass.TextColor3 = pv and C.WARN or C.TEXT
      end
      if ui.vHeavy then
        ui.vHeavy.Text = T("ws.heavyVal", K.signed(((pv or cur).heavy - 1) * 100))
        ui.vHeavy.TextColor3 = pv and C.WARN or C.TEXT
      end
    end
    -- 性能对比：空挂（同样的内油）→ 这一套；悬停时 这一套 → 预览
    if st.jet and cur.p and empty.p then
      local P0, P1, P2 = empty.p, cur.p, pv and pv.p
      local kmh = function(v) return K.int(v) end
      local function row(key, get, fmt, dfmt, better, eps)
        local r = ui.cmp[key]
        if r then r:set(get(P0), get(P1), P2 and get(P2) or nil, { fmt = fmt, dfmt = dfmt, better = better, eps = eps }) end
      end
      row("vAB", function(p) return p.vAB * 3.6 end, kmh, function(v) return K.signed(v) end, 1, 0.5)
      row("vMil", function(p) return p.vMil * 3.6 end, kmh, function(v) return K.signed(v) end, 1, 0.5)
      row("tw", function(p) return p.tw end, f2, function(v) return K.signed(v, 2) end, 1, 0.005)
      row("str", function(p) return p.str * 180 / math.pi end, f1, function(v) return K.signed(v, 1) end, 1, 0.05)
      row("roc", function(p) return p.roc end, function(v) return K.int(v) end, function(v) return K.signed(v) end, 1, 0.5)
      row("wl", function(p) return p.wl end, function(v) return K.int(v) end, function(v) return K.signed(v) end, -1, 0.5)
    elseif not st.jet then
      local vt = function(c) return (c.vh or 0) / AD.M * 3.6 end
      if ui.cmp.vh then ui.cmp.vh:set(vt(empty), vt(cur), pv and vt(pv) or nil, { fmt = function(v) return K.int(v) end, dfmt = function(v) return K.signed(v) end, better = 1, eps = 0.5 }) end
      if ui.cmp.min then ui.cmp.min:set(empty.min, cur.min, pv and pv.min or nil, { fmt = function(v) return T("ws.minutes", math.floor(v + 0.5)) end,
        dfmt = function(v) return K.signed(v) end, better = 1, eps = 0.5 }) end
    end
    -- 内油
    if ui.fuel then ui.fuel.set(st.fuel) end
    local c = pv or cur
    ui.fuel1.Text = T("ws.endur", c.min) .. ((c.minX > 0) and ("  " .. T("ws.endurTank", c.minX)) or "")
    if st.jet and c.Lo.m and st.D then
      ui.fuel2.Text = T("ws.fuelKg", K.int(st.D.fi * st.fuel), K.int(c.Lo.xf or 0))
    else
      ui.fuel2.Text = T("ws.heavyNote", K.signed((c.heavy - 1) * 100))
    end
  end

  ---------------------------------------------------------------- 悬停资料卡（桌面：浮在左栏右边，跟着鼠标挂着的那张卡）

  local function buildDetail()
    local D0 = ws.detail
    clear(D0)
    if compact then return end
    local w = LAY.DW
    local pnl = K.panel(D0, UD2(0, w, 0, 208), UD2(0, 1, 0, 1))
    pnl.Name = "Card"
    pnl.BackgroundTransparency = 0.06
    ui.detail = D0
    ui.dName = K.text(pnl, "", S.body, "bold", C.TEXT, UD2(0, w - 24, 0, 20), UD2(0, 12, 0, 8))
    ui.dName.Name = "Name"
    ui.dSub = K.text(pnl, "", S.small, "cond", C.MUTE, UD2(0, w - 24, 0, 16), UD2(0, 12, 0, 28))
    ui.dSub.Name = "Sub"
    ui.dPlate = K.plate(pnl, UD2(0, w - 24, 0, 46), UD2(0, 12, 0, 48))
    ui.dRows = {}
    for k = 1, 4 do
      local y = 100 + (k - 1) * 17
      local nm = K.text(pnl, "", S.tiny, "cond", C.MUTE, UD2(0, 70, 0, 14), UD2(0, 12, 0, y))
      local tr = K.frame(pnl, UD2(0, w - 24 - 70 - 70, 0, 3), UD2(0, 12 + 70, 0, y + 6), C.LINE, 0.9)
      local bar = K.frame(tr, UD2(0, 0, 1, 0), nil, C.TEXT, 0.15)
      local v = K.text(pnl, "", S.tiny, "mono", C.TEXT, UD2(0, 64, 0, 14), UD2(1, -12, 0, y), RIGHT, V2(1, 0))
      ui.dRows[k] = { nm = nm, bar = bar, v = v, tr = tr }
    end
    ui.dVs = {}
    local cw = (w - 24) / 6
    for k = 1, 6 do
      local x = 12 + (k - 1) * cw
      local a = K.text(pnl, "", S.tiny, "cond", C.FAINT, UD2(0, cw, 0, 13), UD2(0, x, 0, 174), CENTER)
      local b = K.text(pnl, "", S.tiny, "mono", C.TEXT, UD2(0, cw, 0, 13), UD2(0, x, 0, 189), CENTER)
      ui.dVs[k] = { a = a, b = b }
    end
    D0.Visible = false
  end
  local VS_KEYS = { "inf", "light", "armor", "air", "ship", "fort" }
  local function showDetail(wid, cd)
    if compact or not ui.detail then return end
    local w = wid and AD.W[wid]
    if not (w and st.sel) then
      ui.detail.Visible = false
      return
    end
    local g = st.cards[st.sel]
    local s = st.d.st[g.st[1]]
    ui.dName.Text = T("aw." .. wid)
    ui.dSub.Text = subOf(w, false)
    local W2 = LAY.DW - 24
    K.weaponArt(ui.dPlate, wid, W2, 46, { px = K.artScale(s.opts, W2, 46, 5) })
    -- 四个关键数：条只在这个挂点能挂的几种（同一类）之间比
    local function rowsOf(x)
      local n = AD.count(s, x.id)
      if x.kind == "tank" then
        return { { "ws.d.fuel", x.fuel * n * 100, function(v) return "+" .. math.floor(v + 0.5) .. "%" end },
          { "ws.d.drag", x.drag * n * 100, function(v) return "−" .. math.floor(v + 0.5) .. "%" end },
          { "ws.d.extra", AD.fuelMin(st.d, x.fuel * n), function(v) return T("ws.minutes", math.floor(v + 0.5)) end },
          { "ws.d.shell", (FM and FM.storeMass(x, AD.M) or 0) * n, function(v) return K.int(v) .. " kg" end } }
      elseif x.kind == "bomb" then
        return { { "ws.d.dmg", x.dmg or 0, function(v) return K.int(v) end },
          { "ws.d.radius", (x.splash or 0) / AD.M, function(v) return K.int(v) .. " m" end },
          { "ws.d.mass", (FM and FM.storeMass(x, AD.M) or 0) * n, function(v) return K.int(v) .. " kg" end },
          { "ws.d.count", n, function(v) return "×" .. math.floor(v) end } }
      elseif x.kind == "rkt" then
        return { { "ws.d.tubes", x.tubes or 1, function(v) return tostring(math.floor(v)) end },
          { "ws.d.range", x.range or 0, function(v) return km(v) .. " km" end },
          { "ws.d.dmg", x.dmg or 0, function(v) return K.int(v) end },
          { "ws.d.speed", (x.speed or 0) / AD.M, function(v) return K.int(v) .. " m/s" end } }
      end
      return { { "ws.d.range", x.range or 0, function(v) return km(v) .. " km" end },
        { "ws.d.speed", (x.speed or 0) / AD.M, function(v) return K.int(v) .. " m/s" end },
        { "ws.d.dmg", x.dmg or 0, function(v) return K.int(v) end },
        { "ws.d.lock", x.lockTime or 0, function(v) return (v > 0) and (f1(v) .. " s") or "—" end } }
    end
    local mine = rowsOf(w)
    local mx = { 0, 0, 0, 0 }
    for _, o in ipairs(s.opts) do
      local x = AD.W[o]
      if x and x.kind == w.kind then
        for k, r in ipairs(rowsOf(x)) do mx[k] = math.max(mx[k], r[2]) end
      end
    end
    for k, r in ipairs(ui.dRows) do
      local e = mine[k]
      r.nm.Text = e and T(e[1]) or ""
      r.v.Text = e and e[3](e[2]) or ""
      r.tr.Visible = e ~= nil
      if e then TH.tween(r.bar, { Size = UD2(math.clamp(e[2] / math.max(mx[k], 1e-6), 0, 1), 0, 1, 0) }, "num", "out") end
    end
    for k, c in ipairs(ui.dVs) do
      local key = VS_KEYS[k]
      local v = w.vs and w.vs[key]
      c.a.Text = T("ws.vs." .. key)
      c.b.Text = v and ("×" .. f1(v)) or "—"
      c.b.TextColor3 = (v and v >= 1) and C.TEXT or ((v and v < 0.5) and C.FAINT or C.MUTE)
      c.a.Visible, c.b.Visible = w.kind ~= "tank", w.kind ~= "tank"
    end
    -- 位置：和这张卡同一高度（卷动了的照算），放不下往上挪
    local y = LAY.TOP + (ui.schemeH or 0) + (ui.listY or 0) + (cd and cd.pos.Y.Offset or 0)
    local okc, cp = pcall(function() return ui.list.CanvasPosition end)
    if okc and cp then y -= cp.Y end
    y = math.clamp(y - 12, LAY.TOP, math.max(LAY.TOP, LAY.TOP + ws.colH() - 210))
    ui.detail.Position = UD2(0, LAY.M + LAY.LW + LAY.GAP, 0, y)
    if not ui.detail.Visible then
      ui.detail.Visible = true
      local cg = ui.detail
      cg.GroupTransparency = 1
      TH.tween(cg, { GroupTransparency = 0 }, "hover", "out")
    end
  end

  ---------------------------------------------------------------- 底部条：航炮 │ 挂点卡 │ 左右对称、干扰弹

  local SCW = compact and 76 or 92    -- 挂点卡的宽
  local FIXW = compact and 88 or 112  -- 固定卡的宽
  local SYMW = compact and 86 or 104
  local function stationCard(parent, ci, g, x, px)
    local h = LAY.BH
    local cd = K.card(parent, UD2(0, SCW, 0, h), UD2(0, x, 0, 0), {
      name = "Station_" .. ci,
      onEnter = function() if st then st.hov = ci applyHL() end end,
      onLeave = function() if st and st.hov == ci then st.hov = nil applyHL() end end,
      onClick = function() if st and selectCard then selectCard((st.sel == ci) and nil or ci) end end })
    local f = cd.f
    local num = K.text(f, g.label, S.tiny, "mono", C.TEXT, UD2(0, SCW - 12, 0, 14), UD2(0, 8, 0, 5))
    num.Name = "Num"
    local pn = posName(st.d.st[g.st[1]])
    local pos = K.text(f, pn, S.tiny, "cond", C.MUTE, UD2(0, SCW - 12, 0, 14), UD2(1, -6, 0, 5), RIGHT, V2(1, 0))
    pos.Name = "Pos"
    pos.Visible = K.textW(g.label, S.tiny, true) + K.textW(pn, S.tiny) + 10 <= SCW - 12   -- 放不下（手机、一对的编号长）就不写位置

    local pw, ph = SCW - 12, compact and 26 or 34
    local plate = K.plate(f, UD2(0, pw, 0, ph), UD2(0, 6, 0, compact and 20 or 22))
    local nm = K.text(f, "", compact and S.tiny or S.small, "bold", C.TEXT, UD2(0, SCW - 12, 0, 16), UD2(0, 8, 0, compact and 49 or 61))
    nm.Name = "Name"
    local sub = K.text(f, "", S.tiny, "cond", C.MUTE, UD2(0, SCW - 12, 0, 14), UD2(0, 8, 0, compact and 64 or 79))
    sub.Name = "Sub"
    cd.plate, cd.nm, cd.sub, cd.g, cd.pw, cd.ph, cd.px = plate, nm, sub, g, pw, ph, px
    return cd
  end
  local function fillStationCard(cd)
    local g = cd.g
    local wid, mixed = cardWeapon(g)
    local s = st.d.st[g.st[1]]
    if wid then
      local w = AD.W[wid]
      local n = AD.count(s, wid)
      -- 一架飞机一个比例尺（长的就是长），细长的导弹最多放大到 1.6 倍（不然一根头发丝）
      local px = math.min(cd.px * 1.6, K.artScale({ wid }, cd.pw, cd.ph, 3))
      K.weaponArt(cd.plate, wid, cd.pw, cd.ph, { px = px, n = (n > 1 and w.kind ~= "rkt") and 2 or 1 })
      cd.nm.Text = wname(wid) .. (mixed and " *" or "")
      cd.nm.TextColor3 = C.TEXT
      local sub = (w.kind == "rkt") and T("ws.tubes", w.tubes or n) or ((w.kind == "tank") and T("wcs.tank") or ("×" .. n .. " · " .. T("gds." .. (w.guide or "none"))))
      if #g.st > 1 and w.kind ~= "rkt" and w.kind ~= "tank" then sub = "×" .. (n * #g.st) .. " · " .. T("gds." .. (w.guide or "none")) end
      cd.sub.Text = sub
      cd:setState(st.sel == cd.ci and "sel" or "own")
    else
      for _, c in ipairs(cd.plate:GetChildren()) do if c.Name == "Art" then c:Destroy() end end
      cd.nm.Text = T("ws.empty")
      cd.nm.TextColor3 = C.FAINT
      cd.sub.Text = mixed and T("ws.mixed") or ""
      cd:setState(st.sel == cd.ci and "sel" or nil)
    end
    cd:setSel(st.sel == cd.ci)
  end
  local function buildBottom()
    local B = ws.bottom
    clear(B)
    ui.scards = {}
    local d = st.d
    local h = LAY.BH
    local vw = ws.vw()
    local barW = vw - 2 * LAY.M
    local xL = 0
    -- 航炮（固定卡）
    if d.gun then
      local gc = K.card(B, UD2(0, FIXW, 0, h), UD2(0, 0, 0, 0), { name = "GunCard" })
      gc:setState("own")
      K.text(gc.f, T("ws.gun"), S.tiny, "cond", C.MUTE, UD2(1, -16, 0, 14), UD2(0, 10, 0, 5)).Name = "Head"
      local pl = K.plate(gc.f, UD2(0, FIXW - 16, 0, compact and 26 or 34), UD2(0, 8, 0, compact and 20 or 22))
      K.gunArt(pl, d.gun, FIXW - 16, compact and 26 or 34)
      K.text(gc.f, wname(d.gun), compact and S.tiny or S.small, "bold", C.TEXT, UD2(1, -16, 0, 16), UD2(0, 10, 0, compact and 49 or 61)).Name = "Name"
      K.text(gc.f, T("ws.rounds", d.gunAmmo or 0), S.tiny, "mono", C.MUTE, UD2(1, -16, 0, 14), UD2(0, 10, 0, compact and 64 or 79)).Name = "Rounds"
      xL = FIXW + 13
      K.frame(B, UD2(0, 1, 0, h - 24), UD2(0, FIXW + 6, 0, 12), C.LINE, A.line).Name = "Div"
    end
    -- 右边：左右对称、干扰弹
    local xR = barW - FIXW
    do
      local it = st.it
      local t = G.treeState and G.treeState()
      local md = t and t.mods and t.mods[st.key]
      local fx = WMd.fx(it, md and md.done)
      local locked = not fx.flares
      local fc = K.card(B, UD2(0, FIXW, 0, h), UD2(0, xR, 0, 0), { name = "FlareCard", onClick = function()
        if locked and ws.openTab then ws.openTab("mods") end
      end })
      fc:setState(locked and "lock" or "own")
      K.text(fc.f, T("ws.flares"), S.tiny, "cond", C.MUTE, UD2(1, -16, 0, 14), UD2(0, 10, 0, 5)).Name = "Head"
      local pl = K.plate(fc.f, UD2(0, FIXW - 16, 0, compact and 26 or 34), UD2(0, 8, 0, compact and 20 or 22))
      K.flareArt(pl, FIXW - 16, compact and 26 or 34, { col = locked and C.FAINT or C.TEXT })
      local nm = K.text(fc.f, locked and T("ws.flaresLocked") or T("ws.rounds", d.flares or 0), compact and S.tiny or S.small, "bold",
        locked and C.FAINT or C.TEXT, UD2(1, -16, 0, 16), UD2(0, 10, 0, compact and 49 or 61))
      nm.Name = "Name"
      K.text(fc.f, locked and T("ws.flaresHow") or T("ws.flaresOn"), S.tiny, "cond", locked and C.FAINT or C.MUTE, UD2(1, -16, 0, 14),
        UD2(0, 10, 0, compact and 64 or 79)).Name = "Sub"
      ui.flareLocked = locked
      xR -= SYMW + 6
      local sc = K.frame(B, UD2(0, SYMW, 0, h), UD2(0, xR, 0, 0), C.PANEL, 0.12)
      sc.Name = "SymCard"
      TH.corner(sc)
      TH.stroke(sc)
      K.text(sc, T("ws.sym"), S.tiny, "cond", C.MUTE, UD2(1, -16, 0, 14), UD2(0, 10, 0, 5)).Name = "Head"
      ui.symSeg = K.seg(sc, { { key = true, text = T("ws.on"), name = "SymOn" }, { key = false, text = T("ws.off"), name = "SymOff" } },
        UD2(1, -16, 0, compact and 34 or 30), UD2(0, 8, 0, compact and 22 or 26), { name = "SymSeg", onPick = function(on)
          if on == st.sym then return end
          local keep = st.sel and st.cards[st.sel] and st.cards[st.sel].st[1]
          st.sym = on
          makeGroups()
          buildBottom()
          st.sel = keep and cardOfStation(keep) or nil
          st.hov = nil
          for _, cd in ipairs(ui.scards) do fillStationCard(cd) end
          buildList()
          applyHL()
          st.idle = 0
        end })
      ui.symSeg.set(st.sym)
      local note = K.text(sc, T("ws.symNote"), S.tiny, "body", C.FAINT, UD2(1, -16, 0, 28), UD2(0, 10, 0, compact and 58 or 62))
      note.TextWrapped, note.TextTruncate = true, Enum.TextTruncate.None
      note.TextYAlignment = Enum.TextYAlignment.Top
      xR -= 13
      K.frame(B, UD2(0, 1, 0, h - 24), UD2(0, xR + 6, 0, 12), C.LINE, A.line).Name = "Div"
    end
    -- 中间：挂点卡（放不下就横着卷）
    local area = Instance.new("ScrollingFrame")
    area.Name = "Stations"
    area.BackgroundTransparency = 1
    area.BorderSizePixel = 0
    area.ScrollBarThickness = compact and 0 or 3
    area.ScrollBarImageColor3 = C.MUTE
    area.ScrollingDirection = Enum.ScrollingDirection.X
    area.ClipsDescendants = true
    area.Size = UD2(0, math.max(10, xR - xL), 0, h + 4)
    area.Position = UD2(0, xL, 0, -2)
    area.Parent = B
    ui.area = area
    local n = #st.cards
    local need = n * (SCW + 6) - 6
    local avail = xR - xL
    local x0 = (need <= avail) and math.floor((avail - need) / 2) or 0
    area.CanvasSize = UD2(0, math.max(need, avail), 1, 0)
    -- 一架飞机的挂点卡一个比例尺（长的弹就是长）
    local all = {}
    for _, s in ipairs(st.d.st or {}) do for _, w in ipairs(s.opts) do all[#all + 1] = w end end
    local px = K.artScale(all, SCW - 12, compact and 26 or 34, 3)
    for ci, g in ipairs(st.cards) do
      local cd = stationCard(area, ci, g, x0 + (ci - 1) * (SCW + 6), px)
      cd.ci = ci
      cd.f.Position = UD2(0, x0 + (ci - 1) * (SCW + 6), 0, 2)
      cd.pos = cd.f.Position
      ui.scards[ci] = cd
      fillStationCard(cd)
    end
    if n == 0 then
      K.text(area, T("ws.noStations"), S.small, "body", C.FAINT, UD2(1, 0, 1, 0), nil, CENTER)
    end
  end

  ---------------------------------------------------------------- 3D 标签（每帧）

  local function buildTags()
    local layer = ws.labels
    clear(layer)
    st.tags = {}
    for i in ipairs(st.d.st or {}) do
      local tg = K.tag(layer, "Tag_" .. i)
      tg.b.MouseEnter:Connect(function() if st then st.hov = cardOfStation(i) applyHL() st.idle = 0 end end)
      tg.b.MouseLeave:Connect(function() if st and st.hov == cardOfStation(i) then st.hov = nil applyHL() end end)
      tg.b.Activated:Connect(function()
        if not st then return end
        local ci = cardOfStation(i)
        if ci and selectCard then selectCard((st.sel == ci) and nil or ci) end
      end)
      tg:show(false)
      st.tags[i] = tg
    end
  end
  -- 一行标签互相不压：先按想要的位置从左往右推开，超出右边再往左收，最后左边夹住
  local function spread(list, x0, x1, gap)
    local pos = {}
    for k, e in ipairs(list) do
      local c = e.want
      if k > 1 then c = math.max(c, pos[k - 1] + (list[k - 1].w + e.w) / 2 + gap) end
      pos[k] = c
    end
    for k = #list, 1, -1 do
      local lim = (k == #list) and (x1 - list[k].w / 2) or (pos[k + 1] - (list[k + 1].w + list[k].w) / 2 - gap)
      pos[k] = math.min(pos[k], lim)
    end
    for k = 1, #list do
      local lim = (k == 1) and (x0 + list[k].w / 2) or (pos[k - 1] + (list[k - 1].w + list[k].w) / 2 + gap)
      pos[k] = math.max(pos[k], lim)
    end
    return pos
  end
  local function placeTags()
    local A0 = G.hangarAir and G.hangarAir()
    if not (A0 and A0.key == st.key and Stage and st.anchor) then
      for _, tg in pairs(st.tags or {}) do tg:show(false) end
      return
    end
    local sc = ws.scale()
    local cam = workspace.CurrentCamera
    local camX = cam and A0.cf:PointToObjectSpace(cam.CFrame.Position).X or 0
    local cur = previewLoad() or st.load   -- 悬停预览时，选中那一对的标签写预览的那枚（3D 里换上的就是它）
    local gh = st.d.gearH or 6
    local floorY = 0
    local pts = {}
    for i, tg in pairs(st.tags) do
      local a = st.anchor[i]
      local sp, z, on = Stage.toScreen(A0.cf * a)
      if sp and on and z > 0 then
        local s = st.d.st[i]
        local wid = cur[i]
        local fsp = Stage.toScreen(A0.cf * V3(a.X, -gh, a.Z))   -- 挂点正下方的地面：标签排在机轮着地的那条线下面，不压在起落架上
        if fsp then floorY = math.max(floorY, fsp.Y / sc) end
        local far = (not s.bay) and math.abs(s.pos.X) > 1.5 and (s.pos.X * camX < 0)
        -- 平时只写编号（像图纸上的引线编号）；选中的、鼠标挂着的写「3 · 霹雳-15」
        local ci = cardOfStation(i)
        local full = ci ~= nil and (ci == st.sel or ci == st.hov)
        local txt = full and (st.num[i] .. " · " .. (wid and wname(wid) or T("ws.empty"))) or tostring(st.num[i])
        table.insert(pts, { i = i, x = sp.X / sc, y = sp.Y / sc, txt = txt, w = K.tagW(txt), far = far })
      else
        tg:show(false)
      end
    end
    if #pts == 0 then return end
    table.sort(pts, function(a, b) return a.x < b.x end)
    local x0, x1 = free3d()
    local avail = x1 - x0
    local total = 0
    for _, p in ipairs(pts) do total += p.w + 6 end
    local nRows = (total > avail * 0.95) and 2 or 1
    local maxY = 0
    for _, p in ipairs(pts) do maxY = math.max(maxY, p.y) end
    local bottomY = ws.vh() - LAY.BM - LAY.BH - LAY.GAP - 4
    local railY = math.clamp(math.max(maxY + 26, floorY + 10), LAY.TOP, math.max(LAY.TOP, bottomY - 18 - (nRows - 1) * 24))
    local rows = {}
    for r = 1, nRows do rows[r] = {} end
    for k, p in ipairs(pts) do
      local r = ((k - 1) % nRows) + 1
      p.want = p.x
      table.insert(rows[r], p)
    end
    local alpha = st.tagAlpha or 1
    for r, list in ipairs(rows) do
      local pos = spread(list, x0, x1, 6)
      for k, p in ipairs(list) do
        local tg = st.tags[p.i]
        local ci = cardOfStation(p.i)
        tg:show(alpha > 0.01)
        tg:place(p.x, p.y, pos[k], railY + (r - 1) * 24, { text = p.txt, empty = not cur[p.i], sel = ci ~= nil and ci == st.sel,
          hov = ci ~= nil and ci == st.hov, alpha = alpha * (p.far and 0.5 or 1) })
      end
    end
  end

  ---------------------------------------------------------------- 选挂点、悬停

  selectCard = function(ci)
    if not st then return end
    st.sel = ci
    st.hoverOpt = nil
    st.idle = 0
    if ui.detail then ui.detail.Visible = false end
    for _, cd in ipairs(ui.scards or {}) do fillStationCard(cd) end
    buildList()
    applyHL()
    if ci then stationView(ci) else overview() end
    -- 卷到选中的那张（手机上挂点卡横着卷）
    if ci and ui.area and ui.scards[ci] then
      pcall(function()
        local x = ui.scards[ci].pos.X.Offset
        local wv = ui.area.Size.X.Offset
        local cx = math.clamp(x - wv / 2 + SCW / 2, 0, math.max(0, ui.area.CanvasSize.X.Offset - wv))
        ui.area.CanvasPosition = V2(cx, 0)
      end)
    end
    show3d(st.load)
    updateRight()
  end
  -- 鼠标挂在一张武器卡上（on）/ 离开：右栏马上显示变化，3D 停 0.12 秒再换（扫过一列卡时不来回重搭）
  setHover = function(wid, on)
    if not st or not st.sel then return end
    st.hoverVer = (st.hoverVer or 0) + 1
    local ver = st.hoverVer
    st.idle = 0
    if on then
      st.hoverOpt = wid
      updateRight()
      local cd = nil
      for _, c in ipairs(ui.opts or {}) do if c.wid == wid then cd = c end end
      showDetail(wid, cd)
      task.delay(0.12, function()
        if st and st.hoverVer == ver and st.hoverOpt == wid then
          local pl = previewLoad()
          if pl then show3d(pl) end
        end
      end)
    else
      task.delay(0.06, function()
        if st and st.hoverVer == ver then
          st.hoverOpt = nil
          if ui.detail then ui.detail.Visible = false end
          updateRight()
          show3d(st.load)
        end
      end)
    end
  end

  refreshAll = function()
    if not st then return end
    for _, cd in ipairs(ui.scards or {}) do fillStationCard(cd) end
    refreshList()
    if not st.sel then buildManifest() end
    refreshChips()
    updateRight()
    applyHL()
  end

  ---------------------------------------------------------------- 打开 / 关上 / 每帧

  function P.open(it)
    local d = AD.get(it.play)
    if not d then return false end
    local load, pk, fuel = nil, nil, 1
    if G.treeAirLoad then load, pk, fuel = G.treeAirLoad(it) end
    load = load or AD.presetLoad(d)
    local t = G.treeState and G.treeState()
    local v = t and t.load and t.load[it.key]
    local savedP = (type(v) == "table") and (type(v.p) == "string") and v.p or nil
    if type(v) == "table" and type(v.l) == "table" and not savedP then pk = nil end   -- 存过、没记预设：自己配的（或我的方案）
    local D = nil
    if FM and d.kind == "jet" then D = FM.get(d.id, it.key) or (d.like and FM.get(d.like)) or nil end
    local empty = {}
    for i = 1, #(d.st or {}) do empty[i] = false end
    st = { it = it, key = it.key, d = d, D = D, jet = D ~= nil, load = load, pk = pk, fuel = AD.cleanFuel(fuel or 1), sym = true,
      sel = nil, hov = nil, hoverOpt = nil, perf = {}, shown = {}, empty = empty, idle = 0, tagAlpha = 0 }
    -- 打开时正好是哪一套「我的方案」
    for i = 1, 3 do
      local sv = setOf(i)
      if not st.pk and sv and same(sv.l, st.load) and math.abs(sv.f - st.fuel) < 1e-6 then st.mine = i end
    end
    numberStations()
    makeGroups()
    G.onHangarAir = onAir
    buildLeft()
    buildRight()
    buildDetail()
    buildBottom()
    buildTags()
    buildList()
    refreshChips()
    show3d(st.load)
    local A0 = G.hangarAir and G.hangarAir()
    if A0 and A0.key == st.key then onAir(A0) end
    -- 弹舱打开（0.6 秒）、镜头飞到全景；标签等镜头差不多到了再淡出来
    K.anim("wsBay", 0.6, "out", function(e) poseBay(e) end)
    overview(TH.T.cam)
    local mySt = st
    task.delay(TH.T.cam * 0.6, function()
      if st == mySt then K.anim("wsTags", TH.T.panel, "out", function(e) if st == mySt then st.tagAlpha = e end end) end
    end)
    updateRight()
    return true
  end
  function P.close(instant)
    if not st then return end
    local was = st
    st = nil
    K.stop("wsTags")
    K.stop("wsMount")
    K.stop("wsFlash")
    if G.onHangarAir == onAir then G.onHangarAir = nil end
    if Stage then Stage.unhighlight() end
    clear(ws.labels)
    if ui.detail then ui.detail.Visible = false end
    -- 3D 还原成存的那套；弹舱关上（0.3 秒）
    if G.hangarAirLoad then G.hangarAirLoad(nil) end
    if instant then
      K.stop("wsBay")
      if G.hangarAirPose then G.hangarAirPose(nil) end
    else
      K.anim("wsBay", 0.3, "out", function(e)
        if e >= 1 then
          if G.hangarAirPose then G.hangarAirPose(nil) end
        else
          poseBay(1 - e)
        end
      end)
    end
    local _ = was
  end
  -- Esc：选着挂点时先退回全景（再按一次退出整备）
  function P.esc()
    if st and st.sel then
      selectCard(nil)
      return true
    end
    return false
  end
  function P.step(dt)
    if not st then return end
    placeTags()
    -- 全景、几秒没动：慢慢转（拖过、滚过、悬停过都重新计时）
    if Stage then
      local vs = Stage.viewState()
      if st.lastYaw and (math.abs(vs.yaw - st.lastYaw) > 1e-4 or math.abs(vs.dist - (st.lastDist or vs.dist)) > 1e-3) then st.idle = 0 end
      st.idle += dt
      if not st.sel and st.idle > 6 and not vs.flying then
        Stage.focus({ at = vs.at, dist = vs.dist, yaw = vs.yaw + dt * 0.05, pitch = vs.pitch, tilt = vs.tilt, shift = vs.shift, t = 0 })
        vs = Stage.viewState()
      end
      st.lastYaw, st.lastDist = vs.yaw, vs.dist
    end
  end
  function P.refresh()   -- 存档变了（服务器推了新的 Tree：我的方案、改装研究完了）
    if not st then return end
    refreshChips()
    local t = G.treeState and G.treeState()
    local md = t and t.mods and t.mods[st.key]
    local fx = WMd.fx(st.it, md and md.done)
    if (not fx.flares) ~= ui.flareLocked then
      buildBottom()
      for _, cd in ipairs(ui.scards or {}) do fillStationCard(cd) end
    end
  end
  function P.relayout()
    if not st then return end
    buildBottom()
    for _, cd in ipairs(ui.scards or {}) do fillStationCard(cd) end
  end
  -- 测试、截图用：现在的状态、点某张挂点卡 / 武器卡
  function P.state() return st end
  function P.select(ci) selectCard(ci) end
  function P.ui() return ui end
  return P
end

return WsArms
