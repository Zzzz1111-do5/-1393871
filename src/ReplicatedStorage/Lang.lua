-- Roblox全面大战场——中英文字。服务器给客户端发的是文字编号和参数，各人按自己的语言显示
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

add("game.title", "Roblox全面大战场", "Roblox Total Battlefield")
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
add("role.rifle.desc", "M4 卡宾枪 + 手雷，什么都能打", "M4 carbine and a grenade. Good at everything")
add("role.mg.desc", "百发弹链的机枪，压制冲上来的人", "100-round machine gun to pin down attackers")
add("role.sniper.desc", "远距离一枪一个，爆头双倍；另带一支 M4", "One shot from far away, headshots deal double; carries an M4 too")
add("role.at.desc", "火箭筒打坦克、装甲车、碉堡", "Rocket launcher against tanks, APCs and bunkers")
add("role.aa.desc", "单兵防空导弹，锁定直升机、飞机", "Shoulder SAM that locks onto helicopters and jets")
add("role.medic.desc", "M4 + 急救包，给身边的队友回血", "M4 and a medkit that heals nearby teammates")
add("role.engineer.desc", "修车、修工事；探雷、排雷、剪铁丝网", "Repairs vehicles and forts; finds and clears mines, cuts wire")
add("role.mortar.desc", "迫击炮：点准星下的地面，炮弹几秒后落下", "Mortar: shells land where you aim a few seconds later")
add("role.spec.desc", "跑得最快，M4 + 炸药包 + 手雷", "The fastest runner, with an M4, C4 charges and a grenade")
add("role.spotter.desc", "望远镜标记敌人，呼叫炮火覆盖", "Binoculars to mark enemies and call artillery")

add("weapon.m4", "M4 卡宾枪", "M4 Carbine")
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
add("weapon.breach", "破障器材", "Breaching Kit")
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
add("beach.outpost", "前哨岛南岸", "Outpost Isle (south)")
add("beach.lighthouse", "灯塔岛南岸", "Lighthouse Isle (south)")
add("beach.port", "港湾（直冲港口）", "Harbor (port assault)")
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

-- 地图自带的工事、障碍
add("fort.bunker", "机枪碉堡", "MG Bunker")
add("fort.coastal", "岸防炮", "Coastal Gun")
add("fort.aaa", "高炮", "AA Gun")
add("fort.howitzer", "M777 榴弹炮", "M777 Howitzer")
add("fort.mine", "地雷", "Mine")
add("fort.strike", "炮火支援", "Artillery")
add("fw.hmg", "12.7 毫米机枪", "12.7 mm MG")
add("fw.naval127", "127 毫米炮", "127 mm gun")
add("fw.flak35", "双联 35 毫米高炮", "Twin 35 mm AA")
add("fw.how155", "155 毫米榴弹炮", "155 mm howitzer")
add("ui.man", "操作", "Man")
add("ui.board", "上车", "Enter")
add("ui.manned", "你在操作{1}", "You are manning the {1}")
add("ui.fortKilled", "摧毁 {1}", "Destroyed {1}")
add("ui.fortDown", "{1} 摧毁了 {2}", "{1} destroyed {2}")
add("ui.fortLost", "你操作的工事被摧毁了", "The emplacement you were manning was destroyed")
add("ui.fortHelp", "鼠标 瞄准 · 左键 开火 · 右键 / V 瞄准镜 · 滚轮 倍率 · F 离开", "Mouse aim · LMB fire · RMB / V sight · Wheel zoom · F leave")
add("ui.howHelp", "鼠标指向落点 · 左键 开炮 · 右键 放大 · F 离开", "Point at the target · LMB fire · RMB zoom · F leave")
add("ui.howRange", "{1} 米（射程 {2}～{3}）", "{1} m (range {2}-{3})")
add("ui.reloadIn", "装填 {1} 秒", "Reloading {1}s")
add("ui.inWire", "铁丝网：走不快", "Barbed wire slows you down")
add("ui.defusing", "排雷中… {1}%", "Clearing mine… {1}%")
add("ui.cutting", "剪铁丝网… {1}%", "Cutting wire… {1}%")
add("ui.defused", "排除了一颗地雷", "Mine cleared")
add("ui.wireCut", "剪开了一段铁丝网", "Wire cut")
add("ui.mineNear", "附近有地雷 ×{1}（按住左键排雷）", "Mines nearby ×{1} (hold LMB to clear)")
add("ui.wireNear", "按住左键剪铁丝网", "Hold LMB to cut the wire")
add("ui.noMines", "附近没探到地雷", "No mines detected nearby")

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
add("ui.help", "WASD 移动 · 左键开火 · 右键开镜 · R 换弹 · 1–4 切武器 · V 第一 / 第三人称 · E 上车 / 操作 · Tab 战况 · M 地图",
  "WASD move · LMB fire · RMB aim · R reload · 1-4 weapons · V 1st / 3rd person · E enter / man · Tab scoreboard · M map")
