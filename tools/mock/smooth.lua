-- M3 丝滑第二轮（审查 wip/perf 挑出来的问题改完以后）：python3 tools/mock/run.py tools/mock/smooth.lua
--   不出生：开服、进一个人，直接调客户端的函数 / 发客户端消息看（几分钟）——
--   ① G.velTrack（锁定圈、提前量的目标速度）：15 Hz 正常飞 220 格/秒估得准；停了 5 秒一下挪 300 格不算速度；行进中一拍挪 80 格这一拍不算；
--      真换了速度（100 → 400）连着两拍就认
--   ② 命中提示（WtHud）：机炮一秒 10 条命中只在第一条、升级（击穿 → 击毁）、离上次弹超过 0.4 秒时弹；到点 0.18 秒淡掉再藏；淡到一半又来一条：接着显示、重新弹
--   ③ 命中回放的影子（WtHud）：履带板（TrackLink）不要，按最长边挑——细长的天线、机枪管留着
--   ④ 舰艇罗盘（VehHud）：罗盘宽度变了、航向没变，刻度和 ▲ 也按新宽度摆
--   ⑤ 球拼的积云（Warfx）：重摆当场按现在的钟点上色、分帧上色那一轮作废；体积云晚到时 1 秒淡掉再删，刚摆的直接删
--   ⑥ 公用缓动（UI）：关到一半又打开回到 1；别人有 UIScale 时 uiPop 返回 false、不叠第二个；
--      sceneFade：半黑起淡、hold 以后等两帧顺、ready 不成立最多等 0.8 秒、第二次接着（不一下子变亮）
--   ⑦ 击杀栏（WtBattle）：上一条没滑完又来一条，各行从「原来那一行现在在哪」接着滑（不往回跳）
--   ⑧ B 大地图（WtMap）：左栏、地图的锚点在中间（UIScale 从中心长开），左上角位置不变
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3 = T.R, T.V3
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
local me = T.join("P1", 8721, true)
R.run(1)
local C = T.C
local function find(name)
  for _, d in ipairs(me.PlayerGui:GetDescendants()) do if d.Name == name then return d end end
end

