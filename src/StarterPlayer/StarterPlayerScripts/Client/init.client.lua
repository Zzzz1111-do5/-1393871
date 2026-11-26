-- Roblox全面大战场——客户端（StarterPlayerScripts.Client）
-- 各模块共用一个上下文 G：Fx 特效与音效 · MapUI 地图 · UI 界面 · Play 步兵操作 · View 实体的样子 · Drive 开载具（VehModels 拼车）·
--   FortView 地图自带工事的样子、走过去的「E 操作 / 上车」提示 · Gunner 操作工事（机枪、岸防炮、高炮、榴弹炮）、工兵的破障器材 ·
--   FPSView 第一人称：镜头前的枪（M4 照动作包的动画）和 Roblox 方块手臂 · Fly 飞机、直升机的样子和驾驶（AirModels 拼零件）·
--   ShipView 舰艇的样子 · Sail 开船（车钟、舵、舰炮、反舰导弹）· Hangar 挂载编辑器 ·
--   Optics 瞄准镜、望远镜的真模型（Sketchfab 原模型：导入的或内嵌后现生成的）· Scope 瞄准镜（目镜里的像：圆形出瞳、分划、倍率、别人镜片的闪光）· ScopePip 瞄准镜画中画（镜内单独放大）·
--   Depot 地图里的载具生成点（牌子、按键文字、飞机生成前弹挂载界面）· Night 夜视仪（N）· Faction 选阵营（解放军 / 美军）·
--   Chute 跳伞的人头顶的降落伞 · Tablet 遥控无人机的战术平板（平板外壳、地面站遥测、重连提示）· Soldier 机器人士兵（Roblox 小人）·
--   TacPad 单兵战术平板（B：呼叫空投载具、空投补给、空中打击，每样一局有次数；飞来的飞机、落下的货盘和炸弹）
--   Coach 新手指导（最下面按当前状态的几个键、F1 全部按键、第一次上某种载具的三步卡、目标方向箭头、队友和空车标记）
--   AirFx 飞机机动的云雾和音爆（翼尖涡流、高过载机翼水汽、跨音速蒸汽锥、过音障的音爆）
--   MslCam 导弹视角小窗（自己打出去的导弹 / 制导炸弹：右上角从弹上看目标，命中 / 未命中）
--   Juice 爽感（加分滚动、爆头、连杀横幅、受伤方向、低血量心跳）
--   Radar 战雷式机载雷达（雷达屏、置零 / 地杂波判定，雷达弹只能锁看得见的）
--   Bombsight 战雷式轰炸瞄准镜（F7）和 CCRP 目标点的画面（状态、按键、镜头在 Fly.lua）
--   Marks 炸弹落点标记（开飞机选中炸弹时地上的落点圈和光柱、扔出去的炸弹的落点）
--   Perf 性能面板（F7：帧率、各模块每帧毫秒、引擎统计）和自动画质多管的几样（地形草）
--   HudArt 驾驶界面的抗锯齿图标（HudIcons：每辆车侧面的全息图、六边形、炮弹……）解成 EditableImage
--   GunKit 改枪的配件：自己这把枪的武器表（G.myW）、别人 / 第三人称枪上装的配件模型、激光、手电
--   Gunsmith 改枪界面（对标三角洲行动：3D 枪、改装位、性能条、推荐改装、方案、改枪码）
--   Downed 倒地与救援（自己倒地的界面、镜头、放弃；队友头顶的救援标记、按住 E 救起；倒地的姿势）
--   Shock 震荡（近处爆炸：耳鸣、别的声音发闷、画面一白一糊）
--   Mantle 翻越 / 攀爬（步行时按空格：矮墙、沙袋翻过去，台子、窗台爬上去）
--   SquadHud 小队面板（队友血条、倒地、阵亡、距离）和小队队友头顶的绿色标记
--   Coins 左上角的金币牌子（菜单里一直显示，打仗时金币变了亮几秒）
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalizationService = game:GetService("LocalizationService")

