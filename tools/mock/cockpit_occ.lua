-- 座舱里的屏幕有没有被挡住（模拟器）：python3 tools/mock/run.py tools/mock/cockpit_occ.lua air=<型号>
--   用户 11-22：「飞机的电子屏会被挡住」。坐进座舱，从眼睛往每块屏幕（眼前 1.2 米以内、在视野里的，平显不算）正中打线，
--   隔着什么都列出来（透明的玻璃、眼睛在里面的不算：Roblox 只画朝外的面）
-- （下面开服、召唤、坐进座舱同 cockpit.lua）
-- 飞机座舱测试（模拟器）：python3 tools/mock/run.py tools/mock/cockpit.lua [air=j20|j35|j16|j15t|f35|f22|a10c] [dump=<目录>]
--   用户 11-21：第一人称开飞机要有和 DCS 一样的视觉细节；座舱盖玻璃要有畸变、划痕、反光折射
--   ① 召唤、坐上，V 进座舱：座舱拼出来了（零件、屏幕、平显、座舱盖玻璃和划痕），镜头在飞行员眼位；外模型的飞行员、座舱盖玻璃不画；外面的 2D 平显不画
--   ② 屏幕边的按键：中间小点对准、左键按（换页，不开炮）
--   ③ 起飞：油门杆往前推、驾驶杆跟着拉、收起落架（手柄、三个绿灯灭）；屏幕和平显是实时的速度、高度、航向；平显的机头符号在组合玻璃中间
--   ④ 头跟着鼠标瞄准转；按住 Alt 自由看：准心不动
--   ⑤ K 导演镜头、U 藏界面
--   ⑥ V 出座舱：外模型放回来；下飞机：座舱拆掉
--   dump=<目录>：写出 interior_<型号>.json，tools/mock/interior_view.cjs 画成图
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local dumpDir = TEST_ARGS:match("dump=(%S+)")
local AIR = TEST_ARGS:match("air=(%w+)") or "j20"
local US = { f35 = true, f22 = true, a10c = true, ah64e = true, uh60 = true, ch47 = true, b2 = true }
local side = US[AIR] and "def" or "atk"

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
P.team = side
me.Team = G.TEAM[side]
me.Neutral = false
me:SetAttribute("Side", side)
G.pushOne(P)
R.run(1)
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
T.runUntil(function() return G.round.phase == "battle" end, 90)   -- 守方机场准备阶段不能出生
T.actAs(me, "deploy", "rifle", (side == "atk") and "af2" or "afield")
R.run(1.5)
check(P.alive and me.Character ~= nil, "在机场出生了")
local cam = R.workspace.CurrentCamera

print("① 召唤 " .. AIR .. "、坐上，V 进座舱")
local pad = T.pad(AIR)
check(pad ~= nil, "有能召唤 " .. AIR .. " 的召唤位")
local e
if pad then
  T.usePad(me, pad)
  local card = T.findNamed("Pick_" .. AIR)
  if card then T.press(card) end
  R.run(0.3)
  local go = T.findButton("^" .. C.T("pad.spawn") .. "$")
  if go then T.press(go) end
  R.run(1)
  for _, x in ipairs(G.aircraft or {}) do if x.padId == pad.id and x.alive then e = x end end
end
if not e then   -- 没有召唤位的（轰炸机）：在本方战斗机召唤位上直接生成
  local fp = T.pad((side == "atk") and "j20" or "f22")
  if fp then
    local c = fp.base.Position
    local d = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs")).get(AIR)
    local pos = R.Vector3.new(c.X, G.airSurface(c.X, c.Z) + d.gearH, c.Z)
    e = G.spawnAircraft(side, AIR, R.CFrame.lookAt(pos, pos + fp.base.LookVector), nil, P, 1)
    local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
    if hrp then me.Character:PivotTo(R.CFrame.new(pos + R.Vector3.new(12, 2, 0))) end
    R.run(0.5)
  end
