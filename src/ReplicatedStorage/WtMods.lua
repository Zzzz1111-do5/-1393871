-- 全面大战场——科技树每辆车的改装（用户 11-25「都要做」：照战雷那样，车买来是「原厂」状态，打仗挣研究点一项项研究改装）
--   这辆车打仗挣的研究点先给它正在研究的那项改装（Tech.lua G.treeAward；没选就自动挑下一项），研究完自动装上、效果真的生效：
--   地面车：
--     机动——履带（转向快）、悬挂（加速、转向）、空滤（极速、加速）、传动（加速）、发动机（极速、加速）：
--       车上的 ModSpd / ModAcc / ModTurn 属性，客户端 Drive.lua 开车时乘（服务器按型号车速的 1.5 倍限移动，加的这点不会被拉回）
--     防护——零件（没研究：坏了的模块修不了，Wt.lua wtFix）、灭火器（没研究：着火只能等它烧完，wtExt）、
--       烟幕弹（没研究：车上没烟幕弹）、工具箱（修车快四分之一）
--     火力——炮塔驱动（炮塔转得快：ModTrav）、第二种弹 / 第三种弹（没研究只能打第一种：服务器 Armor.lua 按 ModAmmo 认，客户端换弹也跳过）
--   飞机：散热器 / 压缩机 / 发动机 / 新发动机（推力：ModThr，客户端 Fly.lua 乘）、机身 / 机翼 / 座舱装甲（血量）、
--     干扰弹（没研究：没有热焰弹）
--   每一级研究完 TIER_NEED 项开下一级；价钱按这辆车的级别（越新越贵）
local M = {}

M.CLS = { "mob", "pro", "fire" }
M.CLS_NAME = { mob = { "机动", "Mobility" }, pro = { "防护", "Protection" }, fire = { "火力", "Firepower" } }
M.TIER_NEED = 2
M.BASE = { 1200, 1800, 2400, 3000 }   -- 第一级车每级改装多少研究点（整套约 2.5 万，一局打得好挣五六千：四五局装齐）；车每高一级 × 1.5

-- fx：效果（下面 M.fx 合起来）；desc：界面上写的（和效果一致）
M.GROUND = {
  { key = "tracks", cls = "mob", tier = 1, zh = "履带", en = "Tracks", fx = { turn = 1.06 }, dz = "转向快 6%", de = "Turning +6%" },
  { key = "parts", cls = "pro", tier = 1, zh = "零件", en = "Parts", fx = { repair = true }, dz = "能在战场上修坏了的模块（没有它坏了就修不了）", de = "Repair damaged modules in battle" },
  { key = "ammo2", cls = "fire", tier = 1, zh = "第二种弹", en = "2nd ammo type", fx = { ammo = 2 }, dz = "解锁这门炮的第二种弹", de = "Unlocks the gun's 2nd shell" },
  { key = "susp", cls = "mob", tier = 2, zh = "悬挂", en = "Suspension", fx = { accel = 1.05, turn = 1.04 }, dz = "加速快 5%、转向快 4%", de = "Accel +5%, turning +4%" },
  { key = "fpe", cls = "pro", tier = 2, zh = "灭火器", en = "FPE", fx = { ext = true }, dz = "着火能自己扑灭（没有它只能等火烧完）", de = "Put out fires yourself" },
  { key = "hdrive", cls = "fire", tier = 2, zh = "炮塔驱动", en = "Horizontal drive", fx = { trav = 1.15 }, dz = "炮塔转得快 15%", de = "Turret traverse +15%" },
  { key = "filter", cls = "mob", tier = 3, zh = "空滤", en = "Filters", fx = { speed = 1.03, accel = 1.05 }, dz = "极速 +3%、加速快 5%", de = "Top speed +3%, accel +5%" },
  { key = "smoke", cls = "pro", tier = 3, zh = "烟幕弹", en = "Smoke grenades", fx = { smoke = true }, dz = "车上装烟幕弹发射器", de = "Smoke grenade launchers" },
  { key = "ammo3", cls = "fire", tier = 3, zh = "第三种弹", en = "3rd ammo type", fx = { ammo = 3 }, dz = "解锁这门炮的第三种弹", de = "Unlocks the gun's 3rd shell" },
  { key = "trans", cls = "mob", tier = 4, zh = "传动", en = "Transmission", fx = { accel = 1.08, speed = 1.02 }, dz = "加速快 8%、极速 +2%", de = "Accel +8%, top speed +2%" },
  { key = "engine", cls = "mob", tier = 4, zh = "发动机", en = "Engine", fx = { speed = 1.06, accel = 1.1 }, dz = "极速 +6%、加速快 10%", de = "Top speed +6%, accel +10%" },
  { key = "tools", cls = "pro", tier = 4, zh = "工具箱", en = "Improved parts", fx = { repK = 0.75 }, dz = "修车快四分之一", de = "Repairs 25% faster" },
}
M.AIR = {
  { key = "rad", cls = "mob", tier = 1, zh = "散热器", en = "Radiator", fx = { thr = 1.02 }, dz = "推力 +2%", de = "Thrust +2%" },
  { key = "fuse", cls = "pro", tier = 1, zh = "机身修理", en = "Fuselage repair", fx = { hp = 1.05 }, dz = "机身血量 +5%", de = "Airframe HP +5%" },
  { key = "comp", cls = "mob", tier = 2, zh = "压缩机", en = "Compressor", fx = { thr = 1.03 }, dz = "推力 +3%", de = "Thrust +3%" },
  { key = "wing", cls = "pro", tier = 2, zh = "机翼修理", en = "Wings repair", fx = { hp = 1.05 }, dz = "机身血量 +5%", de = "Airframe HP +5%" },
  { key = "engine", cls = "mob", tier = 3, zh = "发动机", en = "Engine", fx = { thr = 1.05 }, dz = "推力 +5%", de = "Thrust +5%" },
  { key = "flares", cls = "pro", tier = 3, zh = "干扰弹", en = "Countermeasures", fx = { flares = true }, dz = "带热焰弹（没有它挂不了）", de = "Carry flares" },
  { key = "neweng", cls = "mob", tier = 4, zh = "新发动机", en = "New engines", fx = { thr = 1.04 }, dz = "推力 +4%", de = "Thrust +4%" },
  { key = "cover", cls = "pro", tier = 4, zh = "座舱装甲", en = "Cockpit armor", fx = { hp = 1.05 }, dz = "机身血量 +5%", de = "Airframe HP +5%" },
}