-- 载具
add("ui.tabInf", "步兵", "Infantry")
add("ui.tabVeh", "载具", "Vehicles")
add("ui.vehCap", "在场 {1} / {2}", "{1} / {2} in use")
add("ui.vehCd", "冷却 {1} 秒", "Cooldown {1}s")
add("ui.vehFull", "这类载具已经满了", "No free slot for this vehicle type")
add("ui.vehLost", "你的载具被击毁了", "Your vehicle was destroyed")
add("ui.vehKilled", "击毁 {1}", "Destroyed {1}")
add("ui.outOfRange", "超出射程", "Out of range")
add("ui.needSpawnVeh", "载具只能在海滩、据点或营地出生", "Vehicles spawn at beaches, held points or the camp")
add("ui.lcac", "气垫艇正把你的车送上滩……", "The hovercraft is bringing your vehicle ashore...")
add("ui.vehHelp", "WASD 驾驶 · 鼠标 瞄准 · 左键 开火 · 1/2 换武器 · X 烟幕弹 · 右键 / V 瞄准镜 · N 夜视 / 热成像 · F 下车",
  "WASD drive · Mouse aim · LMB fire · 1/2 weapon · X smoke · RMB / V gunner sight · N night vision / thermal · F exit")
add("ui.enterVeh", "按 F 上车", "Press F to enter")

-- 飞机、直升机
add("spawn.air.lhd", "075 两栖攻击舰甲板", "Type 075 flight deck")
add("spawn.air.cv", "航母甲板（舰载机）", "Carrier deck (naval jets)")
add("spawn.air.af2", "攻方机场岛", "Island airstrip")
add("spawn.air.af", "主岛机场", "Main island airfield")
add("spawn.air.in", "空中出发", "Air start")
add("spawn.air.camp", "营地停机坪", "Camp helipad")
add("spawn.air.pt", "据点 {1} 停机坪", "Helipad at {1}")
add("ui.loadout", "挂载：{1}", "Loadout: {1}")
add("ui.rearmed", "补满了弹药和热诱弹", "Rearmed and resupplied with flares")
add("ui.notCarrier", "这型飞机上不了航母", "This aircraft can't operate from the carrier")
local PRESET = {
  aa = { "空战", "Air superiority" }, ag = { "对地", "Ground attack" }, beast = { "满挂", "Full load" }, at = { "反坦克", "Anti-tank" },
  mix = { "混合", "Mixed" }, rkt = { "火箭", "Rockets" }, none = { "空载", "Unarmed" }, dap = { "火力型", "Gunship" }, strike = { "轰炸", "Strike" },
  bomb = { "炸弹", "Bombs" }, kd88 = { "KD-88 远程打击", "KD-88 standoff" }, cas = { "近距支援", "Close air support" }, hk = { "猎杀", "Hunter-killer" },
  jdam = { "联合直接攻击弹药", "JDAM" }, mk82 = { "Mk 82 炸弹", "Mk 82 bombs" },
}
for k, v in pairs(PRESET) do add("preset." .. k, v[1], v[2]) end
local AW = {
  gsh30 = { "30 毫米航炮", "30 mm cannon" }, m61 = { "20 毫米航炮", "20 mm cannon" }, gau22 = { "25 毫米航炮", "25 mm cannon" }, gau8 = { "GAU-8 30 毫米机炮", "GAU-8 30 mm" },
  m230 = { "30 毫米链式炮", "30 mm chain gun" }, zh23 = { "23 毫米炮", "23 mm turret" }, m134 = { "舱门机枪", "Door gun" },
  pl10 = { "霹雳-10", "PL-10" }, pl15 = { "霹雳-15", "PL-15" }, aim9x = { "AIM-9X", "AIM-9X" }, aim120 = { "AIM-120", "AIM-120" },
  ty90 = { "天燕-90", "TY-90" }, aim92 = { "毒刺（机载）", "Stinger (air)" }, akd10 = { "AKD-10", "AKD-10" }, agm114 = { "地狱火", "Hellfire" },
  kd88 = { "KD-88", "KD-88" }, agm65 = { "小牛", "Maverick" }, ls6 = { "雷石-6", "LS-6" }, gbu12 = { "GBU-12", "GBU-12" }, gbu31 = { "GBU-31", "GBU-31" },
  mk82 = { "Mk 82 炸弹", "Mk 82 bomb" }, b250 = { "250 公斤炸弹", "250 kg bomb" }, hydra = { "九头蛇火箭", "Hydra rockets" }, fl90 = { "90 毫米火箭", "90 mm rockets" },
  pl12 = { "霹雳-12", "PL-12" }, yj91 = { "鹰击-91 反辐射导弹", "YJ-91 anti-radiation missile" }, agm88 = { "AGM-88 哈姆", "AGM-88 HARM" },
  gbu32 = { "GBU-32 联合直接攻击弹药（450 公斤）", "1,000 lb GBU-32 JDAM" }, gbu38 = { "GBU-38 联合直接攻击弹药（230 公斤）", "500 lb GBU-38 JDAM" },
  gbu39 = { "GBU-39 小直径炸弹", "GBU-39 Small Diameter Bomb" }, lt2 = { "雷霆-2 激光制导炸弹", "LT-2 laser-guided bomb" },
}
for k, v in pairs(AW) do add("aw." .. k, v[1], v[2]) end
add("preset.sead", "防空压制", "SEAD")
add("preset.custom", "自定义", "Custom")
add("hangar.empty", "不挂", "Empty")
add("hangar.pick", "点白圈选一个挂点", "Pick a hardpoint")
add("hangar.guide", "导引方式", "Guidance")
add("hangar.range", "射程", "Range")
add("hangar.km", "{1} 公里", "{1} km")
add("hangar.count", "数量", "Quantity")
add("hangar.lock", "锁定时间", "Lock time")
add("hangar.sec", "{1} 秒", "{1} s")
add("hangar.symOn", "左右对称：开", "Symmetric: ON")
add("hangar.symOff", "左右对称：关", "Symmetric: OFF")
add("hangar.back", "返回", "BACK")
add("hangar.save", "保存", "SAVE")
add("preset.sdb", "小直径炸弹", "Small Diameter Bombs")
add("wcat.gun", "航炮", "Cannon")
add("wcat.aam", "空空导弹", "Air-to-Air Missile")
add("wcat.agm", "空地导弹", "Air-to-Ground Missile")
add("wcat.bomb", "炸弹", "Bomb")
add("wcat.gbomb", "制导炸弹", "Guided Bomb")
add("wcat.rkt", "火箭弹", "Rocket Pod")
add("wcat.arm", "反辐射导弹", "Anti-Radiation Missile")
add("guide.ir", "红外", "Infrared")
add("guide.radar", "主动雷达", "Active radar")
add("guide.laser", "激光", "Laser")
add("guide.gps", "卫星 / 惯性", "GPS / INS")
add("guide.tv", "电视 / 红外成像", "TV / imaging IR")
add("guide.arm", "被动雷达（打防空雷达）", "Passive radar (hunts air defenses)")
add("guide.none", "无制导", "Unguided")
add("guide.gun", "—", "—")
add("air.alt", "高度 {1} 米", "Alt {1} m")
add("air.flares", "热诱弹 {1}", "Flares {1}")
add("air.gearState.down", "起落架 放下", "Gear down")
add("air.gearState.up", "起落架 收起", "Gear up")
add("air.noWeapon", "没有武器", "Unarmed")
add("air.passenger", "（乘客）", "(passenger)")
add("air.ab", "加力", "AFTERBURNER")
add("air.missile", "导弹来袭", "MISSILE")
add("air.oob", "返回作战区域", "RETURN TO BATTLE AREA")
add("air.stall", "失速", "STALL")
add("air.pullup", "拉起", "PULL UP")
add("air.locking", "锁定中 {1}%", "LOCKING {1}%")
add("air.locked", "已锁定", "LOCKED")
add("air.notYet", "尚未开战", "Weapons cold")
add("air.needLock", "未锁定", "No lock")
add("air.helpJet", "鼠标 飞行方向 · W/S 油门（推满进加力）· A/D 滚转 · Q/E 方向舵 · 左键 开火 · 1-6 武器 · R 换目标 · X 热诱弹 · G 起落架 · F 跳伞",
  "Mouse steer · W/S throttle (max = afterburner) · A/D roll · Q/E rudder · LMB fire · 1-6 weapons · R target · X flares · G gear · F eject")
