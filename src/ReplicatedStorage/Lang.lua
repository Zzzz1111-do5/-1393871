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
-- 选阵营（解放军 = 进攻方、美军 = 防守方）
add("faction.title", "选择阵营", "CHOOSE YOUR SIDE")
add("faction.sub", "夜战 · 群岛登陆", "NIGHT OPS · ARCHIPELAGO ASSAULT")
add("faction.atk.en", "PEOPLE'S LIBERATION ARMY", "PEOPLE'S LIBERATION ARMY")
add("faction.def.en", "UNITED STATES ARMED FORCES", "UNITED STATES ARMED FORCES")
add("faction.atk.name", "中国人民解放军", "PLA")
add("faction.def.name", "美国军队", "U.S. Forces")
add("faction.atk.role", "进攻  ·  两栖登陆", "ATTACK  ·  AMPHIBIOUS ASSAULT")
add("faction.def.role", "防守  ·  岛屿防御", "DEFEND  ·  ISLAND DEFENSE")
add("faction.atk.desc", "从海上登陆，拿下岛上全部 5 个据点；每拿下一个，时间延长 3 分钟。", "Land from the sea and take all 5 objectives. Each capture adds 3 minutes.")
add("faction.def.desc", "守住岛上的据点：时间结束时手里还有任意一个就赢。", "Hold the island. Keep any one objective when time runs out to win.")
add("faction.players", "{1} 名玩家", "{1} PLAYERS")
add("faction.join", "加入", "JOIN")
add("faction.stay", "继续", "CONTINUE")
add("faction.full", "人数已满", "TEAM FULL")
add("faction.round", "第 {1} 局", "ROUND {1}")
add("ui.teamFull", "这一边人数已满", "That side is full")
add("ui.switchSide", "换阵营", "Switch side")

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
add("spawn.fleet", "两栖攻击舰", "Assault ship")
add("spawn.cv", "航母甲板", "Carrier deck")
add("spawn.barge", "登陆平台", "Landing platform")
add("spawn.af2", "攻方机场岛", "Island airbase")
add("pad.spawn", "生成", "Spawn")
add("pad.ready", "在场 {1}/{2}", "Deployed {1}/{2}")
add("pad.full", "已满 {1}/{2}", "Full {1}/{2}")
add("pad.cd", "冷却 {1} 秒", "Ready in {1}s")
add("pad.needD", "机场失守", "Airfield lost")
add("ui.padLocked", "这个生成点现在用不了", "This spawn point is unavailable")
add("ui.padBusy", "生成点上还停着一辆", "The spawn spot is occupied")
add("ui.vehCdMsg", "这一类还要等 {1} 秒", "Available in {1}s")
add("ui.reserved", "这辆是别人刚生成的", "Reserved for the player who spawned it")
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
add("ui.nextRound", "{1} 秒后开下一局", "Next round in {1}s")   -- 开新一局不打乱分队（各自留在选的阵营）
add("ui.roundOver", "本局结束", "ROUND OVER")
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
add("ui.needPick", "先选一个生成点", "Pick a spawn point first")
add("ui.spawnBlocked", "这个出生点现在用不了", "That spawn point is not available right now")
add("ui.help", "WASD 移动 · 左键开火 · 右键开镜 · R 换弹 · 1–4 / 滚轮 切武器 · Q 上一把 · V 第一 / 第三人称 · E 上车 / 操作 · B 战术平板 · N 夜视 · Tab 战况 · M 地图",
  "WASD move · LMB fire · RMB aim · R reload · 1-4 / wheel weapons · Q last weapon · V 1st / 3rd person · E enter / man · B tac-pad · N night vision · Tab scoreboard · M map")
