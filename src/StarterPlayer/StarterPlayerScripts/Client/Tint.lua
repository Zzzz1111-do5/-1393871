-- Roblox全面大战场（客户端）——导入的原模型贴图没出来时的底色
--   Studio「导入 3D」时网格和贴图分开上传：贴图没传上去、还在审核或者被拒，零件就是一块白的（导入器把零件颜色设成白色，等贴图盖上）；
--   没贴图的材质导入器也不一定把颜色带过来。这里按 ImportedTint（tools/models/tint.py：每块零件原贴图按面积取样的平均色 × 材质底色）补：
--   1. 复制出来的零件颜色一律先换成平均色——贴图正常时被贴图盖住看不出来，贴图出不来时露出来的是这个颜色而不是白色；
--   2. 带贴图的（SurfaceAppearance 的贴图出不来时不露零件颜色）：这块零件第一次用到时在后台对导入的原件查一次（ContentProvider:PreloadAsync），
--      贴图加载失败就去掉贴图、上平均色，已经摆出去的同名零件一起改；输出窗口列出贴图没出来的模型，好重新导入
--   用法：Tint.fix(复制出来的零件, 导入的原件) —— 要在调用方自己上色（换涂装、烧黑）之前调
local RS = game:GetService("ReplicatedStorage")

local Tint = {}

local DATA = nil
do
  local ok, r = pcall(function() return require(RS:WaitForChild("ImportedTint", 3)) end)
  if ok and type(r) == "table" then DATA = r end
end

local state = {}   -- [零件名] = "wait" / "ok" / "bad"
local live = {}    -- [零件名] = { [复制出来的零件] = true }（弱引用）：等检查结果的
local bad = {}     -- [模型键] = 贴图没出来的块数
local reportAt = nil

local function surf(p) return p:FindFirstChildOfClass("SurfaceAppearance") end
local function texId(p)
  local ok, t = pcall(function() return p.TextureID end)   -- 不是 MeshPart 的没有这个属性
  return ok and t or ""
end
local function textured(p) return surf(p) ~= nil or (texId(p) or "") ~= "" end

-- 去掉贴图、上平均色
local function paint(p, col)
  for _, sa in ipairs(p:GetChildren()) do
    if sa:IsA("SurfaceAppearance") then sa:Destroy() end
  end
  pcall(function() p.TextureID = "" end)
  p.Color = col
end

local function report()
  if reportAt then return end
  reportAt = os.clock()
  task.delay(4, function()
    reportAt = nil
    local list = {}
    for k, n in pairs(bad) do table.insert(list, k .. "（" .. n .. " 块）") end
    table.sort(list)
    if #list > 0 then
      warn("[全面大战场] 这些原模型的贴图没加载出来，先用原贴图的平均色代替：" .. table.concat(list, "、")
        .. "。多半是 Studio 导入时贴图没传上去或者还在审核：过几分钟再开一次；还不行就把这几个 GLB 删掉重新导入（一次少导几个），导入时看输出窗口有没有上传失败")
    end
  end)
end

local function check(name, src)
  state[name] = "wait"
  task.spawn(function()
    local failed = false
    local okM, meshId = pcall(function() return src.MeshId end)
    pcall(function()
      game:GetService("ContentProvider"):PreloadAsync({ src }, function(id, status)
        if status == Enum.AssetFetchStatus.Failure or status == Enum.AssetFetchStatus.TimedOut then
          if not (okM and id == meshId) then failed = true end   -- 网格没出来的零件本来就看不见，只管贴图
        end
      end)
    end)
    state[name] = failed and "bad" or "ok"
    local set = live[name]
    live[name] = nil
    if failed then
      local c = DATA[name]
      local col = Color3.fromRGB(c[1], c[2], c[3])
      for p in pairs(set or {}) do
        if p.Parent and textured(p) then paint(p, col) end   -- 调用方已经自己去掉贴图（换涂装、烧黑）的不动
      end
      local key = string.match(name, "^%a_([%w_]-)__") or string.match(name, "^(FPS_M4)") or name
      bad[key] = (bad[key] or 0) + 1
      report()
    end
  end)
end

function Tint.fix(p, src)
  if not DATA or not p then return p end
  local name = (src and src.Name) or p.Name
  local c = DATA[name]
  if not c then return p end
  local col = Color3.fromRGB(c[1], c[2], c[3])
  p.Color = col
  if not textured(p) then return p end   -- 没贴图：平均色就是它本来的颜色
  local st = state[name]
  if st == "bad" then
    paint(p, col)
  elseif st ~= "ok" then
    live[name] = live[name] or setmetatable({}, { __mode = "k" })
    live[name][p] = true
    if st == nil then check(name, src or p) end
  end
  return p
end

-- 有没有这块零件的平均色（调用方没贴图时自己上色用）
function Tint.color(name)
  local c = DATA and DATA[name]
  return c and Color3.fromRGB(c[1], c[2], c[3]) or nil
end

return Tint
