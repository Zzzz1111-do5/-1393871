-- 沙海两边主基地测试（用户 11-24：「军事基地应该在一起」「固定两边都在双方各自固定位置出生」「做一个军事基地营地，一整套细节做到极致」
--   「沙海加载时间太长」）：开服就建沙海；两座基地（FOB.lua）都建出来、零件够多；车场车位、三个直升机坪、跑道上的飞机召唤位都在自己基地里；
--   出生只有「主基地」「主基地机场」两处，快速加入出生在自己基地的出生广场上、朝着战场；地形开服只写两边基地一带，其余后台写
--   python3 tools/mock/run.py tools/mock/fob.lua
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local check = T.check
local wall0 = os.clock()

print("① 开服就建沙海")
local G = T.boot()
G.fortsHold = true
local p1 = T.join("P1", 6101, true)
local p2 = T.join("P2", 6102, false)
local ok = T.runUntil(function() return G.worldReady end, 900)
check(ok and G.mapId == "sands", "沙海建好了（" .. tostring(G.mapId) .. "）")
local Map = G.Map
print(string.format("  开服写的起伏块 %s 块，后台还剩 %s 块（墙钟 %.0f 秒）", tostring(G.terrainChunks), tostring(G.terrainRest), os.clock() - wall0))
check(Map.BASES and Map.BASES.atk and Map.BASES.def, "两边主基地的定义（Map.BASES）")

print("② 两座基地都建出来了")
local scen = R.services.Workspace:FindFirstChild("Map") and R.services.Workspace.Map:FindFirstChild("Scenery")
for _, side in ipairs({ "atk", "def" }) do
  local f = scen and scen:FindFirstChild("FOB_" .. side)
  local n = 0
  local kinds = {}
  if f then
    for _, d in ipairs(f:GetDescendants()) do
      if d:IsA("BasePart") then n = n + 1 end
    end
    for _, c in ipairs(f:GetChildren()) do kinds[c.Name] = true end
  end
  check(f ~= nil and n > 4000, string.format("%s 主基地 %d 个零件", side, n))
  local miss = {}
  for _, k in ipairs({ "Perimeter", "ECP", "Roads", "Spawn", "MotorPool", "Helipads", "Command", "Living", "Services", "Logistics", "Airfield", "Berm" }) do
    if not kinds[k] then table.insert(miss, k) end
  end
  check(#miss == 0, side .. "：营区、检查站、出生广场、车场、直升机坪、指挥中心、生活区、保障、后勤、机场、土堤都有" .. (#miss > 0 and ("（缺 " .. table.concat(miss, " ") .. "）") or ""))
end

print("③ 召唤位都在自己基地里")
for _, side in ipairs({ "atk", "def" }) do
  local B = Map.BASES[side]
  local R0 = B.rect
  local veh, heli, jet, out = 0, 0, 0, 0
  for _, p in ipairs(G.pads or {}) do
    if p.team == side then
      local q = p.base.Position
      local inside = q.X >= R0.x0 and q.X <= R0.x1 and q.Z >= R0.z0 and q.Z <= R0.z1
      if not inside then out = out + 1 end
      if p.kind == "veh" then veh = veh + 1 elseif p.heli then heli = heli + 1 else jet = jet + 1 end
    end
  end
  check(veh >= 4 and heli == 3 and jet == 4 and out == 0, string.format("%s：地面车位 %d、直升机坪 %d、飞机 %d，基地外 %d 个", side, veh, heli, jet, out))
end

print("④ 出生只在自己主基地")
for _, side in ipairs({ "atk", "def" }) do
  local list = G.spawnList(side, nil)
  local ids = {}
  for _, s in ipairs(list) do table.insert(ids, s.id) end
  check(#list == 2 and list[1].id == "base" and list[2].id == "baseAir", side .. " 的出生点：" .. table.concat(ids, " "))
end
R.run(1)
for _, pl in ipairs({ p1, p2 }) do T.actAsRemote(pl, "quickJoin") end
T.runUntil(function() return G.P[p1] and G.P[p1].alive and G.P[p2] and G.P[p2].alive end, 60)
for _, pl in ipairs({ p1, p2 }) do
  local P = G.P[pl]
  local ch = pl.Character
  local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
  local B = P and Map.BASES[P.team]
  if hrp and B then
    local p = hrp.Position
    local d = math.sqrt((p.X - B.spawn.x) ^ 2 + (p.Z - B.spawn.z) ^ 2)
    local look = hrp.CFrame.LookVector
    check(d < 30 and look.Z * B.face > 0.7, string.format("%s（%s）出生在自己基地的出生广场（离广场中心 %.0f 格）、朝着战场", pl.Name, P.team, d))
  else
    check(false, pl.Name .. " 没出生")
  end
end
check(G.P[p1] and G.P[p2] and G.P[p1].team ~= G.P[p2].team, "两个人分在两边")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
print(string.format("用时 %.0f 秒", os.clock() - wall0))
T.summary()
