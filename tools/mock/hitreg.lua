-- 命中判定的延迟补偿（服务器 Rewind.lua + 客户端 View.lua 的 G.viewRay）：
--   跑动的小兵、玩家，按开枪的人屏幕上那一刻的位置判定；太久以前的位置、墙后面的不算；客户端准星打在画面上的小兵身上
--   python3 tools/mock/run.py tools/mock/hitreg.lua
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check

print("① 开服、两个人进来、开战")
local G = T.boot()
G.fortsHold = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local p1 = T.join("P1", 4001, true)
local p2 = T.join("P2", 4002, false)
R.run(1)
local C = T.C
if C.menuShown and C.menuShown() then
  C.menuEnter()
  R.run(0.5)
end
local P1, P2 = G.P[p1], G.P[p2]
check(P1.team ~= P2.team, "两个人分在两边（" .. tostring(P1.team) .. " / " .. tostring(P2.team) .. "）")
local function spawnOf(P) return (P.team == "atk") and "fleet" or "camp" end
T.actAsRemote(p1, "deploy", "rifle", spawnOf(P1))
T.actAsRemote(p2, "deploy", "rifle", spawnOf(P2))
R.run(1)
local okB = T.runUntil(function() return G.round.phase == "battle" end, G.Config.Round.prep + 5)
check(okB and P1.alive and P2.alive, "开战了，两个人都出生了")
check(G.rewindShot ~= nil and G.rewindTrace ~= nil, "服务器有延迟补偿（Rewind.lua）")

-- 场地：海面上空（没有地形、房子挡着），开枪的人站在 O，目标在北边 40 格处左右跑
local O = V3(2000, 60, 4000)
local Y = 60
-- 模拟器的角色只有根零件和头，中间没有关节：两个都摆（头在根零件上面 1.5 格）
local function place(ch, p)
  ch.HumanoidRootPart.CFrame = CF(p.X, p.Y, p.Z)
  ch.Head.CFrame = CF(p.X, p.Y + 1.5, p.Z)
end
local function placeShooter()
  place(p1.Character, O)
  local tool = p1.Character:FindFirstChildOfClass("Tool") or p1.Backpack:FindFirstChild("m4")
  if tool and tool.Parent ~= p1.Character then tool.Parent = p1.Character end
end
-- 部署界面的镜头停在远处：把客户端「远了收起来」的距离放大，小兵的样子照常插值
C.perfK = 100
placeShooter()
local head = function() return p1.Character.Head.Position end

-- 目标：一个不动脑子的敌方小兵实体（只按测试挪），血量给大一点好数
local e = G.newEnt({ kind = "bot", team = P2.team, cat = "inf", hp = 1000, size = V3(2.2, 5.6, 1.6), cf = CF(O.X - 30, Y, O.Z - 40), extra = { headTop = 1.4 } })
local track = {}   -- 测试自己记的目标位置：{ t, p }
local function posAgo(list, dt)
  local t = R.clock() - dt
  for i = #list, 2, -1 do
    local a, b = list[i - 1], list[i]
    if a.t <= t then
      local k = (t - a.t) / math.max(1e-4, b.t - a.t)
      return a.p + (b.p - a.p) * k
    end
  end
  return list[1].p
