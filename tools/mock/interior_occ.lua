-- 内饰里的屏幕有没有被挡住（模拟器）：python3 tools/mock/run.py tools/mock/interior_occ.lua veh=<型号>
--   用户 11-22：「坦克内部屏幕会被挡住」。每个乘员位：眼睛 → 眼前 1 米以内（自己这个位置的屏幕）、在视野里的每块屏幕正中打一条线，
--   看中间隔着什么（别的乘员、内饰零件、车外模型），挡住的列出来
-- （下面开服、坐进车里同 interior_all.lua）
-- 地面载具内饰的通用测试（模拟器）：python3 tools/mock/run.py tools/mock/interior_all.lua veh=<型号> [dump=<目录>]
--   用户 11-21：所有载具都要有内饰、所有观瞄设备都要实现。每型：坐上、C 进车内（零件、乘员、屏幕都起来了，没报错）→ F2～F5 换遍乘员位（镜头在车里）→
--   每个乘员位的观瞄设备（Shift 主镜、G 备用、T 第三个）开了再关 → 开一炮 / 打一梭 → 开着走、打方向（方向盘 / T 形把跟着转）→ C 出去
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local VEH = TEST_ARGS:match("veh=(%w+)") or "m2a3"
local dumpDir = TEST_ARGS:match("dump=(%S+)")

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8101, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = "def"
me.Team = G.TEAM.def
me.Neutral = false
me:SetAttribute("Side", "def")
G.pushOne(P)
R.run(1)
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
T.actAs(me, "deploy", "rifle", "camp")
R.run(1.5)
local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))
local Map = G.Map
local def = VD.get(VEH)
print("① 坐上 " .. VEH .. "，C 进车内")
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or V3(Map.CAMP.x, 0, Map.CAMP.z)
local cx, cz = hp.X + 18, hp.Z
for k = 0, 23 do
  local a = k / 24 * math.pi * 2
  local x, z = hp.X + math.cos(a) * 20, hp.Z + math.sin(a) * 20
  if Map.isLand(x, z) and Map.slope(x, z) < 0.25 then cx, cz = x, z break end
