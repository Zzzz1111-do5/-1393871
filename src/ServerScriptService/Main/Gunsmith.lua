-- Roblox全面大战场——改枪（服务器，用户 11-20：做一整套改枪系统，对标三角洲行动；数据和算法在 ReplicatedStorage.GunMods）
--   每个人每把枪装的配件、存的三个方案、枪械经验：存档在 P.data.guns[枪] = { b = 现在装的, s = { 方案1, 方案2, 方案3 } }、P.data.gxp[枪]
--   客户端的改枪界面（Client/Gunsmith.lua）发 gunBuild（装上这一套）/ gunSave（存成方案几）：服务器核对（这把枪装得了、等级够），
--     存起来，写在玩家属性上给客户端读：Gun_<枪> 现在装的（GM.encode）、GunSaves_<枪> 三个方案（| 隔开）、GunXp_<枪> 经验、GunAll 配件全开
--   出击时（Round.lua onCharacter → G.gunApply）按装的算一份武器表（GunMods.apply：弹匣、换弹、后坐、散布、射程、消音……），
--     开枪、换弹都按它（G.wOf）；工具带上 Build 属性（Weapons.lua giveLoadout），大家的客户端照它装配件。改了配件下次出击生效
--   用这把枪打死人加枪械经验（Config.GunMods.killXp / botXp），升级时提示解锁了什么
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Gunsmith = {}

