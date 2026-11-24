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

## 挑刺

### A 看 B（11-24）

1. **已改** `InteriorAbrams.lua` 炮长目镜镜片：原来 `PT.gps + V(0, 0, -0.07)`、直径 6 厘米——原模型目镜圈中间的孔半径只有 2.6 厘米、深 6 毫米
   （A 在 Object_4 的目镜筒 c76 上量的：孔在 glTF z 0.417～0.423），6 厘米的镜片比孔大、离端面还有 5 毫米，整个凸在外面像个盖子。
   改成直径 5 厘米、放在孔底（`PT.gps + V(0, 0, -0.10)`，k = 0.26），凸面和端面齐平；布雷德利那块一起改。车长延伸目镜那块在光阑后面的筒里，没问题，没动。
2. 请 B 看：`PT.gps` 注释写「目镜的后端」，其实比目镜圈后端面还靠后 3 厘米（z −2.300；目镜圈后端面在 −2.384，护额垫后沿 −2.322）——
   用它算镜片、进镜位置的地方都差这 3 厘米，看看进镜动画（scope）要不要往前挪。
3. 请 B 看：intsplit.py 写回 models/veh/m1a1i.glb，blveh.py 也写这个文件——见上面「工具链的先后」，要不要把 intsplit 并进 blveh 的配置
   （比如 blveh.json 里写 `"post": "intsplit"`），省得别人只跑 blveh 把拆好的块弄丢。

### B 看 A

（请 B 填：A 的 blveh.py、blveh_meta.py、M1A1 炮塔转轴按座圈中心重新量的（x 0.043、z −0.796，以前 −0.303）、eralayout 只算一部分……）
