-- 模拟测试共用：开服、进服、按键、鼠标、点按钮、检查
--   local T = dofile(MOCK_DIR .. "/common.lua")；T.boot() 之后 T.R 是模拟器、T.G 是服务器的共用上下文、T.join() 进一个玩家（跑客户端）
local T = { fails = 0 }
local R = dofile(MOCK_DIR .. "/rbx.lua")
T.R = R
T.V3, T.CF, T.Enum = R.Vector3.new, R.CFrame.new, R.Enum
local Enum = R.Enum
local UIS = R.services.UserInputService

function T.check(ok, what)
  print((ok and "  通过 " or "  不对 ") .. what)
  if not ok then T.fails = T.fails + 1 end
  return ok
end

function T.boot()
  T.scripts = dofile(MOCK_DIR .. "/load.lua")(R, SRC_DIR)
  R.verbose = TEST_ARGS:match("%f[%w]v%f[%W]") ~= nil
  -- 地图（11-26 起游戏默认是钢城）：老测试的坐标都是按沙海写的，照旧开沙海；测钢城的测试在 boot 前设 T.mapName = "city"
  R.workspace:SetAttribute("MapName", T.mapName or "sands")
  for _, s in ipairs(T.scripts.server) do R.runScript(s, "server") end
  R.run(0.5)
  T.G = R.Gs.server
  -- 战雷式「玩家不步行」（Config.Wt.noInfantry，11-25）：老测试都是先当步兵出生再上车，默认照旧能当步兵；测机库、科技树的测试在 boot 前设 T.wtMode = true
  if not T.wtMode then T.G.allowInfantry = true end
  -- 匹配（11-26，WtMatch.lua）：老测试都是开服就进准备阶段——默认关着，测匹配的测试在 boot 前设 T.matchMode = true
  if not T.matchMode then T.G.matchOff = true end
  -- 射线打地形用项目自己的高度函数
  R.terrainHeight = T.G.Map.height
  return T.G
end

function T.runUntil(f, maxT, dt)
  local t = 0
  dt = dt or 1 / 30
  while t < maxT do
    if f() then return true end
    R.run(dt, dt)
    t = t + dt
  end
  return f() and true or false
end

-- 一个玩家进服；client = true 时这个玩家跑客户端脚本（模拟器同一时间只跑一个客户端）
function T.join(name, uid, client)
  local p = R.addPlayer(name, uid)
  if client then R.localPlayer = p end
  R.services.Players.PlayerAdded:Fire(p)
  if client then
    for _, c in ipairs(T.scripts.client) do R.runScript(c, "client") end
    T.C = nil
  end
  R.run(0.5)
  if client then
    T.C = R.Gs.client
    T.C.perfFixed = true   -- 自动画质不调（模拟器的帧率不是真的）
    if T.fpAll then T.allFirstPerson() end
    if not T.wtMode then T.C.forceInfantry = true end   -- 老测试：照旧是步兵部署页（不盖机库）
    -- 客户端每帧的步骤出错只显示在界面的红条上：也记进报错
    local se = T.C.showError
    if se then T.C.showError = function(m) R.errors[#R.errors + 1] = "客户端：" .. tostring(m) return se(m) end end
  end
  return p
end

-- 第一人称白名单（Config.FirstPerson.only：用户 11-25 只留 M1A1、M1A2）：测别的车内饰、飞机座舱的老测试在 join 前设 T.fpAll = true（全开）
function T.allFirstPerson()
  if T.G and T.G.Config.FirstPerson then T.G.Config.FirstPerson.only = nil end
  if T.C and T.C.Config.FirstPerson then T.C.Config.FirstPerson.only = nil end
end

function T.key(code, down)
  R.keys[code.Name] = down or nil
  R.as("client", function()
    -- ContextActionService 绑了这个键的（坦克的 Shift 瞄准镜、狙击镜屏息）：先调它
    for name, keys in pairs(R.bindKeys or {}) do
      for _, k in ipairs(keys) do
        if k == code and R.binds[name] then
          R.binds[name](name, down and Enum.UserInputState.Begin or Enum.UserInputState.End, { KeyCode = code, UserInputType = Enum.UserInputType.Keyboard })
        end
      end
    end
    if down then UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = code, UserInputState = Enum.UserInputState.Begin }, false)
    else UIS.InputEnded:Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = code, UserInputState = Enum.UserInputState.End }, false) end
  end)
