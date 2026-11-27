-- 整备（用户 11-27「整个给载具配置武器的系统 做的很粗糙 我需要非常艺术经验的效果 参考战雷」）：python3 tools/mock/run.py tools/mock/workshop.lua
--   第一段（止血 + 地基）。真游戏开着匹配：没进局的人在「匹配中」的机库里（T.matchMode，同 tools/mock/wttestair.lua），像玩家一样：
--   ① 科技树机库里飞机能配挂载：阵容里选中歼-10C → 顶栏弹药键（不再淡掉、提示写「挂载」）→ 挂载编辑器按存的那套开（没存过是第一套预设）→
--      换一套预设（对地）、点一个挂点换一种弹（左右一对一起换）、内油 75% → 保存：服务器存档 tree.load 记着（照哪套改的、每个挂点、内油），
--      客户端的 Tree 跟着；机库里摆的飞机换成存的那套（同一架只换模型、镜头不动）；资料卡写「当前挂载」、存的武器、外挂重量
--   ② 地基：HangarStage.focus（缓动飞过去、拖动打断）、停机坪俯仰能压到负的、highlight（最多 4 个，还了能再借）、toScreen；Theme.T / tween
--   ③ 试驾：飞机实际挂的（服务器 e.load、模型上的 Load 属性、客户端开的 st.load）、内油和存的一样；
--      开飞机用的重量 / 阻力（Fly.lua）= FlightModel.loadout，也等于原来 Fly.lua 的算法（照抄一份在下面比）
--   ④ 出击（点开战 → 局内选车 → 先出地面车 → 回机库 → 出飞机）：停在机场的飞机挂的、内油和存的一样
--   ⑤ 服务器校验：非法武器清成空、内油夹到 0.25～1、不认得的预设不记、地面车 / 不认得的键不收；读档也照这样清
--   ⑥ FlightModel.loadout / perf：挂满比空挂重、阻力大、极速低、推重比小、转弯和爬升差；弹舱里的不算阻力；vTop / card 吃阻力增量
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

print("① 机库里给歼-10C 配挂载：弹药键 → 换预设、改一个挂点、内油 → 保存进存档")
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
if ab then T.press(ab) R.run(0.6) end
local HS = C.hangarState and C.hangarState()
check(HS ~= nil and HS.d.id == d.id, "打开了挂载编辑器（" .. tostring(HS and HS.d.id) .. "）")
check(HS ~= nil and same(HS.load, AD.presetLoad(d)) and HS.presetKey == d.presets[1].key and math.abs(HS.fuel - 1) < 1e-9,
  "按存的打开：没存过是第一套预设（" .. tostring(HS and HS.presetKey) .. "）、满内油")
check(C.stageFree ~= nil and not C.stageFree(T.V3(640, 360, 0)), "编辑器开着：在上面按住拖动不转后面机库里的飞机")
local pb = T.findNamed("Preset_ag")
check(pb ~= nil and T.findNamed("Preset_" .. d.presets[1].key) ~= nil, "上面一排是这架飞机的预设方案")
if pb then T.press(pb) R.run(0.3) end
local want = AD.presetLoad(d, "ag")
check(HS and same(HS.load, want) and HS.presetKey == "ag", "点「对地」：换成那一套")
-- 点一个看得见的「mid」挂点（左右对称：一对只画离镜头近的那个圈），换成霹雳-12
local idx, mate = nil, nil
for i, s in ipairs(d.st) do
  if s.name == "mid" then
    local b = T.findNamed("Spot" .. i)
    if b and not idx then idx = i elseif not mate then mate = i end
  end
