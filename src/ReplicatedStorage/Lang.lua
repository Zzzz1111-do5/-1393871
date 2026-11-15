-- 暗剑：登岛战——中英文字。服务器给客户端发的是文字编号和参数，各人按自己的语言显示
--   客户端按 LocalizationService.RobloxLocaleId 判断：zh 开头用中文，其余英文；设置里能手动切
--   Lang.t(lang, key, ...)：{1} {2} … 换成参数；参数是表 { k = "编号", … } 时先翻译它（服务器发「据点 A」「步枪兵」这种）
local Lang = {}

local ZH, EN = {}, {}
Lang.zh, Lang.en = ZH, EN

local function add(key, zh, en)
  ZH[key] = zh
  EN[key] = en
end

---------------------------------------------------------------- 名字

add("game.title", "暗剑：登岛战", "Darksword: Island Assault")
add("team.atk", "进攻方", "Attackers")
add("team.def", "防守方", "Defenders")
add("team.atk.short", "攻", "ATK")
add("team.def.short", "守", "DEF")

add("role.rifle", "步枪兵", "Rifleman")
add("role.mg", "机枪手", "Machine Gunner")
add("role.sniper", "狙击手", "Sniper")
add("role.at", "反坦克兵", "Anti-Tank")
add("role.aa", "防空兵", "Anti-Air")
add("role.medic", "医疗兵", "Medic")
add("role.engineer", "工兵", "Engineer")
add("role.mortar", "迫击炮手", "Mortarman")
add("role.spec", "特种兵", "Special Forces")
add("role.spotter", "观察员", "Spotter")
add("role.rifle.desc", "步枪 + 手枪 + 手雷，什么都能打", "Rifle, pistol and a grenade. Good at everything")
add("role.mg.desc", "百发弹链的机枪，压制冲上来的人", "100-round machine gun to pin down attackers")
add("role.sniper.desc", "远距离一枪一个，爆头双倍", "One shot from far away. Headshots deal double")
add("role.at.desc", "火箭筒打坦克、装甲车、碉堡", "Rocket launcher against tanks, APCs and bunkers")
add("role.aa.desc", "单兵防空导弹，锁定直升机、飞机", "Shoulder SAM that locks onto helicopters and jets")
add("role.medic.desc", "冲锋枪 + 急救包，给身边的队友回血", "SMG and a medkit that heals nearby teammates")
add("role.engineer.desc", "修车、埋反坦克地雷", "Repairs vehicles and lays anti-tank mines")
add("role.mortar.desc", "迫击炮：点准星下的地面，炮弹几秒后落下", "Mortar: shells land where you aim a few seconds later")
add("role.spec.desc", "跑得快的消音冲锋枪 + 炸药包", "Fast, suppressed SMG and C4 charges")
add("role.spotter.desc", "望远镜标记敌人，呼叫炮火覆盖", "Binoculars to mark enemies and call artillery")

add("weapon.rifle", "步枪", "Rifle")
add("weapon.carbine", "卡宾枪", "Carbine")
add("weapon.lmg", "机枪", "LMG")
add("weapon.sniper", "狙击枪", "Sniper Rifle")
add("weapon.smg", "冲锋枪", "SMG")
add("weapon.smgsd", "消音冲锋枪", "Suppressed SMG")
add("weapon.pistol", "手枪", "Pistol")
add("weapon.rpg", "火箭筒", "Rocket Launcher")
add("weapon.manpads", "防空导弹", "MANPADS")
add("weapon.grenade", "手雷", "Grenade")
add("weapon.mortar", "迫击炮", "Mortar")
add("weapon.medkit", "急救包", "Medkit")
add("weapon.repair", "扳手", "Repair Tool")
add("weapon.mine", "反坦克地雷", "AT Mine")
add("weapon.c4", "炸药包", "C4")
add("weapon.binoc", "望远镜", "Binoculars")

