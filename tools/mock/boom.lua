-- 武器音效、爆炸效果测试（模拟器）：python3 tools/mock/run.py tools/mock/boom.lua [v]
--   用户：所有飞机开火声音都是枪声；导弹、炮弹爆炸效果都很小，要按不同武器改
--   ① 爆炸按武器分：航炮一点火光，炮弹、导弹、炸弹一档比一档大（火球、尘土柱、烟柱）；海面上是水柱；半空是一团火 + 黑烟
--   ② 服务器的爆炸带类别（炸弹 bomb、导弹 msl、炮弹 shell、航炮 gun、被击毁 wreck）
--   ③ 自己开飞机：航炮按住一直响（循环起爆那一小段，一圈一发）、松开停；火箭弹、导弹各一种声音，不是步枪的声音
--   ④ 别人开的飞机：航炮声在炮口那里，停火 0.25 秒后停；导弹的发动机声挂在弹上跟着飞，烧完停；扔炸弹「咣」一声
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 120)
local me = T.join("P1", 6101, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
R.run(1)
local C = T.C
T.act("deploy", "rifle", "af2")
R.run(2)
check(P.alive, "出生了")
local FXF = R.services.Workspace:FindFirstChild("ClientFx")
local SS = R.services.SoundService
local EXP = "rbxasset://sounds/impact_explosion_03.mp3"

-- 一件事之后客户端特效文件夹里新出来的零件
local function fresh(f)
  local before = {}
  for _, c in ipairs(FXF:GetChildren()) do before[c] = true end
  f()
  local out = {}
  for _, c in ipairs(FXF:GetChildren()) do if not before[c] then out[#out + 1] = c end end
  return out
end
-- 这些零件上的粒子：几组、最大的一颗多大、用了哪些贴图、有没有平躺的圈
local function stats(list)
  local n, big, tex, flat, sounds = 0, 0, {}, false, {}
  for _, h in ipairs(list) do
    for _, x in ipairs(h:GetChildren()) do
      if x.ClassName == "ParticleEmitter" then
        n = n + 1
        local nm = x.Texture:match("([%w_]+)%.%w+$") or x.Texture
        tex[nm] = true
        for _, k in ipairs(x.Size.Keypoints or {}) do if k.Value > big then big = k.Value end end
        if x.Orientation == Enum.ParticleOrientation.VelocityPerpendicular then flat = true end
      elseif x.ClassName == "Sound" then
        sounds[#sounds + 1] = x
      end
    end
  end
  return { n = n, big = big, tex = tex, flat = flat, sounds = sounds }
end
local function texList(t)
  local o = {}
  for k in pairs(t) do o[#o + 1] = k end
  table.sort(o)
  return table.concat(o, ",")
end

local hrp = me.Character:FindFirstChild("HumanoidRootPart")
local base = hrp.Position
local function ground(dx, dz)
  local x, z = base.X + dx, base.Z + dz
  return V3(x, G.Map.ground(x, z) + 0.5, z)
end
-- 镜头放在人旁边（模拟器的镜头不跟人走）
local cam = R.services.Workspace.CurrentCamera
cam.CFrame = R.CFrame.lookAt(base + V3(0, 30, 120), base)

print("① 爆炸按武器分大小")
local S = {}
for _, it in ipairs({ { "gun", 0.3, 0 }, { "shell", 0.5, 60 }, { "msl", 1.3, -60 }, { "bomb", 2.5, 120 } }) do
  local c, s, dx = it[1], it[2], it[3]
  local list = fresh(function() R.as("client", function() C.boom(ground(dx, -30), s, c) end) end)
  S[c] = stats(list)
  print(string.format("    %-5s 粒子 %2d 组、最大一颗 %5.1f 格、贴图 %s、声音 %d 个", c, S[c].n, S[c].big, texList(S[c].tex), #S[c].sounds))
end
check(S.gun.n >= 2 and S.gun.big < 12 and not S.gun.tex.explosion01_core_main, "航炮弹：一点火光、几颗火星、一小团土，没有大火球")
check(S.shell.tex.explosion01_core_main and S.shell.tex.SquareParticle and S.shell.tex.smoke_main, "炮弹：火球、碎块、尘土和烟")
check(S.shell.big > S.gun.big and S.msl.big > S.shell.big * 1.5 and S.bomb.big > S.msl.big * 1.4,
  string.format("一档比一档大（航炮 %.0f < 炮弹 %.0f < 导弹 %.0f < 炸弹 %.0f）", S.gun.big, S.shell.big, S.msl.big, S.bomb.big))
check(S.msl.flat and S.bomb.flat and S.bomb.tex.explosion01_shockwave_main, "导弹、炸弹在地上：贴地一圈冲击波")
check(S.bomb.tex.fire_main, "炸弹炸完弹坑里还烧一会儿")
check(S.bomb.big >= 60, string.format("炸弹的烟尘柱够大（%.0f 格，约 %.0f 米）", S.bomb.big, S.bomb.big / 2.8))

-- 声音：近处的不晚到，按大小变调（炸弹低沉两层、航炮弹脆）
local function speeds(list)
  local o = {}
  for _, s in ipairs(list) do if s.SoundId == EXP then o[#o + 1] = s.PlaybackSpeed end end
  return o
end
local bombSp, gunSp = speeds(S.bomb.sounds), speeds(S.gun.sounds)
R.run(0.3)
local bombAll = 0
for _, h in ipairs(FXF:GetChildren()) do for _, x in ipairs(h:GetChildren()) do if x.ClassName == "Sound" and x.SoundId == EXP and x.PlaybackSpeed < 0.7 then bombAll = bombAll + 1 end end end
check(#gunSp >= 1 and gunSp[1] > 1.4, "航炮弹的爆炸声脆（变调 " .. tostring(gunSp[1]) .. "）")
check(#bombSp >= 1 and bombSp[1] < 0.7 and bombAll >= 2, string.format("炸弹的爆炸声低沉（变调 %.2f），还叠一层滚雷似的闷响（%d 层）", bombSp[1] or 0, bombAll))

print("② 海面上是水柱；半空炸是一团火和黑烟（没有土、没有贴地的圈）")
local sea = nil
for d = 800, 20000, 400 do
  local x, z = base.X, base.Z + d
  if G.Map.height(x, z) < -3 then sea = V3(x, 0.5, z) break end
end
check(sea ~= nil, "找到一块海面")
if sea then
  cam.CFrame = R.CFrame.lookAt(sea + V3(0, 40, 200), sea)
  local w = stats(fresh(function() R.as("client", function() C.boom(sea, 1.3, "shell") end) end))
  local white = false
  check(w.flat and not w.tex.SquareParticle, "海面：水柱、水雾、平躺的一圈白沫，没有土块（贴图 " .. texList(w.tex) .. "）")
  local hasWater = false
  for _, s in ipairs(w.sounds) do if s.SoundId:find("impact_water") then hasWater = true end end
  R.run(0.2)
  for _, h in ipairs(FXF:GetChildren()) do for _, x in ipairs(h:GetChildren()) do if x.ClassName == "Sound" and x.SoundId:find("impact_water") then hasWater = true end end end
  check(hasWater, "海面爆炸有哗的一声水响")
end
local sky = base + V3(0, 260, 0)
cam.CFrame = R.CFrame.lookAt(sky + V3(0, 0, 150), sky)
local a = stats(fresh(function() R.as("client", function() C.boom(sky, 0.7, "flak") end) end))
check(a.tex.smoke_main and not a.tex.SquareParticle and not a.flat, "半空（高炮）：一团火、一团黑烟，没有土块和贴地的圈")
cam.CFrame = R.CFrame.lookAt(base + V3(0, 30, 120), base)

print("③ 服务器的爆炸带类别")
local got = {}
local onFx0 = C.onFx
C.onFx = function(list)
  for _, e in ipairs(list) do if e.k == "boom" then got[#got + 1] = e end end
  return onFx0(list)
end
local mk82 = { kind = "bomb", dmg = 1100, splash = 30 }
G.explode(ground(0, -400), mk82, nil)
G.explode(ground(30, -400), { kind = "agm", dmg = 900, splash = 10 }, nil)
G.explode(ground(60, -400), { kind = "shell", dmg = 600, splash = 6 }, nil)
G.explode(ground(90, -400), { dmg = 20, splash = 3, boom = "gun" }, nil, 0.3)
R.run(0.3)
local kinds = {}
for _, e in ipairs(got) do kinds[#kinds + 1] = tostring(e.c) end
local ks = table.concat(kinds, ",")
check(ks:find("bomb") and ks:find("msl") and ks:find("shell") and ks:find("gun"), "客户端收到的爆炸带类别：" .. ks)
C.onFx = onFx0

print("④ 自己开飞机：航炮按住响、松开停；火箭弹、导弹各一种声音")
local calls = {}
local sfx0 = C.sfx
C.sfx = function(def, pos, o)
  calls[#calls + 1] = (type(def) == "string") and def or "爆炸"
  return sfx0(def, pos, o)
end
local A2 = G.Map.AFIELD2
local x, z = A2.x + 300, A2.z - A2.wid / 2 - 200
local gy = G.airSurface(x, z)
local e = G.spawnAircraft("atk", "ah64e", CF(x, gy + 6, z), C.AD.presetLoad(C.AD.get("ah64e"), "mix"), P)   -- 混挂：外侧导弹、内侧火箭巢（原来是直-10，11-27 删了）
check(e ~= nil, "放了一架阿帕奇（航炮、火箭巢、导弹）")
if e then
  me.Character:PivotTo(CF(x + 20, gy + 3.5, z))
  R.run(0.3)
  T.act("enterVeh", e.id)
  R.run(1)
  local st = C.fly
  check(st ~= nil and P.vehicle == e, "坐进了直升机")
  T.runUntil(function() return G.round.phase == "battle" end, 60)
  check(G.round.phase == "battle", "开战了（开战以后才能开火）")
  if st then
    local function loopSnd()
      for _, s in ipairs(SS:GetChildren()) do if s.ClassName == "Sound" and s.Looped then return s end end
    end
    T.tap(Enum.KeyCode.One)
    R.run(0.2)
    T.mouse(true)
    R.run(0.6)
    local s = loopSnd()
    local w = C.AD and C.AD.W[e.def.gun] or nil
    check(s ~= nil and s.SoundId == EXP and s.PlaybackRegionsEnabled, "按住开火：航炮循环声响着（" .. tostring(e.def.gun) .. "）")
    if s then
      local per = (s.LoopRegion.Max - s.LoopRegion.Min) / s.PlaybackSpeed
      local rate = w and w.rate or 0.1
      check(math.abs(per - rate) < 0.002, string.format("循环一圈 %.3f 秒 = 一发（射速 %.3f 秒一发）", per, rate))
    end
    local a0 = e.gunAmmo
    R.run(1)
    check(e.gunAmmo < a0, string.format("服务器那边真在打（炮弹 %d → %d）", a0, e.gunAmmo))
    T.mouse(false)
    R.run(0.3)
    check(loopSnd() == nil, "松开就停")
    -- 火箭巢、导弹
    local function pick(kind)
      for i, wid in ipairs(st.wl) do
        local ww = C.AD and C.AD.W[wid]
        if ww and ww.kind == kind then return i end
      end
    end
    local ri, mi = pick("rkt"), pick("agm")
    calls = {}
    if ri then
      T.tap(({ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four })[ri])
      R.run(0.2)
      T.key(Enum.KeyCode.F, true)   -- 挂载按 F 发（左键是机炮，keen-heisenberg 改的键位）
      R.run(0.5)
      T.key(Enum.KeyCode.F, false)
      R.run(0.3)
    end
    local nR = 0
    for _, c in ipairs(calls) do if c == "rkt" then nR = nR + 1 end end
    check(ri and nR >= 2, "火箭弹：按住连发，每发「噗」一声 + 呼的一下（" .. nR .. " 次）")
    calls = {}
    if mi then
      T.tap(({ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four })[mi])
      R.run(0.2)
      T.key(Enum.KeyCode.F, true)
      R.run(0.1)
      T.key(Enum.KeyCode.F, false)
      R.run(0.5)
    end
    local nM, dup = 0, 0
    for _, c in ipairs(calls) do if c == "msl" then nM = nM + 1 end end
    check(mi and nM == 1, "导弹：低沉的点火声 + 呼啸，只放一遍（服务器发回来的不再放，" .. nM .. " 次）")
  end
end
C.sfx = sfx0

print("⑤ 别人开的飞机：航炮声在炮口、停火就停；导弹发动机声跟着弹飞、烧完停；扔炸弹「咣」一声")
local pos = base + V3(0, 200, -300)
cam.CFrame = R.CFrame.lookAt(pos + V3(0, 0, 200), pos)
local function oneShot(id)
  R.as("client", function() C.onFx({ { k = "shot", id = id, p = pos, v = V3(0, 0, -900), kind = "shell", f = "agun", w = "gsh30", by = "plane_x", g = true, gs = 0.08 } }) end)
end
local gl = fresh(function() oneShot(90001) end)
local hold = nil
for _, h in ipairs(gl) do for _, x in ipairs(h:GetChildren()) do if x.ClassName == "Sound" and x.Looped then hold = h end end end
check(hold ~= nil, "别人的航炮：炮口那里一个循环声")
for i = 1, 5 do oneShot(90001 + i) R.run(0.1) end
check(hold and hold.Parent ~= nil, "一直在打就一直响")
R.run(0.45)
check(hold and hold.Parent == nil, "停火 0.25 秒后停")
local ml = fresh(function()
  R.as("client", function() C.onFx({ { k = "shot", id = 91001, p = pos, v = V3(0, 0, -300), kind = "missile", w = "pl10", by = "plane_x" } }) end)
end)
local roar = nil
for _, h in ipairs(ml) do for _, x in ipairs(h:GetChildren()) do if x.ClassName == "Sound" and x.Looped and x.SoundId:find("action_falling") then roar = x end end end
check(roar ~= nil, "导弹的发动机声挂在弹的尾焰上（风声加失真）")
local burn = C.AD and C.AD.W.pl10.burn or 3.5
R.run(burn + 0.8)
check(roar and roar.Parent == nil, string.format("发动机烧完（%.1f 秒）声音就停", burn))
R.as("client", function() C.onFx({ { k = "shotEnd", id = 91001 } }) end)
local bl = fresh(function()
  R.as("client", function() C.onFx({ { k = "shot", id = 91002, p = pos, v = V3(0, -4, -200), kind = "bomb", w = "mk82", by = "plane_y" } }) end)
end)
local clunk = false
for _, h in ipairs(bl) do for _, x in ipairs(h:GetChildren()) do if x.ClassName == "Sound" and x.SoundId:find("volume_slider") and x.PlaybackSpeed < 0.4 then clunk = true end end end
check(clunk, "扔炸弹：挂架弹开「咣」一声")
R.as("client", function() C.onFx({ { k = "shotEnd", id = 91002 } }) end)

T.summary()
