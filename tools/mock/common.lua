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
  for _, s in ipairs(T.scripts.server) do R.runScript(s, "server") end
  R.run(0.5)
  T.G = R.Gs.server
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
    -- 客户端每帧的步骤出错只显示在界面的红条上：也记进报错
    local se = T.C.showError
    if se then T.C.showError = function(m) R.errors[#R.errors + 1] = "客户端：" .. tostring(m) return se(m) end end
  end
  return p
end

function T.key(code, down)
  R.keys[code.Name] = down or nil
  R.as("client", function()
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
    if (cls == "Frame" or cls == "TextButton" or cls == "TextLabel" or cls == "ImageButton" or cls == "ImageLabel" or cls == "ScrollingFrame" or cls == "CanvasGroup") and o.Visible == false then return false end
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
function T.pad(vid)
  for _, p in ipairs(T.G.pads or {}) do
    if p.vid == vid then return p end
  end
  return nil
end
function T.usePad(pl, p)
  local G = T.G
  local y = p.sea and G.Map.BARGE.top or G.airSurface(p.term.X, p.term.Z)
  pl.Character:PivotTo(T.CF(p.term.X + 1.5, y + 3, p.term.Z + 1.5))
  R.run(0.2)
  R.as("server", function() p.prompt.Triggered:Fire(pl) end)
  R.run(0.6)
  for _, list in ipairs({ G.vehicles or {}, G.aircraft or {} }) do
    for _, e in ipairs(list) do
      if e.padId == p.id and e.alive then return e end
    end
  end
  return nil
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
