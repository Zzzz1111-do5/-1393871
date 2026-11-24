-- Roblox全面大战场（服务器）——战雷式飞机受伤（用户 11-24 夜「把整个游戏做成战雷」④：飞机补齐）
--   飞机除了原来的机身血（e.hp，打光就炸），再分部件：左翼、右翼（直升机是主旋翼）、尾翼（直升机是尾桨）、发动机、油箱、飞行员、操纵面，各 100 血；
--   打在哪按命中点落在机身哪一段：翼展外侧是机翼、后三成是尾翼、中后段发动机、中段油箱、机头座舱（直升机：机身上方是旋翼）；
--   爆炸（近炸引信的导弹、高炮弹）按炸点落在哪一段分，连带旁边一块
--   · 机翼打断：断翼——往断的那边滚、升力少一大半（客户端 Fly.lua 按 WtaWing），12 秒还没摔就算被打下来
--     直升机主旋翼打断：没有升力，直接掉
--   · 尾翼打断：俯仰不受控、上下乱晃，舵效只剩三成（WtaTail）；直升机尾桨打断：机身打转；操纵面受损：舵效按血打折（WtaCtl）
--   · 发动机：受损推力按血打折，打坏没推力只能滑翔（WtaEng）；打中有机会起火
--   · 油箱：漏油（WtaLeak：每秒多烧内油的几成，Air.lua burnFuel），打中有机会起火
--   · 起火（WtaFire）：烧 14～26 秒，每秒掉 3% 机身血、着火的那块也掉；烧完自己灭
--   · 飞行员：0 血昏迷（WtaKO）——松杆失控，4 秒后算被打下来（记给打的人）
--   打的人 { op = "wtaHit" }、挨打的 { op = "wtaHurt" }（WtHud 写字）；部件状态写属性 WtaP（每块一位 0～9）
local WtAir = {}

