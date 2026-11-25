-- 射流弹 X 光慢放动画（模拟器）：python3 tools/mock/run.py tools/mock/wtxray.lua
--   用户 11-24 夜「射流弹击中别的坦克的 x 光动画要有特殊效果」：直接给客户端发一发射流弹打穿 T-90M、弹药殉爆的命中（wtHit），一帧帧看——
--   ① 0.35 秒：弹在飞（一根发光的弹）② 1.1 秒：射流钻进去、熔珠和破片出来（发光件十几个以上），字幕「金属射流弹 · 穿深 950 …」、慢放标签
--   ③ 3.2 秒：字幕换成「弹药殉爆」、慢放标签收起 ④ 7.5 秒：X 光窗口关了；全程没报错
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3 = T.R, T.V3
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
local me = T.join("P1", 8701, true)
R.run(1)
local function find(name)
  for _, d in ipairs(me.PlayerGui:GetDescendants()) do if d.Name == name then return d end end
end
local xr = find("WtXray")
check(xr ~= nil, "X 光窗口在")
if not xr then T.summary() return end
local wm = xr:FindFirstChild("View") and xr.View:FindFirstChildOfClass("WorldModel")
local function lit()   -- 看得见的发光件
  local n, shell = 0, false
  for _, p in ipairs(wm and wm:GetChildren() or {}) do
    if p:IsA("BasePart") and p.Material == R.Enum.Material.Neon and p.Transparency < 0.95 then
      n = n + 1
      if math.abs(p.Size.Z - 1.2) < 0.05 and math.abs(p.Size.X - 0.24) < 0.02 then shell = true end
    end
  end
  return n, shell
end
local m = { op = "wtHit", id = 0, veh = "t90m", r = "pen", kill = true, why = "ammo", fire = true,
  parts = { { k = "gnr", kind = "crew", s = 0 }, { k = "cmd", kind = "crew", s = 1 }, { k = "ammo", kind = "mod", s = 0 } },
  pen = 950, arm = 620, dist = 800,
  xr = { p = { 0, 4.2, -5.5 }, d = { 0.1, -0.05, 1 }, ty = 0, seed = 4321, half = 16, n = 18, core = 4.4, jet = true, big = true } }
G.R.Drive:FireClient(me, m)
R.run(0.35)
check(T.visible(xr), "X 光窗口打开")
local n1, sh = lit()
check(sh, "0.35 秒：弹在飞进来（发光件 " .. n1 .. " 个）")
R.run(0.75)
local n2 = lit()
local info, slow = find("XrInfo"), find("XrSlow")
print("  1.1 秒：发光件 " .. n2 .. " 个；字幕「" .. tostring(info and info.Text) .. "」")
check(n2 >= 14, "1.1 秒：射流、熔珠、破片都出来了（" .. n2 .. " 个发光件）")
check(info and info.Visible and string.find(info.Text, "950", 1, true) ~= nil, "字幕写穿深 950")
check(slow and slow.Visible, "慢放标签")
R.run(2.1)
print("  3.2 秒：字幕「" .. tostring(info and info.Text) .. "」")
check(info and string.find(info.Text, "殉爆", 1, true) ~= nil, "3.2 秒：字幕换成弹药殉爆")
check(slow and not slow.Visible, "慢放标签收起")
R.run(4.3)
check(not T.visible(xr), "7.5 秒：X 光窗口关了")
T.summary()
