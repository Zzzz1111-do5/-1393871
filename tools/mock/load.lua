-- 按 Rojo 的目录约定（和 tools/build.luau 一样）把 src/ 装进模拟的 DataModel：
--   src/<服务名>/... ；目录 = Folder；X.lua = ModuleScript；X.server.lua = Script；X.client.lua = LocalScript；
--   目录里有 init.server.lua / init.client.lua / init.lua 时这个目录本身就是那个脚本
-- 返回：服务器脚本列表、StarterPlayerScripts 里的客户端脚本（玩家进服时复制一份跑）
return function(R, SRC)
  local L = dofile(MOCK_DIR .. "/luau.lua")
  R.transform = function(src, path)
    local out = L.compile(src, path)
    return out
  end
  local function ls(dir)
    local p = io.popen('ls -1 "' .. dir .. '" 2>/dev/null')
    local out = {}
    for f in p:lines() do out[#out + 1] = f end
    p:close()
    table.sort(out)
    return out
  end
  local function isDir(path)
    local p = io.popen('[ -d "' .. path .. '" ] && echo d')
    local r = p:read("a")
    p:close()
    return r:match("d") ~= nil
  end
  local function kindOf(file)
    if file:match("%.server%.lua$") then return "Script", (file:gsub("%.server%.lua$", "")) end
    if file:match("%.client%.lua$") then return "LocalScript", (file:gsub("%.client%.lua$", "")) end
    if file:match("%.lua$") then return "ModuleScript", (file:gsub("%.lua$", "")) end
  end
  local scripts = { server = {}, client = {} }
  local function build(dir, parent, svc)
    for _, name in ipairs(ls(dir)) do
      local path = dir .. "/" .. name
      if isDir(path) then
        local inst
        for _, init in ipairs({ "init.server.lua", "init.client.lua", "init.lua" }) do
          local f = io.open(path .. "/" .. init)
          if f then
            f:close()
            local cls = kindOf(init)
            inst = R.scriptFrom(cls, name, path .. "/" .. init, nil)
            if cls == "Script" then table.insert(scripts.server, inst) end
            if cls == "LocalScript" then table.insert(scripts.client, inst) end
            break
          end
        end
        if not inst then
          inst = parent:FindFirstChild(name)
          if not inst then
            inst = R.make("Folder")
            inst._p.Name = name
          end
        end
        inst.Parent = parent
        build(path, inst, svc)
      elseif not name:match("^init%.") then
        local cls, base = kindOf(name)
        if cls then
          local s = R.scriptFrom(cls, base, path, parent)
          if cls == "Script" then table.insert(scripts.server, s) end
          if cls == "LocalScript" then table.insert(scripts.client, s) end
        end
      end
    end
  end
  for _, svc in ipairs(ls(SRC)) do
    local root = R.services[svc] or R.game:GetService(svc)
    build(SRC .. "/" .. svc, root, svc)
  end
  return scripts
end
