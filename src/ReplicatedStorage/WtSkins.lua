-- Roblox全面大战场（共用）——涂装、贴花（用户 11-25「全部都做」⑯：战雷里每辆车能换涂装、贴战术号码和国徽）
--   CAMO：零件拼的车（没导入原模型）直接按 base / dark / light 上色（VehModels.build 的 paint）；导入的原模型有自己的贴图，
--     只能把贴图整体乘一个色调（SurfaceAppearance.Color）——tint 是那个色调（冬季这种要变白的，乘色调做不到，原模型上看着只是灰一点）
--   贴花：战术号码（0～999，炮塔两侧白色模板字）、国徽（按系：中俄红星、美军白星、日本红圆；德国不贴十字——Roblox 审核会判违规）——客户端 View.lua 贴
local C = Color3.fromRGB
local S = {}

S.ORDER = { "std", "desert", "wood", "winter", "urban", "nato" }
S.CAMO = {
  std = { zh = "原厂", en = "Factory" },
  desert = { zh = "沙漠", en = "Desert", base = C(196, 170, 120), dark = C(150, 124, 84), light = C(220, 200, 156), tint = C(255, 232, 186) },
  wood = { zh = "林地", en = "Woodland", base = C(86, 98, 62), dark = C(52, 60, 38), light = C(120, 112, 80), tint = C(206, 232, 190) },
  winter = { zh = "冬季", en = "Winter", base = C(220, 224, 226), dark = C(150, 156, 160), light = C(240, 242, 244), tint = C(236, 240, 244) },
  urban = { zh = "城市灰", en = "Urban grey", base = C(116, 120, 122), dark = C(72, 76, 78), light = C(160, 164, 166), tint = C(206, 210, 214) },
  nato = { zh = "北约三色", en = "NATO 3-tone", base = C(70, 84, 56), dark = C(36, 38, 34), light = C(94, 78, 56), tint = C(214, 224, 198) },
}
-- 国徽（字形；颜色）：按科技树的系（键的前缀）
S.EMB = {
  cn = { "★", C(222, 40, 36) }, ru = { "★", C(210, 32, 32) }, us = { "★", C(240, 240, 240) },
  jp = { "●", C(214, 32, 40) },   -- 德国不贴：联邦国防军的十字被 Roblox 审核当成仇恨符号（11-25 用户账号因为豹 2A6 贴图上的十字被警告）
}
function S.natOf(treeKey, team)
  local n = type(treeKey) == "string" and string.match(treeKey, "^(%a%a)_") or nil
  if n and S.EMB[n] then return n end
  return (team == "def") and "us" or "cn"
end

return S
