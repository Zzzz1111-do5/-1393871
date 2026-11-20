-- 全面大战场（客户端）——驾驶界面的图标（用户 11-19：「像素感太强，我要 3A 级别的 UI」「每个坦克侧面截个图，做成全息颜色的 icon，
--   下面显示血量，全息微微带着光晕」）
--   ReplicatedStorage.HudIcons（tools/models/hudicons.py 生成）里是每辆地面载具从原模型正侧面拍的全息图（灰度 + 柔光晕）和
--   界面图形（六边形、炮弹、机枪弹、烟幕弹、「∧」、小炮弹，4 倍超采样画的，边缘不起锯齿），这里解成 EditableImage：
--   G.hudIcon(名字) → { content = Content（给 ImageLabel.ImageContent）, w, h }；用不了（游戏设置 → 安全里没打开 Mesh / Image API）返回 nil，
--   界面退回方块拼的。图是白的 / 灰的，界面上用 ImageColor3 染色（全息青、挨打红）。第一次用到时解（一张一两毫秒），之后缓存
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
end

return HudArt
