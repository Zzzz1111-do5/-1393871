-- 全面大战场——乘员（用户 11-25「都要做」：照战雷）：每个系的出击阵容每个位置一组乘员（换车不换人），
--   打仗攒乘员经验 → 升级给技能点 → 点技能，效果真的生效（Tech.lua 出车时乘到车上）：
--   装填（装填快：服务器 Armor.lua 的装填时间、客户端 Drive.lua 的装填预测都乘 CrewRel）、瞄准（炮塔转得快：乘进 ModTrav）、
--   驾驶（加速、转向：乘进 ModAcc / ModTurn）、维修（修车快：乘进修车时间）、耐力（车里每个乘员的血：Wt.lua 的乘员血量）
local C = {}

C.SKILLS = {
  { key = "load", zh = "装填", en = "Loading", dz = "装填时间每级 −4%", de = "Reload −4% per level" },
  { key = "aim", zh = "瞄准", en = "Gunnery", dz = "炮塔转速每级 +4%", de = "Turret traverse +4% per level" },
  { key = "drive", zh = "驾驶", en = "Driving", dz = "加速、转向每级 +3%", de = "Accel & turning +3% per level" },
  { key = "repair", zh = "维修", en = "Repair", dz = "修车时间每级 −8%", de = "Repair time −8% per level" },
  { key = "vital", zh = "耐力", en = "Vitality", dz = "乘员血量每级 +8%", de = "Crew HP +8% per level" },
}
C.MAXLV = 5          -- 每项最多 5 级
C.PTS_PER_LV = 3     -- 乘员每升一级给几点
-- 第 n 级累计要多少经验（一局打得好四五百经验：头几级一两局一级，越往后越慢）
function C.xpFor(n) return math.floor(250 * n ^ 1.55) end
function C.level(xp)
  local n = 0
  while n < 40 and (xp or 0) >= C.xpFor(n + 1) do n += 1 end
  return n
end
-- 技能升到第 lv 级要几点（1、2、3、4、5）
function C.stepCost(lv) return lv end
function C.spent(sk)
  local s = 0
  for _, k in ipairs(C.SKILLS) do
    for l = 1, math.min(C.MAXLV, (sk and sk[k.key]) or 0) do s += C.stepCost(l) end
  end
  return s
end
-- 还能用的技能点
function C.free(cr)
  return C.level(cr and cr.xp or 0) * C.PTS_PER_LV - C.spent(cr and cr.sk)
end
function C.fx(sk)
  sk = sk or {}
  return {
    rel = 1 - 0.04 * (sk.load or 0),
    trav = 1 + 0.04 * (sk.aim or 0),
    drive = 1 + 0.03 * (sk.drive or 0),
    repK = 1 - 0.08 * (sk.repair or 0),
    vital = 1 + 0.08 * (sk.vital or 0),
  }
end
-- 一局的乘员经验：得分 × 0.8 + 击毁 × 40 + 60（赢了多三成）
function C.award(score, kills, won)
  return math.floor(((score or 0) * 0.8 + (kills or 0) * 40 + 60) * (won and 1.3 or 1))
end

return C