local Lang = require(RS:WaitForChild("Lang"))
local G = { Config = require(RS:WaitForChild("Config")), Lang = Lang, Map = require(RS:WaitForChild("Map")), R = {}, S = nil }
G.Theme = require(RS:WaitForChild("Theme"))   -- 全游戏统一外观（颜色、字体、字号）：各界面从 G.Theme 取，规范在 docs/style.md
do   -- 语言：按系统语言，zh 开头中文、其余英文（界面上能切）
  local ok, id = pcall(function() return LocalizationService.RobloxLocaleId end)
  G.lang = Lang.pick(ok and id or "en")
end
local Remotes = RS:WaitForChild("Remotes")
for _, name in ipairs({ "State", "Act", "Shoot", "Msg", "Fx", "Drive", "Err", "Board" }) do
  G.R[name] = Remotes:WaitForChild(name)
end

-- 地图（用户 11-22：选地图）：服务器定了哪张，ReplicatedStorage 的 MapId 属性就是哪张——进服时已经定了就先换好再初始化各模块；
--   进服以后才定（自己在选地图界面点的）：换过来，再挨个通知存了地图数据的模块（G.onMap 登记：小地图、据点条、远海……）重算
local mapHooks = {}
function G.onMap(f) table.insert(mapHooks, f) end
do
  local mid = RS:GetAttribute("MapId")
  if type(mid) == "string" then G.Map.use(mid) end
  Lang.mapId = G.Map.id   -- 地图专用的说法（据点名……）
  if G.Config and G.Config.useMap then G.Config.useMap(G.Map.id) end   -- 跟着地图变的数（阶段表）
  local applied = G.Map.id   -- 各模块是按哪张初始化的（Studio 单机测试服务器、客户端共用一份 Map 表时 Map.id 可能已经先换了：按这个比）
  RS:GetAttributeChangedSignal("MapId"):Connect(function()
    local id = RS:GetAttribute("MapId")
    if type(id) ~= "string" or id == applied then return end
    if G.Map.use(id) then
      applied = id
      Lang.mapId = id
      if G.Config and G.Config.useMap then G.Config.useMap(id) end
      for _, f in ipairs(mapHooks) do
        local ok, err = pcall(f, id)
        if not ok then warn("[全面大战场] 换地图（" .. id .. "）出错：" .. tostring(err)) end
      end
    end
  end)
end

-- 逐帧回调计时（F7 性能面板 Perf.lua 读）：G.perfT[名字] = 这半秒累计的秒数；各模块自己的 RenderStepped 用 G.frameConn(名字, 函数) 连
G.perfT = {}
G.perfMax = {}   -- 这半秒里单次最长（一阵一阵卡的时候看是谁：用户 11-25「游戏一阵一阵卡，枪、坦克、飞机一阵一阵抽搐」）
function G.perfWrap(name, f)
  return function(...)
    local t0 = os.clock()
    f(...)
    local d = os.clock() - t0
    local T, M = G.perfT, G.perfMax
    T[name] = (T[name] or 0) + d
    if d > (M[name] or 0) then M[name] = d end
  end
end
function G.frameConn(name, f) return RunService.RenderStepped:Connect(G.perfWrap(name, f)) end

-- 武器表（自己的枪装了配件以后的那份）：G.W[武器] = G.myW(武器)（GunKit.lua 按背包里工具的 Build 属性算，GunMods.apply）；
--   Play、Hud、FPSView 开枪、换弹、准星、后坐都按它（服务器 Weapons.lua 按同一套算的那份核对）
G.W = setmetatable({}, { __index = function(_, id)
  local f = G.myW
  if f then return f(id) end
  return G.Config.Weapons[id]
end })

