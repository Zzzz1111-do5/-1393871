-- 全面大战场——地图的「卫星图」：按 Map.lua 的高度、材质一个像素一个像素算颜色（客户端 MapUI 用 EditableImage 画小地图、部署地图）
--   用户 11-19：右上角小地图显示内容更精细、颜色更暗淡、更拟真（原来是按高度分几档的色块，110 × 110 格）
--   · 海：按水深从浅滩的灰绿到深海的墨蓝，海底的起伏也带一点阴影；岸边一圈浅色的浪
--   · 陆地：按地形材质（沙滩、草地、深色草、土路、岩石、板岩）上色，高处偏灰；山体阴影（光从西北来，坡朝东南的暗）；
--     压平的场地（据点、营地、港口、停机坪）是夯过的土色；跑道是沥青
--   · 整体压暗、去饱和；加两层噪声的斑驳（不然一块块平涂，像卡通）
--   画法：paint(Map, P, r0, r1, buf) 把第 r0～r1−1 行算进 buf（RGBA，每行 P.w 个像素；buf 从第 r0 行开始放）；
--     P = { x0, z0 世界坐标左上角, step 每像素几格, w, h 像素, detail 要不要按材质（细节块要，整张底图只按高度、坡度估） }
--     分几次画（每帧画几行）时 P 记着上一行的高度（算阴影用）
local MapPaint = {}

local floor, sqrt, max, min = math.floor, math.sqrt, math.max, math.min
local noise = math.noise

local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function smooth(a, b, v)
  local t = clamp((v - a) / (b - a), 0, 1)
  return t * t * (3 - 2 * t)
end

-- 材质的底色（暗、灰一点：夜里的地图、卫星图那样）
local COL = {
  Sand = { 146, 136, 110 },
  Grass = { 76, 90, 58 },
  LeafyGrass = { 60, 74, 48 },
  Ground = { 104, 92, 74 },
  Rock = { 100, 98, 92 },
  Slate = { 82, 82, 80 },
  Mud = { 84, 72, 58 },
  Concrete = { 118, 116, 110 },   -- 港口码头平地
  Asphalt = { 70, 72, 74 },       -- 港口坡道
  Sandstone = { 150, 118, 86 },   -- 沙漠：台地、古城
  Salt = { 170, 166, 154 },       -- 沙漠：盐碱地
}
MapPaint.COL = COL
local HIGH = { 96, 98, 88 }                  -- 高处的草偏灰绿
local PAD = { 88, 86, 78 }                   -- 压平的场地：夯土、水泥地
local TARMAC = { 48, 50, 52 }                -- 跑道
local SHALLOW, MID, DEEP = { 82, 100, 96 }, { 42, 62, 74 }, { 19, 30, 43 }
local SURF = { 128, 134, 126 }
-- 光从西北上方来（北是 −Z、西是 −X）
local LX, LY, LZ = -0.62, 0.62, -0.48
do
  local l = sqrt(LX * LX + LY * LY + LZ * LZ)
  LX, LY, LZ = LX / l, LY / l, LZ / l
end

local function runwayAt(Map, x, z)
  for _, k in ipairs({ "AIRFIELD", "AFIELD2" }) do
    local A = Map[k]
    if A and A.len and math.abs(x - A.x) <= A.len / 2 and math.abs(z - A.z) <= (A.wid or 90) / 2 then return true end
  end
  return false
end

-- 底图（没按材质）：按高度、坡度估一个材质（跟 Map.material 的规则差不多）
local function guessMat(Map, y, slope)
  local K, HK = Map.K or 1, Map.HK or 1
  if y < 2.2 then return "Sand" end
  if slope > 1.15 * HK / K then return (y > 120 * HK) and "Slate" or "Rock" end
  if y > 232 * HK then return "Rock" end
  if slope > 0.92 * HK / K then return "Ground" end
  return "Grass"
end