add("point.A", "A 前哨岛", "A Outpost Isle")
add("point.B", "B 灯塔岛", "B Lighthouse Isle")
add("point.C", "C 港口镇", "C Harbor Town")
add("point.D", "D 机场", "D Airfield")
add("point.E", "E 指挥所", "E Command Post")
add("beach.red", "红滩", "Red Beach")
add("beach.white", "白滩", "White Beach")
add("beach.blue", "蓝滩", "Blue Beach")
add("beach.gold", "金滩", "Gold Beach")
add("beach.flank", "东北滩（侧翼）", "NE Beach (flank)")
add("spawn.camp", "后方营地", "Rear Camp")
add("spawn.fleet", "舰队（两栖攻击舰）", "Fleet (assault ship)")
add("spawn.para", "伞降", "Paradrop")

add("vcat.tank", "坦克", "Tanks")
add("vcat.apc", "装甲车", "APCs")
add("vcat.aa", "防空", "Anti-Air")
add("vcat.arty", "火炮", "Artillery")
add("vcat.heli", "直升机", "Helicopters")
add("vcat.jet", "固定翼", "Jets")
add("vcat.ship", "舰艇", "Ships")
local VEH = {
  ztq15 = { "ZTQ-15 轻型坦克", "ZTQ-15 Light Tank" }, ztz96 = { "ZTZ-96 主战坦克", "ZTZ-96 MBT" }, ztz99a = { "ZTZ-99A 主战坦克", "ZTZ-99A MBT" },
  m10 = { "M10 布克", "M10 Booker" }, m1a1 = { "M1A1 艾布拉姆斯", "M1A1 Abrams" }, m1a2 = { "M1A2 SEPv3", "M1A2 SEPv3" },
  ztd05 = { "ZTD-05 两栖突击车", "ZTD-05 Amphibious Assault Gun" }, zbd05 = { "ZBD-05 两栖步战车", "ZBD-05 Amphibious IFV" },
  zsl92b = { "ZSL-92B 轮式步战车", "ZSL-92B Wheeled IFV" }, ptl02 = { "PTL-02 突击炮", "PTL-02 Assault Gun" },
  m1117 = { "M1117 装甲警卫车", "M1117 Guardian" }, hmmwv = { "悍马", "Humvee" }, jltv = { "JLTV 联合轻型战术车", "JLTV" },
  m2a3 = { "M2A3 布雷德利", "M2A3 Bradley" }, stryker = { "斯特赖克", "Stryker" }, m1150 = { "M1150 突击破障车", "M1150 ABV" },
  pgz07 = { "PGZ-07 自行高炮", "PGZ-07 SPAAG" }, pgl625 = { "PGL-625 弹炮结合防空车", "PGL-625 Gun-Missile AA" }, ld2000 = { "LD-2000 近防炮", "LD-2000 CIWS" },
  m163 = { "M163 火神高炮", "M163 VADS" }, mshorad = { "M-SHORAD", "M-SHORAD" }, cram = { "C-RAM 陆基密集阵", "C-RAM" }, patriot = { "爱国者", "Patriot" },
  plz07 = { "PLZ-07 自行榴弹炮", "PLZ-07 SPH" }, m109a7 = { "M109A7 帕拉丁", "M109A7 Paladin" }, m270 = { "M270 火箭炮", "M270 MLRS" }, m777 = { "M777 榴弹炮", "M777 Howitzer" },
  z10 = { "直-10 武装直升机", "Z-10 Attack Helicopter" }, z20 = { "直-20 运输直升机", "Z-20 Transport Helicopter" },
  ah64e = { "AH-64E 阿帕奇", "AH-64E Apache" }, uh60 = { "UH-60 黑鹰", "UH-60 Black Hawk" }, ch47 = { "CH-47 支奴干", "CH-47 Chinook" },
  j15t = { "歼-15T", "J-15T" }, j35 = { "歼-35", "J-35" }, j20 = { "歼-20", "J-20" }, j16 = { "歼-16", "J-16" }, j50 = { "歼-50", "J-50" },
  h6k = { "轰-6K", "H-6K" }, gj11 = { "攻击-11", "GJ-11" }, gj2 = { "攻击-2", "GJ-2" },
  a10c = { "A-10C 雷电", "A-10C Thunderbolt" }, f35 = { "F-35", "F-35" }, f22 = { "F-22 猛禽", "F-22 Raptor" }, mq9 = { "MQ-9 死神", "MQ-9 Reaper" }, b2 = { "B-2 幽灵", "B-2 Spirit" },
  t055 = { "055 型驱逐舰", "Type 055 Destroyer" }, t054a = { "054A 型护卫舰", "Type 054A Frigate" }, t022 = { "022 型导弹艇", "Type 022 Missile Boat" },
  ddg125 = { "DDG-125 驱逐舰", "DDG-125 Destroyer" }, cg47 = { "CG-47 巡洋舰", "CG-47 Cruiser" }, lcs2 = { "LCS-2 濒海战斗舰", "LCS-2 Littoral Combat Ship" }, pbr = { "PBR 巡逻艇", "PBR Patrol Boat" },
  lcm = { "登陆艇", "Landing Craft" }, lcac = { "726 型气垫艇", "Type 726 LCAC" },
}
for k, v in pairs(VEH) do add("veh." .. k, v[1], v[2]) end

