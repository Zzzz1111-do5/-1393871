-- 导弹尾烟（模拟器，不用开服）：python3 tools/mock/run.py tools/mock/mslsmoke.lua
--   用户 11-28「然后导弹尾烟不够真实」：Client/MslSmoke.lua——连着的烟带（Trail）+ 往外胀、顺风飘的烟团（每帧在这一帧飞过的那一段里撒）+ 喷口火舌
--   ① 一枚浓烟弹一秒飞 1680 格（600 米 / 秒）飞 3 秒：每一帧都撒到（不再隔几十格一颗球），撒的总数有上限；发射器的小零件拉成这一帧那一段那么长；
--      发射器飞过 500 格换一个新的（旧的停在原地）
--   ② 低烟发动机比浓烟的细、淡、留得短、撒得少
--   ③ 助推 → 续航：另起一条烟带（细一点、淡一点），旧的那条多开一帧接上
--   ④ 发动机一关：火舌灭、烟带不长了、不再撒；⑤ 弹没了：烟留到散完才收（小零件过几秒才删）
--   用户 11-28「尾烟还是不像战雷」：浓烟挂二十来秒、一般的十几秒；烟带两层（里浓外淡、外层宽一倍）叠出虚的边
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check

do   -- 不开服：自己装上 Luau → Lua 5.4 的转换（同 load.lua）
  local L = dofile(MOCK_DIR .. "/luau.lua")
  R.transform = function(src, path) return L.compile(src, path) end
end
local folder = R.Instance.new("Folder")
folder.Name = "ClientFx"
folder.Parent = R.services.Workspace
local ms = R.scriptFrom("ModuleScript", "MslSmoke", SRC_DIR .. "/StarterPlayer/StarterPlayerScripts/Client/MslSmoke.lua", R.services.ReplicatedStorage)
local MSL = R.require(ms)
local G = { perfK = 1 }
local M = MSL.new(G, folder, nil)
local cam = R.services.Workspace.CurrentCamera
if cam then cam.CFrame = CF(V3(0, 30, 400)) end

local function count(cls, name)
  local n = 0
  for _, d in ipairs(folder:GetDescendants()) do
    if d.ClassName == cls and (name == nil or d.Name == name) then n = n + 1 end
  end
  return n
end
-- 镜头跟着弹（300 格后面）：11-28 起四千格外只剩烟带、不撒烟团，镜头不动的话弹飞远了就不撒了；camFix 给了就钉在那里（量远处的）
local camFix = nil
local function fly(s, v, secs, cls, ph, on, from)
  local p = from or V3(0, 300, 0)
  local dir = V3(1, 0.05, -0.2).Unit
  local frames, hit = 0, 0
  for _ = 1, math.floor(secs * 60 + 0.5) do
    p = p + dir * v / 60
    if cam then cam.CFrame = camFix or CF(p - dir * 300 + V3(0, 40, 0)) end
    local e0 = M.stat.emitted
    M.step(s, R.CFrame.lookAt(p, p + dir), 2, 1 / 60, on ~= false, cls, ph, 1.0)
    frames = frames + 1
    if M.stat.emitted > e0 then hit = hit + 1 end
  end
  return p, frames, hit
end

print("① 浓烟弹，600 米 / 秒，3 秒")
local s = {}
local e0, em0 = M.stat.emitted, M.stat.emitters
local p1, frames, hit = fly(s, 1680, 3, "heavy", 1)
local n = M.stat.emitted - e0
print(string.format("   撒了 %d 团（%d 帧里 %d 帧撒到）；发射器 %d 个；烟带 %d 条", n, frames, hit, M.stat.emitters - em0, count("Trail")))
check(s.sm ~= nil and count("Trail") >= 2, "有烟带、火舌两条 Trail")
check(hit >= frames - 2, "几乎每一帧都撒到（连着的，不再隔几十格一颗球）")
check(n >= 200 and n <= 700, "撒的总数有上限（" .. n .. "；烟团大、活得久，撒得稀：11-28「开飞机太卡了」又收了一半多）")
check(M.stat.emitters - em0 >= 8, "飞过 500 格换一个发射器（" .. (M.stat.emitters - em0) .. " 个）")
local E = s.sm and s.sm.E
check(E ~= nil and math.abs(E.h.Size.Z - 28) < 1.5, string.format("发射器的小零件拉成这一帧那一段（%.1f 格）", E and E.h.Size.Z or -1))
local tr = s.sm and s.sm.trails["heavy_1"]
check(tr ~= nil and tr.Lifetime >= 18 and tr.LightInfluence == 1, string.format("浓烟的烟带挂 %.0f 秒（战雷那样看得清整条弹道）、受光照（夜里不自己发白）", tr and tr.Lifetime or 0))
local hl = s.sm and s.sm.halos and s.sm.halos["heavy_1"]
local wC = tr and (tr.Attachment1.Position - tr.Attachment0.Position).Magnitude or 0
local wH = hl and (hl.Attachment1.Position - hl.Attachment0.Position).Magnitude or 0
local tC = tr and tr.Transparency.Keypoints[1].Value or 1
local tH = hl and hl.Transparency.Keypoints[2].Value or 0
check(hl ~= nil and hl.Enabled and wH > wC * 1.6 and tH > tC + 0.3, string.format("外面一层宽、淡的烟（%.1f / %.1f 格，透明度 %.2f / %.2f）：里浓外淡、边是虚的", wH, wC, tH, tC))
local fl = s.sm and s.sm.flame
check(fl ~= nil and fl.MaxLength > 0 and fl.MaxLength < 12 and fl.LightEmission == 1, "火舌最长几格（不随速度拖长）、自己发光")

