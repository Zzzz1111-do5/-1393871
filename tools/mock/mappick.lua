-- 选地图界面测试（用户 11-23：「选第一的界面有bug」——三张图按两张排，第三张「沙海」整个排到屏幕外；接着「三张地图改成投票制，进去投票选地图」）：
--   主菜单「开始游戏」→ 选地图：Map.ids 有几张就有几张卡，都在内容框里、互不重叠；每张卡的字都在卡里；缩略图；开着时主菜单的字藏起来、关了放回来；
--   投票：点一张是投一票（能改票），每张卡显示票数、底下倒计时；在场的人都投了再等几秒按票数最多的开（不是自己投的那张也一样）；地图好了投过票的自动快速加入
--   python3 tools/mock/run.py tools/mock/mappick.lua          三个人投票（P1 改票），沙海两票胜出，生成好了 P1 自动加入
--   python3 tools/mock/run.py tools/mock/mappick.lua timer    两个人只有 P1 投：到点（Config.MapVote.time）才开
--   python3 tools/mock/run.py tools/mock/mappick.lua bands    EditableImage 用不了（Studio 没开 Mesh / Image API）：缩略图是一行一条渐变拼的色带
local T = dofile(MOCK_DIR .. "/common.lua")
local R, Enum = T.R, T.Enum
local check = T.check
local BANDS = TEST_ARGS:match("bands") ~= nil
local TIMER = TEST_ARGS:match("timer") ~= nil
if BANDS then R.noEditable = true end

print("① 开服、进人、主菜单「开始游戏」")
local G = T.boot()
G.fortsHold = true
local p1 = T.join("P1", 5201, true)
local p2 = T.join("P2", 5202, false)
local p3 = (not TIMER) and T.join("P3", 5203, false) or nil
local C = T.C
R.run(4)
check(G.mapId == nil, "有人在：等大家投票（过了空服的 3 秒也不自己按岛开）")
check(C.menuShown and C.menuShown(), "主菜单开着")
local pg = p1.PlayerGui
local menu = pg:FindFirstChild("Menu")
local function menuContent()
  -- 主菜单的内容框：1280 × 720 那一块（bg 下面）
  for _, d in ipairs(menu:GetDescendants()) do
    if d.ClassName == "Frame" and d.Size.X.Offset == 1280 and d.Size.Y.Offset == 720 then return d end
  end
end
local mc = menuContent()
check(mc ~= nil and mc.Visible ~= false, "主菜单的字看得见")
R.as("client", function() C.menuPlay() end)
R.run(0.5)
check(C.mapPickShown(), "点「开始游戏」打开选地图")
check(mc ~= nil and mc.Visible == false, "选地图开着：主菜单的字藏起来（不从卡片后面透出来）")

print("② 卡片：几张图几张卡，都在内容框里、不重叠")
local Map = C.Map
local mp = pg:FindFirstChild("MapPick")
local cards = {}
for _, d in ipairs(mp:GetDescendants()) do
  local id = d.Name:match("^Map_(%w+)$")
  if id then cards[id] = d end
