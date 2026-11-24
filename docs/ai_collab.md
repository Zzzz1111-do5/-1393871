# 几个 AI 会话一起做：怎么传话、怎么分工、互相挑刺

用户 11-24：「其他 AI 跟你一起做，你通过提交的方式跟他互相传递信息配合，也让他知道这一点；同时你俩互相检查、挑刺，力求做到完美」。

我们之间没有别的通道，**只靠 git**：提交说明、这个文件。每个会话：

1. **开工前**先 `git fetch`，把别人的分支合进自己的分支（`git merge origin/<别人的分支>`），读一遍别人的提交说明和这个文件；
   冲突按「谁的做法更完整就用谁的」解决，在下面写一笔。
2. **提交说明写清楚**：改了什么、为什么（引用户原话）、没做完的、想让别人看的地方。
3. **这个文件**：「正在做」写自己手上的事（免得两边做重复）；「挑刺」写看别人代码发现的问题（文件:行、问题、怎么改），
   能顺手改的直接改了再写「已改」，拿不准的留给原作者。

## 会话和分支

| 代号 | 分支 | 在做 |
|---|---|---|
| A | `claude/darksword-forts-navy` | 原车转换工具（blveh.py：Sketchfab 整车 → 游戏格式）、挖内腔（carve.py）、悍马 / JLTV 驾驶室；**接下来：俄系装备、PvE 关卡**（用户 11-24 给 A 的：「没事干了就去找俄系和做关卡，越多越逼真越好」） |
| B | `claude/vibrant-ramanujan-hd84ou` | M1A1 原模型内饰拆块（intsplit.py）、搬进 M1A2 SEPv2 和 M2A3（InteriorAbrams.lua）、火控真功能（Drive.lua） |
| C | `claude/affectionate-pasteur-vj1oop` | 飞机：歼-20 弹舱、战雷式锁定界面 |

飞机「锁定、投弹、操作细节和手感跟战雷一模一样」：用户 11-24 也交给了 A（排在俄系、关卡后面）。C 已经开了头（锁定界面），
**C 在做就 C 接着做，A 负责对照战雷挑刺**；C 一段时间没动静，A 再接手——接手前在这里写一笔。

## 正在做

- A（11-24）：俄系装备找模型（Sketchfab 上 CC-BY / CC0、不是游戏里扒的），按 blveh.py 转；PvE 关卡加多、做真。
  - 已做：T-90M（t90m，mansoorsajidp 带车内的那个；Ballistics 加了俄制 125 弹 gun125r：3BM60 / 3BK31 / 3OF26，弹种加了类别 cls，面板键按这门炮挑同一类——B 改面板时注意 `BAL.panelAmmo`）；BMP-3（bmp3，lampilamp；新武器 gun100：2A70 100 毫米低膛压炮）
  - PvE 关卡 8 → 16 关（Config.Pve 每关加 ai 编成：def / atk 的 max、tank、ids；AIVeh.lua 照它挑车），每关简报 pve.b<n>，关卡页可滚动；测试 tools/mock/pve_ai.lua
  - blveh.py 修了：算转轴前没刷新视图层，matrix_world 是旧的（以前没给 tur 的车，炮塔转轴都算错了）；拆出来的块照原块减面
  - 候选（都查过描述、不是扒的）：BMP-3（lampilamp / scout.）、BTR-82A（cloudhub）、Pantsir-S1（SanderWolf_）、Tor-M2（Chenzoss）、TOS-1A（L_elo）、BMPT（maks_modeller）；飞机 Su-35（mansoorsajidp）、Su-57（andertan）、Ka-52（maddex88）、Mi-28（cloudhub）
- B：（请 B 自己填）

## 工具链的先后（别互相覆盖）

- **M1A1（m1a1i）**：`blveh.py`（Blender 从原文件转）→ `blveh_meta.py`（写 ImportedMeta 那一行）→ `intsplit.py m1a1i write`（B 的：
  把炮塔内饰拆成 15 块、ImportedMeta 加 Int_* 块）。**重跑前两步以后一定要再跑 intsplit**，不然拆好的块和元数据都没了。
- ImportedMeta.lua 文件头写着 mdl2glb.py 生成：现在 mdl2glb 会保留 blveh.json 里那些模型的行、alias、old（A 改的），重跑不会丢 m1a1i。
- EraMeta：`eralayout.py <键>` 可以只重算几型，其余照旧（A 改的）。

## 合并记录

- 11-24 A 合 B（184c035…ea3fe88）：A 自己那版 M1A1 车内（InteriorM1A1.lua：原模型车内整块在原位显示、上面盖屏和键）和 B 的
  InteriorAbrams 重复了——B 的更完整（拆块、炮尾后坐、握把摆、可动旋钮、M1A2 / 布雷德利都能借），**用 B 的**，A 那版和它的测试删了。
  A 原来那版里有、B 已经有的：镜片、ccp / m1stat 页面、数字键盘手动装定距离（B 就是在 A 的提交上接着做的）。

- 11-24 A 合 B（aaf26ae…dca4d36：AirAudio、坦克分层发动机声、M1A2 挖内腔、坦克能换位）：B 的 AirAudio.lua 和 A 的锁定音（d4db3c0，Fly.lua 里拿
  UI 提示音截一段循环）重复了——**用 B 的**（SoundLib 的 1000 赫兹纯音调音高，声音干净，还有失速、拉起、油少、熄火、起落架、命中），A 那段删了；
  tools/mock/hud.lua 的锁定音检查改成查 AirAudio 的声部（模拟器里纯音没载上就跳过）。合并后跑过 hud、bombsight、tankkeys、interior_abrams，都过。
  import_guide 里两边都叫「第几包」，改成「A 第几包」「B 第几包」

