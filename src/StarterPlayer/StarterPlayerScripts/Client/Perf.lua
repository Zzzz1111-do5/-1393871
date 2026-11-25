-- 全面大战场（客户端）——性能面板（F7）与自动画质多管的几样（用户 11-19：游戏非常卡顿）
--   F7 开关（开着挂炸弹的飞机时 F7 是轰炸瞄准镜，用 Ctrl + F7）：左边一块小面板，每半秒刷新——帧率（平均、这半秒里最慢的一帧）、自动画质档位 G.perfK、
--     客户端每个模块每帧用掉多少毫秒（init.client.lua 的逐帧步骤、各模块自己用 G.frameConn 连的逐帧回调）、
--     引擎的统计（Stats：实例、零件、会动的零件、物理每步、内存、网络收发，读得到的话还有渲染的 CPU / GPU 时间）、
--     载具这一帧摆了多少零件、地图光晕亮着几个——截图发过来就知道卡在哪
--   地形草叶一直关着（用户 11-21：直接把草删掉；原来自动画质按 G.perfK 开关它）；夜视的模糊在 Night.lua 按 perfK 关
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

local Perf = {}

function Perf.init(G)
  local me = Players.LocalPlayer
  local okS, Stats = pcall(function() return game:GetService("Stats") end)
  if not okS then Stats = nil end
  local zh = G.lang == "zh"
  local function L(a, b) return zh and a or b end
  -- 模块名 → 面板上的名字
  local NAMES = {
    drive = L("开车", "drive"), fly = L("飞机", "fly"), sail = L("开船", "sail"), view = L("实体画面", "view"), play = L("步兵操作", "play"),
    fx = L("特效", "fx"), forts = L("工事", "forts"), gunner = L("炮位", "gunner"), ui = L("界面", "ui"), map = L("地图", "map"),
    operation = L("战役", "operation"), hud = L("战场界面", "hud"), scenery = L("景物", "scenery"), chute = L("伞", "chute"),
    tablet = L("平板", "tablet"), tacpad = L("战术平板", "tacpad"), menu = L("菜单", "menu"), coach = L("指导", "coach"),
    daynight = L("昼夜", "daynight"), airfx = L("机动云雾", "airfx"), mslcam = L("导弹小窗", "mslcam"),
  }

  local gui = Instance.new("ScreenGui")
  gui.Name = "PerfPanel"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 60
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")
  local box = Instance.new("TextLabel")
  box.Name = "Stats"
  box.Size = UDim2.fromOffset(360, 300)
  box.Position = UDim2.fromOffset(12, 140)
  box.BackgroundColor3 = Color3.new(0, 0, 0)
  box.BackgroundTransparency = 0.35
  box.BorderSizePixel = 0
  box.Font = Enum.Font.RobotoMono
  box.TextSize = 13
  box.TextColor3 = Color3.fromRGB(224, 232, 236)
  box.TextXAlignment = Enum.TextXAlignment.Left
  box.TextYAlignment = Enum.TextYAlignment.Top
  box.TextWrapped = true
  box.Text = ""
  box.Parent = gui
  local pad = Instance.new("UIPadding")
  pad.PaddingLeft, pad.PaddingTop, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 6), UDim.new(0, 8)
  pad.Parent = box
  G.perfPanel = gui   -- 测试用

  UIS.InputBegan:Connect(function(input, gp)
    -- 开着挂炸弹的飞机：F7 是战雷的轰炸瞄准镜（Fly.lua），这时 Ctrl + F7 开性能面板
    if input.KeyCode == Enum.KeyCode.F7 and not UIS:GetFocusedTextBox() and not (G.flyWantsF7 and G.flyWantsF7()) then
      gui.Enabled = not gui.Enabled
    end
  end)

  local function stat(k)
    if not Stats then return nil end
    local ok, v = pcall(function() return Stats[k] end)
    return (ok and type(v) == "number") and v or nil
  end
  local function f1(x) return string.format("%.1f", x) end

  -- 地形草叶（用户 11-21：坦克还是半截卡在下面，「你直接把草删掉好了」）：原来这里每半秒设一遍 Terrain.Decoration = false——
  --   Roblox 不许脚本改它（一改就报错，被 pcall 吞了），一直没生效；现在服务器写地形不用 Grass 材质（World.lua 的 writeChunk），草叶长不出来。
  --   原来自动画质卡了关草、流畅了再开也一起去掉了（同样改不了）

  local frames, acc, worst, puts0 = 0, 0, 0, 0
  RunService.RenderStepped:Connect(function(dt)
    frames += 1
    acc += dt or 0
    if (dt or 0) > worst then worst = dt end
    if acc < 0.5 then return end
    local T, n, a, w = G.perfT or {}, frames, acc, worst
    local MX = G.perfMax or {}
    G.perfT = {}
    G.perfMax = {}
    frames, acc, worst = 0, 0, 0
    local puts = G.viewPuts or 0
    local dPuts = puts - puts0
    puts0 = puts
    if not gui.Enabled then return end
    local lines = {}
    lines[#lines + 1] = string.format(L("帧率 %d · 最慢一帧 %d 毫秒 · 自动画质 %.2f", "FPS %d · worst %d ms · quality %.2f"),
      math.floor(n / a + 0.5), math.floor(w * 1000 + 0.5), G.perfK or 1)
    -- 脚本：每帧毫秒，大的在前
    local rows, tot = {}, 0
    for k, v in pairs(T) do
      rows[#rows + 1] = { k = NAMES[k] or k, v = v / n * 1000 }
      tot += v / n * 1000
    end
    table.sort(rows, function(x, y) return x.v > y.v end)
    lines[#lines + 1] = string.format(L("脚本 %s 毫秒/帧：", "scripts %s ms/frame:"), f1(tot))
    local part = {}
    for i = 1, math.min(9, #rows) do
      part[#part + 1] = rows[i].k .. " " .. f1(rows[i].v)
      if #part == 3 then
        lines[#lines + 1] = "  " .. table.concat(part, " · ")
        part = {}
      end
    end
    if #part > 0 then lines[#lines + 1] = "  " .. table.concat(part, " · ") end
    -- 尖峰：这半秒里单次最长的三个（一阵一阵卡的时候看这一行；用户 11-25）
    local spikes = {}
    for k, v in pairs(MX) do spikes[#spikes + 1] = { k = NAMES[k] or k, v = v * 1000 } end
    table.sort(spikes, function(x, y) return x.v > y.v end)
    if spikes[1] and spikes[1].v >= 2 then
      local sp = {}
      for i = 1, math.min(3, #spikes) do sp[#sp + 1] = spikes[i].k .. " " .. f1(spikes[i].v) end
      lines[#lines + 1] = L("单次最长 ", "spikes ") .. table.concat(sp, " · ") .. L(" 毫秒", " ms")
    end
    -- 引擎
    local inst, prim, mov, cont = stat("InstanceCount"), stat("PrimitivesCount"), stat("MovingPrimitivesCount"), stat("ContactsCount")
    if inst then
      lines[#lines + 1] = string.format(L("实例 %d · 零件 %d · 会动的 %d · 接触 %d", "instances %d · parts %d · moving %d · contacts %d"),
        inst, prim or 0, mov or 0, cont or 0)
    end
    local phys, hb = stat("PhysicsStepTimeMs"), stat("HeartbeatTimeMs")
    local mem = nil
    if Stats then
      local ok, v = pcall(function() return Stats:GetTotalMemoryUsageMb() end)
      if ok then mem = v end
    end
    if phys or mem then
      lines[#lines + 1] = string.format(L("物理 %s 毫秒 · 心跳 %s 毫秒 · 内存 %d MB", "physics %s ms · heartbeat %s ms · memory %d MB"),
        f1(phys or 0), f1(hb or 0), math.floor(mem or 0))
    end
    local rx, tx = stat("DataReceiveKbps"), stat("DataSendKbps")
    if rx then lines[#lines + 1] = string.format(L("网络 收 %s KB/s · 发 %s KB/s", "network in %s KB/s · out %s KB/s"), f1(rx), f1(tx or 0)) end
    local rc, rg = stat("RenderCPUFrameTime"), stat("RenderGPUFrameTime")
    if rc or rg then
      local function ms(x) return f1((x or 0) < 1 and (x or 0) * 1000 or (x or 0)) end
      lines[#lines + 1] = string.format(L("渲染 CPU %s 毫秒 · GPU %s 毫秒", "render CPU %s ms · GPU %s ms"), ms(rc), ms(rg))
    end
    -- 本游戏自己的
    lines[#lines + 1] = string.format(L("载具摆零件 %d/帧 · 光晕亮着 %d/%d", "vehicle parts moved %d/frame · glows %d/%d"),
      math.floor(dPuts / n + 0.5), G.glowLit or 0, G.glowCount and G.glowCount() or 0)
    lines[#lines + 1] = L("F7 关掉这个面板", "F7 hides this panel")
    box.Text = table.concat(lines, "\n")
    box.Size = UDim2.fromOffset(360, 18 + #lines * 16)
  end)
end

return Perf