local RANKS = {
  { "列兵", "Private" }, { "上等兵", "Private First Class" }, { "下士", "Corporal" }, { "中士", "Sergeant" }, { "上士", "Staff Sergeant" },
  { "少尉", "Second Lieutenant" }, { "中尉", "First Lieutenant" }, { "上尉", "Captain" }, { "少校", "Major" }, { "中校", "Lieutenant Colonel" },
  { "上校", "Colonel" }, { "大校", "Senior Colonel" }, { "少将", "Major General" }, { "中将", "Lieutenant General" }, { "上将", "General" },
}
for i, v in ipairs(RANKS) do add("rank." .. i, v[1], v[2]) end

---------------------------------------------------------------- 界面

add("ui.deploy", "部署", "Deploy")
add("ui.chooseRole", "选择兵种", "Choose your role")
add("ui.chooseSpawn", "选择出生点", "Choose a spawn point")
add("ui.deployBtn", "出击", "DEPLOY")
add("ui.waitRespawn", "{1} 秒后可以重新部署", "Redeploy in {1}s")
add("ui.prep", "准备阶段：{1} 秒后开战", "Get ready: battle starts in {1}s")
add("ui.youAre", "你在{1}", "You are on the {1}")
add("ui.goalAtk", "拿下全部 5 个据点（每拿下一个，时间 +3 分钟）", "Capture all 5 points (each capture adds 3 minutes)")
add("ui.goalDef", "守住任何一个据点直到时间结束", "Hold at least one point until time runs out")
add("ui.timeLeft", "剩余", "Time")
add("ui.overtime", "加时", "Overtime")
add("ui.capturing", "正在占领 {1}", "Capturing {1}")
add("ui.losing", "{1} 正在被攻方占领！", "{1} is being captured!")
add("ui.contested", "{1} 争夺中", "{1} contested")
add("ui.captured", "{1} 被攻方拿下了", "{1} has fallen to the Attackers")
add("ui.capturedYou", "拿下 {1}！时间 +3 分钟", "{1} captured! +3 minutes")
add("ui.scoreboard", "战况", "Scoreboard")
add("ui.kills", "击杀", "Kills")
add("ui.deaths", "阵亡", "Deaths")
add("ui.score", "得分", "Score")
add("ui.captures", "占领", "Caps")
add("ui.bot", "（AI）", "(AI)")
add("ui.win.atk", "进攻方胜利：5 个据点全部拿下", "ATTACKERS WIN: all 5 points captured")
add("ui.win.def", "防守方胜利：守住了据点", "DEFENDERS WIN: held the line")
add("ui.youWon", "你们赢了！", "Victory!")
add("ui.youLost", "你们输了", "Defeat")
add("ui.nextRound", "{1} 秒后开下一局，重新分队", "Next round in {1}s with new teams")
add("ui.xp", "经验 +{1}", "+{1} XP")
add("ui.rankUp", "晋升：{1}", "Promoted: {1}")
add("ui.killed", "{1} 击毙了 {2}", "{1} killed {2}")
add("ui.youKilled", "击毙 {1}", "Killed {1}")
add("ui.killedBy", "你被 {1} 击毙", "Killed by {1}")
add("ui.died", "你阵亡了", "You died")
add("ui.lang", "中文 / EN", "EN / 中文")
add("ui.ammo", "{1}  {2} / {3}", "{1}  {2} / {3}")
add("ui.reloading", "{1}  换弹中…", "{1}  reloading…")
add("ui.reloadKey", "R 换弹", "R to reload")
add("ui.healed", "治疗 +{1}", "Healed +{1}")
add("ui.spotted", "标记了 {1} 个敌人", "Spotted {1} enemies")
add("ui.strikeCalled", "炮火覆盖：{1} 秒后落下", "Artillery inbound in {1}s")
add("ui.strikeCd", "炮击还要 {1} 秒才能再叫", "Artillery ready in {1}s")
add("ui.mortarRange", "超出射程（{1}～{2}）", "Out of range ({1}-{2})")
add("ui.locking", "锁定中…", "Locking…")
add("ui.locked", "已锁定", "LOCKED")
add("ui.noTarget", "没有空中目标", "No air target")
add("ui.c4placed", "放好了炸药包（再按一次引爆）", "C4 placed (use again to detonate)")
add("ui.minePlaced", "埋好了反坦克地雷", "AT mine placed")
add("ui.outOfAmmo", "没有弹药了", "Out of ammo")
add("ui.landing", "登陆艇正在冲滩……", "Landing craft heading for the beach…")
add("ui.boatSunk", "登陆艇被击沉了", "Your landing craft was sunk")
add("ui.joinBalance", "人数不平衡，你被分到{1}", "Teams were unbalanced: you joined the {1}")
add("ui.pointLocked", "据点被攻方拿下后不能再夺回", "Captured points stay with the Attackers")
add("ui.serverStarting", "正在生成地图……{1}%", "Building the map… {1}%")
add("ui.needPick", "先选兵种和出生点", "Pick a role and a spawn point first")
add("ui.spawnBlocked", "这个出生点现在用不了", "That spawn point is not available right now")
add("ui.help", "WASD 移动 · 鼠标左键开火 · 右键瞄准 · R 换弹 · 1–4 切武器 · Tab 战况 · M 地图", "WASD move · LMB fire · RMB aim · R reload · 1-4 weapons · Tab scoreboard · M map")
add("ui.credits", "致谢", "Credits")
add("ui.close", "关闭", "Close")
add("ui.map", "地图", "Map")

---------------------------------------------------------------- 翻译

function Lang.pick(localeId)
  if type(localeId) == "string" and string.sub(string.lower(localeId), 1, 2) == "zh" then return "zh" end
  return "en"
end

local function tr(lang, key)
  local T = (lang == "zh") and ZH or EN
  return T[key] or ZH[key] or EN[key] or tostring(key)
end

function Lang.t(lang, key, ...)
  local s = tr(lang, key)
  local args = table.pack(...)
  if args.n == 0 then return s end
  return (string.gsub(s, "{(%d)}", function(i)
    local v = args[tonumber(i)]
    if type(v) == "table" and v.k then return tr(lang, v.k) end
    return tostring(v)
  end))
end

-- 军衔名（第几级）
function Lang.rank(lang, i) return tr(lang, "rank." .. i) end

return Lang