-- 载具
add("ui.vehFull", "这类载具已经满了", "No free slot for this vehicle type")
add("ui.vehLost", "你的载具被击毁了", "Your vehicle was destroyed")
add("ui.vehKilled", "击毁 {1}", "Destroyed {1}")
add("ui.outOfRange", "超出射程", "Out of range")
add("ui.lcac", "气垫艇正把你的车送上滩……", "The hovercraft is bringing your vehicle ashore...")
add("ui.lcacOn", "{1}  ·  甲板上：{2}", "{1}  ·  carrying {2}")
add("ui.lcacHelp", "W/S 油门 · A/D 转向（越快越灵，转弯会甩尾）· 鼠标 转炮塔 · 冲上沙滩自动放下车，接着开下去 · F 下车",
  "W/S throttle · A/D steer (sharper at speed, the stern slides out) · Mouse turret · Run up the beach to unload, then drive off · F exit")
add("ui.vehHelp", "WASD 驾驶 · 鼠标 瞄准 · 左键 开火 · 1/2 换武器 · Shift 瞄准镜 · V 光电模式（昼光 / 夜视 / 热成像）· M 烟幕弹 · F 下车",
  "WASD drive · Mouse aim · LMB fire · 1/2 weapon · Shift gunner sight · V optics (day / NV / thermal) · M smoke · F exit")
-- 坦克瞄准镜里的提示（Drive.lua）：用户——开镜上面写一下，按 V 切换光电模式、按 M 释放烟雾弹
add("drv.hintOptic", "[V] 切换光电模式：{1}", "[V] Optics: {1}")
add("drv.hintSmoke", "[M] 释放烟雾弹（剩 {1} 发）", "[M] Smoke ({1} left)")
add("drv.hintLine", "Shift 退出瞄准镜 · Z / 滚轮 倍率 · 1/2 换武器 · 左键 开火", "Shift leave sight · Z / Wheel zoom · 1/2 weapon · LMB fire")
add("drv.optic", "光电", "OPT")
add("drv.smoke", "烟幕", "SMK")
add("ui.enterVeh", "按 F 上车", "Press F to enter")

-- 舰艇
add("pad.needC", "港口失守", "Port lost")
add("ui.shipRearmed", "靠上码头：导弹补满了，正在修理", "Alongside the pier: missiles reloaded, repairing")
add("ui.boardShip", "上船", "Board")
add("ship.help", "W/S 车钟 · A/D 转舵 · 鼠标 瞄准 · 左键 开火 · 1 舰炮 · 2 反舰导弹 · R 锁定 · 右键 / V 望远镜 · N 夜视 · F 下船",
  "W/S engine order · A/D rudder · Mouse aim · LMB fire · 1 guns · 2 anti-ship missiles · R lock · RMB / V binoculars · N night vision · F leave ship")
local ORD = { [-2] = { "后退二", "Full astern" }, [-1] = { "后退一", "Slow astern" }, [0] = { "停车", "Stop" }, [1] = { "前进一", "Dead slow ahead" },
  [2] = { "前进二", "Slow ahead" }, [3] = { "前进三", "Half ahead" }, [4] = { "前进四", "Full ahead" }, [5] = { "全速前进", "Flank speed" } }
for k, v in pairs(ORD) do add("ship.order." .. k, v[1], v[2]) end
add("ship.kn", "{1} 节", "{1} kn")
add("ship.hdg", "航向 {1}°", "HDG {1}°")
add("ship.left", "左舵 {1}°", "Port {1}°")
add("ship.right", "右舵 {1}°", "Stbd {1}°")
add("ship.mid", "正舵", "Midships")
add("ship.sam", "防空导弹 {1}（自动）", "SAM {1} (auto)")
add("ship.ciws", "近防炮（自动）", "CIWS (auto)")
add("ship.lock", "锁定：{1}", "Locked: {1}")
add("ship.noLock", "没有锁定：打准星下那一点", "No lock: fires at the crosshair")
add("ship.shallow", "水太浅！", "Shallow water!")
add("ship.rest", "停靠补给中……", "Resupplying alongside...")
local SW = {
  g130 = { "130 毫米主炮", "130 mm main gun" }, g127 = { "Mk 45 127 毫米舰炮", "Mk 45 5-inch gun" }, g76 = { "76 毫米舰炮", "76 mm gun" },
  g57 = { "Mk 110 57 毫米舰炮", "Mk 110 57 mm gun" }, g30 = { "30 毫米加特林", "30 mm Gatling" }, m2x2 = { "双联 12.7 毫米机枪", "Twin .50 cal" },
  yj18 = { "鹰击-18 反舰导弹", "YJ-18 anti-ship missiles" }, yj83 = { "鹰击-83 反舰导弹", "YJ-83 anti-ship missiles" },
  tlam = { "战斧（海上打击型）", "Tomahawk Maritime Strike" }, harpoon = { "鱼叉反舰导弹", "Harpoon anti-ship missiles" }, nsm = { "NSM 海军打击导弹", "Naval Strike Missiles" },
}
for k, v in pairs(SW) do add("sw." .. k, v[1], v[2]) end

