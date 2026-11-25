-- 科技树、机库、只开载具（用户 11-25：「从1960到现代的战机和坦克 科技树」「再去做一个中 德 美 日 俄系」
--   「不要让玩家拿枪之类的了 就跟战雷完全一样 不要让玩家作为个体活动」）：python3 tools/mock/run.py tools/mock/techtree.lua
--   ① 数据：五个系 × 两棵树，每一项能开（veh / base 在 VehDefs / AirDefs 里），同一列前置连得上，每棵树第一级有白送的
--   ② 机库：没出击时盖住步兵部署页，底下是出击阵容（白送的那几辆）；当步兵出击被拒
--   ③ 出击：点阵容里一辆坦克的「出击」，人直接坐在这辆车里、出现在自己基地；车上记着科技树的名字
--   ④ 「下车」= 回机库：车没了、人阵亡，机库又出来
--   ⑤ 研究、购买、放进阵容：选研究目标 → 研究点够了研究完 → 买 → 放进阵容；客户端拿到更新
--   ⑥ 科技树界面：格子、详情、研究按钮；一局结束发研究点
local T = dofile(MOCK_DIR .. "/common.lua")
local R, Enum = T.R, T.Enum
local check = T.check

T.wtMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local TT = R.require(R.services.ReplicatedStorage:FindFirstChild("TechTree"))
local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))
local AD = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs"))

print("① 数据：五个系、两棵树")
local nAll, bad, noFree = 0, {}, {}
for _, nat in ipairs(TT.NATIONS) do
  for _, br in ipairs(TT.BRANCHES) do
    local list = TT.list[nat][br]
    local free = 0
    for _, it in ipairs(list) do
      nAll = nAll + 1
      if not (VD.get(it.play) or AD.get(it.play)) then table.insert(bad, it.key .. "→" .. tostring(it.play)) end
      if it.prev and not TT.get(it.prev) then table.insert(bad, it.key .. " 前置 " .. it.prev) end
      if (br == "air") ~= (AD.get(it.play) ~= nil) then table.insert(bad, it.key .. " 树和型号对不上") end
      if it.free then free = free + 1 end
    end
    if free == 0 then table.insert(noFree, nat .. ":" .. br) end
  end