end
local n = 0
for _ in pairs(cards) do n = n + 1 end
check(n == #Map.ids, string.format("卡片 %d 张（Map.ids %d 张）", n, #Map.ids))
local W = 1232
local boxes = {}
for i, id in ipairs(Map.ids) do
  local b = cards[id]
  if b then
    local x0, w = b.Position.X.Offset, b.Size.X.Offset
    check(x0 >= 0 and x0 + w <= W, string.format("「%s」在内容框里（%d～%d，框宽 %d）", id, x0, x0 + w, W))
    boxes[i] = { x0, x0 + w }
    -- 卡里的字、按钮都在卡里
    local bad = {}
    for _, d in ipairs(b:GetChildren()) do
      if d.ClassName == "TextLabel" and d.Size.X.Scale == 0 then
        local lx = d.Position.X.Offset + d.Position.X.Scale * w - d.AnchorPoint.X * d.Size.X.Offset
        if lx < 0 or lx + d.Size.X.Offset > w + 0.5 then table.insert(bad, d.Text) end
      end
    end
    check(#bad == 0, "「" .. id .. "」的字都在卡里：" .. table.concat(bad, " | "))
  end
end
local overlap = false
for i = 2, #boxes do if boxes[i] and boxes[i - 1] and boxes[i][1] < boxes[i - 1][2] then overlap = true end end
check(not overlap, "卡片不重叠")
check(cards.sands and T.visible(cards.sands), "沙海那张看得见")

print(BANDS and "③ 缩略图：没有 EditableImage 就画色带" or "③ 缩略图：EditableImage 画一张图")
R.run(3)
for _, id in ipairs(Map.ids) do
  local b = cards[id]
  local pv = b and b:FindFirstChild("Preview")
  local bands = pv and pv:FindFirstChild("Bands")
  if BANDS then
    check(bands ~= nil and #bands:GetChildren() >= 20, string.format("「%s」画了色带（%d 条）", id, bands and #bands:GetChildren() or 0))
  else
    check(pv ~= nil and pv.ImageContent ~= nil and bands == nil, "「" .. id .. "」的缩略图是一张图（没画色带）")
  end
end
-- 沙海的缩略图不该有草绿（原来石灰岩台地、板岩都落到草绿上）：色带的色点看得到颜色
if BANDS then
  local pv = cards.sands and cards.sands:FindFirstChild("Preview")
  local bands = pv and pv:FindFirstChild("Bands")
  local green, total = 0, 0
  for _, f in ipairs(bands and bands:GetChildren() or {}) do
    local g = f:FindFirstChildOfClass("UIGradient")
    for _, k in ipairs(g and g.Color.Keypoints or {}) do
      local c = k.Value
      total = total + 1
      if c.G > c.R * 1.15 and c.G > c.B * 1.15 then green = green + 1 end
    end
  end
  check(total > 0 and green == 0, string.format("沙海的缩略图没有草绿（%d / %d 个点）", green, total))
end

print("④ Esc 关掉：主菜单的字放回来")
R.as("client", function() T.key(Enum.KeyCode.Escape, true) T.key(Enum.KeyCode.Escape, false) end)
R.run(0.3)
check(not C.mapPickShown(), "Esc 关掉选地图")
check(mc ~= nil and mc.Visible ~= false, "主菜单的字放回来了")
R.as("client", function() C.menuPlay() end)
R.run(0.3)

print("⑤ 投票")
-- 卡上的票数牌（「N 票」那块）、按钮、底下那行
local votePat = "^" .. C.T("map.votes", 0):gsub("0", "(%%d+)") .. "$"
local function votesOf(id)
  for _, d in ipairs(cards[id]:GetChildren()) do
    if d.ClassName == "TextLabel" and d.Visible then
      local k = d.Text:match(votePat)
      if k then return tonumber(k) end
    end
  end
  return nil
end
local function hasLabel(id, txt)
  for _, d in ipairs(cards[id]:GetChildren()) do
    if d.ClassName == "TextLabel" and d.Visible and d.Text == txt then return true end
  end
  return false
end
local function statusText()
  for _, d in ipairs(mp:GetDescendants()) do
    if d.ClassName == "TextLabel" and d.Size.X.Offset == 1232 and d.Position.Y.Offset == 680 then return d.Text end
  end
  return ""
end
local MV = G.Config.MapVote
check(votesOf("island") == 0 and votesOf("sands") == 0, "还没人投：每张卡写「" .. C.T("map.votes", 0) .. "」")
check(statusText() == C.T("map.voteIdle", MV.time), "底下写「" .. statusText() .. "」")
if TIMER then
  T.press(cards.island)
  R.run(0.5)
  check(G.mapVotes[p1] == "island" and votesOf("island") == 1, "P1 投了岛：那张卡 " .. tostring(votesOf("island")) .. " 票")
  check(statusText():find("1 / 2", 1, true) ~= nil, "底下倒计时、1 / 2 人已投：「" .. statusText() .. "」")
  R.run(MV.time - 5)
  check(G.mapId == nil, string.format("P2 没投：%d 秒后还没定", MV.time - 4))
  R.run(6)
  check(G.mapId == "island", "到点按票数最多的开（" .. tostring(G.mapId) .. "）")
  T.summary()
  return
end
T.press(cards.sands)
R.run(0.5)
check(G.mapId == nil and G.mapVotes[p1] == "sands", "P1 点沙海：投了一票，还没定")
check(votesOf("sands") == 1, "沙海那张 " .. tostring(votesOf("sands")) .. " 票")
check(hasLabel("sands", C.T("map.voted")), "自己投的那张按钮写「" .. C.T("map.voted") .. "」")
check(statusText():find("1 / 3", 1, true) ~= nil, "底下倒计时、1 / 3 人已投：「" .. statusText() .. "」")
T.actAsRemote(p2, "pickMap", "sands")
T.actAsRemote(p3, "pickMap", "sands")
R.run(0.5)
check(votesOf("sands") == 3, "P2、P3 也投沙海：沙海那张 " .. tostring(votesOf("sands")) .. " 票")
-- P1 改票：沙海 → 岛（沙漠风暴 11-24 删了，只剩两张）
T.press(cards.island)
R.run(0.3)
check(G.mapVotes[p1] == "island" and votesOf("island") == 1 and votesOf("sands") == 2, "P1 改投岛：岛 1 票、沙海 2 票")
check(hasLabel("island", C.T("map.voted")) and not hasLabel("sands", C.T("map.voted")), "「已投」跟着挪到岛那张")
check(G.mapId == nil, "大家都投了：还等几秒（能改票）")
R.run(MV.grace + 0.5)
check(G.mapId == "sands", "在场的人都投了，几秒后按票数最多的开：沙海 2 票（" .. tostring(G.mapId) .. "）")
R.run(0.5)
check(statusText():find(C.T("map.decided", C.T("map.sands.name")), 1, true) ~= nil, "P1 投的不是沙海：底下写「" .. statusText() .. "」")
T.actAsRemote(p2, "pickMap", "island")
R.run(0.3)
check(G.mapId == "sands", "定了以后再投不改地图")

print("⑥ 地图生成好：投过票的自动快速加入（不管最后是不是自己投的那张）")
T.runUntil(function() return G.worldReady end, 900)
check(G.worldReady, "沙海建好了")
T.runUntil(function() return G.P[p1] and G.P[p1].alive end, 30)
check(not C.mapPickShown(), "选地图界面关了")
check(G.P[p1] and G.P[p1].alive, "P1 自动快速加入、出生了")
T.summary()
