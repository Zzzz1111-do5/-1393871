-- 整备（用户 11-27「整个给载具配置武器的系统 做的很粗糙 我需要非常艺术经验的效果 参考战雷」）：python3 tools/mock/run.py tools/mock/workshop.lua
--   第一段（止血 + 地基）。真游戏开着匹配：没进局的人在「匹配中」的机库里（T.matchMode，同 tools/mock/wttestair.lua），像玩家一样：
--   ① 科技树机库里飞机能配挂载：阵容里选中歼-10C → 顶栏弹药键（不再淡掉、提示写「挂载」）→ 整备的挂载页按存的那套开（没存过是第一套预设）→
--      换一套预设（对地）、点一个挂点换一种弹（左右一对一起换）、内油 75% → 保存：服务器存档 tree.load 记着（照哪套改的、每个挂点、内油），
--      客户端的 Tree 跟着；机库里摆的飞机换成存的那套（同一架只换模型、镜头不动）；资料卡写「当前挂载」、存的武器、外挂重量
--   ② 地基：HangarStage.focus（缓动飞过去、拖动打断）、停机坪俯仰能压到负的、highlight（最多 4 个，还了能再借）、toScreen；Theme.T / tween
--   ③ 试驾：飞机实际挂的（服务器 e.load、模型上的 Load 属性、客户端开的 st.load）、内油和存的一样；
--      开飞机用的重量 / 阻力（Fly.lua）= FlightModel.loadout，也等于原来 Fly.lua 的算法（照抄一份在下面比）
--   ④ 出击（点开战 → 局内选车 → 先出地面车 → 回机库 → 出飞机）：停在机场的飞机挂的、内油和存的一样
--   ⑤ 服务器校验：非法武器清成空、内油夹到 0.25～1、不认得的预设不记、地面车 / 不认得的键不收；读档也照这样清
--   ⑥ FlightModel.loadout / perf：挂满比空挂重、阻力大、极速低、推重比小、转弯和爬升差；弹舱里的不算阻力；vTop / card 吃阻力增量
--   第二段（整备外壳 + 挂载页，Workshop.lua / WsArms.lua）：① 改成走整备的挂载页（顶栏弹药键 → 预设 → 底部挂点卡 → 武器卡 → 内油，改动即时存，Esc 两下回机库）；
--   ⑦ 挂点卡数（对称 / 不对称、按全景画面从左到右排）、选项 = 可挂的 + 「不挂」、左右一对一起换、性能数 = 飞行物理、外挂越多极速越低、悬停预览（右栏马上、3D 停一下、
--      不进存档、搭过的那套收着：装上 / 离开不重搭）、我的方案（右键菜单清空）、撤销（左栏「撤销」、Ctrl+Z）、保存状态「已保存」、
--      返回（右键、3D 空白处点一下、Esc；Roblox 系统菜单开着时 Esc 不算）、顶栏和页签重复的键收起、干扰弹没研究跳改装页、飞机没有涂装页签、截图（uidump）、Esc 回机库原样还原
local T = dofile(MOCK_DIR .. "/common.lua")
local R, Enum = T.R, T.Enum
local check = T.check

T.wtMode = true
T.matchMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
G.Config.Match.wait = 6   -- 测试里匹配等 6 秒（真游戏 60 秒）
T.runUntil(function() return G.worldReady end, 900)
local RS = R.services.ReplicatedStorage
local TT = R.require(RS:FindFirstChild("TechTree"))
local AD = R.require(RS:FindFirstChild("AirDefs"))
local FM = R.require(RS:FindFirstChild("FlightModel"))
local me = T.join("P1", 9571, true)
T.runUntil(function() return G.round ~= nil end, 30)
local P = G.P[me]
local C = T.C
T.leaveMenu()
T.runUntil(function() return G.rangeReady == true and T.findNamed("HangarGo") ~= nil end, 120, 1 / 10)
R.run(1)
check(G.round.phase == "queue", "在匹配中的机库（还没进局）：" .. tostring(G.round.phase))

local KEY = "cn_j10c"   -- 歼-10C：四套预设（空战 / 对地 / 防空压制 / 轰炸），七个挂点（左右成对）
local it = TT.byKey[KEY]
local d = AD.get(it.play)
-- 测试脚本跑在普通的 Lua 5.4 里（不是游戏脚本的环境）：没有 math.clamp、table.find
local function clamp(x, a, b) return math.max(a, math.min(b, x)) end
local function tfind(t, v) for i, x in ipairs(t) do if x == v then return i end end return nil end
local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for i = 1, #(d.st or {}) do if (a[i] or false) ~= (b[i] or false) then return false end end
  return true
end
local function sig(load)
  local s = {}
  for i = 1, #(d.st or {}) do s[i] = (load and load[i]) or "" end
  return table.concat(s, ",")
end

