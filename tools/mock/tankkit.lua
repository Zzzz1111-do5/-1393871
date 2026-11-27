-- 坦克改装体系（TankMods v2，用户 11-22 晚：「坦克要能自己选位置贴爆反」「一整套的坦克改装体系」「坦克上面就别贴了」）：
--   python3 tools/mock/run.py tools/mock/tankkit.lua
--   ① 数据：改装串来回、老写法（era="tf+gl"、aps="hk"）换成新的、按格贴（原车自带的总在）、候选格里没有朝上的（不贴车顶）、重量和车速
--   ② 服务器：M1A2 带 ARAT-2 + 侧裙后段 + Trophy + 栅栏 + 防雷板 + 扫雷犁 + 伪装网出车——爆反按格、Trophy 两个发射器各 4 发、扫雷犁属性
--   ③ 栅栏：火箭弹从车尾打来约一半哑火；从正面打来不管
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local TM = R.require(R.services.ReplicatedStorage:FindFirstChild("TankMods"))
local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))

print("① 数据")
-- 11-27 拆开重叠的版本：借同族模型、真车没有爆反的（noEra）一格都不贴、没有改装页；有爆反的同族变型改装页照同族
do
  local n = 0
  for _ in pairs(TM.cellsOn("m1")) do n = n + 1 end
  check(TM.eraOf("m1") == nil and n == 0 and not TM.has("m1"), "M1（借 M1A1 的模型）：ARAT 块不起作用、没有改装页（" .. n .. " 格）")
  check(TM.has("m1a2sep3") and TM.FOR.m1a2sep3 == TM.FOR.m1a2 and TM.SPEC.m1a2sep3 ~= nil and TM.SPEC.m1a2sep3.t > TM.SPEC.m1a2.t,
    "M1A2 SEPv3 的改装页照 SEPv2（ARAT / Trophy），车重按自己的 66.8 吨")