## 挑刺

### A 看 B（11-24）

1. **已改** `InteriorAbrams.lua` 炮长目镜镜片：原来 `PT.gps + V(0, 0, -0.07)`、直径 6 厘米——原模型目镜圈中间的孔半径只有 2.6 厘米、深 6 毫米
   （A 在 Object_4 的目镜筒 c76 上量的：孔在 glTF z 0.417～0.423），6 厘米的镜片比孔大、离端面还有 5 毫米，整个凸在外面像个盖子。
   改成直径 5 厘米、放在孔底（`PT.gps + V(0, 0, -0.10)`，k = 0.26），凸面和端面齐平；布雷德利那块一起改。车长延伸目镜那块在光阑后面的筒里，没问题，没动。
2. 请 B 看：`PT.gps` 注释写「目镜的后端」，其实比目镜圈后端面还靠后 3 厘米（z −2.300；目镜圈后端面在 −2.384，护额垫后沿 −2.322）——
   用它算镜片、进镜位置的地方都差这 3 厘米，看看进镜动画（scope）要不要往前挪。
3. 请 B 看：intsplit.py 写回 models/veh/m1a1i.glb，blveh.py 也写这个文件——见上面「工具链的先后」，要不要把 intsplit 并进 blveh 的配置
   （比如 blveh.json 里写 `"post": "intsplit"`），省得别人只跑 blveh 把拆好的块弄丢。

4. 请 B 看（aaf26ae，View.lua 别人的车的发动机声）：`running = lit and dist < 380` 没有回差——车在 380 格上下来回（并排开、绕圈）时每过一次线就
   Destroy / 新建两个 Sound；建议进 360 格才挂、出 400 格才拆。
5. 请 B 看（aaf26ae，Drive.lua）：燃气轮机写死 `d.id == "m1a1" or d.id == "m1a2"`——以后加 T-80（也是燃气轮机）还得改这里；
   建议 VehDefs 加 `turbine = true`、这里认 `d.turbine`。A 加俄系时要是先加了 T-80，A 顺手改，改了在这里写一笔。
6. B 的 AirAudio：A 加了一个声部（③½ 被雷达锁定，读 a.rwrLock / a.rwrFull），别的没动。

### A 看 C（11-24，对照战雷）

C 的锁定界面（345b7f9）方框、型号、距离、红外导引头圈都对上了。还差（C 十个小时没提交，**A 接手做，下面打钩的是做完的**）：

- [x] 驾驶手感：战雷默认是鼠标瞄准（教官）——鼠标给方向、镜头顺着它看、飞机自己追过去；按方向键直接操纵、松开回到鼠标；C 自由看。
  做在 Fly.lua（M 切回用户 11-21 要的纯键盘驾驶），AirHud 画鼠标瞄准小圈（info.maim）；tools/mock/air.lua ⑤¾
- [x] 锁定音：红外导引头看到热源的低频「嗡嗡」、锁上的高频音；雷达锁定的嘀声（Fly.lua 锁定音那段，一个循环的短声音调音高 / 音量；tools/mock/hud.lua 查）
- [x] 被敌机雷达照射 / 锁定的告警：雷达弹锁着敌机，客户端半秒报一次 lockOn，服务器（Air.lua lockOn）看一眼转告被锁那架的飞行员 rwrLock；
  屏幕上「被雷达照射」/「被雷达锁定！」，告警声接在 **B 的 AirAudio.lua**（③½：锁定中一下一下高的「嘀」，锁上两短一停；A 改了 B 的文件，B 看一下）。
  红外弹是被动的不报；地面防空车雷达跟踪还没接（AaFcs.lua，以后做）
- [x] 投弹（照战雷 2026-10 的 CCRP 改版说明、战雷默认键）：F7「轰炸机视角」（Bombsight.lua 画：圆形视场、十字中心 = 落点、竖线上秒刻度、
  高度 / 地速 / 落下时间 / 投弹方式；Fly.lua 管镜头：机腹往下、稳定对着落点，鼠标左右修航向、教官平飞，Z 变焦）；Shift + B 单投 → 双投 → 齐投
  （服务器 Air.lua fireStore 的 n / rip：双投两枚同时、齐投隔 0.08 秒一枚）；Alt + 中键标目标点（兴趣点）：地上红方框（Marks.lua）、屏幕上红方框 +
  歪向要转那边的箭头 + 「几秒后投弹」，落点走到目标点自动投，航向偏太多变灰不投；手动投照旧随时能投。测试 tools/mock/bombsight.lua（炸点离目标点 5.5 格）
  - 没做引信延时：我们的爆炸不伤自己人、不伤自己（Ents.lua damageEnt 同队直接 return），战雷的「突击引信」是防低空投弹炸到自己的，这里没意义
  - F7 原来是性能面板（Perf.lua）：开着挂炸弹的飞机时 F7 归瞄准镜，Ctrl + F7 开性能面板
  - 请 C 看：C 的锁定框（AirHud 的 LockMark）在瞄准镜里跟着 AirHud 一起收起来了（st.bsight 跟 st.eo 一样处理），C 要是想在瞄准镜里也画锁定框告诉我
- C 的锁定框右边写的「接近速度」战雷的目标标记上没有（在雷达屏上）——留着不碍事，C 回来自己定

### B 看 A

（请 B 填：A 的 blveh.py、blveh_meta.py、M1A1 炮塔转轴按座圈中心重新量的（x 0.043、z −0.796，以前 −0.303）、eralayout 只算一部分……）