-- 一个模块初始化出错、或者脚本没换全少了一个模块，不能把后面的都卡死（用户 11-20：deploy 进不去——原来出一个错就停在那里，部署界面都起不来）：
--   每个模块单独 pcall；等不到的模块等 10 秒就跳过；出的错打到输出窗口，等界面起来以后也显示在屏幕上方的红字里
local initErrs = {}
for _, name in ipairs({ "Stream", "HudArt", "GunKit", "Fx", "VehCam", "MapUI", "UI", "Faction", "Menu", "MapPick", "Play", "View", "Soldier", "Drive", "Ride", "Hatch", "Fly", "ShipView", "Sail", "Hangar", "Depot", "Night", "DayNight", "Chute", "Tablet", "TacPad", "FortView", "Gunner", "AaFcs", "Optics", "FPSView", "GearView", "ScopePip", "Scope", "Scenery", "Hud", "Operation", "Coach", "AirFx", "Nuke", "MslCam", "Juice", "Warfx", "VehHud", "Bodycam", "Nade", "ArmorFx", "WreckFx", "Garage", "TankHud", "WtHud", "WtTank", "WtBattle", "TechUI", "WtAmmo", "WtSkin", "WtVoice", "WtComms", "WtCam", "Settings", "ArtyView", "Tracks", "WtVfx", "WtMap", "XrayOwn", "WtAir", "AirHud", "AirAudio", "Bombsight", "Radar", "WtFlight", "Marks", "Gunsmith", "Interior", "Downed", "Shock", "DeathFx", "Mantle", "SquadHud", "Coins", "Perf" }) do
  local mod = script:WaitForChild(name, 10)
  if not mod then
    table.insert(initErrs, "缺少模块 " .. name .. "（脚本没换全？）")
  else
    local ok, err = pcall(function() require(mod).init(G) end)
    if not ok then table.insert(initErrs, name .. " 初始化出错：" .. tostring(err)) end
  end
end
for _, e in ipairs(initErrs) do
  warn("[全面大战场] " .. e)
  if G.showError then G.showError("local " .. e) end
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
  { "sail", function(dt) if G.stepSail then G.stepSail(dt) end end }, { "view", function(dt) G.stepView(dt) end },
  { "interior", function(dt) if G.stepInterior then G.stepInterior(dt) end end },   -- 载具内饰：要用 View 这一帧算好的车体、炮塔姿态，镜头最后定
  { "ride", function(dt) if G.stepRide then G.stepRide(dt) end end },   -- 坐在别人开的车后面（Ride.lua）：镜头要用 View 这一帧摆好的车
  { "hatch", function(dt) if G.stepHatches then G.stepHatches(dt) end end },   -- 舱盖、车门开合，车长探身，上车的小人（Hatch.lua）：跟着 View 这一帧摆好的车
  { "play", function(dt) G.stepPlay(dt) end },
  { "fx", function(dt) G.stepFx(dt) end }, { "forts", function(dt) if G.stepForts then G.stepForts(dt) end end },
  { "gunner", function(dt) if G.stepGunner then G.stepGunner(dt) end end },
  { "ui", function(dt) G.stepUI(dt) end }, { "map", function() G.stepMap() end },
  { "operation", function(dt) G.stepOperation(dt) end }, { "hud", function(dt) if G.stepHud then G.stepHud(dt) end end },
  { "scenery", function(dt) if G.stepScenery then G.stepScenery(dt) end end },
  { "chute", function(dt) if G.stepChute then G.stepChute(dt) end end },
  { "tablet", function(dt) if G.stepTablet then G.stepTablet(dt) end end },
  { "tacpad", function(dt) if G.stepTacPad then G.stepTacPad(dt) end end },
  { "menu", function(dt) if G.stepMenu then G.stepMenu(dt) end end },   -- 主菜单背后的场景（火光、镜头）
  { "coach", function(dt) if G.stepCoach then G.stepCoach(dt) end end },   -- 新手指导：按键提示、三步卡、目标箭头、队友 / 空车标记
  { "daynight", function(dt) if G.stepDayNight then G.stepDayNight(dt) end end },   -- 昼夜更替（DayNight.lua）
  { "airfx", function(dt) if G.stepAirFx then G.stepAirFx(dt) end end },   -- 飞机机动的翼尖涡流、机翼水汽、蒸汽锥、音爆
  { "mslcam", function() if G.stepMslCam then G.stepMslCam() end end } }   -- 导弹视角小窗
RunService.RenderStepped:Connect(function(dt)
  local T, M = G.perfT, G.perfMax
  for _, s in ipairs(steps) do
    local t0 = os.clock()
    local ok, err = pcall(s[2], dt)
    local d = os.clock() - t0
    T[s[1]] = (T[s[1]] or 0) + d
    if d > (M[s[1]] or 0) then M[s[1]] = d end
    if not ok then G.showError("local " .. s[1] .. ": " .. tostring(err)) end
  end
end)
