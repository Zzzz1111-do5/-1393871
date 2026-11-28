-- Roblox全面大战场——金币充值（R 币买金币：开发者产品 Developer Product + ProcessReceipt）。用户 11-28「你做个金币充值界面好了收robux」
--   Config.CoinPacks：一档一个开发者产品（id 是创作者后台建好的产品编号；还是 0 = 没上架，买不了）
--   客户端（CoinShop.lua）发 buyCoins(档) → 这里弹 Roblox 的购买框（PromptProductPurchase）→ 玩家付了钱，Roblox 调 ProcessReceipt：
--     ① 认得这个产品、人在这台服务器、存档读好了——不然 NotProcessedYet（Roblox 过一会儿、他下次进服再调，钱不会白付）
--     ② 这一单（PurchaseId）发过货了：直接 PurchaseGranted（Roblox 可能重复调同一单——不能发两次）
--     ③ 加金币、把这一单记进存档（data.rcpt，留最近 100 单），马上写存档（G.saveNow），写进去了才回 PurchaseGranted；
--        没写进去：刚加的金币、记的单都退回去，回 NotProcessedYet（Roblox 会再调：不会白付钱，也不会多发）
--   Studio 里存不了档（没开 API 服务）：测试购买不花钱——只加在内存里、照样回 PurchaseGranted
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local okM, MPS = pcall(function() return game:GetService("MarketplaceService") end)   -- 拿不到（测试环境）就只留 G.shopReceipt 给测试调
if not okM then MPS = nil end

local Shop = {}

function Shop.init(G)
  -- 每次现查 Config（五档，便宜）：服务器跑着时改了编号也算数
  local function packBy(f, v)
    for _, p in ipairs(G.Config.CoinPacks or {}) do
      if p[f] == v and (f ~= "id" or (p.id or 0) ~= 0) then return p end
    end
  end
  local DEC = { ok = "PurchaseGranted", later = "NotProcessedYet" }
  pcall(function()
    DEC.ok = Enum.ProductPurchaseDecision.PurchaseGranted
    DEC.later = Enum.ProductPurchaseDecision.NotProcessedYet
  end)
  local studio = false
  pcall(function() studio = RunService:IsStudio() end)
  local KEEP = 100
  local busy = {}   -- 正在发货的单（同一单 Roblox 又调进来：先回 NotProcessedYet）

  local function trim(rc)
    local ids = {}
    for k, t in pairs(rc) do ids[#ids + 1] = { k, tonumber(t) or 0 } end
    if #ids <= KEEP then return end
    table.sort(ids, function(a, b) return a[2] < b[2] end)
    for i = 1, #ids - KEEP do rc[ids[i][1]] = nil end
  end

  local function process(info)
    local pack = type(info) == "table" and packBy("id", info.ProductId) or nil
    if not pack then return DEC.later end   -- 不认得的产品（配错了）：先不认账，改好 Config 以后 Roblox 会再调
    local pl = Players:GetPlayerByUserId(info.PlayerId)
    local P = pl and G.P[pl]
    if not (P and P.data) then return DEC.later end
    local id = tostring(info.PurchaseId or "")
    if id == "" then return DEC.later end
    local d = P.data
    d.rcpt = (type(d.rcpt) == "table") and d.rcpt or {}
    if d.rcpt[id] then return DEC.ok end   -- 这一单发过了
    if busy[id] then return DEC.later end
    busy[id] = true
    local n = math.max(0, math.floor(tonumber(pack.coins) or 0))
    d.coins = (tonumber(d.coins) or 0) + n
    d.rcpt[id] = os.time()
    trim(d.rcpt)
    local saved
    if P.canSave and G.saveNow then
      saved = G.saveNow(P)
    else
      saved = studio   -- Studio 里存不了档：测试购买不花钱，记在内存里就算
      if saved then warn("[充值] Studio 里存不了档：这次充的 " .. n .. " 金币只在内存里") end
    end
    busy[id] = nil
    if not saved then
      d.coins = math.max(0, d.coins - n)
      d.rcpt[id] = nil
      G.msg(pl, "bad", "shop.saveFail")
      return DEC.later
    end
    if G.econPublish then G.econPublish(P) end   -- 客户端的金币数（玩家属性 Coins）
    G.msg(pl, "good", "shop.thanks", n)
    if G.emit then pcall(G.emit, "coinsBought", P, n) end
    return DEC.ok
  end
  G.shopReceipt = process   -- 测试用
  G.shopDecision = DEC      -- 测试用
  if MPS then pcall(function() MPS.ProcessReceipt = process end) end

  -- 客户端点了某一档：弹 Roblox 的购买框
  G.ACT.buyCoins = function(P, key)
    local p = (type(key) == "string") and packBy("key", key) or nil
    if not p then return end
    if (p.id or 0) == 0 then G.msg(P.pl, "bad", "shop.notListed") return end
    G.shopPrompted = (G.shopPrompted or 0) + 1   -- 测试用
    if not MPS then return end
    pcall(function() MPS:PromptProductPurchase(P.pl, p.id) end)
  end
end

return Shop
