-- 全面大战场——烘焙地形（用户 11-28 夜「然后卡顿问题你给他想办法解决」）
--   雪山图开服前只写两边基地一带，其余四千七百多块起伏地块开服以后在后台写十几二十分钟：服务器一直占着、客户端一直在重建地形网格，
--   没写到的地方是一块块垫底的平地。把整张地形提前写好、跟地点文件一起存下来，开服就一块都不用写（World.terrain 对 Terrain 的属性 Baked）。
--
--   用法：在 Studio「编辑」模式（不要点「开始」）打开「视图 → 命令栏」，粘贴这一行、回车：
--       require(game.ServerScriptService.Main.TerrainBake)()
--   Output 里每 5 秒报一次进度，做完写「烘焙完了」（几分钟，这期间 Studio 会有点卡），然后按 Ctrl + S 存档（地点文件会大一些）。
--   之后换脚本请用 ScriptsUpdate.rbxmx（只换脚本，烘好的地形留着）；地形算法改了（MapSnow 的 TERRAIN_VER 换了）开服会在 Output 里提示再烘一次
return function(mapId)
  local RunService = game:GetService("RunService")
  local okR, running = pcall(function() return RunService:IsRunning() end)
  if okR and running then
    warn("[烘焙地形] 游戏正在跑（点了「开始」）：先停止，在编辑模式的命令栏里跑")
    return
  end
  local World = require(script.Parent:WaitForChild("World"))
  mapId = mapId or "snow"
  print("[烘焙地形] 开始：" .. mapId .. "（要几分钟，每 5 秒报一次进度；做完会说「烘焙完了」）")
  -- 烘焙这一大片地形不进撤销记录（Ctrl + Z 撤不回整张图，记着反而占内存）；做完重新打开、记一笔，Studio 知道地点改了要存
  local CHS = game:GetService("ChangeHistoryService")
  local chsOff = pcall(function() CHS:SetEnabled(false) end)
  local ok, n, chunks, secs = pcall(World.bake, mapId)
  if chsOff then
    pcall(function() CHS:SetEnabled(true) end)
    pcall(function() CHS:SetWaypoint("烘焙地形") end)
  end
  if not ok then
    warn("[烘焙地形] 没做完：" .. tostring(n) .. "（地形可能只写了一部分：不要存档，重新打开地点文件再跑一次）")
    return
  end
  print(string.format("[烘焙地形] 烘焙完了：%s，%d 块起伏地形，用了 %.0f 秒。按 Ctrl + S 存档（地点文件会大一些）；之后开服不再写地形",
    tostring(workspace.Terrain:GetAttribute("Baked")), chunks or 0, secs or 0))
end
