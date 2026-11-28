-- 射流弹 X 光慢放动画（模拟器）：python3 tools/mock/run.py tools/mock/wtxray.lua
--   用户 11-24 夜「射流弹击中别的坦克的 x 光动画要有特殊效果」：直接给客户端发一发射流弹打穿 T-90M、弹药殉爆的命中（wtHit），一帧帧看——
--   ① 0.35 秒：弹在飞（一根发光的弹）② 1.1 秒：射流钻进去、熔珠和破片出来（发光件十几个以上），字幕「T-90M · 800 米 / 金属射流弹 · 穿深 950 …」、
--      上面正中的结果字「击穿」
--   ③ 3.2 秒：结果字换成「弹药殉爆」；窗口下面「车组 2 / 3」、一行行红 / 黄字（炮长阵亡、车长重伤、弹药架损毁、起火），打坏的模块外面一圈橙框
--   ④ 7.5 秒：X 光窗口关了；全程没报错
--   用户 11-28「跟战雷还是有区别」：照战雷的命中回放重排（右上、没有框和慢放标签、结果字在上、车组和损伤在窗口下面）
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
local info, title, crew = find("XrInfo"), find("XrTitle"), find("XrCrew")
check(find("XrSlow") == nil, "没有慢放标签了（战雷的回放没有）")
print("  1.1 秒：发光件 " .. n2 .. " 个；字幕「" .. tostring(info and info.Text) .. "」；结果字「" .. tostring(title and title.Text) .. "」")
check(n2 >= 14, "1.1 秒：射流、熔珠、破片都出来了（" .. n2 .. " 个发光件）")
check(info and info.Visible and string.find(info.Text, "950", 1, true) ~= nil, "字幕写穿深 950")
check(info and string.find(info.Text, "800", 1, true) ~= nil, "字幕第一行车名 · 距离 800 米")
check(title and title.Text == "击穿", "1.1 秒：结果字「击穿」（击毁还没到）")
local function dmgLines()
  local out = {}
  for i = 1, 6 do
    local l = find("XrDmg" .. i)
    if l and l.Visible and l.Text ~= "" then out[#out + 1] = l.Text end
  end
  return out
end
local function edges()   -- 橙框：细的发光边（0.07）
  local n = 0
  for _, p in ipairs(wm and wm:GetChildren() or {}) do
    if p:IsA("BasePart") and p.Material == R.Enum.Material.Neon and p.Transparency < 0.5 and math.abs(p.Size.X - 0.07) < 0.005 then n = n + 1 end
  end
  return n
end
local d0 = dmgLines()
check(#d0 < 4, "1.1 秒：损伤行还没全冒出来（跟着射流 / 破片到的那一刻一行行出，现在 " .. #d0 .. " 行）")
R.run(2.1)
print("  3.2 秒：结果字「" .. tostring(title and title.Text) .. "」；车组「" .. tostring(crew and crew.Text) .. "」")
check(title and string.find(title.Text, "殉爆", 1, true) ~= nil, "3.2 秒：结果字换成弹药殉爆")
local dl = dmgLines()
print("  损伤行：" .. table.concat(dl, " / "))
local all = table.concat(dl, "|")
check(string.find(all, "炮长阵亡", 1, true) ~= nil and string.find(all, "车长重伤", 1, true) ~= nil, "损伤行：炮长阵亡、车长重伤")
check(string.find(all, "弹药架损毁", 1, true) ~= nil and string.find(all, "起火", 1, true) ~= nil, "损伤行：弹药架损毁、起火")
check(crew and string.find(crew.Text, ">2<", 1, true) ~= nil and string.find(crew.Text, "/ 3", 1, true) ~= nil, "车组 2 / 3（活着的数字上色）")
local ne = edges()
check(ne >= 12, "打坏的弹药架外面一圈橙框（" .. ne .. " 根边）")
R.run(4.3)
check(not T.visible(xr), "7.5 秒：X 光窗口关了")
T.summary()
