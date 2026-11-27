-- 全面大战场（客户端）——驾驶界面的图标（用户 11-19：「像素感太强，我要 3A 级别的 UI」「每个坦克侧面截个图，做成全息颜色的 icon，
--   下面显示血量，全息微微带着光晕」）
--   ReplicatedStorage.HudIcons（tools/models/hudicons.py 生成）里是每辆地面载具从原模型正侧面拍的全息图（灰度 + 柔光晕）和
--   界面图形（六边形、炮弹、机枪弹、烟幕弹、「∧」、小炮弹，4 倍超采样画的，边缘不起锯齿），这里解成 EditableImage：
--   G.hudIcon(名字) → { content = Content（给 ImageLabel.ImageContent）, w, h }；用不了（游戏设置 → 安全里没打开 Mesh / Image API）返回 nil，
--   界面退回方块拼的。图是白的 / 灰的，界面上用 ImageColor3 染色（全息绿、挨打红）。第一次用到时解（一张一两毫秒），之后缓存
local RS = game:GetService("ReplicatedStorage")

local HudArt = {}

function HudArt.init(G)
  local AS = game:GetService("AssetService")
  local data = nil
  local B64 = {}
  do
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, 64 do B64[string.byte(chars, i)] = i - 1 end
  end
  local function unb64(s)   -- → 二进制字符串（同 FPSView）
    local parts, chunk, cn = {}, {}, 0
    local pad = 0
    if string.sub(s, -1) == "=" then pad = (string.sub(s, -2, -2) == "=") and 2 or 1 end
    for i = 1, #s, 4 do
      local a, b, c, d = string.byte(s, i, i + 3)
      local x = B64[a] * 262144 + B64[b] * 4096 + (B64[c] or 0) * 64 + (B64[d] or 0)
      chunk[cn + 1] = math.floor(x / 65536) % 256
      chunk[cn + 2] = math.floor(x / 256) % 256
      chunk[cn + 3] = x % 256
      cn += 3
      if cn >= 3000 then
        parts[#parts + 1] = string.char(table.unpack(chunk, 1, cn))
        cn = 0
      end
    end
    if cn > 0 then parts[#parts + 1] = string.char(table.unpack(chunk, 1, cn)) end
    local out = table.concat(parts)
    if pad > 0 then out = string.sub(out, 1, #out - pad) end
    return out
  end

  local cache = {}
  local broken = false   -- EditableImage 用不了：不再试
  local function decode(t)
    local w, h = t.w, t.h
    local raw = unb64(t.d)
    local buf = buffer.create(w * h * 4)   -- 新建的是全 0（透明）
    local la = t.f == "la"
    local o, i, n = 0, 1, #raw
    while i <= n do
      local b = string.byte(raw, i)
      if b == 0 then
        o += string.byte(raw, i + 1)   -- 一串透明的：跳过
        i += 2
      else
        local l, a
        if la then
          l, a = math.floor(b / 16) * 17, (b % 16) * 17
        else
          l, a = 255, b
        end
        local p = o * 4
        buffer.writeu8(buf, p, l)
        buffer.writeu8(buf, p + 1, l)
        buffer.writeu8(buf, p + 2, l)
        buffer.writeu8(buf, p + 3, a)
        o += 1
        i += 1
      end
    end
    local img = AS:CreateEditableImage({ Size = Vector2.new(w, h) })
    img:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), buf)
    return { img = img, content = Content.fromObject(img), w = w, h = h }
  end

  function G.hudIcon(name)
    local c = cache[name]
    if c ~= nil then return c or nil end
    if broken then return nil end
    if not data then
      local ok, d = pcall(function() return require(RS:WaitForChild("HudIcons", 5)) end)
      data = (ok and type(d) == "table") and d or {}
    end
    local t = data[name]
    if not t then
      cache[name] = false
      return nil
    end
    local ok, res = pcall(decode, t)
    if not ok then
      broken = true
      cache[name] = false
      return nil
    end
    cache[name] = res
    return res
  end

  -- 给一个 ImageLabel 装上图标：成功返回 true（失败时 ImageLabel 不动，调用的地方显示方块拼的）
  function G.hudIconOn(label, name)
    local ic = G.hudIcon(name)
    if not ic then return false end
    local ok = pcall(function() label.ImageContent = ic.content end)
    if ok then label:SetAttribute("Icon", name) end   -- 测试的截图工具（tools/mock/hudshot.lua）认图用
    return ok
  end

  ---------------------------------------------------------------- 写实车图（用户 11-25「主页和科技树的载具图用实拍图吧 然后角度要像战雷那样」）
  --   ReplicatedStorage.VehPics（tools/models/vehpics.py）：原模型按战雷科技树那个角度拍的彩色图，每张自己的调色板（带透明度），透明串只记个数；
  --   G.vehPic(图名) → { content, w, h }；G.vehPicOn(ImageLabel, 树枝, 型号……)：按型号找图（地面车查 veh 表，飞机、直升机查 air 表），
  --   装上就把 ImageColor3 还成白（不染色）；没有图、EditableImage 用不了返回 false（调用的地方退回白色剪影）
  local picData, picCache = nil, {}
  -- gray：去色（弹药栏打空了的那格用：调色板每一色换成它的亮度）
  local function picDecode(t, W, H, gray)
    local pal = unb64(t.p)
    local raw = unb64(t.d)
    local buf = buffer.create(W * H * 4)
    local o, i, n = 0, 1, #raw
    while i <= n do
      local b = string.byte(raw, i)
      if b == 0 then
        o += string.byte(raw, i + 1)
        i += 2
      else
        local q = (b - 1) * 4 + 1
        local r, g, bl, a = string.byte(pal, q, q + 3)
        r, g, bl = r or 0, g or 0, bl or 0
        if gray then
          local l = math.floor(r * 0.299 + g * 0.587 + bl * 0.114 + 0.5)
          r, g, bl = l, l, l
        end
        local p = o * 4
        buffer.writeu8(buf, p, r)
        buffer.writeu8(buf, p + 1, g)
        buffer.writeu8(buf, p + 2, bl)
        buffer.writeu8(buf, p + 3, a or 255)
        o += 1
        i += 1
      end
    end
    local img = AS:CreateEditableImage({ Size = Vector2.new(W, H) })
    img:WritePixelsBuffer(Vector2.zero, Vector2.new(W, H), buf)
    return { img = img, content = Content.fromObject(img), w = W, h = H }
  end
  function G.vehPic(name)
    local c = picCache[name]
    if c ~= nil then return c or nil end
    if broken then return nil end
    if not picData then
      local ok, d = pcall(function() return require(RS:WaitForChild("VehPics", 5)) end)
      picData = (ok and type(d) == "table") and d or { pics = {} }
    end
    local t = picData.pics and picData.pics[name]
    if not t then
      picCache[name] = false
      return nil
    end
    local ok, res = pcall(picDecode, t, picData.w or 240, picData.h or 120)
    if not ok then
      picCache[name] = false
      return nil
    end
    picCache[name] = res
    return res
  end
  -- 型号 → 图名（地面车 veh、飞机 / 直升机 air）
  function G.vehPicName(air, id)
    if not picData then G.vehPic("") end
    local tb = picData and (air and picData.air or picData.veh)
    return tb and tb[id] or nil
  end
  function G.vehPicOn(label, air, ...)
    for _, id in ipairs({ ... }) do
      local name = id and G.vehPicName(air, id)
      if name then pcall(function() label:SetAttribute("PicName", name) end) end   -- 界面截图预览（tools/mock/hud_render.py）按它画车图
      local pc = name and G.vehPic(name)
      if pc then
        local ok = pcall(function() label.ImageContent = pc.content end)
        if ok then
          label.ImageColor3 = Color3.new(1, 1, 1)
          label:SetAttribute("Icon", "pic_" .. name)
          return true
        end
      end
    end
    return false
  end

  ---------------------------------------------------------------- 写实弹种图（用户 11-27「我需要你完全按照战雷的风格去做设计 而不是这种卡通风格……更拟真」）
  --   ReplicatedStorage.AmmoPics（tools/models/ammopics.py）：每种弹、机枪 / 机炮 / 导弹、弹药栏的工具一张 Blender 按真弹建模渲的图
  --   （横放、弹头朝右，显示尺寸的 2 倍），编码同车图，用同一个 picDecode 解；
  --   G.ammoPicName("ammo" | "w" | "tool", 键) → 图名；G.ammoPic(图名, 去色) → { content, w, h }；
  --   G.ammoPicFade(图名)：药筒伸出图外、左边要渐隐的（弹药栏用 UIGradient 做）；
  --   G.ammoPicOn(ImageLabel, 图名, 去色)：装上返回 true；没有这张图、用不了 EditableImage（游戏设置没开 Mesh / Image API）返回 false
  --   （弹药栏退回单色剪影）
  local apData, apCache, apBroken = nil, {}, false
  local function apLoad()
    if not apData then
      local ok, d = pcall(function() return require(RS:WaitForChild("AmmoPics", 5)) end)
      apData = (ok and type(d) == "table") and d or { pics = {} }
    end
    return apData
  end
  function G.ammoPicName(kind, key)
    local tb = key and apLoad()[kind]
    return tb and tb[key] or nil
  end
  function G.ammoPicFade(name)
    local tb = name and apLoad().fade
    return (tb and tb[name]) == true
  end
  function G.ammoPic(name, gray)
    if not name then return nil end
    local ck = gray and (name .. "#g") or name
    local c = apCache[ck]
    if c ~= nil then return c or nil end
    if broken or apBroken then return nil end
    local t = (apLoad().pics or {})[name]
    if not t then
      apCache[ck] = false
      return nil
    end
    local ok, res = pcall(picDecode, t, t.w, t.h, gray)
    if not ok then
      apBroken = true   -- EditableImage 用不了：后面的也不试了
      apCache[ck] = false
      return nil
    end
    apCache[ck] = res
    return res
  end
  function G.ammoPicOn(label, name, gray)
    local pc = G.ammoPic(name, gray)
    if not pc then return false end
    local ok = pcall(function() label.ImageContent = pc.content end)
    if not ok then return false end
    label.ImageColor3 = Color3.new(1, 1, 1)
    label:SetAttribute("AmmoPic", gray and (name .. "#g") or name)   -- 界面截图预览（tools/mock/hud_render.py）按它画图
    return true
  end
end

return HudArt