function M.list(it) return (it and it.branch == "air") and M.AIR or M.GROUND end
function M.get(it, key)
  for _, m in ipairs(M.list(it)) do if m.key == key then return m end end
  return nil
end
function M.cost(it, m)
  local base = M.BASE[m.tier] or 1000
  return math.floor(base * (1 + 0.5 * (((it and it.rank) or 1) - 1)) / 50 + 0.5) * 50
end
-- 这一级开了没有：上一级研究完 TIER_NEED 项
function M.tierOpen(it, done, tier)
  if tier <= 1 then return true end
  local n = 0
  for _, m in ipairs(M.list(it)) do
    if m.tier == tier - 1 and done and done[m.key] then n += 1 end
  end
  return n >= M.TIER_NEED
end
function M.canResearch(it, done, key)
  local m = M.get(it, key)
  if not m or (done and done[key]) then return false end
  return M.tierOpen(it, done, m.tier)
end
-- 下一项（没选研究目标时自动挑）：级别低的先，同一级按机动、防护、火力
function M.nextKey(it, done)
  for tier = 1, 4 do
    for _, c in ipairs(M.CLS) do
      for _, m in ipairs(M.list(it)) do
        if m.tier == tier and m.cls == c and not (done and done[m.key]) and M.tierOpen(it, done, tier) then return m.key end
      end
    end
  end
  return nil
end
function M.count(it, done)
  local n, all = 0, 0
  for _, m in ipairs(M.list(it)) do
    all += 1
    if done and done[m.key] then n += 1 end
  end
  return n, all
end
-- 装了的改装合起来的效果：倍率相乘，开关有一个就算；ammo 能打前几种弹（原厂只有第一种）
function M.fx(it, done)
  local f = { speed = 1, accel = 1, turn = 1, trav = 1, repK = 1, thr = 1, hp = 1, ammo = 1, repair = false, ext = false, smoke = false, flares = false }
  for _, m in ipairs(M.list(it)) do
    if done and done[m.key] then
      for k, v in pairs(m.fx) do
        if type(v) == "boolean" then f[k] = f[k] or v
        elseif k == "ammo" then f.ammo = math.max(f.ammo, v)
        else f[k] = (f[k] or 1) * v end
      end
    end
  end
  return f
end

return M