end
check(nAll >= 150, "一共 " .. nAll .. " 项（中德美日俄 × 坦克 / 战机，1960 年到现代）")
check(#bad == 0, "每一项都开得了（型号在 VehDefs / AirDefs 里）、前置连得上" .. (#bad > 0 and ("：" .. table.concat(bad, " ", 1, math.min(8, #bad))) or ""))
check(#noFree == 0, "每棵树第一级都有白送的" .. (#noFree > 0 and ("（缺 " .. table.concat(noFree, " ") .. "）") or ""))

print("② 机库：盖住步兵部署页，当步兵出击被拒")
local me = T.join("P1", 9101, true)
local msgs = {}
local msg0 = G.msg
G.msg = function(pl, kind, key, ...) if pl == me then table.insert(msgs, tostring(key)) end return msg0(pl, kind, key, ...) end
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
R.run(1)
local C = T.C
T.leaveMenu()   -- 客户端的函数要在客户端那边调（模拟器按连接时在哪一边跑回调：在服务器这边建的按钮按了发不出去）
R.run(1)
T.runUntil(function() return type(me:GetAttribute("Tree")) == "string" end, 20)
check(type(me:GetAttribute("Tree")) == "string", "服务器把科技树存档写给了客户端（玩家属性 Tree）")
local hg = C.hangarGui
check(hg ~= nil and hg.Visible, "没出击：机库显示着")
local deployF = T.findNamed("Deploy")
check(deployF == nil or not deployF.Visible, "步兵部署页藏着")
T.act("deploy", "rifle", "base")
R.run(2)
check(not P.alive, "当步兵出击被拒（「从机库的出击阵容里挑一辆车出击」）")
local cards = {}
for _, c in ipairs(hg and hg:GetDescendants() or {}) do
  if c.Name:match("^Line_") then table.insert(cards, c) end
end
check(#cards >= 2, "出击阵容里有白送的几辆（" .. #cards .. " 张卡）")

print("③ 出击：直接坐在车里出现在自己基地")
local groundKey
for _, c in ipairs(cards) do
  local k = c.Name:sub(6)
  local it = TT.get(k)
  if it and it.branch == "ground" then groundKey = k break end
end
check(groundKey ~= nil, "阵容里有地面车：" .. tostring(groundKey))
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
R.run(0.5)
-- 机库每次刷新都重建卡片：等到开战以后再找按钮（旧卡片已经销毁了，按了没反应）
local goBtn
for _, c in ipairs(hg and hg:GetDescendants() or {}) do
  if c.Name == "Line_" .. tostring(groundKey) then goBtn = c end   -- 机库 11-25 重排：点卡片选中，右下一个大「出击」（HangarGo）
end
check(goBtn ~= nil, "阵容里有这张卡")
if goBtn then T.press(goBtn) R.run(0.2) end
for _, c in ipairs(hg and hg:GetDescendants() or {}) do
  if c.Name == "HangarGo" then goBtn = c end
end
check(goBtn ~= nil and goBtn.Name == "HangarGo", "右下有大「出击」")
-- 追踪：出击走到哪一步（失败时打印）
local trace = {}
local function tr(s) table.insert(trace, s) end
local dv0, dp0, ps0 = G.ACT.deployVeh, G.ACT.deploy, G.padSpawnAt
G.ACT.deployVeh = function(P2, key, ...)
  tr("deployVeh(" .. tostring(key) .. ") alive=" .. tostring(P2.alive) .. " pad=" .. tostring(G.treePadFor and G.treePadFor(P2.team, false) ~= nil))
  return dv0(P2, key, ...)
end
G.ACT.deploy = function(P2, choice, sid, after, ...)
  tr(string.format("deploy(%s,%s,after=%s) phase=%s alive=%s canDeployAt=%s", tostring(choice), tostring(sid), type(after), tostring(G.round.phase), tostring(P2.alive), tostring(P2.canDeployAt)))
  local r = dp0(P2, choice, sid, after, ...)
  tr("deploy 之后 P.after=" .. type(P2.after) .. " spawnId=" .. tostring(P2.spawnId))
  return r
end
G.padSpawnAt = function(P2, p, a, vid, ...)
  local e = ps0(P2, p, a, vid, ...)
  tr("padSpawnAt(" .. tostring(vid) .. ") → " .. tostring(e and e.id))
  return e
end
-- 这段时间服务器收到了哪些操作（看是不是被限流丢了）
local acts, act0 = {}, {}
for k, f in pairs(G.ACT) do
  if type(f) == "function" then
    act0[k] = f
    G.ACT[k] = function(...) acts[k] = (acts[k] or 0) + 1 return act0[k](...) end
  end
end
tr("按之前 tokens=" .. tostring(P.tokens))
local up0 = #(R.up or {})
if goBtn then
  local sig = goBtn.MouseButton1Click
  local nOn, sides = 0, {}
  for _, c in ipairs(sig.conns or {}) do if c.on then nOn = nOn + 1 table.insert(sides, tostring(c.side)) end end
  tr("按钮连接 " .. nOn .. "（" .. table.concat(sides, ",") .. "） 父级 " .. tostring(goBtn.Parent and goBtn.Parent.Name) .. "/" .. tostring(goBtn.Parent and goBtn.Parent.Parent and goBtn.Parent.Parent.Name))
  T.press(goBtn)
end
local ups = {}
for i = up0 + 1, #(R.up or {}) do table.insert(ups, R.up[i].name .. ":" .. tostring(R.up[i].args[1])) end
tr("客户端发出 " .. table.concat(ups, " "))
T.runUntil(function() return P.alive and P.vehicle ~= nil end, 15)
local e = P.vehicle
check(P.alive and e ~= nil, "人出生了、坐在车里（" .. tostring(e and e.def and e.def.id) .. "）")
if not e then
  print("  服务器给这个人的提示：" .. table.concat(msgs, " "), "alive", tostring(P.alive), "pads", #(G.pads or {}))
  local la = {}
  for k, n in pairs(acts) do table.insert(la, k .. "×" .. n) end
  print("  经过：" .. table.concat(trace, " | "), "tokens", tostring(P.tokens), "收到的操作：" .. table.concat(la, " "))
end
for k, f in pairs(act0) do G.ACT[k] = f end
G.ACT.deployVeh, G.ACT.deploy, G.padSpawnAt = dv0, dp0, ps0
check(e ~= nil and e.model:GetAttribute("TreeKey") == groundKey, "车上记着科技树的名字（" .. tostring(e and e.model:GetAttribute("TreeKey")) .. "）")
-- 暂用车（59 式借 m10，没原模型、零件拼的）按真车涂装上色，不按阵营刷沙色；驾驶界面写科技树里的名字
R.run(1)
local it59 = TT.get(groundKey)
local pb = it59 and TT.paint(it59) and TT.paint(it59).base
local v = e and C.views and C.views[e.model]
local hitPaint = false
for _, x in ipairs(v and v.M and v.M.parts or {}) do
  local c = x[1].Color
  if pb and math.abs(c.R * 255 - pb[1]) < 1.5 and math.abs(c.G * 255 - pb[2]) < 1.5 and math.abs(c.B * 255 - pb[3]) < 1.5 then hitPaint = true break end
end
check(hitPaint, "暂用车按真车涂装上色（" .. tostring(it59 and it59.name) .. "：" .. (pb and table.concat(pb, ",") or "?") .. "）")
local nameShown = false
for _, x in ipairs(me.PlayerGui:GetDescendants()) do
  if (x:IsA("TextLabel") or x:IsA("TextButton")) and it59 and (x.Text == it59.name or x.Text == it59.en) and x.Visible then nameShown = true break end
end
check(nameShown, "驾驶界面写科技树里的名字（" .. tostring(it59 and it59.name) .. "）")
local bp = me:FindFirstChildOfClass("Backpack")
local nTools = 0
for _, c in ipairs(bp and bp:GetChildren() or {}) do if c:IsA("Tool") then nTools = nTools + 1 end end
check(nTools == 0, "身上没有枪（背包里 " .. nTools .. " 样）")
R.run(1)
check(hg and not hg.Visible, "出击了：机库收起来")

print("④ 「下车」= 回机库（用户 11-25「在车上按空格也不要自动阵亡了」：空格不下车，长按 H 才回机库，也不放阵亡）")
T.remoteAs(me, "Drive", { op = "exit" })   -- 空格 / F / E 的老「下车」
R.run(2)
check(e ~= nil and e.alive and P.alive and P.vehicle == e, "老的「下车」请求不理：车还在、人还在车里")
local fxOn = false
T.remoteAs(me, "Drive", { op = "exit", hangar = true })   -- 长按 H
T.runUntil(function() if C.deathFxOn and C.deathFxOn() then fxOn = true end return false end, 3)
check(e ~= nil and not e.alive, "车没了")
T.runUntil(function() return not P.alive end, 10)
check(not P.alive, "人回机库")
check(not fxOn, "回机库不放阵亡效果")
T.runUntil(function() return hg and hg.Visible end, 15)
check(hg and hg.Visible, "机库又出来了")

print("⑤ 研究、购买、放进阵容")
local t = G.treeOf(P)
local target
for _, it in ipairs(TT.list.cn.ground) do
  if TT.canResearch(t, it.key) then target = it break end
end
check(target ~= nil, "有能研究的：" .. tostring(target and target.name))
if target then
  T.act("treeResearch", target.key)
  R.run(0.5)
  check(t.cur["cn:ground"] == target.key, "选成了研究目标")
  G.treeAddRp(P, target.key, target.rp)
  G.treePublish(P)
  R.run(0.5)
  check(TT.researched(t, target.key), "研究点够了：研究完")
  T.act("treeBuy", target.key)
  R.run(0.5)
  check(TT.owned(t, target.key), "买下了")
  local inL = false
  for _, k in ipairs(G.treeLineup(P)) do if k == target.key then inL = true end end
  check(inL, "阵容没满：顺手放进了出击阵容")
  local ct = C.treeState and C.treeState()
  check(ct and ct.own and ct.own[target.key] == true, "客户端拿到了更新（买下的）")
end

print("⑥ 科技树界面、一局结束发研究点")
R.as("client", function() C.openTechTree() end)
R.run(0.5)
local panel = C.treeGui
local nCard = 0
for _, c in ipairs(panel and panel:GetDescendants() or {}) do if c.Name:match("^Card_") then nCard = nCard + 1 end end
check(panel and panel.Visible and nCard == #TT.list[(C.treeState().nat)].ground, "科技树开着：中国坦克 " .. nCard .. " 格")
local nxt
for _, it in ipairs(TT.list.cn.ground) do if TT.canResearch(t, it.key) then nxt = it break end end
if nxt then
  local card
  for _, c in ipairs(panel:GetDescendants()) do if c.Name == "Card_" .. nxt.key then card = c end end
  if card then T.press(card) end
  R.run(0.3)
  local rb
  for _, c in ipairs(panel:GetDescendants()) do if c.Name == "Research" then rb = c end end
  check(rb ~= nil, "点一格：详情里有「研究这一辆」（" .. nxt.name .. "）")
  if rb then T.press(rb) end
  R.run(0.5)
  check(t.cur["cn:ground"] == nxt.key, "点了以后成了研究目标")
  P.score, P.kills = 600, 3
  P.treeUsed = { ground = true }
  local rp = G.treeAward(P, true)
  check(rp > 0 and ((t.rp[nxt.key] or 0) > 0 or TT.researched(t, nxt.key)), string.format("一局结束：挣了 %d 研究点，记在 %s 上（%d / %d）", rp, nxt.name, t.rp[nxt.key] or 0, nxt.rp))
end
print("⑦ 资料卡、装甲查看器")
R.as("client", function() C.openInfo(TT.get("cn_59")) end)
R.run(0.5)
local ip = C.infoGui
local nPart, cols, penRow = 0, {}, false
for _, x in ipairs(ip and ip:GetDescendants() or {}) do
  if x:IsA("BasePart") then
    nPart = nPart + 1
    cols[string.format("%d,%d,%d", math.floor(x.Color.R * 255), math.floor(x.Color.G * 255), math.floor(x.Color.B * 255))] = true
  end
  if x:IsA("TextLabel") and x.Text:find("穿深") then penRow = true end
end
local nCol = 0
for _ in pairs(cols) do nCol = nCol + 1 end
check(ip and ip.Visible and nPart > 10 and nCol >= 3, string.format("装甲查看器：车模 %d 块、按装甲上了 %d 种颜色", nPart, nCol))
check(penRow, "参数里写着每种弹的穿深")
R.as("client", function() C.openInfo(TT.get("cn_j6")) end)
R.run(0.5)
local airRow = false
for _, x in ipairs(ip:GetDescendants()) do if x:IsA("TextLabel") and x.Text:find("km/h") then airRow = true end end
check(airRow, "飞机的资料卡写着速度")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
