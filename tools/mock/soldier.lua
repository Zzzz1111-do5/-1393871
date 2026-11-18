-- 小兵的姿势（模拟器，不开服）：python3 tools/mock/run.py tools/mock/soldier.lua [dump=<目录>]
--   用户：给小兵加上动画和姿势；每个人要有自己的动作，不要一模一样
--   直接加载 Soldier.lua，摆一个小兵（零件拼的那种，关节名字和 R15 一样），挨个试：站着端枪、低姿持枪、走、跑、蹲着走、单膝跪、卧倒、
--   匍匐、换弹匣、扔手雷、手势、倒下；检查脚踩在地上（不悬空、不陷进去）、双手握在枪上、跪着一边膝盖着地、趴着贴地、倒下后躺在地上；
--   两个小兵的步子、端枪不一样。dump=<目录>：每个姿势的零件写成 JSON（tools/mock/pose_render.py 画成图看）
local R = dofile(MOCK_DIR .. "/rbx.lua")
dofile(MOCK_DIR .. "/load.lua")(R, SRC_DIR)
local V3, CF = R.Vector3.new, R.CFrame.new
local fails = 0
local function check(ok, what)
  print((ok and "  通过 " or "  不对 ") .. what)
  if not ok then fails = fails + 1 end
end
local dumpDir = TEST_ARGS:match("dump=(%S+)")

local client = R.services.StarterPlayer:FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")
local ms = client:FindFirstChild("Soldier")
local G = {
  Config = { Teams = { atk = { color = R.Color3.fromRGB(220, 70, 55) }, def = { color = R.Color3.fromRGB(60, 120, 230) } } },
  perfK = 1,
}
local errs = 0
function G.try_(f, ...)
  local ok, e = pcall(f, ...)
  if not ok then errs = errs + 1 print("  出错：" .. tostring(e)) end
end
local vel = V3(0, 0, 0)
function G.follow(v, target)
  v.fl = v.fl or {}
  v.fl.vel = vel
  return target
end
local K
R.as("client", function()
  local Soldier = R.require(ms)
  Soldier.init(G)
  K = G.viewKind.bot
end)
if not K then print("Soldier.lua 没加载起来") TEST_CODE = 2 return end

local folder = R.Instance.new("Folder")
folder.Parent = R.game:GetService("Workspace")
local function newBot(id, x)
  local em = R.Instance.new("Model")
  em.Name = id
  em:SetAttribute("EntId", id)
  em:SetAttribute("Hp", 100)
  em:SetAttribute("MaxHp", 100)
  local root = R.Instance.new("Part")
  root.Name = "Root"
  root.Size = V3(2.2, 5.6, 1.6)
  root.CFrame = CF(x, 2.8, 0)   -- 地面 y = 0
  root.Parent = em
  em.Parent = folder
  local v = { root = root, em = em, id = id, cf = root.CFrame }
  local ok = false
  R.as("client", function() ok = K.build(v, em, "atk") end)
  if not ok then return nil end
  v.model.Parent = folder
  return v
end
R.localPlayer = R.addPlayer("P1", 6001)   -- 有本地玩家，R.step 才推 RenderStepped（倒地动画在那上面）
local function run(v, sec, dt)
  dt = dt or 1 / 30
  for _ = 1, math.floor(sec / dt + 0.5) do
    R.step(dt)   -- 推时钟（os.clock）
    R.as("client", function() K.step(v, dt, V3(0, 5, 40)) end)
  end
end
local function tick(n) for _ = 1, n do R.step(1 / 30) end end
local function partOf(v, name) return v.model:FindFirstChild(name, true) end
local function world(p) return p.CFrame end
-- 脚底（两只脚最低点）、膝盖最低点、整个人最低 / 最高点
local function lowest(p)
  local cf, s = world(p), p.Size * 0.5
  local lo = math.huge
  for _, x in ipairs({ -1, 1 }) do for _, y in ipairs({ -1, 1 }) do for _, z in ipairs({ -1, 1 }) do
    lo = math.min(lo, (cf * V3(s.X * x, s.Y * y, s.Z * z)).Y)
  end end end
  return lo
end
local function highest(v)
  local hi = -math.huge
  for _, p in ipairs(v.model:GetDescendants()) do
    if p:IsA("BasePart") and p.Transparency < 1 then hi = math.max(hi, world(p).Position.Y) end
  end
  return hi
