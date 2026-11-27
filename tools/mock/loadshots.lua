-- 整备挂载页的截图（模拟器，一次开服拍完）：python3 tools/mock/run.py tools/mock/loadshots.lua dir=<目录> [mobile=1]
--   用户 11-27「整个给载具配置武器的系统 做的很粗糙 我需要非常艺术经验的效果 参考战雷」：像玩家一样进机库，阵容里选歼-15T，点顶栏的弹药键打开整备的挂载页，拍：
--   01 全景 · 02 选中一个挂点（左栏这个挂点能挂的武器、镜头飞到那一侧）· 03 鼠标挂在一张武器卡上（3D 先换上、右栏的变化、浮出来的资料卡）·
--   04 换了方案以后（对地，再改一个挂点：「已改」）· 05 直升机（AH-64E）；mobile=1：06 手机（1000 × 500 的画布，触屏）
--   每张写两份 JSON：<名>.json 界面（tools/mock/uidump.lua）、<名>.scene.json 3D（镜头、停机坪和飞机的零件）；出图：
--     SS=2 python3 -I tools/mock/scene_render.py <名>.scene.json <名>.bg.png
--     SS=2 BIG=1 python3 -I tools/mock/hud_render.py <名>.json <名>.png <名>.bg.png        （手机那张加 WH=1280x640）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, Enum = T.R, T.V3, T.Enum
local check = T.check
local dir = TEST_ARGS:match("dir=(%S+)") or "."
local mobile = TEST_ARGS:match("mobile=1") ~= nil
local dump = dofile(MOCK_DIR .. "/uidump.lua")
if mobile then   -- 手机横屏：触屏、画面 1280 × 640（TechUI 按 1000 × 500 的画布缩放：1.28 倍）
  R.touch = true
  R.viewSize = R.Vector2.new(1280, 640)
end

T.wtMode = true
T.matchMode = true   -- 没进局：「匹配中」的机库（同 tools/mock/workshop.lua）
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
G.Config.Match.wait = 600   -- 截图的时候别真的开局
T.runUntil(function() return G.worldReady end, 900)
local RS = R.services.ReplicatedStorage
local TT = R.require(RS:FindFirstChild("TechTree"))
local AD = R.require(RS:FindFirstChild("AirDefs"))
local me = T.join("P1", 9581, true)
T.runUntil(function() return G.round ~= nil end, 30)
local C = T.C
T.leaveMenu()
T.runUntil(function() return G.rangeReady == true and T.findNamed("HangarGo") ~= nil end, 120, 1 / 10)
R.run(1)

---------------------------------------------------------------- 拍一张：界面 + 3D 场景

