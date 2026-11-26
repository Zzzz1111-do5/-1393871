-- 喷口、螺旋桨对不对得上原模型（模拟器）：python3 tools/mock/run.py tools/mock/airnoz.lua [out=<输出.json>] [ids=j6,j10,…]
--   用户 11-26「发动机的 bug 是螺旋桨建模位置歪了 且发动机不会动」：假装 Studio 里导入了原模型，放一架飞机让客户端拼出来，
--   程序画的涡轮 / 尾锥 / 火焰稳定器 / 喷口热光 / 推力矢量喷口外罩换算回原模型坐标，检查：
--   ① 都在原模型的喷口里（ImportedAir 的 noz，tools/models/nozray.py 量的）：离喷口轴不超过内径，涡轮在出口往里、在原模型自己那层前面
--   ② 两台发动机共用一个喷口的（歼-6）只画一份
--   ③ MQ-9 / 攻击-2：螺旋桨（原模型拆出来的 Prop）绕桨轴转，桨毂不动、转快了桨叶变虚、出桨盘
--   out= 把程序画的零件写成 JSON（tools/models/nozcheck.py 叠到原模型的尾部特写上看）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check

local IDS = { "j6", "j8", "j10", "j11", "j15t", "j16", "j20", "j35", "f35", "h6k", "f15", "f14", "f16", "mq9", "gj2" }
local ids0 = TEST_ARGS:match("ids=([%w_,]+)")
if ids0 then
  IDS = {}
  for s in ids0:gmatch("[^,]+") do IDS[#IDS + 1] = s end
end
local OUT = TEST_ARGS:match("out=(%S+)")

local G = T.boot()
G.fortsHold = true
G.Config.Bots.minPerTeam = 0
local RS = R.services.ReplicatedStorage
local IA = R.require(RS:FindFirstChild("ImportedAir"))
local keyOf = {}
for _, id in ipairs(IDS) do
  local k = IA.alias[id]
  if k then
    keyOf[id] = (k:gsub("~$", ""))
    T.fakeImportAir(keyOf[id])
  end
end
T.fakeImportAir("tvc")
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 8601, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.picked = true
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
T.actAs(me, "deploy", "rifle", "base")
R.run(1.5)
T.runUntil(function() return G.round.phase == "battle" end, 90)
local AD = R.require(RS:FindFirstChild("AirDefs"))
local hrp = P.char:FindFirstChild("HumanoidRootPart")

local function viewOf(em)
  for em2, v in pairs(C.views or {}) do if em2 == em and v.M then return v end end
end
-- JSON（只写用到的几种值）
local function js(v)
  local t = type(v)
  if t == "table" then
    if #v > 0 or next(v) == nil then
      local o = {}
      for i = 1, #v do o[i] = js(v[i]) end
      return "[" .. table.concat(o, ",") .. "]"
    end
    local o = {}
    for k, x in pairs(v) do o[#o + 1] = string.format("%q", tostring(k)) .. ":" .. js(x) end
    return "{" .. table.concat(o, ",") .. "}"
  elseif t == "number" then
    return string.format("%.4f", v)
  elseif t == "boolean" then
    return tostring(v)
  end
  return string.format("%q", tostring(v))
end

local dump = {}
local dx = 0
for _, id in ipairs(IDS) do
  local d = AD.get(id)
  local key = keyOf[id]
  print(string.format("—— %s（原模型 %s）", id, tostring(key)))
  if not d or not key then
    check(false, id .. " 没有定义或原模型")
  else
    dx = dx + 90
    local x, z = hrp.Position.X + 60 + dx, hrp.Position.Z + 80
    local gy = G.airSurface(x, z)
    local e = G.spawnAircraft(P.team, id, CF(x, gy + d.gearH + 0.5, z), nil, P)
    R.run(1.2)
    local v = e and viewOf(e.model)
    check(v ~= nil and v.M ~= nil, id .. "：客户端拼出来了")
    if v and v.M then
      local M = v.M
      check(M.imported == key, string.format("%s：用的是原模型 %s（%s）", id, key, tostring(M.imported)))
      local O = M.imp and M.imp.O or V3(0, 0, 0)
      local I = M.imp and M.imp.info or {}
      local inv = v.cf:Inverse()
      local function mpos(p) return inv * p.Position - O end   -- 原模型坐标
      local nozs = {}
      for _, nz in ipairs(I.noz or {}) do nozs[#nozs + 1] = { x = nz[1], y = nz[2], z = nz[3], r = nz[4], deep = nz[5] } end
      local function nearestNoz(q)
        local best, bd = nil, math.huge
        for _, n in ipairs(nozs) do
          local dd = math.sqrt((q.X - n.x) ^ 2 + (q.Y - n.y) ^ 2)
          if dd < bd then best, bd = n, dd end
        end
        return best, bd
      end
      local parts, bad, cores = {}, {}, {}
      for _, it in ipairs(M.items) do
        local p = it.p
        if p and p:IsA("BasePart") then
          local q = mpos(p)
          local what = (it.tag == "eng" and "eng") or (it.holder and "holder") or (it.core and "core") or (it.tag == "tvc" and "tvc") or nil
          if what and #nozs > 0 then
            local n, rr = nearestNoz(q)
            local lim = (what == "tvc") and n.r * 1.15 or n.r * 1.02
            if rr > lim then bad[#bad + 1] = string.format("%s 离喷口轴 %.2f（内径 %.2f）", what, rr, n.r) end
            if what == "eng" or what == "holder" then
              local depth = n.z - q.Z
              if depth < 0.05 or depth > 1.8 * n.r + 0.05 then bad[#bad + 1] = string.format("%s 在出口往里 %.2f（半径 %.2f）", what, depth, n.r) end
              if n.deep and depth > n.deep then bad[#bad + 1] = string.format("%s 在原模型自己那层后面（往里 %.2f，那层 %.2f）", what, depth, n.deep) end
            end
            if what == "core" then cores[n] = (cores[n] or 0) + 1 end
          end
          if not tostring(p.Name):match("^A_" .. key .. "__") then
            local cf = inv * p.CFrame
            local r = { cf:GetComponents() }
            parts[#parts + 1] = { n = p.Name, tag = tostring(it.tag or ""), what = what or "", kind = it.kind, c = { q.X, q.Y, q.Z }, s = { p.Size.X, p.Size.Y, p.Size.Z },
              R = { r[4], r[5], r[6], r[7], r[8], r[9], r[10], r[11], r[12] }, sh = p:IsA("Part") and tostring(p.Shape) or "Mesh" }
          end
        end
      end
      if #nozs > 0 and d.kind == "jet" and not d.prop then
        check(#bad == 0, string.format("%s：涡轮、火焰稳定器、热光、喷口外罩都在原模型的喷口里%s", id, (#bad > 0) and ("（" .. table.concat(bad, "；", 1, math.min(#bad, 4)) .. "）") or ""))
        local dup = false
        for _, k in pairs(cores) do if k > 1 then dup = true end end
        check(not dup, id .. "：一个喷口只画一份热光（两台发动机共用一个喷管的不叠两份）")
      end
      if I.prop then   -- 螺旋桨：转起来绕桨轴，桨毂不动
        local blade, hub
        for _, it in ipairs(M.items) do
          local n = tostring(it.p and it.p.Name or "")
          if n:match("__Prop_%d+$") then blade = it end
          if n:match("__PropHub_%d+$") then hub = it end
        end
        check(blade ~= nil and hub ~= nil, id .. "：螺旋桨桨叶、整流罩是会转的部件")
        if blade and hub then
          local a0, h0 = inv * blade.p.CFrame, mpos(hub.p)
          for _ = 1, 12 do   -- 没人开的飞机：服务器每帧会把油门写回去，一直给着
            e.model:SetAttribute("Thr", 80)
            R.run(0.1)
          end
          inv = v.cf:Inverse()
          local a1, h1 = inv * blade.p.CFrame, mpos(hub.p)
          local hubAxis = V3(I.prop.p[1], I.prop.p[2], I.prop.p[3])
          local ang = math.acos(math.max(-1, math.min(1, a0.RightVector:Dot(a1.RightVector))))
          local drift = (V3(h1.X, h1.Y, 0) - V3(hubAxis.X, hubAxis.Y, 0)).Magnitude
          print(string.format("  1.2 秒桨叶转了 %.0f°，整流罩离桨轴 %.3f 格", math.deg(ang), drift))
          check(ang > math.rad(5), id .. "：螺旋桨在转")
          check(drift < 0.05 and (h1 - h0).Magnitude < 0.05, id .. "：整流罩绕桨轴转（不歪、不晃）")
          print(string.format("  油门 %s、螺旋桨转速 %s、桨叶透明度 %.2f、pblur %s、Thr 属性 %s", tostring(v.c and v.c.thr), tostring(v.rpmP), blade.p.Transparency, tostring(M.pblur), tostring(e.model:GetAttribute("Thr"))))
          if (v.c and v.c.thr or 0) > 50 then
            check(blade.p.Transparency > 0.5, string.format("%s：转快了桨叶变虚（透明度 %.2f）", id, blade.p.Transparency))
          else   -- 服务器那边每帧把油门写回去了（无人机自己的控制）：只看慢车照样转、桨叶清楚
            check(blade.p.Transparency < 0.1 and (v.rpmP or 0) > 20, string.format("%s：慢车时螺旋桨照样转、桨叶看得清（转速 %.0f）", id, v.rpmP or 0))
          end
        end
      end
      dump[id] = { key = key, O = { O.X, O.Y, O.Z }, noz = I.noz or {}, prop = I.prop, parts = parts }
    end
    if e and e.model then
      if G.removeVehicle then pcall(G.removeVehicle, e) else e.model:Destroy() end
    end
    R.run(0.3)
  end
end
if OUT then
  local f = io.open(OUT, "w")
  f:write(js(dump))
  f:close()
  print("写好了 " .. OUT)
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
