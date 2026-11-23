-- Roblox全面大战场（客户端）——从原车模型挖出来的内腔（tools/models/carve.py 写的 ReplicatedStorage.CavityMeta）给内饰代码查：
--   用户 11-23：「改成在原车内部雕刻出来内饰」「这样各种载具的从外面可以看得见的窗户跟内部的内饰就能对得上了」
--   Cav.get(模型键, 座圈中心 piv（格）) → 查询对象，坐标是内饰用的米（相对座圈中心，X 右、Y 上、−Z 朝前），跟 InteriorDefs 一样：
--     q:floor(x, z) / q:roof(x, z)    这一点正下方的内腔地板、正上方的内腔顶（米；这一列没有内腔返回 nil）
--     q:space(名字)                   只查某一个空间（"Hull" 车体 / "Tur" 炮塔 / "Cab" 驾驶室……）
--     q:walls(z, y)                   这个前后位置、这个高度上内腔左右两边的墙（x 最小、最大，米）
--     q.win                           窗户：{ c 中心, n 朝外, up, w 宽, h 高 }（米、相对座圈中心）
--     q.anchors                       carve.json 里点的乘员位（眼位、座椅……，米）
--     q.ring                          座圈半径（米）
local RS = game:GetService("ReplicatedStorage")
local S = 2.8

local Cav = {}
local META = nil
local function meta()
  if META == nil then
    local m = RS:FindFirstChild("CavityMeta")
    local ok, r = pcall(function() return m and require(m) end)
    META = (ok and type(r) == "table") and r or false
  end
  return META or nil
end

local B64 = {}
do
  local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  for i = 1, 64 do B64[string.byte(chars, i)] = i - 1 end
end
local function unb64(s)
  local out, n = table.create(#s * 3 // 4), 0
  for i = 1, #s, 4 do
    local a, b, c, d = string.byte(s, i, i + 3)
    local x = B64[a] * 262144 + B64[b] * 4096 + (B64[c] or 0) * 64 + (B64[d] or 0)
    out[n + 1] = x // 65536 % 256
    out[n + 2] = x // 256 % 256
    out[n + 3] = x % 256
    n += 3
  end
  local pad = (string.sub(s, -2) == "==") and 2 or ((string.sub(s, -1) == "=") and 1 or 0)
  return out, n - pad
end

-- 一张高度表解成两张数组（格；没有内腔 = nil）
local function decode(hm)
  local lo, nlo = unb64(hm.lo)
  local hi = unb64(hm.hi)
  local n = hm.nx * hm.nz
  local L, H = table.create(n), table.create(n)
  local span = hm.y1 - hm.y0
  for i = 0, math.min(n, nlo // 2) - 1 do
    local a = lo[i * 2 + 1] + lo[i * 2 + 2] * 256
    local b = hi[i * 2 + 1] + hi[i * 2 + 2] * 256
    if a ~= 65535 then
      L[i + 1] = hm.y0 + span * a / 65534
      H[i + 1] = hm.y0 + span * b / 65534
    end
  end
  return { x0 = hm.x0, z0 = hm.z0, d = hm.d, nx = hm.nx, nz = hm.nz, L = L, H = H }
end

local cache = {}
local Q = {}
Q.__index = Q

-- 格坐标里查一列（最近的那列）
local function col(t, X, Z)
  local i = math.floor((X - t.x0) / t.d + 0.5)
  local k = math.floor((Z - t.z0) / t.d + 0.5)
  if i < 0 or k < 0 or i >= t.nx or k >= t.nz then return nil, nil end
  local j = i * t.nz + k + 1
  return t.L[j], t.H[j]
end

function Q:_cols(x, z)
  local X, Z = self.piv.X + x * S, self.piv.Z + z * S
  local bl, bh = nil, nil
  for _, t in ipairs(self.list) do
    local l, h = col(t, X, Z)
    if l then
      bl = bl and math.min(bl, l) or l
      bh = bh and math.max(bh, h) or h
    end
  end
  return bl, bh
end
function Q:floor(x, z)
  local l = self:_cols(x, z)
  return l and (l - self.piv.Y) / S or nil
end
function Q:roof(x, z)
  local _, h = self:_cols(x, z)
  return h and (h - self.piv.Y) / S or nil
end
-- 这个前后位置、这个高度上的内腔左右边（米）：按列扫
function Q:walls(z, y)
  local Y = self.piv.Y + y * S
  local Z = self.piv.Z + z * S
  local xmin, xmax = nil, nil
  for _, t in ipairs(self.list) do
    for i = 0, t.nx - 1 do
      local X = t.x0 + i * t.d
      local l, h = col(t, X, Z)
      if l and l <= Y and h >= Y then
        local xm = (X - self.piv.X) / S
        xmin = xmin and math.min(xmin, xm) or xm
        xmax = xmax and math.max(xmax, xm) or xm
      end
    end
  end
  return xmin, xmax
end
function Q:space(name)
  local t = self.byName[name]
  if not t then return nil end
  return setmetatable({ piv = self.piv, list = { t }, byName = self.byName, win = self.win, anchors = self.anchors, ring = self.ring }, Q)
end

function Cav.get(mkey, piv)
  local M = meta()
  local e = M and M[mkey]
  if not e then return nil end
  local c = cache[mkey]
  if not c then
    c = { byName = {}, list = {} }
    for name, sp in pairs(e.spaces or {}) do
      local t = decode(sp.hm)
      t.g = sp.g
      c.byName[name] = t
      table.insert(c.list, t)
    end
    cache[mkey] = c
  end
  local V = Vector3.new
  local function m(p) return (V(p[1], p[2], p[3]) - piv) / S end
  local win = {}
  for _, w in ipairs(e.win or {}) do
    table.insert(win, { c = m(w.c), n = V(w.n[1], w.n[2], w.n[3]), up = V(w.up[1], w.up[2], w.up[3]), w = w.w / S, h = w.h / S })
  end
  local anchors = {}
  for k, p in pairs(e.anchors or {}) do anchors[k] = m(p) end
  local ring = nil   -- 座圈半径（米；挖的时候座圈开口的半径）
  for _, sp in pairs(e.spaces or {}) do if sp.ring then ring = math.max(ring or 0, sp.ring / S) end end
  return setmetatable({ piv = piv, list = c.list, byName = c.byName, win = win, anchors = anchors, ring = ring }, Q)
end

return Cav
