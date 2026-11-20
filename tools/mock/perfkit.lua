-- 卡顿排查的公用工具（perf.lua、perf_battle.lua 用）
--   模拟器的 CPU 时间不准：射线逐个零件试（比真 Roblox 慢几百倍，所以另算、从回调时间里扣掉），
--   属性读写过一层元表（比真的慢几倍）。主要看次数：每帧建 / 删 / 改属性多少次、射线几条、远程事件每秒多少数据、场景里有多少零件 / 灯 / 光晕
return function(T)
  local R = T.R
  local K = {}
  local cpu = os.clock

  -- 把一张表里 step 开头的函数都包一层计时（客户端的 G.stepXxx、服务器的 G.xxxStep）
  function K.wrap(tbl, pat, prefix, into)
    for k, v in pairs(tbl) do
      if type(v) == "function" and k:match(pat) then
        tbl[k] = function(...)
          local t0, r0, n0 = cpu(), R.rayT, R.rayN
          local a, b, c = v(...)
          local key = prefix .. k
          into.t[key] = (into.t[key] or 0) + (cpu() - t0) - (R.rayT - r0)
          into.n[key] = (into.n[key] or 0) + (R.rayN - n0)
          return a, b, c
        end
      end
    end
  end

  -- 场景清单：渲染的负担
  function K.inventory(title, me)
    local cls, top, n = {}, {}, 0
    local shadow, trans = 0, 0
    local function walk(o, topName)
      for _, c in ipairs(o._kids) do
        n = n + 1
        cls[c._cls] = (cls[c._cls] or 0) + 1
        local tn = topName or c._p.Name
        top[tn] = (top[tn] or 0) + 1
        if R.base.IsA(c, "BasePart") then
          if c._p.CastShadow ~= false then shadow = shadow + 1 end
          local tr = c._p.Transparency or 0
          if tr > 0 and tr < 1 then trans = trans + 1 end
        end
        walk(c, tn)
      end
    end
    walk(R.workspace)
    print(string.format("  —— %s：workspace 里 %d 个实例；投影子的零件 %d，半透明零件 %d", title, n, shadow, trans))
    local function line(map, m)
      local rows = {}
      for k, v in pairs(map) do rows[#rows + 1] = { k = k, v = v } end
      table.sort(rows, function(a, b) return a.v > b.v end)
      local out = {}
      for i = 1, math.min(m, #rows) do out[#out + 1] = rows[i].k .. " " .. rows[i].v end
      return table.concat(out, "，")
    end
    print("    按类：" .. line(cls, 18))
    print("    按顶层：" .. line(top, 16))
    local pg = me and me:FindFirstChildOfClass("PlayerGui")
    if pg then
      local g, vis = 0, 0
      local function gw(o, shown)
        for _, c in ipairs(o._kids) do
          g = g + 1
          local s2 = shown
          if c._cls == "ScreenGui" then s2 = c._p.Enabled ~= false
          elseif R.base.IsA(c, "GuiObject") then s2 = shown and c._p.Visible ~= false end
          if s2 and R.base.IsA(c, "GuiObject") then vis = vis + 1 end
          gw(c, s2)
        end
      end
      gw(pg, true)
      print(string.format("    界面：PlayerGui 里 %d 个实例，显示着的界面元素 %d 个", g, vis))
    end
  end

  function K.report(title, wall, n, ops, timed)
    print(string.format("  —— %s：%d 帧，模拟器 CPU %.1f 秒（每帧 %.2f 毫秒，含射线和模拟器开销）", title, n, wall, wall / n * 1000))
    local rows = {}
    for k, v in pairs(R.prof) do rows[#rows + 1] = { k = "连接 " .. k, v = v, r = R.profRay[k] or 0 } end
    for k, v in pairs(timed.t) do rows[#rows + 1] = { k = k, v = v, r = timed.n[k] or 0 } end
    table.sort(rows, function(a, b) return a.v > b.v end)
    print("    不算射线的 CPU（毫秒 / 帧）、射线（条 / 帧）：")
    for i = 1, math.min(16, #rows) do print(string.format("    %7.2f 毫秒  %5.1f 条  %s", rows[i].v / n * 1000, rows[i].r / n, rows[i].k)) end
    local byKind, byLine = {}, {}
    for k, v in pairs(ops) do
      local sd, kind, where = k:match("^(%S+)\t(.-)\t(.*)$")
      local kk = sd .. " " .. kind
      byKind[kk] = (byKind[kk] or 0) + v
      local kl = sd .. " " .. kind .. "  @" .. where
      byLine[kl] = (byLine[kl] or 0) + v
    end
    local function top(map, m, label)
      local rr = {}
      for k, v in pairs(map) do if not k:find("bytes") and not k:find("raylen") then rr[#rr + 1] = { k = k, v = v } end end
      table.sort(rr, function(a, b) return a.v > b.v end)
      print("    " .. label)
      for i = 1, math.min(m, #rr) do print(string.format("    %9.1f /帧  %s", rr[i].v / n, rr[i].k)) end
    end
    top(byKind, 24, "每帧操作（哪边 操作 类）：")
    top(byLine, 30, "每帧操作最多的代码行：")
    local net, tot = {}, 0
    for k, v in pairs(byKind) do
      if k:find("bytes") then net[#net + 1] = { k = k, v = v } tot = tot + v end
    end
    table.sort(net, function(a, b) return a.v > b.v end)
    print(string.format("    远程事件数据量 %.1f KB/秒：", tot / (n / 30) / 1024))
    for i = 1, math.min(8, #net) do print(string.format("    %8.2f KB/秒  %s", net[i].v / (n / 30) / 1024, net[i].k)) end
  end

  function K.measure(title, sec, timed, f)
    R.prof, R.profRay, R.ops = {}, {}, {}
    timed.t, timed.n = {}, {}
    local n = math.floor(sec * 30)
    local t0 = cpu()
    for i = 1, n do
      if f then f(i) end
      R.step(1 / 30)
    end
    local ops = R.ops
    R.ops = nil
    K.report(title, cpu() - t0, n, ops, timed)
    R.prof = nil
  end
  return K
end
