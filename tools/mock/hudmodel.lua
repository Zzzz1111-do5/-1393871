-- 平显原模型（模拟器）：python3 tools/mock/run.py tools/mock/hudmodel.lua [air=j15t|j20|j16] [off=1]
--   用户 11-22：「把飞机驾驶舱的光学瞄准屏直接搬来用」「j15t 原模型自带内饰」——歼-15T 原模型座舱里的平显（models/optics/hud15.glb，tools/weapons/hud.mjs）。
--   模拟器里假装导入了：ReplicatedStorage.Imported.Optics.hud15 放两块 MeshPart（O_hud15__Frame、O_hud15__Glass），坐进座舱看
--   ① 换上了原模型的框和玻璃（零件拼的投影仪、框不要了），大小照元数据 × 缩放；② 符号屏在组合玻璃正中、不比玻璃大；③ 玻璃几乎透明
--   off=1：不放原模型——照旧零件拼的平显
-- （下面开服、召唤、坐进座舱同 cockpit.lua）
-- 飞机座舱测试（模拟器）：python3 tools/mock/run.py tools/mock/cockpit.lua [air=j20|j35|j16|j15t|f35|f22|a10c] [dump=<目录>]
--   用户 11-21：第一人称开飞机要有和 DCS 一样的视觉细节；座舱盖玻璃要有畸变、划痕、反光折射
--   ① 召唤、坐上，V 进座舱：座舱拼出来了（零件、屏幕、平显、座舱盖玻璃和划痕），镜头在飞行员眼位；外模型的飞行员、座舱盖玻璃不画；外面的 2D 平显不画
--   ② 屏幕边的按键：中间小点对准、左键按（换页，不开炮）
--   ③ 起飞：油门杆往前推、驾驶杆跟着拉、收起落架（手柄、三个绿灯灭）；屏幕和平显是实时的速度、高度、航向；平显的机头符号在组合玻璃中间
--   ④ 头跟着鼠标瞄准转；按住 Alt 自由看：准心不动
--   ⑤ K 导演镜头、U 藏界面
--   ⑥ V 出座舱：外模型放回来；下飞机：座舱拆掉
--   dump=<目录>：写出 interior_<型号>.json，tools/mock/interior_view.cjs 画成图
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local dumpDir = TEST_ARGS:match("dump=(%S+)")
local AIR = TEST_ARGS:match("air=(%w+)") or "j20"
local US = { f35 = true, f22 = true, a10c = true, ah64e = true, uh60 = true, ch47 = true, b2 = true }
local side = US[AIR] and "def" or "atk"

local G = T.boot()
local OFF = TEST_ARGS:match("off=1") ~= nil
local HM = R.require(R.services.ReplicatedStorage:FindFirstChild("HudMeta")).hud15
if not OFF then
  local RS = R.services.ReplicatedStorage
  local imp = RS:FindFirstChild("Imported") or R.Instance.new("Folder")
  imp.Name = "Imported"
  imp.Parent = RS
  local opt = imp:FindFirstChild("Optics") or R.Instance.new("Folder")
  opt.Name = "Optics"
  opt.Parent = imp
  local f = R.Instance.new("Folder")
  f.Name = "hud15"
  for name, p in pairs(HM.parts) do
    local mp = R.Instance.new("MeshPart")
    mp.Name = "O_hud15__" .. name
    mp.Size = R.Vector3.new(p.s[1], p.s[2], p.s[3]) * 2.8
    mp.Anchored = true
    mp.Parent = f
  end
  f:SetAttribute("N", 2)
  f.Parent = opt
end
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8101, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = side
me.Team = G.TEAM[side]
me.Neutral = false
me:SetAttribute("Side", side)
G.pushOne(P)
R.run(1)
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
T.runUntil(function() return G.round.phase == "battle" end, 90)   -- 守方机场准备阶段不能出生
T.actAs(me, "deploy", "rifle", (side == "atk") and "af2" or "afield")
R.run(1.5)
check(P.alive and me.Character ~= nil, "在机场出生了")
local cam = R.workspace.CurrentCamera

print("① 召唤 " .. AIR .. "、坐上，V 进座舱")
local pad = T.pad(AIR)
check(pad ~= nil, "有能召唤 " .. AIR .. " 的召唤位")
local e
if pad then
  T.usePad(me, pad)
  local card = T.findNamed("Pick_" .. AIR)
  if card then T.press(card) end
  R.run(0.3)
  local go = T.findButton("^" .. C.T("pad.spawn") .. "$")
  if go then T.press(go) end
  R.run(1)
  for _, x in ipairs(G.aircraft or {}) do if x.padId == pad.id and x.alive then e = x end end
