-- 地图上长什么（ReplicatedStorage.Flora）：树林、灌木、石头、草丛、花丛的摆放，纯按 Map 算——同一个格子谁算都一样（每个客户端看到的树在同一个地方）
--   用户：地图要像 Arma 那样——土路、草地花丛、成片的针叶林、起伏的山丘
--   按 64 格一格，每格按格子坐标定随机种子：
--     树：18 格一个候选点（抖开）；树林是两层噪声叠出来的大片（林子里密、林缘稀、草地上偶尔一棵）；山上多针叶（冷杉、松树），低处多阔叶（白桦、橡树、枫树）；
--       林缘长小冷杉、灌木，林子里偶尔一棵枯树、一根倒木
--     灌木：林缘多、草地上零星；石头：坡陡、山高的地方多，岩坡上是成堆的岩石
--     草丛：9 格一个，草地上大半都有（高草、矮草、杂草）；花：另一层噪声圈出的一片片花地，里面开满黄花（蒲公英）
--   不长的地方：海滩沙地和水边、路面和路肩、压平的场地（据点、机场、营地、港口、机场岛）、工事旁边、太陡的崖壁（只有石头）
--   Flora.cell(cx, cz, layer) 返回这一格这一层的 { { k 模型键, x, y, z, yaw, s 缩放 }, … }；客户端（Scenery.lua）按距离摆出来
local RS = game:GetService("ReplicatedStorage")
local Map = require(RS:WaitForChild("Map"))

local Flora = {}
Flora.CELL = 64
local CELL = Flora.CELL
local noise, floor, sqrt, max, min = math.noise, math.floor, math.sqrt, math.max, math.min
local smooth = Map.smooth

-- 各层：候选点间距
Flora.LAYERS = { tree = 18, bush = 22, rock = 40, grass = 10, flower = 8 }

-- 工事（碉堡、岸防炮……）周围不长树、灌木：按 FortDefs 的摆法（开服时一样）
local fortPts = nil
local function forts()
  if fortPts then return fortPts end
  fortPts = {}
  local ok, FD = pcall(function() return require(RS:WaitForChild("FortDefs", 5)) end)
  if ok and FD and FD.layout then
    local ok2, list = pcall(FD.layout, Map)
    if ok2 and list then
      for _, f in ipairs(list) do
        local p = f.cf and f.cf.Position
        if p then table.insert(fortPts, { p.X, p.Z }) end
      end
    end
  end
  return fortPts
end
local function nearFort(x, z, r)
  for _, f in ipairs(forts()) do
    local dx, dz = x - f[1], z - f[2]
    if dx * dx + dz * dz < r * r then return true end
  end
  return false
end
local function nearPoint(x, z, r)
  for _, p in ipairs(Map.POINTS) do
    local dx, dz = x - p.x, z - p.z
    if dx * dx + dz * dz < r * r then return true end
  end
  return false
end

-- 树林密度（−1～1 左右；> 0.05 算林子）、花地（> 0.2 是一片花）
function Flora.forest(x, z)
  return noise(x / 430, z / 430, 21.7) * 0.7 + noise(x / 140, z / 140, 5.3) * 0.35 + noise(x / 47, z / 47, 9.9) * 0.1
end
function Flora.flowerField(x, z)
  return noise(x / 190, z / 190, 33.1) + noise(x / 55, z / 55, 2.2) * 0.25
end

-- 可重复的随机数：按格子坐标、层定种子
local function rng(cx, cz, salt)
  local s = (cx * 73856093 + cz * 19349663 + salt * 83492791) % 2147483647
  if s <= 0 then s = s + 2147483646 end
  return function()
    s = (s * 48271) % 2147483647
    return s / 2147483647
  end
end
local SALT = { tree = 1, bush = 2, rock = 3, grass = 4, flower = 5 }

-- 这一点能不能长东西：返回高度、坡度；不能长返回 nil
local function site(x, z, roadPad, flatMax)
  local h = Map.height(x, z)
  if h < 4 then return nil end   -- 海里、海滩、水边
  local rd, _, rw = Map.roadNear(x, z)
  if rd and rd < rw * 0.5 + roadPad then return nil end
  if Map.flatW(x, z) > (flatMax or 0.02) then return nil end
  local zs, zn = Map.coastS(x), Map.coastN(x)
  if zs and (zs - z < 70 or z - zn < 50) and h < 14 then return nil end   -- 海滩后面的沙丘
  return h, Map.slope(x, z)
