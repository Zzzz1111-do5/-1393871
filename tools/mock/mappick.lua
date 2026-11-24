-- 选地图界面测试（用户 11-23：「选第一的界面有bug」——三张图按两张排，第三张「沙海」整个排到屏幕外；接着「三张地图改成投票制，进去投票选地图」）：
--   主菜单「开始游戏」→ 选地图：Map.ids 有几张就有几张卡，都在内容框里、互不重叠；每张卡的字都在卡里；缩略图；开着时主菜单的字藏起来、关了放回来；
--   投票：点一张是投一票（能改票），每张卡显示票数、底下倒计时；在场的人都投了再等几秒按票数最多的开（不是自己投的那张也一样）；地图好了投过票的自动快速加入
--   用户 11-24 只留沙海：不用投票，开服就建；点「开始游戏」显示生成进度，好了自动加入
--   python3 tools/mock/run.py tools/mock/mappick.lua
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
T.runUntil(function() return G.worldReady end, 900)   -- 开服就在建沙海：建好之前是生成进度，好了才是主菜单
R.run(1)
check(G.mapId == "sands", "只剩沙海（用户 11-24）：开服就定了沙海、开始建，不用等投票（" .. tostring(G.mapId) .. "）")
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

print("⑤ 只剩沙海：点沙海那张卡就加入")
T.press(cards.sands)
R.run(0.5)
T.runUntil(function() return G.P[p1] and G.P[p1].alive end, 30)
check(not C.mapPickShown(), "选地图界面关了")
check(G.P[p1] and G.P[p1].alive, "P1 自动快速加入、出生了")
T.summary()