function WtAir.init(G)
  local now = os.clock
  local JET = { "wingL", "wingR", "tail", "eng", "fuel", "pilot", "ctrl" }
  local HELI = { "rotor", "tail", "eng", "fuel", "pilot", "ctrl" }
  local K = 2.4   -- 这一下占机身满血的几成 × 100 × K = 部件掉的血：打掉四成机身血的一发能把那块打断
  local FIRE_DPS = 0.03
  local planes = {}

  local function partsOf(e) return (e.def and e.def.kind == "heli") and HELI or JET end

  local function push(e)
    local S = e.wta
    if not S or not e.model then return end
    local m = e.model
    local ds = {}
    for _, k in ipairs(S.list) do table.insert(ds, tostring(math.clamp(math.ceil(S.p[k] / 11), 0, 9))) end
    m:SetAttribute("WtaP", table.concat(ds))
    local eng = S.p.eng
    m:SetAttribute("WtaEng", (eng <= 0) and 0 or ((eng >= 70) and 1 or (0.3 + 0.7 * eng / 70)))
    m:SetAttribute("WtaCtl", math.clamp(0.4 + 0.6 * S.p.ctrl / 100, 0.4, 1))
    m:SetAttribute("WtaWing", S.wing)
    m:SetAttribute("WtaTail", S.p.tail <= 0)
    m:SetAttribute("WtaLift", (S.p.rotor or 100) <= 0 and 0 or 1)
    m:SetAttribute("WtaFire", S.fireT ~= nil)
    m:SetAttribute("WtaLeak", (S.leak > 0) and S.leak or nil)
    m:SetAttribute("WtaKO", S.koT ~= nil)
  end

  function G.wtaSetup(e)
    local list = partsOf(e)
    local p = {}
    for _, k in ipairs(list) do p[k] = 100 end
    e.wta = { list = list, p = p, leak = 0, maxHp = e.hp, fireT = nil, wing = nil, wingT = nil, koT = nil, src = nil, msgT = {} }
    planes[e] = true
    push(e)
  end

  -- 打在哪几块：{ { 部件, 权重 } … }
  local function partAt(e, pos)
    local d = e.def
    local heli = d.kind == "heli"
    if not pos then   -- 不知道打在哪（地面火力的溅射……）：按面积随便挑一块
      local r = math.random()
      if heli then
        if r < 0.25 then return { { "rotor", 1 } } elseif r < 0.45 then return { { "eng", 1 } } elseif r < 0.65 then return { { "fuel", 1 } }
        elseif r < 0.8 then return { { "tail", 1 } } elseif r < 0.9 then return { { "ctrl", 1 } } else return { { "pilot", 1 } } end
      end
      if r < 0.3 then return { { (r < 0.15) and "wingL" or "wingR", 1 } } elseif r < 0.55 then return { { "fuel", 1 } }
      elseif r < 0.75 then return { { "eng", 1 } } elseif r < 0.88 then return { { "tail", 1 } } elseif r < 0.95 then return { { "ctrl", 1 } } end
      return { { "pilot", 1 } }
    end
    local l = e.root.CFrame:PointToObjectSpace(pos)
    local u = l.X / math.max(1, (d.W or 10) / 2)
    local v = l.Z / math.max(1, (d.L or 20) / 2)   -- −1 机头、+1 机尾
    if heli then
      if l.Y > (d.H or 10) * 0.25 then return { { "rotor", 1 }, { "ctrl", 0.3 } } end
      if v > 0.45 then return { { "tail", 1 } } end
      if v < -0.45 then return { { "pilot", 1.6 }, { "ctrl", 0.3 } } end   -- 人比铝皮脆：座舱挨一发炮弹基本就昏了
      return { { "eng", 0.8 }, { "fuel", 0.6 } }
    end
    if math.abs(u) > 0.3 then return { { (u < 0) and "wingL" or "wingR", 1 }, { "ctrl", 0.3 }, { "fuel", 0.15 } } end
    if v > 0.55 then return { { "tail", 1 }, { "ctrl", 0.4 } } end
    if v < -0.5 then return { { "pilot", 1.6 }, { "ctrl", 0.3 } } end   -- 人比铝皮脆：座舱挨一发炮弹基本就昏了
    if v > 0.1 then return { { "eng", 1 }, { "fuel", 0.3 } } end
    return { { "fuel", 1 }, { "eng", 0.25 } }
  end

  local function destroy(e, src)
    if not e.alive then return end
    G.wtRaw = true
    local ok, err = pcall(G.damageEnt, e, 1e9, src)
    G.wtRaw = nil
    if not ok then G.reportError("战雷飞机", err) end
  end

  local function ignite(e, src)
    local S = e.wta
    if S.fireT then return false end
    S.fireT, S.fireEnd, S.fireSrc = now(), now() + 14 + math.random() * 12, src
    return true
  end

  -- 一块掉血：越过门槛的事记进 out（打的人、挨打的人看的字）
  local function hurtPart(e, k, dmg, src, out)
    local S = e.wta
    local v0 = S.p[k]
    if not v0 or v0 <= 0 or dmg <= 0 then return end
    local v1 = math.max(0, v0 - dmg)
    S.p[k] = v1
    table.insert(out.parts, k)
    if v1 <= 0 then
      table.insert(out.ev, k .. "Off")
      if k == "wingL" or k == "wingR" then
        S.wing = S.wing or ((k == "wingL") and "L" or "R")
        S.wingT = S.wingT or now()
      elseif k == "pilot" then
        S.koT = S.koT or now()
      elseif k == "rotor" then
        S.wingT = S.wingT or now()   -- 旋翼没了：掉下去，12 秒还没摔就算打下来
      end
    end
    -- 起火、漏油
    if k == "eng" and math.random() < 0.35 * math.clamp(dmg / 20, 0.3, 1) and ignite(e, src) then table.insert(out.ev, "fire") end
    if k == "fuel" then
      local was = S.leak
      S.leak = math.min(0.02, S.leak + 0.002 + dmg / 100 * 0.01)
      if was <= 0 then table.insert(out.ev, "leak") end
      if math.random() < 0.25 * math.clamp(dmg / 20, 0.3, 1) and ignite(e, src) then table.insert(out.ev, "fire") end
    end
  end

  local function sendMsg(e, src, out)
    if #out.parts == 0 and #out.ev == 0 then return end
    local S = e.wta
    local t = now()
    -- 打的人：同一个目标 0.4 秒内的并成一条（机枪一串打过来不刷屏）
    local P = src and src.P
    if P and P.pl and G.P[P.pl] == P then
      local last = S.msgT[P] or 0
      if t - last > 0.4 or #out.ev > 0 then
        S.msgT[P] = t
        G.R.Drive:FireClient(P.pl, { op = "wtaHit", veh = e.def.id, parts = out.parts, ev = out.ev })
      end
    end
    local D = e.driver
    if D and D.pl and (#out.ev > 0 or t - (S.hurtT or 0) > 0.8) then
      S.hurtT = t
      G.R.Drive:FireClient(D.pl, { op = "wtaHurt", parts = out.parts, ev = out.ev })
    end
  end

  -- Ents.damageEnt 交过来的每一下（机身血照扣）：pos 打中 / 炸点（G.wtPos）
  function G.wtaHit(e, amt, src, pos)
    local S = e.wta
    if not S or not e.alive or amt <= 0 then return end
    local frac = amt / math.max(1, S.maxHp)
    if frac < 0.004 then return end
    if src then S.src = src end
    local out = { parts = {}, ev = {} }
    for _, pw in ipairs(partAt(e, pos)) do hurtPart(e, pw[1], frac * 100 * K * pw[2], src, out) end
    push(e)
    sendMsg(e, src, out)
  end

  -- 漏油（Air.lua burnFuel 每秒多烧这么多内油）
  function G.wtaLeak(e) return (e.wta and e.wta.leak) or 0 end

  -- 每 0.25 秒：起火掉血、烧完灭火、断翼 / 昏迷到时间算打下来
  local acc = 0
  game:GetService("RunService").Heartbeat:Connect(function(dt)
    acc += dt
    if acc < 0.25 then return end
    local step = acc
    acc = 0
    local t = now()
    for e in pairs(planes) do
      local S = e.wta
      if not e.alive or not S then
        planes[e] = nil
      else
        local dirty = false
        if S.fireT then
          if t >= S.fireEnd then
            S.fireT = nil
            dirty = true
            if e.driver and e.driver.pl then G.R.Drive:FireClient(e.driver.pl, { op = "wtaHurt", parts = {}, ev = { "fireOut" } }) end
          else
            local burn = (S.p.eng > 0 and S.p.eng < 100) and "eng" or "fuel"
            S.p[burn] = math.max(0, S.p[burn] - 2 * step)
            G.wtRaw = true
            local ok, err = pcall(G.damageEnt, e, S.maxHp * FIRE_DPS * step, S.fireSrc or S.src)
            G.wtRaw = nil
            if not ok then G.reportError("飞机起火", err) end
            dirty = true
          end
        end
        if e.alive and S.koT and t - S.koT > 4 then destroy(e, S.src) end
        if e.alive and S.wingT and t - S.wingT > 12 then destroy(e, S.src) end
        if dirty and e.alive then push(e) end
      end
    end
  end)
end

return WtAir