print("① 机库里给歼-10C 配挂载：顶栏弹药键 → 整备的挂载页 → 换预设、改一个挂点（左右一对）、内油 → 即时存进存档")
T.act("redeem", "Zhengyongshuo")   -- 全部解锁（设置里的兑换码）
R.run(1)
local starter = TT.starter("cn", "ground")
T.act("treeLineup", "cn", { starter.key, KEY })
R.run(1)
check(#d.presets >= 2, "歼-10C 有 " .. #d.presets .. " 套预设")
local card = T.findNamed("Line_" .. KEY)
check(card ~= nil, "阵容里有歼-10C 的卡")
if card then T.press(card) R.run(0.5) end
local sel = C.hangarSel and select(2, C.hangarSel())
check(sel == KEY, "选中了歼-10C（" .. tostring(sel) .. "）")
local ab = T.findNamed("AmmoBtn")
local tip = ab and ab:FindFirstChild("Tip")
check(ab ~= nil and ab.BackgroundTransparency < 0.3 and ab:GetAttribute("Off") == false, "顶栏弹药键对飞机不再淡掉（" .. tostring(ab and ab.BackgroundTransparency) .. "）")
check(tip ~= nil and tip.Text == "挂载", "提示写「挂载」（" .. tostring(tip and tip.Text) .. "）")
local S = C.hangarStage
check(S ~= nil and S.active() and S.modeNow() == "air", "背后是停机坪，停着这架飞机")
local shown0 = C.hangarShown and C.hangarShown()
check(shown0 == KEY .. "|" .. sig(AD.presetLoad(d)), "没存过：机库里摆的是第一套预设（" .. tostring(shown0) .. "）")
if ab then T.press(ab) R.run(1.2) end
local W, st = C.workshopState()
check(W.on and st ~= nil and st.key == KEY and st.d.id == d.id, "打开了整备的挂载页（" .. tostring(st and st.key) .. "）")
check(not (C.hangarOpen and C.hangarOpen()), "不再是老的挂载编辑器（Hangar.lua 留给步兵召唤台）")
check(st ~= nil and same(st.load, AD.presetLoad(d)) and st.pk == d.presets[1].key and math.abs(st.fuel - 1) < 1e-9,
  "按存的打开：没存过是第一套预设（" .. tostring(st and st.pk) .. "）、满内油")
local H0 = C.hangarParts
check(H0.wsOn == true and not H0.mid.Visible and not H0.row.Visible and not H0.match.Visible, "机库的国旗 / 乘员 / 阵容卡 / 这一局那块收起了")
local lg = T.findNamed("WsBack")
check(lg ~= nil and T.findNamed("HangarGo") ~= nil, "抬头有「‹ 机库」，顶栏「加入战斗」还在（唯一的主按钮）")
local nPrimary = 0
for _, x in ipairs(me.PlayerGui:GetDescendants()) do
  if x.ClassName == "TextButton" and T.visible(x) and x:IsDescendantOf(C.hangarGui) and x.Name ~= "HangarGo"
    and x.BackgroundTransparency < 0.05 and x.BackgroundColor3 == C.Theme.C.TEXT and not x.Name:match("^Tab_") and not x.Name:match("^Fuel") and not x.Name:match("^Sym")
    and not x.Name:match("^Preset_") and not x.Name:match("^Mine_") then
    nPrimary = nPrimary + 1
  end
end
check(nPrimary == 0, "整备里没有别的白底主按钮（选中的页签、分段键不算）：" .. nPrimary)
local pb = T.findNamed("Preset_ag")
check(pb ~= nil and T.findNamed("Preset_" .. d.presets[1].key) ~= nil, "左栏上面是这架飞机的预设方案")
if pb then T.press(pb) R.run(0.6) end
local want = AD.presetLoad(d, "ag")
check(st and same(st.load, want) and st.pk == "ag", "点「对地」：换成那一套")
-- 机翼中段那一对：底部的挂点卡（左右对称：一对一张）
local ci = nil
for k, g in ipairs(st.cards) do if g.name == "mid" then ci = k end end
check(ci ~= nil and #st.cards[ci].st == 2, "机翼中段那一对合成一张卡（第 " .. tostring(ci) .. " 张）")
local idx, mate = st.cards[ci].st[1], st.cards[ci].st[2]
local NEW = "pl12"
check(want[idx] ~= NEW and tfind(d.st[idx].opts, NEW) ~= nil, "这个挂点能挂霹雳-12、现在挂的不是（" .. tostring(want[idx]) .. "）")
local scard = T.findNamed("Station_" .. ci)
if scard then T.press(scard) R.run(1.0) end
check(st.sel == ci, "选中了这一对（" .. tostring(st.sel) .. "）")
local vsel = S.viewState()
check(vsel.at ~= nil and vsel.sd < vsel.base, string.format("镜头飞到挂点那一侧（离得 %.1f，全景 %.1f）", vsel.sd, vsel.base))
local opt = T.findNamed("Opt_" .. NEW)
check(opt ~= nil and T.findNamed("Opt_none") ~= nil, "列表里有霹雳-12、最后一张是「不挂」")
if opt then T.press(opt) R.run(0.8) end
want[idx], want[mate] = NEW, NEW
check(same(st.load, want), "左右一对一起换成霹雳-12：" .. sig(st.load))
check(math.abs(S.viewState().sd - vsel.sd) < 1e-3 and S.viewState().at ~= nil, "换上以后同一架只换模型：镜头还在这个挂点")
local srow = T.findNamed("BackToSchemes")
local srowT = srow and srow:FindFirstChild("Label")
check(srowT ~= nil and srowT.Text:find("已改 2") ~= nil, "选着挂点时方案收成一行：「" .. tostring(srowT and srowT.Text) .. "」")
check(T.findNamed("Preset_ag") == nil, "选着挂点时预设那几块收起来（武器卡整张整张地放）")
if srow then T.press(srow) R.run(0.8) end
check(st.sel == nil and C.workshopOpen(), "点「‹ 方案」：回全景")
local chip = T.findNamed("Preset_ag")
local modTag = chip and chip:FindFirstChild("Mod")
check(modTag ~= nil and modTag.Visible and modTag.Text:find("已改") ~= nil, "预设那一块写「已改」（" .. tostring(modTag and modTag.Text) .. "）")
local stLine = nil
for _, x in ipairs(me.PlayerGui:GetDescendants()) do if x.Name == "LoadStatus" then stLine = x end end
check(stLine ~= nil and stLine.Text:find("改过 2 个挂点") ~= nil, "左栏写「照『对地』改过 2 个挂点」（" .. tostring(stLine and stLine.Text) .. "）")
local f75 = T.findNamed("Fuel75")
check(f75 ~= nil, "内油能选 75%")
if f75 then T.press(f75) end
R.run(1.5)
local sv = P.data.tree.load and P.data.tree.load[KEY]
check(sv ~= nil and sv.p == "ag" and same(sv.l, want) and sv.f == 0.75,
  string.format("改动即时存：服务器存档记着照「%s」改的、%s、内油 %s", tostring(sv and sv.p), sig(sv and sv.l), tostring(sv and sv.f)))
local ct = C.treeState().load and C.treeState().load[KEY]
check(ct ~= nil and same(ct.l, want) and ct.f == 0.75 and ct.p == "ag", "客户端的 Tree 跟着")
check(#T.texts("挂载已保存") == 0, "即时存不弹「挂载已保存」")
check(C.hangarShown() == KEY .. "|" .. sig(want), "机库里摆的飞机就是改过的这套（" .. tostring(C.hangarShown()) .. "）")
local scard2 = T.findNamed("Station_" .. ci)
if scard2 then T.press(scard2) R.run(1.0) end
check(st.sel == ci, "再选中这一对")
-- Esc：先退回全景，再按一次回机库（机库那几层滑回来）
T.key(Enum.KeyCode.Escape, true)
T.key(Enum.KeyCode.Escape, false)
R.run(0.8)
check(C.workshopOpen() and st.sel == nil and S.viewState().at ~= nil, "Esc 一下：退回全景（还在整备里）")
T.key(Enum.KeyCode.Escape, true)
T.key(Enum.KeyCode.Escape, false)
R.run(1.2)
check(not C.workshopOpen() and H0.wsOn == nil and H0.mid.Visible and H0.row.Visible and H0.match.Visible, "Esc 再一下：回机库，收起的几层都回来了")
check(T.findNamed("HangarTest") ~= nil and T.findNamed("Line_" .. KEY) ~= nil, "阵容卡、试驾键能点了")
check(C.stageFree(T.V3(640, 360, 0)), "回机库以后：点空白处照常转车")
check(C.hangarShown() == KEY .. "|" .. sig(want), "回机库：摆的还是存的那套")
-- 资料卡：写当前挂载
R.as("client", function() C.openInfo(it) end)
R.run(0.5)
local cur, hasNew, ext = false, false, false
for _, x in ipairs(C.infoGui:GetDescendants()) do
  if x.ClassName == "TextLabel" then
    if x.Text:find("当前挂载") and x.Text:find(C.T("preset.ag"), 1, true) then cur = true end
    if x.Text:find(C.T("aw." .. NEW), 1, true) then hasNew = true end
    if x.Text:find("外挂") and x.Text:find("75%%") then ext = true end
  end
end
check(cur and hasNew and ext, string.format("资料卡写「当前挂载 · 对地」、存的霹雳-12、内油和外挂重量（%s %s %s）", tostring(cur), tostring(hasNew), tostring(ext)))
R.as("client", function() C.infoGui.Visible = false end)
R.run(0.3)

print("② 地基：机库镜头对焦、轮廓高亮、坐标换算；动效常量")
local v0 = S.viewState()
check(v0.mode == "air" and v0.lim and v0.lim.p0 < 0, string.format("停机坪：俯仰能压到 %.2f（从机翼下面往上看）", v0.lim and v0.lim.p0 or 0))
local st0 = idx and d.st[idx]
local at = st0 and (T.CF(0, d.gearH or 5, 0) * st0.pos) or T.V3(0, 5, 0)
local d0 = v0.sd
R.as("client", function() S.focus({ at = at, dist = 30, yaw = 1.0, pitch = -0.1, t = 0.55 }) end)
R.run(0.25)
local vm = S.viewState()
check(vm.flying and vm.sd < d0 - 1 and vm.sd > 30 + 1, string.format("缓动飞过去：飞到一半（离得 %.1f，从 %.1f 到 30）", vm.sd, d0))
R.run(0.6)
local v1 = S.viewState()
check(not v1.flying and math.abs(v1.sd - 30) < 1e-3 and math.abs(v1.sp + 0.1) < 1e-3 and (v1.sat - at).Magnitude < 1e-3,
  string.format("飞到了：离挂点 %.2f、俯仰 %.3f（负的：从下往上看）", v1.sd, v1.sp))
local sp, z, on = S.toScreen(S.world(at))
check(sp ~= nil and on and z > 0 and math.abs(sp.X - 640) < 60 and sp.Y < 360, string.format("toScreen：挂点在画面正中略偏上（%s）", sp and string.format("%.0f, %.0f", sp.X, sp.Y) or "nil"))
R.as("client", function() S.focus({ yaw = 2.5, t = 0.55 }) end)
R.run(0.1)
R.as("client", function() S.drag(12, 0) end)
check(not S.viewState().flying, "飞的时候拖动：直接打断、跟手")
R.as("client", function() S.drag(0, -2000) end)
check(math.abs(S.viewState().pitch - v0.lim.p0) < 1e-6, "往下拖到底：停在停机坪的下限")
R.as("client", function() S.drag(0, 4000) end)
check(math.abs(S.viewState().pitch - v0.lim.p1) < 1e-6 and v0.lim.p1 > 0.8, string.format("往上拖到底：露天停机坪能升到 %.2f 往下看机翼上面（厂房里 0.8）", v0.lim.p1))
local hs = {}
R.as("client", function()
  for i = 1, 5 do hs[i] = S.highlight(S.model(), { front = i == 1 }) end
end)
check(hs[4] ~= nil and hs[5] == nil and S.highlightsUsed() == 4, "高亮最多借 4 个（第 5 个借不到）")
R.as("client", function()
  S.unhighlight(hs[2])
  hs[6] = S.highlight(S.model())
end)
check(hs[6] ~= nil and S.highlightsUsed() == 4, "还一个以后能再借")
R.as("client", function() S.unhighlight() end)
check(S.highlightsUsed() == 0, "不给句柄：全部还回去")
R.as("client", function() S.home(0) end)
R.run(0.5)
local TH = C.Theme
check(TH.T and TH.T.hover == 0.12 and TH.T.cam == 0.55 and TH.T.out < TH.T.panel and TH.T.panel <= 0.3, "Theme.T：悬停 0.12、镜头 0.55、退场比进场短、进场不超过 0.3 秒")
local fr = R.Instance.new("Frame")
local okT = pcall(function() TH.tween(fr, { BackgroundTransparency = 0.4 }, "ui") end)
check(okT and fr.BackgroundTransparency == 0.4, "Theme.tween：补到终值")
local okBad = pcall(function() TH.tween(fr, { NoSuchProp = 1 }, "ui") TH.tween(nil, { Size = 1 }) end)
check(okBad, "属性写错、零件没了：不报错")
check(TH.stagger(1) == 0 and math.abs(TH.stagger(3) - 2 * TH.T.stagger) < 1e-9 and TH.stagger(30) == TH.stagger(TH.STAGGER_MAX), "错开：每项 25 毫秒，最多算到第 8 项")
check(TH.ease("cam", 0) == 0 and math.abs(TH.ease("cam", 1) - 1) < 1e-9 and TH.ease("out", 0.5) > 0.5 and TH.ease("cam", 0.25) < 0.25, "缓动：先快后慢、镜头两头慢")

print("③ 试驾：飞机挂的、内油和存的一样；飞行物理的重量 / 阻力用同一套")
local tb = T.findNamed("HangarTest")
check(tb ~= nil, "右边有「试驾」")
if tb then T.press(tb) end
T.runUntil(function() return P.alive and P.vehicle ~= nil and C.fly ~= nil end, 30)
local e = P.vehicle
check(e ~= nil and e.air and e.testDrive and e.treeKey == KEY, "坐进了试驾的歼-10C（" .. tostring(e and e.def and e.def.id) .. "）")
R.run(1)
if e and e.air and C.fly then
  check(same(e.load, want) and e.model:GetAttribute("Load") == sig(want), "服务器挂的、模型上的 Load 属性和存的一样：" .. tostring(e.model:GetAttribute("Load")))
  check(e.fuelSel == 0.75, "内油是存的 75%（" .. tostring(e.fuelSel) .. "）")
  local st = C.fly
  check(same(st.load, want), "客户端开的飞机挂的也一样")
  -- 原来 Fly.lua 的算法（照抄）：重构以后一位不差
  local function oldMass()
    local D, dd = st.fmD, st.d
    local m = D.m0 + D.fi * clamp(st.fuel or 1, 0, 1) + D.fi * math.max(st.fuelX or 0, 0)
    local dS = 0
    for i, s in ipairs(dd.st or {}) do
      local wid = st.load and st.load[i]
      local w = wid and AD.W[wid]
      local n = (st.stores and st.stores[i]) or 0
      if w and w.kind == "rkt" then
        local full = math.max(w.tubes or 1, 1)
        m = m + FM.storeMass(w, AD.M) * (0.4 + 0.6 * clamp(n / full, 0, 1))
        if not s.bay then dS = dS + FM.storeDrag(w, AD.M) end
      elseif w and n > 0 then
        m = m + FM.storeMass(w, AD.M) * n
        if not s.bay then dS = dS + FM.storeDrag(w, AD.M) * n end
      end
    end
    return m, dS / D.S
  end
  local m1, c1 = C.flyMass()
  local m0, c0 = oldMass()
  local L = FM.loadout(st.d, st.load, st.fuel, { D = st.fmD, stores = st.stores, fuelX = st.fuelX, AD = AD })
  check(m1 ~= nil and m1 == m0 and c1 == c0 and L.m == m1 and L.dCD0 == c1,
    string.format("开飞机的重量 / 阻力（%.1f kg / ΔCD0 %.5f）= FlightModel.loadout = 原来的算法", m1 or -1, c1 or -1))
  local Lf = FM.loadout(d, want, st.fuel, { key = KEY, AD = AD, fuelX = st.fuelX })   -- 每个挂点按默认（挂满）：刚出来还没打过
  check(math.abs(Lf.m - m1) < 1e-6 and math.abs(Lf.dCD0 - c1) < 1e-12, string.format("刚出来挂满：按存的挂载算的一样（%.1f / %.1f kg）", Lf.m, m1))
end
T.remoteAs(me, "Drive", { op = "exit", hangar = true })
T.runUntil(function() return not P.alive end, 15)
T.runUntil(function() return T.findNamed("HangarTest") ~= nil end, 10)
R.run(1)
check(not P.alive and not P.inTest, "长按 H 回机库")

print("④ 出击：点开战 → 局内先出地面车 → 回机库 → 出歼-10C，停机位上的飞机挂的和存的一样")
T.act("matchJoin", starter.key)
R.run(0.5)
T.runUntil(function() return G.round.phase ~= "queue" end, 15)
check(G.round.phase == "prep", "匹配到了：准备阶段（" .. tostring(G.round.phase) .. "）")
-- 局内选车是战雷的出击页（WtSpawn.lua，用户 11-28「被击毁重新召唤载具要有这个界面」）：顶上阵容卡 Spawn_<键>、右下「加入战斗！」SpawnGo
T.runUntil(function() return C.S and C.S.pick == true and T.findNamed("Spawn_" .. starter.key) ~= nil end, 10)
local gcard = T.findNamed("Spawn_" .. starter.key)
if gcard then T.press(gcard) R.run(0.3) end
local go = T.findNamed("SpawnGo")
if go then T.press(go) end
T.runUntil(function() return P.alive and P.vehicle ~= nil end, 30)
local eg = P.vehicle
check(eg ~= nil and not eg.air and eg.treeKey == starter.key, "先出了地面车（" .. tostring(eg and eg.treeKey) .. "）")
R.run(1)
T.remoteAs(me, "Drive", { op = "exit", hangar = true })
T.runUntil(function() return not P.alive end, 15)
T.runUntil(function() return T.findNamed("SpawnGo") ~= nil end, 10)
G.wtState(P).sp = 5000   -- 打出了分、攒够了出飞机的 SP（测试直接给）
G.pushOne(P)
R.run(1.5)
local acard = T.findNamed("Spawn_" .. KEY)
check(acard ~= nil and acard:GetAttribute("Locked") ~= true, "出过地面车：飞机卡能选了")
if acard then T.press(acard) R.run(0.5) end
go = T.findNamed("SpawnGo")
if go then T.press(go) end
local ea
T.runUntil(function()
  for _, x in ipairs(G.aircraft or {}) do if x.alive and x.treeKey == KEY and not x.testDrive then ea = x end end
  return ea ~= nil
end, 30)
check(ea ~= nil and ea.padId ~= nil, "出击：歼-10C 停在机场停机位上（" .. tostring(ea and ea.padId) .. "）")
if ea then
  check(same(ea.load, want) and ea.model:GetAttribute("Load") == sig(want), "挂的、模型上的 Load 属性和存的一样：" .. tostring(ea.model:GetAttribute("Load")))
  check(ea.fuelSel == 0.75 and math.abs((ea.model:GetAttribute("Fuel") or 0) - 0.75) < 0.01, "内油是存的 75%（" .. tostring(ea.fuelSel) .. "）")
end
-- 退出这一局回普通机库（整备只在机库里开：战雷的出击页里没有整备），⑤ 以后照旧在机库里
T.act("matchLeave")
T.runUntil(function() return P.match == nil and T.findNamed("HangarGo") ~= nil end, 15)
R.run(1)

print("⑤ 服务器校验：非法武器清成空、内油夹住、不认得的预设不记")
local bad = { "aim120", "pl15", 12, "b250", "zzz", true, "tk800" }   -- 别家的弹、挂不上这个挂点的、不是字符串的
T.act("treeLoad", KEY, bad, "nope", 0.05)
R.run(0.5)
local sv2 = P.data.tree.load[KEY]
local nBad, nKept = 0, 0
for i, s in ipairs(d.st) do
  local w = bad[i]
  local legal = type(w) == "string" and tfind(s.opts, w) ~= nil
  if legal then
    if sv2.l[i] == w then nKept = nKept + 1 end
  elseif sv2.l[i] ~= false then
    nBad = nBad + 1
  end
end
check(sv2 ~= nil and nBad == 0 and same(sv2.l, AD.cleanLoad(d, bad)), string.format("非法武器都清成空（%s；合法的留了 %d 个）", sig(sv2 and sv2.l), nKept))
check(sv2 ~= nil and sv2.f == 0.25 and sv2.p == nil, "内油 5% 夹到 25%、不认得的预设不记（" .. tostring(sv2 and sv2.f) .. "）")
T.act("treeLoad", starter.key, { "pl10" }, false, 1)   -- 中间不传 nil（远程事件的参数表不能有空洞）
T.act("treeLoad", "nope_key", { "pl10" }, false, 1)
T.act("treeLoad", KEY, "junk")   -- 没给挂载、没给预设：照第一套
R.run(0.5)
check(P.data.tree.load[starter.key] == nil and P.data.tree.load.nope_key == nil, "地面车、不认得的键不收")
local sv3 = P.data.tree.load[KEY]
check(sv3 ~= nil and same(sv3.l, AD.presetLoad(d)) and sv3.f == 1, "挂载不是表：按第一套预设、满内油")
-- 读档：存档里不对的一样清掉（换个没跑客户端的玩家读一份造的档）
local pl2 = T.join("P2", 9572, false)
local P2 = G.P[pl2]
G.econFromSave(P2, { tree = { nat = "cn",
  load = { [KEY] = { p = "ag", l = bad, f = 7 }, [starter.key] = { l = { "pl10" } }, nope_key = { l = {} } },
  ammo = { [starter.key] = { zzz = 5, [next(R.require(RS:FindFirstChild("Ballistics")).AMMO)] = 999 }, [KEY] = { x = 1 } },
  skin = { [starter.key] = { c = "nope", n = 12345, e = true } } } })
local t2 = P2.data.tree
local a2 = t2.ammo[starter.key]
local n2 = 0
for _ in pairs(a2 or {}) do n2 = n2 + 1 end
check(t2.load[KEY] ~= nil and same(t2.load[KEY].l, AD.cleanLoad(d, bad)) and t2.load[KEY].f == 1 and t2.load[KEY].p == "ag"
  and t2.load[starter.key] == nil and t2.load.nope_key == nil, "读档：挂载照样清（非法武器空、内油夹住、地面车 / 不认得的去掉）")
check(n2 == 1 and select(2, next(a2)) == 200 and t2.ammo[KEY] == nil, "读档：配弹只留认得的弹种、最多 200 发、飞机没有配弹")
local s2 = t2.skin[starter.key]
check(s2 ~= nil and s2.c == nil and s2.n == 999 and s2.e == true, "读档：涂装不认得的不记、战术号码夹到 999")

print("⑥ FlightModel.loadout / perf：挂满比空挂重、阻力大、极速低")
local D = FM.get(d.id, KEY)
local full, empty = {}, {}
for i, s in ipairs(d.st) do   -- 挂满：每个挂点挂能挂的最重的那种弹
  local best, bm = false, -1
  for _, w in ipairs(s.opts) do
    local W = AD.W[w]
    if W and W.kind ~= "tank" then
      local mm = FM.storeMass(W, AD.M) * AD.count(s, w)
      if mm > bm then best, bm = w, mm end
    end
  end
  full[i], empty[i] = best, false
end
local Lf = FM.loadout(d, full, 1, { key = KEY, AD = AD })
local Le = FM.loadout(d, empty, 1, { key = KEY, AD = AD })
check(Lf.ext > 1000 and Le.ext == 0 and Lf.m > Le.m and Lf.dCD0 > 0 and Le.dCD0 == 0,
  string.format("挂满外挂 %.0f kg、ΔCD0 +%.4f；空挂 0", Lf.ext, Lf.dCD0))
local Pf, Pe = FM.perf(D, Lf.m, Lf.dCD0), FM.perf(D, Le.m, Le.dCD0)
check(Pf.vAB < Pe.vAB - 5 and Pf.vMil < Pe.vMil, string.format("极速：挂满 %.0f km/h < 空挂 %.0f km/h（加力，1000 米）", Pf.vAB * 3.6, Pe.vAB * 3.6))
check(Pf.tw < Pe.tw and Pf.str < Pe.str and Pf.roc < Pe.roc,
  string.format("推重比 %.2f < %.2f、持续转弯 %.1f < %.1f °/s、爬升 %.0f < %.0f m/s", Pf.tw, Pe.tw, Pf.str * 57.3, Pe.str * 57.3, Pf.roc, Pe.roc))
check(FM.vTop(D, Le.m, 130, 1000, 0.01) < FM.vTop(D, Le.m, 130, 1000) and FM.card(D).str == FM.card(D, nil, 0).str, "vTop / card 吃阻力增量（不给 = 干净构型，同原来）")
local d20 = AD.get("j20")
local L20 = FM.loadout(d20, AD.presetLoad(d20, "aa"), 1, { AD = AD })
check(L20.ext > 0 and L20.dS == 0, string.format("歼-20 弹舱里挂的不算阻力（外挂重 %.0f kg、阻力面积 %.3f）", L20.ext, L20.dS))
local Lz = FM.loadout(d, full, 1, { key = KEY })
check(Lz.m == Lf.m and Lz.dCD0 == Lf.dCD0, "不传 AirDefs：FlightModel 自己找，结果一样")

print("⑦ 整备的挂载页：挂点卡（对称 / 不对称）、选项 = 可挂的 + 不挂、一对一起换、性能数 = 飞行物理、外挂越多极速越低、悬停预览、我的方案、Esc 还原、截图")
T.remoteAs(me, "Drive", { op = "exit", hangar = true })
T.runUntil(function() return not P.alive end, 15)
T.runUntil(function() return T.findNamed("Line_" .. KEY) ~= nil end, 15)
R.run(1)
local lc = T.findNamed("Line_" .. KEY)
if lc then T.press(lc) R.run(0.5) end
local inPick = C.S ~= nil and C.S.pick == true
local goB = T.findNamed("HangarGo")
local goParent0 = goB and goB.Parent and goB.Parent.Name
local ab7 = T.findNamed("AmmoBtn")
if ab7 then T.press(ab7) R.run(1.2) end
local W7, st7 = C.workshopState()
check(W7.on and st7 ~= nil and st7.key == KEY, "机库里打开整备（" .. tostring(st7 and st7.key) .. (inPick and "，局内" or "") .. "）")
goB = T.findNamed("HangarGo")
check(goB ~= nil and goB.Parent ~= nil and goB.Parent.Name == "TopRow", "整备开着：主按钮在顶栏正中（原来在 " .. tostring(goParent0) .. "；右下是整备的底部条）")
-- 挂点卡：对称时同名的一对一张、不对称时一个挂点一张，从左翼尖排到右翼尖
local uniq, nU = {}, 0
for _, s0 in ipairs(d.st) do if not uniq[s0.name] then uniq[s0.name] = true nU = nU + 1 end end
local function visCards()
  local n = 0
  for k = 1, 40 do if T.findNamed("Station_" .. k) then n = n + 1 end end
  return n
end
check(#st7.cards == nU and visCards() == nU, string.format("左右对称：%d 个挂点合成 %d 张卡（界面上 %d 张）", #d.st, nU, visCards()))
local symB = T.findNamed("SymToggle")
check(symB ~= nil, "卡组上面有「左右对称」勾选框")
if symB then T.press(symB) R.run(0.4) end
check(not st7.sym and #st7.cards == #d.st and visCards() == #d.st, string.format("不对称：一个挂点一张（%d 张）", visCards()))
-- 顺序照全景画面从左到右（全景从左前方看：右翼在画面左边），和机身上的编号一一对得上
local yaw0 = math.rad(-150)
local function ovX(p) return p.X * math.cos(yaw0) - p.Z * math.sin(yaw0) end
local ordered = true
for k = 2, #st7.cards do if ovX(d.st[st7.cards[k].st[1]].pos) < ovX(d.st[st7.cards[k - 1].st[1]].pos) - 1e-6 then ordered = false end end
check(ordered and d.st[st7.cards[1].st[1]].pos.X > 0 and d.st[st7.cards[#st7.cards].st[1]].pos.X < 0, "按全景画面从左到右排（右翼尖在最左、左翼尖在最右）")
local tipL = 1
for i, s0 in ipairs(d.st) do if s0.pos.X < d.st[tipL].pos.X then tipL = i end end
local kTip = nil
for k, g in ipairs(st7.cards) do if g.st[1] == tipL then kTip = k end end
local num1 = kTip and T.findNamed("Station_" .. kTip) and T.findNamed("Station_" .. kTip):FindFirstChild("Num")
check(num1 ~= nil and num1.Text == "1", "左翼尖那个是 1 号（" .. tostring(num1 and num1.Text) .. "，第 " .. tostring(kTip) .. " 张）")
symB = T.findNamed("SymToggle")
if symB then T.press(symB) R.run(0.4) end
check(st7.sym and #st7.cards == nU, "再勾上对称：合回去")
-- 每一张卡的选项 = 这个挂点能挂的 + 「不挂」
local allOk, badT = true, ""
for k, g in ipairs(st7.cards) do
  local sc7 = T.findNamed("Station_" .. k)
  if sc7 then T.press(sc7) R.run(0.3) end
  local s0 = d.st[g.st[1]]
  local n, total = 0, 0
  for _, w in ipairs(s0.opts) do if T.findNamed("Opt_" .. w) then n = n + 1 end end
  for _, x in ipairs(me.PlayerGui:GetDescendants()) do
    if x.ClassName == "TextButton" and x.Name:match("^Opt_") and T.visible(x) then total = total + 1 end
  end
  if not (st7.sel == k and n == #s0.opts and T.findNamed("Opt_none") ~= nil and total == #s0.opts + 1) then allOk = false badT = badT .. g.name .. " " end
end
check(allOk, "每张卡的选项 = 能挂的 + 「不挂」" .. ((badT ~= "") and ("（不对：" .. badT .. "）") or ""))
-- 左右一对一起换（外侧那一对）
local oc = nil
for k, g in ipairs(st7.cards) do if g.name == "outer" then oc = k end end
local occ = oc and T.findNamed("Station_" .. oc)
if occ then T.press(occ) R.run(0.6) end
local g7 = st7.cards[oc]
local cur7 = st7.load[g7.st[1]]
local pick7 = nil
for _, w in ipairs(d.st[g7.st[1]].opts) do if w ~= cur7 then pick7 = w end end
local po = pick7 and T.findNamed("Opt_" .. pick7)
if po then T.press(po) R.run(1.0) end
check(pick7 ~= nil and st7.load[g7.st[1]] == pick7 and st7.load[g7.st[2]] == pick7, "外侧一对一起换成 " .. tostring(pick7))
local sv7 = P.data.tree.load[KEY]
check(sv7 ~= nil and sv7.l[g7.st[1]] == pick7 and sv7.l[g7.st[2]] == pick7, "存档跟着（即时存）")
-- 性能数 = 飞行物理（FlightModel.loadout / perf）
local function int(n)
  n = math.floor((n or 0) + 0.5)
  local s1 = tostring(math.abs(n))
  local o = s1:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if o:sub(1, 1) == "," then o = o:sub(2) end
  return ((n < 0) and "−" or "") .. o
end
local function uiVal(name, child)
  for _, x in ipairs(me.PlayerGui:GetDescendants()) do
    if x.Name == name and T.visible(x) then
      local v = x:FindFirstChild(child or "Val")
      return v and v.Text
    end
  end
end
local Dfm = FM.get(d.id, KEY)
R.run(0.5)
local Lc = FM.loadout(d, st7.load, st7.fuel, { key = KEY, AD = AD })
local Pc = FM.perf(Dfm, Lc.m, Lc.dCD0)
local empty7 = {}
for i = 1, #d.st do empty7[i] = false end
local Le7 = FM.loadout(d, empty7, st7.fuel, { key = KEY, AD = AD })
local Pe7 = FM.perf(Dfm, Le7.m, Le7.dCD0)
check(uiVal("Cmp_vAB") == int(Pc.vAB * 3.6) and uiVal("Cmp_vAB", "Base") == int(Pe7.vAB * 3.6),
  string.format("极速（加力）%s → %s km/h = 飞行物理的 %s → %s", tostring(uiVal("Cmp_vAB", "Base")), tostring(uiVal("Cmp_vAB")), int(Pe7.vAB * 3.6), int(Pc.vAB * 3.6)))
check(uiVal("Cmp_tw") == string.format("%.2f", Pc.tw) and uiVal("Cmp_str") == string.format("%.1f", Pc.str * 180 / math.pi) and uiVal("Cmp_roc") == int(Pc.roc)
  and uiVal("Cmp_wl") == int(Pc.wl), string.format("推重比 %s、持续转弯 %s °/s、爬升 %s m/s、翼载 %s 和飞行物理一样", tostring(uiVal("Cmp_tw")), tostring(uiVal("Cmp_str")),
  tostring(uiVal("Cmp_roc")), tostring(uiVal("Cmp_wl"))))
check(uiVal("Stat_ext") == int(Lc.ext) .. " kg" and uiVal("Stat_mass") == int(Lc.m) .. " kg" and uiVal("Stat_drag") == "+" .. string.format("%.4f", Lc.dCD0),
  string.format("外挂 %s、起飞重量 %s、阻力 %s（FlightModel.loadout）", tostring(uiVal("Stat_ext")), tostring(uiVal("Stat_mass")), tostring(uiVal("Stat_drag"))))
-- 外挂越多极速越低：一张张卡先全清空，再一张张挂上最重的那种，每挂一张界面上的极速都往下掉
local function choose(k, wid)
  local sc7 = T.findNamed("Station_" .. k)
  if sc7 and st7.sel ~= k then T.press(sc7) R.run(0.3) end
  local b = T.findNamed("Opt_" .. (wid or "none"))
  if b then T.press(b) R.run(0.4) end
end
local function vab()
  local t = uiVal("Cmp_vAB")
  return t and tonumber((t:gsub(",", "")))
end
for k = 1, #st7.cards do choose(k, nil) end
R.run(0.4)
local seq = { vab() }
local okSeq = seq[1] ~= nil and uiVal("Cmp_vAB") == uiVal("Cmp_vAB", "Base")
for k, g in ipairs(st7.cards) do
  local best, bm = nil, -1
  for _, w in ipairs(d.st[g.st[1]].opts) do
    local Wd = AD.W[w]
    if Wd and Wd.kind ~= "tank" then
      local mm = FM.storeMass(Wd, AD.M) * AD.count(d.st[g.st[1]], w)
      if mm > bm then best, bm = w, mm end
    end
  end
  choose(k, best)
  R.run(0.3)
  local v = vab()
  if not (v and seq[#seq] and v < seq[#seq]) then okSeq = false end
  table.insert(seq, v or -1)
end
local seqT = {}
for i, v in ipairs(seq) do seqT[i] = tostring(v) end
check(okSeq, "外挂越多极速越低（加力，km/h）：" .. table.concat(seqT, " → "))
-- 悬停预览：右栏马上换成琥珀色的预览值、3D 停一下才换上；离开还原
local mc = nil
for k, g in ipairs(st7.cards) do if g.name == "mid" then mc = k end end
local mcc = mc and T.findNamed("Station_" .. mc)
if mcc and st7.sel ~= mc then T.press(mcc) R.run(0.6) end
local curM = st7.load[st7.cards[mc].st[1]]
local hw = nil
for _, w in ipairs(d.st[st7.cards[mc].st[1]].opts) do if w ~= curM then hw = w end end
local hb = hw and T.findNamed("Opt_" .. hw)
local sig7 = KEY .. "|" .. sig(st7.load)
if hb then R.as("client", function() hb.MouseEnter:Fire(200, 300) end) end
R.run(0.05)
local valColor = nil
for _, x in ipairs(me.PlayerGui:GetDescendants()) do if x.Name == "Cmp_vAB" and T.visible(x) then valColor = x.Val.TextColor3 end end
check(st7.hoverOpt == hw and valColor == C.Theme.C.WARN and C.hangarShown() == sig7, "悬停 " .. tostring(hw) .. "：右栏马上显示预览（琥珀），3D 还没换（停一下）")
R.run(0.3)
local pv7 = {}
for i = 1, #d.st do pv7[i] = st7.load[i] end
for _, j in ipairs(st7.cards[mc].st) do pv7[j] = hw end
check(C.hangarShown() == KEY .. "|" .. sig(pv7) and same(st7.load, P.data.tree.load[KEY].l), "停 0.12 秒以后 3D 换上预览；预览不进存档")
local detail = nil
for _, x in ipairs(me.PlayerGui:GetDescendants()) do if x.Name == "WsDetail" then detail = x end end
check(detail ~= nil and detail.Visible, "旁边浮出这枚弹的资料卡")
if hb then R.as("client", function() hb.MouseLeave:Fire(200, 300) end) end
R.run(0.3)
check(st7.hoverOpt == nil and C.hangarShown() == sig7 and detail ~= nil and not detail.Visible, "离开：3D 还原、资料卡收起")
check(C.hangarAirCached and C.hangarAirCached() >= 1, "悬停预览搭过的那套收着：离开、装上都不重搭（缓存 " .. tostring(C.hangarAirCached and C.hangarAirCached()) .. " 套）")
-- 我的方案（全景时才有）：空着的点一下存现在这一套；换成别的再点回来
local bk7 = T.findNamed("BackToSchemes")
if bk7 then T.press(bk7) R.run(0.6) end
local mine1 = T.findNamed("Mine_1")
if mine1 then T.press(mine1) R.run(0.8) end
local set1 = P.data.tree.sets and P.data.tree.sets[KEY] and P.data.tree.sets[KEY]["1"]
check(set1 ~= nil and same(set1.l, st7.load) and set1.f == st7.fuel and st7.mine == 1, "「我的 1」存了现在这一套（存档 tree.sets）")
local saved1 = {}
for i = 1, #d.st do saved1[i] = st7.load[i] end
local paa = T.findNamed("Preset_aa")
if paa then T.press(paa) R.run(0.6) end
check(st7.pk == "aa" and same(st7.load, AD.presetLoad(d, "aa")), "换成「空战」")
mine1 = T.findNamed("Mine_1")
if mine1 then T.press(mine1) R.run(0.8) end
check(same(st7.load, saved1) and st7.mine == 1 and st7.pk == nil and same(P.data.tree.load[KEY].l, saved1), "点「我的 1」：换回存的那套（也存进挂载）")
-- 有内容的一格右键：小菜单「覆盖成现在这套 / 清空」；点清空
mine1 = T.findNamed("Mine_1")
if mine1 then R.as("client", function() mine1.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton2 }) end) end
R.run(0.2)
local mclr = T.findNamed("Mine_Clear")
check(mclr ~= nil and T.findNamed("Mine_Over") ~= nil, "右键「我的 1」：弹出「覆盖成现在这套 / 清空」")
if mclr then T.press(mclr) R.run(0.8) end
local set1c = P.data.tree.sets and P.data.tree.sets[KEY] and P.data.tree.sets[KEY]["1"]
check(set1c == nil and st7.mine == nil and T.findNamed("Mine_Clear") == nil, "清空：存档里这一格没了、菜单收起")
-- 撤销：换了一对以后左栏有「撤销」，点了回到上一套（也存进存档）；Ctrl+Z 一样
local before7 = {}
for i = 1, #d.st do before7[i] = st7.load[i] end
local oc2 = nil
for k, g in ipairs(st7.cards) do if g.name == "outer" then oc2 = k end end
local cur2 = st7.load[st7.cards[oc2].st[1]]
local pick2 = nil
for _, w in ipairs(d.st[st7.cards[oc2].st[1]].opts) do if w ~= cur2 then pick2 = w end end
choose(oc2, pick2)
R.run(0.4)
local ub = T.findNamed("Undo")
check(not same(st7.load, before7) and ub ~= nil, "换了一对以后左栏有「撤销」")
if ub then T.press(ub) R.run(0.8) end
check(same(st7.load, before7) and same(P.data.tree.load[KEY].l, before7), "点「撤销」：回到上一套（也存进存档）")
choose(oc2, pick2)
R.run(0.4)
T.key(Enum.KeyCode.LeftControl, true)
T.key(Enum.KeyCode.Z, true)
T.key(Enum.KeyCode.Z, false)
T.key(Enum.KeyCode.LeftControl, false)
R.run(0.6)
check(same(st7.load, before7) and same(P.data.tree.load[KEY].l, before7), "Ctrl+Z 也能撤销")
-- 保存状态：服务器回了以后车名右边写「已保存」
local saveL = nil
for _, x in ipairs(me.PlayerGui:GetDescendants()) do if x.Name == "WsSave" then saveL = x:FindFirstChild("Label") end end
check(saveL ~= nil and saveL.Text == "已保存", "车名右边的保存状态：「" .. tostring(saveL and saveL.Text) .. "」（服务器回了才写）")
-- 返回：右键 / 3D 空白处点一下退一层；全景时空白处点一下不退出整备；Roblox 系统菜单开着时 Esc 不算
local function pickCard(k)
  local b = T.findNamed("Station_" .. k)
  if b then T.press(b) R.run(0.8) end
end
pickCard(1)
check(st7.sel == 1, "选中第 1 张")
T.mouse(true, 700, 300, Enum.UserInputType.MouseButton2)
T.mouse(false, 700, 300, Enum.UserInputType.MouseButton2)
R.run(0.6)
check(st7.sel == nil and C.workshopOpen(), "右键：退回全景（还在整备里）")
pickCard(1)
T.mouse(true, 700, 300)
T.mouse(false, 700, 300)
R.run(0.6)
check(st7.sel == nil and C.workshopOpen(), "3D 空白处点一下：退回全景")
T.mouse(true, 700, 300)
T.mouse(false, 700, 300)
R.run(0.6)
check(C.workshopOpen(), "全景时空白处点一下：不退出整备")
pickCard(1)
R.services.GuiService.MenuIsOpen = true
T.key(Enum.KeyCode.Escape, true)
T.key(Enum.KeyCode.Escape, false)
R.run(0.4)
check(st7.sel == 1, "Roblox 的系统菜单开着：Esc 让给系统菜单（不算返回）")
R.services.GuiService.MenuIsOpen = false
T.key(Enum.KeyCode.Escape, true)
T.key(Enum.KeyCode.Escape, false)
R.run(0.6)
check(st7.sel == nil and C.workshopOpen(), "菜单关着：Esc 退回全景")
-- 顶栏和页签重复的键（扳手、弹药、i）整备时收起，帮助、设置还在
check(T.findNamed("AmmoBtn") == nil and T.findNamed("ModsBtn") == nil and T.findNamed("InfoBtn") == nil and T.findNamed("HelpBtn") ~= nil and T.findNamed("SettingsBtn") ~= nil,
  "整备开着：顶栏的扳手、弹药、i 收起（和页签重复），帮助、设置还在")
-- 干扰弹没研究：点了去改装页；涂装页飞机先不开
local md7 = P.data.tree.mods and P.data.tree.mods[KEY]
if not (md7 and md7.done and md7.done.flares) then
  local fc = T.findNamed("FlareCard")
  if fc then T.press(fc) R.run(0.4) end
  check(C.modsGui.Visible and W7.tab == "mods", "干扰弹没研究：点干扰弹卡打开改装页")
  T.key(Enum.KeyCode.Escape, true)
  T.key(Enum.KeyCode.Escape, false)
  R.run(0.4)
  check(not C.modsGui.Visible and W7.tab == "arms" and C.workshopOpen(), "Esc：先关改装页，回到挂载页")
end
check(T.findNamed("Tab_skin") == nil and T.findNamed("Tab_arms") ~= nil and T.findNamed("Tab_info") ~= nil, "飞机没有涂装页签（现在只有地面车会上色），挂载 / 改装 / 乘员 / 资料四个")
-- WsKit 的拖动条（下一轮的弹药页用）：加减、每 5 一道刻度、别的弹占掉的那一截拖不进去
local Kit = C.wsKit
local holder = R.Instance.new("Frame")
local got, sl = nil, nil
R.as("client", function()
  sl = Kit.slider(holder, nil, { w = 172, min = 0, max = 40, step = 1, tick = 5, value = 10, onChange = function(v) got = v end })
end)
local plus = sl and sl.f:FindFirstChild("Plus")
if plus then T.press(plus) end
local nTick = sl and #sl.f:FindFirstChild("Ticks"):GetChildren() or 0
R.as("client", function() sl.setLock(35) end)
local afterLock = sl and sl.get()
local minus = sl and sl.f:FindFirstChild("Minus")
if minus then T.press(minus) end
check(got == 4 and afterLock == 5 and nTick == 9 and sl.f:FindFirstChild("Count").Text == "4",
  string.format("拖动条：10 → 加一 11 → 别的弹占掉 35 发只剩 5 → 减一 4（刻度 %d 道）", nTick))
-- 截图：uidump 写得出整备这一屏（tools/mock/loadshots.lua 用的同一个）；选着一个挂点（武器卡那时才有）
pickCard(1)
local dumpUI = dofile(MOCK_DIR .. "/uidump.lua")
local tmp = os.tmpname()
local items7 = dumpUI(T, me, tmp, true)
local has = {}
for _, it7 in ipairs(items7) do has[it7.name] = true end
local fh = io.open(tmp, "r")
local size7 = fh and #fh:read("a") or 0
if fh then fh:close() end
os.remove(tmp)
check(has.WsLeft and has.WsRight and has.WsBottom and has.Station_1 and has.Opt_none and has.Cmp_vAB and size7 > 1000, "截图：整备这一屏写得出来（" .. size7 .. " 字节）")
-- Esc 两下：回机库，原样还原
T.key(Enum.KeyCode.Escape, true)
T.key(Enum.KeyCode.Escape, false)
R.run(0.4)
T.key(Enum.KeyCode.Escape, true)
T.key(Enum.KeyCode.Escape, false)
R.run(1.2)
local H7 = C.hangarParts
goB = T.findNamed("HangarGo")
check(not C.workshopOpen() and H7.wsOn == nil and H7.row.Visible and H7.mid.Visible and goB ~= nil and goB.Parent.Name == goParent0,
  "Esc 回机库：阵容卡、乘员、主按钮都回到原来的地方（" .. tostring(goB and goB.Parent.Name) .. "）")
check(C.hangarShown() == KEY .. "|" .. sig(P.data.tree.load[KEY].l) and C.hangarStage.highlightsUsed() == 0, "机库里摆的是存的那套，借的高亮都还了")
check(T.findNamed("AmmoBtn") ~= nil and T.findNamed("ModsBtn") ~= nil and T.findNamed("InfoBtn") ~= nil and C.hangarAirCached() == 0,
  "回机库：顶栏的键都回来了，收着的那几套模型清掉了")

check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | ", 1, math.min(#R.errors, 3)))
T.summary()
