-- 卡顿排查（模拟器）：python3 tools/mock/run.py tools/mock/perf.lua [秒数，默认 10] [lines]
--   用户：游戏非常卡顿。模拟器是 Lua 5.4 加一层模拟的 Roblox，CPU 时间不准（射线逐个零件试，比真的慢几百倍），
--   所以主要数次数：真 Roblox 里贵的是场景里的零件 / 灯 / 粒子有多少（渲染），每帧新建、删、改属性多少次，
--   射线几条多长，远程事件每秒发多少数据（网络）。先步兵站着、再开坦克往前开（旁边一辆敌方坦克），各跑一段。
--   加 lines 参数：再按行采样一遍开坦克时最热的游戏代码行（只看相对大小）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local secs = tonumber(TEST_ARGS:match("%d+") or "") or 10
local wantLines = TEST_ARGS:find("lines", 1, true) ~= nil
local cpu = os.clock

-- map=snow / map=city：量线上那两张图（默认照旧沙海，common.lua）
T.mapName = TEST_ARGS:match("map=(%w+)")
local G = T.boot()
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 7201, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = "def"
me.Team = G.TEAM.def
me.Neutral = false
me:SetAttribute("Side", "def")
G.pushOne(P)
R.run(1)
local C = T.C
-- 出生（11-27）：营地出生点改名成 base 了（Round.lua），主菜单要先关掉——原来的 deploy rifle camp 出不了生，开坦克那段跑不到
T.leaveMenu()
T.actAs(me, "deploy", "rifle", "base")
T.runUntil(function() return P.alive and me.Character ~= nil end, 15)
R.run(1)
check(P.alive, "守方在营地出生")