end
local function wrist(v, side)
  local J = v.J[side .. "Wrist"]
  return (world(J.m.Part0) * J.m.C0).Position
end
local function rifleAt(v, pt) return (world(v.rj.Part1) * pt) end
local RIF = { grip = V3(0, -0.02, 0.12), fore = V3(0, -0.04, -0.8), muzzle = V3(0, 0.17, -1.92) }

local dumps = {}
local function dump(v, name)
  if not dumpDir then return end
  local out = {}
  for _, p in ipairs(v.model:GetDescendants()) do
    if p:IsA("BasePart") and p.Transparency < 1 then
      local cf = world(p)
      local c = { cf:GetComponents() }
      local col = p.Color
      out[#out + 1] = string.format('{"n":"%s","s":[%.3f,%.3f,%.3f],"c":[%s],"rgb":[%d,%d,%d],"ball":%s}', p.Name, p.Size.X, p.Size.Y, p.Size.Z,
        table.concat((function() local t = {} for i = 1, 12 do t[i] = string.format("%.4f", c[i]) end return t end)(), ","),
        math.floor(col.R * 255), math.floor(col.G * 255), math.floor(col.B * 255), tostring(p.Shape == R.Enum.PartType.Ball))
    end
  end
  dumps[#dumps + 1] = string.format('{"name":"%s","parts":[%s]}', name, table.concat(out, ","))
end

local v = newBot("e17", 0)
check(v ~= nil and v.J ~= nil, "拼好了一个小兵（关节齐全）")
if not v then TEST_CODE = 2 return end
local function feetOK(what, tol)
  local l, r = lowest(partOf(v, "LeftFoot")), lowest(partOf(v, "RightFoot"))
  check(math.abs(l) < (tol or 0.22) and math.abs(r) < (tol or 0.22), string.format("%s：两只脚踩在地上（脚底 %.2f / %.2f）", what, l, r))
end
local function handsOK(what, tol, fore)
  local dr = (wrist(v, "Right") - rifleAt(v, RIF.grip)).Magnitude
  local dl = (wrist(v, "Left") - rifleAt(v, fore or RIF.fore)).Magnitude
  check(dr < (tol or 0.25) and dl < (tol or 0.25), string.format("%s：右手在握把上、左手在护木上（差 %.2f / %.2f）", what, dr, dl))
end

print("① 站着：低姿持枪 → 端枪瞄准")
v.em:SetAttribute("St", 0)
run(v, 1)
feetOK("站着")
handsOK("低姿持枪")
local mz = rifleAt(v, RIF.muzzle)
local gp = rifleAt(v, RIF.grip)
check(mz.Y < gp.Y, string.format("低姿持枪：枪口朝下（枪口 %.2f、握把 %.2f）", mz.Y, gp.Y))
dump(v, "stand_ready")
v.em:SetAttribute("Aim", 0)
run(v, 1)
handsOK("端枪")
mz, gp = rifleAt(v, RIF.muzzle), rifleAt(v, RIF.grip)
local headY = world(partOf(v, "Head")).Position.Y
check(math.abs(mz.Y - gp.Y) < 0.35 and mz.Z < gp.Z - 1.5 and gp.Y > headY - 2.2, string.format("端枪：枪平端着朝前、抵在肩上（枪口高 %.2f、握把高 %.2f、头 %.2f）", mz.Y, gp.Y, headY))
dump(v, "stand_aim")
v.em:SetAttribute("Aim", -25)
run(v, 1)
mz, gp = rifleAt(v, RIF.muzzle), rifleAt(v, RIF.grip)
check(mz.Y < gp.Y - 0.4, string.format("目标在下面：枪口压低（%.2f）", mz.Y - gp.Y))
handsOK("往下瞄")
dump(v, "stand_aim_down")
v.em:SetAttribute("Aim", nil)
run(v, 3.5)

print("② 走、跑：脚在地上那一段不打滑，跑起来枪斜挎在胸前")
vel = V3(0, 0, -7)
run(v, 1.2)   -- 先走起来（速度平滑到 7 格 / 秒；起步那一下脚还在加速）
local slip, minFoot, maxFoot = 0, math.huge, -math.huge
local lastL, lastT = nil, nil
for i = 1, 90 do
  run(v, 1 / 30)
  local f = partOf(v, "LeftFoot")
  local lo = lowest(f)
  minFoot, maxFoot = math.min(minFoot, lo), math.max(maxFoot, lo)
  local cf = world(f)
  local p = cf.Position
  local flat = cf.UpVector.Y > 0.999 and math.abs(p.Y - 0.15) < 0.01   -- 脚放平踩实在地上（脚中心离地正好半个脚厚）
  if lastL and flat and lastT then slip = math.max(slip, math.abs((p.Z - lastL.Z) - 7 / 30)) end   -- 踩在地上的那几帧：脚跟着身体往后（身体不动，路往后走）
  lastL, lastT = p, flat
  if i == 45 then dump(v, "walk") end
end
check(minFoot > -0.25 and maxFoot > 0.15, string.format("走：脚抬起来又放下（最低 %.2f、最高 %.2f）", minFoot, maxFoot))
check(slip < 0.12, string.format("走：脚在地上那一段跟地面走得一样快，不打滑（差 %.2f 格 / 帧）", slip))
handsOK("走的时候", 0.3)
vel = V3(0, 0, -15)
run(v, 2)
mz, gp = rifleAt(v, RIF.muzzle), rifleAt(v, RIF.grip)
check(mz.Y > gp.Y + 0.5 and mz.X < gp.X, string.format("跑：枪斜挎胸前，枪口朝左上（高 %.2f、左 %.2f）", mz.Y - gp.Y, gp.X - mz.X))
handsOK("跑的时候", 0.3)
local ltRun = world(partOf(v, "UpperTorso"))
check(ltRun.LookVector.Y < -0.12, string.format("跑：身子往前倾（%.0f°）", math.deg(math.asin(-ltRun.LookVector.Y))))
dump(v, "run")
vel = V3(0, 0, 0)
run(v, 2)

print("③ 蹲、跪：单膝跪地端枪；蹲着走")
v.em:SetAttribute("St", 1)
v.em:SetAttribute("Aim", 0)
run(v, 1.2)
local kneeY = math.min(lowest(partOf(v, "RightLowerLeg")), lowest(partOf(v, "LeftLowerLeg")))
check(kneeY < 0.2 and kneeY > -0.3, string.format("跪：一边膝盖着地（%.2f）", kneeY))
local hy = world(partOf(v, "Head")).Position.Y
check(hy < 4.6 and hy > 2.8, string.format("跪：头低下来了（%.2f 格，站着约 5.1）", hy))
handsOK("跪射")
feetOK("跪着", 0.35)
dump(v, "kneel_aim")
v.em:SetAttribute("Aim", nil)
vel = V3(0, 0, -5)
run(v, 4)
hy = world(partOf(v, "Head")).Position.Y
check(hy < 4.7, string.format("蹲着走：头低着（%.2f）", hy))
handsOK("蹲着走", 0.3)
dump(v, "crouch_walk")
vel = V3(0, 0, 0)

print("④ 卧倒：整个人贴着地，枪朝前；匍匐")
v.em:SetAttribute("St", 2)
v.em:SetAttribute("Aim", 0)
run(v, 2.5)
local hi = highest(v)
check(hi < 1.9, string.format("趴着：最高的零件也不过 %.2f 格", hi))
local lo = math.huge
for _, n in ipairs({ "UpperTorso", "LowerTorso", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }) do lo = math.min(lo, lowest(partOf(v, n))) end
check(lo > -0.35, string.format("趴着：身子没陷进地里（最低 %.2f）", lo))
mz, gp = rifleAt(v, RIF.muzzle), rifleAt(v, RIF.grip)
check(mz.Z < gp.Z - 1.4 and mz.Y > -0.1, string.format("趴着：枪朝前（枪口 z %.2f、高 %.2f）", mz.Z, mz.Y))
handsOK("趴着瞄准（左手托在弹匣前面）", 0.3, V3(0, -0.12, -0.5))
dump(v, "prone_aim")
v.em:SetAttribute("Aim", nil)
vel = V3(0, 0, -2.5)
run(v, 1.5)
dump(v, "crawl")
hi = highest(v)
check(hi < 2.1, string.format("匍匐：还是贴着地（%.2f）", hi))
vel = V3(0, 0, 0)
v.em:SetAttribute("St", 0)
run(v, 2.5)
feetOK("站起来")

print("⑤ 动作：换弹匣、扔手雷、打手势")
v.em:SetAttribute("Aim", 0)
v.em:SetAttribute("Act", "r1")
run(v, 0.75)
local dmag = (wrist(v, "Left") - rifleAt(v, V3(0, -0.38, -0.44))).Magnitude
check(dmag < 1.0, string.format("换弹：左手去拔弹匣（离弹匣 %.2f）", dmag))
check(v.mag.Transparency == 1, "换弹：旧弹匣拔下来了")
dump(v, "reload")
run(v, 2)
check(v.mag.Transparency == 0, "换弹：新弹匣插上了")
handsOK("换完弹")
v.em:SetAttribute("Act", "g2")
run(v, 0.5)
local nade = partOf(v, "Nade")
local rw = wrist(v, "Right")
local hd = world(partOf(v, "Head")).Position
check(nade.Transparency == 0 and rw.Y > hd.Y - 0.8, string.format("扔雷：手雷举到脑后（手 %.2f、头 %.2f）", rw.Y, hd.Y))
dump(v, "throw")
run(v, 1)
check(nade.Transparency == 1, "扔雷：扔出去了，手里没了")
v.em:SetAttribute("Act", "s3")
run(v, 0.4)
local lw = wrist(v, "Left")
check(lw.Y > hd.Y - 1.6, string.format("手势：左手举起来（%.2f）", lw.Y))
dump(v, "signal")
run(v, 1.2)
handsOK("手势完")

print("⑥ 每个人不一样")
local w = newBot("e18", 6)
vel = V3(0, 0, -7)
local a1, a2 = {}, {}
for i = 1, 40 do
  run(v, 1 / 30)
  run(w, 1 / 30)
  a1[i] = world(partOf(v, "LeftFoot")).Position.Z
  a2[i] = world(partOf(w, "LeftFoot")).Position.Z
end
local diff = 0
for i = 20, 40 do diff = math.max(diff, math.abs(a1[i] - a2[i])) end
print(string.format("  （步态相位 %.2f / %.2f）", v.ph, w.ph))
check(diff > 0.2, string.format("两个小兵一起走，步子不一样（脚的前后差到 %.2f 格）", diff))
check(v.P.cad ~= w.P.cad and v.P.carry ~= w.P.carry, string.format("各有各的步频（%.2f / %.2f）、端枪高低（%.2f / %.2f）", v.P.cad, w.P.cad, v.P.carry, w.P.carry))
vel = V3(0, 0, 0)

print("⑦ 倒下：躺在地上，枪掉在旁边；8 秒后收走")
v.em:SetAttribute("Aim", nil)
run(v, 1)
v.em:SetAttribute("Hp", 0)
v.em:SetAttribute("DieD", 10)
local keep = false
R.as("client", function() keep = K.remove(v) end)
check(keep == true, "被打死：自己收尾（倒地动画）")
tick(45)
hi = highest(v)
check(hi < 1.9, string.format("倒下：躺在地上了（最高 %.2f）", hi))
local rp = world(v.rj.Part1).Position
check(rp.Y < 0.6, string.format("枪掉在地上（%.2f）", rp.Y))
dump(v, "dead_back")
-- 往前扑的倒法
local v2 = newBot("e31", 12)
run(v2, 1)
v2.em:SetAttribute("Hp", 0)
v2.em:SetAttribute("DieD", 170)
R.as("client", function() K.remove(v2) end)
tick(20)
dump(v2, "dying_forward")
tick(25)
check(highest(v2) < 1.9, string.format("往前扑倒：趴在地上（%.2f）", highest(v2)))
dump(v2, "dead_forward")
tick(8 * 30)
check(v.model.Parent == nil, "8 秒后收走了")

if dumpDir then
  local f = io.open(dumpDir .. "/poses.json", "w")
  f:write("[" .. table.concat(dumps, ",\n") .. "]")
  f:close()
  print("写了 " .. #dumps .. " 个姿势到 " .. dumpDir .. "/poses.json")
end
print(string.format("脚本报错 %d 条", errs))
if fails > 0 or errs > 0 then print("不对 " .. fails .. " 处") TEST_CODE = 1 else print("全部通过") end
