-- Roblox全面大战场——R 币解锁（游戏通行证 Game Pass）。用户：B-2 199 R 币、战术平板（副武器）99 R 币（歼-36 后来不做了）
--   通行证在 Config.Passes：id 是创作者后台建好的通行证编号；还是 0 的时候谁都能用（没上架前不挡人）
--   G.ownsPass(P, 名字)：这个人能不能用（进服时先查一遍、记下来；买了马上算数）
--   玩家属性 Pass_<名字> = true / false：客户端（部署界面、召唤点的机型列表）看它画锁、价钱
--   客户端发 buyPass(名字)：弹出 Roblox 的购买框（PromptGamePassPurchase）
local Players = game:GetService("Players")
local okM, MPS = pcall(function() return game:GetService("MarketplaceService") end)   -- 拿不到（测试环境）就当通行证都没配
if not okM then MPS = nil end
local RunService = game:GetService("RunService")

local Passes = {}

function Passes.init(G)
  local CFG = G.Config.Passes or {}
  local own = {}   -- [UserId][名字] = true / false（查过的）

  local function plOf(P) return (typeof(P) == "Instance") and P or (P and P.pl) end
  local function setAttr(pl, name, v) pcall(function() pl:SetAttribute("Pass_" .. name, v == true) end) end

  -- 查一个人有没有这个通行证（会等网络：进服时在单独的线程里先查好，之后都读缓存）
  local function query(pl, name)
    local c = CFG[name]
    if not c or (c.id or 0) == 0 then return true end
    local uid = pl.UserId
    own[uid] = own[uid] or {}
    if own[uid][name] ~= nil then return own[uid][name] end
    if uid <= 0 then   -- Studio 里「测试 → 玩家」的假号查不了：Studio 里放行
      own[uid][name] = RunService:IsStudio()
      return own[uid][name]
    end
    if not MPS then return true end
    local ok, r = pcall(function() return MPS:UserOwnsGamePassAsync(uid, c.id) end)
    if ok then own[uid][name] = r == true end   -- 查失败不记：下回再查
    return ok and r == true
  end

  function G.ownsPass(P, name)
    local pl = plOf(P)
    if not pl then return false end
    return query(pl, name)
  end
  -- 物品 / 机型要不要通行证、这个人能不能用（不要的直接 true）
  function G.passOkFor(P, item)
    local name = G.Config.PassFor and G.Config.PassFor[item]
    if not name then return true end
    return G.ownsPass(P, name)
  end

  local function refresh(pl)
    for name in pairs(CFG) do setAttr(pl, name, query(pl, name)) end
  end
  Players.PlayerAdded:Connect(function(pl) task.spawn(refresh, pl) end)
  for _, pl in ipairs(Players:GetPlayers()) do task.spawn(refresh, pl) end
  Players.PlayerRemoving:Connect(function(pl) own[pl.UserId] = nil end)

  -- 客户端：点了锁着的东西 → 弹出购买框
  G.ACT.buyPass = function(P, name)
    local c = type(name) == "string" and CFG[name] or nil
    if not c or (c.id or 0) == 0 or not MPS then return end
    pcall(function() MPS:PromptGamePassPurchase(P.pl, c.id) end)
  end
  -- 买成了：马上算数（UserOwnsGamePassAsync 有缓存，刚买完不一定查得到）
  if MPS then pcall(function()
    MPS.PromptGamePassPurchaseFinished:Connect(function(pl, passId, bought)
      if not bought then return end
      for name, c in pairs(CFG) do
        if c.id == passId then
          own[pl.UserId] = own[pl.UserId] or {}
          own[pl.UserId][name] = true
          setAttr(pl, name, true)
          G.msg(pl, "good", "pass.thanks", { k = "pass." .. name })
        end
      end
    end)
  end) end
end

return Passes