-- 飞机、直升机
add("ui.rearmed", "加好了油，补满了弹药和热诱弹", "Refueled, rearmed and resupplied with flares")
local PRESET = {
  aa = { "空战", "Air superiority" }, ag = { "对地", "Ground attack" }, beast = { "满挂", "Full load" }, at = { "反坦克", "Anti-tank" },
  mix = { "混合", "Mixed" }, rkt = { "火箭", "Rockets" }, none = { "空载", "Unarmed" }, dap = { "火力型", "Gunship" }, strike = { "轰炸", "Strike" },
  bomb = { "炸弹", "Bombs" }, kd88 = { "KD-88 远程打击", "KD-88 standoff" }, cas = { "近距支援", "Close air support" }, hk = { "猎杀", "Hunter-killer" },
  jdam = { "联合直接攻击弹药", "JDAM" }, mk82 = { "Mk 82 炸弹", "Mk 82 bombs" }, antiship = { "反舰", "Anti-ship" },
}
for k, v in pairs(PRESET) do add("preset." .. k, v[1], v[2]) end
local AW = {
  gsh30 = { "30 毫米航炮", "30 mm cannon" }, m61 = { "20 毫米航炮", "20 mm cannon" }, gau22 = { "25 毫米航炮", "25 mm cannon" }, gau8 = { "GAU-8 30 毫米机炮", "GAU-8 30 mm" },
  m230 = { "30 毫米链式炮", "30 mm chain gun" }, zh23 = { "23 毫米炮", "23 mm turret" }, m134 = { "舱门机枪", "Door gun" },
  pl10 = { "霹雳-10", "PL-10" }, pl15 = { "霹雳-15", "PL-15" }, aim9x = { "AIM-9X", "AIM-9X" }, aim120 = { "AIM-120", "AIM-120" },
  ty90 = { "天燕-90", "TY-90" }, aim92 = { "毒刺（机载）", "Stinger (air)" }, akd10 = { "AKD-10", "AKD-10" }, agm114 = { "地狱火", "Hellfire" },
  kd88 = { "KD-88", "KD-88" }, agm65 = { "小牛", "Maverick" }, ls6 = { "雷石-6", "LS-6" }, gbu12 = { "GBU-12", "GBU-12" }, gbu31 = { "GBU-31", "GBU-31" },
  mk82 = { "Mk 82 炸弹", "Mk 82 bomb" }, b250 = { "250 公斤炸弹", "250 kg bomb" }, hydra = { "九头蛇火箭", "Hydra rockets" }, fl90 = { "90 毫米火箭", "90 mm rockets" },
  pl12 = { "霹雳-12", "PL-12" }, yj91 = { "鹰击-91 反辐射导弹", "YJ-91 anti-radiation missile" }, yj83k = { "鹰击-83K 反舰导弹", "YJ-83K anti-ship missile" }, agm88 = { "AGM-88 哈姆", "AGM-88 HARM" },
  gbu32 = { "GBU-32 联合直接攻击弹药（450 公斤）", "1,000 lb GBU-32 JDAM" }, gbu38 = { "GBU-38 联合直接攻击弹药（230 公斤）", "500 lb GBU-38 JDAM" },
  gbu39 = { "GBU-39 小直径炸弹", "GBU-39 Small Diameter Bomb" }, lt2 = { "雷霆-2 激光制导炸弹", "LT-2 laser-guided bomb" },
}
for k, v in pairs(AW) do add("aw." .. k, v[1], v[2]) end
add("preset.sead", "防空压制", "SEAD")
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
add("air.helpJet", "鼠标 飞行方向 · W/S 油门（推满进加力）· A/D 滚转 · Q/E 方向舵 · 左键 开火 · 1-6 武器 · R 换目标 · P 光电吊舱 · X 热诱弹 · J 抛副油箱 · G 起落架 · F 跳伞",
  "Mouse steer · W/S throttle (max = afterburner) · A/D roll · Q/E rudder · LMB fire · 1-6 weapons · R target · P targeting pod · X flares · J drop tanks · G gear · F eject")
