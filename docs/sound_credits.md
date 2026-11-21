# 声音的出处（SoundLib.lua）

用户 11-21：「你来处理声音找音源」。都是 Roblox 创作者商店里公开的音频，任何游戏都能直接用、不用上传；挑的是认证创作者上传、名字写清楚内容的。
游戏开局预载，哪个载不下来（被删、被设成私有）就退回原来用 Roblox 自带声音叠出来的那个，不会没声音。

| 用在哪 | SoundLib 键 | 资源 ID | 出处（创作者：资源名） |
|---|---|---|---|
| 坦克炮（车外） | `tankGun` | 18221697746, 18245544654 | Red Bear Community：88mm_cannon_body_EXT_、76mm_Cannon_Body_EXT_01 |
| 坦克炮（车内 / 炮长镜里） | `tankGunIn` | 18221692752, 18221699254 | Red Bear Community：88mm_cannon_body_INT_04、88mm_cannon_body_INT |
| 大爆炸（航弹、导弹） | `boomL` | 18245339193, 9117876720 | Red Bear Community：500lb_bomb_explosion_close_03；ProSoundEffects：Power Explosions Big Heavy Searing Boom 1 |
| 中爆炸（坦克炮弹、火箭弹） | `boomM` | 18245316227, 9114362266, 9114362264 | Red Bear Community：Shell_explosion_large_mid_02；ProSoundEffects：Explosions 4、Explosions 5 |
| 小爆炸（手雷、迫击炮） | `boomS` | 9119236749, 9119236757 | ProSoundEffects：Small Explosion 1、Small Explosion 2 |
| 步枪（也用在狙击枪、手枪，改速度） | `rifle` | 9118173739, 9118173999, 9118173988, 9118173992 | ProSoundEffects：Rifle Single Shots 1–4 |
| 12.7 毫米机枪（车载机枪） | `hmg` | 90006135469253, 133704528245805 | Obamacaremathlab：50 Caliber heavy machine gun fire once (2)、50 Caliber HMG fire once sound effect (3) |
| 导弹 / 火箭发射 | `missile` | 509177476, 101663861280893 | ZuluCenturion：SeaRAM missile launch；ii1_z：ATGM Launch (Stugna-P) Missile |
| 子弹从耳边飞过 | `whiz` | 9113634361, 9113634444 | ProSoundEffects：Bullet Whiz 1、Bullet Whiz 2 |
| 跳弹 | `ric` | 9118168320, 9118168273, 9118168291 | ProSoundEffects：Rico Bullet Whiz 1–3 |
| 子弹打在金属上 | `metalHit` | 9116684733, 9116684830 | ProSoundEffects：Metal Impacts 1、Metal Impacts 3 |
| 音爆 | `sonic` | 9119382258, 9119382493 | ProSoundEffects：Sonic Boom 1 |
| 坦克发动机（循环） | `tankEngine` | 8213083943 | Tankentwerfer：medium tank engine idle loop |
| 喷气发动机（循环） | `jetEngine` | 81983731621096 | JunkersJu87B_2Stuk：Jet engine loop |
| 直升机旋翼（循环） | `heliRotor` | 18630771616, 18630809102 | ChuckNorrisBR1：Helicopter Bell UH-1H "Huey" rotor sound, looped |
| 舰船发动机（循环） | `shipEngine` | 82255182471237 | iris's workshop：Ship Engine |

ProSoundEffects 是 Roblox 2022 年买下授权、免费给所有游戏用的专业音效库；Red Bear Community 是认证群组。
资源页：`https://create.roblox.com/store/asset/<资源 ID>`。要换哪一个，改 `src/ReplicatedStorage/SoundLib.lua` 里的 ids 就行。