end
function T.tap(code) T.key(code, true) T.key(code, false) end
function T.mouse(down, x, y, button)
  button = button or Enum.UserInputType.MouseButton1
  R.keys[button.Name] = down or nil
  local pos = T.V3(x or 640, y or 360, 0)
  R.as("client", function()
    if down then UIS.InputBegan:Fire({ UserInputType = button, Position = pos, UserInputState = Enum.UserInputState.Begin }, false)
    else UIS.InputEnded:Fire({ UserInputType = button, Position = pos, UserInputState = Enum.UserInputState.End }, false) end
  end)
end

local function visible(g)
  local o = g
  while o do
    local cls = o.ClassName
    if cls == "ScreenGui" then return o.Enabled ~= false end
    if cls == "PlayerGui" then return true end
    if (cls == "Frame" or cls == "TextButton" or cls == "TextLabel" or cls == "TextBox" or cls == "ImageButton" or cls == "ImageLabel" or cls == "ScrollingFrame" or cls == "CanvasGroup" or cls == "ViewportFrame") and o.Visible == false then return false end
    o = o.Parent
  end
  return true
end
T.visible = visible
function T.findButton(pattern, pl)
  pl = pl or R.localPlayer
  for _, d in ipairs(pl.PlayerGui:GetDescendants()) do
    if (d.ClassName == "TextButton" or d.ClassName == "ImageButton") and visible(d) and (d.ClassName ~= "TextButton" or d.Text:find(pattern)) then return d end
  end