end
check(e ~= nil, "飞机停在停机位上")
T.act("enterVeh", e and e.id)
R.run(1.5)
local fst = C.fly
check(P.vehicle == e and fst ~= nil and fst.pilot, "坐上了 " .. AIR)
T.runUntil(function() return G.round.phase == "battle" end, 60)
if not fst then T.summary() return end
T.tap(Enum.KeyCode.V)
R.run(0.6)
local I = C.interiorState()
local cur = I.cur
check(C.interiorOn() and cur ~= nil and cur.spec.air and I.mode == "seat", "按 V：坐进座舱（" .. tostring(cur and cur.key) .. "）")
if not cur then T.summary() return end
local SC = 2.8
local function rayOBB(o, d, len, p)
  local cf, sz = p.CFrame, p.Size / 2
  local lo, ld = cf:PointToObjectSpace(o), cf:VectorToObjectSpace(d)
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
print("② 座舱里看屏幕：中间有没有东西挡着")
R.run(0.5)
local eye = cam.CFrame.Position
local look = cam.CFrame.LookVector
local screenParts = {}
for _, s in ipairs(cur.b.screens) do screenParts[s.part] = true end
local groupOf = {}
for _, it in ipairs(cur.b.parts) do groupOf[it[1]] = it[2] and it[2].name end
local v = C.viewById(e.id)
local nS, nB, lines = 0, 0, {}
for _, s in ipairs(cur.b.screens) do
  if s.page ~= "hud" then
    local c = s.part.Position
    local to = c - eye
    local dist = to.Magnitude
    if dist < 1.2 * SC and dist > 0.05 and to.Unit:Dot(look) > 0.0 then
      nS = nS + 1
      local d, len = to.Unit, dist - 0.03 * SC
      local hits = {}
      for _, p in ipairs(cur.model:GetDescendants()) do
        if p:IsA("BasePart") and not screenParts[p] and p.Transparency < 0.5 and p.LocalTransparencyModifier < 0.95 and p.Material ~= Enum.Material.Glass then
          local t = rayOBB(eye, d, len, p)
          if t then
            local c3 = p.Color
            table.insert(hits, string.format("内饰 %s 组 %s 色 %d,%d,%d（%.2f×%.2f×%.2f 米，离眼 %.2f 米）", p.ClassName, tostring(groupOf[p]),
              c3.R * 255, c3.G * 255, c3.B * 255, p.Size.X / SC, p.Size.Y / SC, p.Size.Z / SC, t / SC))
          end
        end
      end
      if v and v.M and v.M.items then
        for _, it in ipairs(v.M.items) do
          local p = it.p
          if p and p:IsA("BasePart") and p.Transparency < 0.5 and p.LocalTransparencyModifier < 0.95 then
            local t = rayOBB(eye, d, len, p)
            if t then
              local q = cam.CFrame:PointToObjectSpace(p.Position) / SC   -- 零件中心在眼睛坐标系里（右、上、后，米）
              table.insert(hits, string.format("外模型 %s%s（%.1f×%.1f×%.1f 格，中心在眼睛 %.2f,%.2f,%.2f 米，离眼 %.2f 米）", p.Name, it.tag and ("·" .. tostring(it.tag)) or "",
                p.Size.X, p.Size.Y, p.Size.Z, q.X, q.Y, q.Z, t / SC))
            end
          end
        end
      end
      if #hits > 0 then
        nB = nB + 1
        table.insert(lines, string.format("    屏幕 %s（离眼 %.2f 米）被挡：%s", tostring(s.page), dist / SC, table.concat(hits, "；", 1, math.min(#hits, 4)) .. ((#hits > 4) and (" …共 " .. #hits .. " 处") or "")))
      end
    end
  end
end
print(string.format("  眼前 %d 块屏幕，被挡 %d 块", nS, nB))
for _, l in ipairs(lines) do print(l) end
check(nB == 0, string.format("座舱里眼前的屏幕都没被挡住（%d / %d 块被挡）", nB, nS))
T.summary()
