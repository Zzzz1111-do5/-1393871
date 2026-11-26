-- 俄系原模型（用户 11-26 给的苏-57、T-50、米格-29、苏-35S、苏-25）在游戏里拼出来对不对：python3 tools/mock/run.py tools/mock/rugear.lua
--   假装 Studio 里导入了原模型（T.fakeImportAir），放一架让客户端拼出来，再用 AirModels.pose 摆各种操纵量，检查：
--   ① 用的是自己的原模型（苏-27 借苏-35S 的），程序拼的起落架没了
--   ② 两套起落架网格（tools/models/sf_gear.py）：放下时画放下那套（腿、打开的舱门）、关好的门板（GearUp）藏着；
--      收到一半腿转过去了；收到底腿、舱门藏起来、关好的门板出来；苏-25 没有舱门，收好的腿留在舱里
--   ③ 原模型的喷口：苏-57 拉杆时整个喷口绕喉道偏 15°（全向），苏-35S 只在外倾 32° 的斜面里偏（俯仰分量 15·cos32 ≈ 12.7°），
--      苏-27 借苏-35S 的模型但没有推力矢量：不偏；调节片开加力时张开
--   ④ 米格-29 / 苏-25 的挂点挂在模型自己的挂架 / 导轨下面：不另画挂架
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check

local G = T.boot()
G.fortsHold = true
G.Config.Bots.minPerTeam = 0
local RS = R.services.ReplicatedStorage
local IA = R.require(RS:FindFirstChild("ImportedAir"))
local AD = R.require(RS:FindFirstChild("AirDefs"))
local IDS = { "su57", "t50", "mig29", "su35", "su25", "su27" }
local keyOf = {}
for _, id in ipairs(IDS) do
  local d = AD.get(id)
  local k = IA.alias[id] or (d and d.like and IA.alias[d.like])
  if k then
    keyOf[id] = (k:gsub("~$", ""))
    T.fakeImportAir(keyOf[id])
  end
