-- 飞机的挂载表（战雷的「挂载」窗口，LoadoutWin.lua）：python3 tools/mock/run.py tools/mock/loadoutwin.lua
--   用户 11-28（战雷截图）：「飞机选挂载我还是没找到位置 你给我做成这样」
--   ① 机库里选中歼-10C：选中框里有「挂载」键（选地面车时看不见）；点开 = 挂载表窗口，标题「挂载 - 歼-10C」
--   ② 表：分组「对空中目标」「对地面目标」「自定义武器」；一套预设一行、一列一个挂点（左翼尖 → 右翼尖）；
--      格子里写型号（挂几枚写 ×N）；存的那一套那一行亮
--   ③ 右栏：这一套的清单（型号 × 枚数）+ 性能参数变化（比空挂：外挂重量多、最大速度少）
--   ④ 点对地那一套：即时存（客户端 tree.load、服务器存档），亮的换成那一行，右栏跟着换
--   ⑤ 空的「编组方案 #1」点一下：把现在这一套存成方案（服务器存档 tree.sets）；换回空战那套以后点 #1 又换回对地那套
--   ⑥ Esc 关窗；「创建 / 细调」打开整备的挂载页
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
G.Config.Match.wait = 600   -- 不让它开局（只在机库里看）
T.runUntil(function() return G.worldReady end, 900)
local RS = R.services.ReplicatedStorage
local TT = R.require(RS:FindFirstChild("TechTree"))
local AD = R.require(RS:FindFirstChild("AirDefs"))
local me = T.join("P1", 9573, true)
T.runUntil(function() return G.round ~= nil end, 30)
local P = G.P[me]
local C = T.C
T.leaveMenu()
T.runUntil(function() return G.rangeReady == true and T.findNamed("HangarGo") ~= nil end, 120, 1 / 10)
R.run(1)

local KEY = "cn_j10c"
local it = TT.byKey[KEY]
local d = AD.get(it.play)
local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for i = 1, #(d.st or {}) do if (a[i] or false) ~= (b[i] or false) then return false end end
  return true
end
local function airOnly(load)
  for _, wid in ipairs(load or {}) do
    local w = wid and AD.W[wid]
    if w and w.kind ~= "aam" and w.kind ~= "tank" then return false end
  end
  return true