end
function T.texts(pattern, pl)
  pl = pl or R.localPlayer
  local out = {}
  for _, d in ipairs(pl.PlayerGui:GetDescendants()) do
    if (d.ClassName == "TextLabel" or d.ClassName == "TextButton") and visible(d) and (not pattern or d.Text:find(pattern)) then out[#out + 1] = d.Text end
  end
  return out
end
function T.press(b)
  R.as("client", function()
    b.MouseButton1Down:Fire(640, 360)
    b.Activated:Fire({ UserInputType = Enum.UserInputType.MouseButton1 }, 1)
    b.MouseButton1Click:Fire()
    b.MouseButton1Up:Fire(640, 360)
  end)
end
-- 主菜单开着（背后是透明的 3D 场景，部署界面先不画）：像玩家一样点「进入战斗」关掉它（同 Luau 测试台的 H.leaveMenu）
function T.leaveMenu()
  R.as("client", function()
    if T.C.menuShown and T.C.menuShown() then T.C.menuEnter() end
  end)
  R.run(0.3)
end
function T.click(pattern)
  local b = T.findButton(pattern)
  if not b then error("找不到看得见的按钮：" .. pattern, 2) end
  T.press(b)
  R.run(0.1)
  return b
end
function T.act(...)
  local a = table.pack(...)
  R.as("client", function() T.C.R.Act:FireServer(table.unpack(a, 1, a.n)) end)
end
-- 不跑客户端的玩家（服务器那边的状态直接改）：用服务器的 ACT 表直接执行
function T.actAs(pl, op, ...)
  local P = T.G.P[pl]
  local f = T.G.ACT[op]
  if P and f then f(P, ...) end
end

-- 任意一个玩家往服务器发远程事件（不跑客户端的玩家也能「开枪」「下令」）：直接触发服务器那边的 OnServerEvent
function T.remoteAs(pl, name, ...)
  local a = table.pack(...)
  R.as("server", function() T.G.R[name].OnServerEvent:Fire(pl, table.unpack(a, 1, a.n)) end)
end
function T.actAsRemote(pl, ...) T.remoteAs(pl, "Act", ...) end

-- 地图里的载具生成点（Depots.lua）：找某个型号的生成点；走到终端柱旁边按 E；返回生成出来的那一辆
--   召唤位（飞机、直升机、地面载具都是：一个位上好几型，Depots.lua 的 summon、vids）：记下要的型号，usePad 时在弹出的卡片里点这一型
--   两边都能用对方的载具（Config.CrossVehicles）以后，对面的召唤位上也有这一型：先找本来就是这一边的型号的那边的召唤位（同以前），没有再随便哪个
T.padVid = {}
local function nativeOf(team, vid)
  for _, list in pairs((T.G.Config.Vehicles or {})[team] or {}) do
    if type(list) == "table" then
      for _, id in ipairs(list) do if id == vid then return true end end
    end
  end
  return false
end
function T.pad(vid, team)
  for _, p in ipairs(T.G.pads or {}) do
    if p.vid == vid and not p.summon then return p end
  end
  for pass = 1, 2 do
    for _, p in ipairs(T.G.pads or {}) do
      local ok = (pass == 2) or (team and p.team == team) or (not team and nativeOf(p.team, vid))
      if ok then
        for _, id in ipairs(p.vids or {}) do
          if id == vid then
            T.padVid[p] = vid
            return p
          end
        end
      end
    end
  end
  return nil
end
-- 按名字找一个看得见的按钮（召唤位的机型卡片 Pick_<型号>、挂载界面的内油 Fuel75……）
function T.findNamed(name, pl)
  pl = pl or R.localPlayer
  for _, d in ipairs(pl.PlayerGui:GetDescendants()) do
    if (d.ClassName == "TextButton" or d.ClassName == "ImageButton") and d.Name == name and visible(d) then return d end
  end
end
function T.usePad(pl, p)
  local G = T.G
  local y = p.ty or (p.sea and G.Map.BARGE.top) or G.airSurface(p.term.X, p.term.Z)   -- ty：舰艇生成点的终端柱站在码头面上
  pl.Character:PivotTo(T.CF(p.term.X + 1.5, y + 3, p.term.Z + 1.5))
  R.run(0.2)
  R.as("server", function() p.prompt.Triggered:Fire(pl) end)
  R.run(0.6)
  -- 地面召唤位：弹出车型卡片，点 T.pad 时要的那一型（不跑客户端的玩家直接替他发 padSpawn）；飞机的卡片测试自己点（后面还有挂载界面）
  local vid = p.summon and p.kind == "veh" and T.padVid[p]
  if vid then
    local card = (pl == R.localPlayer) and T.findNamed("Pick_" .. vid, pl)
    if card then T.press(card) else T.actAsRemote(pl, "padSpawn", p.id, false, vid) end
    R.run(0.6)
    -- 坦克选了以后先进改装界面（Garage.lua，用户 11-19）：照默认改装直接点「出车」
    local C = (pl == R.localPlayer) and T.C or nil
    if C and C.garageOpen and C.garageOpen() then
      local go = T.findNamed("GarageGo", pl)
      if go then T.press(go) R.run(0.6) end
    end
  end
  for _, list in ipairs({ G.vehicles or {}, G.aircraft or {}, G.ships or {} }) do
    for _, e in ipairs(list) do
      if e.padId == p.id and e.alive then return e end
    end
  end
  return nil
end

-- 假装 Studio 里导入了某个原模型（照 ImportedMeta 在 ReplicatedStorage.Imported.Veh.<key> 摆一套同名、同尺寸的 MeshPart；被新块顶替的旧块不摆）
function T.fakeImport(key)
  local RS = R.services.ReplicatedStorage
  local IM = R.require(RS:FindFirstChild("ImportedMeta"))
  local info = IM.m[key]
  if not info then return 0 end
  local imp = RS:FindFirstChild("Imported") or R.Instance.new("Folder")
  imp.Name = "Imported"
  imp.Parent = RS
  local vf = imp:FindFirstChild("Veh") or R.Instance.new("Folder")
  vf.Name = "Veh"
  vf.Parent = imp
  local f = R.Instance.new("Folder")
  f.Name = key
  local gone = {}
  for _, p in pairs(info.parts) do for _, o in ipairs(p.rep or {}) do gone[o] = true end end
  local n = 0
  for name, p in pairs(info.parts) do
    if not gone[name] then
      local b = R.Instance.new("MeshPart")
      b.Name = "V_" .. key .. "__" .. name
      b.Size = T.V3(p.s[1], p.s[2], p.s[3])
      b.Parent = f
      n = n + 1
    end
  end
  f:SetAttribute("N", n)
  f.Parent = vf
  return n
end

function T.summary()
  print(string.format("脚本报错 %d 条，警告 %d 条", #R.errors, #R.warns))
  -- 同一条（每帧都报的）只列一次，后面写重复了几次
  local function list(t, what, n, len)
    local seen, order = {}, {}
    for _, m in ipairs(t) do
      local k = m:sub(1, len)
      if not seen[k] then seen[k] = 0 order[#order + 1] = k end
      seen[k] = seen[k] + 1
    end
    for i = 1, math.min(n, #order) do print("  " .. what .. "：" .. order[i] .. (seen[order[i]] > 1 and ("（共 " .. seen[order[i]] .. " 次）") or "")) end
  end
  list(R.errors, "报错", 8, 400)
  list(R.warns, "警告", 6, 300)
  if #R.errors > 0 then T.fails = T.fails + 1 end
  print(T.fails == 0 and "全部通过" or ("不对 " .. T.fails .. " 处"))
  TEST_CODE = T.fails == 0 and 0 or 1
end
return T
