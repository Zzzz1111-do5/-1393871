-- 弹着点特效测试（模拟器）：python3 tools/mock/run.py tools/mock/groundhit.lua
--   用户 11-25「然后炮弹和导弹 子弹击中地面 不同角度不同材质不同弹种有不同效果 但是都要效果强一点」
--   ① 服务器：坦克穿甲弹打在地上发 gimp（材质、来向），榴弹打在地上的爆炸带材质、来向、弹种；没给的往脚下探材质；炮兵的炮弹带来向
--   ② 客户端：穿甲弹——沙地黄、土地褐、石头迸火星；擦着地打犁出一道沟（比垂直打多几团）；水面一柱水
--   ③ 爆炸：按材质上色、斜着打的土柱往前倒；榴弹土块多、破甲弹有射流闪光、土块少
--   ④ 子弹：斜着打比垂直打多一道土
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local typeof = R.typeof

local G = T.boot()
G.fortsHold = true
G.Config.Bots.minPerTeam = 0
G.Config.Round.prep = 4
T.runUntil(function() return G.worldReady end, 120)
local me = T.join("P1", 6301, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
local C = T.C
local FXF = R.services.Workspace:FindFirstChild("ClientFx")
local cam = R.services.Workspace.CurrentCamera
local base = V3(0, 0, 0)
do
  local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
  if hrp then base = hrp.Position end
end
local function ground(dx, dz)
  local x, z = base.X + dx, base.Z + dz
  return V3(x, G.Map.ground(x, z), z)
end
cam.CFrame = R.CFrame.lookAt(base + V3(0, 30, 120), base)

-- 机库的镜头每帧把镜头挪走：画之前把镜头放回旁边（特效离镜头太远不画）
--   11-27 起特效全走 VfxLib 的发射器池（不再每次新建零件）：按池的记录（C.vfx.log，每喷一次一条）看这一下喷了哪几层
local function fresh(f)
  cam.CFrame = R.CFrame.lookAt(base + V3(0, 30, 120), base)
  C.vfx.logOn = true
  C.vfx.log = {}
  f()
  local out = C.vfx.log
  C.vfx.log = {}
  return out
end
-- 粒子：层数、用了哪些贴图、第一层烟的颜色、自己发光的白点几层（火星、白闪）、土块几层（白点染色、不发光）
local function stats(list)
  local o = { n = 0, tex = {}, col = nil, glow = 0, chunk = 0, pl = 0, names = {} }
  for _, x in ipairs(list) do
    o.n = o.n + 1
    o.tex[x.tex] = true
    o.names[x.name] = true
    if x.tex == "explosion01_implosion_main" and x.le > 0.5 then o.glow = o.glow + 1 end
    if (x.tex == "explosion01_implosion_main" and x.le <= 0.5 and x.vp) or x.tex == "SquareParticle" then o.chunk = o.chunk + 1 end
    if x.tex == "smoke_main" and not o.col then o.col = x.col end
  end
  return o
end
local function rgb(c) return c and string.format("(%d,%d,%d)", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) or "nil" end
local function warm(c) return c and (c.R - c.B) or 0 end

print("① 服务器的弹着点消息")
local got = {}
local onFx0 = C.onFx
C.onFx = function(list)
  for _, e in ipairs(list) do if e.k == "boom" or e.k == "gimp" then got[#got + 1] = e end end
  return onFx0(list)
end
local function gunW() return { id = "t120", kind = "shell", dmg = 500, splash = 4, speed = 1500, range = 4000, cal = 0.42, fx = "tank" } end
local function shoot(cls, dz)
  local tp = ground(0, dz)
  local from = tp + V3(0, 6, 60)
  G.launch({ kind = "shell", pos = from, vel = (tp - from).Unit * 1500, w = gunW(), cls = cls, src = nil, ignore = {} })
end
got = {}
shoot("ap", -200)
R.run(0.4)
local gi
for _, e in ipairs(got) do if e.k == "gimp" then gi = e end end
check(gi ~= nil, "穿甲弹打在地上：发 gimp（不炸）")
if gi then
  check(type(gi.h) == "string" and typeof(gi.n) == "Vector3" and typeof(gi.d) == "Vector3" and gi.d.Y < -0.05,
    string.format("gimp 带材质 %s、地面朝向、来弹方向（往下 %.2f）、大小 %.1f", tostring(gi.h), gi.d and gi.d.Y or 0, gi.s or 0))
  local bm = false
  for _, e in ipairs(got) do if e.k == "boom" then bm = true end end
  check(not bm, "穿甲弹打地上没有爆炸火球")
end
got = {}
shoot("he", -260)
R.run(0.4)
local hb
for _, e in ipairs(got) do if e.k == "boom" then hb = e end end
check(hb ~= nil and hb.am == "he" and type(hb.h) == "string" and typeof(hb.d) == "Vector3",
  string.format("榴弹打在地上：爆炸带弹种 %s、材质 %s、来向", tostring(hb and hb.am), tostring(hb and hb.h)))
got = {}
G.explode(ground(40, -300), { kind = "agm", dmg = 900, splash = 10 }, nil)
R.run(0.2)
check(got[1] and type(got[1].h) == "string", "没给材质的爆炸（导引弹）：服务器往脚下探到材质 " .. tostring(got[1] and got[1].h))
got = {}
G.shell(ground(80, -300), { kind = "arty", dmg = 800, splash = 12 }, nil, 0.2, ground(80, -3300))
R.run(0.6)
local ab = got[1]
check(ab and typeof(ab.d) == "Vector3" and ab.d.Y < -0.6 and ab.d.Z > 0.2 and ab.am == "he",
  string.format("炮兵的炮弹：从炮位那边斜着砸下来（来向 %s），榴弹", ab and tostring(ab.d) or "nil"))
C.onFx = onFx0

print("② 穿甲弹打在不同的地上")
local function kin(hs, dvy, dz)
  local p = ground(0, dz)
  local dv = V3(0, dvy, -1).Unit
  return stats(fresh(function() R.as("client", function() C.kineticHit(p, V3(0, 1, 0), dv, hs, 2.1) end) end))
end
local sand, dirt, rock = kin("n", -0.08, -40), kin("d", -0.08, -60), kin("r", -0.08, -80)
local steep = kin("d", -3, -100)
print(string.format("    沙 %d 组 %s、土 %d 组 %s、石 %d 组 %s（火星 %d）、土垂直 %d 组", sand.n, rgb(sand.col), dirt.n, rgb(dirt.col), rock.n, rgb(rock.col), rock.glow, steep.n))
check(sand.col and dirt.col and sand.col.R > dirt.col.R + 0.25, "沙地的土是浅黄的、土地是深褐的")
check(rock.col and math.abs(warm(rock.col)) < 0.06, "石头是灰的 " .. rgb(rock.col))
check(rock.glow > 0 and dirt.glow == 0, string.format("石头上迸火星（发光的白点 %d 层），土地上没有（%d）", rock.glow, dirt.glow))
check(dirt.chunk > 0 and not dirt.tex.SquareParticle, "土块是白点染色拉成短线，不是白方块")
check(not sand.tex.explosion01_core_main, "穿甲弹没有火球")
check(dirt.n > steep.n, string.format("擦着地打犁出一道沟（%d 组 > 垂直打 %d 组）", dirt.n, steep.n))
local wat = kin("w", -0.5, -120)
check(wat.tex.smoke_main and wat.chunk == 0, "水面：一柱水，没有土块")

print("③ 爆炸按材质、弹种")
local function bm(hs, am, dv, dz)
  local p = ground(0, dz)
  return stats(fresh(function() R.as("client", function() C.boom(p, 0.5, "shell", hs, dv, am) end) end))
end
local bS, bD, bR = bm("n", nil, nil, -140), bm("d", nil, nil, -160), bm("r", nil, nil, -180)
check(bS.col and bD.col and bS.col.R > bD.col.R + 0.25, string.format("沙地的土柱浅黄 %s、土地深褐 %s", rgb(bS.col), rgb(bD.col)))
check(bR.glow > bD.glow, "石头地上炸多一蓬火星")
local bHe, bHeat = bm("d", "he", V3(0, -0.3, -1), -200), bm("d", "heat", V3(0, -0.3, -1), -220)
print(string.format("    榴弹 %d 组、破甲弹 %d 组", bHe.n, bHeat.n))
check(bHeat.glow > bHe.glow, string.format("破甲弹：多一道射流闪光（白热 %d 组 > 榴弹 %d 组）", bHeat.glow, bHe.glow))
print("④ 子弹：斜着打多一道土")
R.as("client", function()
  local ok, err = pcall(C.impact, ground(0, -300), V3(0, -0.1, -1).Unit, "n", 1.7, V3(0, 1, 0))
  check(ok, "斜着打沙地不报错 " .. tostring(err or ""))
  ok, err = pcall(C.impact, ground(0, -310), V3(0, -1, 0), "r", 1, V3(0, 1, 0))
  check(ok, "垂直打石头不报错 " .. tostring(err or ""))
end)
R.run(1)
print("⑤ 雪地（11-28 晚用户「炮弹和炸弹炸到地面没有战雷那种效果 包括机枪打到地面也没有」：雪山图上原来全是白的，白雪地上看不出来）")
-- 每一层的头一个颜色：深（亮度 < 0.45：翻出来的冻土、黑烟）几层、白（> 0.8：雪）几层
local function darkWhite(list)
  local nd, nw = 0, 0
  for _, x in ipairs(list) do
    local c = x.col
    if c then
      local l = (c.R + c.G + c.B) / 3
      if l < 0.45 then nd = nd + 1 elseif l > 0.8 then nw = nw + 1 end
    end
  end
  return nd, nw
end
local kd, kw = darkWhite(fresh(function() R.as("client", function() C.kineticHit(ground(0, -400), V3(0, 1, 0), V3(0, -0.3, -1).Unit, "i", 2.1) end) end))
check(kd >= 2 and kw >= 1, string.format("穿甲弹打雪地：白雪 %d 层 + 深色冻土 %d 层", kw, kd))
local bd, bw = darkWhite(fresh(function() R.as("client", function() C.boom(ground(0, -430), 0.5, "shell", "i", V3(0, -0.3, -1), "he") end) end))
check(bd >= 3 and bw >= 1, string.format("榴弹打雪地：白雪 %d 层 + 深色冻土、黑烟 %d 层", bw, bd))
local id, iw = darkWhite(fresh(function() R.as("client", function() C.impact(ground(0, -460), V3(0, -0.4, -1).Unit, "i", 1.7, V3(0, 1, 0)) end) end))
check(id >= 1 and iw >= 1, string.format("机枪打雪地：白粉雪 %d 层 + 深色冻土屑 %d 层", iw, id))
R.run(1)
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