local function enc(v)
  local t = type(v)
  if t == "number" then return (v ~= v or v == math.huge or v == -math.huge) and "0" or string.format("%.4f", v) end
  if t == "string" then return '"' .. v:gsub('[%c"\\]', function(ch) return string.format("\\u%04x", ch:byte()) end) .. '"' end
  if t == "boolean" then return tostring(v) end
  if t == "table" then
    if #v > 0 or next(v) == nil then
      local o = {}
      for i, x in ipairs(v) do o[i] = enc(x) end
      return "[" .. table.concat(o, ",") .. "]"
    end
    local o = {}
    for k, x in pairs(v) do o[#o + 1] = enc(tostring(k)) .. ":" .. enc(x) end
    return "{" .. table.concat(o, ",") .. "}"
  end
  return "null"
end
-- 3D：镜头附近 4000 格以内的零件（停机坪、机库、塔台、飞机），飞机的打个记号（scene_render.py 给它投影子）
local function scene(path)
  local cam = R.workspace.CurrentCamera
  local cp = cam.CFrame.Position
  local plane = C.hangarStage and C.hangarStage.model()
  local parts = {}
  for _, p in ipairs(R.workspace:GetDescendants()) do
    if p:IsA("BasePart") and p.Transparency < 0.97 then
      local ok, pos = pcall(function() return p.Position end)
      if ok and (pos - cp).Magnitude < 4000 then
        local mesh = p:FindFirstChildOfClass("SpecialMesh")
        local k = p.ClassName
        if k == "Part" then k = p.Shape.Name end
        local c = p.Color
        parts[#parts + 1] = { k = k, z = { p.Size.X, p.Size.Y, p.Size.Z }, f = { p.CFrame:GetComponents() },
          c = { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }, t = p.Transparency,
          m = p.Material.Name, mesh = mesh and mesh.MeshType.Name or nil, pl = (plane ~= nil and p:IsDescendantOf(plane)) or nil }
      end
    end
  end
  local vs = cam.ViewportSize
  local floor = C.hangarStage and C.hangarStage.floorCF()
  local f = assert(io.open(path, "w"))
  f:write(enc({ vw = vs.X, vh = vs.Y, fov = cam.FieldOfView, gy = floor and floor.Position.Y or 0, cam = { cam.CFrame:GetComponents() }, parts = parts }))
  f:close()
  return #parts
end
local shots = {}
local function shot(name)
  for _, d in ipairs(me.PlayerGui:GetDescendants()) do   -- 新手卡、作战简报只为截图收起
    if d.Name == "CoachCard" or d.Name == "OperationBrief" then d.Visible = false end
  end
  local items = dump(T, me, dir .. "/" .. name .. ".json", true)
  local n = scene(dir .. "/" .. name .. ".scene.json")
  table.insert(shots, name)
  print(string.format("拍了 %s（界面 %d 个元素、3D %d 个零件）", name, #items, n))
end
local function vis(name)   -- 看得见的、叫这个名字的界面零件（框、字也算）
  for _, x in ipairs(me.PlayerGui:GetDescendants()) do
    if x.Name == name and T.visible(x) then return x end
  end
end
local function press(name)
  local b = T.findNamed(name)
  check(b ~= nil, "点得到 " .. name)
  if b then T.press(b) end
  return b
end

---------------------------------------------------------------- 阵容：起步坦克 + 歼-15T（中国）；直升机拍美国的 AH-64E

T.act("redeem", "Zhengyongshuo")   -- 全部解锁（设置里的兑换码）
R.run(1)
local JET, HELI = "cn_j15t", "us_ah64e"
T.act("treeLineup", "cn", { TT.starter("cn", "ground").key, JET })
R.run(1)
press("Line_" .. JET)
R.run(0.6)
press("AmmoBtn")
R.run(1.6)
local W, st = C.workshopState()
check(W.on and st and st.key == JET, "整备开了（" .. tostring(st and st.key) .. "）")
local S = C.hangarStage
check(S and S.modeNow() == "air" and not S.viewState().flying, "停机坪、镜头飞到全景了")
R.run(0.6)

if not mobile then
  check(vis("Manifest") ~= nil and vis("Man_gsh30") ~= nil and vis("Man_pl15") ~= nil, "全景：左栏下半是「这一套挂的」（航炮、霹雳-15……）")
  shot("01_overview")
  -- 02：选中机翼中段那一对挂点（这架能挂八种：霹雳-15、霹雳-12、KD-88、鹰击-83K、鹰击-91、雷石-6、雷霆-2、250 公斤炸弹）
  local midCard = nil
  for ci, g in ipairs(st.cards) do if g.name == "mid" then midCard = ci end end
  check(midCard ~= nil, "机翼中段那一对是第 " .. tostring(midCard) .. " 张卡")
  press("Station_" .. tostring(midCard))
  R.run(1.2)
  shot("02_station")
  -- 03：鼠标挂在 KD-88 那张卡上（3D 停一下换上、右栏琥珀色的变化、旁边浮出资料卡）
  local opt = T.findNamed("Opt_kd88")
  check(opt ~= nil, "有 KD-88 那张卡")
  if opt then R.as("client", function() opt.MouseEnter:Fire(200, 300) end) end
  R.run(0.8)
  check(st.hoverOpt == "kd88", "悬停预览：kd88")
  shot("03_hover")
  if opt then R.as("client", function() opt.MouseLeave:Fire(200, 300) end) end
  R.run(0.4)
  -- 04：换成「对地」方案，再把翼尖那一对换成霹雳-10 以外的……（对地本来挂霹雳-10）：把内侧那一对换成 250 公斤炸弹 →「照『对地』改过 2 个挂点」
  press("Preset_ag")
  R.run(0.8)
  local innerCard = nil
  for ci, g in ipairs(st.cards) do if g.name == "inner" then innerCard = ci end end
  press("Station_" .. tostring(innerCard))
  R.run(1.0)
  press("Opt_b250")
  R.run(1.2)
  check(st.pk == "ag" and (st.load[st.cards[innerCard].st[1]] == "b250"), "对地、内侧改成 250 公斤炸弹")
  shot("04_preset")
  -- 05：直升机（美国 AH-64E：地狱火四联装、九头蛇火箭巢、翼尖毒刺、副油箱）
  T.key(Enum.KeyCode.Escape, true)
  T.key(Enum.KeyCode.Escape, false)
  R.run(0.3)
  T.key(Enum.KeyCode.Escape, true)
  T.key(Enum.KeyCode.Escape, false)
  R.run(1)
  check(not C.workshopOpen(), "Esc 两下回机库")
  T.act("treeNat", "us")
  R.run(0.5)
  T.act("treeLineup", "us", { TT.starter("us", "ground").key, HELI })
  R.run(1)
  press("Line_" .. HELI)
  R.run(0.6)
  press("AmmoBtn")
  R.run(1.6)
  W, st = C.workshopState()
  check(W.on and st and st.key == HELI, "直升机的整备开了")
  local outer = nil
  for ci, g in ipairs(st.cards) do if g.name == "outer" then outer = ci end end
  press("Station_" .. tostring(outer))
  R.run(1.2)
  check(vis("Cmp_vh") ~= nil and vis("Cmp_min") ~= nil and vis("Cmp_tw") == nil and vis("Stat_heavy") ~= nil, "直升机：右栏只有极速、续航、重量（没有推重比、转弯）")
  shot("05_heli")
else
  -- 06：手机（1000 × 500 的画布）：全景 + 选中一个挂点
  shot("06_mobile_overview")
  local midCard = nil
  for ci, g in ipairs(st.cards) do if g.name == "mid" then midCard = ci end end
  press("Station_" .. tostring(midCard))
  R.run(1.2)
  shot("06_mobile")
end

check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | ", 1, math.min(#R.errors, 3)))
print("拍好：" .. table.concat(shots, " "))
T.summary()