add("air.helpHeli", "鼠标 看哪飞哪（往下看低头往前冲、往上看抬头减速）· E 升 / Q 降 · W/S 前后 · A/D 左右平移 · 左键 开火 · 1-6 武器 · R 换目标 · P 光电 · X 热诱弹 · J 抛油箱 · F 下飞机",
  "Mouse: fly where you look (look down = nose down, go) · E up / Q down · W/S fwd/back · A/D strafe · LMB fire · 1-6 weapons · R target · P EO sight · X flares · J drop tanks · F exit")
-- 飞机平显（Fly.lua）：速度、高度框的标题，右侧武器栏的热诱弹；光电吊舱（P）的画面
add("hud.spd", "速度 km/h", "SPD km/h")
add("hud.alt", "高度 m", "ALT m")
add("air.flareName", "热诱弹", "Flares")
add("eo.title", "光电吊舱", "EO POD")
add("eo.tv", "电视", "TV")
add("eo.whot", "热成像 · 白热", "IR · WHT")
add("eo.bhot", "热成像 · 黑热", "IR · BHT")
add("eo.range", "距离", "RNG")
add("eo.hint", "P 退出光电 · V 电视 / 白热 / 黑热 · Z / 滚轮 变焦 · R 换目标 · 左键 开火（对地弹、炮塔打吊舱看着的地方）· 飞机自动保持平飞",
  "P exit pod · V TV / WHT / BHT · Z / Wheel zoom · R target · LMB fire (AGMs and turret go where the pod looks) · autopilot holds level flight")
