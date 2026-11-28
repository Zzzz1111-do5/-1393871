-- Roblox全面大战场（客户端）——车被打爆（用户 11-25「载具爆炸效果不够猛画风不够战雷」；11-27「坦克爆炸照战雷做」「M3 上要丝滑」）：照真车殉爆的录像做，写实、不卡通
--   殉爆（服务器 Wt.lua destroy 的 why = "ammo"，View.lua 车变残骸那一帧调 G.wreckFx）：按车的编号从三种样子里挑一种（战雷 Drone Age：每次不一样，但所有人看到的一样）——
--     A「大火球」：白热闪光 → 翻滚的大火球（白热的芯、橙红的火）→ 裹着它往上翻的煤黑浓烟（蘑菇），一大把火星
--     B「座圈火柱」：火球小一点，一根火柱从炮塔座圈直冲上去
--     C「连爆」：两三下接连炸开（隔 0.15～0.3 秒，位置在车里错开）
--   之后：十来块真的钢板碎块（会落地、会弹的零件；抵掉一部分重力，能飞二三十格高、几十格远），拖着火和黑烟，落地 4 秒后定住、留到残骸没了
--     （全局最多 40 块，满了先收最早定住的）；履带车再甩出一两个负重轮，在地上滚；地上一圈冲击波、贴地往外推的一圈土；地面烧焦一大块；
--     八九秒里车里剩下的弹一发一发殉爆（一闪、火星、一小团火、噼啪响，越来越稀）；舱口往外蹿火；车身大火、浓黑的烟柱顺风歪过去
--     （View.lua 的 fire / black 发射器：这里调粗调黑；烧四十秒火小下去、七十秒只剩一缕烟，见 View.lua）
--   烧毁（"fire"）：没有大火球，发动机舱窜火、黑烟柱、地面烧焦；乘员打光（"crew"）和别的：一缕黑烟
--   爆炸那几层全用 VfxLib 的发射器池（不每次新建发射器）；火（fire_main 本身暗褐）LightInfluence 0 + Brightness 3 才亮，
--   烟用 explosion01_smoke_main（本身深灰）、受光照、跟着风；火星是白点顺着速度拉成线（不用八角星）
--   离镜头远、机器跟不上（G.perfK）的少画；同时最多 3 处殉爆在冒碎块
--   11-27 审查：
--   · 预算（5）：殉爆第一秒所有发射器加起来（池里喷的 + 掀炮塔的火柱火星黑烟 + 碎块拖的火和烟 + 舱口火柱 + 炮塔身上的火和烟 + 车身大火）
--     压在 350 颗以内——掀炮塔那几层改走池（G.wreckTossFx / G.wreckLandFx），常喷的发射器少喷一点、用 VfxLib.rateK 记进全局预算。
--     规格写的是 300，11-27 复核时明确接受 350：最费的连爆炸三下实测三百出头（接连殉爆的头一两下落不落在第一秒里，上下差二三十颗）；
--     再砍就得砍火星、连爆、火柱，而用户 11-25 嫌过「载具爆炸效果不够猛」；M3 上贵的是贴脸的大块半透明（overdraw），不是这一秒
--     多出来的二三十颗小火星；全局 1800 / 2800 的上限照样管着（tools/mock/vfxreal.lua 按炸三下查 ≤ 350）
--   · 灯（6）：殉爆只点这里这一盏大灯（View 掀炮塔那盏去掉），白天最多亮 1.5 倍
--   · 碎块（13）：碰撞组——只跟地形、建筑碰，不碰角色和车
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local WreckFx = {}

