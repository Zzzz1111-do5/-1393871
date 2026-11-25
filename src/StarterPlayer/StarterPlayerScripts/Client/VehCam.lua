-- 全面大战场（客户端）——载具的追尾镜头（用户 11-20：「这个游戏目前所有的载具操控都不够 3A，你用虚幻引擎 5 的水平全面升级」）
--   照 UE5 的弹簧臂（SpringArm：CameraLag / CameraRotationLag / 碰撞探测）做，开车、开船、开直升机共用：
--   · 跟随点有惯性：车身上下颠、急停急转时，镜头不是死钉在车上——用车速预测、再用临界阻尼弹簧追上，
--     匀速开时不落后，颠簸、刹车、撞停时车在画面里先晃出去一点再被镜头接住（有重量感）
--   · 加速度推拉：起步镜头往后坠、刹车往前冲、转弯往外甩、落地往下沉（有上限、平滑）
--   · 臂长碰到山坡、房子：一下缩近、慢慢放回（不跳）
--   · 路面颠簸的细抖（速度 × 路面粗糙程度）、发动机的细微震动；大的冲击（落地、撞车、开炮）走 G.shake
--   · 镜头跟着车身侧倾歪一点（两成）；越快视野越宽
--   G.vehCam(o) → 镜头 CFrame（没加细抖的，用来算准星）、细抖（乘在后面）、视野
local VehCam = {}

function VehCam.init(G)
  local V = Vector3.new
  local S = {}   -- 每个用的地方一份（key）

  -- 临界阻尼弹簧：x 往 target 走（w 越大越快）
  local function spring(x, v, target, w, dt)
    local n = math.max(1, math.ceil(dt / (1 / 120)))
    local h = dt / n
    for _ = 1, n do
      local a = (target - x) * (w * w) - v * (2 * w)
      v += a * h
      x += v * h
    end
    return x, v
  end

  function G.vehCamReset(key) S[key] = nil end

  -- o：key, pivot（镜头绕着转的点）, dir（镜头朝向，只取旋转）, dist（臂长）, up（往上抬）, vel（车的速度 Vector3）, dt,
  --   rough（路面颠簸 0～2）, speedK（速度比例 0～1.3）, up3（车身的「上」，镜头跟着歪两成；不给就不歪）, params（镜头不能钻进去的东西）,
  --   fov0（基础视野）, fovK（全速多加几度）, pushK（加速度推镜头的比例）, maxPush, follow（跟随弹簧快慢）, minDist
  function G.vehCam(o)
    local dt = math.clamp(o.dt or 1 / 60, 1 / 240, 0.1)
    local s = S[o.key]
    local pivot = o.pivot
    local vel = o.vel or V()
    if not s or (s.p - pivot).Magnitude > 60 then   -- 第一次 / 被挪走了：直接到位
      s = { p = pivot, pv = V(), lv = vel, acc = V(), push = V(), len = o.dist, fov = o.fov0 or 70, t = 0 }
      S[o.key] = s
    end
    s.t += dt
    -- 跟随点：先按车速往前挪（匀速时不落后），再用弹簧追真正的位置（颠簸、急停时有一点惯性）
    s.p += vel * dt
    local w = o.follow or 9
    local px, pvx = spring(s.p.X, s.pv.X, pivot.X, w * 1.4, dt)
    local py, pvy = spring(s.p.Y, s.pv.Y, pivot.Y, w, dt)
    local pz, pvz = spring(s.p.Z, s.pv.Z, pivot.Z, w * 1.4, dt)
    s.p, s.pv = V(px, py, pz), V(pvx, pvy, pvz)
    local lag = s.p - pivot
    local maxLag = o.maxLag or 2.5
    if lag.Magnitude > maxLag then s.p = pivot + lag.Unit * maxLag end
    -- 加速度推拉：起步往后坠、刹车往前冲、转弯往外甩、落地往下沉
    local acc = (vel - s.lv) / dt
    s.lv = vel
    if acc.Magnitude > 400 then acc = acc.Unit * 400 end   -- 瞬移、刚上车那一下不算
    s.acc = s.acc:Lerp(acc, 1 - math.exp(-dt * 6))
    local push = -s.acc * (o.pushK or 0.02)
    local mp = o.maxPush or 2.2
    if push.Magnitude > mp then push = push.Unit * mp end
    s.push = s.push:Lerp(push, 1 - math.exp(-dt * 5))
    -- 臂：从跟随点往后、往上；碰到东西一下缩近、慢慢放回
    local dir = o.dir
    local want = dir:VectorToWorldSpace(V(0, 0, o.dist)) + V(0, o.up or 0, 0)
    local base = s.p + s.push * 0.6
    local len = o.dist
    if o.params and want.Magnitude > 1 then
      local hit = workspace:Raycast(base, want, o.params)
      if hit then len = math.max(o.minDist or 4, (hit.Position - base).Magnitude - 1.5) * o.dist / want.Magnitude end
    end
    if len < s.len then s.len += (len - s.len) * (1 - math.exp(-dt * 22)) else s.len += (len - s.len) * (1 - math.exp(-dt * 2.5)) end
    local camPos = base + want * (s.len / o.dist) + s.push * 0.4
    -- 歪：世界的「上」往车身的「上」靠两成
    local upV = V(0, 1, 0)
    if o.up3 then
      local u = V(0, 1, 0):Lerp(o.up3, 0.2)
      if u.Magnitude > 0.1 then upV = u.Unit end
    end
    local look = dir.LookVector
    local cf = CFrame.lookAt(camPos, camPos + look, upV)
    -- 细抖：路面颠簸（低频的晃 + 高频的抖）、发动机的细微震动
    local sk = math.clamp(o.speedK or 0, 0, 1.3)
    local r = (o.rough or 0.6) * sk
    local t = s.t
    local aLo = 0.0016 * r
    local aHi = 0.0011 * r + 0.00025
    local shake = CFrame.Angles(math.noise(t * 5.3, 1.7) * aLo + math.noise(t * 23, 4.4) * aHi, math.noise(t * 4.7, 8.1) * aLo * 0.6 + math.noise(t * 21, 2.2) * aHi * 0.6,
      math.noise(t * 6.1, 5.5) * aLo * 0.8)
    -- 视野：越快越宽
    local fovT = (o.fov0 or 70) + (o.fovK or 6) * math.clamp(sk, 0, 1.2)
    s.fov += (fovT - s.fov) * (1 - math.exp(-dt * 3))
    s.cf = cf
    return cf, shake, s.fov
  end
  G.vehCamState = function(key) return S[key] end   -- 测试用
end

return VehCam