end
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 8701, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.picked = true
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
T.actAs(me, "deploy", "rifle", "base")
R.run(1.5)
T.runUntil(function() return G.round.phase == "battle" end, 90)
local hrp = P.char:FindFirstChild("HumanoidRootPart")
local AM = R.require(R.services.StarterPlayer:FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client"):FindFirstChild("AirModels"))

local function viewOf(em)
  for em2, v in pairs(C.views or {}) do if em2 == em and v.M then return v end end
end
-- 这个部件（原模型的块叫 A_<键>__<部件>_<号>）的零件
local function itemsOf(M, key, g)
  local out = {}
  for _, it in ipairs(M.items) do
    local n = tostring(it.p and it.p.Name or "")
    if n:match("^A_" .. key .. "__" .. g .. "_%d+$") then out[#out + 1] = it end
  end
  return out
end
local function shown(list)
  for _, it in ipairs(list) do if it.p.Transparency < 0.99 then return true end end
  return false
end
-- 两个姿势之间某个零件转了多少度（机体坐标）
local function turned(it, cfA, cfB)
  local a, b = cfA:Inverse() * it.p.CFrame, nil
  return a
end
local function angleBetween(c1, c2)
  local rel = c1:ToObjectSpace(c2)
  local _, ang = rel:ToAxisAngle()
  return math.deg(math.abs(ang))
end

local dx = 0
for _, id in ipairs(IDS) do
  local d = AD.get(id)
  local key = keyOf[id]
  print(string.format("—— %s（原模型 %s）", id, tostring(key)))
  if not (d and key) then
    check(false, id .. "：有定义、有原模型")
  else
    dx = dx + 110
    local x, z = hrp.Position.X + 60 + dx, hrp.Position.Z + 90
    local gy = G.airSurface(x, z)
    local e = G.spawnAircraft(P.team, id, CF(x, gy + d.gearH + 0.5, z), nil, P)
    R.run(1.2)
    local v = e and viewOf(e.model)
    check(v ~= nil and v.M ~= nil, id .. "：客户端拼出来了")
    if v and v.M then
      local M = v.M
      check(M.imported == key, string.format("%s：用的是原模型 %s（%s）", id, key, tostring(M.imported)))
      local procGear = 0
      for _, it in ipairs(M.items) do if it.tag == "gear" then procGear = procGear + 1 end end
      check(procGear == 0, id .. "：程序拼的起落架没了（原模型自己的起落架）")
      local cf = v.cf
      local function pose(c) AM.pose(M, cf, c, 0) end
      local legsN, legsL = itemsOf(M, key, "GearN"), itemsOf(M, key, "GearL")
      local up = itemsOf(M, key, "GearUp")
      local two = #up > 0
      check(#legsN > 0 and #legsL > 0, id .. "：前、左主起落架是会动的部件")
      -- ② 放下
      pose({ gear = 1, thr = 80 })
      local cDown = legsL[1] and legsL[1].p.CFrame
      check(shown(legsN) and shown(legsL), id .. "：放下时腿都在")
      if two then check(not shown(up), id .. "：放下时关好的门板（GearUp）藏着") end
      -- 收到一半
      pose({ gear = 0.5, thr = 80 })
      local cHalf = legsL[1] and legsL[1].p.CFrame
      local a = (cDown and cHalf) and angleBetween(cDown, cHalf) or 0
      check(a > 20, string.format("%s：收到一半主起落架转过去了（%.0f°）", id, a))
      -- 收到底
      pose({ gear = 0, thr = 80 })
      if two then
        check(shown(up), id .. "：收到底关好的门板出来了")
        check(not shown(legsN) and not shown(legsL), id .. "：收到底放下那套（腿、舱门）藏起来")
        local doors = 0
        for _, g in ipairs({ "GDoorML", "GDoorMR", "GDoorFL", "GDoorFR", "GDoorAL", "GDoorAR", "GDoorNL", "GDoorNR" }) do
          local l = itemsOf(M, key, g)
          if #l > 0 then doors = doors + 1 end
        end
        check(doors >= 2, string.format("%s：舱门是会动的部件（%d 扇）", id, doors))
      else
        check(shown(legsN) and shown(legsL), id .. "：没有舱门的（苏-25）收好的腿留在舱里")
      end
      -- ③ 喷口
      local noz = itemsOf(M, key, "NozL")
      if #noz > 0 then
        pose({ gear = 0, thr = 80, pit = 0 })
        local c0 = noz[1].p.CFrame
        pose({ gear = 0, thr = 80, pit = 1 })
        local c1 = noz[1].p.CFrame
        local ang = angleBetween(c0, c1)
        local want = (id == "su57" or id == "t50") and 15 or ((id == "su35") and 15 * math.cos(math.rad(32)) or 0)
        check(math.abs(ang - want) < 1.5, string.format("%s：拉杆时喷口偏 %.1f°（要 %.1f°）", id, ang, want))
        if id == "su57" then   -- 全向：偏航时也偏
          pose({ gear = 0, thr = 80, yaw = 1 })
          local cy = noz[1].p.CFrame
          check(angleBetween(c0, cy) > 5, string.format("%s：右偏时喷口也偏（%.1f°）", id, angleBetween(c0, cy)))
        end
        local pet = itemsOf(M, key, "PetL01")
        if #pet > 0 then
          pose({ gear = 0, thr = 100 })
          local p0 = pet[1].p.CFrame
          pose({ gear = 0, thr = 125 })
          local p1 = pet[1].p.CFrame
          check(angleBetween(p0, p1) > 5, string.format("%s：开加力调节片张开（%.1f°）", id, angleBetween(p0, p1)))
        end
      end
      -- ④ 挂点
      if id == "mig29" or id == "su25" then
        local load = {}
        for i, s in ipairs(d.st or {}) do load[i] = s.opts[1] end
        local M2 = AM.build(d, P.team, load)
        local nStore = 0
        for _, l in pairs(M2.stores) do nStore = nStore + #l end
        check(M2.imported == key and #M2.pylons == 0 and nStore > 0, string.format("%s：弹挂在模型自己的挂架 / 导轨下（不另画挂架：%d 个，挂了 %d 件）", id, #M2.pylons, nStore))
        if M2.model then M2.model:Destroy() end
      end
      pose({ gear = 1, thr = 80 })
      if e.model then G.removeEnt(e) end
      R.run(0.3)
    end
  end
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | ", 1, math.min(#R.errors, 3)))
T.summary()
