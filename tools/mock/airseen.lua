-- 飞机不撞看不见的山（模拟器）：python3 tools/mock/run.py tools/mock/airseen.lua
--   用户 11-28 夜「目前飞机开一会就自动爆炸显示被ground击杀」：雪山图的地形开服以后在后台写十几二十分钟，没写到的起伏块真的山还没出来
--   （看着是垫底的一层雪）——原来服务器、客户端都按地图的高度函数判撞地，飞进看不见的山就炸了、显示被 ground 击杀。现在：
--   ① 地形还在写：workspace 挂着 TerrainBusy；World.lua 的 G.terrainSeenH 说出没写到的那块看得见的地面（垫的那层顶），写全了的是 nil
--   ② 飞机在没写到的山「里面」（比垫的雪地高、比真的山低）飞：服务器、客户端都不判撞地，飞机好好的
--   ③ 飞机还在里面时这块不写（不把飞机埋进去）；飞机飞到它上面以后照样写
--   ④ 写全了的山照旧撞：飞机低于真的地面就炸
--   模拟器的地形射线没写过体素的列按高度函数算：这里换成「没写到的按看得见的那层」，跟 Roblox 里一样（只有写了的地形才打得到）
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)
local R, V3 = T.R, T.V3
local check = T.check

T.mapName = "snow"
T.wtMode = true
T.matchMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 1200)
local Map = G.Map

print("① 地形还在后台写")
check(R.workspace:GetAttribute("TerrainBusy") == true, "workspace 挂着 TerrainBusy（客户端看这个）")
check(type(G.terrainSeenH) == "function", "World.lua 给出看得见的地面（G.terrainSeenH）")
-- 没写到的块：模拟器的地形射线也按看得见的那层（同 Roblox：没写的地方射线打不到）
local H0 = R.terrainHeight
R.terrainHeight = function(x, z)
  local sh = G.terrainSeenH and G.terrainSeenH(x, z)
  if sh then return sh end
  return H0(x, z)
end

local me = T.join("P1", 9851, true)
T.runUntil(function() return G.round ~= nil and G.P[me] ~= nil and G.P[me].data ~= nil end, 30)
local P = G.P[me]
local C = T.C
T.leaveMenu()
R.run(1)
T.act("testDrive", "cn_j6")
T.runUntil(function() return P.alive and P.vehicle ~= nil and P.vehicle.air and C.fly ~= nil end, 60)
local ea, st = P.vehicle, C.fly
check(ea ~= nil and st ~= nil, "坐进了试驾的歼-6")
if not (ea and st) then T.summary() return end
R.run(0.5)

-- 找一块还没写的、山比垫的雪地高出两百格以上的起伏块（离基地远一点：开服前写的是基地一带）
local function findHidden()
  local Cc = Map.COLL
  local best, nHid = nil, 0
  for x0 = Cc.x0, Cc.x1 - 256, 256 do
    for z0 = Cc.z0, Cc.z1 - 256, 256 do
      local cx, cz = x0 + 128, z0 + 128
      local PL = (Map.PLAY or 8000) - 800   -- 作战区里（出了作战区要读秒判毁）
      local sh = (math.abs(cx) < PL and math.abs(cz) < PL) and G.terrainSeenH(cx, cz) or nil
      if sh and sh > 2 then
        nHid = nHid + 1
        -- 飞机要飞过的那一段（块中间往 +X 一百格）上最低的山
        local lo = math.huge
        for dx = -70, 50, 20 do lo = math.min(lo, Map.height(cx + dx, cz)) end
        if lo - sh > 90 and (not best or lo - sh > best.gap) then best = { x0 = x0, z0 = z0, sh = sh, h = Map.height(cx, cz), lo = lo, gap = lo - sh } end
      end
    end
  end
  print(string.format("   作战区里还没写全的起伏块 %d 块", nHid))
  return best
end
local hid = findHidden()
check(hid ~= nil, "找到一块还没写的山")
if not hid then T.summary() return end
print(string.format("   块 (%d, %d)：垫的雪地顶 %.0f、山 %.0f～%.0f 格", hid.x0, hid.z0, hid.sh, hid.lo, hid.h))

local function place(p, look, spd)
  st.ground = false
  st.crashed = false
  st.cf = R.CFrame.lookAt(p, p + look)
  st.vdir, st.spd, st.vel = look, spd, look * spd
  st.gearWant, st.gear = 0, 0
  G.moveEnt(ea, st.cf)
  ea.vel = st.vel
  ea.syncT, ea.syncSlack = R.clock(), 160
end

print("② 在没写到的山里面飞：不判撞地")
local cx, cz = hid.x0 + 128, hid.z0 + 128
local y = (hid.sh + hid.lo) / 2
local look = V3(1, 0, 0)
place(V3(cx - 60, y, cz), look, 160)
local dieWhy = nil
R.run(0.5)
local p = st.cf.Position
print(string.format("   飞机在 (%.0f, %.0f, %.0f)；这里的山 %.0f 格、垫的雪地 %s", p.X, p.Y, p.Z, Map.height(p.X, p.Z), tostring(G.terrainSeenH(p.X, p.Z))))
check(p.Y < Map.height(p.X, p.Z) - 20, "飞机确实在真的山里面（比山低）")
check(ea.alive and not st.crashed, "服务器、客户端都没判撞地，飞机好好的")
check(G.terrainSeenH(cx, cz) ~= nil, "飞机还在里面：这块还没写（不把飞机埋进去）")

print("③ 飞到它上面：这块照样写")
place(V3(cx, hid.h + 300, cz), V3(0, 0, -1), 120)
local okW = T.runUntil(function()
  place(V3(cx, hid.h + 300, cz), V3(0, 0, -1), 120)   -- 一直待在这块上空（扫描每半秒看一次真人身边）
  return G.terrainSeenH(cx, cz) == nil
end, 30, 0.25)
check(G.terrainSeenH(cx, cz) == nil, "飞机在上面时这块写出来了")
check(ea.alive, "飞机还好好的")

print("④ 写全了的山照旧撞")
place(V3(cx - 60, y, cz), look, 160)
T.runUntil(function() return not ea.alive end, 3, 0.05)
check(not ea.alive, "飞进写全了的山：炸了")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 800))
T.summary()
