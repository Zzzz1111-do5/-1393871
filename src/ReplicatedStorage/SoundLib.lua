-- 全面大战场——真录音（用户 11-21：声音要逼真，「你来处理声音找音源」）
--   都是 Roblox 创作者商店里公开的音频（任何游戏都能直接用，不用自己上传），挑的是认证创作者上传、名字写清楚是什么的：
--   · ProSoundEffects：Roblox 2022 年买下授权、免费给所有游戏用的专业音效库（步枪、爆炸、子弹呼啸、跳弹、金属撞击、音爆）
--   · Red Bear Community（认证群组）：坦克炮车外 / 车内的录音、炮弹和航弹爆炸
--   · 其他认证创作者：坦克发动机、喷气发动机、休伊直升机旋翼、舰船发动机、导弹发射、12.7 毫米机枪
--   Fx.lua 开局预载：哪个载不下来（被删、被设成私有、没网）就退回原来用 Roblox 自带声音叠出来的那个，不会没声音
--   每项：ids 几个录音（每次随机挑一个）、vol 音量、s 播放速度范围、loop 循环（true 整段循环；{ 起, 止 } 只循环这一段）、len 大概多长（秒）、src 出处
return {
	-- 坦克炮：车外听（别人开炮、第三人称）和车里听（自己在车内 / 炮长镜里开炮：闷、震）
	tankGun = { ids = { 18221697746, 18245544654 }, vol = 1.8, s = { 0.82, 0.9 }, len = 4,
		src = "Red Bear Community：88mm_cannon_body_EXT_、76mm_Cannon_Body_EXT_01" },
	tankGunIn = { ids = { 18221692752, 18221699254 }, vol = 1.6, s = { 0.82, 0.9 }, len = 4,
		src = "Red Bear Community：88mm_cannon_body_INT_04、88mm_cannon_body_INT" },
	-- 坦克炮分层（用户 11-28 晚「坦克开炮声音 炮弹击中地面的声音和效果没有还原战雷」，Fx.lua tankGunSnd）：上面那条炮声本体以外再叠——
	--   都是 ProSoundEffects（描述按 economy 接口查过）；reg：每条录音截哪一段（秒，下载 Ogg 按包络、频谱挑的：起爆前一点点到下一个声音之前）
	--   炸裂 gunCrack：迫击炮爆炸——开头 50 毫秒一下尖的（1.6～4 千赫），紧跟一记很沉的低频（四五十赫兹，0.4～0.8 秒散完），当炮口那一下
	--     （Mortar Explosion 4 后面又炸一下、6 跟 5 是同一条，不用）
	gunCrack = { ids = { 9116973350, 9116973348, 9116973611, 9116973607 }, vol = 1.5, s = { 0.86, 0.94 }, len = 1.2,
		src = "ProSoundEffects：Mortar Explosion 1、2、3、5" },
	--   低频冲击 gunSub：压力波那一记「咚」——Big Low-End Impacts 4（0.2 秒起爆、三四十赫兹、两秒散完）、Deep Hits Big Reverberant Booms（开头那一记）
	gunSub = { ids = { 9113436063, 9125484367 }, vol = 1.2, s = { 0.96, 1.02 }, len = 2.2,
		reg = { [9113436063] = { 0.17, 2.3 }, [9125484367] = { 0, 1.6 } },
		src = "ProSoundEffects：Big Low-End Impacts 4、Deep Hits Big Reverberant Booms Rumbling Tail" },
	--   回声 gunTail：炮声撞到山、楼上滚回来的一长串低沉轰隆——Thunder Distant Boom Thud Rapid Hits 13（0.5～3 秒、八九十赫兹）、
	--     Thunder Cracks Big Rumbling Blasts Booming 2（0.25 秒起、一秒以后剩低沉的滚动）
	gunTail = { ids = { 9120017668, 9120016021 }, vol = 1.3, s = { 0.92, 1.04 }, len = 3.4,
		reg = { [9120017668] = { 0.4, 3.6 }, [9120016021] = { 0.2, 3.8 } },
		src = "ProSoundEffects：Thunder Distant Boom Thud Rapid Hits 13、Thunder Cracks Big Rumbling Blasts Booming 2" },
	--   远处 gunFar：一两公里外听到的一记闷闷的「咚」——Artillery Distant 2 最后那一记（1.25 秒起、七八十赫兹、三秒多散完）、Artillery Distant 3 第一记
	gunFar = { ids = { 9113169432, 9113169435 }, vol = 1.8, s = { 0.95, 1.05 }, len = 3.4,
		reg = { [9113169432] = { 1.18, 4.6 }, [9113169435] = { 0.82, 1.36 } },
		src = "ProSoundEffects：Artillery Distant 2、Artillery Distant 3（Deep Booms, Fire and Deep Explosions）" },
	--   车里的炮闩、抛壳 gunMech：自行火炮车里装弹的金属咔嗒（Howitzer Tank 12、9：Interior, Loading Shell, Large Metal Clunks, Springy Ring Off）
	gunMech = { ids = { 9114842503, 9114842256 }, vol = 3, s = { 0.9, 1 }, len = 1.4,
		reg = { [9114842503] = { 0.02, 1.15 }, [9114842256] = { 0, 1.6 } },
		src = "ProSoundEffects：Howitzer Tank 12、Howitzer Tank 9" },
	-- 炮弹打在地上（Fx.lua kineticHit、boomSound）：
	--   dirtHit 穿甲弹、钢针扎进土里：一下脆的「砰」+ 掀起来的土噼里啪啦落下（Dirt Explosion：Sharp Bang, Fallout；短的这三条）
	dirtHit = { ids = { 9114086657, 9114086949, 9114086583 }, vol = 1.4, s = { 0.98, 1.1 }, len = 1.9,
		src = "ProSoundEffects：Dirt Explosion 1、1、4（Sharp Bang, Blast, Fallout）" },
	--   dirtBlast 榴弹、炸弹炸在土里：爆炸声底下叠一层土被掀起来、砸下来的声音（Dirt Explosion 长的这三条）
	dirtBlast = { ids = { 9114086405, 9114086424, 9114087096 }, vol = 1.3, s = { 0.88, 0.98 }, len = 3.6,
		src = "ProSoundEffects：Dirt Explosion 1、2、3（Sharp Bang, Blast, Fallout）" },
	--   debrisRain 近处炸完半秒，碎土、石子哗啦啦落一地（Debris Rain：Short Gravel and Dirt Falls）
	debrisRain = { ids = { 9114034406, 9114034463, 9114034537 }, vol = 0.9, s = { 0.95, 1.05 }, len = 3.8,
		src = "ProSoundEffects：Debris Rain 1–3（Short Gravel and Dirt Falls）" },
	-- 爆炸：大（航弹、导弹）、中（坦克炮弹、火箭弹）、小（手雷、迫击炮、小口径）
	boomL = { ids = { 18245339193, 9117876720 }, vol = 2, s = { 0.92, 1.02 }, len = 7,
		src = "Red Bear Community：500lb_bomb_explosion_close_03；ProSoundEffects：Power Explosions Big Heavy Searing Boom 1" },
	boomM = { ids = { 18245316227, 9114362266, 9114362264 }, vol = 1.6, s = { 0.95, 1.08 }, len = 6,
		src = "Red Bear Community：Shell_explosion_large_mid_02；ProSoundEffects：Explosions 4、Explosions 5" },
	boomS = { ids = { 9119236749, 9119236757 }, vol = 1.3, s = { 0.95, 1.1 }, len = 3,
		src = "ProSoundEffects：Small Explosion 1、Small Explosion 2" },
	-- 枪
	rifle = { ids = { 9118173739, 9118173999, 9118173988, 9118173992 }, vol = 0.9, s = { 0.96, 1.06 }, len = 3,
		src = "ProSoundEffects：Rifle Single Shots 1–4" },
	hmg = { ids = { 90006135469253, 133704528245805 }, vol = 1, s = { 0.95, 1.05 }, len = 2.5,
		src = "Obamacaremathlab：50 Caliber heavy machine gun fire once (2)、50 Caliber HMG fire once sound effect (3)" },
	-- 车上的机枪、机关炮（用户 11-28「机枪机炮的音效不太好听」，照战雷；Fx.lua G.gunSnd）：
	--   并列机枪（7.62）：M4A1 的整段连发录音（描述写着「Crack of Automatic Fire……Bigger Low End」的两条，录音里约 740 / 757 发 / 分）——
	--   按住时循环其中整数发的那一段（cut.loop：起止都在两发之间的过零点，接缝不响），松开放最后一发起到回声完（cut.tail 起、cut.len 止）；
	--   rpm 录音里的射速（按这挺枪的射速微调播放速度）。分析：下载 Ogg、按包络找每发的起点、自相关定射速、48 kHz 上对过零点
	mg762 = { ids = { 9113185032, 9113183802 }, vol = 1, s = { 1, 1 }, len = 5.4,
		rpm = { [9113185032] = 740, [9113183802] = 757 },
		cut = { [9113185032] = { loop = { 0.16081, 0.73119 }, tail = 0.87009, len = 3.69 },
			[9113183802] = { loop = { 0.3622, 1.59109 }, tail = 1.948, len = 5.36 } },
		src = "ProSoundEffects：Assault Rifle 18、Assault Rifle 19（M4A1 Carbine, Crack of Automatic Fire, Series of Bursts, Bigger Low End）" },
	--   大口径机枪、机关炮、慢的航炮：巴雷特 M82 的单发（.50 BMG，和 M2 重机枪同一种 12.7×99 毫米弹；开头一下很冲、0.1 秒后是回声，
	--   30～300 赫兹占一半多）——一发一发按射速放，口径越大放得越慢越低沉；同上面 rifle 那四条
	bmg50 = { ids = { 9118173739, 9118173999, 9118173988, 9118173992 }, vol = 1, s = { 0.98, 1.02 }, len = 3.4,
		src = "ProSoundEffects：Rifle Single Shots 1–4（Barrett M82 .50 Cal, Single Shots）" },
	missile = { ids = { 509177476, 101663861280893 }, vol = 1.3, s = { 0.95, 1.05 }, len = 5,
		src = "ZuluCenturion：SeaRAM missile launch；ii1_z：ATGM Launch (Stugna-P) Missile" },
	-- 子弹从耳边飞过、跳弹、打在金属上、音爆
	whiz = { ids = { 9113634361, 9113634444 }, vol = 0.8, s = { 0.95, 1.1 }, len = 1, src = "ProSoundEffects：Bullet Whiz 1、Bullet Whiz 2" },
	ric = { ids = { 9118168320, 9118168273, 9118168291 }, vol = 0.9, s = { 0.92, 1.08 }, len = 1, src = "ProSoundEffects：Rico Bullet Whiz 1–3" },
	metalHit = { ids = { 9116684733, 9116684830 }, vol = 0.9, s = { 0.9, 1.1 }, len = 1, src = "ProSoundEffects：Metal Impacts 1、Metal Impacts 3" },
	sonic = { ids = { 9119382258, 9119382493 }, vol = 2, s = { 0.95, 1.02 }, len = 6, src = "ProSoundEffects：Sonic Boom 1" },
	-- 近处爆炸以后的耳鸣（Shock.lua）：创作者商店里没有认证创作者的耳鸣，挑了名字写清楚、自带淡出的这一条；载不下来就不响
	earRing = { ids = { 9069161602 }, vol = 0.7, s = { 0.98, 1.02 }, len = 8, src = "Lvaic：Ear Ringing (Fade)" },
	-- 发动机（循环）：自己开的车 / 飞机 / 船，速度和音量跟着转速、油门、负载变
	tankEngine = { ids = { 8213083943 }, vol = 0.9, s = { 1, 1 }, loop = true, len = 7, src = "Tankentwerfer：medium tank engine idle loop" },
	jetEngine = { ids = { 81983731621096 }, vol = 0.8, s = { 1, 1 }, loop = true, len = 3, src = "JunkersJu87B_2Stuk：Jet engine loop" },
	heliRotor = { ids = { 18630771616, 18630809102 }, vol = 0.9, s = { 1, 1 }, loop = true, len = 10,
		src = "ChuckNorrisBR1：Helicopter Bell UH-1H \"Huey\" rotor sound, looped" },
	shipEngine = { ids = { 82255182471237 }, vol = 0.8, s = { 1, 1 }, loop = true, len = 10, src = "iris's workshop：Ship Engine" },
	-- 坦克发动机分层（用户 11-24：「坦克的发动机声音、加速声音」做成战雷那样）：同一个作者的一套——怠速循环（上面的 tankEngine）、
	--   行驶循环、加速、起动、熄火；Drive.lua 按转速、负载交叉淡入淡出，起步 / 猛踩油门叠一声加速
	tankDrive = { ids = { 8213082259 }, vol = 0.9, s = { 1, 1 }, loop = true, len = 29, src = "Tankentwerfer：medium tank engine driving loop" },
	tankAccel = { ids = { 8213068475 }, vol = 1, s = { 0.96, 1.04 }, len = 3, src = "Tankentwerfer：medium tank engine accelerate" },
	tankStart = { ids = { 8213060841 }, vol = 1, s = { 1, 1 }, len = 4, src = "Tankentwerfer：medium tank engine start up" },
	tankStop = { ids = { 8213085433 }, vol = 1, s = { 1, 1 }, len = 2, src = "Tankentwerfer：medium tank engine shut off" },
	tankTracks = { ids = { 135855037438124 }, vol = 0.8, s = { 1, 1 }, loop = true, len = 3, src = "JunkersJu87B_2Stuka：Tank tracks moving sound [LOOP]" },
	-- 纯音（1000 赫兹，5 秒，循环）：飞机的导引头声、告警音（AirAudio.lua）、M1 燃气轮机的尖啸（Drive.lua）按 PlaybackSpeed 调音高（1 = 1000 赫兹）
	toneSine = { ids = { 87992832353391 }, vol = 1, s = { 1, 1 }, loop = true, len = 5, src = "dragonballz_1995：sine_1000hz" },
	toneSquare = { ids = { 95787800165497 }, vol = 1, s = { 1, 1 }, loop = true, len = 5, src = "dragonballz_1995：square_no_alias_1000hz" },
	toneSaw = { ids = { 122140586645742 }, vol = 1, s = { 1, 1 }, loop = true, len = 5, src = "dragonballz_1995：sawtooth_1000hz" },
}