-- 油量、副油箱（用户：增加油量这个东西并且可以选择挂载副油箱）
add("air.fuel", "油 {1}%", "FUEL {1}%")
add("air.fuelP", "油 {1}%", "Fuel {1}%")
add("air.bingo", "燃油不足", "BINGO FUEL")
add("air.flameout", "燃油耗尽", "FLAMEOUT")
add("ui.tankEmpty", "副油箱用完，已抛掉", "Drop tanks empty, jettisoned")
add("ui.tankDrop", "抛掉了副油箱", "Drop tanks jettisoned")
add("aw.tk800", "800 升副油箱", "800 L drop tank")
add("aw.tk370", "370 加仑副油箱", "370 gal drop tank")
add("aw.tkh", "外挂油箱", "External fuel tank")
add("aw.tk230", "230 加仑外挂油箱", "230 gal external tank")
add("wcat.tank", "副油箱", "Drop Tank")
add("hangar.fuel", "内油", "INTERNAL FUEL")
add("hangar.endur", "巡航约 {1} 分钟", "About {1} min cruise")
add("hangar.endurTank", "（副油箱 +{1} 分钟）", "(tanks +{1} min)")
add("hangar.weight", "重量 {1}（比一半内油、不挂副油箱）", "Weight {1} (vs. half fuel, no tanks)")
add("hangar.tankFuel", "加油", "Fuel")
add("hangar.tankDrag", "最大速度", "Top speed")
add("hangar.tankMin", "多飞", "Extra endurance")
add("hangar.min", "{1} 分钟", "{1} min")
add("hangar.tankAdd", "+{1}% 油", "+{1}% fuel")
-- 飞机召唤位（用户：地图改为召唤飞机的地方，我可以选择哪种飞机）
add("pad.summon", "选择机型", "Choose aircraft")
add("pad.summonJet", "召唤飞机", "Aircraft Terminal")
add("pad.summonHeli", "召唤直升机", "Helicopter Terminal")
add("pick.sub", "选一型飞机，再改挂载和油量", "Pick an aircraft, then set its loadout and fuel")
add("pick.cancel", "取消", "CANCEL")
add("pick.carrier", "舰载", "Carrier")
add("pick.stealth", "隐身", "Stealth")
add("pick.gun", "航炮", "Gun")
add("pick.st", "{1} 个挂点", "{1} hardpoints")
add("pick.fuel", "巡航 {1} 分钟", "{1} min cruise")
add("arole.fighter", "战斗机", "Fighter")
add("arole.strike", "战斗轰炸机", "Strike fighter")
add("arole.attack", "攻击机", "Attack aircraft")
add("arole.bomber", "轰炸机", "Bomber")
add("arole.uav", "察打无人机", "Armed drone")
add("arole.aheli", "武装直升机", "Attack helicopter")
add("arole.uheli", "通用直升机", "Utility helicopter")
add("arole.theli", "运输直升机", "Transport helicopter")
add("air.helpPass", "你坐在后面 · 鼠标 看四周 · F 下飞机（在天上就跳伞）", "You're a passenger · Mouse look · F jump out (parachute if airborne)")
add("ui.smokeLeft", "烟幕弹 ×{1}", "Smoke ×{1}")
add("ui.reloading", "装填中", "Reloading")
add("ui.speed", "{1} 公里/时", "{1} km/h")
add("ui.range", "{1} 米", "{1} m")
-- 部署界面（UI.lua）：不选兵种，底下装备栏改枪械配置，再选生成点
add("deploy.tab.kit", "装备", "LOADOUT")
add("deploy.tab.spawn", "生成点", "SPAWN")
add("deploy.pickSpawn", "选择生成点", "SELECT SPAWN")
add("deploy.enter", "回车", "ENTER")
add("deploy.slot.primary", "主武器", "PRIMARY")
add("deploy.slot.launcher", "发射器", "LAUNCHER")
add("deploy.slot.gadget", "装备", "GADGET")
add("deploy.slot.throw", "投掷", "THROWABLE")
add("deploy.choose", "选择{1}", "SELECT {1}")
add("deploy.none", "不带", "NONE")
add("deploy.noneDesc", "不带发射器，跑得快一点", "Travel light: move a little faster")
add("deploy.current", "已装备", "EQUIPPED")
add("deploy.stat.dmg", "伤害", "DAMAGE")
add("deploy.stat.rate", "射速", "FIRE RATE")
add("deploy.stat.range", "射程", "RANGE")
add("deploy.stat.acc", "精度", "ACCURACY")
add("deploy.stat.blast", "杀伤半径", "BLAST")
add("deploy.stat.ammo", "弹药", "AMMO")
add("deploy.rpm", "{1} 发/分", "{1} RPM")
add("deploy.m", "{1} 米", "{1} m")
add("deploy.kitLine", "装备：{1}", "Loadout: {1}")
add("deploy.editKit", "改装备", "EDIT LOADOUT")
add("deploy.blocked", "不可用", "UNAVAILABLE")
add("deploy.ready", "可以出击", "READY")
add("gear.m4.desc", "全自动卡宾枪，近中距离都好用", "Full-auto carbine for close to medium range")
add("gear.sniper.desc", "远距离一枪一个，爆头双倍", "Long-range precision; headshots deal double")
add("gear.rpg.desc", "打坦克、装甲车、碉堡", "For tanks, armor and bunkers")
add("gear.manpads.desc", "锁定直升机、飞机后发射", "Lock on to helicopters and jets, then fire")
add("gear.mortar.desc", "点准星下的地面，炮弹几秒后落下", "Aim at the ground; shells land a few seconds later")
add("gear.medkit.desc", "给身边的队友回血", "Heals teammates around you")
add("gear.repair.desc", "修车、修工事", "Repairs vehicles and fortifications")
add("gear.breach.desc", "探雷、排雷、剪铁丝网", "Detects and clears mines, cuts wire")
add("gear.binoc.desc", "标记敌人给全队看，呼叫炮火覆盖", "Spots enemies for the team and calls in artillery")
add("gear.grenade.desc", "投掷后几秒爆炸", "Explodes a few seconds after the throw")
add("gear.c4.desc", "放下，再用一次引爆", "Place it, use again to detonate")
-- 主菜单（Menu.lua）
add("menu.rankLine", "{1}   ·   下一级 {2}", "{1}   ·   NEXT {2}")
add("menu.maxRank", "{1}   ·   最高军衔", "{1}   ·   MAX RANK")
add("menu.xp", "{1} / {2} 经验", "{1} / {2} XP")
add("menu.c1.cat", "多人游戏", "MULTIPLAYER")
add("menu.c1.title", "进入战斗", "PLAY")
add("menu.c1.sub", "群岛登陆 · 攻防战", "ARCHIPELAGO ASSAULT")
add("menu.c1.tag", "快速加入", "QUICK JOIN")
add("menu.c1.subtag", "{1} 名玩家在线", "{1} ONLINE")
add("menu.c2.cat", "阵营", "FACTION")
add("menu.c2.title", "选择阵营", "CHOOSE SIDE")
add("menu.c2.sub", "中国人民解放军 · 美国军队", "PLA · U.S. FORCES")
add("menu.c2.none", "未选择", "NOT CHOSEN")
add("menu.c3.cat", "操作", "CONTROLS")
add("menu.c3.title", "操作说明", "HOW TO PLAY")
add("menu.c3.sub", "步兵 · 载具 · 飞机 · 直升机", "INFANTRY · VEHICLES · JETS · HELICOPTERS")
add("menu.c4.cat", "制作人员", "CREDITS")
add("menu.c4.title", "模型与授权", "MODELS & LICENSES")
add("menu.c4.sub", "Sketchfab 作者署名（CC-BY）", "SKETCHFAB AUTHORS (CC-BY)")
add("menu.beta", "测试版", "BETA")
add("menu.close", "关闭", "CLOSE")
add("menu.open", "菜单", "MENU")
add("menu.h.inf", "步兵", "INFANTRY")
add("menu.h.veh", "地面载具", "GROUND VEHICLES")
add("menu.h.jet", "固定翼", "JETS")
add("menu.h.heli", "直升机", "HELICOPTERS")
-- 战斗中的界面（Hud.lua）
add("hud.atk", "解放军", "PLA")
add("hud.def", "美军", "U.S.")
add("hud.squad", "{1}小队", "{1} SQUAD")
add("hud.squad.1", "阿尔法", "ALPHA")
add("hud.squad.2", "布拉沃", "BRAVO")
add("hud.squad.3", "查理", "CHARLIE")
add("hud.squad.4", "德尔塔", "DELTA")
add("hud.squad.5", "回声", "ECHO")
add("hud.squad.6", "狐步", "FOXTROT")
add("hud.squad.7", "高尔夫", "GOLF")
add("hud.squad.8", "旅馆", "HOTEL")
add("hud.auto", "自动", "AUTO")
add("hud.semi", "单发", "SEMI")
add("hud.reload", "换弹中", "RELOADING")
add("hud.dead", "阵亡", "KIA")
add("hud.prep", "准备", "PREP")
add("hud.ot", "加时", "OT")
add("hud.mode", "攻防战", "ASSAULT")
add("hud.tip.title", "目标与据点", "OBJECTIVES")
add("hud.tip.page", "{1} / {2}", "{1} / {2}")
add("hud.tip.2", "站进据点的圈里就开始占领，圈里自己人越多越快；圈里有敌人就停住。拿下的据点在上面变成实心。", "Stand inside a point's circle to capture it; more teammates capture faster, enemies inside stop it. Captured points turn solid at the top.")
add("hud.tip.3", "地图上的载具生成点按 E 生成坦克、直升机、飞机和艇，走过去按 E 上车。", "Press E at a vehicle pad to spawn tanks, helicopters, jets and boats; walk up and press E to get in.")
add("hud.tip.4", "阵亡以后在部署界面底下的装备格换枪械和装备。按 Tab 看战况。", "After you die, change weapons and gear in the loadout slots at the bottom of the deploy screen. Hold Tab for the scoreboard.")
add("hud.tip.close", "结束", "CLOSE")
add("hud.tip.next", "下一个", "NEXT")
add("hud.key.back", "退格", "BKSP")
add("hud.key.enter", "回车", "ENTER")
add("sight.day", "昼光", "DAY")
add("sight.nv", "夜视", "NV")
add("nvg.hint", "按 N 开启夜视", "Press N for night vision")
add("nvg.hintTouch", "点 NV 开启夜视", "Tap NV for night vision")
-- 无人机战术平板（Tablet.lua）
add("air.helpUav", "鼠标 飞行方向 · W/S 油门 · A/D 滚转 · Q/E 方向舵 · 左键 开火 · 1-6 武器 · R 换目标 · 右键/V 切镜头 · Z 变焦（滚轮细调）· G 起落架 · F 收起平板",
  "Mouse steer · W/S throttle · A/D roll · Q/E rudder · LMB fire · 1-6 weapons · R target · RMB/V camera · Z zoom (wheel fine) · G gear · F put tablet away")