end

local CONIFER = { "fir1", "fir2", "fir3", "fir4", "fir1", "fir2", "pine" }
local BROAD = { "birch1", "birch2", "oak", "maple", "birch1" }
local BUSH = { "cshrub", "dshrub", "holly", "sapling" }

local function pick(list, r) return list[floor(r * #list) + 1] end

function Flora.cell(cx, cz, layer)
  local out = {}
  local step = Flora.LAYERS[layer]
  local R = rng(cx, cz, SALT[layer])
  local n = floor(CELL / step + 0.5)
  local x0, z0 = cx * CELL, cz * CELL
  for i = 0, n - 1 do
    for k = 0, n - 1 do
      local x = x0 + (i + 0.15 + R() * 0.7) * step
      local z = z0 + (k + 0.15 + R() * 0.7) * step
      local roll, roll2, yaw, sc = R(), R(), R() * math.pi * 2, 0.85 + R() * 0.3
      if layer == "tree" then
        local f = Flora.forest(x, z)
        local p = (f > 0.05) and (0.15 + 0.75 * smooth(0.05, 0.3, f)) or 0.025   -- 林子里密、林缘稀、草地上偶尔一棵
        if roll < p then
          local h, sl = site(x, z, 7)
          if h and sl < 0.85 and not nearFort(x, z, 34) and not nearPoint(x, z, Map.POINT_R + 15) then
            local conifer = roll2 < 0.55 + 0.4 * smooth(25, 140, h)   -- 山上全是针叶，低处一半阔叶
            local k2
            if f < 0.12 and roll2 > 0.7 then k2 = (roll2 > 0.85) and "nfir" or "fir5"   -- 林缘的小树
            elseif R() < 0.025 and f > 0.15 then k2 = "deadfir"
            elseif conifer then k2 = pick(CONIFER, R())
            else k2 = pick(BROAD, R()) end
            table.insert(out, { k = k2, x = x, y = h - 0.4, z = z, yaw = yaw, s = sc })
          end
        end
      elseif layer == "bush" then
        local f = Flora.forest(x, z)
        local p = (f > -0.06 and f < 0.14) and 0.35 or ((f >= 0.14) and 0.12 or 0.05)
        if roll < p then
          local h, sl = site(x, z, 4)
          if h and sl < 0.9 and not nearFort(x, z, 24) and not nearPoint(x, z, Map.POINT_R) then
            local k2 = (f > 0.14 and R() < 0.25) and "log" or pick(BUSH, R())
            table.insert(out, { k = k2, x = x, y = h - 0.3, z = z, yaw = yaw, s = sc })
          end
        end
      elseif layer == "rock" then
        local h0 = Map.height(x, z)
        if h0 > 4 then
          local sl = Map.slope(x, z)
          local p = 0.03 + 0.55 * smooth(0.45, 1.0, sl) + ((h0 > 160) and 0.15 or 0)
          if roll < p then
            local h = site(x, z, 3)
            if h and not nearFort(x, z, 20) then
              local k2 = (sl > 0.6 and roll2 < 0.6) and "rock3" or ((roll2 < 0.5) and "rock1" or "rock2")
              table.insert(out, { k = k2, x = x, y = h - 1.2, z = z, yaw = yaw, s = sc * ((k2 == "rock3") and 1.1 or 0.8) })
            end
          end
        end
      elseif layer == "grass" then
        local f = Flora.forest(x, z)
        local p = (f > 0.2) and 0.25 or 0.6
        if roll < p then
          local h, sl = site(x, z, 1.5, 0.3)
          if h and sl < 0.9 then
            local k2 = (roll2 < 0.55) and "grass_s" or ((roll2 < 0.85) and "grass_t" or "weeds")
            table.insert(out, { k = k2, x = x, y = h - 0.1, z = z, yaw = yaw, s = sc })
          end
        end
      elseif layer == "flower" then
        local ff = Flora.flowerField(x, z)
        if ff > 0.2 and roll < 0.35 + 0.5 * smooth(0.2, 0.5, ff) and Flora.forest(x, z) < 0.15 then
          local h, sl = site(x, z, 1.5, 0.3)
          if h and sl < 0.6 then table.insert(out, { k = "flowers", x = x, y = h - 0.05, z = z, yaw = yaw, s = sc }) end
        end
      end
    end
  end
  return out
end

return Flora