end
local gui = C.loadoutGui
local function lit(r) return r ~= nil and r:FindFirstChildOfClass("UIStroke") ~= nil end
local function litRows()
  local out = {}
  for _, r in ipairs(gui:FindFirstChild("Table", true):GetChildren()) do
    if r:IsA("TextButton") and lit(r) then out[#out + 1] = r.Name end
  end
  return out
end
local function perf(label)
  local t = gui:FindFirstChild("Perf_" .. label, true)
  return t and t.Text or nil
end

print("① 机库里选中歼-10C：选中框里有「挂载」键，点开挂载表")
T.act("redeem", "Zhengyongshuo")   -- 全部解锁
R.run(1)
local starter = TT.starter("cn", "ground")
T.act("treeLineup", "cn", { starter.key, KEY })
R.run(1)
local card0 = T.findNamed("Line_" .. starter.key)
if card0 then T.press(card0) R.run(0.5) end
local lb = me.PlayerGui:FindFirstChild("LoadoutBtn", true)   -- 看不见时 T.findNamed 找不到：按名字直接找
check(lb ~= nil and not T.visible(lb), "选中地面车：「挂载」键收着")
local card = T.findNamed("Line_" .. KEY)
if card then T.press(card) R.run(0.5) end
check(lb ~= nil and T.visible(lb), "选中歼-10C：「挂载」键出来了")
check(gui ~= nil and not gui.Enabled, "挂载表还没开")
if lb then T.press(lb) R.run(0.5) end
check(gui ~= nil and gui.Enabled and C.loadoutOpen(), "点「挂载」开了挂载表")
local title = gui and gui:FindFirstChild("Title", true)
check(title ~= nil and title.Text:find("挂载", 1, true) ~= nil and title.Text:find(it.name, 1, true) ~= nil, "标题「挂载 - 机名」（" .. tostring(title and title.Text) .. "）")

print("② 表：三组、一套一行、一列一个挂点，存的那套亮")
local groups = {}
for _, x in ipairs(gui:FindFirstChild("Table", true):GetChildren()) do
  if x.Name == "Group" then groups[#groups + 1] = x.Text end
end
local gs = table.concat(groups, "/")
check(gs:find("对空中目标", 1, true) and gs:find("对地面目标", 1, true) and gs:find("自定义武器", 1, true), "分组：" .. gs)
local nRows, cellsOk, gnd, air = 0, true, nil, nil
for _, pr in ipairs(d.presets) do
  local r = gui:FindFirstChild("Preset_" .. pr.key, true)
  if r then
    nRows = nRows + 1
    local nc = 0
    for _, c in ipairs(r:GetChildren()) do if c.Name:match("^Cell_%d+$") then nc = nc + 1 end end
    if nc ~= #d.st then cellsOk = false end
    local load = AD.presetLoad(d, pr.key)
    if airOnly(load) then air = air or pr.key else gnd = gnd or pr.key end
  end
end
check(nRows == #d.presets, string.format("一套预设一行（%d / %d）", nRows, #d.presets))
check(cellsOk, "每行 " .. #d.st .. " 格（一个挂点一格）")
check(air ~= nil and gnd ~= nil, "有对空的（" .. tostring(air) .. "）也有对地的（" .. tostring(gnd) .. "）")
local first = d.presets[1].key
local L0 = litRows()
check(#L0 == 1 and L0[1] == "Preset_" .. first, "没存过：第一套那一行亮（" .. table.concat(L0, ",") .. "）")
local r1 = gui:FindFirstChild("Preset_" .. first, true)
local labs = {}
for _, c in ipairs(r1 and r1:GetDescendants() or {}) do if c.Name == "Lab" then labs[#labs + 1] = c.Text end end
check(#labs > 0, "格子里写型号：" .. table.concat(labs, " "))
local wl = {}
for i, wid in ipairs(AD.presetLoad(d, first)) do if wid and AD.count(d.st[i], wid) > 1 then wl[#wl + 1] = wid end end
local multi = false
for _, s in ipairs(labs) do if s:find("×", 1, true) then multi = true end end
check((#wl == 0) or multi, "一个挂点挂几枚的写 ×N")
local cust = 0
for i = 1, 3 do if gui:FindFirstChild("Custom_" .. i, true) then cust = cust + 1 end end
check(cust == 3, "自定义三行（编组方案 #1～#3）")

print("③ 右栏：清单 + 性能参数变化")
local chosen = gui:FindFirstChild("Chosen", true)
check(chosen ~= nil and chosen.Text:find("×", 1, true) ~= nil, "清单写型号 × 枚数（" .. tostring(chosen and chosen.Text:gsub("\n", " / ")) .. "）")
local pw, pv, pc, pt = perf("外挂重量"), perf("最大速度"), perf("爬升率"), perf("盘旋一圈")
check(pw ~= nil and pw:sub(1, 1) == "+", "外挂重量变多（" .. tostring(pw) .. "）")
check(pv ~= nil and pv:sub(1, 1) == "-", "最大速度变少（" .. tostring(pv) .. "）")
check(pc ~= nil and pt ~= nil, "爬升率、盘旋一圈也写了（" .. tostring(pc) .. "；" .. tostring(pt) .. "）")

if not (gnd and air) then T.summary() return end
print("④ 点对地那一套：即时存、亮的那一行换过去")
local chosen0 = chosen and chosen.Text
local rg = gui:FindFirstChild("Preset_" .. gnd, true)
if rg then T.press(rg) R.run(1) end
local tr = C.treeState()
local cl = tr.load and tr.load[KEY]
check(cl ~= nil and cl.p == gnd and same(cl.l, AD.presetLoad(d, gnd)), "客户端存了对地那套（" .. tostring(cl and cl.p) .. "）")
local sv = P.data.tree.load and P.data.tree.load[KEY]
check(sv ~= nil and sv.p == gnd and same(sv.l, AD.presetLoad(d, gnd)), "服务器存档也是（" .. tostring(sv and sv.p) .. "）")
local L1 = litRows()
check(#L1 == 1 and L1[1] == "Preset_" .. gnd, "亮的换成对地那一行（" .. table.concat(L1, ",") .. "）")
chosen = gui:FindFirstChild("Chosen", true)
check(chosen ~= nil and chosen.Text ~= chosen0, "右栏清单跟着换了")

print("⑤ 空的编组方案 #1：存成方案，换回去再点又回来")
local c1 = gui:FindFirstChild("Custom_1", true)
check(c1 ~= nil and c1:FindFirstChild("SaveHere") ~= nil, "#1 空着，写「点一下：把现在这一套存成这个方案」")
if c1 then T.press(c1) R.run(1) end
local ss = P.data.tree.sets and P.data.tree.sets[KEY] and P.data.tree.sets[KEY]["1"]
check(ss ~= nil and same(ss.l, AD.presetLoad(d, gnd)), "服务器存档 tree.sets 记着这一套")
c1 = gui:FindFirstChild("Custom_1", true)
check(c1 ~= nil and c1:FindFirstChild("SaveHere") == nil, "#1 不再是空的")
local ra = gui:FindFirstChild("Preset_" .. air, true)
if ra then T.press(ra) R.run(1) end
check(C.treeState().load[KEY].p == air, "换回对空那套")
c1 = gui:FindFirstChild("Custom_1", true)
if c1 then T.press(c1) R.run(1) end
local cl2 = C.treeState().load[KEY]
check(cl2 ~= nil and same(cl2.l, AD.presetLoad(d, gnd)), "点 #1：换成存的那套")
local L2 = litRows()
local hasC1 = false
for _, n in ipairs(L2) do if n == "Custom_1" then hasC1 = true end end
check(hasC1, "#1 那一行亮（" .. table.concat(L2, ",") .. "）")

print("⑥ Esc 关；「创建 / 细调」开整备")
T.tap(Enum.KeyCode.Escape)
R.run(0.3)
check(not gui.Enabled, "Esc 关了挂载表")
if lb then T.press(lb) R.run(0.5) end
check(gui.Enabled, "再开一次")
local fine = gui:FindFirstChild("Fine", true)
if fine then T.press(fine) R.run(1.2) end
local W, st = C.workshopState()
check(not gui.Enabled and W.on and st ~= nil and st.key == KEY, "「创建 / 细调」：挂载表关了、整备的挂载页开了（" .. tostring(st and st.key) .. "）")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | ", 1, math.min(#R.errors, 3)))
T.summary()
