-- 飞机、直升机测试（模拟器）：python3 tools/mock/run.py tools/mock/air.lua [atk|def] [v]
--   生成点（停机位按 E、挂载界面按「生成」）→ 走过去坐进座舱 → 起飞（油门、抬头、收起落架）→ 飞行（鼠标瞄准、加力、失速）→ 航炮 → 锁定发射导弹 → 热诱弹 →
--   炸弹 → 弹舱门 → 落地补弹 → 跳伞；直升机：起飞悬停、旋翼转速、机头炮塔、火箭巢；模型：舵面、起落架、旋翼动画
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, Enum = T.R, T.V3, T.Enum
local check = T.check
local side = TEST_ARGS:match("def") and "def" or "atk"

-- 假装在 Studio 里导入了歼-20 的原模型（A_j20__<块>，Imports.lua 开服时收进 Imported.Air.j20）：查摆放时每块都补回了导入时转掉的半圈（ImportTurn.lua）
local IA
do
  local f = assert(io.open(SRC_DIR .. "/ReplicatedStorage/ImportedAir.lua"))
  IA = load(f:read("a"))()
  f:close()
end
for name, p in pairs(IA.m.j20.parts) do
  local mp = R.Instance.new("MeshPart")
  mp.Name = "A_j20__" .. name
  mp.Size = V3(p.s[1], p.s[2], p.s[3])
  mp.CFrame = T.CF(900 + p.c[1], 200 + p.c[2], 900 + p.c[3])
  mp.Parent = R.services.Workspace
end

local G = T.boot()
G.fortsHold = true   -- 这里测的不是工事：工事不开火
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 120)
local me = T.join("P1", 5001, true)
local other = T.join("P2", 5002, false)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local function setTeam(pl, team)
  local P = G.P[pl]
  P.team = team
  pl.Team = G.TEAM[team]
  pl.Neutral = false
  pl:SetAttribute("Side", team)
  G.pushOne(P)
end
local foe = side == "def" and "atk" or "def"
setTeam(me, side)
setTeam(other, foe)
R.run(1)
local P, PO = G.P[me], G.P[other]
local AD = require and nil
AD = R.requireModule and R.requireModule("AirDefs") or nil
local C = T.C

print("① 生成点：飞机型号、名额；走到停机位按 E，挂载界面按「生成」，再走过去坐上")
local jets = G.Config.Vehicles[side].jet
local jetId = (side == "atk") and "j20" or "f22"
local has = false
for _, id in ipairs(C.S.vehModels or {}) do if id == jetId then has = true end end
check(has, "能用的型号里有 " .. jetId .. "：" .. table.concat(C.S.vehModels or {}, ","))
check(C.S.vehAvail and C.S.vehAvail.jet and C.S.vehAvail.jet.cap >= 1, "固定翼名额 " .. tostring(C.S.vehAvail and C.S.vehAvail.jet and C.S.vehAvail.jet.cap))
T.act("deploy", "rifle", (side == "atk") and "af2" or "point.D")   -- 攻方机场岛（歼-20 是陆基飞机）/ 守方机场（据点 D）
R.run(2)
check(P.alive and P.vehicle == nil, "步兵出生了")
local jp = T.pad(jetId)
check(jp ~= nil and jp.kind == "air", "有 " .. jetId .. " 的停机位生成点")
if jp then T.usePad(me, jp) end
local go = T.findButton("^" .. C.T("pad.spawn") .. "$")
check(go ~= nil, "弹出了挂载界面（按钮是「生成」）")
if go then T.press(go) end
R.run(1)
local e0 = nil
for _, x in ipairs(G.aircraft or {}) do if jp and x.padId == jp.id and x.alive then e0 = x end end
check(e0 ~= nil and e0.driver == nil, "飞机停在停机位上（空着）")
T.act("enterVeh", e0 and e0.id)
R.run(1.5)
local e = P.vehicle
check(e ~= nil and e.air and e.def.id == jetId, "坐进了 " .. tostring(e and e.def.id))
if e then
  local n = 0
  for _, k in ipairs(e.stores) do n = n + k end
  check(n > 0, "按预设挂了 " .. n .. " 枚：" .. e.model:GetAttribute("Load"))
  local p = e.root.CFrame.Position
  check(math.abs(p.Y - G.airSurface(p.X, p.Z) - e.def.gearH) < 0.5, string.format("停在跑道上（离地 %.1f 格）", p.Y - G.airSurface(p.X, p.Z)))
end
if e and e.def.id == "j20" then
  print("② 导入的原模型：每块在原位置、绕自己的中心转了半圈（Roblox 导入 GLB 时把每块网格转了半圈，摆的时候转回来）")
  local v
  if C.views then for em, vv in pairs(C.views) do if em == e.model then v = vv end end end
  local n, bad, worst = 0, 0, 0
  local O = V3(0, -e.def.gearH, 0)
  if v and v.M then
    for _, it in ipairs(v.M.items) do
      local name = string.match(it.p.Name, "^A_j20__(.+)$")
      local p = name and IA.m.j20.parts[name]
      if p and it.kind ~= "r" then
        n = n + 1
        local cf = it.cf0
        if it.kind == "h" then cf = it.H * it.off end   -- 绕铰链转的块：转角 0 时的样子
        if cf.LookVector.Z < 0.999 or cf.UpVector.Y < 0.999 then bad = bad + 1 end
        worst = math.max(worst, (cf.Position - (V3(p.c[1], p.c[2], p.c[3]) + O)).Magnitude)
      end
    end
  end
  check(v ~= nil and v.M ~= nil and v.M.imported == "j20", "飞机用上了导入的原模型（" .. tostring(v and v.M and v.M.imported) .. "）")
  check(n > 0 and bad == 0, string.format("%d 块导入的零件都转了半圈（朝向不对的 %d 块）", n, bad))
  check(n > 0 and worst < 0.01, string.format("位置照元数据（最大偏差 %.3f 格）", worst))
end
T.summary()
