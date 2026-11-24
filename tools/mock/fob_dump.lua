-- 主基地导出给预览图（tools/mock/fob_view.cjs 画）：开服建好沙海以后，把一边主基地（FOB_<side>）的零件写成 JSON——
--   形状、大小、CFrame（世界坐标减去基地中心）、颜色、材质、透明度；还有基地的朝向（yaw）好摆镜头
--   python3 tools/mock/run.py tools/mock/fob_dump.lua out=<文件> [side=atk|def]
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local out = TEST_ARGS:match("out=(%S+)") or "/tmp/fob.json"
local side = TEST_ARGS:match("side=(%a+)") or "atk"
local G = T.boot()
G.fortsHold = true
T.runUntil(function() return G.worldReady end, 900)
local B = G.Map.BASES[side]
local Y = G.Map.ground(B.x, B.z)
local f = R.services.Workspace.Map.Scenery:FindFirstChild("FOB_" .. side)
local parts = {}
local function num(x) return string.format("%.3f", x) end
local function dump(root)
  for _, p in ipairs(root:GetDescendants()) do
    if p:IsA("BasePart") and p.Transparency < 0.99 then
      local shape = "Block"
      if p.ClassName == "WedgePart" then shape = "Wedge" elseif p.ClassName == "Part" then shape = p.Shape.Name end
      local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = p.CFrame:GetComponents()
      local c = p.Color
      local glow = (p.Material.Name == "Neon") and 1 or 0
      table.insert(parts, string.format('{"s":"%s","z":[%s,%s,%s],"c":[%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s],"k":[%d,%d,%d],"m":"%s","t":%s,"g":%d}',
        shape, num(p.Size.X), num(p.Size.Y), num(p.Size.Z), num(x - B.x), num(y - Y), num(z - B.z),
        num(r00), num(r01), num(r02), num(r10), num(r11), num(r12), num(r20), num(r21), num(r22),
        math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255), p.Material.Name, num(p.Transparency), glow))
    end
  end
end
dump(f)
-- 附近的召唤位、工事（基地矩形里的）
local pads = R.services.Workspace.Map:FindFirstChild("Pads")
if pads then dump(pads) end
local fh = io.open(out, "w")
fh:write(string.format('{"yaw":%s,"parts":[%s]}', num(B.yaw), table.concat(parts, ",\n")))
fh:close()
print(string.format("写了 %d 个零件 → %s", #parts, out))