end
local e = G.newVehicle("def", VEH, G.vehBaseAt(def, cx, cz, V3(0, 0, -1)))
R.run(0.5)
T.act("enterVeh", e.id)
R.run(1)
check(P.vehicle == e and C.drive ~= nil, "坐上了 " .. VEH)
T.runUntil(function() return G.round.phase == "battle" end, 60)
T.tap(Enum.KeyCode.C)
R.run(0.6)
local I = C.interiorState()
local cur = I.cur
check(C.interiorOn() and cur ~= nil and I.mode == "seat", "C：坐进车里（" .. tostring(I.station) .. "）")
if not cur then T.summary() return end
local nCrew = 0
for _ in pairs(cur.crew) do nCrew = nCrew + 1 end
local live = 0
for _, s in ipairs(cur.b.screens) do if s.update then live = live + 1 end end
check(#cur.b.parts > 150, "内饰零件 " .. #cur.b.parts .. " 个")
check(#cur.b.screens >= 2 and live == #cur.b.screens, string.format("屏幕 %d 块、页面都起来了（%d）", #cur.b.screens, live))
check(nCrew >= #cur.spec.order - 1, string.format("乘员 %d 个（%d 个乘员位）", nCrew, #cur.spec.order))
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
local cam = R.workspace.CurrentCamera
local function inside(tag)
  local v = C.viewById(e.id)
  local hull = v and v.hullF
  if not hull then return false end
  local q = hull:PointToObjectSpace(cam.CFrame.Position)
  local ok = math.abs(q.X) < def.W / 2 + 0.3 and q.Y > -0.3 and q.Y < def.H + 1.2 and math.abs(q.Z) < def.L / 2 + 0.3
  check(ok, string.format("%s：镜头在车里（车体坐标 %.1f, %.1f, %.1f 格）", tag, q.X, q.Y, q.Z))
  return ok
end
inside("进车内")


print("② 各乘员位看屏幕：中间有没有东西挡着")
local FK = { Enum.KeyCode.F2, Enum.KeyCode.F3, Enum.KeyCode.F4, Enum.KeyCode.F5 }
local SC = 2.8
-- 射线和零件的包围盒（长方体）求交：返回距离（格）或 nil
local function rayOBB(o, d, len, p)
  local cf, sz = p.CFrame, p.Size / 2
  local lo, ld = cf:PointToObjectSpace(o), cf:VectorToObjectSpace(d)
  -- 眼睛在这块里面：Roblox 只画朝外的面，从里面看不见它，不算挡
  if math.abs(lo.X) <= sz.X and math.abs(lo.Y) <= sz.Y and math.abs(lo.Z) <= sz.Z then return nil end
  local t0, t1 = 0, len
  for _, ax in ipairs({ { lo.X, ld.X, sz.X }, { lo.Y, ld.Y, sz.Y }, { lo.Z, ld.Z, sz.Z } }) do
    local a, dd, h = ax[1], ax[2], ax[3]
    if math.abs(dd) < 1e-9 then
      if a < -h or a > h then return nil end
    else
      local u, w = (-h - a) / dd, (h - a) / dd
      if u > w then u, w = w, u end
      t0, t1 = math.max(t0, u), math.min(t1, w)
      if t0 > t1 then return nil end
    end
  end
  return t0
end
local screenParts = {}
for _, s in ipairs(cur.b.screens) do screenParts[s.part] = true end
local groupOf = {}
for _, it in ipairs(cur.b.parts) do groupOf[it[1]] = it[2] and it[2].name end
local function crewOf(p)
  for id, cr in pairs(cur.crew) do if p:IsDescendantOf(cr.f.model) then return id end end
  return nil
end
local blockedAll, total = 0, 0
for i, name in ipairs(cur.spec.order) do
  if FK[i] then
    T.tap(FK[i])
    R.run(0.4)
    local eye = cam.CFrame.Position
    local look = cam.CFrame.LookVector
    local v = C.viewById(e.id)
    local lines = {}
    local nS, nB = 0, 0
    for _, s in ipairs(cur.b.screens) do
      local c = s.part.Position
      local to = c - eye
      local dist = to.Magnitude
      if dist < 1.0 * SC and dist > 0.05 and to.Unit:Dot(look) > 0.25 then
        nS = nS + 1
        local d = to.Unit
        local len = dist - 0.03 * SC
        local hits = {}
        for _, p in ipairs(cur.model:GetDescendants()) do
          if p:IsA("BasePart") and not screenParts[p] and p.Transparency < 0.95 and p.LocalTransparencyModifier < 0.95 then
            local t = rayOBB(eye, d, len, p)
            if t then
              local who = crewOf(p)
              local c3 = p.Color
              table.insert(hits, string.format("%s %s 组 %s 色 %d,%d,%d %s（%.2f×%.2f×%.2f 米，离眼 %.2f 米）", who and ("乘员 " .. who) or "内饰",
                p.ClassName, tostring(groupOf[p]), c3.R * 255, c3.G * 255, c3.B * 255, p.Material.Name, p.Size.X / SC, p.Size.Y / SC, p.Size.Z / SC, t / SC))
            end
          end
        end
        if v and v.M then
          for _, it in ipairs(v.M.parts) do
            local p = it[1]
            if p:IsA("BasePart") and p.Transparency < 0.95 and p.LocalTransparencyModifier < 0.95 then
              local t = rayOBB(eye, d, len, p)
              if t then table.insert(hits, string.format("车外模型 %s（%.1f×%.1f×%.1f 格，离眼 %.2f 米）", p.Name, p.Size.X, p.Size.Y, p.Size.Z, t / SC)) end
            end
          end
        end
        if #hits > 0 then
          nB = nB + 1
          table.insert(lines, string.format("    屏幕 %s（离眼 %.2f 米）被挡：%s", tostring(s.page), dist / SC, table.concat(hits, "；", 1, math.min(#hits, 4)) .. ((#hits > 4) and (" …共 " .. #hits .. " 处") or "")))
        end
      end
    end
    print(string.format("  %s：眼前 %d 块屏幕，被挡 %d 块", name, nS, nB))
    for _, l in ipairs(lines) do print(l) end
    blockedAll, total = blockedAll + nB, total + nS
  end
end
check(blockedAll == 0, string.format("各乘员位眼前的屏幕都没被挡住（%d / %d 块被挡）", blockedAll, total))
T.summary()
