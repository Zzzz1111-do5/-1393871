-- Roblox全面大战场——客户端（StarterPlayerScripts.Client）
-- 各模块共用一个上下文 G：Fx 特效与音效 · MapUI 地图 · UI 界面 · Play 步兵操作 · View 实体的样子 · Drive 开载具（VehModels 拼车）·
--   FortView 地图自带工事的样子、走过去的「E 操作 / 上车」提示 · Gunner 操作工事（机枪、岸防炮、高炮、榴弹炮）、工兵的破障器材 ·
--   FPSView 第一人称：镜头前的枪（M4 照动作包的动画）和 Roblox 方块手臂 · Fly 飞机、直升机的样子和驾驶（AirModels 拼零件）·
--   ShipView 舰艇的样子 · Sail 开船（车钟、舵、舰炮、反舰导弹）· Hangar 挂载编辑器 ·
--   Optics 瞄准镜、望远镜的真模型（Sketchfab 原模型：导入的或内嵌后现生成的）· Scope 瞄准镜（目镜里的像：圆形出瞳、分划、倍率、别人镜片的闪光）·
--   Depot 地图里的载具生成点（牌子、按键文字、飞机生成前弹挂载界面）· Night 夜视仪（N）· Faction 选阵营（解放军 / 美军）·
--   Chute 跳伞的人头顶的降落伞 · Tablet 遥控无人机的战术平板（平板外壳、地面站遥测、重连提示）
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalizationService = game:GetService("LocalizationService")

local Lang = require(RS:WaitForChild("Lang"))
local G = { Config = require(RS:WaitForChild("Config")), Lang = Lang, Map = require(RS:WaitForChild("Map")), R = {}, S = nil }
do   -- 语言：按系统语言，zh 开头中文、其余英文（界面上能切）
  local ok, id = pcall(function() return LocalizationService.RobloxLocaleId end)
  G.lang = Lang.pick(ok and id or "en")
end
local Remotes = RS:WaitForChild("Remotes")
for _, name in ipairs({ "State", "Act", "Shoot", "Msg", "Fx", "Drive", "Err", "Board" }) do
  G.R[name] = Remotes:WaitForChild(name)
end

for _, name in ipairs({ "Fx", "MapUI", "UI", "Faction", "Menu", "Play", "View", "Drive", "Fly", "ShipView", "Sail", "Hangar", "Depot", "Night", "Chute", "Tablet", "FortView", "Gunner", "Optics", "FPSView", "GearView", "Scope", "Scenery", "Hud" }) do
  require(script:WaitForChild(name)).init(G)
end

task.delay(25, function()
  if not G.S then G.toast("Server data has not arrived after 25 s — the server script may have stopped. Check the Output window.", "bad") end
end)

G.R.Err.OnClientEvent:Connect(function(msg) G.showError("server " .. tostring(msg)) end)
pcall(function()
  game:GetService("ScriptContext").Error:Connect(function(msg, trace)
    local line = trace and string.match(trace, "[^\n]+") or ""
    G.showError("local " .. tostring(msg) .. ((line ~= "") and ("  @ " .. line) or ""))
  end)
end)

local function safe(f)
  return function(...)
    local ok, err = pcall(f, ...)
    if not ok then G.showError("local " .. tostring(err)) end
  end
end
G.R.State.OnClientEvent:Connect(safe(function(s)
  if type(s) ~= "table" then return end
  G.S = s
  G.refresh()
end))
G.R.Msg.OnClientEvent:Connect(safe(function(kind, key, ...) G.onMsg(kind, key, ...) end))
G.R.Fx.OnClientEvent:Connect(safe(function(list) G.onFx(list) end))
G.R.Board.OnClientEvent:Connect(safe(function(d) G.onBoard(d) end))

local steps = { { "drive", function(dt) G.stepDrive(dt) end }, { "fly", function(dt) if G.stepFly then G.stepFly(dt) end end },
  { "sail", function(dt) if G.stepSail then G.stepSail(dt) end end }, { "view", function(dt) G.stepView(dt) end }, { "play", function(dt) G.stepPlay(dt) end },
  { "fx", function(dt) G.stepFx(dt) end }, { "forts", function(dt) if G.stepForts then G.stepForts(dt) end end },
  { "gunner", function(dt) if G.stepGunner then G.stepGunner(dt) end end },
  { "ui", function(dt) G.stepUI(dt) end }, { "map", function() G.stepMap() end }, { "hud", function(dt) if G.stepHud then G.stepHud(dt) end end },
  { "scenery", function(dt) if G.stepScenery then G.stepScenery(dt) end end },
  { "chute", function(dt) if G.stepChute then G.stepChute(dt) end end },
  { "tablet", function(dt) if G.stepTablet then G.stepTablet(dt) end end } }
RunService.RenderStepped:Connect(function(dt)
  for _, s in ipairs(steps) do
    local ok, err = pcall(s[2], dt)
    if not ok then G.showError("local " .. s[1] .. ": " .. tostring(err)) end
  end
end)