end
-- 让目标沿 x 方向来回跑（speed 格 / 秒），每帧挪一次；跑 dur 秒
local dirX = 1
local function runTarget(dur, speed, mover, list)
  local t = 0
  while t < dur do
    local p = mover()
    local np = p + V3(dirX * speed / 30, 0, 0)
    if np.X > O.X + 30 then dirX = -1 elseif np.X < O.X - 30 then dirX = 1 end
    mover(np)
    list[#list + 1] = { t = R.clock(), p = np }
    placeShooter()
    R.run(1 / 30, 1 / 30)
    t = t + 1 / 30
  end
end
local function entMover(np)
  if np then G.moveEnt(e, CF(np.X, np.Y, np.Z)) return end
  return e.root.CFrame.Position
end

print("② 跑动的小兵：瞄着「画面上」的位置（往回 0.25 秒）开枪")
runTarget(1.2, 14, entMover, track)
local aim = posAgo(track, 0.25)
local d0 = (aim - head()).Unit
check(G.rayBox(head(), d0, e.root.CFrame, e.root.Size, 500) == nil, "按现在的位置这一枪是打空的（原来就是这样不算）")
local hp0 = e.hp
for _ = 1, 3 do
  runTarget(0.1, 14, entMover, track)
  T.remoteAs(p1, "Shoot", "m4", posAgo(track, 0.25))
end
check(e.hp < hp0, string.format("延迟补偿以后打中了（血 %d → %d）", hp0, e.hp))

print("③ 太久以前的位置（0.9 秒前）不算")
local hp1 = e.hp
for _ = 1, 3 do
  runTarget(0.1, 14, entMover, track)
  local old = posAgo(track, 0.9)
  local cur = e.root.CFrame.Position
  if (old - cur).Magnitude > 6 then T.remoteAs(p1, "Shoot", "m4", old) end
end
check(e.hp == hp1, string.format("0.9 秒前的位置打不中（血 %d → %d）", hp1, e.hp))

print("④ 墙挡着：往回找的也打不穿")
runTarget(0.6, 14, entMover, track)
local behind = posAgo(track, 0.25)
local wall = R.Instance.new("Part")
wall.Anchored, wall.CanQuery = true, true
wall.Size = V3(12, 12, 1)
local mid = head() + (behind - head()) * 0.5
wall.CFrame = R.CFrame.lookAt(mid, behind)
wall.Parent = R.services.Workspace
local hp2 = e.hp
T.remoteAs(p1, "Shoot", "m4", behind)
check(e.hp == hp2, string.format("墙后面的打不中（血 %d → %d）", hp2, e.hp))
wall:Destroy()
R.run(0.1)

print("⑤ 跑动的真人：瞄着 0.22 秒前的位置开枪")
local ptrack = {}
local hrp = p2.Character.HumanoidRootPart
local function charMover(np)
  if np then place(p2.Character, np) return end
  return hrp.Position
end
place(p2.Character, V3(O.X - 20, Y, O.Z - 45))
G.moveEnt(e, CF(O.X + 400, Y, O.Z))   -- 小兵挪开，别挡着
runTarget(1.2, 16, charMover, ptrack)
local hum = p2.Character.Humanoid
local h0 = hum.Health
local aimC = posAgo(ptrack, 0.22)
local dC = (aimC - head()).Unit
check(G.rayBox(head(), dC, hrp.CFrame, hrp.Size, 500) == nil and G.rayBox(head(), dC, p2.Character.Head.CFrame, p2.Character.Head.Size, 500) == nil, "按现在的位置这一枪是打空的")
for _ = 1, 2 do
  runTarget(0.1, 16, charMover, ptrack)
  T.remoteAs(p1, "Shoot", "m4", posAgo(ptrack, 0.22))
end
check(hum.Health < h0, string.format("打中了跑动的玩家（血 %.0f → %.0f）", h0, hum.Health))

print("⑥ 客户端：准星打在画面上的小兵身上（不是隐形命中盒）")
place(p2.Character, V3(O.X + 300, Y, O.Z + 300))   -- 玩家挪开
G.moveEnt(e, CF(O.X - 20, Y, O.Z - 40))
track = {}
runTarget(1.5, 14, entMover, track)
local v = C.views and C.views[e.model]
check(v ~= nil and v.fl ~= nil, "客户端给这个小兵建了样子、在做快照插值")
if v then
  local lag = (v.cf.Position - e.root.CFrame.Position).Magnitude
  check(lag > 0.5, string.format("画面上的小兵比命中盒晚 %.1f 格", lag))
  local pAim
  R.as("client", function()
    local cam = R.services.Workspace.CurrentCamera
    cam.CFrame = R.CFrame.lookAt(head(), v.cf.Position)
    pAim = C.aimPoint(600)
  end)
  check(pAim ~= nil and (pAim - v.cf.Position).Magnitude < 2, string.format("准星的点在画面上的小兵身上（离画面上的中心 %.1f 格）", pAim and (pAim - v.cf.Position).Magnitude or -1))
  local hp3 = e.hp
  T.remoteAs(p1, "Shoot", "m4", pAim)
  check(e.hp < hp3, string.format("照客户端的准星点开枪：服务器算打中（血 %d → %d）", hp3, e.hp))
end

T.summary()
