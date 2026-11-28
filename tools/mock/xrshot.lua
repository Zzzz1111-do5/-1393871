-- X 光命中回放截图（模拟器）：python3 tools/mock/run.py tools/mock/xrshot.lua
--   用户 11-28「目前x光效果还是不如战雷」：改回放的样子要看得见——给客户端发几发命中（wtHit），到几个时间点把
--   ① 界面（uidump：回放窗口的框、字）写成 <名>.json（tools/mock/hud_render.py 画）
--   ② 回放窗口里 ViewportFrame 的 3D 场景（每个零件的形状、大小、CFrame、颜色、透明度、材质；镜头；环境光、平行光；
--      车壳的「影子」用哪个原模型、什么颜色材质）写成 <名>.vp.json（tools/mock/vp_render.py 用 Blender 画，贴进 ViewportFrame 的框）
--   环境变量 XR_OUT：输出目录（默认 /tmp/xrshot）；XR_ONLY：只拍这几个（逗号分开）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3 = T.R, T.V3
local check = T.check
local dump = dofile(MOCK_DIR .. "/uidump.lua")

local OUT = os.getenv("XR_OUT") or "/tmp/xrshot"
os.execute("mkdir -p '" .. OUT .. "'")
local ONLY = {}
for k in string.gmatch(os.getenv("XR_ONLY") or "", "[^,]+") do ONLY[k] = true end

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
local me = T.join("P1", 8702, true)
R.run(1)
local function find(name)
  for _, d in ipairs(me.PlayerGui:GetDescendants()) do if d.Name == name then return d end end
end
local xr = find("WtXray")
check(xr ~= nil, "X 光窗口在")
if not xr then T.summary() return end
local vp = xr:FindFirstChild("View")
local wm = vp and vp:FindFirstChildOfClass("WorldModel")

local function c3(c) return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) } end
local function cfa(cf) return { cf:GetComponents() } end
local function enumName(e) return e and tostring(e):match("([%w_]+)$") or nil end
local function dumpVp(path, name)
  local parts = {}
  for _, p in ipairs(wm:GetDescendants()) do
    if R.base.IsA(p, "BasePart") then
      local sm = p:FindFirstChildOfClass("SpecialMesh")
      parts[#parts + 1] = {
        name = p.Name, cls = p.ClassName, shape = enumName(p.Shape), size = { p.Size.X, p.Size.Y, p.Size.Z }, cf = cfa(p.CFrame),
        col = c3(p.Color), tr = p.Transparency, mat = enumName(p.Material), mesh = sm and enumName(sm.MeshType) or nil,
        ghost = p:GetAttribute("XrGhost"), gk = p:GetAttribute("XrGhostKey"),
      }
    end
  end
  local cam = vp.CurrentCamera
  local st = T.C.wtXrStyle and T.C.wtXrStyle() or {}   -- 客户端的 G（T.C）
  local f = io.open(path, "w")
  f:write(R.services.HttpService:JSONEncode({
    name = name, cam = cfa(cam.CFrame), fov = cam.FieldOfView, bg = c3(vp.BackgroundColor3), bgT = vp.BackgroundTransparency,
    amb = c3(vp.Ambient), light = c3(vp.LightColor), ldir = { vp.LightDirection.X, vp.LightDirection.Y, vp.LightDirection.Z },
    parts = parts, ghost = st.ghost,
  }))
  f:close()
  print(string.format("  %s：%d 个零件", path, #parts))
end
local function shoot(name, m, times)
  if next(ONLY) and not ONLY[name] then return end
  print("■ " .. name)
  G.R.Drive:FireClient(me, m)
  local t = 0
  for _, tt in ipairs(times) do
    R.run(tt - t)
    t = tt
    local nm = string.format("%s_%.1f", name, tt)
    dump(T, me, OUT .. "/" .. nm .. ".json", true)
    dumpVp(OUT .. "/" .. nm .. ".vp.json", nm)
  end
  R.run(8)   -- 窗口关了再打下一发
end

-- 射流弹打穿 T-90M、弹药殉爆（同 wtxray.lua）
shoot("t90m_jet", { op = "wtHit", id = 0, veh = "t90m", r = "pen", kill = true, why = "ammo", fire = true,
  parts = { { k = "gnr", kind = "crew", s = 0 }, { k = "cmd", kind = "crew", s = 1 }, { k = "ammo", kind = "mod", s = 0 } },
  pen = 950, arm = 620, dist = 800,
  xr = { p = { 0, 4.2, -5.5 }, d = { 0.1, -0.05, 1 }, ty = 0, seed = 4321, half = 16, n = 18, core = 4.4, jet = true, big = true } }, { 0.4, 1.2, 3.0 })
-- 脱壳穿甲弹打穿豹 2A6 侧面：打到驾驶员、发动机（动能弹的慢放）
shoot("leo_apfsds", { op = "wtHit", id = 0, veh = "leo2a6", r = "pen", kill = false, why = nil,
  parts = { { k = "drv", kind = "crew", s = 0 }, { k = "engine", kind = "mod", s = 1 } },
  pen = 560, arm = 80, dist = 1200,
  xr = { p = { 4.6, 3.0, 1.0 }, d = { -1, -0.08, 0.15 }, ty = 25, seed = 777, half = 22, n = 26, core = 6.0, sub = "ap" } }, { 1.2, 3.5 })
-- 跳弹（不放慢放、静止的回放）：99A 车体侧面，看没事的弹药（洋红）、发动机（电光蓝）的标识色（用户 11-28「给弹药 发动机都搞一下特殊颜色的标识吧」）
shoot("ztz_ric", { op = "wtHit", id = 0, veh = "ztz99a", r = "ric", kill = false, why = nil, parts = {},
  pen = 450, arm = 520, dist = 650,
  xr = { p = { 4.4, 2.6, 2.0 }, d = { -1, -0.1, -0.2 }, ty = 0, seed = 99, half = 18, n = 0, core = 0, sub = "fs" } }, { 1.0 })
T.summary()
