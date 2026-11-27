-- 坦克观瞄按年代（WtOptics，用户 11-26「不同时期的坦克开镜不一样……以及夜视仪这种观瞄设备」）：
--   python3 tools/mock/run.py tools/mock/optics.lua [shot=<目录>]
--   一型一型坐上去、半夜开镜，看：夜视是哪一种、分划是哪一套、能切哪几个光电通道、默认档、各档的画面（探照灯圈、扫描线、发糊）
--     59 式（1959，东方）   主动红外 + 苏式光学分划（没有数字读数）
--     M60A1（1962，西方）   主动红外 + 北约早期弹道分划
--     T-72A（1979）         微光夜视 + 激光测距分划
--     豹 2A4（1985）        第一代热像（扫描线、发糊）+ 激光测距分划
--     T-90M（2017）         第三代高清热像（不糊）+ 猎歼式数字分划
--   shot=<目录>：每型开镜的界面写成 JSON（tools/mock/hud_render.py 画图）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local SHOT = TEST_ARGS:match("shot=(%S+)")

local G = T.boot()
R.services.Workspace:SetAttribute("DayFix", 0)   -- 半夜：开镜默认用这辆车最好的夜视
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
G.allowInfantry = true   -- 战雷式（Config.Wt.noInfantry）只能从机库出车：这里先当步兵出去，再一型一型坐上测试放的车
T.runUntil(function() return G.worldReady end, 900)
if G.botsClear then G.botsClear() end
local me = T.join("P1", 8301, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
-- 每局开局把钟点拨回早上（Round.lua：清掉 DayFix）：开局以后再钉在半夜
R.services.Workspace:SetAttribute("DayFix", 0)
R.run(0.5)
local P = G.P[me]
P.team = "def"
me.Team = G.TEAM.def
me.Neutral = false
me:SetAttribute("Side", "def")
G.pushOne(P)
R.run(1)
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
T.actAs(me, "deploy", "rifle", "base")   -- 主基地（战雷式出车也在这里出生：WtMatch.lua wtDeployVeh）
T.runUntil(function() return P.alive and P.char ~= nil end, 15)
R.run(1)
check(P.alive, "出生了（阶段 " .. tostring(G.round and G.round.phase) .. "）")
local RS = R.services.ReplicatedStorage
local VD = R.require(RS:FindFirstChild("VehDefs"))
local OPT = R.require(RS:FindFirstChild("WtOptics"))
local Map = G.Map
local Lighting = R.services.Lighting
local MODES = { "day", "nv", "whot", "bhot", "ir" }

local function find(name)
  for _, d in ipairs(me.PlayerGui:GetDescendants()) do
    if d.Name == name then return d end
  end
end
local function shownText(name)
  for _, d in ipairs(me.PlayerGui:GetDescendants()) do
    if d.Name == name and T.visible(d) then return d.Text end
  end
end

print("① 表：各型的夜视、分划、通道（没走科技树的车按型号查年代）")
do
  local k59 = OPT.kit("cn_59", "type59", 0, 1959, "cn")
  check(k59.nv == "ir" and k59.ret == "sov" and #k59.modes == 2 and k59.modes[2] == 5, "59 式：主动红外、苏式分划、昼光 + 主动红外")
  local kA = OPT.kit("us_m1a2sep3", "m1a2", 4, 2017, "us")
  check(kA.nv == "th3" and kA.ret == "hk" and #kA.modes == 3, "M1A2 SEPv3：三代热像、猎歼分划、昼光 + 白热 + 黑热")
  local kG = OPT.kit("de_gepard", "gepard1a1", nil, 1976, "de")
  check(kG.nv == "none" and #kG.modes == 1, "猎豹防空车：没有夜视，只有昼光")
  check(OPT.nvByYear(1970, "us") == "ir" and OPT.nvByYear(1985, "ru") == "ii" and OPT.nvByYear(1990, "us") == "th1" and OPT.nvByYear(2020, "cn") == "th3",
    "没写的按年代、东西方推：1970 主动红外、八十年代东方微光 / 西方一代热像、2020 三代热像")
end

-- 车放在离人不远的平地上
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local home = hrp and hrp.Position or V3(Map.CAMP.x, 0, Map.CAMP.z)
local function flatAt(x, z) return Map.isLand(x, z) and Map.height(x, z) > 2 and Map.slope(x, z) < 0.25 end
local spot
for _, rr in ipairs({ 30, 60, 120, 240, 400 }) do
  for k = 0, 23 do
    local a = k / 24 * math.pi * 2
    local x, z = home.X + math.cos(a) * rr, home.Z + math.sin(a) * rr
    if flatAt(x, z) and flatAt(x + 12, z) then spot = { x = x, z = z } break end
  end
  if spot then break end
end
check(spot ~= nil, "找到放车的平地")
if not spot then T.summary() return end

local CASES = {
  { vid = "type59", nv = "ir", ret = "sov", night = "ir", cycle = { "day", "ir" }, digital = false },
  { vid = "m60a1", nv = "ir", ret = "nato", night = "ir", cycle = { "day", "ir" }, digital = false },
  { vid = "t72a", nv = "ii", ret = "lrf", night = "nv", cycle = { "day", "nv" }, digital = true },
  { vid = "leo2a4", nv = "th1", ret = "lrf", night = "whot", cycle = { "bhot", "day", "whot" }, digital = true },
  { vid = "t90m", nv = "th3", ret = "hk", night = "whot", cycle = { "bhot", "day", "whot" }, digital = true },
}
for i, cs in ipairs(CASES) do
  print(string.format("%s 坐上 %s、半夜开镜", ({ "②", "③", "④", "⑤", "⑥" })[i] or "·", cs.vid))
  local def = VD.get(cs.vid)
  check(def ~= nil, "有 " .. cs.vid .. " 这一型")
  if def then
    local e = G.newVehicle("def", cs.vid, G.vehBaseAt(def, spot.x, spot.z, V3(0, 0, -1)))
    R.run(0.5)
    local h2 = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
    if h2 then h2.CFrame = CF(spot.x + 10, Map.height(spot.x + 10, spot.z) + 3, spot.z) end
    R.run(0.3)
    T.act("enterVeh", e.id)
    R.run(1)
    if P.vehicle ~= e then
      local h3 = P.char and P.char:FindFirstChild("HumanoidRootPart")
      print(string.format("    上车没成：alive %s char %s 车 %s 队 %s/%s 司机 %s ai %s 距离 %.1f 留给 %s",
        tostring(P.alive), tostring(P.char ~= nil), tostring(P.vehicle and P.vehicle.id), tostring(e.team), tostring(P.team), tostring(e.driver ~= nil),
        tostring(e.ai), h3 and (h3.Position - e.root.CFrame.Position).Magnitude or -1, tostring(e.resP and e.resP.pl and e.resP.pl.Name)))
    end
    local st = C.drive
    check(P.vehicle == e and st ~= nil, "坐上了 " .. cs.vid)
    if st then
      R.as("client", function() C.driveSetSight(true) end)
      R.run(0.5)
      local kit = st.kit or {}
      check(kit.nv == cs.nv and kit.ret == cs.ret,
        string.format("%s：夜视 %s（要 %s）、分划 %s（要 %s）", cs.vid, tostring(kit.nv), cs.nv, tostring(kit.ret), cs.ret))
      local names = {}
      for _, m in ipairs(st.allow or {}) do names[#names + 1] = MODES[m] end
      check(#names == #cs.cycle, cs.vid .. " 能切的通道：" .. table.concat(names, "、"))
      check(MODES[st.mode] == cs.night, string.format("半夜开镜默认是这辆车最好的夜视：%s（要 %s）", tostring(MODES[st.mode]), cs.night))
      -- 分划（用户 11-27 起：GunSight.lua 照真镜子画、全屏、按密位随倍率缩放；按型号 / 年代挑一家，SightDefs.FAMILY）
      local FAM = { type59 = "tsh", m60a1 = "nato1", t72a = "tpd", leo2a4 = "natolrf", t90m = "sovmod" }
      check(C.gunSightFamily == FAM[cs.vid], string.format("%s 的分划是「%s」（要 %s）", cs.vid, tostring(C.gunSightFamily), FAM[cs.vid]))
      local rc, nl = find("Reticle"), 0
      if rc then for _, f in ipairs(rc:GetChildren()) do if f.Name == "L" and f.Visible then nl = nl + 1 end end end
      check(nl >= 12, string.format("分划画出来了（%d 根线）", nl))
      local eye = find("Eyepiece") or nil
      check(not (eye and eye.Visible), "全屏开镜：不套圆形目镜")
      local rngT = find("GsRange")
      check((rngT ~= nil and rngT.Visible) == cs.digital, cs.digital and "距离有数字读数" or "光学年代：距离不写数字")
      if not cs.digital then
        local lad = C.gunSight and C.gunSight.lastLadder
        check(lad ~= nil and #lad >= 10, string.format("光学年代：竖线左边有这一发弹的表尺（%d 格）", lad and #lad or 0))
      end
      local amm = find("GsAmmo")
      check((amm ~= nil and amm.Visible) == cs.digital, cs.digital and "有火控计算机：下沿有弹种、距离读数" or "光学年代：没有数字读数（弹种、距离、待发方块都不显示）")
      local beam, scan, blur = find("IrBeam"), find("ThScan"), Lighting:FindFirstChild("SightBlur")
      if cs.night == "ir" then
        check(beam and beam.Visible, "主动红外：只有探照灯那一圈亮，外面压黑")
        check(C.sightNv == true, "主动红外按夜视增亮（DayNight 的镜里夜视档）")
        local hv = shownText("HintOptic")
        check(hv and hv:find(C.T("sight.ir"), 1, true), "提示写着主动红外：" .. tostring(hv))
      else
        check(not (beam and beam.Visible), "不是主动红外：没有探照灯圈")
      end
      if cs.nv == "th1" then
        check(scan and scan.Visible and blur and blur.Enabled and math.abs(blur.Size - 3) < 0.01, "第一代热像：有扫描线、画面发糊（模糊 3）")
        check(#T.texts(OPT.NV.th1.short[1]) > 0, "镜里写着「" .. OPT.NV.th1.short[1] .. "」")
      elseif cs.nv == "th3" then
        check(not (scan and scan.Visible) and not (blur and blur.Enabled), "第三代高清热像：没有扫描线、不糊")
        check(#T.texts(OPT.NV.th3.short[1]) > 0, "镜里写着「" .. OPT.NV.th3.short[1] .. "」")
      end
      if SHOT then
        dofile(MOCK_DIR .. "/uidump.lua")(T, me, SHOT .. "/optics_" .. cs.vid .. ".json", true)
      end
      -- V 依次切：只在这辆车有的通道里转
      local seq = {}
      for k = 1, #cs.cycle do
        T.tap(Enum.KeyCode.V)
        R.run(0.4)
        seq[#seq + 1] = tostring(MODES[st.mode])
        if SHOT and k == 1 and (cs.vid == "type59" or cs.vid == "m60a1") then   -- 光学年代的分划在昼光档也截一张
          dofile(MOCK_DIR .. "/uidump.lua")(T, me, SHOT .. "/optics_" .. cs.vid .. "_day.json", true)
        end
      end
      check(table.concat(seq, ",") == table.concat(cs.cycle, ","), cs.vid .. " 按 V：" .. table.concat(seq, " → ") .. "（要 " .. table.concat(cs.cycle, " → ") .. "）")
      R.as("client", function() C.driveSetSight(false) end)
      R.run(0.3)
      check(not (blur and blur.Enabled), "退出瞄准镜：热像的模糊撤掉")
      T.remoteAs(me, "Drive", { op = "exit" })
      R.run(1)
      check(P.vehicle == nil, "下车")
      if e.model then G.removeEnt(e) end
      R.run(0.3)
    end
  end
end
T.summary()
