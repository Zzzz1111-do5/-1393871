-- 加力尾焰里的马赫环（激波钻石，模拟器）：python3 tools/mock/run.py tools/mock/abdia.lua [out=<目录>]
--   用户 11-27「去网上找飞机尾喷口马赫环照片然后自己做」：不开服，直接 require 客户端的 AirModels 拼飞机、按油门摆好，检查——
--   ① 军推没有马赫环（只有加力才有）；全是朝镜头的发光光带（Beam），没有硬边的零件（以前「一节一节的马赫环」）
--   ② 满加力：每台发动机一串，第一颗亮核离喷口 0.3～1 个喷口直径 D，间距 0.9～1.4 D，比焰身窄，越往后越淡
--   ③ 半加力比满加力少、淡；夜里比白天多
--   ④ 镜头顺着喷流从正后方看：淡掉（光带缩成一条线）；换到侧面又有
--   ⑤ 推力矢量喷口（歼-20）抬头偏转：一串钻石跟着焰身一起偏
--   ⑥ 离镜头 700 格外不画
--   零件拼的（没有原模型）、原模型（喷口位置按 ImportedAir 的 noz）、二元喷口（F-22）都走一遍；out= 每种状态导出一份 JSON，
--   tools/mock/abdia_view.cjs 照 Roblox 的画法画成图（和真机照片并排看）
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local V3, CF = R.Vector3.new, R.CFrame.new
local check = T.check
local function mclamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
T.scripts = dofile(MOCK_DIR .. "/load.lua")(R, SRC_DIR)
local OUT = TEST_ARGS:match("out=(%S+)")
local RS = R.services.ReplicatedStorage
local Lighting = R.game:GetService("Lighting")
local IA = R.require(RS:FindFirstChild("ImportedAir"))
for _, id in ipairs({ "j20", "f16", "f22" }) do T.fakeImportAir((IA.alias[id]:gsub("~$", ""))) end
T.fakeImportAir("tvc")
local Client = R.services.StarterPlayer:FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")
local AM, AD
R.as("client", function()
  AD = R.require(RS:FindFirstChild("AirDefs"))
  AM = R.require(Client:FindFirstChild("AirModels"))
end)
local cam = R.workspace.CurrentCamera
local BASE = CF(0, 300, 0)

-- 拼一架：imp = false 时把导入的原模型藏起来（零件拼的那条路）
local function build(id, imp)
  local air = RS:FindFirstChild("Imported"):FindFirstChild("Air")
  local f = air:FindFirstChild((IA.alias[id]:gsub("~$", "")))
  if not imp then f.Parent = nil end
  local M
  R.as("client", function() M = AM.build(AD.get(id), "atk", {}) end)
  if not imp then f.Parent = air end
  M.model.Parent = R.workspace
  return M
end
-- 摆好：thr 油门、clock 钟点、camL 镜头（飞机坐标，机头朝 −Z）、pit 俯仰杆
local function pose(M, o)
  Lighting.ClockTime = o.clock or 14
  R.run(1.2)   -- AirModels 一秒查一次钟点
  cam.CFrame = R.CFrame.lookAt(BASE * (o.camL or V3(40, 2, 30)), BASE.Position)
  local c = { thr = o.thr, rpm = math.min(o.thr, 105), gear = 0, spinJ = 0, pit = o.pit or 0 }
  for _ = 1, 4 do R.as("client", function() AM.pose(M, BASE, c, R.clock()) end) R.run(1 / 30) end
