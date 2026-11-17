-- Roblox全面大战场——导入的原模型摆放时要补回的半圈（服务器、客户端共用）
--   Studio「导入 3D」导入 GLB 时，Roblox 把每一块网格在它自己的坐标里绕 Y 轴转了 180°：文件里的顶点 (x, y, z) 存成 (−x, y, −z)，块的中心不变。
--   用户截图（挂载界面的歼-35）：主翼跑到了平尾的位置、平尾跑到主翼的位置、座舱盖跑到两个垂尾中间、机头成了一根细尖——每一块各自掉了个头；
--   按「每块绕自己中心转半圈」把 models/air/j31.glb 画出来和截图一模一样。坦克的车体、炮塔也是前后反的（炮管前后对称，才不显眼）。
--   别人也碰到过同样的事：https://github.com/LiamTheMo/RBLX-Flintborn/pull/43（顶点 (x, y, z) 存成 (−x, y, −z)，没有镜像）
-- 所以摆每一块导入的零件时右乘 TURN（绕这块自己的中心再转半圈），显示出来就和 GLB 文件里一样。
--   开局用内嵌数据现生成的网格（EditableMesh：瞄准镜、第一人称 M4）没被转过，不乘。
--   以后 Roblox 改了导入、模型又反了：ReplicatedStorage 上加个布尔属性 ImportTurn = false 就不补
local RS = game:GetService("ReplicatedStorage")
local skip = RS:GetAttribute("ImportTurn") == false
return { TURN = skip and CFrame.new() or CFrame.Angles(0, math.pi, 0) }
