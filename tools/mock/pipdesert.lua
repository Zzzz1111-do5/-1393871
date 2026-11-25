-- 瞄准镜画中画在没有海的地图上（模拟器）：python3 tools/mock/run.py tools/mock/pipdesert.lua [map=sands]（原来还能选 desert：沙漠风暴 11-24 删了）
--   用户 11-24：「开镜有bug你修一下 屏幕有一块色斑」——沙漠图里开镜，镜里的盐碱地、砂岩画成草绿（颜色表只有岛上那几种），
--   戈壁平原（开服 FillBlock 铺的平地，画中画「全岛」那级只铺有起伏的块）透出底下垫的蓝绿海面
--   ① 选沙漠开服、建好；② 端 M4 开镜，画中画准备好；③ 镜里没有海、没有深海底，垫底的是沙地颜色的平地，高度贴着地面；
--   ④ 地形网格：每块的颜色都是这张图的地形颜色（Map.COLORS），没有回退成草绿的；没海的图多一级 64 格的网格
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local RS = R.services.ReplicatedStorage
local MAPID = TEST_ARGS:match("map=(%w+)") or "sands"

print("① 选" .. MAPID .. "开服")
local G = T.boot()
G.fortsHold = true
G.Config.Bots.minPerTeam = 0
local me = T.join("P1", 7301, true)
local C = T.C
R.run(2)
R.as("client", function() C.menuPlay() end)
R.run(0.3)
local card
for _, d in ipairs(me.PlayerGui:GetDescendants()) do if d.Name == "Map_" .. MAPID then card = d end end
check(card ~= nil, "有" .. MAPID .. "的卡片")
if card then T.press(card) end
R.run((G.Config.MapVote and G.Config.MapVote.grace or 3) + 0.5)
local clk = os.clock()
check(T.runUntil(function() return G.worldReady end, 1800), string.format("建好了（真实 %.0f 秒）", os.clock() - clk))
local Map = G.Map
check(Map.id == MAPID and RS:GetAttribute("MapId") == MAPID, "Map.id = " .. tostring(Map.id))
check(Map.info[MAPID].sea == false, "这张图没有海")
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
local P = G.P[me]
if C.menuShown and C.menuShown() then C.menuEnter() end
R.run(1)
T.actAs(me, "deploy", { primary = "m4", gadget = "medkit", throw = "grenade" }, nil)
R.run(3)
T.runUntil(function() return P.alive and me.Character ~= nil end, 60)
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)

print("② 端 M4 开镜，画中画准备好")
T.runUntil(function() local v = C.fps return v and v.optic and v.items[1] and v.items[1][1].ClassName == "MeshPart" end, 60)
local cam = R.workspace.CurrentCamera
T.mouse(true, nil, nil, Enum.UserInputType.MouseButton2)
local ready = T.runUntil(function() return C.pipReady and C.pipReady() end, 60)
check(ready, "画中画准备好了")
R.run(1.5)
-- 第三级（64 格一点）后台再算一会儿
T.runUntil(function() local st = C.pipDebug() return st.lv[3] ~= nil and not st.busy end, 60)
R.run(1)
local st, vpf, wm = C.pipDebug()
check(vpf.Visible, "镜片里是画中画")

print("③ 垫底的那层：没有海，是沙地颜色的平地")
local water, deep, plates = 0, 0, 0
local badPlate = {}
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
for _, p in ipairs(wm:GetChildren()) do
  if p.ClassName == "Part" and p.Size.X >= 2000 and p.Size.Z >= 2000 then
    plates = plates + 1
    local c = p.Color
    local r, g, b = c.R * 255, c.G * 255, c.B * 255
    local seaLike = b > r + 10 and g > r   -- 蓝绿：海面 (26, 82, 98)、深海 (10, 34, 44)
    if p.Transparency < 0.99 then
      if seaLike then
        if p.Transparency > 0.2 then water = water + 1 else deep = deep + 1 end
        table.insert(badPlate, string.format("(%d,%d,%d) 透明 %.2f", r, g, b, p.Transparency))
      end
    end
  end
end
check(plates >= 25, "垫底的大板子 " .. plates .. " 块")
check(water == 0 and deep == 0, "镜里没有海面、没有深海底：" .. (#badPlate > 0 and table.concat(badPlate, " | ") or "没有"))
-- 脚下那块板：比地面低 3 格左右（垫在地形网格下面，不挡）
local near, nd = nil, 1e9
local hp = hrp and hrp.Position or cam.CFrame.Position
for _, p in ipairs(wm:GetChildren()) do
  if p.ClassName == "Part" and p.Size.X >= 2000 and p.Transparency < 0.99 then
    local d = (V3(p.CFrame.Position.X, 0, p.CFrame.Position.Z) - V3(hp.X, 0, hp.Z)).Magnitude
    if d < nd then near, nd = p, d end
  end
end
if near then
  local top = near.CFrame.Position.Y + near.Size.Y / 2
  local gy = (Map.height(near.CFrame.Position.X, near.CFrame.Position.Z))
  check(top < gy - 1 and top > gy - 40, string.format("板子上表面 %.1f 格，比那里的地面（%.1f）低一点", top, gy))
  local c = near.Color
  check(c.R > c.B, string.format("颜色是土 / 沙的暖色（%d, %d, %d），材质 %s", c.R * 255, c.G * 255, c.B * 255, tostring(near.Material)))
end

print("④ 地形网格：颜色按这张图的地形颜色")
local nMesh, greenish, wrong = 0, 0, {}
local mats = {}
for _, d in ipairs(wm:GetDescendants()) do
  if d.ClassName == "MeshPart" and d.Name:sub(1, 11) == "PipTerrain_" then
    nMesh = nMesh + 1
    local m = d.Material
    mats[m.Name] = (mats[m.Name] or 0) + 1
    local want = Map.COLORS and Map.COLORS[m.Name]
    local c = d.Color
    if want and (math.abs(c.R - want.R) > 0.01 or math.abs(c.G - want.G) > 0.01 or math.abs(c.B - want.B) > 0.01) then
      table.insert(wrong, m.Name)
    end
    if m.Name ~= "Grass" and m.Name ~= "LeafyGrass" and c.G > c.R + 0.05 and c.G > c.B + 0.05 then greenish = greenish + 1 table.insert(wrong, m.Name .. "（绿）") end
  end
end
local ml = {}
for k, n in pairs(mats) do table.insert(ml, k .. "×" .. n) end
table.sort(ml)
check(nMesh > 0, "地形网格 " .. nMesh .. " 块：" .. table.concat(ml, "、"))
check(Map.COLORS ~= nil, "这张图带地形颜色表（Map.COLORS）")
check(#wrong == 0 and greenish == 0, "每块网格的颜色都对（不对的：" .. (#wrong > 0 and table.concat(wrong, "、") or "没有") .. "）")
check(st.lv[3] ~= nil, "没海的图多一级 64 格的网格（戈壁平原远处也是真的地面）")
T.mouse(false, nil, nil, Enum.UserInputType.MouseButton2)
R.run(0.5)
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