print("① 目标速度（G.velTrack，服务器 15 Hz、客户端 60 帧）")
do
  -- 按帧喂：pos(t) 是服务器那一拍的位置（一秒 15 拍），返回每帧估出来的速度（只看 X）
  local function run(rec, t0, t1, pos, maxV)
    local out = {}
    local f = math.floor(t0 * 60 + 0.5)
    while f / 60 <= t1 + 1e-9 do
      local t = f / 60
      local tick = math.floor(t * 15 + 1e-6) / 15
      local v = C.velTrack(rec, pos(tick), t, maxV)
      out[#out + 1] = { t = t, v = v }
      f = f + 1
    end
    return out
  end
  local function at(out, t)
    local best = out[1]
    for _, o in ipairs(out) do if math.abs(o.t - t) < math.abs(best.t - t) then best = o end end
    return best.v
  end
  -- 正常飞：220 格 / 秒
  local rec = {}
  local o1 = run(rec, 0, 2, function(t) return V3(220 * t, 900, 0) end, 1500)
  local v2 = at(o1, 2)
  check(math.abs(v2.X - 220) < 15 and math.abs(v2.Y) < 1, string.format("正常飞 220 格/秒：估出来 %.1f", v2.X))
  -- 停了 5 秒，一下挪 300 格（传送 / 刚出视野回来）：不算速度
  rec = {}
  run(rec, 0, 5, function() return V3(0, 0, 0) end, 1500)
  local o2 = run(rec, 5 + 1 / 60, 5.5, function(t) return (t >= 5.05) and V3(300, 0, 0) or V3(0, 0, 0) end, 1500)
  local worst = 0
  for _, o in ipairs(o2) do worst = math.max(worst, o.v.Magnitude) end
  check(worst < 1, string.format("停 5 秒后一下挪 300 格：速度一直是 0（最大 %.1f；原来估成 60、0.6 秒才归零）", worst))
  -- 行进中一拍多挪 80 格（服务器纠正位置）：这一拍不算，接着估 220
  rec = {}
  local jumpAt = 1.0
  local function posJ(t) return V3(220 * t + ((t >= jumpAt - 1e-6) and 80 or 0), 900, 0) end
  local o3 = run(rec, 0, 2, posJ, 1500)
  local peak = 0
  for _, o in ipairs(o3) do if o.t >= jumpAt and o.t < jumpAt + 0.4 then peak = math.max(peak, o.v.X) end end
  local v3e = at(o3, 2)
  check(peak < 300 and math.abs(v3e.X - 220) < 15, string.format("行进中一拍多挪 80 格：那一下最多 %.0f（原来跳到 430）、后来 %.1f", peak, v3e.X))
  -- 真换了速度（100 → 400，连着好几拍都是 400）：连着两拍以后认新的
  rec = {}
  local function posS(t) return V3((t < 1) and 100 * t or (100 + 400 * (t - 1)), 900, 0) end
  local o4 = run(rec, 0, 1.6, posS, 1500)
  local v4 = at(o4, 1.4)
  check(math.abs(v4.X - 400) < 40, string.format("100 → 400 格/秒：0.4 秒后估 %.0f", v4.X))
  -- 比 maxV 还快的一拍照旧不算
  rec = {}
  run(rec, 0, 1, function(t) return V3(220 * t, 0, 0) end, 1500)
  local o5 = run(rec, 1 + 1 / 60, 1.2, function(t) return V3(220 * t + ((t >= 1.1) and 5000 or 0), 0, 0) end, 1500)
  local pk5 = 0
  for _, o in ipairs(o5) do pk5 = math.max(pk5, o.v.Magnitude) end
  check(pk5 < 300, string.format("一拍挪 5000 格（比 maxV 快）：不算（最大 %.0f）", pk5))
end

print("② 命中提示：连射不一直闪、到点淡掉")
local hitBox = find("WtHitText")
local hitTop = hitBox and hitBox:FindFirstChild("Result")
check(hitBox ~= nil and hitTop ~= nil, "命中提示框在")
if hitBox and hitTop then
  local pops = 0
  local orig = C.uiPop
  C.uiPop = function(o, ...)
    if o == hitBox then pops = pops + 1 end
    return orig(o, ...)
  end
  -- 发一条命中（服务器 → 客户端的消息下一帧才到：跑一帧）
  local function hit(r, kill)
    G.R.Drive:FireClient(me, { op = "wtHit", id = 0, veh = "t90m", r = r, kill = kill or false, parts = {}, pen = 300, arm = 80, dist = 900 })
    R.run(1 / 60, 1 / 60)
  end
  for i = 1, 10 do   -- 机炮：一秒 10 条
    hit("pen")
    R.run(0.1 - 1 / 60, 1 / 60)
  end
  check(pops >= 1 and pops <= 3, string.format("一秒 10 条击穿：只弹了 %d 下（第一条、过 0.4 秒；原来 10 下）", pops))
  local p0 = pops
  hit("pen", true)   -- 升级：击毁
  check(pops == p0 + 1, "结果升级（击穿 → 击毁）：马上弹一下")
  R.run(0.05)
  hit("pen")
  check(pops == p0 + 1, "降回击穿（0.05 秒后）：只换字、不弹")
  -- 到点：0.18 秒淡掉再藏（击穿 2.6 秒）
  R.run(2.6 + 0.09, 1 / 60)
  local midTr = hitTop.TextTransparency
  check(hitBox.Visible and midTr > 0.15 and midTr < 0.85, string.format("到点先淡（淡到一半：字透明 %.2f，框还在）", midTr))
  -- 淡到一半又来一条：接着显示、重新弹
  local p1 = pops
  hit("ric")
  check(hitBox.Visible and hitTop.TextTransparency == 0 and pops == p1 + 1, "淡到一半又来一条：字马上回来、重新弹一下")
  R.run(1.6 + 2.6 + 0.3)
  check(not hitBox.Visible, "淡完了就藏起来")
  C.uiPop = orig
end

print("③ 命中回放的影子挑哪几块")
do
  local pick = C.wtGhostParts
  check(pick ~= nil, "有挑影子的函数")
  if pick then
    local m
    R.as("client", function()
      m = R.Instance.new("Model")
      local function part(name, x, y, z)
        local p = R.Instance.new("Part")
        p.Name = name
        p.Size = V3(x, y, z)
        p.Parent = m
        return p
      end
      part("Hull", 10, 3, 20)
      part("Turret", 6, 2, 6)
      part("Gun", 0.5, 0.5, 8)
      part("Antenna", 0.1, 7, 0.1)
      part("MG", 0.2, 0.2, 3)
      for _ = 1, 150 do part("Bolt", 1, 1, 1) end
      for _ = 1, 90 do part("TrackLink", 1.6, 0.4, 1.4) end
    end)
    local got = pick(m)
    local has, links = {}, 0
    for _, p in ipairs(got) do
      has[p.Name] = true
      if p.Name == "TrackLink" then links = links + 1 end
    end
    check(#got == 120 and links == 0, string.format("最多 120 块、履带板一块都不要（%d 块，履带板 %d）", #got, links))
    check(has.Hull and has.Turret and has.Gun and has.Antenna and has.MG, "车体、炮塔、炮管、细长的天线和机枪管都留着（按最长边挑；按体积挑天线、机枪管会被挤掉）")
  end
end

print("④ 舰艇罗盘：宽度变了也重摆")
do
  local vc = C.vehCompass
  check(vc ~= nil and vc.setCW ~= nil, "罗盘的测试口在")
  if vc and vc.setCW then
    local function tickAt(st, h, ang)   -- 第几格是 ang 度：它的 x
      local first = math.floor((h - st.cw / 2 / st.px) / 5) * 5
      local i = (ang - first) / 5 + 1
      local tk = st.ticks[i]
      return tk and tk.t.Position.X.Offset
    end
    R.as("client", function()
      vc.setCW(166)
      vc.group.Visible = true
      vc.step(90, 100)
    end)
    local s1 = vc.state()
    local x1 = tickAt(s1, 90, 90)
    R.as("client", function()
      vc.setCW(261)   -- 窗口 1280 → 1470（layoutPanels 跟着改的宽度）
      vc.group.Visible = true
      vc.step(90, 100)   -- 航向、标记都没变
    end)
    local s2 = vc.state()
    local x2 = tickAt(s2, 90, 90)
    check(x1 == 166 / 2 and x2 == 261 / 2, string.format("090 那格在罗盘正中：宽 166 时 %s、宽 261 时 %s（原来航向没变就还按旧宽度摆）", tostring(x1), tostring(x2)))
    check(math.abs(s2.mark - (261 / 2 + 10 * s2.px)) < 0.01, string.format("▲（标记航向 100°）跟着新宽度：%.1f", s2.mark))
  end
end

print("⑤ 球拼的积云：重摆就上色、体积云晚到淡掉")
do
  local banks = C.cloudBanks
  check(banks ~= nil and #banks:GetChildren() > 100, "沙海上有球拼的积云（" .. tostring(banks and #banks:GetChildren()) .. " 块）")
  if banks then
    -- 正午：先拨到夜里让它上一轮夜里的色，再拨回正午、逮住分帧上色的那几帧，当场重摆
    R.workspace:SetAttribute("DayFix", 2.3)
    R.run(2.5)
    R.workspace:SetAttribute("DayFix", 12.5)
    local busy = T.runUntil(function() return C.cloudTintBusy and C.cloudTintBusy() end, 4, 1 / 60)
    check(busy, "钟点变了：开始分帧上色")
    R.as("client", function() C.cloudBanksRefresh() end)
    local dark = 0
    for _, p in ipairs(banks:GetChildren()) do if p.Color.R < 0.6 then dark = dark + 1 end end
    check(not C.cloudTintBusy() and dark == 0, string.format("重摆当场按正午上色、那一轮分帧上色作废（还是夜里颜色的 %d 块）", dark))
    -- 刚摆的（2 秒内）遇到体积云：直接删
    R.as("client", function() C.snowCloudsOn = true C.cloudBanksRefresh() end)
    check(#banks:GetChildren() == 0 and not C.cloudBanksFading(), "刚摆的球遇到体积云：直接删")
    R.as("client", function() C.snowCloudsOn = false C.cloudBanksRefresh() end)
    R.run(2.3)
    local n0 = #banks:GetChildren()
    local tr0 = 0
    for _, p in ipairs(banks:GetChildren()) do tr0 = tr0 + p.Transparency end
    R.as("client", function() C.snowCloudsOn = true C.cloudBanksRefresh() end)   -- 摆了 2 秒以上才来的体积云（clouds.glb 晚到）
    check(C.cloudBanksFading() and #banks:GetChildren() == n0, "摆了一会儿的球：先不删，开始淡")
    R.run(0.5)
    local tr1 = 0
    for _, p in ipairs(banks:GetChildren()) do tr1 = tr1 + p.Transparency end
    check(#banks:GetChildren() == n0 and tr1 > tr0 + n0 * 0.08, string.format("半秒：还在、更透明了（平均透明度 %.2f → %.2f）", tr0 / math.max(1, n0), tr1 / math.max(1, n0)))
    R.run(0.7)
    check(#banks:GetChildren() == 0 and not C.cloudBanksFading(), "1 秒多：淡完删掉")
    R.as("client", function() C.snowCloudsOn = false C.cloudBanksRefresh() end)
    check(#banks:GetChildren() == n0, "体积云关了：球又摆回来")
    R.workspace:SetAttribute("DayFix", nil)
  end
end

print("⑥ 公用缓动、黑场")
do
  local gui
  R.as("client", function()
    gui = R.Instance.new("ScreenGui")
    gui.Name = "SmoothTest"
    gui.Parent = me.PlayerGui
  end)
  local f, g, h
  R.as("client", function()
    f = R.Instance.new("Frame") f.Parent = gui f.Visible = false
    g = R.Instance.new("Frame") g.Parent = gui
    local own = R.Instance.new("UIScale") own.Parent = g
    h = R.Instance.new("Frame") h.Parent = gui
  end)
  local function scales(o) local n = 0 for _, c in ipairs(o:GetChildren()) do if c.ClassName == "UIScale" then n = n + 1 end end return n end
  R.as("client", function() C.uiShow(f, true) end)
  R.run(0.3)
  R.as("client", function() C.uiShow(f, false, { out = true }) end)   -- 关：缩到 0.97 再藏
  R.as("client", function() C.uiShow(f, true) end)                    -- 关到一半又打开
  R.run(0.4)
  local es = f:FindFirstChild("EaseScale")
  check(f.Visible and es and math.abs(es.Scale - 1) < 1e-6, "关到一半又打开：还显示着、大小回到 1（原来停在 0.97）：" .. tostring(es and es.Scale))
  local okG
  R.as("client", function() okG = C.uiPop(g, 1.07) end)
  check(okG == false and scales(g) == 1, "自己有 UIScale 的界面：uiPop 返回 false、不叠第二个")
  R.as("client", function() C.uiPop(h, 1.07) end)
  R.as("client", function() local o = R.Instance.new("UIScale") o.Name = "Other" o.Parent = h end)
  local okH
  R.as("client", function() okH = C.uiPop(h, 1.07) end)
  check(okH == false and scales(h) == 1 and h:FindFirstChild("Other") ~= nil, "后来别的模块也挂了 UIScale：自己那个撤掉（不乘在一起）")
  -- 黑场
  local fs = C.sceneFadeState
  R.as("client", function() C.sceneFade(0, 0.12, { from = 0.5 }) end)
  local a = fs()
  check(a.on and math.abs(a.tr - 0.5) < 1e-6, string.format("退镜那种：从半黑开始（透明 %.2f）", a.tr))
  R.run(0.3, 1 / 60)
  check(not fs().on, "0.12 秒淡开完就收起")
  -- 盖住加载：hold 到了，帧还卡（dt 1/20）就接着黑；连着两帧顺了才淡
  R.as("client", function() C.sceneFade(0.1, 0.25) end)
  R.run(0.3, 1 / 20)
  local b = fs()
  check(b.on and b.waiting and b.tr == 0, "hold 过了、帧还卡：接着全黑")
  R.run(2 / 60 + 1e-3, 1 / 60)
  check(not fs().waiting, "连着两帧顺：开始淡")
  R.run(0.5, 1 / 60)
  check(not fs().on, "淡完收起")
  -- ready 一直不成立：最多再等 0.8 秒
  R.as("client", function() C.sceneFade(0.1, 0.25, { ready = function() return false end }) end)
  R.run(0.6, 1 / 60)
  check(fs().waiting, "ready（镜头还没到车上）不成立：接着黑")
  R.run(0.45, 1 / 60)
  check(not fs().waiting, "最多等 hold + 0.8 秒")
  R.run(0.5, 1 / 60)
  -- 第二次接着：出击的黑还没淡开又来一下退镜（半黑）——不一下子变亮，也不把出击那一下要等的冲掉
  R.as("client", function() C.sceneFade(0.3, 0.25) end)
  R.run(0.05, 1 / 60)
  R.as("client", function() C.sceneFade(0, 0.12, { from = 0.5 }) end)
  check(fs().tr == 0, "全黑还没淡开又来一次半黑的：接着全黑（不一下子变亮）")
  R.run(0.1, 1 / 60)
  check(fs().waiting and fs().tr == 0, "出击那一下的 0.3 秒还没到：照旧黑着等")
  R.run(0.8, 1 / 60)
  check(not fs().on, "两边都满足以后淡开、跑完收起")
  R.as("client", function() gui:Destroy() end)
end

print("⑦ 击杀栏：连着来不往回跳")
do
  local slide = C.wtFeedSlide
  check(slide ~= nil, "击杀栏的测试口在")
  if slide then
    local function feed(i)
      G.R.Drive:FireClient(me, { op = "wtFeed", k = "甲" .. i, kt = "atk", v = "乙" .. i, vt = "def" })
      R.run(1 / 60, 1 / 60)   -- 消息下一帧才到
    end
    feed(1) R.run(0.3)
    feed(2) R.run(0.3)
    local _, rows, UD2 = slide()
    -- 假装上一条刚滑到一半：每一行在往下滑的半路上（第 1 行还偏左）
    R.as("client", function()
      for i, Rw in ipairs(rows) do Rw.f.Position = UD2(0, (i == 1) and -9 or 0, 0, (i - 1.5) * 22) end
    end)
    local mid = {}
    for i, Rw in ipairs(rows) do mid[i] = Rw.f.Position end
    feed(3)
    local start = slide()
    local ok = start[1] and start[1].Y.Offset == -22 and start[1].X.Offset == -18
    for i = 2, #rows do
      if not (start[i] and start[i].X.Offset == mid[i - 1].X.Offset and start[i].Y.Offset == mid[i - 1].Y.Offset) then ok = false end
    end
    check(ok, string.format("第 2 行从第 1 行现在的位置（%s, %s）接着滑、第 3 行从第 2 行的（%s, %s）……原来一律从固定的上一格开始",
      tostring(mid[1].X.Offset), tostring(mid[1].Y.Offset), tostring(mid[2].X.Offset), tostring(mid[2].Y.Offset)))
    R.run(0.5)
    check(rows[2].f.Position.Y.Offset == 22, "滑完停在自己那一格")
  end
end

print("⑧ B 大地图：从中心长开")
do
  R.as("client", function() C.wtMapToggle(true) end)
  R.run(0.3)
  local mg = me.PlayerGui:FindFirstChild("WtMap")
  local side, box
  for _, d in ipairs(mg and mg:GetDescendants() or {}) do
    if d.Name == "Side" then side = d end
    if d.Name == "MapBox" then box = d end
  end
  check(side and box and side.AnchorPoint.X == 0.5 and side.AnchorPoint.Y == 0.5 and box.AnchorPoint.X == 0.5 and box.AnchorPoint.Y == 0.5, "左栏、地图的锚点在中间（UIScale 从中心缩放）")
  if side and box then
    local sx = side.Position.X.Offset - side.Size.X.Offset / 2
    local bx, by = box.Position.X.Offset - box.Size.X.Offset / 2, box.Position.Y.Offset - box.Size.Y.Offset / 2
    check(math.abs(sx - 28) < 0.01 and math.abs(bx - (28 + 320 + 40)) < 0.01 and math.abs(by - 60) < 0.01,
      string.format("左上角还在原来的地方（左栏 x %.0f；地图 %.0f, %.0f）", sx, bx, by))
  end
  R.as("client", function() C.wtMapToggle(false) end)
  R.run(0.2)
end

T.summary()
