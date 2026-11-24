-- 内饰导出给预览图（tools/mock/interior_view.cjs 画）：零件、灯、屏幕上的界面、镜头，坐标都换到 ref（车体 / 座舱眼位）里
--   用法：dofile(MOCK_DIR .. "/interior_dump.lua")(cur, ref, cams, path, cam, Enum)
return function(cur2, hull, dumpCams, path, cam, Enum)
  local out = { parts = {}, cams = {}, lights = {}, screens = {} }
  local function num(x) return string.format("%.4f", x) end
  local function cfStr(cf, turn)
    local l = hull:ToObjectSpace(cf)
    local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = l:GetComponents()
    if turn then   -- 右乘绕自己 Y 轴转半圈：旋转矩阵的第 1、3 列取反
      r00, r10, r20, r02, r12, r22 = -r00, -r10, -r20, -r02, -r12, -r22
    end
    return table.concat({ num(x), num(y), num(z), num(r00), num(r01), num(r02), num(r10), num(r11), num(r12), num(r20), num(r21), num(r22) }, ",")
  end
  for _, p in ipairs(cur2.model:GetDescendants()) do
    if p:IsA("BasePart") and p.Transparency < 0.99 then
      local shape = "Block"
      if p.ClassName == "WedgePart" then shape = "Wedge" elseif p.ClassName == "Part" then shape = p.Shape.Name end
      local mesh = p:FindFirstChildOfClass("SpecialMesh")
      if mesh and mesh.MeshType == Enum.MeshType.Sphere then shape = "Sphere" end
      local col = p.Color
      -- 真模型部件（MeshPart，名字 O_<键>__<块>）：记下键和块名，预览图按 models/optics/<键>.glb 里的那一块画（不画成方块）
      local mk, mp = string.match(p.Name, "^O_(.-)__(.+)$")
      local cf = p.CFrame
      local turn = false
      -- 原车模型的块（V_<模型键>__<块>：M1A1 原模型的炮塔内饰，InteriorAbrams 克隆进来的）：预览图按 models/veh/<键>.glb 里的那一块画；
      --   B:mesh 摆的时候乘了导入时转掉的半圈（ImportTurn），GLB 里的几何没转——这里乘回去（半圈乘两次是原样）
      local vk, vb = string.match(p.Name, "^V_(.-)__(.+)$")
      if p:IsA("MeshPart") and vk then
        mk, mp = "veh/" .. vk, p.Name
        turn = true
      end
      table.insert(out.parts, string.format('{"s":"%s","z":[%s,%s,%s],"c":[%s],"k":[%d,%d,%d],"m":"%s","t":%s%s}', shape,
        num(p.Size.X), num(p.Size.Y), num(p.Size.Z), cfStr(cf, turn), math.floor(col.R * 255), math.floor(col.G * 255), math.floor(col.B * 255),
        p.Material.Name, num(math.max(p.Transparency, p.LocalTransparencyModifier)), (p:IsA("MeshPart") and mk) and string.format(',"mk":"%s","mp":"%s"', mk, mp) or ""))
      local _ = vb
    end
  end
  for _, L in ipairs(cur2.b.lights) do
    local pos = hull:PointToObjectSpace(L.part.Position)
    local col = L.L.Color
    table.insert(out.lights, string.format('{"p":[%s,%s,%s],"k":[%d,%d,%d],"r":%s,"b":%s,"role":"%s"}', num(pos.X), num(pos.Y), num(pos.Z),
      math.floor(col.R * 255), math.floor(col.G * 255), math.floor(col.B * 255), num(L.L.Range), num(L.L.Enabled and L.L.Brightness or 0), L.role or ""))
  end
  -- 屏幕上的界面：自己按 UDim2 排（模拟器不算 SurfaceGui 里的绝对位置）
  local function c3(c) return string.format("[%d,%d,%d]", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255)) end
  local function guiNodes(o, px, py, pw, ph, acc, vis)
    for _, ch in ipairs(o:GetChildren()) do
      if ch:IsA("GuiObject") then
        local sz, pos, ap = ch.Size, ch.Position, ch.AnchorPoint
        local w = sz.X.Scale * pw + sz.X.Offset
        local h = sz.Y.Scale * ph + sz.Y.Offset
        local x = px + pos.X.Scale * pw + pos.X.Offset - ap.X * w
        local y = py + pos.Y.Scale * ph + pos.Y.Offset - ap.Y * h
        local v = vis and ch.Visible
        local round = ch:FindFirstChildOfClass("UICorner") ~= nil and ch:FindFirstChildOfClass("UICorner").CornerRadius.Scale >= 0.3
        local st = ch:FindFirstChildOfClass("UIStroke")
        local txt = ch:IsA("TextLabel") and ch.Text or nil
        local g = ch:FindFirstChildOfClass("UIGradient")
        local bg = ch.BackgroundColor3
        if g then
          local ok, kp = pcall(function() return g.Color.Keypoints end)
          if ok and kp and #kp > 0 then bg = kp[#kp].Value end
        end
        table.insert(acc, string.format('{"x":%s,"y":%s,"w":%s,"h":%s,"v":%s,"bg":%s,"bt":%s,"rot":%s,"round":%s%s%s}', num(x), num(y), num(w), num(h),
          tostring(v), c3(bg), num(ch.BackgroundTransparency), num(ch.Rotation), tostring(round),
          st and string.format(',"st":%s,"stw":%s', c3(st.Color), num(st.Thickness)) or "",
          txt and txt ~= "" and string.format(',"text":"%s","tc":%s,"ts":%s,"al":"%s","bold":%s', (txt:gsub('[\\"]', ''):gsub('%c', ' ')), c3(ch.TextColor3), num(ch.TextSize), ch.TextXAlignment.Name, tostring(ch.Font == Enum.Font.GothamBold)) or ""))
        guiNodes(ch, x, y, w, h, acc, v)
      end
    end
  end
  for _, s in ipairs(cur2.b.screens) do
    local acc = {}
    local pw, ph = s.px.X, s.px.Y
    guiNodes(s.gui, 0, 0, pw, ph, acc, true)
    table.insert(out.screens, string.format('{"page":"%s","z":[%s,%s],"c":[%s],"pw":%s,"ph":%s,"gui":[%s]}', s.page, num(s.part.Size.X), num(s.part.Size.Y), cfStr(s.part.CFrame),
      num(pw), num(ph), table.concat(acc, ",")))
  end
  for name, cf in pairs(dumpCams or {}) do
    table.insert(out.cams, string.format('{"name":"%s","c":[%s],"fov":%s}', name, cfStr(cf), num(cam.FieldOfView)))
  end
  local f = io.open(path, "w")
  f:write('{"kind":"' .. (cur2.spec.air and "air" or "veh") .. '","parts":[' .. table.concat(out.parts, ",\n") .. '],\n"lights":[' .. table.concat(out.lights, ",") .. '],\n"screens":[' .. table.concat(out.screens, ",") .. '],\n"cams":[' .. table.concat(out.cams, ",") .. ']}')
  f:close()
  print("  写出 " .. path .. "（" .. #out.parts .. " 个零件）")
end