add("air.helpHeli", "鼠标 瞄准 · W/S 前后 · A/D 转向 · Q/E 平移 · 空格 / Ctrl 升降 · 左键 开火 · 1-6 武器 · R 换目标 · X 热诱弹 · F 下飞机",
  "Mouse aim · W/S forward/back · A/D turn · Q/E strafe · Space / Ctrl up/down · LMB fire · 1-6 weapons · R target · X flares · F exit")
add("air.helpPass", "你坐在后面 · 鼠标 看四周 · F 下飞机（在天上就跳伞）", "You're a passenger · Mouse look · F jump out (parachute if airborne)")
add("ui.smokeLeft", "烟幕弹 ×{1}", "Smoke ×{1}")
add("ui.reloading", "装填中", "Reloading")
add("ui.speed", "{1} 公里/时", "{1} km/h")
add("ui.range", "{1} 米", "{1} m")
add("sight.day", "昼光", "DAY")
add("sight.nv", "夜视", "NV")
add("sight.whot", "热成像 · 白热", "THERMAL · WHT")
add("sight.bhot", "热成像 · 黑热", "THERMAL · BHT")
add("vw.gun125", "125 毫米炮", "125 mm gun")
add("vw.gun120", "120 毫米炮", "120 mm gun")
add("vw.gun105", "105 毫米炮", "105 mm gun")
add("vw.ac30", "30 毫米机关炮", "30 mm autocannon")
add("vw.ac35", "35 毫米高炮", "35 mm AA gun")
add("vw.vulcan", "20 毫米加特林", "20 mm Gatling")
add("vw.coax", "并列机枪", "Coaxial MG")
add("vw.hmg", "12.7 毫米机枪", "12.7 mm HMG")
add("vw.how155", "155 毫米榴弹炮", "155 mm howitzer")
add("vw.mlrs", "火箭炮", "Rocket launcher")
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