print("② 低烟发动机：细、淡、留得短、撒得少")
local s2 = {}
local e1 = M.stat.emitted
fly(s2, 1680, 3, "low", 1, true, V3(0, 600, 0))
local n2 = M.stat.emitted - e1
local tl = s2.sm and s2.sm.trails["low_1"]
check(tl ~= nil and tl.Lifetime < tr.Lifetime and tl.Transparency.Keypoints[1].Value > tr.Transparency.Keypoints[1].Value, string.format("烟带留得短（%.0f 秒）、更淡", tl and tl.Lifetime or 0))
check(n2 < n * 0.5, string.format("撒得少（%d 团 / 浓烟 %d 团）", n2, n))

print("③ 助推 → 续航")
local s3 = {}
local p3 = fly(s3, 1200, 0.6, "med", "boost", true, V3(0, 900, 0))
fly(s3, 1200, 1 / 60, "med", "sus", true, p3)
local tb, ts = s3.sm.trails["med_boost"], s3.sm.trails["med_sus"]
check(tb ~= nil and ts ~= nil, "续航段另起一条烟带")
check(tb and tb.Enabled and ts and ts.Enabled, "换段那一帧两条都开着（接上，不断一截）")
fly(s3, 1200, 2 / 60, "med", "sus", true, p3 + V3(40, 0, 0))
check(tb and not tb.Enabled and ts.Enabled, "下一帧旧的关掉")
local wB = (tb.Attachment1.Position - tb.Attachment0.Position).Magnitude
local wS = (ts.Attachment1.Position - ts.Attachment0.Position).Magnitude
check(wS < wB and ts.Transparency.Keypoints[1].Value > tb.Transparency.Keypoints[1].Value, string.format("续航段细一点（%.2f / %.2f 格）、淡一点", wS, wB))

print("④ 发动机一关")
local e2 = M.stat.emitted
fly(s, 1680, 0.5, "heavy", 1, false, p1)
check(M.stat.emitted == e2, "不再撒烟团")
check(not fl.Enabled and not tr.Enabled and not hl.Enabled, "火舌灭了、烟带（两层）不再长")

print("⑥ 四千格外：只剩烟带，不撒烟团（11-28「开飞机太卡了」：远处的烟团小得看不清、白画）")
do
  local s6 = {}
  camFix = CF(V3(0, 1200, 0))
  local e6 = M.stat.emitted
  fly(s6, 1200, 0.5, "heavy", 1, true, V3(9000, 1200, 0))
  camFix = nil
  local tr6 = s6.sm and s6.sm.trails["heavy_1"]
  check(M.stat.emitted == e6 and tr6 ~= nil and tr6.Enabled, string.format("离镜头九千格的浓烟弹：烟带照画、烟团一团没撒（%d）", M.stat.emitted - e6))
  M.stop(s6)
end
print("⑤ 弹没了：烟留到散完才收")
local h = s.sm and s.sm.h
M.stop(s)
check(s.sm == nil and h ~= nil and h.Parent ~= nil, "零件先留着（烟还在飘）")
R.run(8)
check(h.Parent ~= nil, "八秒后还在（烟挂得久）")
R.run(17)
check(h.Parent == nil, "过了烟的寿命收掉")
T.summary()