end
for _, id in ipairs({ "ztz99a", "ztz96", "m1a2", "m1a1" }) do
  local L = TM.eraOf(id)
  check(L and L.b and #L.b > 0, id .. " 有爆反格（" .. (L and #L.b or 0) .. "）")
  local up, ownN = 0, 0
  for _, b in ipairs(L.b) do
    if not TM.own(L, b) and b[6] > 0.8 then up = up + 1 end
    if TM.own(L, b) then ownN = ownN + 1 end
  end
  check(up == 0, id .. "：自选的格里没有朝上的（车顶不贴）")
  local m = TM.clean(id, {})
  local on = TM.cellsOn(id, m)
  local n = 0
  for _ in pairs(on) do n = n + 1 end
  check(n >= ownN, id .. "：出厂贴 " .. n .. " 格（原车自带 " .. ownN .. " 格总在）")
  local s = TM.encode(m)
  local m2 = TM.clean(id, TM.decode(s))
  check(TM.encode(m2) == s, id .. "：改装串来回一样（" .. s .. "）")
end
local L2 = TM.eraOf("m1a2")
local legacy = TM.clean("m1a2", { era = "sk+gl", aps = "hk" })
check(legacy.era == "arat" and legacy.aps == "trophy", "老写法换成新的：era=" .. legacy.era .. "、aps=" .. legacy.aps)
local srCells = TM.cellsInZones("m1a2", { "sr" })
local nsr = 0
for _ in pairs(srCells) do nsr = nsr + 1 end
check(nsr > 0, "M1A2 侧裙后段有 " .. nsr .. " 格能贴")
local full = { era = "arat2", ep = TM.epEncode(srCells, #L2.b), aps = "trophy", ew = "lws", slat = "slat", belly = "belly", eng = "plow", cam = "mcs" }
local st0 = TM.stats("m1a2", {})
local st1 = TM.stats("m1a2", full)
check(st1.t > st0.t + 8, string.format("全装加重：%.1f → %.1f 吨", st0.t, st1.t))
check(st1.vmax < st0.vmax and st1.pw < st0.pw, string.format("车速 %.0f → %.0f 公里 / 时，单位功率 %.1f → %.1f 马力 / 吨", st0.vmax, st1.vmax, st0.pw, st1.pw))
check(st1.travK < 1, "Trophy 让炮塔转得慢一点（" .. st1.travK .. "）")
local d0 = VD.get("m1a2")
local dd = TM.applyDef(d0, TM.encode(full))
check(dd.speed < d0.speed and dd.kit.slat and dd.kit.plow and dd.kit.mcs and dd.kit.belly, "型号数据按改装改了（车速、加装件）")

print("② 服务器出车")
local cx, cz = 0, 0
local e = G.newVehicle("def", "m1a2", G.vehBaseAt(d0, cx, cz, V3(0, 0, -1)), nil, TM.clean("m1a2", full))
R.run(0.5)
check(e and e.era, "爆反记下了")
local ownN = 0
for _, b in ipairs(L2.b) do if TM.own(L2, b) then ownN = ownN + 1 end end
check(e.era.n == ownN + nsr, "贴了 " .. e.era.n .. " 格（自带 " .. ownN .. " + 侧裙后段 " .. nsr .. "）")
check(e.era.kind == TM.ERA.arat2, "爆反型号是 ARAT-2")
check(e.aps and #e.aps.L == 2 and e.aps.max == 8, "Trophy：两个发射器、共 8 发")
check(e.model:GetAttribute("ApsSys") == "trophy", "模型属性 ApsSys = trophy")
check(e.model:GetAttribute("Plow") == 0, "扫雷犁收着（Plow = 0）")
check(string.find(e.model:GetAttribute("Mods") or "", "eng=plow", 1, true) ~= nil, "模型属性 Mods 写着扫雷犁")

print("③ 栅栏装甲")
local hull = e.root.CFrame
local rearP = (hull * CF(0, 0, e.def.L / 2 - 0.5)).Position
local frontP = (hull * CF(0, 0, -e.def.L / 2 + 0.5)).Position
local dud, n = 0, 40
for _ = 1, n do
  local s = { kind = "rocket", vel = hull.LookVector * 230, w = { dmg = 110 }, src = { team = "atk" } }   -- 从车尾往前打（速度朝车头）
  if G.kitRocket(s, { Instance = e.root, Position = rearP, Normal = hull.LookVector }) then dud = dud + 1 end
end
check(dud > n * 0.25 and dud < n * 0.75, "从车尾打 " .. n .. " 发，栅栏卡住 " .. dud .. " 发（约一半）")
local fd = 0
for _ = 1, 20 do
  local s = { kind = "rocket", vel = -hull.LookVector * 230, w = { dmg = 110 }, src = { team = "atk" } }
  if G.kitRocket(s, { Instance = e.root, Position = frontP, Normal = -hull.LookVector }) then fd = fd + 1 end
end
check(fd == 0, "从正面打：栅栏不管（" .. fd .. "）")
check(G.sigK(e) < 1, "伪装网：被发现的距离 × " .. G.sigK(e))

print("④ 爆反挡导弹按装药（11-27 审查：Era.lua 原来对导弹一律按串联算——车上的反坦克导弹其实整个绕过了爆反）")
do
  local E = e.era
  local K, L = E and E.kind, E and E.L
  local base = e.root.CFrame * CF(0, -e.def.H / 2, 0)
  -- 挑一格还在的侧裙块（自带的 sk + 贴的 sr），从块外面顺着它的法线往里打：一发炸一格
  local function cellCF()
    for i, b in ipairs(L.b) do
      if not E.dead[i] and not (E.off and E.off[i]) and (b[17] == "sk" or b[17] == "sr") then return (TM.blockCF(L, b, base, e.ty or 0, 1)) end
    end
    return nil
  end
  local function hit(w)
    local cf = cellCF()
    if not cf then return "没有剩下的格" end
    local left0 = E.left
    local m = G.eraBlast(cf.Position + cf.ZVector * 3, w, -cf.ZVector * 200)
    return m and m[e], left0 - E.left
  end
  local refl = G.tankWeaponOf("gun125r", VD.W.gun125r, "refleks")   -- 炮射导弹「反射」：开火时的武器表（炮的那份 + ammo）
  local cases = {
    { "陶式 1（tow1，单装药）", VD.W.tow1, "k" }, { "红箭-73（单装药）", VD.W.hj73, "k" }, { "「婴儿」（单装药）", VD.W.malyutka, "k" },
    { "陶式 2（串联）", VD.W.tow2, "kt" }, { "「短号」（串联）", VD.W.kornet, "kt" }, { "「反射」炮射导弹（串联）", refl, "kt" },
    { "火箭弹", { kind = "rkt", dmg = 110, splash = 4 }, "k" },
  }
  check(K == TM.ERA.arat2 and K.k < K.kt, string.format("这辆 M1A2 挂 ARAT-2（单装药剩 %.2f、串联剩 %.2f）", K and K.k or -1, K and K.kt or -1))
  local gc = G.eraClass and G.eraClass(VD.W.gun120)
  check(G.eraClass and G.eraClass(VD.W.tow1) == "msl" and G.eraClass(refl) == "msl" and gc ~= "msl" and gc ~= "rkt",
    "车上的反坦克导弹、炮射导弹按导弹挡（原来 boomKind 认不出 kind = atgm），坦克炮弹不走这里（" .. tostring(gc) .. "：G.eraShell 管）")
  for _, c in ipairs(cases) do
    local k, n = hit(c[2])
    check(k == K[c[3]] and n == 1, string.format("%s：剩 %s 成（应为 %s = %.2f），炸了 %s 格", c[1], tostring(k), c[3], K[c[3]], tostring(n)))
  end
  check(G.eraBlast(e.root.Position + V3(0, 0, -30), VD.W.gun120, V3(0, 0, 1)) == nil, "坦克炮弹（动能弹）不走火箭弹 / 导弹这条（eraBlast 不管）")
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
