-- 全面大战场（客户端）——整备的「挂载」页（飞机、直升机；外壳是 Workshop.lua，零件是 WsKit.lua）
--   用户 11-27：「整个给载具配置武器的系统 做的很粗糙 我需要非常艺术经验的效果 参考战雷」——照同类写实军事游戏的做法（按挂点一个个配、换了 3D 马上跟着变、
--   写清楚正在改的是哪一套、重量和阻力数字比条重要），用我们自己的界面美术（docs/style.md；卡片和战斗里的弹药栏一套画法）：
--   舞台就是机库的停机坪（HangarStage：真光照、Highlight 描轮廓），起落架放着、弹舱打开、直升机旋翼停着；界面压在上面：
--   · 底部条：航炮（固定）│ 挂点卡（卡组的中点对准 3D 区的中点；左右对称时一对合成一张；顺序照全景画面上从左到右——全景从左前方看，右翼在画面左边，
--     卡片和机身上的编号一一对得上）│ 干扰弹（没研究锁住，点了去改装页）。卡组上面一行：名牌（鼠标挂着 / 选着的挂点：全称、类别、导引）、左右对称勾选框
--   · 机身上每个挂点：一个点、只走横竖的引线、一个键位框编号（每帧按 HangarStage.toScreen 摆，排在机轮着地线下面一行、互相不压）；
--     全景时只给镜头这一边的写编号，另一边只画淡点（悬停 / 选中一对时另一边那个也写，虚线引线 = 在机身后面）；选中的琥珀、后面跟名字；
--     镜头动着（飞向挂点、拖着转）时 0.12 秒淡掉，停稳了淡回来；落在两栏、资料卡、底部条底下的不画
--   · 左栏全景：方案（这一型的预设 + 三个「我的方案」）、状态行（照哪套改过 · 撤销）、挂载清单、提示；选了挂点：方案收成一行「‹ 方案 · 对地（已改 2）」，
--     下面挂点标题「挂点 3、8」（粗 17）+「中段 · 现在：霹雳-15 ×2」、武器卡（整张整张地放，放不下写「还有 N 种」；打开时卷到装着的那张）
--     鼠标挂在一张上：3D 先换上（停 0.12 秒才换，扫过去不来回重搭）、右栏琥珀的变化、旁边浮出资料卡（3D 小视口里这枚弹慢慢滚着转、四个关键数和已装的比）；
--     点一下装上（3D 里从挂架下滑上去、琥珀轮廓亮一下淡掉）；左右对称时一对一起换（同 Hangar.lua）。手机：第一次点是预览，再点一下才装上
--   · 右栏：当前挂载的外挂重量、阻力（ΔCD0）、起飞重量；性能比空挂（极速、推重比、持续转弯、爬升、翼载；悬停时换成「现在 → 换上」，红绿只说这次换上会怎样）；内油四档——
--     全部用飞行物理同一套算（FlightModel.loadout / perf：开飞机 Fly.lua 用的就是 loadout），不另编数；外挂重量上限仓库里没有数据，先不画上限。
--     直升机没有喷气机的飞行物理：只写重量（Fly.lua 直升机用的 AD.heavy）、续航（AD.fuelMin）、极速（副油箱的阻力，同 Fly.lua 的式子）
--   · 镜头：全景从左前下方看（按飞机大小、两栏中间那一段算距离；不自己转：转到正侧面构图就坏了），点一个挂点飞到它那一侧（偏航 ±125°，弹舱从下往上看）
--   改动即时存（Tech.lua treeLoad，不弹提示；车名右边的保存状态等服务器回了写「已保存」）、能撤销（最近 10 步：左栏「撤销」、Ctrl+Z）；
--   出击、试驾都按存的；「我的方案」存在 treeLoadSet（有内容的右键 / 长按：覆盖、清空）
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
  -- 武器卡第三行的三列：{ 射程 { 数, 单位 }, 锁定 / 发数 { 数, 单位 }, 每个挂点几枚 }（单位淡）
  local function colsOf(s, wid)
    local w = AD.W[wid]
    if not w then return {} end
    local n = AD.count(s, wid)
    local cnt = (n > 1) and ("×" .. n) or ""
    if w.kind == "tank" then return { { "+" .. math.floor(w.fuel * n * 100 + 0.5) .. "%", " " .. T("ws.unitFuel") }, nil, cnt } end
    if w.kind == "rkt" then return { w.range and { km(w.range), " km" } or nil, { tostring(w.tubes or n), " " .. T("ws.unitRk") }, "" } end
    if w.kind == "bomb" then
      local m = FM and FM.storeMass and FM.storeMass(w, AD.M) or nil
      return { m and { K.int(m), " kg" } or nil, nil, cnt }
    end
    return { w.range and { km(w.range), " km" } or nil, (w.lockTime and w.lockTime > 0) and { f1(w.lockTime), " s" } or nil, cnt }
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
  local function sameOn(d, a, b)
    for i = 1, #(d.st or {}) do if ((a and a[i]) or false) ~= ((b and b[i]) or false) then return false end end
    return true
  end
  local function same(a, b) return sameOn(st.d, a, b) end
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

  -- 全景的镜头（左前下方）：卡片按挂点在这个画面上从左到右的位置排（屏幕往右 = 机体的 (cos y, 0, −sin y) 方向）
  local OV_YAW, OV_PITCH = math.rad(-150), -0.06
  local function ovX(p) return p.X * math.cos(OV_YAW) - p.Z * math.sin(OV_YAW) end
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
  -- 底部的卡：左右对称时同名的一对合成一张；不对称时一个挂点一张。顺序：全景画面上从左到右（一对按镜头这一边那个算），和机身上的编号对得上
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
      table.sort(g.st, function(a, b) return st.num[a] < st.num[b] end)
      local rep = g.st[1]   -- 全景镜头那一边（左翼，X 小）的那个
      for _, i in ipairs(g.st) do if d.st[i].pos.X < d.st[rep].pos.X then rep = i end end
      g.rep = rep
      g.x, g.bay = ovX(d.st[rep].pos), d.st[rep].bay
      local nums = {}
      for _, i in ipairs(g.st) do table.insert(nums, tostring(st.num[i])) end
      g.nums = nums
      g.label = table.concat(nums, T("ws.sep"))   -- 「3、8」（编号里不用「·」：等宽小字里像小数点）
    end
    table.sort(out, function(a, b)
      if math.abs(a.x - b.x) > 1e-3 then return a.x < b.x end
      return st.num[a.st[1]] < st.num[b.st[1]]
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
  -- 换上（或者还原）3D 里挂的：TechUI 换模型（同一架、同一套搭过的直接换回来；镜头不动），搭好回调 onAir
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
  -- 全景按透视算准：飞机最外面的几个点（机头、机尾、翼尖、平尾尖、每个挂点、机轮着地点、直升机的桨盘）投到画面上，
  --   调镜头的远近和横移，让它们正好落在两栏中间那一段（左右各留 28 像素、高不超过栏高的六成）——斜着看时机头离镜头近（透视放大）、
  --   后掠翼的翼尖靠后，按外接方盒估会偏出去（翼尖那个挂点的编号被右栏盖住）
  local function framePts(d)
    local pts = {}
    local function add(x, y, z) pts[#pts + 1] = V3(x, y, z) end
    local L, W = d.L or 40, d.W or 30
    add(0, 0, -L / 2)
    add(0, 0, L / 2)
    add(0, (d.H or 12) * 0.6, L * 0.3)   -- 垂尾顶（大约）
    add(0, -(d.gearH or 6), 0)            -- 机轮着地
    local wg = d.wing
    if wg and wg.xt then
      for _, sx in ipairs({ -1, 1 }) do add(sx * wg.xt, wg.y or 0, ((wg.zt0 or 0) + (wg.zt1 or 0)) / 2) end
    elseif d.kind ~= "heli" then
      for _, sx in ipairs({ -1, 1 }) do add(sx * W / 2, 0, 0) end
    end
    local ht = d.htail
    if ht and ht.xt then for _, sx in ipairs({ -1, 1 }) do add(sx * ht.xt, ht.y or 0, ht.zt1 or (L / 2)) end end
    for _, s in ipairs(d.st or {}) do add(s.pos.X, s.pos.Y, s.pos.Z) end
    if d.kind == "heli" and d.rotor and d.rotor.r then   -- 桨盘按八成算（桨尖伸到两栏底下没关系）
      local h0 = d.rotor.hub or V3(0, (d.H or 12) * 0.5, 0)
      local r = d.rotor.r * 0.8
      add(h0.X + r, h0.Y, h0.Z)
      add(h0.X - r, h0.Y, h0.Z)
      add(h0.X, h0.Y, h0.Z + r)
      add(h0.X, h0.Y, h0.Z - r)
    end
    -- 搭好的模型（原模型的翼展、挂点和型号表的数不完全一样）：挂点上的弹、所有零件的中心也算上（fitView 里只留沿画面横竖最外面的那几个）
    local A0 = G.hangarAir and G.hangarAir()
    if A0 and A0.key == st.key and A0.M and A0.M.model then
      for _, a in pairs(st.anchor or {}) do pts[#pts + 1] = a end
      local cand = {}
      for _, x in ipairs(A0.M.model:GetDescendants()) do
        if x:IsA("BasePart") and x.Transparency < 0.9 then cand[#cand + 1] = A0.cf:PointToObjectSpace(x.Position) end
      end
      pts.model = cand
      -- 旋翼（直升机）：桨叶的零件中心在半径中间，桨尖按上面的八成那几个点算
    end
    return pts
  end
  local function fitView(d, yaw, pitch)
    local vw, vh = ws.vw(), ws.vh()
    local tv = tanV()
    local tanH = tv * vw / math.max(vh, 1)
    local x0, x1 = free3d()
    local lx, rx = x0 + 28, x1 - 28
    local cxT, wantW, wantH = (lx + rx) / 2, rx - lx, ws.colH() * 0.6
    local cp = math.cos(pitch)
    local f = -V3(math.sin(yaw) * cp, math.sin(pitch), math.cos(yaw) * cp)   -- 镜头往哪看（从镜头指向目标）
    local r = f:Cross(V3(0, 1, 0)).Unit
    local u = r:Cross(f)
    local gh = d.gearH or 6
    local off = V3(0, gh * 0.08, 0)   -- 镜头看的那一点（gearH × 0.92）在机身原点下面一点
    local pts = framePts(d)
    if pts.model and #pts.model > 0 then   -- 模型零件：沿画面横 / 竖方向各取最外面几个（几百个零件全投影一遍太慢）
      local m = pts.model
      local function keep(axis, k)
        table.sort(m, function(a, b) return a:Dot(axis) < b:Dot(axis) end)
        for i = 1, math.min(k, #m) do pts[#pts + 1] = m[i] end
        for i = math.max(1, #m - k + 1), #m do pts[#pts + 1] = m[i] end
      end
      keep(r, 8)
      keep(u, 4)
      pts.model = nil
    end
    local function ext(D, sh)
      local mn, mx, ymn, ymx = math.huge, -math.huge, math.huge, -math.huge
      for _, p in ipairs(pts) do
        local q = p + off
        local dep = D + q:Dot(f)
        if dep > 1 then
          local sx = vw / 2 * (1 + (q:Dot(r) - sh) / (dep * tanH))
          local sy = vh / 2 * (1 - q:Dot(u) / (dep * tv))
          mn, mx = math.min(mn, sx), math.max(mx, sx)
          ymn, ymx = math.min(ymn, sy), math.max(ymx, sy)
        end
      end
      return mn, mx, ymn, ymx
    end
    local function centerShift(D)   -- 横移：最左、最右两个点的中点对准两栏中间
      local sh = 0
      for _ = 1, 5 do
        local mn, mx = ext(D, sh)
        if mn == math.huge then break end
        sh += ((mn + mx) / 2 - cxT) * (D * tanH) / (vw / 2)
      end
      return sh
    end
    local lo, hi = 5, 4000
    for _ = 1, 30 do
      local D = (lo + hi) / 2
      local mn, mx, ymn, ymx = ext(D, centerShift(D))
      if mn == math.huge or mx - mn > wantW or ymx - ymn > wantH then lo = D else hi = D end
    end
    return hi, centerShift(hi)
  end
  local function overview(t)
    local d = st.d
    local ok, dist, sh = pcall(fitView, d, OV_YAW, OV_PITCH)
    if not ok or not dist then   -- 算不出来（不该发生）：照外接方盒估
      dist = fitDist(d, OV_YAW, OV_PITCH)
      local x0, x1 = free3d()
      sh = shiftFor(dist, (x0 + x1) / 2)
    end
    if Stage then
      Stage.focus({ at = V3(0, (d.gearH or 6) * 0.92, 0), dist = dist, yaw = OV_YAW, pitch = OV_PITCH, shift = sh, t = t })
    end
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
  end

  ---------------------------------------------------------------- 界面零件（左栏、右栏、底部条、标签层、资料卡）：每次打开按这一架重建

  local ui = {}
  -- 清空一块（只删界面零件：面板自己的 UIGradient / UIStroke / UICorner 留着）
  local function clear(f) for _, c in ipairs(f:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end end
  -- 分节标题换字（线跟着字的宽挪）
  local function setHeader(h, str)
    if not h or not h.t then return end
    h.t.Text = str
    local tw = K.textW(str, S.small) + 8
    h.ln.Size = UD2(0, math.max(0, h.w - tw), 0, 1)
    h.ln.Position = UD2(0, h.x + tw, 0, h.y + 8)
  end
  local function header(parent, str, y, w, x)
    local t, ln = K.header(parent, str, y, w, x)
    return { t = t, ln = ln, w = w, x = x or 12, y = y }
  end

  -- 左栏：全景（方案、状态行、挂载清单、提示）/ 选了挂点（收起的方案行、挂点标题、武器卡）
  local CH = compact and 54 or 62   -- 武器卡的高（桌面一屏放得下 5 张整卡 +「还有 N 种」）
  local PW, PH = compact and 76 or 104, compact and 28 or 40   -- 卡上那块图
  local CHIP_H = compact and 44 or 28   -- 小块的高（手机能点的东西 ≥ 44）
  local refreshAll, selectCard, setHover, buildList, updateRight, refreshChips, layoutLeft, refreshListLook, updatePlate, setHov
  local closeMenu, showUndo

  ---------------------------------------------------------------- 改动：撤销、存、3D、刷新

  local function snap() return { load = table.clone(st.load), pk = st.pk, mine = st.mine, fuel = st.fuel } end
  -- 存（即时存，不弹提示）：车名右边的保存状态等服务器推回来的存档里真有这一套才写「已保存」；4 秒没回「没存上 · 重试」
  local function save()
    local key, d, l, pk, f = st.key, st.d, table.clone(st.load), st.pk, st.fuel
    local function send()
      if G.treeSaveLoad then G.treeSaveLoad(key, l, pk, f, true) end
    end
    local function check()
      local t = G.treeState and G.treeState()
      local v = t and t.load and t.load[key]
      if type(v) ~= "table" or type(v.l) ~= "table" then return false end
      return sameOn(d, AD.cleanLoad(d, v.l), l) and math.abs(AD.cleanFuel(v.f) - f) < 1e-6
    end
    local function arm()
      if ws.saving then ws.saving(check, function()
        send()
        arm()
      end) end
    end
    -- 存档里已经是这一套（只换了「我的方案」那一格的选中、或者原样点回来）：不发（服务器的存档不会变，也就等不到回音）
    local t = G.treeState and G.treeState()
    local v = t and t.load and t.load[key]
    if type(v) == "table" and type(v.l) == "table" and sameOn(d, AD.cleanLoad(d, v.l), l) and math.abs(AD.cleanFuel(v.f) - f) < 1e-6
      and (v.p or false) == (pk or false) then return end
    send()
    arm()
  end
  -- 换成新的一套（点了装上、换预设、读我的方案、改内油、撤销）：记一步撤销、存、3D 跟着换（新挂上的从挂架下滑上去）、界面刷新（数字滚动）
  --   一样的不动（也不发服务器）
  local function commit(nl, pk, mine, fuel, why)
    local before = snap()
    if same(before.load, nl) and before.pk == pk and before.mine == mine and math.abs(before.fuel - fuel) < 1e-6 then return false end
    if why ~= "undo" then
      table.insert(st.undo, before)
      if #st.undo > 10 then table.remove(st.undo, 1) end
    end
    local changed = {}
    for i = 1, #(st.d.st or {}) do
      local a, b = st.load[i] or false, nl[i] or false
      if a ~= b and b then table.insert(changed, i) end
    end
    st.load, st.pk, st.mine, st.fuel = nl, pk, mine, fuel
    st.pendingMount = (#changed > 0) and changed or nil
    local rebuilt = show3d(st.load)
    if not rebuilt and st.pendingMount then
      local m = st.pendingMount
      st.pendingMount = nil
      mountAnim(m)
    end
    save()
    refreshAll(true)
    showUndo(#st.undo > 0)
    return true
  end
  function P.undo()
    if not st or #st.undo == 0 then return false end
    closeMenu()
    local s0 = table.remove(st.undo)
    st.hoverOpt = nil
    ws.detailShow(false)
    commit(s0.load, s0.pk, s0.mine, s0.fuel, "undo")
    return true
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
  local function choosePreset(key)
    closeMenu()
    st.hoverOpt = nil
    commit(AD.presetLoad(st.d, key), key, nil, st.fuel, "preset")
  end

  ---------------------------------------------------------------- 我的方案

  -- 存上了：这一格自己反馈（一圈琥珀描边 0.6 秒淡掉），不跳到抬头去
  local function flashSlot(ch)
    local fl = ch.f:FindFirstChild("SavedFlash") or K.frame(ch.f, UD2(1, 0, 1, 0), nil, nil, 1)
    fl.Name = "SavedFlash"
    TH.corner(fl)
    local s = TH.stroke(fl)
    s.Color, s.Transparency = C.WARN, 0
    TH.tween(s, { Transparency = 1 }, 0.6, "out")
  end
  local function mineSave(i)
    if G.treeSaveSet then G.treeSaveSet(st.key, i, st.load, st.fuel) end
    st.mine = i
    refreshChips()
    if ui.mine[i] then flashSlot(ui.mine[i]) end
  end
  local function mineClear(i)
    if G.treeSaveSet then G.treeSaveSet(st.key, i, false) end
    if st.mine == i then st.mine = nil end
    refreshChips()
  end
  local function mineClick(i)
    closeMenu()
    local v = setOf(i)
    if v then
      st.hoverOpt = nil
      if not commit(v.l, nil, i, v.f, "mine") then
        st.mine, st.pk = i, nil
        refreshChips()
      end
    else
      mineSave(i)
    end
  end
  closeMenu = function()
    if ui.menu then
      ui.menu:Destroy()
      ui.menu = nil
    end
  end
  -- 有内容的一格右键 / 长按：小菜单「覆盖成现在这套 / 清空」
  local function openMenu(i)
    closeMenu()
    local ch = ui.mine and ui.mine[i]
    if not ch then return end
    local ih = compact and 44 or 28
    local mw = compact and 176 or 156
    local p = ch.f.Position
    local m = K.panel(ws.left, UD2(0, mw, 0, 2 * ih + 8), UD2(0, math.min(p.X.Offset, LAY.LW - 12 - mw), 0, p.Y.Offset + ch.f.Size.Y.Offset + 4), nil, 0.02)
    m.Name = "MineMenu"
    m.ZIndex = 10
    for k, it in ipairs({ { "Over", T("ws.mineOver"), function() mineSave(i) end }, { "Clear", T("ws.mineClear"), function() mineClear(i) end } }) do
      local b = K.button(m, UD2(1, -8, 0, ih), UD2(0, 4, 0, 4 + (k - 1) * ih), "Mine_" .. it[1])
      b.ZIndex = 11
      local t = K.text(b, it[2], S.small, "bold", C.MUTE, UD2(1, -16, 1, 0), UD2(0, 8, 0, 0))
      t.ZIndex = 12
      b.MouseEnter:Connect(function() t.TextColor3 = C.TEXT end)
      b.MouseLeave:Connect(function() t.TextColor3 = C.MUTE end)
      b.Activated:Connect(function()
        closeMenu()
        it[3]()
      end)
    end
    ui.menu = m
  end
  -- 一格：有内容的同预设小块（我的 1，选中 / 已改）；空着的只画淡的键位框「1」和「＋」（悬停写「存当前」）
  local function mineSlot(parent, i, size, pos)
    local ch
    ch = K.chip(parent, "", size, pos, { name = "Mine_" .. i, onClick = function()
      if ui.menuJust then
        ui.menuJust = false
        return
      end
      mineClick(i)
    end })
    local h = size.Y.Offset
    local kb = K.keyBox(ch.f, tostring(i), 8, math.floor((h - 14) / 2), C.FAINT, "Key")
    local pl = K.plus(ch.f, 30, math.floor((h - 9) / 2), 9, C.FAINT)
    local hint = K.text(ch.f, T("ws.mineEmpty"), S.tiny, "bold", C.MUTE, UD2(1, -46, 1, 0), UD2(0, 44, 0, 0))
    hint.Name = "Hint"
    hint.Visible = false
    ch.key, ch.plus, ch.hint = kb, pl, hint
    ch.f.MouseEnter:Connect(function() if ch.empty then hint.Visible = true end end)
    ch.f.MouseLeave:Connect(function() hint.Visible = false end)
    ch.f.InputBegan:Connect(function(io)
      if io.UserInputType == Enum.UserInputType.MouseButton2 then
        if not ch.empty then openMenu(i) end
      elseif io.UserInputType == Enum.UserInputType.Touch then   -- 长按 0.5 秒
        local tok = {}
        ch.hold = tok
        task.delay(0.5, function()
          if ch.hold == tok and not ch.empty and st then
            ui.menuJust = true
            openMenu(i)
          end
        end)
      end
    end)
    ch.f.InputEnded:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch then ch.hold = nil end end)
    return ch
  end

  ---------------------------------------------------------------- 左栏

  local function buildLeft()
    local Lf = ws.left
    clear(Lf)
    ui.menu = nil
    local w = LAY.LW - 24
    ui.chips, ui.mine = {}, {}
    local presets = st.d.presets or {}
    -- 全景：方案
    local schemeBox = K.frame(Lf, UD2(1, 0, 0, 10), nil, nil, 1)
    schemeBox.Name = "Schemes"
    ui.schemeBox = schemeBox
    local y = 10
    K.header(schemeBox, T("ws.schemes"), y, w)
    y += 22
    local cols = 3
    local G6 = 6
    local CW = math.floor((w - (cols - 1) * G6) / cols)
    for k, p in ipairs(presets) do
      local r, c = math.floor((k - 1) / cols), (k - 1) % cols
      local ch = K.chip(schemeBox, T("preset." .. p.key), UD2(0, CW, 0, CHIP_H), UD2(0, 12 + c * (CW + G6), 0, y + r * (CHIP_H + G6)), {
        name = "Preset_" .. p.key,
        onClick = function() choosePreset(p.key) end })
      ui.chips[p.key] = ch
    end
    y += math.max(1, math.ceil(#presets / cols)) * (CHIP_H + G6) + 6
    K.header(schemeBox, T("ws.mine"), y, w)
    y += 22
    for i = 1, 3 do ui.mine[i] = mineSlot(schemeBox, i, UD2(0, CW, 0, CHIP_H), UD2(0, 12 + (i - 1) * (CW + G6), 0, y)) end
    y += CHIP_H + 8
    ui.status = K.text(schemeBox, "", S.tiny, "bold", C.MUTE, UD2(0, w - 48, 0, 16), UD2(0, 12, 0, y))
    ui.status.Name = "LoadStatus"
    ui.statusY = y
    y += 24
    schemeBox.Size = UD2(1, 0, 0, y)
    ui.schemeH = y
    -- 全景：挂载清单、提示
    ui.manifest = K.frame(Lf, UD2(1, 0, 0, 10), UD2(0, 0, 0, y), nil, 1)
    ui.manifest.Name = "Manifest"
    ui.hint = K.text(Lf, T(compact and "ws.pickTouch" or "ws.pick"), S.tiny, "body", C.FAINT, UD2(0, w, 0, 16), UD2(0, 12, 0, y))
    ui.hint.Name = "PickHint"
    -- 选了挂点：方案收成一行「‹ 方案 · 对地（已改 2）」（点了回全景）
    local sbox = K.frame(Lf, UD2(1, 0, 1, 0), nil, nil, 1)
    sbox.Name = "StationBox"
    ui.sbox = sbox
    local rowH = CHIP_H
    local row = K.button(sbox, UD2(1, -24, 0, rowH), UD2(0, 12, 0, 4), "BackToSchemes")
    local chev = K.chevron(row, 0, math.floor(rowH / 2) - 6, 12, C.MUTE)
    local rl = K.text(row, "", S.small, "bold", C.MUTE, UD2(1, -66, 1, 0), UD2(0, 18, 0, 0))
    rl.Name = "Label"
    row.MouseEnter:Connect(function()
      rl.TextColor3 = C.TEXT
      K.tintChevron(chev, C.TEXT)
    end)
    row.MouseLeave:Connect(function()
      rl.TextColor3 = C.MUTE
      K.tintChevron(chev, C.MUTE)
    end)
    row.Activated:Connect(function() if selectCard then selectCard(nil) end end)
    K.frame(sbox, UD2(1, -24, 0, 1), UD2(0, 12, 0, 4 + rowH + 2), C.LINE, A.line).Name = "RowLine"
    ui.schemeRow, ui.schemeRowT = row, rl
    local hy = 4 + rowH + 6
    ui.stHead = K.text(sbox, "", compact and S.body or S.sub, "bold", C.TEXT, UD2(0, w - 56, 0, 22), UD2(0, 12, 0, hy))
    ui.stHead.Name = "StationHead"
    ui.stPos = K.text(sbox, "", compact and S.tiny or S.small, "bold", C.MUTE, UD2(0, w, 0, 16), UD2(0, 12, 0, hy + (compact and 20 or 22)))
    ui.stPos.Name = "StationPos"
    ui.bayTag = K.frame(sbox, UD2(0, 40, 0, 16), UD2(1, -12, 0, hy + 3), C.PANEL, 1, V2(1, 0))
    ui.bayTag.Name = "BayTag"
    TH.stroke(ui.bayTag).Transparency = 0.6
    TH.corner(ui.bayTag)
    K.text(ui.bayTag, T("ws.bay"), S.tiny, "bold", C.MUTE, UD2(1, 0, 1, 0), nil, CENTER).Name = "Text"
    local listY = hy + (compact and 40 or 44)
    ui.listY = listY
    local list = Instance.new("ScrollingFrame")
    list.Name = "Weapons"
    list.BackgroundTransparency = 1
    list.BorderSizePixel = 0
    list.ScrollBarThickness = compact and 0 or 3
    list.ScrollBarImageColor3 = C.MUTE
    list.ScrollBarImageTransparency = 0.3
    list.ScrollingDirection = Enum.ScrollingDirection.Y
    list.ClipsDescendants = true
    list.CanvasSize = UD2(0, 0, 0, 0)
    list.Size = UD2(1, -18, 0, 100)
    list.Position = UD2(0, 12, 0, listY)
    list.Parent = sbox
    ui.list = list
    ui.more = K.text(sbox, "", S.tiny, "bold", C.FAINT, UD2(0, w, 0, 14), UD2(0, 12, 0, listY + 100))
    ui.more.Name = "More"
    list:GetPropertyChangedSignal("CanvasPosition"):Connect(function() if ui.updateMore then ui.updateMore() end end)
    -- 撤销（换了预设、我的方案、一对挂点、内油以后 5 秒）：状态行 / 收起的方案行右边一个文字键
    local ub = Instance.new("TextButton")
    ub.Name = "Undo"
    ub.AutoButtonColor = false
    ub.BackgroundTransparency = 1
    ub.BorderSizePixel = 0
    ub.Text = T("ws.undo")
    ub.Font = TH.F.bold
    ub.TextSize = S.tiny
    ub.TextColor3 = C.MUTE
    ub.TextXAlignment = RIGHT
    ub.Size = UD2(0, 44, 0, compact and 44 or 18)
    ub.AnchorPoint = V2(1, 0.5)
    ub.Visible = false
    ub.ZIndex = 3
    ub.Parent = Lf
    ub.MouseEnter:Connect(function() ub.TextColor3 = C.TEXT end)
    ub.MouseLeave:Connect(function() ub.TextColor3 = C.MUTE end)
    ub.Activated:Connect(function() P.undo() end)
    ui.undo = ub
  end
  showUndo = function(on)
    local ub = ui.undo
    if not ub then return end
    ui.undoTok = {}
    local tok = ui.undoTok
    ub.Visible = on == true
    if on then task.delay(5, function() if ui.undoTok == tok and ub.Parent then ub.Visible = false end end) end
  end

  -- 挂载清单（全景时左栏下半）：航炮在最前，然后按类（空空、空地、炸弹、火箭巢、副油箱），一种一行：小图、短名、类别、几枚
  local CAT_ORDER = { aam = 1, agm = 2, bomb = 3, rkt = 4, tank = 5 }
  local function buildManifest()
    local box = ui.manifest
    if not box then return 0 end
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
    K.header(box, T("ws.manifest"), 4, w)
    local RH = compact and 24 or 30
    local PWm, PHm = compact and 48 or 64, compact and 16 or 20
    local maxRows = math.max(1, math.floor((ws.colH() - (ui.schemeH or 0) - 26 - (compact and 6 or 32)) / RH))
    local all = {}
    for _, r in ipairs(rows) do if r.wid then all[#all + 1] = r.wid end end
    local px = K.artScale(all, PWm, PHm, 2)
    local nShown = 0
    for k, r in ipairs(rows) do
      if k > maxRows then break end
      nShown = k
      local row = K.frame(box, UD2(0, w, 0, RH - 4), UD2(0, 12, 0, 26 + (k - 1) * RH), nil, 1)
      row.Name = "Man_" .. (r.wid or r.gun)
      local lb = K.lightbox(row, UD2(0, PWm, 0, PHm), UD2(0, 0, 0.5, -PHm / 2))
      if r.gun then K.gunArt(lb, r.gun, PWm, PHm) else K.weaponArt(lb, r.wid, PWm, PHm, { px = px }) end
      local Wd = r.wid and AD.W[r.wid]
      K.text(row, r.gun and wname(r.gun) or wname(r.wid), S.small, "bold", C.TEXT, UD2(0, w - PWm - 104, 1, 0), UD2(0, PWm + 10, 0, 0)).Name = "Name"
      local cat = r.gun and T("wcs.gun") or T("wcs." .. catOf(Wd))
      K.text(row, cat, S.tiny, "cond", C.MUTE, UD2(0, 64, 1, 0), UD2(1, -44, 0, 0), RIGHT, V2(1, 0)).Name = "Cat"
      local cntT = r.gun and tostring(r.n) or ("×" .. r.n)
      K.text(row, cntT, S.small, "mono", C.TEXT, UD2(0, 40, 1, 0), UD2(1, 0, 0, 0), RIGHT, V2(1, 0)).Name = "Count"
    end
    local h = 26 + nShown * RH
    if #order == 0 then
      K.text(box, T("ws.manifestEmpty"), S.small, "body", C.FAINT, UD2(0, w, 0, 18), UD2(0, 12, 0, h)).Name = "Empty"
      h += 22
    end
    box.Size = UD2(1, 0, 0, h)
    return h
  end

  -- 武器卡（左栏）：左边 104 × 40 的图（平时灰、装着的 / 鼠标挂着的白）、标题（粗 15）、「类别 · 导引」、第三行三列（射程 · 锁定 · 每个挂点几枚，按列对齐、单位淡）；
  --   装着的：左边 2 像素白竖条 + 右上「已装」（粗 12 灰）
  local function cell(parent, data, x, w, y)
    local l = K.text(parent, "", S.tiny, "mono", C.TEXT, UD2(0, w, 0, 16), UD2(0, x, 0, y), RIGHT)
    l.RichText = true
    l.Text = data and K.rich({ { data[1] }, { data[2], C.FAINT } }, S.tiny) or ""
    return l
  end
  local pickWeapon
  local function weaponCard(parent, k, wid, s, px)
    local y = (k - 1) * (CH + 6)
    local wcard = K.card(parent, UD2(1, -6, 0, CH), UD2(0, 0, 0, y), {
      name = "Opt_" .. (wid or "none"),
      onEnter = function() if not compact and setHover then setHover(wid, true) end end,
      onLeave = function() if not compact and setHover then setHover(wid, false) end end,
      onClick = function() if pickWeapon then pickWeapon(wid) end end })
    local f = wcard.f
    local w = wid and AD.W[wid]
    local px0 = compact and 8 or 10
    wcard.wid = wid
    if w then
      wcard.lb = K.lightbox(f, UD2(0, PW, 0, PH), UD2(0, px0, 0.5, -PH / 2))
      wcard.artPx = math.min(px * 1.5, K.artScale({ wid }, PW, PH, 4))
      local tx = px0 + PW + 10
      local t1 = K.text(f, wname(wid), compact and S.small or S.body, "bold", C.TEXT, UD2(1, -(tx + 46), 0, 18), UD2(0, tx, 0, compact and 3 or 4))
      t1.Name = "Name"
      local t2 = K.text(f, subOf(w, compact), compact and S.tiny or S.small, "cond", C.MUTE, UD2(1, -(tx + 8), 0, 16), UD2(0, tx, 0, compact and 19 or 23))
      t2.Name = "Sub"
      local cols = colsOf(s, wid)
      local y3 = compact and 34 or 41
      cell(f, cols[1], tx, compact and 54 or 60, y3).Name = "Range"
      if not compact then cell(f, cols[2], tx + 60, 48, y3).Name = "Lock" end
      local cn = K.text(f, cols[3] or "", S.tiny, "mono", C.TEXT, UD2(0, 36, 0, 16), UD2(1, -10, 0, y3), RIGHT, V2(1, 0))
      cn.Name = "Count"
    else   -- 不挂：虚线框
      wcard.st.Transparency = 1
      wcard.restT = 1
      wcard.f.BackgroundTransparency = 0.6
      K.dashed(f, LAY.LW - 24, CH, C.LINE, 0.55)
      local t1 = K.text(f, T("ws.none"), compact and S.small or S.body, "bold", C.TEXT, UD2(1, -24, 0, 18), UD2(0, 16, 0, CH / 2 - 18))
      t1.Name = "Name"
      local t2 = K.text(f, T("ws.noneSub"), S.small, "cond", C.MUTE, UD2(1, -24, 0, 16), UD2(0, 16, 0, CH / 2 + 2))
      t2.Name = "Sub"
    end
    local tag = K.text(f, T("ws.equipped"), S.tiny, "bold", C.MUTE, UD2(0, 60, 0, 14), UD2(1, -10, 0, compact and 4 or 6), RIGHT, V2(1, 0))
    tag.Name = "Equipped"
    tag.Visible = false
    local tx0 = (compact and 8 or 10) + PW + 10
    local again = K.text(f, T("ws.tapAgain"), S.tiny, "bold", C.MUTE, UD2(1, -(tx0 + 8), 0, 16), UD2(0, tx0, 0, compact and 19 or 23))
    again.Name = "TapAgain"
    again.Visible = false
    wcard.tag, wcard.again, wcard.sub = tag, again, f:FindFirstChild("Sub")
    return wcard
  end
  -- 卡上跟着状态走的：装着的（白竖条、「已装」）、鼠标挂着 / 预览着的（图变白；手机写「再点一下装上」）——不重建（鼠标还挂在卡上，重建了悬停就断了）
  refreshListLook = function()
    local g = st.sel and st.cards[st.sel]
    if not g then return end
    local cur, mixed = cardWeapon(g)
    for _, cd in ipairs(ui.opts or {}) do
      local own = (not mixed) and (cur or false) == (cd.wid or false)
      local pv = st.hoverOpt ~= nil and (st.hoverOpt or false) == (cd.wid or false)
      cd:setOwn(own)
      cd.tag.Visible = own and not (compact and pv)
      cd.again.Visible = compact and pv and not own
      if cd.sub then cd.sub.Visible = not cd.again.Visible end
      if compact then cd:setHover(pv) end
      if cd.lb then
        local hot = own or pv or cd.hov
        if cd.hot ~= hot then
          cd.hot = hot
          K.weaponArt(cd.lb, cd.wid, PW, PH, { px = cd.artPx, col = hot and C.TEXT or C.MUTE })
        end
      end
    end
  end

  buildList = function()
    if not ui.list then return end
    clear(ui.list)
    ui.opts = {}
    local g = st.sel and st.cards[st.sel]
    if not g then return end
    local d = st.d
    local s = d.st[g.st[1]]
    local cur = cardWeapon(g)
    local Wc = cur and AD.W[cur]
    ui.stHead.Text = T("ws.station", g.label)
    local now = Wc and (wname(cur) .. ((AD.count(s, cur) > 1 and Wc.kind ~= "rkt") and (" ×" .. AD.count(s, cur)) or "")) or T("ws.emptyNow")
    ui.stPos.Text = posName(s) .. " · " .. T("ws.now", now)
    ui.bayTag.Visible = g.bay ~= nil
    local opts = table.clone(s.opts)
    table.insert(opts, false)
    local px = K.artScale(s.opts, PW, PH, 4)
    local kCur = #opts
    for k, wid in ipairs(opts) do
      local cd = weaponCard(ui.list, k, wid, s, px)
      table.insert(ui.opts, cd)
      K.reveal(cd.f, k)
      if (wid or false) == (cur or false) then kCur = k end
    end
    -- 列表多高：整张整张地放（放不下的写「还有 N 种」），多出来的给面板留白
    local avail = ws.colH() - ui.listY - 6
    local nFit = math.max(1, math.floor((avail + 6) / (CH + 6)))
    if nFit < #opts then nFit = math.max(1, math.floor((avail - 18 + 6) / (CH + 6))) end
    nFit = math.min(nFit, #opts)
    local listH = nFit * (CH + 6) - 6
    ui.listH, ui.listMore = listH, nFit < #opts
    ui.list.Size = UD2(1, -18, 0, listH)
    ui.list.CanvasSize = UD2(0, 0, 0, #opts * (CH + 6) - 6)
    ui.more.Position = UD2(0, 12, 0, ui.listY + listH + 4)
    ui.nFit = nFit
    -- 卷到装着的那张（放在中间）
    local maxY = math.max(0, #opts * (CH + 6) - 6 - listH)
    local cy = math.clamp((kCur - 1) * (CH + 6) - (listH - CH) / 2, 0, maxY)
    ui.list.CanvasPosition = V2(0, math.floor(cy / (CH + 6) + 0.5) * (CH + 6))
    ui.updateMore = function()
      local okc, cp = pcall(function() return ui.list.CanvasPosition end)
      local top = (okc and cp) and math.floor(cp.Y / (CH + 6) + 0.5) or 0
      local below = math.max(0, #opts - (top + nFit))
      ui.more.Text = (below > 0) and T("ws.more", below) or ""
    end
    ui.updateMore()
    refreshListLook()
    if ws.detailAt then ws.detailAt(LAY.TOP + ui.listY) end
  end

  -- 左栏两种样子：全景（方案 + 清单 + 提示，高度跟着内容走）/ 选了挂点（整栏）
  layoutLeft = function(instant)
    local g = st.sel and st.cards[st.sel]
    local ov = g == nil
    ui.schemeBox.Visible = ov
    ui.manifest.Visible = ov
    ui.hint.Visible = ov and not compact   -- 手机放不下（第一次点武器卡时卡上自己写「再点一下装上」）
    ui.sbox.Visible = not ov
    local w = LAY.LW - 24
    if ov then
      local mh = buildManifest()
      local hy = ui.schemeH + mh + 6
      ui.hint.Position = UD2(0, 12, 0, hy)
      ui.undo.Position = UD2(0, 12 + w, 0, ui.statusY + 8)
      ws.fitCol("left", compact and (hy + 4) or (hy + 26), instant)
    else
      buildList()
      ui.undo.Position = UD2(0, 12 + w, 0, 4 + CHIP_H / 2)
      -- 栏高到最后一张卡（有「还有 N 种」再加一行）为止：只有三四种可挂的时候下面不留半截空面板
      ws.fitCol("left", ui.listY + (ui.listH or 0) + (ui.listMore and 22 or 0) + 10, instant)
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
      local on = st.mine == i and v ~= nil
      local modded = on and not (same(v.l, st.load) and math.abs(v.f - st.fuel) < 1e-6)
      ch.empty = v == nil
      ch.t.Text = v and T("ws.mineN", i) or ""
      ch.key.Visible, ch.plus.Visible = v == nil, v == nil
      if v ~= nil then ch.hint.Visible = false end
      ch:set(on, modded and T("ws.modTag") or nil)
      if v == nil then   -- 空格：不画框（只有键位框和加号）
        local s = ch.f:FindFirstChildOfClass("UIStroke")
        if s then s.Transparency = 1 end
      end
    end
    -- 状态行「照『对地』改过 2 个挂点」/「对地 · 预设」/「我的 1」/「自定义」；收起的方案行「方案 · 对地（已改 2）」
    local txt, col, short = "", C.MUTE, ""
    if st.mine then
      local v = setOf(st.mine)
      local modded = v and not (same(v.l, st.load) and math.abs(v.f - st.fuel) < 1e-6)
      txt, col = modded and T("ws.mineModded", st.mine) or T("ws.mineN", st.mine), modded and C.WARN or C.MUTE
      short = T("ws.mineN", st.mine) .. (modded and T("ws.modShort0") or "")
    elseif st.pk then
      local _, n = presetMod()
      local pn = T("preset." .. st.pk)
      if n > 0 then
        txt, col = T("ws.presetModded", pn, n), C.WARN
        short = T("ws.modShort", pn, n)
      else
        txt = T("ws.presetExact", pn)
        short = pn
      end
    else
      txt = T("ws.custom")
      short = T("ws.custom")
    end
    if ui.status then
      ui.status.Text = txt
      ui.status.TextColor3 = col
    end
    if ui.schemeRowT then ui.schemeRowT.Text = T("ws.schemeRow", short) end
  end

  ---------------------------------------------------------------- 右栏：当前挂载、性能对比、内油

  local function buildRight()
    local Rf = ws.right
    clear(Rf)
    ui.cmp = {}
    local w = LAY.RW - 24
    local y = compact and 8 or 10
    header(Rf, T("ws.thisSet"), y, w)
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
      ui.vMass = (not compact) and stat("mass", T("ws.mass")) or nil   -- 手机：右栏只有 300 高，起飞重量不写
      ui.vHeavy = nil
    else
      ui.vDrag, ui.vMass = nil, nil
      ui.vHeavy = stat("heavy", T("ws.heavy"))
    end
    y += compact and 6 or 10
    ui.perfHead = header(Rf, T("ws.perf"), y, w)
    y += compact and 20 or 22
    -- 列名（粗 12 淡）：平时「空挂 现在 差」，悬停时「现在 换上 差」
    ui.colA, ui.colB = nil, nil
    if not compact then
      ui.colA = K.text(Rf, T("ws.colBase"), S.tiny, "bold", C.FAINT, UD2(0, 50, 0, 14), UD2(0, 12 + w + K.CMP_COLS.base, 0, y), RIGHT, V2(1, 0))
      ui.colA.Name = "ColA"
      ui.colB = K.text(Rf, T("ws.colCur"), S.tiny, "bold", C.FAINT, UD2(0, 50, 0, 14), UD2(0, 12 + w + K.CMP_COLS.cur, 0, y), RIGHT, V2(1, 0))
      ui.colB.Name = "ColB"
      ui.colD = K.text(Rf, T("ws.colD"), S.tiny, "bold", C.FAINT, UD2(0, 40, 0, 14), UD2(0, 12 + w, 0, y), RIGHT, V2(1, 0))
      ui.colD.Name = "ColD"
      y += 16
    end
    local rows
    if st.jet then
      rows = { { "vAB", "ws.vAB" }, { "vMil", "ws.vMil" }, { "tw", "ws.tw" }, { "str", "ws.str" }, { "roc", "ws.roc" }, { "wl", "ws.wl" } }
      if st.D and not (st.D.Ta > st.D.Tm) then table.remove(rows, 2) end   -- 没有加力：只有一个极速
      if compact then rows = { rows[1], { "tw", "ws.tw" }, { "str", "ws.str" }, { "roc", "ws.roc" } } end
    else
      rows = { { "vh", "ws.vMax" }, { "min", "ws.endurRow" } }
    end
    local RH = compact and 24 or 26
    for _, r in ipairs(rows) do
      ui.cmp[r[1]] = K.compare(Rf, y, w, T(r[2]), nil, compact, RH)
      ui.cmp[r[1]].f.Name = "Cmp_" .. r[1]
      y += RH
    end
    if st.jet and not compact then   -- 手机放不下这一行说明
      local note = K.text(Rf, T("ws.perfNote"), S.tiny, "body", C.FAINT, UD2(0, w, 0, 16), UD2(0, 12, 0, y + 4))
      note.Name = "Note"
      y += 30
    else
      y += 8
    end
    header(Rf, T("ws.fuel"), y, w)
    y += compact and 20 or 22
    local opts = {}
    for _, f in ipairs(AD.FUEL_OPTS) do
      local pc = math.floor(f * 100 + 0.5)
      table.insert(opts, { key = f, text = pc .. "%", name = "Fuel" .. pc })
    end
    local segH = compact and 44 or 28
    ui.fuel = K.seg(Rf, opts, UD2(0, w, 0, segH), UD2(0, 12, 0, y), { name = "FuelSeg", onPick = function(f)
      closeMenu()
      commit(table.clone(st.load), st.pk, st.mine, f, "fuel")
    end })
    y += segH + 8
    ui.fuel1, ui.fuel2 = nil, nil
    if st.jet then   -- 直升机：续航、重量上面已经有了（不重复写）
      ui.fuel1 = K.text(Rf, "", S.small, "mono", C.TEXT, UD2(0, w, 0, 16), UD2(0, 12, 0, y))
      ui.fuel1.Name = "Endurance"
      y += 18
      if not compact then
        ui.fuel2 = K.text(Rf, "", S.tiny, "mono", C.MUTE, UD2(0, w, 0, 16), UD2(0, 12, 0, y))
        ui.fuel2.Name = "FuelWeight"
        y += 18
      end
    end
    ws.fitCol("right", y + 8, true)
  end

  -- roll：数字滚动（点了装上、改内油）；悬停预览时直接换
  updateRight = function(roll)
    if not st or not ui.vExt then return end
    local cur = perfOf(st.load, st.fuel)
    local empty = perfOf(st.empty, st.fuel)
    local pl = previewLoad()
    local pv = pl and perfOf(pl, st.fuel) or nil
    local function put(lab, key, v, fmt)
      if not lab or v == nil then return end
      if roll and not pv then K.roll(lab, key, st.shown[key], v, fmt) else
        K.stop(key)
        lab.Text = fmt(v)
      end
      st.shown[key] = v
      lab.TextColor3 = pv and C.WARN or C.TEXT
    end
    -- 当前挂载（悬停时是换上以后的，琥珀）
    local x = (pv or cur).Lo
    put(ui.vExt, "wsExt", x.ext, function(v) return K.int(v) .. " kg" end)
    put(ui.vDrag, "wsDrag", x.dCD0 or 0, function(v) return "+" .. string.format("%.4f", v) end)
    put(ui.vMass, "wsMass", x.m, function(v) return K.int(v) .. " kg" end)
    if ui.vHeavy then
      ui.vHeavy.Text = T("ws.heavyVal", K.signed(((pv or cur).heavy - 1) * 100))
      ui.vHeavy.TextColor3 = pv and C.WARN or C.TEXT
    end
    -- 性能：平时 空挂 → 现在（差灰）；悬停时 现在 → 换上（差红绿）
    setHeader(ui.perfHead, T(pv and "ws.perfPv" or "ws.perf"))
    if ui.colA then
      ui.colA.Text = T(pv and "ws.colCur" or "ws.colBase")
      ui.colB.Text = T(pv and "ws.colNew" or "ws.colCur")
    end
    if st.jet and cur.p and empty.p then
      local P0, P1, P2 = empty.p, cur.p, pv and pv.p
      local function row(key, get, fmt, dfmt, better, eps)
        local r = ui.cmp[key]
        if r then r:set(get(P0), get(P1), P2 and get(P2) or nil, { fmt = fmt, dfmt = dfmt, better = better, eps = eps, roll = roll }) end
      end
      local int = function(v) return K.int(v) end
      row("vAB", function(p) return p.vAB * 3.6 end, int, function(v) return K.signed(v) end, 1, 0.5)
      row("vMil", function(p) return p.vMil * 3.6 end, int, function(v) return K.signed(v) end, 1, 0.5)
      row("tw", function(p) return p.tw end, f2, function(v) return K.signed(v, 2) end, 1, 0.005)
      row("str", function(p) return p.str * 180 / math.pi end, f1, function(v) return K.signed(v, 1) end, 1, 0.05)
      row("roc", function(p) return p.roc end, int, function(v) return K.signed(v) end, 1, 0.5)
      row("wl", function(p) return p.wl end, int, function(v) return K.signed(v) end, -1, 0.5)
    elseif not st.jet then
      local vt = function(c) return (c.vh or 0) / AD.M * 3.6 end
      if ui.colA then   -- 直升机不挂副油箱时两行都没变（只写一个数）：列名不写
        local flat = not pv and math.abs(vt(empty) - vt(cur)) < 0.5 and math.abs(empty.min - cur.min) < 0.5
        for _, c in ipairs({ ui.colA, ui.colB, ui.colD }) do c.Visible = not flat end
      end
      if ui.cmp.vh then ui.cmp.vh:set(vt(empty), vt(cur), pv and vt(pv) or nil, { fmt = function(v) return K.int(v) end, dfmt = function(v) return K.signed(v) end,
        better = 1, eps = 0.5, roll = roll }) end
      if ui.cmp.min then ui.cmp.min:set(empty.min, cur.min, pv and pv.min or nil, { fmt = function(v) return T("ws.minutes", math.floor(v + 0.5)) end,
        dfmt = function(v) return K.signed(v) end, better = 1, eps = 0.5, roll = roll }) end
    end
    -- 内油
    if ui.fuel then ui.fuel.set(st.fuel) end
    local c = pv or cur
    if ui.fuel1 then
      ui.fuel1.Text = T("ws.endur", c.min) .. ((c.minX > 0) and ("  " .. T("ws.endurTank", c.minX)) or "")
      ui.fuel1.TextColor3 = pv and C.WARN or C.TEXT
    end
    if ui.fuel2 and st.D then
      local xf = c.Lo.xf or 0
      ui.fuel2.Text = T("ws.fuelKg", K.int(st.D.fi * st.fuel)) .. ((xf > 0.5) and T("ws.fuelKgX", K.int(xf)) or "")
    end
  end

  ---------------------------------------------------------------- 悬停资料卡（桌面：左栏右边，位置固定在武器列表上沿那一高）

  local function buildDetail()
    local D0 = ws.detail
    if ui.dView then ui.dView:clear() end
    clear(D0)
    ui.dView, ui.dRows = nil, nil
    if compact then return end
    local w = LAY.DW
    local pnl = K.panel(D0, UD2(0, w, 0, 250), UD2(0, 1, 0, 1), nil, 0.04)
    pnl.Name = "Card"
    ui.dName = K.text(pnl, "", S.body, "bold", C.TEXT, UD2(0, w - 24, 0, 20), UD2(0, 12, 0, 8))
    ui.dName.Name = "Name"
    ui.dSub = K.text(pnl, "", S.small, "cond", C.MUTE, UD2(0, w - 24, 0, 16), UD2(0, 12, 0, 28))
    ui.dSub.Name = "Sub"
    -- 这枚弹的 3D 模型（同挂在飞机上的那套零件）：后面一块横向柔光，弹在里面慢慢滚着转
    ui.dPlate = K.lightbox(pnl, UD2(0, w - 24, 0, 72), UD2(0, 12, 0, 48))
    ui.dView = K.wpnView(pnl, UD2(0, w - 24, 0, 72), UD2(0, 12, 0, 48), "WsWpnView")
    -- 四个关键数：名字 | 2 像素的条（同类之间比；有已装的那枚时画它的刻度）| 数 | 比已装的那枚（变好绿、变差红）
    ui.dRows = {}
    for k = 1, 4 do
      local y = 128 + (k - 1) * 20
      local nm = K.text(pnl, "", S.tiny, "cond", C.MUTE, UD2(0, 64, 0, 16), UD2(0, 12, 0, y))
      local tr = K.frame(pnl, UD2(0, 100, 0, 2), UD2(0, 80, 0, y + 7), C.LINE, 0.88)
      local bar = K.frame(tr, UD2(0, 0, 1, 0), nil, C.TEXT, 0.1)
      local tick = K.frame(tr, UD2(0, 1, 0, 7), UD2(0, 0, 0.5, 0), C.MUTE, 0, V2(0.5, 0.5))
      tick.Name = "Ref"
      local v = K.text(pnl, "", S.tiny, "mono", C.TEXT, UD2(0, 60, 0, 16), UD2(0, 244, 0, y), RIGHT, V2(1, 0))
      local dv = K.text(pnl, "", S.tiny, "mono", C.MUTE, UD2(0, 42, 0, 16), UD2(1, -12, 0, y), RIGHT, V2(1, 0))
      dv.Name = "Diff"
      ui.dRows[k] = { nm = nm, bar = bar, v = v, tr = tr, tick = tick, dv = dv }
    end
    K.frame(pnl, UD2(0, w - 24, 0, 1), UD2(0, 12, 0, 210), C.LINE, 0.9).Name = "Sep"
    ui.dVs = {}
    local cw = (w - 24) / 6
    for k = 1, 6 do
      local x = 12 + (k - 1) * cw
      local a = K.text(pnl, "", S.tiny, "cond", C.FAINT, UD2(0, cw, 0, 14), UD2(0, x, 0, 214), CENTER)
      local b = K.text(pnl, "", S.tiny, "mono", C.TEXT, UD2(0, cw, 0, 14), UD2(0, x, 0, 230), CENTER)
      ui.dVs[k] = { a = a, b = b }
    end
    ws.detailShow(false)
  end
  local VS_KEYS = { "inf", "light", "armor", "air", "ship", "fort" }
  -- 一枚弹的四个关键数：{ 名字键, 值, 写法, 差的写法, better（1 越大越好 / −1 越小越好）, nobar（不画条：锁定时间越长越差，条的方向会反）}
  local function rowsOf(x, s)
    local n = AD.count(s, x.id)
    local sgn0 = function(v) return K.signed(v) end
    if x.kind == "tank" then
      return { { "ws.d.fuel", x.fuel * n * 100, function(v) return "+" .. math.floor(v + 0.5) .. "%" end, sgn0, 1 },
        { "ws.d.drag", x.drag * n * 100, function(v) return "-" .. math.floor(v + 0.5) .. "%" end, sgn0, -1 },
        { "ws.d.extra", AD.fuelMin(st.d, x.fuel * n), function(v) return T("ws.minutes", math.floor(v + 0.5)) end, sgn0, 1 },
        { "ws.d.shell", (FM and FM.storeMass(x, AD.M) or 0) * n, function(v) return K.int(v) .. " kg" end, sgn0, -1 } }
    elseif x.kind == "bomb" then
      return { { "ws.d.dmg", x.dmg or 0, function(v) return K.int(v) end, sgn0, 1 },
        { "ws.d.radius", (x.splash or 0) / AD.M, function(v) return K.int(v) .. " m" end, sgn0, 1 },
        { "ws.d.mass", (FM and FM.storeMass(x, AD.M) or 0) * n, function(v) return K.int(v) .. " kg" end, sgn0, -1 },
        { "ws.d.count", n, function(v) return "×" .. math.floor(v) end, sgn0, 1 } }
    elseif x.kind == "rkt" then
      return { { "ws.d.tubes", x.tubes or 1, function(v) return tostring(math.floor(v)) end, sgn0, 1 },
        { "ws.d.range", x.range or 0, function(v) return km(v) .. " km" end, function(v) return K.signed(v / AD.M / 1000, 1) end, 1 },
        { "ws.d.dmg", x.dmg or 0, function(v) return K.int(v) end, sgn0, 1 },
        { "ws.d.speed", (x.speed or 0) / AD.M, function(v) return K.int(v) .. " m/s" end, sgn0, 1 } }
    end
    return { { "ws.d.range", x.range or 0, function(v) return km(v) .. " km" end, function(v) return K.signed(v / AD.M / 1000, 1) end, 1 },
      { "ws.d.speed", (x.speed or 0) / AD.M, function(v) return K.int(v) .. " m/s" end, sgn0, 1 },
      { "ws.d.dmg", x.dmg or 0, function(v) return K.int(v) end, sgn0, 1 },
      { "ws.d.lock", x.lockTime or 0, function(v) return (v > 0) and (f1(v) .. " s") or "-" end, function(v) return K.signed(v, 1) end, -1, true } }
  end
  local function showDetail(wid)
    if compact or not ui.dRows then return end
    local w = wid and AD.W[wid]
    if not (w and st.sel) then
      ws.detailShow(false)
      return
    end
    local g = st.cards[st.sel]
    local s = st.d.st[g.st[1]]
    local cur = cardWeapon(g)
    local Wc = cur and AD.W[cur]
    ui.dName.Text = T("aw." .. wid)
    ui.dSub.Text = subOf(w, false)
    if ui.dView and ui.dView:set(wid) then
      for _, c in ipairs(ui.dPlate:GetChildren()) do if c.Name == "Art" then c:Destroy() end end
    else   -- 视口拼不出来（模块没到）：退回剪影
      local W2 = LAY.DW - 24
      K.weaponArt(ui.dPlate, wid, W2, 72, { px = K.artScale(s.opts, W2, 72, 8), col = C.TEXT })
    end
    local mine = rowsOf(w, s)
    local ref = (Wc and Wc.kind == w.kind and cur ~= wid) and rowsOf(Wc, s) or nil
    local mx = { 0, 0, 0, 0 }
    for _, o in ipairs(s.opts) do
      local x = AD.W[o]
      if x and x.kind == w.kind then
        for k, r in ipairs(rowsOf(x, s)) do mx[k] = math.max(mx[k], r[2]) end
      end
    end
    for k, r in ipairs(ui.dRows) do
      local e = mine[k]
      r.nm.Text = e and T(e[1]) or ""
      r.v.Text = e and e[3](e[2]) or ""
      local bar = e ~= nil and not e[6]
      r.tr.Visible = bar
      local rv = ref and ref[k]
      if bar then
        r.bar.Size = UD2(math.clamp(e[2] / math.max(mx[k], 1e-6), 0, 1), 0, 1, 0)
        r.tick.Visible = rv ~= nil
        if rv then r.tick.Position = UD2(math.clamp(rv[2] / math.max(mx[k], 1e-6), 0, 1), 0, 0.5, 0) end
      end
      if rv and e and math.abs(e[2] - rv[2]) > 1e-6 then
        local dd = e[2] - rv[2]
        r.dv.Text = e[4](dd)
        r.dv.TextColor3 = ((dd * (e[5] or 1)) > 0) and C.GOOD or C.BAD
      else
        r.dv.Text = ""
      end
    end
    for k, c in ipairs(ui.dVs) do
      local key = VS_KEYS[k]
      local v = w.vs and w.vs[key]
      c.a.Text = T("ws.vs." .. key)
      c.b.Text = v and ("×" .. f1(v)) or "-"
      c.b.TextColor3 = (v and v >= 1) and C.TEXT or ((v and v < 0.5) and C.FAINT or C.MUTE)
      c.a.Visible, c.b.Visible = w.kind ~= "tank", w.kind ~= "tank"
    end
    ws.detailShow(true)
  end

  ---------------------------------------------------------------- 底部条：航炮 │ 挂点卡 │ 干扰弹；上面一行：名牌、左右对称

  local FIXW = compact and 88 or 112   -- 固定卡的宽
  local function artBox()   -- 卡里那块图：y 22～58（手机 20～44）
    return compact and 20 or 22, compact and 24 or 36
  end
  local function stationCard(parent, ci, g, x, cw, px)
    local h = LAY.BH
    local cd = K.card(parent, UD2(0, cw, 0, h), UD2(0, x, 0, 0), {
      name = "Station_" .. ci,
      onEnter = function() if st and setHov then setHov(ci) end end,
      onLeave = function() if st and st.hov == ci and setHov then setHov(nil) end end,
      onClick = function() if st and selectCard then selectCard((st.sel == ci) and nil or ci) end end })
    local f = cd.f
    -- 左上编号框（同弹药栏的键位框；一对就两个 [3][8]，间距 3）
    cd.keys = {}
    local kx = 10
    for k, nstr in ipairs(g.nums) do
      local kb, kw = K.keyBox(f, nstr, kx, 6, C.MUTE, (k == 1) and "Num" or ("Num" .. k))
      cd.keys[k] = { box = kb, st = g.st[k] }
      kx += kw + 3
    end
    -- 右上：这张卡一共几枚（等宽 15）
    cd.cnt = K.text(f, "", S.body, "mono", C.TEXT, UD2(0, 40, 0, 18), UD2(1, -10, 0, 4), RIGHT, V2(1, 0))
    cd.cnt.Name = "Count"
    local ay, ah = artBox()
    cd.lb = K.lightbox(f, UD2(1, -12, 0, ah), UD2(0, 6, 0, ay))
    cd.nm = K.text(f, "", compact and S.tiny or S.small, "bold", C.TEXT, UD2(1, -20, 0, 16), UD2(0, 10, 0, compact and 47 or 63))
    cd.nm.Name = "Name"
    cd.sub = K.text(f, "", S.tiny, "bold", C.MUTE, UD2(1, -20, 0, 14), UD2(0, 10, 0, compact and 64 or 82))
    cd.sub.Name = "Sub"
    cd.g, cd.pw, cd.ph, cd.px, cd.ci = g, cw - 12, ah, px, ci
    return cd
  end
  local function fillStationCard(cd)
    local g = cd.g
    local wid, mixed = cardWeapon(g)
    local s = st.d.st[g.st[1]]
    local on = st.sel == cd.ci
    local hot = on or st.hov == cd.ci
    if wid then
      local w = AD.W[wid]
      local n = AD.count(s, wid)
      -- 一架飞机一个比例尺（长的就是长），细长的导弹最多放大到 1.6 倍（不然一根头发丝）
      local px = math.min(cd.px * 1.6, K.artScale({ wid }, cd.pw, cd.ph, 3))
      local sig = wid .. (hot and "+" or "-")
      if cd.artSig ~= sig then
        cd.artSig = sig
        K.weaponArt(cd.lb, wid, cd.pw, cd.ph, { px = px, col = hot and C.TEXT or C.MUTE })
      end
      cd.nm.Text = wname(wid) .. (mixed and " *" or "")
      cd.nm.TextColor3 = C.TEXT
      local total = 0
      for _, i in ipairs(g.st) do if st.load[i] and AD.W[st.load[i]] then total += (AD.W[st.load[i]].kind == "rkt") and 1 or AD.count(st.d.st[i], st.load[i]) end end
      cd.cnt.Text = tostring(total)
      cd.sub.Text = (w.kind == "rkt") and T("ws.tubes", w.tubes or n) or ((w.kind == "tank") and T("wcs.tank") or T("gds." .. (w.guide or "none")))
      cd:setDim(false)
    else
      cd.artSig = nil
      for _, c in ipairs(cd.lb:GetChildren()) do if c.Name == "Art" then c:Destroy() end end
      cd.nm.Text = T("ws.empty")
      cd.nm.TextColor3 = C.FAINT
      cd.cnt.Text = ""
      cd.sub.Text = mixed and T("ws.mixed") or ""
      cd:setDim(true)
    end
    cd:setSel(on)
    -- 照预设改过的挂点：编号框琥珀（看得出是哪几个改了）
    local pl = st.pk and AD.presetLoad(st.d, st.pk) or nil
    for _, kk in ipairs(cd.keys) do
      local mod = pl ~= nil and (pl[kk.st] or false) ~= (st.load[kk.st] or false)
      kk.box.TextColor3 = mod and C.WARN or C.MUTE
      local s2 = kk.box:FindFirstChildOfClass("UIStroke")
      if s2 then s2.Color = mod and C.WARN or C.MUTE end
    end
  end
  -- 名牌（卡组上面）：鼠标挂着的、没有就选着的那个挂点——「挂点 3、8 · 霹雳-15」（窄体 15 白）+「· 空空导弹 · 主动雷达」（13 灰）
  updatePlate = function()
    if not ui.plate then return end
    local ci = st.hov or st.sel
    local g = ci and st.cards[ci]
    if not g then
      ui.plate.Text = ""
      return
    end
    local wid = cardWeapon(g)
    local w = wid and AD.W[wid]
    local head = T("ws.station", g.label) .. "  ·  " .. (w and wname(wid) or T("ws.noneSub"))
    local tail = w and ("  ·  " .. subOf(w, false)) or ""
    ui.plate.Text = K.rich({ { head }, { tail, C.MUTE, S.small } }, S.body)
  end
  -- 鼠标挂着哪一张挂点卡（卡片、机身上的编号都算）：3D 白色淡轮廓、卡片描边亮、名牌
  setHov = function(ci)
    if not st then return end
    local was = st.hov
    st.hov = ci
    for _, cd in ipairs(ui.scards or {}) do
      cd:setHover(cd.ci == ci)
      if cd.ci == was or cd.ci == ci then fillStationCard(cd) end
    end
    applyHL()
    updatePlate()
  end
  local function buildBottom()
    local B = ws.bottom
    clear(B)
    clear(ws.barHead)
    ui.scards = {}
    local d = st.d
    local h = LAY.BH
    local vw = ws.vw()
    local barW = vw - 2 * LAY.M
    local ay, ah = artBox()
    local xL, xR = 0, barW
    -- 航炮（固定卡，不能点：悬停不变亮）
    if d.gun then
      local gc = K.card(B, UD2(0, FIXW, 0, h), UD2(0, 0, 0, 0), { name = "GunCard", still = true })
      K.text(gc.f, T("ws.gun"), S.tiny, "bold", C.MUTE, UD2(1, -20, 0, 14), UD2(0, 10, 0, 6)).Name = "Head"
      K.text(gc.f, tostring(d.gunAmmo or 0), S.body, "mono", C.TEXT, UD2(0, 50, 0, 18), UD2(1, -10, 0, 4), RIGHT, V2(1, 0)).Name = "Count"
      local lb = K.lightbox(gc.f, UD2(1, -12, 0, ah), UD2(0, 6, 0, ay))
      K.gunArt(lb, d.gun, FIXW - 12, ah, { col = C.MUTE })
      K.text(gc.f, wname(d.gun), compact and S.tiny or S.small, "bold", C.TEXT, UD2(1, -20, 0, 16), UD2(0, 10, 0, compact and 47 or 63)).Name = "Name"
      K.text(gc.f, T("ws.gunFixed"), S.tiny, "bold", C.FAINT, UD2(1, -20, 0, 14), UD2(0, 10, 0, compact and 64 or 82)).Name = "Sub"
      xL = FIXW + 13
      K.frame(B, UD2(0, 1, 0, h - 24), UD2(0, FIXW + 6, 0, 12), C.LINE, A.line).Name = "Div"
    end
    -- 干扰弹（固定卡；没研究：锁住、点了去改装页；研究了不能点）
    do
      local it = st.it
      local t = G.treeState and G.treeState()
      local md = t and t.mods and t.mods[st.key]
      local fx = WMd.fx(it, md and md.done)
      local locked = not fx.flares
      local fc = K.card(B, UD2(0, FIXW, 0, h), UD2(0, barW - FIXW, 0, 0), { name = "FlareCard", still = not locked, onClick = function()
        if locked and ws.openTab then ws.openTab("mods") end
      end })
      K.text(fc.f, T("ws.flares"), S.tiny, "bold", C.MUTE, UD2(1, -20, 0, 14), UD2(0, 10, 0, 6)).Name = "Head"
      if not locked then
        K.text(fc.f, tostring(d.flares or 0), S.body, "mono", C.TEXT, UD2(0, 50, 0, 18), UD2(1, -10, 0, 4), RIGHT, V2(1, 0)).Name = "Count"
      end
      local lb = K.lightbox(fc.f, UD2(1, -12, 0, ah), UD2(0, 6, 0, ay))
      K.flareArt(lb, FIXW - 12, ah, { col = locked and C.MUTE or C.MUTE, tr = locked and 0.65 or 0.1 })
      local nm = K.text(fc.f, locked and T("ws.flaresLocked") or T("ws.flaresOn"), compact and S.tiny or S.small, "bold",
        locked and C.FAINT or C.TEXT, UD2(1, -20, 0, 16), UD2(0, 10, 0, compact and 47 or 63))
      nm.Name = "Name"
      K.text(fc.f, locked and T("ws.flaresHow") or T("ws.flaresAuto"), S.tiny, "bold", locked and C.FAINT or C.MUTE, UD2(1, -20, 0, 14),
        UD2(0, 10, 0, compact and 64 or 82)).Name = "Sub"
      ui.flareLocked = locked
      xR = barW - FIXW - 13
      K.frame(B, UD2(0, 1, 0, h - 24), UD2(0, barW - FIXW - 7, 0, 12), C.LINE, A.line).Name = "Div"
    end
    -- 挂点卡：卡组的中点对准 3D 区的中点（就在飞机和编号行底下），夹在两张固定卡中间；放不下才铺满、横着卷（最后一张露出四成：看得出还能卷）
    local n = #st.cards
    local avail = xR - xL
    local GAPC = 4
    local lo, hi = compact and 80 or 88, compact and 100 or 120
    local x0f, x1f = free3d()
    local fitFree = math.floor(((x1f - x0f) - (n - 1) * GAPC) / math.max(n, 1))   -- 先试整组放在两栏中间（正好在飞机底下）
    local cw = (fitFree >= lo) and math.min(hi, fitFree) or math.clamp(math.floor((avail - (n - 1) * GAPC) / math.max(n, 1)), lo, hi)
    local need = n * cw + (n - 1) * GAPC
    local scroll = need > avail + 0.5
    if scroll then
      for k = n - 1, 1, -1 do
        cw = math.floor((avail - k * GAPC) / (k + 0.4))
        if cw >= lo then break end
      end
      cw = math.max(lo, cw)
      need = n * cw + (n - 1) * GAPC
    end
    local mid = (x0f + x1f) / 2 - LAY.M   -- 3D 区的中点（条的坐标）
    local gx = scroll and xL or math.clamp(math.floor(mid - need / 2 + 0.5), xL, math.max(xL, xR - need))
    local area = Instance.new("ScrollingFrame")
    area.Name = "Stations"
    area.BackgroundTransparency = 1
    area.BorderSizePixel = 0
    area.ScrollBarThickness = 0
    area.ScrollingDirection = Enum.ScrollingDirection.X
    area.ClipsDescendants = true
    area.Size = UD2(0, math.max(10, avail), 0, h + 4)
    area.Position = UD2(0, xL, 0, -2)
    area.CanvasSize = UD2(0, math.max(avail, (gx - xL) + need), 1, 0)
    area.Parent = B
    ui.area, ui.cardW = area, cw
    -- 一架飞机的挂点卡一个比例尺（长的弹就是长）
    local all = {}
    for _, s in ipairs(st.d.st or {}) do for _, w in ipairs(s.opts) do all[#all + 1] = w end end
    local px = K.artScale(all, cw - 12, ah, 3)
    for ci, g in ipairs(st.cards) do
      local x = (gx - xL) + (ci - 1) * (cw + GAPC)
      local cd = stationCard(area, ci, g, x, cw, px)
      cd.f.Position = UD2(0, x, 0, 2)
      cd.pos = cd.f.Position
      ui.scards[ci] = cd
      fillStationCard(cd)
    end
    if n == 0 then
      K.text(area, T("ws.noStations"), S.small, "body", C.FAINT, UD2(1, 0, 1, 0), nil, CENTER)
    end
    -- 卡组上面一行：左边名牌、右边左右对称——只在两栏中间那一段（这一行和两栏的底边一样高，伸出去就压在面板上）
    local gl = math.max(gx, x0f - LAY.M)
    local gr = math.min(scroll and xR or (gx + need), x1f - LAY.M)
    ui.plate = K.text(ws.barHead, "", S.body, "cond", C.TEXT, UD2(0, math.max(40, gr - gl - 96), 1, 0), UD2(0, gl, 0, 0))
    ui.plate.Name = "Plate"
    ui.plate.RichText = true
    ui.sym = K.check(ws.barHead, T("ws.sym"), UD2(0, gr, 0.5, 0), { name = "SymToggle", value = st.sym, h = LAY.HIT, anchor = V2(1, 0.5),
      onToggle = function(on)
        if on == st.sym then return end
        local keep = st.sel and st.cards[st.sel] and st.cards[st.sel].st[1]
        st.sym = on
        makeGroups()
        st.sel = keep and cardOfStation(keep) or nil
        st.hov = nil
        buildBottom()
        layoutLeft()
        applyHL()
      end })
    updatePlate()
  end

  ---------------------------------------------------------------- 3D 标签（每帧）

  local function buildTags()
    local layer = ws.labels
    clear(layer)
    st.tags = {}
    for i in ipairs(st.d.st or {}) do
      local tg = K.tag(layer, "Tag_" .. i, not compact)
      if not compact then
        tg.b.MouseEnter:Connect(function() if st and setHov then setHov(cardOfStation(i)) end end)
        tg.b.MouseLeave:Connect(function() if st and st.hov == cardOfStation(i) and setHov then setHov(nil) end end)
        tg.b.Activated:Connect(function()
          if not st then return end
          local ci = cardOfStation(i)
          if ci and selectCard then selectCard((st.sel == ci) and nil or ci) end
        end)
      end
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
  local function wrapPi(a) return (a + math.pi) % (2 * math.pi) - math.pi end
  local function placeTags(dt)
    local A0 = G.hangarAir and G.hangarAir()
    if not (A0 and A0.key == st.key and Stage and st.anchor) then
      for _, tg in pairs(st.tags or {}) do tg:show(false) end
      return
    end
    -- 镜头动着（飞向挂点、拖着转、缩放）：0.12 秒淡掉，停稳了淡回来——一排编号不在眼前换位置
    local vs = Stage.viewState()
    local moving = vs.flying or math.abs(wrapPi(vs.yaw - vs.sy)) > 0.004 or math.abs(vs.pitch - vs.sp) > 0.004 or math.abs(vs.dist - vs.sd) > 0.08
    local want = moving and 0 or 1
    local stp = (dt or 0.016) / TH.T.hover
    st.tagAlpha = math.clamp(st.tagAlpha + math.clamp(want - st.tagAlpha, -stp, stp), 0, 1)
    local alpha = st.tagAlpha
    if alpha <= 0.01 then
      for _, tg in pairs(st.tags) do tg:show(false) end
      return
    end
    local sc = ws.scale()
    local cam = workspace.CurrentCamera
    local camX = cam and A0.cf:PointToObjectSpace(cam.CFrame.Position).X or 0
    local camSide = (camX >= 0) and 1 or -1
    local cur = previewLoad() or st.load   -- 悬停预览时，选中那一对写预览的那枚（3D 里换上的就是它）
    local gh = st.d.gearH or 6
    local x0, x1 = free3d()
    if ws.detail and ws.detail.Visible then x0 = x0 + LAY.DW + LAY.GAP end   -- 资料卡开着：它盖着的那一段也不画
    local barY = ws.barTop() - LAY.PLATE - 4
    local floorY = 0
    local pts, dots = {}, {}
    for i, tg in pairs(st.tags) do
      local a = st.anchor[i]
      local sp, z, on = Stage.toScreen(A0.cf * a)
      local used = false
      if sp and on and z > 0 then
        local x, y = sp.X / sc, sp.Y / sc
        if x >= x0 + 4 and x <= x1 - 4 and y < barY - 30 and y > LAY.TOP then
          local s = st.d.st[i]
          local ci = cardOfStation(i)
          local sel, hov = ci ~= nil and ci == st.sel, ci ~= nil and ci == st.hov
          local near = math.abs(s.pos.X) <= 1.5 or ((s.pos.X >= 0) and 1 or -1) == camSide
          if near or sel or hov then
            local fsp = Stage.toScreen(A0.cf * V3(a.X, -gh, a.Z))   -- 挂点正下方的地面：标签排在机轮着地的那条线下面，不压在起落架上
            if fsp then floorY = math.max(floorY, fsp.Y / sc) end
            local wid = cur[i]
            local nm = (sel and near) and (wid and wname(wid) or T("ws.empty")) or nil
            local num = tostring(st.num[i])
            table.insert(pts, { i = i, x = x, y = y, num = num, name = nm, w = K.tagW(num, nm), sel = sel, hov = hov, far = not near, empty = not wid })
            used = true
          elseif not st.sel then   -- 另一边：只在全景时画个淡点（选了挂点镜头凑近一边时，另一边的点挤在机身上，不画）
            table.insert(dots, { i = i, x = x, y = y })
            used = true
          end
        end
      end
      if not used then tg:show(false) end
    end
    if #pts > 0 then
      table.sort(pts, function(a, b) return a.x < b.x end)
      local maxY = 0
      for _, p in ipairs(pts) do maxY = math.max(maxY, p.y) end
      local railY = math.clamp(math.max(maxY + 30, floorY + 12), LAY.TOP + 20, barY - 16)
      for _, p in ipairs(pts) do p.want = p.x end
      local pos = spread(pts, x0, x1, 4)
      for k, p in ipairs(pts) do
        p.lx = pos[k]
        p.lvl = 0
      end
      -- 引线横着走的那一层：同一方向偏开、横段重叠的错开 4 像素（往右偏的左边那个低、往左偏的右边那个低：竖线不穿过别人的横段）
      for k = 2, #pts do
        local p, q = pts[k], pts[k - 1]
        if p.lx > p.x + 1 and q.lx > q.x + 1 and p.x < q.lx then p.lvl = q.lvl + 1 end
      end
      for k = #pts - 1, 1, -1 do
        local p, q = pts[k], pts[k + 1]
        if p.lx < p.x - 1 and q.lx < q.x - 1 and q.lx < p.x then p.lvl = q.lvl + 1 end
      end
      for _, p in ipairs(pts) do
        local tg = st.tags[p.i]
        tg:show(true)
        tg:place({ dx = p.x, dy = p.y, lx = p.lx, ly = railY, jy = railY - 8 - 4 * math.min(p.lvl, 4), num = p.num, name = p.name,
          sel = p.sel, hov = p.hov, empty = p.empty, far = p.far, alpha = alpha })
      end
    end
    for _, dd in ipairs(dots) do st.tags[dd.i]:dotOnly(dd.x, dd.y, alpha * 0.85) end
  end

  ---------------------------------------------------------------- 选挂点、悬停、装上

  selectCard = function(ci)
    if not st then return end
    closeMenu()
    st.sel = ci
    st.hoverOpt = nil
    ws.detailShow(false)
    for _, cd in ipairs(ui.scards or {}) do fillStationCard(cd) end
    layoutLeft()
    applyHL()
    updatePlate()
    if ci then stationView(ci, TH.T.cam) else overview(TH.T.cam) end
    -- 卷到选中的那张（手机上挂点卡横着卷）
    if ci and ui.area and ui.scards[ci] then
      pcall(function()
        local x = ui.scards[ci].pos.X.Offset
        local wv = ui.area.Size.X.Offset
        local cx = math.clamp(x - wv / 2 + (ui.cardW or 100) / 2, 0, math.max(0, ui.area.CanvasSize.X.Offset - wv))
        ui.area.CanvasPosition = V2(cx, 0)
      end)
    end
    show3d(st.load)
    updateRight(false)
  end
  -- 鼠标挂在一张武器卡上（on）/ 离开：右栏马上显示变化（直接换、不滚），3D 停 0.12 秒再换（扫过一列卡时不来回重搭）
  setHover = function(wid, on)
    if not st or not st.sel then return end
    st.hoverVer = (st.hoverVer or 0) + 1
    local ver = st.hoverVer
    if on then
      st.hoverOpt = wid
      updateRight(false)
      refreshListLook()
      showDetail(wid)
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
          ws.detailShow(false)
          updateRight(false)
          refreshListLook()
          show3d(st.load)
        end
      end)
    end
  end
  -- 点一张武器卡：装上（左右对称时一对一起换）。手机：第一次点是预览（3D 换上、右栏琥珀的变化、卡上「再点一下装上」），再点一下才装上
  pickWeapon = function(wid)
    if not st or not st.sel then return end
    if compact and (st.hoverOpt == nil or (st.hoverOpt or false) ~= (wid or false)) then
      st.hoverVer = (st.hoverVer or 0) + 1
      st.hoverOpt = wid
      updateRight(false)
      refreshListLook()
      local pl = previewLoad()
      if pl then show3d(pl) end
      return
    end
    local g = st.cards[st.sel]
    local l = table.clone(st.load)
    for _, j in ipairs(g.st) do l[j] = (wid and table.find(st.d.st[j].opts, wid)) and wid or false end
    st.hoverOpt = nil
    st.hoverVer = (st.hoverVer or 0) + 1
    ws.detailShow(false)
    if not commit(l, st.pk, st.mine, st.fuel, "pair") then
      refreshListLook()
      updateRight(false)
    end
  end

  refreshAll = function(roll)
    if not st then return end
    for _, cd in ipairs(ui.scards or {}) do fillStationCard(cd) end
    if st.sel then
      refreshListLook()
      local g = st.cards[st.sel]
      local cur = g and cardWeapon(g)
      local s = g and st.d.st[g.st[1]]
      if s then
        local Wc = cur and AD.W[cur]
        local now = Wc and (wname(cur) .. ((AD.count(s, cur) > 1 and Wc.kind ~= "rkt") and (" ×" .. AD.count(s, cur)) or "")) or T("ws.emptyNow")
        ui.stPos.Text = posName(s) .. " · " .. T("ws.now", now)
      end
    else
      layoutLeft()
    end
    refreshChips()
    updateRight(roll)
    applyHL()
    updatePlate()
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
    if type(v) == "table" and type(v.l) == "table" and not savedP then pk = nil end   -- 存过、没记预设：自定义（或我的方案）
    local D = nil
    if FM and d.kind == "jet" then D = FM.get(d.id, it.key) or (d.like and FM.get(d.like)) or nil end
    local empty = {}
    for i = 1, #(d.st or {}) do empty[i] = false end
    st = { it = it, key = it.key, d = d, D = D, jet = D ~= nil, load = load, pk = pk, fuel = AD.cleanFuel(fuel or 1), sym = true,
      sel = nil, hov = nil, hoverOpt = nil, perf = {}, shown = {}, empty = empty, tagAlpha = 0, undo = {} }
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
    layoutLeft(true)
    refreshChips()
    showUndo(false)
    show3d(st.load)
    local A0 = G.hangarAir and G.hangarAir()
    if A0 and A0.key == st.key then onAir(A0) end
    -- 弹舱打开（0.6 秒）、镜头飞到全景；标签等镜头停稳了自己淡出来
    K.anim("wsBay", 0.6, "out", function(e) poseBay(e) end)
    overview(TH.T.cam)
    updateRight(false)
    return true
  end
  function P.close(instant)
    if not st then return end
    st = nil
    closeMenu()
    K.stop("wsMount")
    K.stop("wsFlash")
    if G.onHangarAir == onAir then G.onHangarAir = nil end
    if Stage then Stage.unhighlight() end
    clear(ws.labels)
    ws.detailShow(false)
    if ui.dView then ui.dView:clear() end
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
  end
  -- 退一层（Esc / 右键 / Backspace / 3D 空白处点一下）：先关小菜单 → 手机上的预览 → 选着的挂点退回全景；都没有返回 false（外壳再退出整备）
  function P.esc()
    if not st then return false end
    if ui.menu then
      closeMenu()
      return true
    end
    if compact and st.hoverOpt ~= nil then
      st.hoverOpt = nil
      st.hoverVer = (st.hoverVer or 0) + 1
      refreshListLook()
      updateRight(false)
      show3d(st.load)
      return true
    end
    if st.sel then
      selectCard(nil)
      return true
    end
    return false
  end
  function P.step(dt)
    if not st then return end
    placeTags(dt)
    if ui.dView and ws.detail and ws.detail.Visible then ui.dView:spin(dt) end
  end
  function P.refresh()   -- 存档变了（服务器推了新的 Tree：我的方案、改装研究完了）
    if not st then return end
    refreshChips()
    local t = G.treeState and G.treeState()
    local md = t and t.mods and t.mods[st.key]
    local fx = WMd.fx(st.it, md and md.done)
    if (not fx.flares) ~= ui.flareLocked then buildBottom() end
  end
  function P.relayout()
    if not st then return end
    buildBottom()
    layoutLeft(true)
  end
  -- 测试、截图用：现在的状态、点某张挂点卡 / 武器卡
  function P.state() return st end
  function P.select(ci) selectCard(ci) end
  function P.ui() return ui end
  return P
end

return WsArms
