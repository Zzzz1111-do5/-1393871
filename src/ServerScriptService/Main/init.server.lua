-- Roblox全面大战场——服务器主脚本（ServerScriptService.Main）
-- 各模块共用一个上下文 G：每个模块的 init(G) 把自己的函数挂到 G 上，模块之间通过 G 互相调用（不互相 require，免得循环引用）
--   World 地图 · Store 存档 · Round 回合、分队、部署、据点、胜负 · Weapons 步兵武器 · Ents 实体（机器人、载具、舰艇、工事）与伤害、爆炸、飞行中的弹 ·
--   Vehicles 开载具、登陆艇 · Armor 地面载具 · Air 飞机、直升机 · Forts 地图自带的工事和障碍（玩家走过去能操作） · Bots 机器人
-- 循环里每一步都包在 pcall 里：一处出错只跳过那一下，不会把整个服务器卡死（出错原文发到所有人屏幕上的红条）
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(RS:WaitForChild("Config"))
local Map = require(RS:WaitForChild("Map"))
local G = { Config = Config, Map = Map, P = {} }   -- P[player] = 这个玩家这一局的状态

Players.CharacterAutoLoads = false   -- 先看部署界面：选好兵种和出生点才生成角色

---------------------------------------------------------------- 远程事件

local Remotes = Instance.new("Folder")
Remotes.Name = "Remotes"
G.R = {}
for _, name in ipairs({ "State", "Act", "Shoot", "Msg", "Fx", "Drive", "Err", "Board" }) do
  local r = Instance.new("RemoteEvent")
  r.Name = name
  r.Parent = Remotes
  G.R[name] = r
end
Remotes.Parent = RS

local fxq = {}
function G.fx(e) fxq[#fxq + 1] = e end
-- 发一条文字（编号 + 参数，客户端按自己的语言翻译）；kind：info / good / bad / kill / center
function G.msg(pl, kind, key, ...)
  if pl then G.R.Msg:FireClient(pl, kind, key, ...) end
end
function G.msgAll(kind, key, ...) G.R.Msg:FireAllClients(kind, key, ...) end
function G.msgTeam(team, kind, key, ...)
  for pl, P in pairs(G.P) do
    if P.team == team then G.R.Msg:FireClient(pl, kind, key, ...) end
  end
end

-- 开服时出的错记下来；运行中接住的错 Output 里留一条、所有玩家屏幕上方红条显示（同一个错只发一次）
G.bootErrors = {}
local function bootError(what, err)
  local msg = "[全面大战场] " .. what .. "出错：" .. tostring(err)
  warn(msg)
  table.insert(G.bootErrors, msg)
end
local errSeen, errN = {}, 0
function G.reportError(where, err)
  local full = tostring(err)
  local first = string.match(full, "^[^\n]*") or full
  local key = tostring(where) .. first
  if errSeen[key] then return end
  errSeen[key] = true
  errN += 1
  warn("[全面大战场] " .. tostring(where) .. " 出错：" .. full)
  if errN <= 8 then pcall(function() G.R.Err:FireAllClients(string.sub(tostring(where) .. "：" .. first, 1, 300)) end) end
end
local function tb(e) return debug.traceback(tostring(e), 2) end
function G.try(where, f, ...)
  local ok, err = xpcall(f, tb, ...)
  if not ok then G.reportError(where, err) end
  return ok, err
end

-- 每帧要做的（登陆艇、开着的车、车组跟车）：G.onFrame 登记
local frameFns = {}
function G.onFrame(f) table.insert(frameFns, f) end

-- 事件：模块之间互相通知（开局、阵亡、走人、据点易手、结算）——G.on 登记、G.emit 挨个调（一个出错不影响别的）
local hooks = {}
function G.on(ev, f)
  hooks[ev] = hooks[ev] or {}
  table.insert(hooks[ev], f)
end
function G.emit(ev, ...)
  for _, f in ipairs(hooks[ev] or {}) do G.try(ev, f, ...) end
end

local ACT = {}
G.ACT = ACT   -- 各模块往里登记客户端能发来的操作：ACT.deploy = function(P, ...) … end

-- 各模块挂到 G 上；一个出错不影响后面的（init 里不能等网络、不能久等，要等的放 task.spawn）
G.World = require(script:WaitForChild("World"))
for _, name in ipairs({ "Store", "Ents", "Round", "Weapons", "Vehicles", "Armor", "Air", "Forts", "Nav", "Bots" }) do
  local mod = script:FindFirstChild(name)
  if mod then
    local ok, err = pcall(function() require(mod).init(G) end)
    if not ok then bootError("模块 " .. name .. " ", err) end
  end
end

---------------------------------------------------------------- 客户端发来的操作

G.R.Act.OnServerEvent:Connect(function(pl, op, a, b, c)
  local P = G.P[pl]
  if not P or type(op) ~= "string" then return end
  -- 限流：每秒十几次
  local now = os.clock()
  P.tokens = math.min(20, (P.tokens or 20) + (now - (P.tokT or now)) * 14)
  P.tokT = now
  if P.tokens < 1 then return end
  P.tokens -= 1
  local f = ACT[op]
  if f then G.try("操作 " .. op, f, P, a, b, c) end
end)

G.R.Shoot.OnServerEvent:Connect(function(pl, id, a, b)
  local P = G.P[pl]
  if P and type(id) == "string" and G.shoot then G.try("开火", G.shoot, P, id, a, b) end
end)

G.R.Drive.OnServerEvent:Connect(function(pl, d)
  local P = G.P[pl]
  if P and type(d) == "table" and G.driveInput then G.try("开载具", G.driveInput, P, d) end
end)

---------------------------------------------------------------- 开服：先生成地图，再开局

task.spawn(function()
  local ok, err = xpcall(function() G.World.build(G) end, tb)
  if not ok then bootError("生成地图", err) G.worldReady = true end
  if G.navBuild then G.try("寻路", G.navBuild) end   -- 后台算机器人走路的流场
  if G.roundStart then G.try("开局", G.roundStart) end
  print("[全面大战场] " .. Config.Version .. " 地图好了：" .. tostring(G.terrainChunks) .. " 块地形、" .. tostring(G.terrainVoxels) .. " 个体素")
end)

---------------------------------------------------------------- 循环

-- 推演：每 Config.Tick 秒一步（占领、AI、炮弹、导弹、登陆艇）
local acc = 0
RunService.Heartbeat:Connect(function(dt)
  acc += dt
  local n = 0
  while acc >= Config.Tick and n < 3 do
    acc -= Config.Tick
    n += 1
    if G.worldReady then
      if G.roundStep then G.try("回合", G.roundStep, Config.Tick) end
      if G.entsStep then G.try("实体", G.entsStep, Config.Tick) end
      if G.botsStep then G.try("机器人", G.botsStep, Config.Tick) end
      if G.vehStep then G.try("载具", G.vehStep, Config.Tick) end
      if G.fortsStep then G.try("工事", G.fortsStep, Config.Tick) end
    end
  end
  if acc > Config.Tick * 3 then acc = 0 end
  for _, f in ipairs(frameFns) do G.try("逐帧", f, dt) end   -- 登陆艇、开着的载具：每帧挪一次（看着平滑）
  if #fxq > 0 then
    local list = fxq
    fxq = {}
    G.R.Fx:FireAllClients(list)
  end
end)

game:BindToClose(function()
  if G.saveAll then G.saveAll() end
end)

print("[全面大战场] " .. Config.Version .. " 服务器启动" .. ((#G.bootErrors > 0) and ("（有 " .. #G.bootErrors .. " 处出错，见上面的警告）") or ""))