-- 场景清单：渲染的负担
local function inventory(title)
  local cls, top, n = {}, {}, 0
  local shadow, trans, big = 0, 0, 0
  local function walk(o, topName)
    for _, c in ipairs(o._kids) do
      n = n + 1
      local k = c._cls
      cls[k] = (cls[k] or 0) + 1
      top[topName or c._p.Name] = (top[topName or c._p.Name] or 0) + 1
      if R.base.IsA(c, "BasePart") then
        if c._p.CastShadow ~= false then shadow = shadow + 1 end
        if (c._p.Transparency or 0) > 0 and (c._p.Transparency or 0) < 1 then trans = trans + 1 end
      end
      walk(c, topName or c._p.Name)
    end
  end
  walk(R.workspace)
  print(string.format("  —— %s：workspace 里 %d 个实例；投影子的零件 %d，半透明零件 %d", title, n, shadow, trans))
  local rows = {}
  for k, v in pairs(cls) do rows[#rows + 1] = { k = k, v = v } end
  table.sort(rows, function(a, b) return a.v > b.v end)
  local line = {}
  for i = 1, math.min(18, #rows) do line[#line + 1] = rows[i].k .. " " .. rows[i].v end
  print("    按类：" .. table.concat(line, "，"))
  rows = {}
  for k, v in pairs(top) do rows[#rows + 1] = { k = k, v = v } end
  table.sort(rows, function(a, b) return a.v > b.v end)
  line = {}
  for i = 1, math.min(16, #rows) do line[#line + 1] = rows[i].k .. " " .. rows[i].v end
  print("    按顶层：" .. table.concat(line, "，"))
  local pg = me:FindFirstChildOfClass("PlayerGui")
  if pg then
    local g, vis = 0, 0
    local function gw(o, shown)
      for _, c in ipairs(o._kids) do
        g = g + 1
        local s2 = shown
        if c._cls == "ScreenGui" then s2 = c._p.Enabled ~= false
        elseif R.base.IsA(c, "GuiObject") then s2 = shown and c._p.Visible ~= false end
        if s2 and R.base.IsA(c, "GuiObject") then vis = vis + 1 end
        gw(c, s2)
      end
    end
    gw(pg, true)
    print(string.format("    界面：PlayerGui 里 %d 个实例，显示着的界面元素 %d 个", g, vis))
  end
end

-- 客户端的 G.stepXxx 包一层计时（init.client.lua 每帧按名字调）
local stepT = {}
for k, v in pairs(C) do
  if type(v) == "function" and k:match("^step") then
    C[k] = function(...)
      local t0 = cpu()
      local a, b, c = v(...)
      stepT[k] = (stepT[k] or 0) + (cpu() - t0)
      return a, b, c
    end
  end
end

local function report(title, wall, n, ops)
  print(string.format("  —— %s：%d 帧，模拟器 CPU %.1f 秒（每帧 %.2f 毫秒，含模拟器开销）", title, n, wall, wall / n * 1000))
  local rows = {}
  for k, v in pairs(R.prof) do rows[#rows + 1] = { k = "连接 " .. k, v = v } end
  for k, v in pairs(stepT) do rows[#rows + 1] = { k = "G." .. k, v = v } end
  table.sort(rows, function(a, b) return a.v > b.v end)
  for i = 1, math.min(12, #rows) do print(string.format("    %6.2f 毫秒/帧  %s", rows[i].v / n * 1000, rows[i].k)) end
  -- 操作次数：按（哪边，什么操作）合计，再按行
  local byKind, byLine = {}, {}
  for k, v in pairs(ops) do
    local sd, kind, where = k:match("^(%S+)\t(.-)\t(.*)$")
    local kk = sd .. " " .. kind
    byKind[kk] = (byKind[kk] or 0) + v
    local kl = sd .. " " .. kind .. "  @" .. where
    byLine[kl] = (byLine[kl] or 0) + v
  end
  local function top(map, m, label, skip)
    local rr = {}
    for k, v in pairs(map) do if not (skip and k:find(skip)) then rr[#rr + 1] = { k = k, v = v } end end
    table.sort(rr, function(a, b) return a.v > b.v end)
    print("    " .. label)
    for i = 1, math.min(m, #rr) do print(string.format("    %9.1f /帧  %s", rr[i].v / n, rr[i].k)) end
  end
  top(byKind, 26, "每帧操作（哪边 操作 类）：", "raylen")
  top(byLine, 30, "每帧操作最多的代码行：", "raylen")
  -- 网络：每秒字节数
  local net = {}
  for k, v in pairs(byKind) do
    if k:find("bytes") then net[#net + 1] = { k = k, v = v } end
  end
  table.sort(net, function(a, b) return a.v > b.v end)
  local tot = 0
  for _, r in ipairs(net) do tot = tot + r.v end
  print(string.format("    远程事件数据量 %.1f KB/秒：", tot / (n / 30) / 1024))
  for i = 1, math.min(8, #net) do print(string.format("    %8.2f KB/秒  %s", net[i].v / (n / 30) / 1024, net[i].k)) end
end
local function measure(title, sec, f)
  R.prof, stepT, R.ops = {}, {}, {}
  local n = math.floor(sec * 30)
  local t0 = cpu()
  for i = 1, n do
    if f then f(i) end
    R.step(1 / 30)
  end
  local ops = R.ops
  R.ops = nil
  report(title, cpu() - t0, n, ops)
  R.prof = nil
end

inventory("开局")
print("① 步兵站在营地")
measure("步兵", secs * 0.6)

print("② 开坦克往前开，旁边一辆敌方坦克")
local tid = G.Config.Vehicles.def.tank[1]
local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))
local d = VD.get(tid)
local hrp = me.Character.HumanoidRootPart
local p = hrp.Position
local x, z = p.X + 30, p.Z + 30
local e = G.newVehicle("def", tid, G.vehBaseAt(d, x, z, V3(0, 0, 1)))
G.newVehicle("atk", G.Config.Vehicles.atk.tank[1], G.vehBaseAt(VD.get(G.Config.Vehicles.atk.tank[1]), x + 40, z + 170, V3(0, 0, -1)))
R.run(0.5)
me.Character:PivotTo(CF(x + 6, G.Map.ground(x + 6, z) + 3.5, z))
R.run(0.3)
T.act("enterVeh", e.id)
R.run(2)
check(C.drive ~= nil, "坐进坦克 " .. tid)
T.key(Enum.KeyCode.W, true)
measure("开坦克", secs)
inventory("开了一会坦克")

if wantLines then
  -- 按行采样：每 997 条虚拟机指令看一眼在哪（只记游戏代码 src/ 里的那一层）
  print("③ 开坦克：按行采样，最热的游戏代码行")
  local hits = {}
  R.sampler = function()
    for lv = 2, 14 do
      local info = debug.getinfo(lv, "Sl")
      if not info then break end
      local src = info.source or ""
      if src:find("/src/", 1, true) then
        local k = (src:match("([^/]+)$") or src) .. ":" .. tostring(info.currentline)
        hits[k] = (hits[k] or 0) + 1
        return
      end
    end
  end
  for _ = 1, math.floor(secs * 10) do R.step(1 / 30) end
  R.sampler = nil
  local rows, tot = {}, 0
  for k, v in pairs(hits) do rows[#rows + 1] = { k = k, v = v } tot = tot + v end
  table.sort(rows, function(a, b) return a.v > b.v end)
  for i = 1, math.min(25, #rows) do print(string.format("    %5.1f%%  %s", rows[i].v / math.max(tot, 1) * 100, rows[i].k)) end
end
T.key(Enum.KeyCode.W, false)
T.summary()