function MapPaint.paint(Map, P, r0, r1, buf)
  local w, step = P.w, P.step
  local x0, z0 = P.x0, P.z0
  local ex = P.exag or 1.5   -- 阴影夸张一点（地图上看得出山）
  local prev = P.prev
  if not prev or P.prevRow ~= r0 - 1 then   -- 上一行的高度（第一行往上多算一行）
    prev = table.create(w)
    local zp = z0 + (r0 - 0.5) * step
    for i = 0, w - 1 do prev[i + 1] = (Map.height(x0 + (i + 0.5) * step, zp)) end
  end
  local cur = table.create(w)
  for r = r0, r1 - 1 do
    local z = z0 + (r + 0.5) * step
    for i = 0, w - 1 do cur[i + 1] = (Map.height(x0 + (i + 0.5) * step, z)) end
    local base = (r - r0) * w * 4
    for i = 1, w do
      local x = x0 + (i - 0.5) * step
      local y = cur[i]
      local gx = (cur[min(w, i + 1)] - cur[max(1, i - 1)]) / (step * ((i > 1 and i < w) and 2 or 1))   -- 左右两边的差（单边差会把地形里的小台阶画成一道道竖线）
      local gz = (y - prev[i]) / step
      -- 法线 (−gx·ex, 1, −gz·ex) 和光的点积：平地 = 1，朝西北的坡亮、朝东南的暗
      local nx, nz = -gx * ex, -gz * ex
      local nl = sqrt(nx * nx + 1 + nz * nz)
      local lit = (nx * LX + LY + nz * LZ) / nl / LY
      local R, Gc, B
      if y <= 0.3 then
        local d = -y
        local t1, t2 = smooth(0, 12, d), smooth(12, 100, d)
        R = SHALLOW[1] + (MID[1] - SHALLOW[1]) * t1
        Gc = SHALLOW[2] + (MID[2] - SHALLOW[2]) * t1
        B = SHALLOW[3] + (MID[3] - SHALLOW[3]) * t1
        R, Gc, B = R + (DEEP[1] - R) * t2, Gc + (DEEP[2] - Gc) * t2, B + (DEEP[3] - B) * t2
        if d < 1.6 then   -- 岸边的浪
          local k = (1 - d / 1.6) * 0.45
          R, Gc, B = R + (SURF[1] - R) * k, Gc + (SURF[2] - Gc) * k, B + (SURF[3] - B) * k
        end
        local sh = 1 + (clamp(lit, 0.5, 1.4) - 1) * 0.35 * (1 - t2)   -- 浅海底的起伏
        local nn = 1 + noise(x / 70, z / 70, 4.4) * 0.03
        R, Gc, B = R * sh * nn, Gc * sh * nn, B * sh * nn
      else
        local slope = sqrt(gx * gx + gz * gz)
        local c
        if runwayAt(Map, x, z) then
          c = TARMAC
        else
          local m
          if P.detail or Map.desert then   -- 沙漠：底图也按材质（不然平地全按「草地」画成绿的）
            local ok, mat = pcall(Map.material, x, z, y, slope)
            m = ok and mat and mat.Name or guessMat(Map, y, slope)
          else
            m = guessMat(Map, y, slope)
          end
          c = COL[m] or COL.Grass
          if P.detail and Map.flatW and m ~= "Sand" and Map.flatW(x, z) > 0.92 then c = PAD end
        end
        R, Gc, B = c[1], c[2], c[3]
        if c == COL.Grass or c == COL.LeafyGrass then   -- 高处的草偏灰
          local k = smooth(60, 420, y) * 0.4
          R, Gc, B = R + (HIGH[1] - R) * k, Gc + (HIGH[2] - Gc) * k, B + (HIGH[3] - B) * k
        end
        local sh = clamp(lit, 0.55, 1.25)
        local nn = 1 + noise(x / 46, z / 46, 5.1) * 0.05 + noise(x / 11, z / 11, 2.7) * 0.03
        R, Gc, B = R * sh * nn, Gc * sh * nn, B * sh * nn
      end
      -- 去饱和一点、整体压暗
      local L = (R * 0.3 + Gc * 0.59 + B * 0.11)
      R, Gc, B = (L + (R - L) * 0.86) * 0.94, (L + (Gc - L) * 0.86) * 0.94, (L + (B - L) * 0.86) * 0.94
      local o = base + (i - 1) * 4
      buffer.writeu8(buf, o, clamp(floor(R + 0.5), 0, 255))
      buffer.writeu8(buf, o + 1, clamp(floor(Gc + 0.5), 0, 255))
      buffer.writeu8(buf, o + 2, clamp(floor(B + 0.5), 0, 255))
      buffer.writeu8(buf, o + 3, 255)
    end
    prev, cur = cur, prev
  end
  P.prev, P.prevRow = prev, r1 - 1
end

-- 这一块（世界坐标 x0, z0 起、边长 size 格）有没有陆地 / 浅滩（全是深海的细节块不用画：底图就够了）
function MapPaint.hasLand(Map, x0, z0, size)
  for j = 0, 6 do
    for i = 0, 6 do
      if (Map.height(x0 + i / 6 * size, z0 + j / 6 * size)) > -16 then return true end
    end
  end
  return false
end

return MapPaint