end
-- 每台发动机的那串：{ D 喷口直径, n 亮着几颗, z 每颗亮核离焰身起点多远, w 宽, a 亮核不透明度, wp 亮核世界位置 }
local function chains(M)
  local out = {}
  for _, it in ipairs(M.items) do
    if it.plume and it.dia then
      local ch = { D = it.diaD, n = 0, z = {}, w = {}, a = {}, wp = {}, src = it.p, fillEnd = it.fillEnd, fill = it.fill }
      for _, dm in ipairs(it.dia) do
        if dm.bm[1].Enabled then
          ch.n = ch.n + 1
          table.insert(ch.z, dm.p[1].Position.Z)   -- 亮核离焰身起点（喷口出口）多远
          table.insert(ch.w, dm.bm[1].Width1)
          local kp = dm.bm[1].Transparency.Keypoints
          table.insert(ch.a, 1 - kp[#kp].Value)
          table.insert(ch.wp, dm.p[1].WorldPosition)
        end
      end
      table.insert(out, ch)
    end
  end
  return out
end
local function partsNamed(M, pat)
  local n = 0
  for _, d in ipairs(M.model:GetDescendants()) do if d:IsA("BasePart") and d.Name:match(pat) and d.Transparency < 0.95 then n = n + 1 end end
  return n
end

-- JSON（给 abdia_view 画）：零件、开着的光带、粒子，坐标都换到飞机坐标里
local function num(x) return string.format("%.4f", x) end
local function c3(col) return string.format("[%d,%d,%d]", math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5)) end
local function seq(s, f)
  local o = {}
  for _, k in ipairs(s.Keypoints or {}) do o[#o + 1] = "[" .. num(k.Time) .. "," .. f(k.Value) .. "]" end
  return "[" .. table.concat(o, ",") .. "]"
end
local function v3s(p) return "[" .. num(p.X) .. "," .. num(p.Y) .. "," .. num(p.Z) .. "]" end
local function cfs(cf)
  local t = { cf:GetComponents() }
  for i = 1, 12 do t[i] = num(t[i]) end
  return "[" .. table.concat(t, ",") .. "]"
end
local function dump(M, id, o, name)
  if not OUT then return end
  local inv = BASE:Inverse()
  local parts, beams, pes = {}, {}, {}
  for _, p in ipairs(M.model:GetDescendants()) do
    if p:IsA("BasePart") and p.Transparency < 0.99 then
      local shape = "Block"
      if p.ClassName == "WedgePart" then shape = "Wedge" elseif p.ClassName == "MeshPart" then shape = "Mesh" elseif p.ClassName == "Part" then shape = p.Shape.Name end
      local mesh = p:FindFirstChildOfClass("SpecialMesh")
      if mesh and mesh.MeshType == R.Enum.MeshType.Sphere then shape = "Sphere" end
      parts[#parts + 1] = string.format('{"n":"%s","s":"%s","z":%s,"cf":%s,"k":%s,"m":"%s","t":%s}', p.Name, shape, v3s(p.Size), cfs(inv * p.CFrame), c3(p.Color),
        p.Material.Name, num(p.Transparency))
    elseif p.ClassName == "Beam" and p.Enabled and p.Attachment0 and p.Attachment1 then
      beams[#beams + 1] = string.format('{"n":"%s","a0":%s,"a1":%s,"w0":%s,"w1":%s,"col":%s,"tr":%s,"le":%s,"li":%s,"br":%s,"seg":%d,"fc":%s}',
        p.Name, v3s(inv * p.Attachment0.WorldPosition), v3s(inv * p.Attachment1.WorldPosition), num(p.Width0), num(p.Width1), seq(p.Color, c3), seq(p.Transparency, num),
        num(p.LightEmission), num(p.LightInfluence), num(p.Brightness), p.Segments, tostring(p.FaceCamera))
    elseif p.ClassName == "ParticleEmitter" and p.Enabled and p.Rate > 0 and p.Parent:IsA("BasePart") then
      pes[#pes + 1] = string.format('{"n":"%s","cf":%s,"sp":[%s,%s],"life":[%s,%s],"rate":%s,"size":%s,"tr":%s,"col":%s,"le":%s,"spread":%s,"dir":"%s"}',
        p.Name, cfs(inv * p.Parent.CFrame), num(p.Speed.Min), num(p.Speed.Max), num(p.Lifetime.Min), num(p.Lifetime.Max), num(p.Rate), seq(p.Size, num), seq(p.Transparency, num),
        seq(p.Color, c3), num(p.LightEmission), num(p.SpreadAngle.X), p.EmissionDirection.Name)
    end
  end
  local noz = {}
  for _, n in ipairs(AM.nozzles(M)) do noz[#noz + 1] = string.format('{"p":%s,"r":%s}', v3s(n.p), num(n.r)) end
  local imp = M.imp
  local f = io.open(OUT .. "/" .. name .. ".json", "w")
  f:write(string.format('{"id":"%s","key":%s,"O":%s,"thr":%s,"clock":%s,"cam":%s,"noz":[%s],"parts":[%s],"beams":[%s],"pes":[%s]}',
    id, imp and ('"' .. imp.key .. '"') or "null", imp and v3s(imp.O) or "[0,0,0]", num(o.thr), num(o.clock or 14), v3s(o.camL or V3(40, 2, 30)),
    table.concat(noz, ","), table.concat(parts, ","), table.concat(beams, ","), table.concat(pes, ",")))
  f:close()
end
if OUT then os.execute('mkdir -p "' .. OUT .. '"') end

for _, spec in ipairs({ { "j20", false, "歼-20（零件拼的）" }, { "j20", true, "歼-20（原模型、推力矢量喷口）" }, { "f16", true, "F-16（原模型）" }, { "f22", true, "F-22（二元喷口）" } }) do
  local id, imp, label = spec[1], spec[2], spec[3]
  print("—— " .. label)
  local M = build(id, imp)
  local tag = id .. (imp and "_imp" or "_parts")
  check(imp == (M.imported ~= nil), label .. "：拼法对（原模型 " .. tostring(M.imported) .. "）")
  -- ① 军推
  pose(M, { thr = 100 })
  dump(M, id, { thr = 100 }, tag .. "_mil_day")
  local mil = 0
  for _, ch in ipairs(chains(M)) do mil = mil + ch.n end
  check(mil == 0, label .. "：军推没有马赫环（" .. mil .. " 颗）")
  -- ② 满加力、白天
  pose(M, { thr = 125 })
  dump(M, id, { thr = 125 }, tag .. "_ab_day")
  local day = chains(M)
  check(#day >= 1, label .. "：每台加力发动机一串（" .. #day .. " 串）")
  local nDay = 0
  for i, ch in ipairs(day) do
    nDay = math.max(nDay, ch.n)
    local D = ch.D
    local okSp, okW, okA = true, true, true
    for k = 2, ch.n do
      local sp = (ch.z[k] - ch.z[k - 1]) / D
      if sp < 0.9 or sp > 1.4 then okSp = false end
      if ch.a[k] > ch.a[k - 1] + 1e-6 then okA = false end
    end
    for k = 1, ch.n do if ch.w[k] > D * 0.7 then okW = false end end
    local z1 = ch.n > 0 and (ch.z[1] / D) or -1
    if i == 1 then
      print(string.format("  满加力白天：%d 颗，第一颗亮核离喷口 %.2f D、间距 %.2f D，亮核不透明度 %s", ch.n, z1, ch.n > 1 and (ch.z[2] - ch.z[1]) / D or 0,
        table.concat((function() local t = {} for k = 1, ch.n do t[k] = string.format("%.2f", ch.a[k]) end return t end)(), " ")))
    end
    check(ch.n >= 4 and ch.n <= 9, string.format("%s 第 %d 串：满加力白天 %d 颗（4～9）", label, i, ch.n))
    check(z1 >= 0.3 and z1 <= 1.0, string.format("%s 第 %d 串：第一颗亮核离喷口 %.2f D（0.3～1）", label, i, z1))
    check(okSp, label .. "：间距 0.9～1.4 D")
    check(okW, label .. "：比焰身窄（亮核宽不到 0.7 D）")
    check(okA, label .. "：越往后越淡")
  end
  check(partsNamed(M, "^MachRing$") == 0 and partsNamed(M, "^AbTube$") == 0, label .. "：没有硬边的环 / 管子零件")
  local beamsOk = true
  for _, d in ipairs(M.model:GetDescendants()) do
    if d.ClassName == "Beam" and d.Name == "AbDiamond" and (not d.FaceCamera or d.LightEmission < 1) then beamsOk = false end
  end
  check(beamsOk, label .. "：马赫环是朝镜头、叠加发光的光带")
  -- ③ 半加力、夜里
  pose(M, { thr = 112 })
  dump(M, id, { thr = 112 }, tag .. "_half_day")
  local half = chains(M)[1]
  check(half.n >= 1 and half.n <= day[1].n and half.a[1] < day[1].a[1], string.format("%s：半加力 %d 颗、第一颗 %.2f（满加力 %d 颗、%.2f）", label, half.n, half.a[1] or 0, day[1].n, day[1].a[1]))
  pose(M, { thr = 125, clock = 1 })
  dump(M, id, { thr = 125, clock = 1 }, tag .. "_ab_night")
  local night = chains(M)[1]
  check(night.n > day[1].n, string.format("%s：夜里比白天多（%d / %d 颗）", label, night.n, day[1].n))
  -- ④ 正后方看
  local nz = AM.nozzles(M)[1].p
  pose(M, { thr = 125, camL = V3(nz.X, nz.Y + 0.3, nz.Z + 80) })
  dump(M, id, { thr = 125, camL = V3(nz.X, nz.Y + 0.3, nz.Z + 80) }, tag .. "_ab_rear")
  local rear = 0
  for _, ch in ipairs(chains(M)) do rear = rear + ch.n end
  check(rear == 0, label .. "：镜头从正后方顺着喷流看，马赫环淡掉（" .. rear .. " 颗）")
  pose(M, { thr = 125, camL = V3(30, 8, 70) })
  dump(M, id, { thr = 125, camL = V3(30, 8, 70), clock = 18 }, tag .. "_ab_quarter")
  check(chains(M)[1].n > 0, label .. "：斜后方又看得见")
  -- ⑤ 推力矢量
  if id == "j20" and imp then
    pose(M, { thr = 125, camL = V3(40, 2, 30), pit = 0 })
    local ch0 = chains(M)[1]
    local a0 = (ch0.wp[ch0.n] - ch0.src.Position).Unit
    pose(M, { thr = 125, camL = V3(40, 2, 30), pit = 1 })
    local ch1 = chains(M)[1]
    local src = ch1.src
    local a1 = (ch1.wp[ch1.n] - src.Position).Unit
    local f1 = (ch1.fillEnd.WorldPosition - src.Position).Unit
    local ang = math.deg(math.acos(mclamp(a0:Dot(a1), -1, 1)))
    print(string.format("  抬头：钻石串偏了 %.1f°，跟焰身同轴（夹角 %.2f°）", ang, math.deg(math.acos(mclamp(a1:Dot(f1), -1, 1)))))
    check(ang > 5 and a1:Dot(f1) > 0.9995, "推力矢量喷口偏转：马赫环跟着焰身一起偏")
  end
  -- ⑥ 远处
  pose(M, { thr = 125, camL = V3(900, 0, 0) })
  local far = 0
  for _, ch in ipairs(chains(M)) do far = far + ch.n end
  check(far == 0, label .. "：离镜头 700 格外不画（" .. far .. " 颗）")
  M.model:Destroy()
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
if OUT then print("JSON 写在 " .. OUT) end
T.summary()
