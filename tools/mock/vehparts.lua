-- 导出零件拼的载具（没有原模型的那几辆）的零件：形状、尺寸、CFrame（Roblox 坐标，车头朝 −Z），给 tools/models/vehicons.mjs 画侧面图标
--   python3 tools/mock/run.py tools/mock/vehparts.lua out=<文件.json> [ids=ztz96,pgz07,...]
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local out = TEST_ARGS:match("out=(%S+)")
local idsArg = TEST_ARGS:match("ids=(%S+)") or "ztz96,pgz07,ld2000"
local G = T.boot()
T.runUntil(function() return G.worldReady end, 120)
local me = T.join("P1", 7701, true)
R.run(1)
local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))
-- 客户端的 VehModels（模块按实例缓存，客户端已经 require 过的这里拿到同一份）
local VM = R.require(R.services.StarterPlayer:FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client"):FindFirstChild("VehModels"))
local res = {}
for id in idsArg:gmatch("[^,]+") do
  local d = VD.get(id)
  if d then
    local M, err
    R.as("client", function()
      local ok, r = pcall(VM.build, d, "atk", nil)
      if ok then M = r else err = r end
    end)
    for _ = 1, 20 do
      if M or err then break end
      R.run(0.1)
    end
    if not M then print(id .. " 建不出来：" .. tostring(err)) end
    local parts = {}
    -- 照 View.lua stepVeh 摆零件的办法合成（车身底部中心为原点，炮塔、炮都朝正前方，轮子不转、悬挂不压）
    local CF = R.CFrame.new
    local tF = CF(M.tpiv or d.turret and d.turret.pivot or R.Vector3.new())
    local gF = tF * CF(M.gpiv or (d.gun and d.gun.pivot) or R.Vector3.new())
    local rF = M.rpiv and (tF * CF(M.rpiv)) or nil
    local rgF = (rF and M.rgpiv) and (rF * CF(M.rgpiv)) or nil
    for _, it in ipairs(M and M.parts or {}) do
      local p, grp, off = it[1], it[2], it[3]
      if p and R.base.IsA(p, "BasePart") and (p._p.Transparency or 0) < 0.95 then
        local cf
        if grp == "turret" then cf = tF * off
        elseif grp == "gun" then cf = gF * off
        elseif grp == "rws" then cf = (rF or tF) * off
        elseif grp == "rwg" then cf = (rgF or rF or tF) * off
        elseif grp == "kit" then cf = (M.kpiv and (tF * CF(M.kpiv)) or tF) * off
        elseif grp == "wheel" then
          local w = M.wheels[it[4]]
          cf = CF(w.x, w.r, w.z) * off
        elseif grp == "seg" then cf = off
        else cf = off end
        local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
        local shape = p._cls == "WedgePart" and "Wedge" or ((p._p.Shape and p._p.Shape.Name) or "Block")
        local s = p._p.Size
        parts[#parts + 1] = { shape = shape, size = { s.X, s.Y, s.Z }, cf = { x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 } }
      end
    end
    res[id] = { parts = parts }
    print(id .. "：" .. #parts .. " 个零件")
  else
    print("没有这个车型：" .. id)
  end
end
local function enc(v)
  local t = type(v)
  if t == "number" then return string.format("%.4f", v) end
  if t == "string" then return '"' .. v .. '"' end
  if t == "boolean" then return tostring(v) end
  if #v > 0 then
    local o = {}
    for i, x in ipairs(v) do o[i] = enc(x) end
    return "[" .. table.concat(o, ",") .. "]"
  end
  local o = {}
  for k, x in pairs(v) do o[#o + 1] = '"' .. k .. '":' .. enc(x) end
  return "{" .. table.concat(o, ",") .. "}"
end
if out then
  local f = assert(io.open(out, "w"))
  f:write(enc(res))
  f:close()
  print("写到 " .. out)
end
T.summary()