function WreckFx.init(G)
  local V, CF, RGB = Vector3.new, CFrame.new, Color3.fromRGB
  local Map = require(RS:WaitForChild("Map"))
  local VL = G.vfx
  if not VL then error("WreckFx 要先有 Fx（VfxLib）") end
  local TX = VL.TX
  local seq, cs = VL.ns, VL.cs
  local upCF, lookCF = VL.upCF, VL.lookCF
  local UP = V(0, 1, 0)
  local DAY = { day = VL.DAY_MUL_BIG }   -- 殉爆的灯白天最多亮 1.5 倍
  -- 写实的颜色：火是白热 → 金黄 → 橙红，烟是煤黑 → 灰褐（不要纯黑、不要发紫）
  local FIRE_MID, FIRE_DARK = RGB(255, 158, 64), RGB(150, 52, 22)
  -- 火的中心偏白（用户 11-28「战雷的火中心偏白」）：刚喷出来（在火团中心）近乎白热，往外飘、变老才转金黄 → 橙 → 暗红
  local FIRE_WHITE, FIRE_PALE = RGB(255, 250, 238), RGB(255, 226, 158)

  local function holder(cf)
    local p = Instance.new("Part")
    p.Size, p.CFrame, p.Transparency = V(0.3, 0.3, 0.3), cf, 1
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    p.Parent = G.fxFolder or workspace
    return p
  end
  -- 单独一个常喷的发射器（舱口火柱、碎块拖的火和烟这种要跟着东西、喷好几秒的）：o 的字段同 VfxLib（tex、life、spd、spread、size、tr、col、
  --   acc、drag、le、li、bright、rot、dir、vp、sq、wind）；rate 常喷、n 一次喷多少；secs 大概喷几秒（记进全局预算，粒子太多时 Rate 少给）
  local function emitter(h, o)
    local pe = Instance.new("ParticleEmitter")
    if o.rate and o.rate > 0 then
      local kb = VL.rateK(o.rate, o.secs or 3, o.life[2], o.prio or 2)
      o.rate = o.rate * kb
    end
    VL.apply(pe, o)
    pe.Parent = h
    if o.n and o.n > 0 then pe:Emit(o.n) end
    return pe
  end
  local function lod(p)
    local t, d = VL.lod(p)
    local k = VL.perfK() * ((t == 2) and 0.65 or ((t >= 3) and 0.4 or 1))
    return k, d, t
  end
  local function N(x, k) return math.max(1, math.floor(x * k + 0.5)) end
  local stat = { big = 0, chunks = 0, pops = 0, scorch = 0, jets = 0, wheels = 0, anchored = 0, style = {}, toss = 0, land = 0 }   -- 给测试看的（tools/mock/wreckfx.lua、vfxreal.lua）
  G.wreckStat = stat
  local function groundAt(p) return math.max(Map.height(p.X, p.Z), 0) end
  -- 残骸脚下是什么地（扬起的土按它上色）
  local function codeAt(p)
    local hs = G.groundUnder and G.groundUnder(p + V(0, 4, 0), 16)
    return G.groundCode and G.groundCode(hs) or "d"
  end

  ---------------------------------------------------------------- 碰撞组（审查 13）
  -- 碎块、负重轮现在飞得高、飞得远，物理在本地算：原来 CanCollide 一开，最容易推开、绊住本地玩家的角色。
  --   VfxChunk（碎块）只跟 Default（地形、房子、地图上的零件）碰；角色（所有玩家的）、车（View 的模型）的零件放进 VfxActor
  --   ——VfxActor 跟 Default、跟自己照样碰，只是不碰碎块。碎块之间也不碰（省物理）。
  --   PhysicsService 注册不了（老版本、客户端不让注册）就照旧：碎块照样碰所有东西（输出里留一条提示）
  --   服务器（Ents.lua）开服时也注册一遍：客户端不让注册、不让改的话，用服务器注册好、复制过来的那份
  local CHUNK_G, ACTOR_G = "VfxChunk", "VfxActor"
  local groupsOk = pcall(function()
    local PS = game:GetService("PhysicsService")
    local function reg(n)
      local okR, has = pcall(function() return PS:IsCollisionGroupRegistered(n) end)
      if not (okR and has) then PS:RegisterCollisionGroup(n) end
    end
    reg(CHUNK_G)
    reg(ACTOR_G)
    local okSet = pcall(function()
      PS:CollisionGroupSetCollidable(CHUNK_G, ACTOR_G, false)
      PS:CollisionGroupSetCollidable(CHUNK_G, CHUNK_G, false)
      PS:CollisionGroupSetCollidable(CHUNK_G, "Default", true)
      PS:CollisionGroupSetCollidable(ACTOR_G, "Default", true)
      PS:CollisionGroupSetCollidable(ACTOR_G, ACTOR_G, true)
    end)
    if not okSet and PS:CollisionGroupsAreCollidable(CHUNK_G, ACTOR_G) then error("碰撞组没设好") end
  end)
  G.wreckGroupsOk = groupsOk
  if not groupsOk then warn("[特效] 碎块的碰撞组注册不了（PhysicsService）：碎块照旧碰所有东西") end
  if groupsOk then
    local function actorPart(d)
      if d:IsA("BasePart") then pcall(function() if d.CollisionGroup ~= ACTOR_G then d.CollisionGroup = ACTOR_G end end) end
    end
    local function actorModel(m)
      if not m then return end
      for _, d in ipairs(m:GetDescendants()) do actorPart(d) end
      m.DescendantAdded:Connect(actorPart)
    end
    local function watchChar(pl)
      if pl.Character then actorModel(pl.Character) end
      pl.CharacterAdded:Connect(actorModel)
    end
    for _, pl in ipairs(Players:GetPlayers()) do watchChar(pl) end
    Players.PlayerAdded:Connect(watchChar)
    actorModel(G.viewFolder)   -- 车、机器人、工事的样子（View.lua 的 EntView）
  end
  local function chunkGroup(p)
    if groupsOk then pcall(function() p.CollisionGroup = CHUNK_G end) end
  end

  ---------------------------------------------------------------- 爆炸的各层（q = 火球半径 R / 14，主战坦克 1 上下；按 1.2 倍一档建发射器）
  VL.def("wFlash", function(q)   -- A0 闪光
    local R = 14 * q
    return { tex = TX.GLOW, life = { 0.14, 0.2 }, spd = { 0, 0 }, size = seq(0, R * 2, 1, R * 3.6), tr = seq(0, 0, 1, 1),
      col = cs(RGB(255, 250, 236), RGB(255, 200, 140)), le = 1, li = 0, bright = 6, z = 4, prio = 1 }
  end)
  VL.def("wCore", function(q)   -- A1 火球芯：从车里一个球里往外胀开
    local R = 14 * q
    return { tex = TX.CORE, life = { 0.5, 0.9 }, spd = { R * 0.6, R * 1.6 }, spread = 180, drag = 6, acc = V(0, R * 0.8, 0), rot = 120,
      size = seq(0, R * 0.6, 0.3, R * 1.3, 1, R * 1.5), tr = seq(0, 0, 0.6, 0.3, 1, 1),
      col = cs(0, FIRE_WHITE, 0.32, RGB(255, 238, 196), 0.55, RGB(255, 172, 72), 0.8, RGB(170, 64, 26), 1, RGB(70, 36, 22)),
      le = 0.95, li = 0, bright = 4, z = 3, shape = { "Sphere", "Volume", "Outward" }, box = V(R * 0.8, R * 0.8, R * 0.8), prio = 1 }
  end)
  VL.def("wHeart", function(q)   -- A1′ 白热的芯（用户 11-28「战雷的火中心偏白」）：火球正中几团叠加发光的白光，比火球芯活得久一点，慢慢转金黄、淡掉
    local R = 14 * q
    return { tex = TX.GLOW, life = { 0.55, 0.95 }, spd = { 0, R * 0.25 }, spread = 180, drag = 4, acc = V(0, R * 0.5, 0),
      size = seq(0, R * 0.8, 0.35, R * 1.35, 1, R * 1.1), tr = seq(0, 0.15, 0.55, 0.4, 1, 1),
      col = cs(0, RGB(255, 255, 250), 0.5, RGB(255, 244, 214), 1, RGB(255, 200, 120)), le = 1, li = 0, bright = 4, z = 3, prio = 1 }
  end)
  VL.def("wFire", function(q)   -- A2 翻滚的火：往外滚、被空气挡住、往上卷
    local R = 14 * q
    return { tex = TX.FIRE, life = { 1.0, 2.0 }, spd = { R * 0.8, R * 2.4 }, spread = 180, drag = 4, acc = V(0, R * 1.1, 0), rot = 70,
      size = seq(0, R * 0.5, 0.25, R * 1.1, 1, R * 0.7), tr = seq(0, 0.05, 0.5, 0.25, 1, 1), col = cs(0, FIRE_WHITE, 0.2, FIRE_PALE, 0.5, FIRE_MID, 1, FIRE_DARK),
      le = 0.9, li = 0, bright = 3.5, z = 2, prio = 1 }
  end)
  VL.def("wSoot", function(q)   -- A3 黑烟蘑菇：从火球外面翻上去，越升越大、越淡，顺风歪
    local R = 14 * q
    return { tex = TX.SOOT, life = { 5, 9 }, spd = { R * 0.5, R * 1.5 }, spread = 180, drag = 1.6, acc = V(0, R * 0.38 + 3, 0), wind = true, rot = 18,
      size = seq(0, R * 0.7, 0.2, R * 1.6, 1, R * 3.2), tr = seq(0, 1, 0.05, 0.08, 0.4, 0.2, 1, 1), col = cs(RGB(255, 255, 255)), z = 1, prio = 2 }
  end)
  VL.def("wEdge", function(q)   -- A3 外沿浅一点的烟
    local R = 14 * q
    return { tex = TX.SMOKE, life = { 5, 9 }, spd = { R * 0.6, R * 1.6 }, spread = 180, drag = 1.6, acc = V(0, R * 0.38 + 3, 0), wind = true, rot = 18,
      size = seq(0, R * 0.8, 0.2, R * 1.8, 1, R * 3.4), tr = seq(0, 1, 0.05, 0.1, 0.4, 0.3, 1, 1), col = cs(RGB(44, 41, 38), RGB(78, 74, 70)), z = 1, prio = 2 }
  end)
  VL.def("wSpark", function()   -- A4 火星：往四周上方撒，顺着飞的方向拉成线，带重力落
    return { tex = TX.GLOW, life = { 0.9, 2.2 }, spd = { 30, 85 }, spread = 70, drag = 0.6, acc = V(0, -28, 0),
      size = seq(0, 0.5, 1, 0.15), tr = seq(0, 0, 0.8, 0.2, 1, 1), col = cs(RGB(255, 232, 170), RGB(255, 150, 70)), le = 1, li = 0, bright = 3,
      vp = true, sq = seq(0, 2, 1, 0.8), prio = 3 }
  end, true)
  VL.def("wPillar", function(q)   -- B 座圈火柱
    local R = 14 * q
    return { tex = TX.FIRE, life = { 0.9, 1.4 }, spd = { 40, 80 }, spread = 12, drag = 1.5, acc = V(0, 8, 0), rot = 80,
      size = seq(0, R * 0.35, 0.4, R * 0.7, 1, R * 0.2), tr = seq(0, 0.05, 0.6, 0.3, 1, 1), col = cs(0, FIRE_WHITE, 0.3, FIRE_PALE, 0.6, FIRE_MID, 1, FIRE_DARK),
      le = 0.95, li = 0, bright = 3, z = 2, prio = 1 }
  end)
  VL.def("wDust", function(q, v)   -- A8 贴地往外推的一圈土（按残骸脚下的地上色）
    local R = 14 * q
    local P = (G.groundPal and G.groundPal(v)) or { dust = RGB(132, 118, 98), dust2 = RGB(170, 160, 142), life = 1 }
    return { tex = TX.SMOKE, life = { 1.6 * P.life, 2.8 * P.life }, spd = { R * 1.2, R * 2.4 }, dir = Enum.NormalId.Front, spread = { 180, 3 }, drag = 2,
      acc = V(0, 1.2, 0), wind = true, rot = 25, size = seq(0, R * 0.4, 1, R * 1.6), tr = seq(0, 0.3, 1, 1), col = cs(P.dust, P.dust2), sq = seq(0, -0.5, 1, -0.5), prio = 2 }
  end)
  VL.def("wShock", function(q)   -- A8 贴地冲击波圈
    local R = 14 * q
    return { tex = TX.RING, life = { 0.45, 0.55 }, spd = { 0.05, 0.05 }, spread = 0, flat = true, size = seq(0, R * 0.5, 1, R * 5),
      tr = seq(0, 0.2, 1, 1), col = cs(RGB(240, 226, 200)), li = 1, z = 0, prio = 3 }
  end)
  -- A9 车里剩下的弹一发一发殉爆（var B：大的一下）
  VL.def("wPopFlash", function(_, v)
    local b = v == "B"
    return { tex = TX.GLOW, life = { 0.08, 0.13 }, spd = { 0, 0 }, size = b and seq(0, 9, 1, 13) or seq(0, 5, 1, 7), tr = seq(0, 0, 1, 1),
      col = cs(RGB(255, 246, 220), RGB(255, 190, 120)), le = 1, li = 0, bright = 5, z = 3, prio = 1 }
  end, true)
  VL.def("wPopSpark", function(_, v)
    return { tex = TX.GLOW, life = { 0.5, 1.3 }, spd = { 20, (v == "B") and 70 or 50 }, spread = 60, drag = 0.5, acc = V(0, -40, 0),
      size = seq(0, 0.4, 1, 0.1), tr = seq(0, 0, 1, 0.4), col = cs(RGB(255, 230, 160), RGB(255, 140, 60)), le = 1, li = 0, bright = 3,
      vp = true, sq = seq(0, 2, 1, 1), prio = 3 }
  end, true)
  VL.def("wPopFire", function(_, v)
    local b = v == "B"
    return { tex = TX.FIRE, life = { 0.4, 0.8 }, spd = { 6, b and 26 or 14 }, spread = 35, drag = 2.5, acc = V(0, 18, 0), rot = 60,
      size = b and seq(0, 4, 0.4, 7, 1, 1.5) or seq(0, 2.5, 0.4, 4, 1, 1), tr = seq(0, 0.05, 1, 1), col = cs(0, FIRE_WHITE, 0.35, FIRE_PALE, 1, FIRE_DARK),
      le = 0.9, li = 0, bright = 3, prio = 2 }
  end, true)
  VL.def("wPopSmoke", function(_, v)
    return { tex = TX.SOOT, life = { 2.5, 4.5 }, spd = { 4, 10 }, spread = 30, drag = 1.2, acc = V(0, 5, 0), wind = true, rot = 15,
      size = seq(0, 3, 1, (v == "B") and 14 or 9), tr = seq(0, 0.1, 1, 1), col = cs(RGB(255, 255, 255)), prio = 2 }
  end, true)
  -- 转盘车殉爆前先烧：里面噼啪的火星
  VL.def("wCrackle", function()
    return { tex = TX.GLOW, life = { 0.35, 0.9 }, spd = { 18, 46 }, spread = 70, drag = 0.6, acc = V(0, -40, 0), size = seq(0, 0.35, 1, 0.08),
      tr = seq(0, 0, 1, 0.4), col = cs(RGB(255, 236, 170), RGB(255, 150, 60)), le = 1, li = 0, bright = 3, vp = true, sq = seq(0, 2, 1, 1), prio = 3 }
  end, true)
  -- 烧毁：发动机舱窜一下火、冒一大团黑烟；乘员打光：一缕黑烟
  VL.def("wFireBurst", function()
    return { tex = TX.FIRE, life = { 0.6, 1.2 }, spd = { 6, 18 }, spread = 30, drag = 2, acc = V(0, 14, 0), rot = 60, size = seq(0, 3, 0.4, 7, 1, 2),
      tr = seq(0, 0.05, 1, 1), col = cs(0, FIRE_WHITE, 0.25, FIRE_PALE, 0.55, FIRE_MID, 1, FIRE_DARK), le = 0.9, li = 0, bright = 3, prio = 1 }
  end, true)
  VL.def("wFireSmoke", function()
    return { tex = TX.SOOT, life = { 4, 7 }, spd = { 6, 14 }, spread = 25, drag = 1.2, acc = V(0, 4, 0), wind = true, rot = 15,
      size = seq(0, 5, 1, 22), tr = seq(0, 0.05, 1, 1), col = cs(RGB(255, 255, 255)), prio = 2 }
  end, true)
  VL.def("wCrewSmoke", function()
    return { tex = TX.SOOT, life = { 3, 5 }, spd = { 3, 8 }, spread = 30, drag = 1.2, acc = V(0, 3, 0), wind = true, rot = 15,
      size = seq(0, 3, 1, 12), tr = seq(0, 0.15, 1, 1), col = cs(RGB(255, 255, 255)), prio = 2 }
  end, true)
  -- 掀炮塔（View.lua 的 tossFx / landFx，审查 5：原来每次新建 3～4 个发射器、一下喷 186 颗）：座圈里冲上去的一柱火、往四周上方撒的火星、
  --   一团黑烟；炮塔砸到地上：贴地一圈冲击波、一圈土、一把火星。var B：坦克（同时还有 WreckFx 的大火球：这几层少喷）
  VL.def("tFire", function()
    return { tex = TX.FIRE, life = { 0.35, 0.8 }, spd = { 28, 60 }, spread = 14, drag = 1.5, acc = V(0, 4, 0), rot = 80,
      size = seq(0, 3.5, 0.5, 7, 1, 2), tr = seq(0, 0.05, 1, 1), col = cs(0, RGB(255, 246, 200), 0.4, RGB(255, 160, 60), 1, RGB(120, 40, 20)),
      le = 1, li = 0, bright = 3, z = 2, prio = 1 }
  end, true)
  VL.def("tSpark", function()
    return { tex = TX.GLOW, life = { 0.8, 1.8 }, spd = { 30, 70 }, spread = 60, drag = 0.4, acc = V(0, -40, 0),
      size = seq(0, 0.45, 1, 0.12), tr = seq(0, 0, 0.8, 0.2, 1, 1), col = cs(RGB(255, 210, 120)), le = 1, li = 0, bright = 3,
      vp = true, sq = seq(0, 2, 1, 0.8), prio = 3 }
  end, true)
  VL.def("tSmoke", function()
    return { tex = TX.SOOT, life = { 2.5, 4.5 }, spd = { 14, 30 }, spread = 30, drag = 1.2, acc = V(0, 2, 0), wind = true, rot = 15,
      size = seq(0, 5, 1, 20), tr = seq(0, 0.05, 1, 1), col = cs(RGB(255, 255, 255)), prio = 2 }
  end, true)
  VL.def("tRing", function()
    return { tex = TX.RING, life = { 0.5, 0.6 }, spd = { 0.05, 0.05 }, spread = 0, flat = true, size = seq(0, 3, 1, 15),
      tr = seq(0, 0.35, 1, 1), col = cs(RGB(160, 146, 124)), li = 1, prio = 3 }
  end, true)
  VL.def("tDust", function(_, v)
    local P = (G.groundPal and G.groundPal(v)) or { dust = RGB(140, 124, 98), dust2 = RGB(170, 160, 142), life = 1 }
    return { tex = TX.SMOKE, life = { 1, 2.2 }, spd = { 8, 22 }, spread = 75, drag = 2.5, acc = V(0, -4, 0), wind = true, rot = 25,
      size = seq(0, 3, 1, 11), tr = seq(0, 0.3, 1, 1), col = cs(P.dust, P.dust2), prio = 2 }
  end, true)
  VL.def("tLandSpark", function()
    return { tex = TX.GLOW, life = { 0.3, 0.7 }, spd = { 20, 40 }, spread = 80, drag = 0.5, acc = V(0, -40, 0),
      size = seq(0, 0.35, 1, 0.1), tr = seq(0, 0, 1, 0.3), col = cs(RGB(255, 200, 120)), le = 1, li = 0, bright = 3,
      vp = true, sq = seq(0, 2, 1, 0.8), prio = 3 }
  end, true)
  -- p 座圈的位置；big 坦克（WreckFx 同时画殉爆的大火球：火柱、火星、黑烟都少一点）
  function G.wreckTossFx(p, big)
    local k, d = lod(p)
    if d > 4000 then return end
    VL.emit("tFire", 1, upCF(p, UP), N(big and 16 or 30, k))
    VL.emit("tSpark", 1, upCF(p, UP), N(big and 14 or 30, k))
    VL.emit("tSmoke", 1, upCF(p, UP), N(big and 5 or 10, k))
    stat.toss += 1
  end
  -- 炮塔砸到地上
  function G.wreckLandFx(p)
    local k, d = lod(p)
    if d > 2500 then return end
    VL.emit("tRing", 1, upCF(p + V(0, 0.2, 0), UP), 1)
    VL.emit("tDust", 1, upCF(p, UP), N(14, k), codeAt(p))
    VL.emit("tLandSpark", 1, upCF(p, UP), N(14, k))
    stat.land += 1
  end

  -- 声音：闷响（服务器那声爆炸之外再叠一层低沉拖长的）、殉爆的噼啪
  local EXP = G.sndIds and G.sndIds.EXP or "rbxasset://sounds/impact_explosion_03.mp3"
  local function thump(p, d)
    if not G.sfx then return end
    local L = { { id = EXP, vol = 1.3, s = { 0.42, 0.48 }, eq = { 10, -4, -12 }, echo = { 0.35, 0.4, -6 } } }
    local RL = G.realLayer and G.realLayer("boomL", 0.78, 1.15)
    if RL then L = { RL, L[1] } end
    G.sfx(L, p, { delay = math.max(0, d - 250) / 960 + 0.04, rmin = 120, rmax = 6000, must = true })
  end
  local function pop(p, d, big)
    if not G.sfx or d > 1800 then return end
    local RL = G.realLayer and G.realLayer("boomS", big and 1.05 or (1.3 + math.random() * 0.3), big and 0.8 or 0.45)
    local L = RL and { RL } or { { id = EXP, vol = big and 0.8 or 0.45, s = big and { 1.0, 1.1 } or { 1.6, 2.1 }, reg = { 0.02, 0.6 } } }
    G.sfx(L, p, { delay = math.max(0, d - 250) / 960, rmin = 40, rmax = 2500 })
  end

  -- ① 闪光：白热的一团 + 照亮四周的大灯（Range 120，0.6 秒降到 0；离镜头 250 格内才要影子，同时只给 1 盏）——殉爆只点这一盏，白天最多 1.5 倍
  local function flashAt(p, R, d)
    if G.flash then G.flash(p + V(0, R * 0.3, 0), RGB(255, 190, 120), 120, 14, 0.6, { shadow = d < 250, day = VL.DAY_MUL_BIG }) end
    VL.emit("wFlash", R / 14, CF(p), 2)
  end
  -- ② 火球 + 浓烟 + 火星（样子 A / B / C）
  G.wreckStyleOverride = nil   -- 测试用：强制样子（"A" / "B" / "C"）
  G.wreckBlastsOverride = nil  -- 测试用：连爆炸几下（2 / 3；最费的是 3 下）
  local function fireball(p, R, k, style, L)
    local q = R / 14
    local function blast(at, m)
      VL.emit("wHeart", q, CF(at + V(0, R * 0.15, 0)), N(4 * m, k))
      VL.emit("wCore", q, CF(at), N(12 * m, k))
      VL.emit("wFire", q, CF(at), N(22 * m, k))
      VL.emit("wSoot", q, CF(at + V(0, R * 0.2, 0)), N(18 * m, k))
      VL.emit("wEdge", q, CF(at + V(0, R * 0.2, 0)), N(5 * m, k))
    end
    if style == "C" then   -- 连爆：两三下，隔 0.15～0.3 秒，位置在车里错开（后几下的闪光不另点大灯：一盏小的）
      local nb = G.wreckBlastsOverride or (2 + ((math.random() < 0.5) and 1 or 0))
      local t = 0
      for i = 1, nb do
        local off = V((math.random() - 0.5) * 0.6 * L, 0, (math.random() - 0.5) * 0.6 * L)
        if i == 1 then blast(p, 0.5) else
          t += 0.15 + math.random() * 0.15
          task.delay(t, function()
            blast(p + off, 0.5)
            VL.emit("wFlash", q * 0.7, CF(p + off), 1)
            if G.flash then G.flash(p + off + V(0, 3, 0), RGB(255, 186, 110), 40, 6, 0.3, DAY) end
          end)
        end
      end
    elseif style == "B" then   -- 座圈火柱：火球小一点，一根火柱往上冲
      blast(p, 0.7)
      VL.emit("wPillar", q, upCF(p + V(0, R * 0.2, 0), UP), N(40, k))
    else
      blast(p, 1)
    end
    VL.emit("wSpark", 1, upCF(p, UP), N(32, k))
  end

  -- ④ 地上：贴地冲击波圈、扬起一圈土
  local function groundRing(p, R, k)
    local gy = groundAt(p)
    local code = codeAt(p)
    VL.emit("wShock", R / 14, upCF(V(p.X, gy + 0.8, p.Z), UP), 1)
    VL.emit("wDust", R / 14, lookCF(V(p.X, gy + 0.8, p.Z), V(1, 0, 0)), N(16, k), code)
  end

  -- ④ 地面烧焦：软边的黑斑（烟的贴图染黑，平铺在地上）；跟着残骸，残骸没了它也没了
  local function scorch(base, L, W, parent)
    local gy = groundAt(base.Position)
    local D = math.max(L, W) * 1.5 * 1.2
    local p = Instance.new("Part")
    p.Size = V(D, 0.05, D)
    p.CFrame = CF(base.Position.X, gy + 0.06, base.Position.Z) * CFrame.Angles(0, math.random() * 6.28, 0)
    p.Transparency = 1
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    for i = 1, 2 do
      local dc = Instance.new("Decal")
      dc.Face = Enum.NormalId.Top
      dc.Texture = TX.SMOKE
      dc.Color3 = RGB(0, 0, 0)
      dc.Transparency = (i == 1) and 0.05 or 0.35
      dc.Parent = p
    end
    p.Name = "Scorch"
    p.Parent = parent or G.fxFolder or workspace
    stat.scorch += 1
    return p
  end

  ---------------------------------------------------------------- ③ 钢板碎块、负重轮
  -- 真的零件：飞出去、落地弹、拖着火和烟。Workspace.Gravity 是默认的 196.2 格/秒²（约 7 g），原来往上 28～74 格/秒只飞得起 2～14 格——
  --   每块挂一个往上的恒力（VectorForce）抵掉一部分，等于重力 45 格/秒²：往上 40～70、往旁边 15～40 格/秒，能飞二三十格高、几十格远；
  --   落地就把恒力关了（按真重力停稳），4 秒后定住（锚定、不碰撞）留到残骸没了；全局最多 40 块（满了先收最早定住的）；
  --   碰撞组 VfxChunk：只跟地形、建筑碰，不碰角色和车；一直没落地的（掉海里、卡在半空）9 秒后淡掉
  --   拖的火和烟（审查 5）：大块的都拖，小块的四分之一拖；火 8 / 6、烟 4 / 2 颗每秒，记进全局预算
  local G_EFF = 45
  local CHUNK_MAX = 40
  local chunkList = {}   -- { p, f, sm, vf, t0, land, rest, owner, burnT }
  local function killChunk(c)
    if c.p.Parent then c.p:Destroy() end
    c.dead = true
  end
  local function cap(need)
    local live = 0
    for _, c in ipairs(chunkList) do if not c.dead then live += 1 end end
    while live + need > CHUNK_MAX do
      local old = nil
      for _, c in ipairs(chunkList) do
        if not c.dead and c.rest and (not old or c.rest < old.rest) then old = c end   -- 最早定住的
      end
      if not old then break end
      killChunk(old)
      stat.capKill = (stat.capKill or 0) + 1
      live -= 1
    end
    return math.max(0, CHUNK_MAX - live)
  end
  local function massOf(part)
    local ok, m = pcall(function() return part:GetMass() end)
    if ok and type(m) == "number" and m > 0 then return m end
    local s = part.Size
    return 7.8 * s.X * s.Y * s.Z * (part:IsA("WedgePart") and 0.5 or 1)
  end
  local function lift(c)
    local a = Instance.new("Attachment")
    a.Parent = c
    local vf = Instance.new("VectorForce")
    vf.Attachment0 = a
    vf.RelativeTo = Enum.ActuatorRelativeTo.World
    vf.ApplyAtCenterOfMass = true
    vf.Force = V(0, massOf(c) * (workspace.Gravity - G_EFF), 0)
    vf.Parent = c
    return vf
  end
  -- 碎块拖的烟带（Trail）：两个附着点隔 1.2 格（宽度 = 间距 × WidthScale），越往后越宽、越淡、越灰（烟散开了）；
  --   一直对着镜头；烧完（burnT）以后不再拖新的，已经拖出来的照常淡掉。贴图是烟团，按 4 格一段重复（看上去是一团团连着的浓烟）
  local function smokeTrail(c, big)
    local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
    a0.Position, a1.Position = V(0, 0.6, 0), V(0, -0.6, 0)
    a0.Parent, a1.Parent = c, c
    local t = Instance.new("Trail")
    t.Attachment0, t.Attachment1 = a0, a1
    t.Texture = TX.SOOT
    pcall(function() t.TextureMode = Enum.TextureMode.Wrap end)
    t.TextureLength = 4
    t.FaceCamera = true
    t.Lifetime = big and 3.4 or 2.6
    t.MinLength = 0.2
    t.WidthScale = seq(0, big and 1.3 or 0.9, 0.3, big and 2.6 or 1.8, 1, big and 5 or 3.6)
    t.Transparency = seq(0, 0.2, 0.08, 0.04, 0.6, 0.35, 1, 1)
    t.Color = cs(0, RGB(255, 236, 200), 0.04, RGB(34, 31, 28), 0.5, RGB(52, 48, 44), 1, RGB(92, 88, 84))   -- 头上一点被火照亮
    t.LightEmission, t.LightInfluence = 0, 1
    t.Parent = c
    stat.trails = (stat.trails or 0) + 1
    return t
  end
  G.wreckSmokeTrail = smokeTrail   -- 测试用
  local function chunks(p, R, k, n, owner, wheels)
    n = N(n, k)
    local room = cap(n + (wheels or 0))
    n = math.min(n, room)
    for i = 1, n do
      local big = i <= 2
      local s = big and V(2.2 + math.random() * 1.4, 0.25, 1.6 + math.random()) or V(0.5 + math.random() * 1.2, 0.18 + math.random() * 0.2, 0.4 + math.random() * 0.9)
      local c = Instance.new((math.random() < 0.35) and "WedgePart" or "Part")
      c.Size = s
      c.CFrame = CF(p + V((math.random() - 0.5) * 3, 1 + math.random() * 2, (math.random() - 0.5) * 3)) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
      c.Material = Enum.Material.CorrodedMetal
      c.Color = RGB(46, 43, 40):Lerp(RGB(70, 62, 52), math.random())
      c.Anchored, c.CanCollide, c.CanQuery, c.CanTouch, c.CastShadow = false, true, false, false, true
      chunkGroup(c)
      pcall(function() c.CustomPhysicalProperties = PhysicalProperties.new(7.8, 0.6, 0.15) end)   -- 钢：重、不怎么弹（模拟器没有这个类型）
      c.Parent = G.fxFolder or workspace
      local vf = lift(c)
      -- 11-28 用户给了战雷殉爆的截图：烧着的碎块往四面八方甩出一道道弧、拖着浓黑的烟——飞得更高更远（往上 50～95、往旁边 18～55 格 / 秒）
      local ang = math.random() * 6.28
      local hs = 18 + math.random() * 37
      local lv = V(math.cos(ang) * hs, 50 + math.random() * 45, math.sin(ang) * hs)
      local av = V((math.random() - 0.5) * 18, (math.random() - 0.5) * 18, (math.random() - 0.5) * 18)
      pcall(function() c.AssemblyLinearVelocity = lv end)
      pcall(function() c.AssemblyAngularVelocity = av end)
      -- 拖着的火和黑烟：一多半烧着（原来大块 + 四分之一），每块一条烟带（Trail：连成一整道弧，不是一团团的烟——颗粒不算进预算）
      --   + 头上的火、稀稀的几团烟（落地以后接着冒一会儿）
      local f, sm, tr
      local burnT = 2.5 + math.random() * 3
      if big or math.random() < 0.55 then
        f = emitter(c, { tex = TX.FIRE, rate = big and 8 or 5, secs = burnT, life = { 0.25, 0.5 }, spd = { 0.5, 2 }, spread = 40, acc = V(0, 6, 0),
          size = seq(0, big and 2.2 or 1.4, 1, 0.3), tr = seq(0, 0.1, 1, 1), col = cs(0, FIRE_WHITE, 0.35, FIRE_PALE, 1, FIRE_DARK), le = 0.9, li = 0, bright = 3, prio = 2 })
        sm = emitter(c, { tex = TX.SOOT, rate = big and 2 or 1, secs = 11, life = { 1.4, 2.6 }, spd = { 0.5, 2 }, spread = 30, acc = V(0, 3, 0), drag = 0.8, wind = true,
          size = seq(0, big and 1.6 or 1, 1, big and 6 or 4), tr = seq(0, 0.1, 1, 1), col = cs(RGB(255, 255, 255)), rot = 20, prio = 2 })
        tr = smokeTrail(c, big)
      end
      table.insert(chunkList, { p = c, f = f, sm = sm, tr = tr, vf = vf, t0 = os.clock(), owner = owner, burnT = burnT })
      stat.chunks += 1
    end
    -- 负重轮（战雷 Drone Age：飞出去的零件里有主动轮、负重轮，拖着烟，落地还会滚）
    for _ = 1, math.min(wheels or 0, math.max(0, room - n)) do
      local w = Instance.new("Part")
      w.Shape = Enum.PartType.Cylinder
      w.Size = V(0.8, 2.2, 2.2)
      w.CFrame = CF(p + V((math.random() - 0.5) * 4, 0.5, (math.random() - 0.5) * 4)) * CFrame.Angles(0, math.random() * 6.28, 0)
      w.Material = Enum.Material.CorrodedMetal
      w.Color = RGB(40, 38, 36)
      w.Anchored, w.CanCollide, w.CanQuery, w.CanTouch, w.CastShadow = false, true, false, false, true
      chunkGroup(w)
      pcall(function() w.CustomPhysicalProperties = PhysicalProperties.new(7.8, 0.5, 0.25) end)
      w.Parent = G.fxFolder or workspace
      local vf = lift(w)
      local ang = math.random() * 6.28
      local hv = 20 + math.random() * 15
      pcall(function() w.AssemblyLinearVelocity = V(math.cos(ang) * hv, 22 + math.random() * 12, math.sin(ang) * hv) end)
      pcall(function() w.AssemblyAngularVelocity = V(0, 0, (math.random() - 0.5) * 30) end)
      local burnT = 3 + math.random() * 2
      local sm = emitter(w, { tex = TX.SOOT, rate = 4, secs = burnT + 1, life = { 1.6, 2.8 }, spd = { 0.5, 2 }, spread = 30, acc = V(0, 3, 0), drag = 0.8, wind = true,
        size = seq(0, 1.2, 1, 5), tr = seq(0, 0.1, 1, 1), col = cs(RGB(255, 255, 255)), rot = 20, prio = 2 })
      table.insert(chunkList, { p = w, sm = sm, vf = vf, t0 = os.clock(), owner = owner, burnT = burnT, wheel = true })
      stat.wheels += 1
    end
  end
  G.wreckChunks = function(p, R, k, n) return chunks(p, R, k, n, nil, 0) end   -- Fx.lua 的 boom（飞机、舰被打爆那一类）也用真碎块
  G.wreckChunkList = function() return chunkList end   -- 测试用
  G.wreckChunkMax = CHUNK_MAX
  -- 碎块每秒看 10 次：落地关恒力、4 秒后定住；火烧几秒灭、烟变稀；没落地的淡掉；残骸没了的收掉
  local chT = 0
  RunService.RenderStepped:Connect(function(dt)
    if #chunkList == 0 then return end
    chT += dt
    if chT < 0.1 then return end
    chT = 0
    local now = os.clock()
    for i = #chunkList, 1, -1 do
      local c = chunkList[i]
      local part = c.p
      if c.dead or not part.Parent then
        table.remove(chunkList, i)
      else
        local age = now - c.t0
        if c.f and age > c.burnT and c.f.Enabled then c.f.Enabled = false end
        if c.tr and c.tr.Enabled and (age > c.burnT + 1.5 or (c.land and now - c.land > 0.5)) then c.tr.Enabled = false end   -- 烧完 / 落地：不再拖新的烟带
        if c.sm and not c.smThin and age > c.burnT + 1 then
          c.smThin = true
          c.sm.Rate = c.wheel and 0 or math.min(c.sm.Rate, 1.5)
        end
        if c.sm and age > 11 and c.sm.Enabled then c.sm.Enabled = false end
        if not c.land then
          local pos = part.Position
          local vel = V()
          pcall(function() vel = part.AssemblyLinearVelocity end)
          -- 落在房顶、车壳上的（不在地面）：慢下来半秒也算落地
          if age > 1 and vel.Magnitude < 3 then c.slow = (c.slow or 0) + 0.1 else c.slow = 0 end
          if (age > 0.3 and pos.Y < groundAt(pos) + 2.5 and vel.Y < 2) or c.slow >= 0.5 then
            c.land = now
            if c.vf then c.vf.Enabled = false end
            if Map.height(pos.X, pos.Z) < -0.5 then   -- 掉进海里：沉了
              killChunk(c)
            end
          elseif age > 9 and not c.fade then   -- 一直没落地（卡在半空）：淡掉
            c.fade = true
            TweenService:Create(part, TweenInfo.new(2.5), { Transparency = 1 }):Play()
            Debris:AddItem(part, 2.6)
          end
        elseif not c.rest and now - c.land > 4 then
          local sp = 0
          pcall(function() sp = part.AssemblyLinearVelocity.Magnitude end)
          if sp < 4 or now - c.land > 7 then
            c.rest = now
            part.Anchored = true
            part.CanCollide = false
            if c.vf then c.vf:Destroy() c.vf = nil end
            stat.anchored += 1
            if not c.owner then   -- 没有残骸跟着的（飞机、舰的碎块）：再留几秒淡掉
              task.delay(4, function()
                if part.Parent then TweenService:Create(part, TweenInfo.new(2.5), { Transparency = 1 }):Play() end
              end)
              Debris:AddItem(part, 6.6)
            end
          end
        elseif c.rest and c.owner and not c.owner.Parent then   -- 残骸没了：一起收掉
          killChunk(c)
        end
      end
    end
  end)

  -- ⑤ 车里剩下的弹一发一发殉爆（越来越稀）；舱口往外蹿火（前几秒）
  local function cookOff(v, base, L, W, H, k, d)
    local n = N(9, math.min(1, k + 0.2))
    local t = 0.35
    for i = 1, n do
      t += 0.25 + math.random() * 0.55 * (1 + i / n)
      task.delay(t, function()
        if not (v.M and v.M.model and v.M.model.Parent) then return end
        local q = base.Position + base.RightVector * ((math.random() - 0.5) * W * 0.6) + base.LookVector * ((math.random() - 0.5) * L * 0.6) + V(0, H * (0.75 + math.random() * 0.35), 0)
        local bigOne = (i % 4 == 0)
        local var = bigOne and "B" or nil
        if G.flash then G.flash(q, RGB(255, 186, 110), bigOne and 34 or 20, bigOne and 7 or 4, 0.18, DAY) end
        VL.emit("wPopFlash", 1, CF(q), 1, var)
        VL.emit("wPopSpark", 1, upCF(q, UP), bigOne and 22 or 10, var)
        VL.emit("wPopFire", 1, upCF(q, UP), bigOne and 9 or 5, var)
        VL.emit("wPopSmoke", 1, upCF(q, UP), bigOne and 5 or 3, var)
        pop(q, d, bigOne)
        stat.pops += 1
      end)
    end
  end
  local function hatchJet(base, H, secs, strong)
    local p = base.Position + V(0, H + 0.5, 0)
    local h = holder(CFrame.lookAt(p, p + V(0, 1, 0)))
    local f = emitter(h, { tex = TX.FIRE, rate = strong and 26 or 16, secs = secs + secs * 1.2 * 0.3, life = { 0.45, 0.9 }, spd = { strong and 16 or 9, strong and 34 or 18 }, spread = 14,
      dir = Enum.NormalId.Front, drag = 1.5, acc = V(0, 8, 0), size = seq(0, 2.6, 0.4, strong and 6 or 4, 1, 1.5), tr = seq(0, 0.05, 0.7, 0.35, 1, 1),
      col = cs(0, FIRE_WHITE, 0.3, FIRE_PALE, 0.6, FIRE_MID, 1, FIRE_DARK), le = 0.95, li = 0, bright = 3.5, rot = 80, z = 2, prio = 1 })
    stat.jets += 1
    task.delay(secs, function() f.Rate = f.Rate * 0.3 end)
    task.delay(secs * 2.2, function() f.Enabled = false end)
    Debris:AddItem(h, secs * 2.2 + 1.2)
  end

  -- ⑥ 车身的大火、烟柱：View.lua 的 fire / black 发射器（平时关着）调粗、调黑、升高、顺风；fire 的贴图本身暗：LightInfluence 0 + Brightness 3；
  --   black 换成深灰的烟贴图、受光照、跟着风。
  --   镜头 60 格内黑烟小一号（审查 7：原来是改 Size——Size 是整条曲线，一改连已经在飘的四十来颗一起缩放，走过那条线整根烟柱一下变小）：
  --   两个发射器，M.black 远处那根、M.blackN 小一号的那根，View.lua 按远近换着喷（G.wreckBlackRate：一个给 Rate、另一个 0）
  --   每辆车稳定时（View.lua 的节奏，用户 11-28「然后有浓烈的烟雾我持续冒」）：前 60 秒 fire 30 + black 8，60 秒后 14 + 7，150 秒以后 5 + 5 一直冒到残骸没了；
  --   同时冒浓烟的最多 10 处，再早的 black 2.5（还是一根烟柱）
  local function blackRate(M, r, near)
    if r ~= nil then M.blackRate = r end
    if near ~= nil then M.blackIsNear = near end
    local rr = M.blackRate or 0
    local b, bn = M.black, M.blackN
    local useN = M.blackIsNear == true and bn ~= nil
    if b and b.Rate ~= (useN and 0 or rr) then b.Rate = useN and 0 or rr end
    if bn and bn.Rate ~= (useN and rr or 0) then bn.Rate = useN and rr or 0 end
  end
  G.wreckBlackRate = blackRate
  local function prepBurn(M)
    local f, b = M.fire, M.black
    if f and not M.burnPrep then
      f.LightEmission, f.LightInfluence, f.Brightness = 0.9, 0, 3
    end
    if b and not M.burnPrep then
      b.Texture = TX.SOOT
      b.LightInfluence = 1
      b.Color = cs(RGB(255, 255, 255))
      b.Drag = 0.35
      pcall(function() b.WindAffectsDrag = true end)
      local ok, bn = pcall(function() return b:Clone() end)   -- 近处那根（小一号）：同一个零件上，平时不喷
      if ok and bn then
        bn.Name = "BlackNear"
        bn.Rate = 0
        bn.Parent = b.Parent
        M.blackN = bn
      end
    end
    M.burnPrep = true
  end
  G.wreckPrepBurn = prepBurn
  local function heavyBurn(M, strong)
    prepBurn(M)
    local f, b, bn = M.fire, M.black, M.blackN
    if f then
      f.Size = seq(0, strong and 6 or 4.5, 0.4, strong and 9 or 7, 1, 2)
      f.Lifetime = NumberRange.new(0.5, 1.0)
      f.Speed = NumberRange.new(5, 11)
      f.SpreadAngle = Vector2.new(25, 25)
      f.Acceleration = V(0, 7, 0)
      f.Transparency = seq(0, 0.05, 0.6, 0.35, 1, 1)
      f.Color = cs(0, FIRE_WHITE, 0.25, FIRE_PALE, 0.55, FIRE_MID, 1, FIRE_DARK)
      f.RotSpeed = NumberRange.new(-60, 60)
      f.Rotation = NumberRange.new(0, 360)
    end
    local acc = V(0, 2.4, 0)
    if VL.wind().Magnitude < 0.5 then acc = V(2.6, 2.4, 1.2) end   -- 地图没设风：照旧写死顺风歪过去
    -- 烟柱（11-28 用户「浓烈的烟雾我持续冒」）：粗一点、高一点（活 5.5～8.5 秒、往上冲得快一点，四五十米高的一根），越往上越大越淡、顺风歪
    local s0, s1, s2 = strong and 7 or 5, strong and 16 or 12, strong and 42 or 31   -- 11-28 晚：最上面 50 → 42 格（卡：烟团越大要画的像素越多）
    for _, e in ipairs({ b or false, bn or false }) do
      if e then
        local kk = (e == bn) and 0.7 or 1
        e.Lifetime = NumberRange.new(5.5, 8.5)
        e.Speed = NumberRange.new(9, 15)
        e.SpreadAngle = Vector2.new(12, 12)
        e.Acceleration = acc
        e.Size = seq(0, s0 * kk, 0.25, s1 * kk, 1, s2 * kk)
        e.Transparency = seq(0, 0.05, 0.3, 0.1, 0.75, 0.5, 1, 1)
        e.RotSpeed = NumberRange.new(-12, 12)
        e.Rotation = NumberRange.new(0, 360)
      end
    end
    if b then
      local r = b.Rate + ((bn and bn.Rate) or 0)
      local BR = G.wreckBurnRates   -- 殉爆、烧毁的：烟柱至少是头一分钟那一档（转盘车先烧那几秒是 6）
      if strong and BR then r = math.max(r, BR.black[1]) end
      blackRate(M, r)
    end
  end

  -- 样子 A / B / C：按车的编号定（大家看到的一样）
  local function styleOf(v)
    -- 编号先按字符串散列（同 WtDamage.cookSecs），再乘黄金分割常数取小数：相邻的编号也分得开，各个客户端算出来一样
    local h = 0
    for ch in tostring(v.id or ""):gmatch(".") do h = (h * 31 + string.byte(ch)) % 1000003 end
    local x = ((h * 2654435761) % 4294967296) / 4294967296
    return (x < 0.5 and "A") or (x < 0.78 and "B") or "C"
  end
  G.wreckStyleOf = styleOf

  -- 转盘车先烧的那两个舱口：炸开以后火小到四分之一、烟 2 颗每秒（只做一次）
  local function cookJetsDown(jets)
    if not jets or jets.done then return end
    jets.done = true
    for _, j in ipairs(jets) do
      if j.f.Parent then
        j.f.Rate = j.f.Rate * 0.25
        j.s.Rate = 2
      end
    end
  end
  -- 转盘车殉爆前先烧（用户 11-26「部分弹药架在下面的坦克被干掉炮塔飞起来吧 然后要先着火再飞」）：发射药一着火，
  --   车长、炮长两个舱口往上喷火（越烧越旺、越喷越高），里面噼啪乱响、火星乱溅，火光一闪一闪，黑烟往上冒；
  --   secs 秒后 View.lua 掀炮塔、G.wreckFx 画大火球（同一刻）——炸开那一刻舱口的火小到四分之一接着烧（这辆车不再另加 hatchJet）
  function G.wreckCook(v, base, secs)
    local d0 = v.def or {}
    local M = v.M or {}
    if not base then return end
    local L, W, H = d0.L or 20, d0.W or 10, d0.hullH or (d0.H or 8) * 0.6
    local tp = d0.turret and d0.turret.pivot
    local top = base.Position + V(0, (tp and tp.Y or H) + (d0.turret and 2.2 or 0.6), 0)
    local p = base.Position + V(0, H * 0.7, 0)
    local k, d = lod(p)
    if d > 4000 then return end   -- 太远：不接手（没设 v.cookJets）——View.lua 照别的残骸马上把车身的火、黑烟烧起来
    stat.cook = (stat.cook or 0) + 1
    prepBurn(M)
    v.cookJets = true
    -- 两个舱口：炮塔顶左右各一个（按车宽）
    local jets = {}
    for _, sx in ipairs({ -0.22, 0.2 }) do
      local q = top + base.RightVector * (W * sx) - base.LookVector * (L * 0.02)
      local h = holder(CFrame.lookAt(q, q + V(0, 1, 0)))
      local f = emitter(h, { tex = TX.FIRE, rate = 10, secs = secs + 5, life = { 0.35, 0.7 }, spd = { 6, 12 }, spread = 10, dir = Enum.NormalId.Front,
        drag = 1.4, acc = V(0, 8, 0), size = seq(0, 1.6, 0.4, 3, 1, 1), tr = seq(0, 0.05, 0.7, 0.35, 1, 1),
        col = cs(0, FIRE_WHITE, 0.3, FIRE_PALE, 0.6, FIRE_MID, 1, FIRE_DARK), le = 0.95, li = 0, bright = 3.5, rot = 80, z = 2, prio = 1 })
      local s2 = emitter(h, { tex = TX.SOOT, rate = 3, secs = secs + 5, life = { 2.5, 4 }, spd = { 5, 9 }, spread = 14, drag = 1, acc = V(0, 4, 0), wind = true,
        size = seq(0, 2, 1, 10), tr = seq(0, 0.1, 1, 1), col = cs(RGB(255, 255, 255)), rot = 15, prio = 2 })
      table.insert(jets, { h = h, f = f, s = s2, r = -1 })
      Debris:AddItem(h, secs + 5)
    end
    v.cookJetList = jets   -- 炸开那一刻（G.wreckFx）马上小下去，不等下面那圈 0.25 秒一看
    -- 越烧越旺：喷得越来越高、越来越密（每 0.25 秒看一次、变化过一成才写；原来每 0.1 秒改一遍）
    local t0 = os.clock()
    VL.rateK(2 * 30, secs, 0.7, 1)   -- 越烧越旺那段多出来的（平均每个舱口多 30 颗 / 秒）也记进全局预算
    task.spawn(function()
      while os.clock() - t0 < secs and not jets.done do
        local q = math.clamp((os.clock() - t0) / secs, 0, 1)
        for _, j in ipairs(jets) do
          local r = 10 + 46 * q
          if j.f.Parent and math.abs(r - j.r) > j.r * 0.1 then
            j.r = r
            j.f.Rate = r
            j.f.Speed = NumberRange.new(6 + 18 * q, 12 + 30 * q)
            j.f.Size = seq(0, 1.6 + 1.6 * q, 0.4, 3 + 4 * q, 1, 1.4)
            j.s.Rate = 3 + 6 * q
          end
        end
        task.wait(0.25)
      end
      cookJetsDown(jets)   -- 炸开那一下之后火小下去（大火由 heavyBurn 接着烧）；G.wreckFx 那边先到就已经小下去了
    end)
    -- 里面噼啪：零星的小殉爆（火星、闪一下、一声脆响），越到后面越密
    local t = 0.15
    while t < secs - 0.15 do
      local tt = t
      task.delay(tt, function()
        if not (M.model and M.model.Parent) then return end
        local q = top + base.RightVector * ((math.random() - 0.5) * W * 0.5) + V(0, -1 + math.random(), 0)
        VL.emit("wCrackle", 1, upCF(q, UP), N(14, k))
        if G.flash then G.flash(q, RGB(255, 170, 90), 18, 3, 0.12) end
        pop(q, d, false)
      end)
      t += 0.45 - 0.25 * (t / secs) + math.random() * 0.2
    end
    -- 车身也烧起来（View.lua 的 fire / black：先小、炸开以后 heavyBurn 调大）
    if M.fire then M.fire.Rate = 14 end
    if M.black then blackRate(M, 6) end
  end

  local liveBig = 0
  -- v：View.lua 的车（v.M 模型、v.def 型号）；why：服务器的 WtWhy（"ammo" 殉爆、"fire" 烧毁、"crew" 乘员打光、nil 老式血量打光）；base：车底的 CFrame
  function G.wreckFx(v, why, base)
    local d0 = v.def or {}
    local M = v.M or {}
    if not base then return end
    local L, W, H = d0.L or 20, d0.W or 10, d0.hullH or (d0.H or 8) * 0.6
    local p = base.Position + V(0, H * 0.7, 0)
    local k, d, tl = lod(p)
    if d > 6000 then return end
    local ammo = why == "ammo" or (why == nil and d0.cat == "tank")
    if ammo then
      -- 火球半径（格）：用户 11-28 给了战雷殉爆的截图（离得近时火球占满大半个屏幕）——原来车长的 0.55 倍（主战坦克 11 格、约 4 米）太小，
      --   改成约一个车长（主战坦克 20 格上下、约 7 米）；各层的速度、大小都按它放大，颗数不变（第一秒的预算照旧）
      local R = math.clamp(math.max(L, W) * 1.0, 13, 28)
      stat.lastR = R
      local style = G.wreckStyleOverride or styleOf(v)
      stat.big += 1
      stat.style[style] = (stat.style[style] or 0) + 1
      stat.last = style
      flashAt(p, R, d)
      if tl <= 3 then fireball(p, R, k, style, L) end
      if tl <= 2 then groundRing(p, R, k) end
      thump(p, d)
      if d < 1500 and liveBig < 3 then
        liveBig += 1
        task.delay(16, function() liveBig -= 1 end)
        chunks(p, R, k, 14, M.model, (d0.arch == "tracked") and (1 + ((style == "C") and 1 or 0)) or 0)
      end
      if v.cookJets then cookJetsDown(v.cookJetList) else hatchJet(base, H, 3.5, true) end   -- 转盘车先烧的那两个舱口还在喷：小下去接着喷，不另加
      cookOff(v, base, L, W, H, k, d)
      if G.shake then
        local shR = 260
        if d < shR then G.shake(0.9 * (1 - d / shR)) end
      end
      heavyBurn(M, true)
      -- 车身大火先小一点（第一秒火球、碎块、舱口火柱都在喷），两秒半以后照 View.lua 的节奏烧到头一分钟那一档（G.wreckBurnRates.fire[1]）
      if M.fire then
        M.fire.Rate = 10
        task.delay(2.5, function()
          local full = (G.wreckBurnRates and G.wreckBurnRates.fire[1]) or 26
          if M.fire and M.fire.Parent and not v.burnt1 and M.fire.Rate < full then M.fire.Rate = full end
        end)
      end
    elseif why == "fire" then
      local q = base.Position - base.LookVector * L * 0.3 + V(0, H, 0)   -- 发动机舱在后面
      VL.emit("wFireBurst", 1, upCF(q, UP), N(18, k))
      VL.emit("wFireSmoke", 1, upCF(q, UP), N(10, k))
      if G.flash then G.flash(q, RGB(255, 170, 90), 30, 5, 0.4, DAY) end
      hatchJet(base, H, 2.5, false)
      heavyBurn(M, true)
    else   -- 乘员打光：车停下、一缕黑烟
      VL.emit("wCrewSmoke", 1, upCF(p, UP), N(6, k))
      heavyBurn(M, false)
    end
    -- 地面烧焦（殉爆、烧毁的）：跟着残骸的模型，残骸没了一起没
    if (ammo or why == "fire") and M.model then
      local ok = pcall(scorch, base, L, W, M.model)
      if not ok then scorch(base, L, W) end
    end
  end

  -- 预建（审查 12）：殉爆、掀炮塔那几层进局时分几帧建好（11-28 火球放大以后主战坦克的半径 17～24 格：q 1.2 / 1.44 两档），第一次殉爆不用现建；
  --   贴地那圈土按地面分（土、草、沙、石；雪山加雪）——地图进服以后才投出来的，换图（G.onMap）时补排新地面的（同 Fx.lua）
  do
    local list = {}
    local warmed = {}
    local function dustFor(code)
      if warmed[code] then return end
      warmed[code] = true
      for _, q in ipairs({ 1.2, 1.44 }) do list[#list + 1] = { "wDust", q, code } end
      list[#list + 1] = { "tDust", 1, code }
    end
    local function mapCodes() return Map.NAME == "snow" and { "d", "v", "r", "i" } or { "d", "v", "n", "r" } end
    for _, q in ipairs({ 1.2, 1.44 }) do
      for _, nm in ipairs({ "wFlash", "wHeart", "wCore", "wFire", "wSoot", "wEdge", "wPillar", "wShock" }) do list[#list + 1] = { nm, q } end
    end
    list[#list + 1] = { "wFlash", 1 }   -- 连爆后几下的小闪光（q × 0.7）
    for _, nm in ipairs({ "wSpark", "wCrackle", "wFireBurst", "wFireSmoke", "wCrewSmoke", "tFire", "tSpark", "tSmoke", "tRing", "tLandSpark" }) do list[#list + 1] = { nm, 1 } end
    for _, nm in ipairs({ "wPopFlash", "wPopSpark", "wPopFire", "wPopSmoke" }) do
      list[#list + 1] = { nm, 1 }
      list[#list + 1] = { nm, 1, "B" }
    end
    for _, code in ipairs(mapCodes()) do dustFor(code) end
    VL.prewarmLater(list)
    if G.onMap then
      G.onMap(function()
        list = {}
        for _, code in ipairs(mapCodes()) do dustFor(code) end
        if #list > 0 then VL.prewarmLater(list) end
      end)
    end
  end
end

return WreckFx
