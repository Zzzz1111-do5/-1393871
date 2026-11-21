# 飞机座舱资料（用户 11-21：飞机显示屏不够还原，「你去网上找每一个型号的飞机的内饰的各种细节」）

2026-11-21 上网查的（session_01LjuH3fMZAmBoHts4cMHdAX）。这台机器只能用搜索、打不开网页正文（观察者网、sldinfo、oocities、howstuffworks 的域名都被环境的网络策略拦了），
下面全是搜索结果里能确认的；查不到的写「没查到」，游戏里照旧或按同类飞机推，不编。改到的代码：`InteriorDefs.lua`（座舱布局）、`InteriorScreens.lua`（屏幕页面）。

## 战斗机

### 歼-20
- 主显示器：一块大尺寸彩色液晶**触摸屏**，约 24 × 9 英寸（610 × 230 毫米），双背光冗余。
- 另有**三块小的辅助显示屏**；**广角全息平显**；手不离杆（HOTAS）。
- 早年还有「两块液晶 + 平显」「F-35 那样一整块」的猜测，现在多数资料是「一大三小」。
- 来源：[Airforce Technology](https://www.airforce-technology.com/projects/chengdu-j20/)、[weaponspecs](https://www.weaponspecs.com/systems/avic/j-20/)、[military-history.fandom](https://military-history.fandom.com/wiki/Chengdu_J-20)、[Airplane Update](https://www.airplaneupdate.com/2019/09/chengdu-j-20.html)
- 游戏：主屏 0.61 × 0.23 米触摸屏（菜单条画在玻璃上，不是凸出来的键）；三块小屏在遮光罩下面一排（左通信导航、中备份姿态、右告警油量）；平显组合玻璃加宽。三块小屏的具体位置没查到，按常见布局摆。

### 歼-35（歼-35A）
- 沈飞宣传视频里量产型的座舱模拟器：**整体式大屏幕（「大横屏」）+ 侧杆操纵**；标题说「支持多点触控」，正文没证实。
- 来源：[观察者网「歼-35A战斗机座舱『大横屏』首次曝光」](https://user.guancha.cn/main/content?id=1601350)
- 游戏：整块触摸大屏 + 侧杆（原来就是）；平显照旧（没查到有没有）。

### 歼-50
- 没查到任何座舱资料。游戏照歼-35 的整块触摸大屏 + 侧杆。

### 歼-16
- 2018 年央视画面：前舱**「一平二下」——上方一台平显，下方两台大尺寸多功能显示器**；正前方控制板（UFC）的显示面积比歼-11 系列大。
- 后舱：没查到歼-16 自己的；它的前身苏-30MKK 后座是**两块大显示器上下叠着**（每块约 15.8 × 21.1 厘米，6.2 × 8.3 英寸）。
- 前舱专注操纵和战术决策，后舱管武器系统（沈阳所工程师）。
- 来源：[新浪军事 2018-06-04「歼16座舱曝光 采用双大屏显示器」](https://mil.news.sina.com.cn/jssd/2018-06-04/doc-ihcmurvh3343687.shtml)、[搜狐「歼16战斗机座舱首次曝光」](https://www.sohu.com/a/226047267_335714)、[环球网](https://mil.huanqiu.com/article/4NUj666bflU)、[Su-30MKK（fandom）](https://military-history.fandom.com/wiki/Sukhoi_Su-30MKK)
- 游戏：前舱两块竖着的大屏并排 + 上面一条液晶 UFC + 平显、中央杆；后舱歼-16 自己的布局没查到，照旧两块方屏并排（没照苏-30MKK 改成上下叠着）。

### 歼-15T
- 座舱照片几乎没有公开。观察者网转载的分析：歼-16、歼-15T 下方原来的几块多功能显示器换成了**一整块大屏（有的大屏其实是两块拼起来的）**；**歼-15T 的 UFC 从发光二极管点阵改成液晶屏，还能兼作专用显示器，显示航姿等关键飞参**。
- 来源：[观察者网（搜索摘要）](https://user.guancha.cn/main/content?id=1601350)、[War Thunder 论坛歼-15T 讨论（只当旁证）](https://forum.warthunder.com/t/15t/311322/101)
- 游戏：两块拼起来的一整块大屏（中间一道缝）+ 液晶 UFC（小姿态球、速度、高度、航向）+ 平显、中央杆。

### F-35
- **全景座舱显示器（PCD）20 × 8 英寸**，由**两块 10 × 8 英寸**拼成（各 1280 × 1024 像素），电子上分成两半互为备份；触摸屏。
- 显示区可以按需要分成最多 12 个窗口，大的叫「门户」（portal），**一共 4 个门户**（或「4 个门户 + 6 个副窗口」）；照片里**左边那个门户是大号战术态势显示（TSD）**。
- **没有平显**（头盔显示器 Gen III）；**备份飞行显示器**（SFD，480 × 480 像素）独立显示姿态、高度、空速、升降速度、迎角——它在哪没查到（游戏放在全景屏上方正中）。
- Block 4 换新的全景屏，外形尺寸一样。
- 来源：[Military & Aerospace Electronics](https://www.militaryaerospace.com/home/article/16724144/panoramic-display-avionics-in-f-35-joint-strike-fighter-ignites-industry-debate-on-the-size-of-cockpit-screens)、[SLDinfo「The F-35 Cockpit」](https://sldinfo.com/2012/04/the-f-35-cockpit-enabling-the-pilot-as-a-tactical-decision-maker/)、[Lockheed Martin 换新显示器](https://www.militaryaerospace.com/sensors/article/14276510/panoramic-display-f-35-cockpit-avionics)、[Driven Technologies（模拟器 SFD）](https://www.driven-technologies.com/portfolio-2-1/project-one-j6axm-fwwcg-gj2r2-b4k8y-z3954)、[PPRuNe（训练资料引文）](https://www.pprune.org/military-aviation/654847-usmc-f-35b-crash-17-sep-23-a-7.html)
- 游戏：两块 10 × 8 英寸拼成一整条（中间一道缝），左半是大号 TSD，右半两个门户（燃油 / 外挂），每半上面一条触摸菜单；上方正中一块方的备份显示器；去掉原来多画的两块「上前显示器」（那是 F-22 的）和三个圆表。

### F-22
- **主多功能显示器 8 × 8 英寸**，在仪表板正中，画空中、地面战术态势的俯视图（威胁身份、优先级、跟踪信息）：**敌机红三角、友机绿圆、不明飞机黄方块、地空导弹五边形**。
- **三块副显示器 6.25 × 6.25 英寸**：两块在主显示器两边，第三块在**飞行员两膝之间**。
- **上前显示器（UFD）**底边有边框键（检查单键），检查单出在**左边那块副显示器**上。
- **综合控制面板（ICP）在仪表板正上方中间**，输入通信、自动驾驶、导航（COM、NAV、STPT、IFF、ALT、HUD、A/P 等页）。平显、右侧杆、左边油门。
- 来源：[HowStuffWorks](https://science.howstuffworks.com/f-22-raptor7.htm)、[F-22 cockpit（oocities）](https://www.oocities.org/southbeach/bay/8200/Cockpit.htm)、[Airforce Technology](https://www.airforce-technology.com/?p=1628)、[Just Flight F-22 手册（ICP 页名）](https://downloads.justflight.com/support/manuals/TMS_F-22A_PremiumEdition_UserManual.pdf)
- 游戏：主显示器 0.203 米方屏画 TSD（照上面的符号和颜色）；两边、膝间三块 0.159 米副显示器（左：外挂 / 检查单，右：发动机燃油，膝间：姿态）；平显下面一块 ICP 键盘，两边各一块上前显示器。

### A-10C
- **两块约 4.9 × 4.9 英寸多功能彩显（MFCD）**，左右各一；平显下面**正前方控制器（UFC）**；控制显示单元（CDU）、辅助航电面板；**中间一列机械飞行仪表：姿态仪（ADI）、升降速度表、空速表、水平状态指示器（HSI）、雷达告警**，发动机 / 液压 / 燃油表一组。左 MFCD 常放 TAD（战术态势），右 MFCD 能调出 CDU 页。
- 来源：[DCS A-10C 手册](https://Digitalcombatsimulator.com/upload/iblock/7aa/DCS%20A-10C%20Flight%20Manual%20EN.pdf)、[DCS 论坛（面板顺序、尺寸）](https://forum.dcs.world/topic/134052-a-10c-cockpit-by-patriot/page/3)、[DCS 论坛（UFC 与 CDU）](https://forum.dcs.world/topic/46373-most-used-control-panel-in-a-10c)
- 游戏：两块 0.124 米 MFCD（左 TAD、右外挂）；中间一列机械表（大姿态仪、HSI、空速、高度、升降速度）；右下发动机表；平显下 UFC 键盘；右侧操纵台上 CDU 小屏。

## 直升机

### 直-10
- 串列双座，两人都有头盔瞄准具（武器跟着头转）；有资料说前座武器操作员、后座驾驶员，也有央视报道说起飞常由前舱飞行员操作——前后分工没查准。
- 仪表有**两种配置：三块彩色液晶多功能显示器，或两块更大的液晶显示器**，两种都有**全息平显**。
- 来源：[Army Recognition](https://www.armyrecognition.com/military-products/air/helicopters/attack-helicopters/wz-10-z-10-caic)、[Military Factory](https://www.militaryfactory.com/aircraft/detail.php?aircraft_id=600)、[环球网（央视报道）](https://mil.huanqiu.com/article/4Omrr7Wf6Xz)
- 游戏：每座两块大屏 + 平显（原来就是，对得上第二种配置）。

### AH-64E
- 每个乘员位**两块 6.25 × 6.25 英寸多用途显示器（MPD）**（彩色和单色视频、彩色符号）、一块**增强型上前显示器（EUFD，系统和应急信息、电台）**、左边一个**键盘单元（KU）**；
  前座射手位中间是 **TADS 电子显示与控制器（TEDAC）：5 × 5 英寸液晶**显示瞄准传感器画面，带两个握把。驾驶员戴 IHADSS 单目头盔显示器。
- 来源：[L3Harris 6.25 × 6.25 MPD](https://www.l3harris.com/all-capabilities/625-x-625-multi-purpose-display-mpd)、[Lockheed Martin TEDAC](https://lockheedmartin.com/en-us/products/tedac.html)、[Defence Connect（KU、EUFD）](https://www.defenceconnect.com.au/industry/18295-crew-station-technology-for-ah-64e-apache-successfully-completes-testing)、[DCS AH-64D 座舱说明](https://www.gamepressure.com/digital-combat-simulator-ah-64d/cockpits-and-controls/z7fa00)
- 游戏：原来每座两块 0.16 米方屏 + 上前显示器（对得上）；射手的 TEDAC 改成 0.127 米方屏。

### UH-60M
- **四块多功能显示器**（柯林斯 MFD-268C4，6 × 8 英寸液晶）横贯仪表板，数字地图、四轴耦合飞行指引、双套 EGI。
- 来源：[Sikorsky UH-60M 手册](https://Lockheedmartin.com/content/dam/lockheed-martin/rms/documents/black-hawk/sikorsky-UH60M-brochure.pdf)、[Military & Aerospace（MFD-268C4）](https://www.militaryaerospace.com/computers/article/55360666/collins-aerospace-rtx-collins-to-upgrade-and-sustain-army-uh-60m-helicopter-glass-cockpit-multifunction-display-avionics)、[Collins MFD-268](https://www.rtx.com/collinsaerospace/what-we-do/industries/military-and-defense/displays-and-controls/airborne/head-down-displays/mfd-268-multi-function-display)
- 游戏：原来就是四块竖着的 6 × 8 英寸（对得上）。

### 直-20
- 玻璃座舱，**至少五块多功能液晶显示器**（直-20J 报道是五块）；机头下面有激光防撞雷达。
- 来源：[Army Recognition（直-20J）](https://armyrecognition.com/news/navy-news/2024/harbins-new-z-20j-shipborne-helicopter-strengthens-anti-submarine-and-patrol-capacities-of-chinese-navy)、[Chinese Military Aviation](http://chinese-military-aviation.blogspot.com/p/helicopters-iii.html)
- 游戏：原来四块横的大屏 + 中间一块小的 = 五块（对得上）。

### CH-47F
- 通用航电架构系统（CAAS）全玻璃座舱：**五块多功能液晶显示器**，飞行、发动机、告警都在上面；独立的控制显示单元（CDU）、数字飞控（DAFCS）、移动地图。
- 来源：[Army Technology](https://army-technology.com/projects/chinook/)、[DCS CH-47F 抢先体验手册](https://www.digitalcombatsimulator.com/upload/iblock/0fd/n8rej5yziyy44qo42m81aluvij05fsk0/DCS%20CH-47F%20Early%20Access%20Guide%20EN.pdf)
- 游戏：原来五块（两座各两块 + 中间发动机），对得上。

## 轰炸机

### 轰-6K
- 玻璃座舱，**六块数字式多功能显示器**（人民日报 2016）／「五块或更多」（简氏 2015）；首个给三到四名机组都配弹射座椅的轰-6；四名机组前后两排。驾驶盘、平显没查到。
- 来源：[GlobalSecurity（人民网转载）](https://www.globalsecurity.org/wmd/library/news/china/2016/china-160603-pdo04.htm)、[Richard Fisher / 简氏（SDF 转载）](https://www.sinodefenceforum.com/goto/post?id=332154)、[新华网「五大改进」](https://www.xinhuanet.com/mil/2016-03/04/c_128772466.htm)
- 游戏：每座三块，共六块（原来另加的中间第七块发动机屏去掉，发动机页放到右座第三块）。

### B-2
- **八块主多功能显示器**（美国空军采购文件：原来是阴极射线管，「显示器现代化」项目全部换新）；左座飞行员、右座任务指挥官；显示器集中在各座前面和中间操纵台。
- 最重要的是**垂直状态显示（VSD，主飞行显示：高度、速度、航向、姿态）**；**水平状态显示（HSD）**画航线、附近敌我飞机、雷达信息，中间一个三角形的飞机符号；CIDS 备份 VSD 和发动机参数。
- **驾驶杆在各座正前方（中央杆），油门各座一套、在各自左手边**（不在中间操纵台）。
- 来源：[美国空军 B-2 简介](https://www.af.mil/About-Us/Fact-Sheets/Display/Article/104482/b-2-spirit/)、[Defense Daily（显示器升级）](https://www.defensedaily.com/air-force-looks-increase-b-2-mission-readiness-cockpit-display-upgrade/air-force/)、[Business Insider（VSD、HSD、CIDS）](https://businessinsider.in/miscellaneous/heres-whats-in-the-cockpit-of-one-of-americas-most-secretive-weapons-the-b-2-stealth-bomber/slidelist/69136992.cms)、[The Aviationist（座舱视频细节）](https://theaviationist.com/2019/04/29/here-are-some-interesting-details-weve-noticed-in-the-first-ever-video-filmed-inside-a-b-2s-cockpit-while-in-flight/)
- 游戏：每座 2 × 2 四块（原来就是八块），左上 VSD、右上 HSD；油门从中间操纵台挪到各座左手边。