function Gunsmith.init(G)
  local Config = G.Config
  local W = Config.Weapons
  local GM = require(RS:WaitForChild("GunMods"))
  local C = Config.GunMods or {}
  local studio = false
  pcall(function() studio = RunService:IsStudio() end)
  local ALL = C.unlockAll == true or (C.studioAll ~= false and studio)
  G.gunAll = ALL
  local now = os.clock

  -- 存档里的改枪数据整理成合法的（Store.lua 读档时调）：认不得的枪、太长的字串都不要
  function G.gunsFromSave(d)
    local guns, gxp = {}, {}
    if type(d) ~= "table" then return guns, gxp end
    if type(d.guns) == "table" then
      for id, g in pairs(d.guns) do
        if GM.DEF[id] and type(g) == "table" then
          local e = { b = (type(g.b) == "string" and #g.b < 300) and g.b or nil, s = {} }
          if type(g.s) == "table" then
            for i = 1, 3 do
              local v = g.s[i]
              e.s[i] = (type(v) == "string" and #v < 300) and v or ""
            end
          end
          guns[id] = e
        end
      end
    end
    if type(d.gxp) == "table" then
      for id, v in pairs(d.gxp) do
        if GM.DEF[id] then gxp[id] = math.max(0, math.floor(tonumber(v) or 0)) end
      end
    end
    return guns, gxp
  end

  -- 读档之前（刚进服就改了枪）先记在 P.gunsEarly，读完档并进去
  local function gunsOf(P)
    local d = P.data
    if not d then
      P.gunsEarly = P.gunsEarly or { guns = {}, gxp = {} }
      return P.gunsEarly.guns, P.gunsEarly.gxp
    end
    d.guns = d.guns or {}
    d.gxp = d.gxp or {}
    return d.guns, d.gxp
  end
  function G.gunsMergeEarly(P)
    local E = P.gunsEarly
    P.gunsEarly = nil
    if not E or not P.data then return end
    local guns, gxp = gunsOf(P)
    for id, g in pairs(E.guns) do guns[id] = g end
    for id, v in pairs(E.gxp) do gxp[id] = (gxp[id] or 0) + v end
  end

  function G.gunLevel(P, id)
    local _, gxp = gunsOf(P)
    return (GM.level(id, gxp[id] or 0))
  end

  -- 这把枪现在装的（整理过的：没解锁的换成默认）
  function G.gunBuild(P, id)
    if not GM.DEF[id] then return nil end
    local guns = gunsOf(P)
    local g = guns[id]
    return GM.clean(id, (g and g.b) and GM.decode(g.b) or GM.default(id), G.gunLevel(P, id), ALL)
  end

  -- 写在玩家属性上（客户端的改枪界面、部署界面读）
  local function publish(P, id)
    local guns, gxp = gunsOf(P)
    local g = guns[id] or { s = {} }
    pcall(function()
      P.pl:SetAttribute("Gun_" .. id, GM.encode(G.gunBuild(P, id)))
      P.pl:SetAttribute("GunSaves_" .. id, table.concat({ g.s and g.s[1] or "", g.s and g.s[2] or "", g.s and g.s[3] or "" }, "|"))
      P.pl:SetAttribute("GunXp_" .. id, gxp[id] or 0)
    end)
  end
  function G.gunPublish(P)
    for id in pairs(GM.DEF) do publish(P, id) end
    pcall(function() P.pl:SetAttribute("GunAll", ALL) end)
  end

  -- 改了配件、加了经验：过一会儿存一次档（DataStore 一个键几秒才能写一次；一局结束、退出时本来也存）
  local function dirty(P)
    if P.gunSaveAt then return end
    P.gunSaveAt = now() + 25
    task.delay(25, function()
      P.gunSaveAt = nil
      if G.P[P.pl] == P and G.saveData then G.try("改枪存档", G.saveData, P) end
    end)
  end

  -- 出击：按装的算这一条命的武器表（开枪、换弹按它，工具上写 Build 属性）
  function G.gunApply(P)
    P.wEff, P.wBuild = {}, {}
    for id in pairs(GM.DEF) do
      local b = G.gunBuild(P, id)
      P.wBuild[id] = b
      P.wEff[id] = GM.apply(id, W[id], b)
    end
  end
  function G.wOf(P, id)
    local e = P and P.wEff and P.wEff[id]
    return e or W[id]
  end
  -- 走路速度倍数（配件的重量：弹鼓、长消音器、6 倍镜慢一点）：部署时按主武器算
  function G.gunMob(P, id)
    if not id or not GM.DEF[id] then return 1 end
    local w = GM.apply(id, W[id], G.gunBuild(P, id))
    return (w and w.mobK) or 1
  end

  local function cleanReq(id, b)
    if type(b) ~= "table" then return nil end
    local out = {}
    for _, slot in ipairs(GM.SLOTS) do
      local v = b[slot]
      if type(v) == "string" and #v < 40 then out[slot] = v end
    end
    return out
  end

  -- 客户端：这把枪装上这一套（改枪界面点「完成」、套用推荐 / 方案 / 改枪码）
  G.ACT.gunBuild = function(P, id, b)
    if type(id) ~= "string" or not GM.DEF[id] then return end
    local t = now()
    if t - (P.gunT or 0) < 0.15 then return end
    P.gunT = t
    local req = cleanReq(id, b)
    if not req then return end
    local lv = G.gunLevel(P, id)
    local got = GM.clean(id, req, lv, ALL)
    local locked = 0
    for _, slot in ipairs(GM.SLOTS) do
      if req[slot] and got[slot] and req[slot] ~= got[slot] then locked += 1 end
    end
    local guns = gunsOf(P)
    guns[id] = guns[id] or { s = { "", "", "" } }
    guns[id].b = GM.encode(got)
    publish(P, id)
    if locked > 0 then G.msg(P.pl, "bad", "gm.someLocked", locked) end
    if P.data then dirty(P) end
  end

  -- 客户端：存成方案 i（1～3）；b 是空的就清掉这个方案
  G.ACT.gunSave = function(P, id, i, b)
    if type(id) ~= "string" or not GM.DEF[id] or type(i) ~= "number" or i < 1 or i > 3 or i ~= math.floor(i) then return end
    local t = now()
    if t - (P.gunT or 0) < 0.15 then return end
    P.gunT = t
    local guns = gunsOf(P)
    guns[id] = guns[id] or { s = { "", "", "" } }
    guns[id].s = guns[id].s or { "", "", "" }
    local req = cleanReq(id, b)
    guns[id].s[i] = req and GM.encode(GM.clean(id, req)) or ""
    publish(P, id)
    if P.data then dirty(P) end
  end

  -- 用这把枪打死一个（Round.lua 打死真人、Bots.lua 打死机器人）：加经验，升级了提示解锁了什么
  function G.gunXp(P, id, n)
    if not P or not P.pl or not id or not GM.DEF[id] or not n or n <= 0 then return end
    local _, gxp = gunsOf(P)
    local old = GM.level(id, gxp[id] or 0)
    gxp[id] = (gxp[id] or 0) + math.floor(n)
    local lv = GM.level(id, gxp[id])
    pcall(function() P.pl:SetAttribute("GunXp_" .. id, gxp[id]) end)
    if lv > old then
      G.msg(P.pl, "good", "gm.lvUp", { k = "weapon." .. id }, lv)
      local un = GM.unlocksBetween(id, old, lv)
      if #un > 0 and not ALL then
        local names = {}
        for k = 1, math.min(3, #un) do names[k] = { k = "gm.item." .. un[k] } end
        -- 最多写三样（参数是表的会按各人的语言翻译）
        if #names == 1 then G.msg(P.pl, "good", "gm.unlocked", names[1])
        else
          local key = (#names == 2) and "gm.unlocked2" or "gm.unlocked3"
          G.msg(P.pl, "good", key, names[1], names[2], names[3])
        end
      end
      publish(P, id)
    end
    if P.data then dirty(P) end
  end
end

return Gunsmith
