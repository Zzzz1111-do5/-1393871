-- Roblox全面大战场——爆炸反应装甲（用户 11-19：给坦克实现爆反；这些坦克都自带爆反，99A 炮塔正面原模型没有、补贴一片）
--   每型的块在 EraMeta.lua（tools/models/eralayout.py 在原模型表面量的：车体首上、炮塔正面 / 侧面、侧裙板），出车时 G.eraSetup 记下来
--   用户 11-22 晚：「坦克要能自己选位置贴爆反」——贴了哪几格按改装（TankMods.cellsOn：改装界面里一格格点的 + 原车自带的），爆反型号也按改装选的
--   挨打（Ents.lua 问这里）：
--     破甲类（火箭弹、导弹：boomKind 是 rkt / msl）——从炸点顺着来向往车里找第一块还在的块（命中盒是个大方块，真的块在里面一两格），
--       找到就炸掉它，这一下对这辆车的伤害（直接命中 + 爆炸）只剩 TankMods.ERA[型号].k 成（火箭弹，单装药）/ kt 成（导弹，串联装药：前级先把爆反引爆）；
--     坦克炮弹（动能弹）——只有重型爆反（FY-4）会起爆、削掉一些（ke 成）；小口径、榴弹不管
--   炸掉的块号写进模型属性 EraX（"3,7,12"），客户端（VehModels / View）把那块藏起来、换成焦黑的空位；特效 { k = "era" }（ArmorFx.lua）
--   块自己爆开也会伤到贴着车的步兵（不多）
local RS = game:GetService("ReplicatedStorage")

local Era = {}

function Era.init(G)
  local TM = require(RS:WaitForChild("TankMods"))
  local BAL = require(RS:WaitForChild("Ballistics"))   -- 坦克炮的弹种（破甲弹按聚能装药挡）
  local V, CF = Vector3.new, CFrame.new
  local function baseOf(e) return e.root.CFrame * CF(0, -e.def.H / 2, 0) end   -- 同 Armor.lua 的 baseOf：车底中心

  function G.eraSetup(e)
    local L = e.def and TM.eraOf(e.def.id)
    if not L or not L.b or #L.b == 0 then return end
    -- 只有贴了的格起作用（改装界面一格格选的 e.def.mods.ep + 原车自带的；没选按出厂）
    local m = e.def.mods
    local on = TM.cellsOn(e.def.id, m)
    local off, n = {}, 0
    for i in ipairs(L.b) do
      if on[i] then n += 1 else off[i] = true end
    end
    if n == 0 then return end
    local kind = TM.ERA[m and m.era or ""] or TM.ERA[L.kind] or TM.ERA.fy2
    e.era = { L = L, dead = {}, off = off, n = n, left = n, kind = kind, list = {} }
    e.model:SetAttribute("Era", n)
    e.model:SetAttribute("EraX", "")
  end

  -- 射线 o + t·d（t 在 0~maxT）打第一块还在的块：返回块号、t、块的 CFrame（Z 朝外）
  local function rayBlock(e, o, d, maxT)
    local E = e.era
    local base = baseOf(e)
    local best, bt, bcf = nil, maxT, nil
    for i, b in ipairs(E.L.b) do
      if not E.dead[i] and not (E.off and E.off[i]) then
        local cf, w, h, t = TM.blockCF(E.L, b, base, e.ty or 0, TM.own(E.L, b) and 1 or E.kind.th)
        -- 射线进块的局部坐标，和放大一点（0.35 格）的盒子求交（slab 法）
        local lo = cf:PointToObjectSpace(o)
        local ld = cf:VectorToObjectSpace(d)
        local half = V(w / 2 + 0.35, h / 2 + 0.35, t / 2 + 0.6)
        local t0, t1 = 0, bt
        local ok = true
        for _, ax in ipairs({ "X", "Y", "Z" }) do
          local p, q, hh = lo[ax], ld[ax], half[ax]
          if math.abs(q) < 1e-6 then
            if math.abs(p) > hh then ok = false break end
          else
            local a, c = (-hh - p) / q, (hh - p) / q
            if a > c then a, c = c, a end
            t0, t1 = math.max(t0, a), math.min(t1, c)
            if t0 > t1 then ok = false break end
          end
        end
        -- 要从外面打进来（来向和块朝外的面相对），背面打穿过去的不算
        if ok and t0 < bt and d:Dot(cf.ZVector) < 0.25 then best, bt, bcf = i, t0, cf end
      end
    end
    return best, bt, bcf
  end

  local function detonate(e, i, cf)
    local E = e.era
    if E.dead[i] then return end
    E.dead[i] = true
    E.left -= 1
    table.insert(E.list, i)
    e.model:SetAttribute("EraX", table.concat(E.list, ","))
    local p = cf.Position
    G.fx({ k = "era", id = e.id, i = i, p = p, n = cf.ZVector })
    -- 块的爆片：贴着车的步兵挨一点（自己人也挨——爆反就是这样）
    for _, P in pairs(G.P) do
      local hrp = P.char and P.char:FindFirstChild("HumanoidRootPart")
      if hrp and P.alive and not G.inVeh(P) then
        local dd = (hrp.Position - p).Magnitude
        if dd < 7 then G.hurtChar(P.char, 28 * (1 - dd / 7), e.lastHitBy) end
      end
    end
    G.eraHits = (G.eraHits or 0) + 1   -- 测试用
  end
  G.eraDetonate = detonate

  -- 坦克炮弹直接打在车上：只有重型爆反起作用（返回伤害倍数，没起作用 nil）
  function G.eraShell(e, s, pos)
    local E = e and e.era
    if not E or not e.alive or E.left <= 0 or not s.w or s.w.fx ~= "tank" then return nil end
    -- 坦克炮的破甲弹、多用途弹（Ballistics 的 ce：聚能装药）：爆反照挡破甲弹那样挡（k）；穿甲弹只有重型爆反削得动（ke）
    local am = s.w.ammo and BAL.AMMO[s.w.ammo]
    local mult = (am and am.ce) and (E.kind.k or 1) or (E.kind.ke or 1)
    if mult >= 1 then return nil end
    local d = s.vel.Magnitude > 1e-3 and s.vel.Unit or (e.root.CFrame.Position - pos).Unit
    local i, _, cf = rayBlock(e, pos - d * 1.5, d, 14)
    if not i then return nil end
    detonate(e, i, cf)
    return mult
  end

  -- 破甲类的爆炸（火箭弹、导弹）：炸点附近带爆反的车，顺着来向（没有就朝车中心）找块；返回 { [车] = 伤害倍数 }，没有 nil
  function G.eraBlast(pos, w, dir)
    local bk = G.boomKind and G.boomKind(w)
    if bk ~= "rkt" and bk ~= "msl" then return nil end
    local out = nil
    for _, e in ipairs(G.vehicles or {}) do
      local E = e.era
      if E and e.alive and E.left > 0 then
        local c = e.root.CFrame.Position
        local reach = math.max(e.def.L, e.def.W) * 0.5 + 6
        if (c - pos).Magnitude < reach then
          local d = (dir and dir.Magnitude > 1e-3) and dir.Unit or (c - pos).Unit
          local i, _, cf = rayBlock(e, pos - d * 2, d, 16)
          if i then
            detonate(e, i, cf)
            out = out or {}
            out[e] = (bk == "msl") and (E.kind.kt or E.kind.k) or E.kind.k   -- 导弹多是串联装药：前级先引爆爆反，主装药照样往里钻
          end
        end
      end
    end
    return out
  end
end

return Era