add("ui.uavLost", "无人机被击落，数据链中断", "UAV shot down — link lost")
add("uav.brand", "TAC-UAV · 地面控制终端", "TAC-UAV · GROUND CONTROL")
add("uav.kCam", "镜头", "CAM")
add("uav.kZoom", "变焦", "ZOOM")
add("uav.kNv", "夜视", "NV")
add("uav.kExit", "收起", "EXIT")
add("uav.link", "建立数据链…", "Establishing datalink…")
add("uav.linkName", "数据链", "LINK")
add("uav.sat", "卫通", "SATCOM")
add("uav.los", "视距", "LOS")
add("uav.rec", "录像", "REC")
add("uav.bat", "电量 {1}%", "BAT {1}%")
add("uav.nose", "前视光电", "EO NOSE")
add("uav.chase", "外部视角", "EXTERNAL")
add("uav.alt", "高度  {1} m", "ALT  {1} m")
add("uav.spd", "速度  {1} km/h", "SPD  {1} km/h")
add("uav.vs", "升降  {1} m/s", "V/S  {1} m/s")
add("uav.dist", "距操作员 {1} km", "RANGE {1} km")
add("uav.flr", "诱饵弹 ×{1}", "FLARES ×{1}")
add("uav.aim", "瞄准点 {1} km", "SPI {1} km")
-- 单兵战术平板（TacPad.lua / Tactical.lua）：呼叫空投载具、空中打击，每样一局有次数
add("tac.title", "战术平板 · 呼叫支援", "TAC-PAD · FIRE SUPPORT")
add("tac.brand", "TAC-PAD · 单兵终端", "TAC-PAD · SOLDIER TERMINAL")
add("tac.vdrop", "空投载具", "Vehicle Airdrop")
add("tac.vdrop.desc", "运输直升机吊运一辆车，挂伞投到目标点，落地就能开", "A helicopter drops a vehicle under canopy — ready to drive on landing")
add("tac.supply", "空投补给", "Supply Drop")
add("tac.supply.desc", "补给箱：附近队友补满弹药、慢慢回血", "Crate refills ammo and slowly heals nearby squadmates")
add("tac.pgm", "精确打击", "Precision Strike")
add("tac.pgm.desc", "战斗机投一枚激光制导炸弹，打单个目标", "A fighter drops one laser-guided bomb on a single target")
add("tac.gunrun", "机炮扫射", "Strafing Run")
add("tac.gunrun.desc", "攻击机顺着你看的方向扫射一条线", "Attack jet strafes a line along your bearing")
add("tac.cluster", "集束轰炸", "Carpet Bombing")
add("tac.cluster.desc", "轰炸机沿方向投一串炸弹，覆盖一大片", "Bomber lays a string of bombs across a wide strip")
add("tac.left", "剩 {1} 次", "{1} LEFT")
add("tac.out", "用完了", "EXPENDED")
add("tac.cdShort", "冷却 {1}", "CD {1}")
add("tac.ready", "就绪", "READY")
add("tac.eta", "到达 {1} 秒", "ETA {1} s")
add("tac.limit", "这一局 {1} 次 · 冷却 {2} 秒", "{1} per round · {2} s cooldown")
add("tac.pick", "在地图上点选目标", "Click the map to mark a target")
add("tac.call", "呼叫", "CALL IN")
add("tac.callNow", "确认呼叫 · Enter", "CONFIRM · ENTER")
add("tac.close", "收起 · B", "CLOSE · B")
add("tac.closeTouch", "收起", "CLOSE")
add("tac.target", "目标 {1} 米 · 方位 {2}°", "TGT {1} m · BRG {2}°")
add("tac.range", "呼叫范围 {1} 米", "RANGE {1} m")
add("tac.zoom", "滚轮缩放 · 左键选点 · 右键拖动", "Wheel zoom · LMB mark · RMB pan")
add("tac.zoomTouch", "点地图选目标", "Tap the map to mark")
add("tac.sent", "已呼叫 · {1} 秒后到达", "Called in · {1} s out")
add("tac.danger", "离你很近，注意隐蔽", "Danger close — take cover")
add("tac.notYet", "开战以后才能呼叫支援", "Support is available once the battle starts")
add("tac.none", "这一样这一局已经用完了", "That support is used up this round")
add("tac.cd", "还在冷却，{1} 秒后才能再叫", "Still cooling down — {1} s")
add("tac.teamBusy", "队友刚叫过，{1} 秒后再试", "A squadmate just called it — {1} s")
add("tac.far", "太远了，只能叫 {1} 米以内", "Too far — max {1} m")
add("tac.water", "空投只能落在陆地上", "Airdrops must land on solid ground")
add("tac.vmax", "全队空投的车已经有 {1} 辆了", "Your team already has {1} airdropped vehicles")
add("tac.called", "{1} 呼叫了{2}，{3} 秒后到达", "{1} called in {2} — {3} s out")
add("tac.key", "平板", "PAD")
add("tac.kSel", "选择", "SELECT")
add("tac.kCall", "呼叫", "CALL")
add("tac.kClose", "收起", "CLOSE")
add("uav.weak", "信号弱", "WEAK SIGNAL")
add("uav.hit", "操作员遭到攻击！", "OPERATOR UNDER FIRE!")
add("uav.relink", "按 T 重新连接无人机（{1}）", "Press T to reconnect UAV ({1})")
add("uav.relinkAir", "按 T 重新连接无人机（{1} · 自动盘旋 {2} 秒）", "Press T to reconnect UAV ({1} · loitering {2}s)")
add("uav.relinkTouch", "点这里重新连接无人机（{1}）", "Tap to reconnect UAV ({1})")
add("uav.relinkTouchAir", "点这里重新连接无人机（{1} · 自动盘旋 {2} 秒）", "Tap to reconnect UAV ({1} · loitering {2}s)")
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

-- 方位（望远镜的读数；北是地图的 −Z）
add("dir.0", "北", "N")
add("dir.1", "东北", "NE")
add("dir.2", "东", "E")
add("dir.3", "东南", "SE")
add("dir.4", "南", "S")
add("dir.5", "西南", "SW")
add("dir.6", "西", "W")
add("dir.7", "西北", "NW")

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
