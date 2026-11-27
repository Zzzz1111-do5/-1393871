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
  -- 解成像素（RGBA buffer）：gray 去色（弹药栏打空了的那格用：调色板每一色换成它的亮度）；
  --   调色板里透明度 0 的颜色也照写（弹种图的透明边外扩了两圈边缘色：缩小显示时双线性插值不把边混黑）
  local function picPixels(t, W, H, gray)
    local pal = unb64(t.p)
    local raw = unb64(t.d)
    local buf = buffer.create(W * H * 4)
    local o, i, n, last = 0, 1, #raw, W * H
    local rle = t.f == "r"   -- 弹种图：255 + 个数 = 上一个像素再重复几个（车图没有这一码，255 是第 255 色）
    while i <= n do
      local b = string.byte(raw, i)
      if b == 0 then
        o += string.byte(raw, i + 1)
        i += 2
      elseif rle and b == 255 then
        local k = string.byte(raw, i + 1)
        if o < 1 or o + k > last then error("重复码越界") end
        local q = (o - 1) * 4
        local r, g, bl, a = buffer.readu8(buf, q), buffer.readu8(buf, q + 1), buffer.readu8(buf, q + 2), buffer.readu8(buf, q + 3)
        for _ = 1, k do
          local p = o * 4
          buffer.writeu8(buf, p, r)
          buffer.writeu8(buf, p + 1, g)
          buffer.writeu8(buf, p + 2, bl)
          buffer.writeu8(buf, p + 3, a)
          o += 1
        end
        i += 2
      else
        if o >= last then error("像素比图大") end
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
    return buf
  end
  local function picImage(buf, W, H)
    local img = AS:CreateEditableImage({ Size = Vector2.new(W, H) })
    img:WritePixelsBuffer(Vector2.zero, Vector2.new(W, H), buf)
    return { img = img, content = Content.fromObject(img), w = W, h = H }
  end
  local function picDecode(t, W, H, gray)
    return picImage(picPixels(t, W, H, gray), W, H)
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
  --   （横放、弹头朝右），两套：pics 显示尺寸的 2 倍、pics1 1 倍（弹药栏按格子实际几个像素选，k = 2 / 1）；编码同车图，同一套解法
  --   （透明边外扩的边缘色照写，不写黑）。
  --   11-27 美术审查之后：
  --   · 模块在这里 task.defer 提前 require（427 KB 的模块原来第一次出弹药栏那一帧才 require，前面还 WaitForChild 最多等 5 秒——
  --     模块到之前每一帧都再开一个 WaitForChild）：只等一次，没到之前 G.ammoPicState() 是 "loading"，弹药栏先空着图
  --   · 解码不在 G.ammoPic 里顺手做：G.ammoPicPump() 每调一次最多解一张（弹药栏上车时按格子排队，每帧解一张、去色的也提前解好），
  --     不再一帧里解十来张、建十来个 EditableImage
  --   · 只有 CreateEditableImage 出错才算「用不了」（apBroken）；换车时 G.ammoPicRetry() 再试一次；
  --     一张解不出（数据坏了）只记这一张失败——弹药栏看到有一格失败就整排退回剪影（不会一排里写实图、剪影混着）
  --   G.ammoPicName("ammo" | "w" | "tool", 键) → 图名（模块还没到：nil）；G.ammoPicFade(图名)：药筒伸出图外、左边要渐隐的；
  --   G.ammoPicWant(图名, 去色, k)：排进解码队列；G.ammoPic(图名, 去色, k) → { content, w, h }（解好了）/ false（解不出、没这张）/ nil（还没解）；
  --   G.ammoPicOn(ImageLabel, 图名, 去色, k)：装上返回 true；解不出 false；还没解 nil
  local apData, apState, apCache, apBroken = nil, nil, {}, false
  local apQueue = {}
  local function apStart()
    if apState then return end
    apState = "loading"
    task.spawn(function()
      local ok, d = pcall(function() return require(RS:WaitForChild("AmmoPics", 15)) end)
      if ok and type(d) == "table" and type(d.pics) == "table" then
        apData, apState = d, "ready"
      else
        apData, apState = { pics = {} }, "failed"
      end
    end)
  end
  task.defer(apStart)   -- 进游戏就开始加载（不等第一次上车）
  -- "loading" 还在加载 / "ready" 能用 / "failed" 没有模块 / "broken" 用不了 EditableImage（游戏设置没开 Mesh / Image API）
  function G.ammoPicState()
    apStart()
    if apState == "ready" and apBroken then return "broken" end
    return apState
  end
  function G.ammoPicName(kind, key)
    local tb = key and apState == "ready" and apData[kind]
    return tb and tb[key] or nil
  end
  function G.ammoPicFade(name)
    local tb = name and apState == "ready" and apData.fade
    return (tb and tb[name]) == true
  end
  local function ckey(name, gray, k) return name .. ((k == 1) and "@1" or "") .. (gray and "#g" or "") end
  local function decodeOne(name, gray, k)
    local ck = ckey(name, gray, k)
    if apCache[ck] ~= nil then return end
    local set = (k == 1) and apData.pics1 or apData.pics
    local t = (set or {})[name] or ((k == 1) and apData.pics[name]) or nil   -- 没打 1 倍的：用 2 倍那张
    if not t then
      apCache[ck] = false
      return
    end
    local okP, buf = pcall(picPixels, t, t.w, t.h, gray)
    if not okP then   -- 数据坏了：只这一张失败
      apCache[ck] = false
      return
    end
    local okI, res = pcall(picImage, buf, t.w, t.h)
    if not okI then   -- CreateEditableImage 出错：用不了（换车时再试一次）
      apBroken = true
      return
    end
    apCache[ck] = res
  end
  function G.ammoPicWant(name, gray, k)
    if not name then return end
    local ck = ckey(name, gray, k)
    if apCache[ck] ~= nil then return end
    for _, q in ipairs(apQueue) do if q[4] == ck then return end end
    table.insert(apQueue, { name, gray, k, ck })
  end
  -- 解一张（弹药栏每帧调一次）：返回还剩几张没解
  function G.ammoPicPump()
    if apState ~= "ready" or apBroken then return #apQueue end
    while #apQueue > 0 do
      local q = table.remove(apQueue, 1)
      if apCache[q[4]] == nil then
        decodeOne(q[1], q[2], q[3])
        break
      end
    end
    return #apQueue
  end
  function G.ammoPic(name, gray, k)
    if not name then return false end
    local c = apCache[ckey(name, gray, k)]
    if c == nil then return nil end
    return c
  end
  function G.ammoPicRetry()
    if not apBroken then return end
    apBroken = false
    for ck, v in pairs(apCache) do if v == false then apCache[ck] = nil end end
  end
  function G.ammoPicOn(label, name, gray, k)
    local pc = G.ammoPic(name, gray, k)
    if not pc then return pc end
    local ok = pcall(function() label.ImageContent = pc.content end)
    if not ok then return false end
    label.ImageColor3 = Color3.new(1, 1, 1)
    label:SetAttribute("AmmoPic", gray and (name .. "#g") or name)   -- 界面截图预览（tools/mock/hud_render.py）按它画图
    label:SetAttribute("AmmoPicK", (k == 1) and 1 or 2)             -- 哪一套（1 倍 / 2 倍）
    return true
  end
end

return HudArt