end
if not e then   -- 没有召唤位的（轰炸机）：在本方战斗机召唤位上直接生成
  local fp = T.pad((side == "atk") and "j20" or "f22")
  if fp then
    local c = fp.base.Position
    local d = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs")).get(AIR)
    local pos = R.Vector3.new(c.X, G.airSurface(c.X, c.Z) + d.gearH, c.Z)
    e = G.spawnAircraft(side, AIR, R.CFrame.lookAt(pos, pos + fp.base.LookVector), nil, P, 1)
    local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
    if hrp then me.Character:PivotTo(R.CFrame.new(pos + R.Vector3.new(12, 2, 0))) end
    R.run(0.5)
  end
end
check(e ~= nil, "飞机停在停机位上")
T.act("enterVeh", e and e.id)
R.run(1.5)
local fst = C.fly
check(P.vehicle == e and fst ~= nil and fst.pilot, "坐上了 " .. AIR)
T.runUntil(function() return G.round.phase == "battle" end, 60)
if not fst then T.summary() return end
T.tap(Enum.KeyCode.V)
R.run(0.6)
local I = C.interiorState()
local cur = I.cur
check(C.interiorOn() and cur ~= nil and cur.spec.air and I.mode == "seat", "按 V：坐进座舱（" .. tostring(cur and cur.key) .. "）")
if not cur then T.summary() return end
print("① 平显：" .. (OFF and "没导入原模型（零件拼的）" or "导入了歼-15T 的原模型"))
local hs = cur.b.named.hud
check(hs ~= nil, "有符号屏（hud 页）")
local meshes = {}
for _, it in ipairs(cur.b.parts) do
  local p = it[1]
  if p:IsA("MeshPart") and string.match(p.Name, "^O_hud15__") then meshes[p.Name] = p end
end
local frame, glass = meshes.O_hud15__Frame, meshes.O_hud15__Glass
if OFF then
  check(frame == nil and glass == nil and cur.b.hudModel == nil, "没导入：照旧零件拼的平显")
  T.summary()
  return
end
check(frame ~= nil and glass ~= nil and cur.b.hudModel == 2, "换上了原模型的框和组合玻璃（2 块）")
if not (frame and glass and hs) then T.summary() return end
-- 两块的大小之比和元数据一样（同一个缩放）
local k1 = frame.Size.X / (HM.parts.Frame.s[1] * 2.8)
local k2 = glass.Size.Y / (HM.parts.Glass.s[2] * 2.8)
check(math.abs(k1 - k2) < 1e-3 and k1 >= 0.7 and k1 <= 1.2, string.format("框和玻璃按同一个缩放（%.3f / %.3f）", k1, k2))
-- 符号屏在玻璃正中（同一个组里：比较两块相对组原点的位置）
local function offOf(p) for _, it in ipairs(cur.b.parts) do if it[1] == p then return it[3] end end end
local go, ho = offOf(glass), offOf(hs.part)
local d = (go.Position - ho.Position).Magnitude / 2.8
check(d < 0.01, string.format("符号屏在组合玻璃正中（差 %.3f 米）", d))
check(hs.part.Size.X <= glass.Size.X + 1e-3, string.format("符号屏不比玻璃宽（%.2f / %.2f 格）", hs.part.Size.X, glass.Size.X))
check(glass.Transparency >= 0.85, "组合玻璃几乎透明（" .. glass.Transparency .. "）")
-- 零件拼的那套投影仪、框不要了：平显附近（符号屏下面 0.2 米以内）没有零件拼的深灰金属块
local leftover = 0
for _, it in ipairs(cur.b.parts) do
  local p = it[1]
  if not p:IsA("MeshPart") and p.Material == Enum.Material.Metal and p.Color == R.Color3.fromRGB(30, 32, 34) then
    local rel = (it[3].Position - ho.Position) / 2.8
    if math.abs(rel.X) < 0.2 and rel.Y < 0.15 and rel.Y > -0.2 and math.abs(rel.Z) < 0.15 then leftover = leftover + 1 end
  end
end
check(leftover == 0, "零件拼的投影仪、立柱没摆（剩 " .. leftover .. " 块）")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