end
if idx and not mate then for i, s in ipairs(d.st) do if s.name == "mid" and i ~= idx then mate = i end end end
check(idx ~= nil and mate ~= nil, "找到机翼中间那一对挂点（看得见的是 " .. tostring(idx) .. "）")
local NEW = "pl12"
check(idx ~= nil and want[idx] ~= NEW and tfind(d.st[idx].opts, NEW) ~= nil, "这个挂点能挂霹雳-12、现在挂的不是（" .. tostring(idx and want[idx]) .. "）")
if idx then T.press(T.findNamed("Spot" .. idx)) R.run(0.6) end
check(HS and HS.sel == idx, "选中了挂点 " .. tostring(HS and HS.sel))
local opt = T.findNamed("Opt_" .. NEW)
check(opt ~= nil and T.findNamed("Opt_none") ~= nil, "列表里有霹雳-12、最后一项是「不挂」")
if opt then T.press(opt) R.run(0.3) end
if idx then want[idx] = NEW end
if mate then want[mate] = NEW end
check(HS and same(HS.load, want), "左右一对一起换成霹雳-12：" .. sig(HS and HS.load))
local pb2 = T.findNamed("Preset_ag")
check(pb2 ~= nil and pb2.Text:find("已改") ~= nil, "预设那一块写「（已改）」（" .. tostring(pb2 and pb2.Text) .. "）")
local back = T.findNamed("HangarBack")
if back then T.press(back) R.run(0.3) end   -- 先退回全景：内油那一栏才出来
local f75 = T.findNamed("Fuel75")
check(f75 ~= nil, "内油能选 75%")
if f75 then T.press(f75) R.run(0.2) end
-- 保存之前把机库镜头挪到一个特写：存了新挂载以后（同一架换模型）镜头不该跳回全景
R.as("client", function() S.focus({ dist = 70, t = 0 }) end)
R.run(0.5)
local save = T.findNamed("HangarSave")
check(save ~= nil and save.Text == "保存", "右下是「保存」（" .. tostring(save and save.Text) .. "）")
if save then T.press(save) end
R.run(1.5)
local sv = P.data.tree.load and P.data.tree.load[KEY]
check(sv ~= nil and sv.p == "ag" and same(sv.l, want) and sv.f == 0.75,
  string.format("服务器存档记着：照「%s」改的、%s、内油 %s", tostring(sv and sv.p), sig(sv and sv.l), tostring(sv and sv.f)))
local ct = C.treeState().load and C.treeState().load[KEY]
check(ct ~= nil and same(ct.l, want) and ct.f == 0.75 and ct.p == "ag", "客户端的 Tree 跟着")
check(not (C.hangarOpen and C.hangarOpen()), "编辑器关了")
check(C.stageFree(T.V3(640, 360, 0)), "关了以后：点空白处照常转车")
check(#T.texts("挂载已保存") > 0, "提示「挂载已保存」")
check(C.hangarShown() == KEY .. "|" .. sig(want), "机库里摆的飞机换成存的那套（" .. tostring(C.hangarShown()) .. "）")
check(S.model() ~= nil and math.abs(S.viewState().dist - 70) < 1e-6, string.format("同一架只换模型：镜头不跳回全景（%.1f）", S.viewState().dist))
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
T.runUntil(function() return C.S and C.S.pick == true and T.findNamed("Line_" .. starter.key) ~= nil end, 10)
local gcard = T.findNamed("Line_" .. starter.key)
if gcard then T.press(gcard) R.run(0.3) end
local go = T.findNamed("HangarGo")
if go then T.press(go) end
T.runUntil(function() return P.alive and P.vehicle ~= nil end, 30)
local eg = P.vehicle
check(eg ~= nil and not eg.air and eg.treeKey == starter.key, "先出了地面车（" .. tostring(eg and eg.treeKey) .. "）")
R.run(1)
T.remoteAs(me, "Drive", { op = "exit", hangar = true })
T.runUntil(function() return not P.alive end, 15)
T.runUntil(function() return T.findNamed("HangarGo") ~= nil end, 10)
G.wtState(P).sp = 5000   -- 打出了分、攒够了出飞机的 SP（测试直接给）
G.pushOne(P)
R.run(1.5)
local acard = T.findNamed("Line_" .. KEY)
check(acard ~= nil and acard:GetAttribute("Locked") ~= true, "出过地面车：飞机卡能选了")
if acard then T.press(acard) R.run(0.5) end
go = T.findNamed("HangarGo")
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

check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | ", 1, math.min(#R.errors, 3)))
T.summary()
