-- 开飞机的提示音、告警音（用户 11-24：「把开飞机的各种 ui 声音做成战雷」）
--   · 红外弹（seeker = "ir"）的导引头声：没锁上是低沉发毛的嗡嗡声（「咕噜」）；锁定进度往上走，音调跟着升；锁上是尖的长音；
--     锁着但目标出了离轴角（菱形变黄）又回到嗡嗡
--   · 雷达弹：锁的过程一下一下轻的「嘀」，锁上「嘀嘀」两声；空对地弹、制导炸弹锁上「嘀」一声
--   · 导弹来袭（服务器的 rwr）：急促的「嘀嘀嘀」；被敌机雷达锁着（服务器的 rwrLock，A 加的）：一下一下高的「嘀」、锁上两短一停；失速：喇叭一样的「嘟——嘟——」；拉起（离地近还在往下掉）：高低两个音来回换；
--     油不多：隔几秒「叮——咚」；发动机熄火：隔一会儿低沉的「当」
--   · 放热诱弹「嘭嘭」两声；打中敌人「叮」；打下来往上走的两声；自己挨打金属的「当」；起落架收放时液压的嗡嗡、到位「咔」一声
--   音源：SoundLib 的 1000 赫兹纯音（toneSine 正弦、toneSquare 方波、toneSaw 锯齿波），PlaybackSpeed 调音高（1 = 1000 赫兹）；
--     哪个没载上那几样就不响（屏幕上的告警字照旧）
--   Fly.lua 每帧调 G.airAudioStep(dt, a)，下飞机调 G.airAudioOff()，一次性的事调 G.airAudioEvent(名字)
local M = {}

function M.init(G)
  local SS = game:GetService("SoundService")
  local clamp = math.clamp
  local EXP = "rbxasset://sounds/impact_explosion_03.mp3"
  local TICK = "rbxasset://sounds/volume_slider.ogg"
  local THUD = "rbxasset://sounds/action_jump_land.mp3"

  local voices = {}   -- [名字] = 循环的 Sound（音量、音高每帧调）
  local function voice(name, key)
    local v = voices[name]
    if v and v.Parent then return v end
    if not G.realLoop then return nil end
    v = G.realLoop(key, SS)
    if not v then return nil end
    v.Volume = 0
    v.Name = "AirAudio_" .. name
    voices[name] = v
    return v
  end
  local function effect(v, cls, props)
    local e = v:FindFirstChildOfClass(cls)
    if not e then
      e = Instance.new(cls)
      e.Parent = v
    end
    for k, x in pairs(props) do e[k] = x end
    return e
  end
  -- 一个声部：音量、音高（赫兹）；返回 Sound（没载上 nil）
  local function set(name, key, vol, hz)
    local v = voice(name, key)
    if not v then return nil end
    v.Volume = vol
    if hz then v.PlaybackSpeed = clamp(hz / 1000, 0.05, 20) end
    return v
  end
  local function silence()
    for _, v in pairs(voices) do v.Volume = 0 end
  end

  -- 短促的「嘀」：排进队列，每帧取正在响的那一个（同一时间只响一个，后来的高过先来的就用后来的）
  local queue = {}
  local function beep(hz, dur, vol, delay)
    local t0 = os.clock() + (delay or 0)
    table.insert(queue, { t0 = t0, t1 = t0 + dur, hz = hz, vol = vol })
  end
  local function shot(L)   -- 一次性的叠层声音（Fx.lua 的 makeSound）
    if G.makeSound then pcall(G.makeSound, L, SS, { dry = false }) end
  end
  local function realShot(key, speed, vol)
    local id, cfg = nil, nil
    if G.realSound then id, cfg = G.realSound(key) end
    if not id then return false end
    local s = Instance.new("Sound")
    s.SoundId = id
    s.Volume = (cfg and cfg.vol or 1) * vol
    s.PlaybackSpeed = speed
    s.Parent = SS
    s:Play()
    game:GetService("Debris"):AddItem(s, ((cfg and cfg.len) or 3) / speed + 0.5)
    return true
  end

  local S = { hp = nil, gear = nil, lockWas = false, rTick = 0, chimeT = 0, outT = 0 }

  function G.airAudioOff()
    silence()
    queue = {}
    S.hp, S.gear, S.lockWas = nil, nil, false
  end

  function G.airAudioEvent(name)
    if name == "flare" then   -- 热诱弹：两声闷的「嘭」
      for i = 0, 1 do
        shot({ id = EXP, vol = 0.32, s = { 2.3, 2.7 }, reg = { 0.02, 0.22 }, eq = { -4, 2, 2 } })
        task.delay(0.07 + i * 0.07, function() shot({ id = TICK, vol = 0.35, s = { 0.9, 1.0 } }) end)
      end
    elseif name == "hit" then   -- 打中敌机：清脆的「叮」
      if not realShot("metalHit", 1.6, 0.32) then shot({ id = TICK, vol = 0.6, s = { 3.0, 3.1 } }) end
    elseif name == "kill" then   -- 打下来：往上走的两声
      beep(1320, 0.09, 0.30)
      beep(1760, 0.18, 0.30, 0.10)
    elseif name == "damaged" then   -- 自己挨打：金属的「当」+ 一声闷响
      if not realShot("metalHit", 0.85, 0.9) then shot({ id = TICK, vol = 0.9, s = { 0.6, 0.65 } }) end
      shot({ id = EXP, vol = 0.35, s = { 1.5, 1.7 }, reg = { 0.0, 0.25 }, eq = { 6, 0, -10 } })
    end
  end

  function G.airAudioStep(dt, a)
    if not a or not a.on then silence() return end
    local t = os.clock()
    local w = a.w
    local isIR = w and w.kind == "aam" and w.seeker ~= "radar"
    local isRadar = w and w.kind == "aam" and w.seeker == "radar"
    local guided = w and (w.kind == "agm" or (w.kind == "bomb" and w.guided))
    local prog = (a.hasTgt and w and w.lockTime) and clamp(a.lockT / w.lockTime, 0, 1) or 0
    local locked = a.locked and not a.out
    local busy = a.rwr and 0.5 or 1   -- 导弹来袭时别的声音让一让

    -- ① 红外导引头：嗡嗡（方波，压掉高音、加点失真，音量一抖一抖）→ 锁上尖的长音（正弦）
    -- 照战雷（用户 11-28 夜「以及各种音效」）：导引头开着、小圈里没目标——低低的、轻的嗡嗡（搜索）；目标进了小圈（截获中）——
    --   一下子响起来、变尖，越接近锁上越尖；锁上——尖的长音。原来选上红外弹就一直是响的嗡嗡（有没有目标一个样）
    local growlV, lockV, gHz = 0, 0, 320
    if isIR then
      if locked then
        lockV = 0.30 * busy
      elseif a.hasTgt then
        growlV = 0.27 * busy
        gHz = 380 + 300 * prog + (a.out and 120 or 0)
      else
        growlV = 0.09 * busy
        gHz = 240
      end
    end
    local g = set("growl", "toneSquare", growlV, gHz + math.sin(t * 31) * 7 + math.sin(t * 13) * 5)
    if g then
      effect(g, "EqualizerSoundEffect", { LowGain = 4, MidGain = 0, HighGain = -14 })
      effect(g, "DistortionSoundEffect", { Level = 0.55 })
      effect(g, "TremoloSoundEffect", { Depth = 0.55, Duty = 0.5, Frequency = 10 })
    end
    set("lock", "toneSine", lockV, 1450 + math.sin(t * 9) * 6)

    -- ② 雷达弹：锁的过程每 0.3 秒一下轻「嘀」；锁上「嘀嘀」；空对地 / 制导炸弹锁上「嘀」
    if isRadar and a.hasTgt and not locked and t >= S.rTick then
      S.rTick = t + 0.3
      beep(900, 0.04, 0.13 * busy)
    end
    if locked and not S.lockWas then
      if isRadar then
        beep(1250, 0.07, 0.30)
        beep(1250, 0.07, 0.30, 0.11)
      elseif guided then
        beep(1000, 0.12, 0.26)
      end
    end
    S.lockWas = locked == true

    -- ③ 导弹来袭：急促的「嘀嘀嘀」（每秒七下半）
    set("rwr", "toneSine", (a.rwr and ((t * 7.5) % 1 < 0.5)) and 0.34 or 0, 1150)
    -- ③½ 被敌机雷达锁着（A 11-24 加的：对方雷达弹锁着你，服务器转告 rwrLock）：锁定中每 0.6 秒一下高的「嘀」，锁上了「嘀嘀」两短一停；
    --   导弹来袭时让给上面那个
    if a.rwrLock and not a.rwr and t >= (S.lkTick or 0) then
      S.lkTick = t + 0.6
      if a.rwrFull then
        beep(1600, 0.06, 0.26)
        beep(1600, 0.06, 0.26, 0.11)
      else
        beep(1600, 0.08, 0.2)
      end
    end

    -- ④ 失速：锯齿波「嘟——嘟——」（每秒两下半）
    local stallV = (a.stall and ((t * 2.5) % 1 < 0.62)) and 0.20 * busy or 0
    local sv = set("stall", "toneSaw", stallV, 440)
    if sv then effect(sv, "EqualizerSoundEffect", { LowGain = 2, MidGain = 0, HighGain = -10 }) end

    -- ⑤ 拉起：两个音来回换（像近地告警）
    set("pull", "toneSine", a.pullup and 0.28 * busy or 0, ((t * 5) % 1 < 0.5) and 650 or 950)

    -- ⑥ 油不多 / 熄火：隔一会儿响一下
    if (a.bingo or a.flameout) and t >= S.chimeT then
      if a.flameout then
        S.chimeT = t + 2.5
        beep(420, 0.45, 0.22 * busy)
      else
        S.chimeT = t + 5
        beep(880, 0.18, 0.18 * busy)
        beep(660, 0.26, 0.18 * busy, 0.2)
      end
    end

    -- ⑦ 起落架：收放时液压的嗡嗡，到位「咔」一声
    local gear = a.gear
    if gear then
      local moving = gear > 0.02 and gear < 0.98
      local hv = set("hyd", "toneSquare", moving and 0.045 or 0, 150 + (gear * 25))
      if hv then
        effect(hv, "EqualizerSoundEffect", { LowGain = 6, MidGain = -6, HighGain = -30 })
        effect(hv, "DistortionSoundEffect", { Level = 0.4 })
      end
      if S.gear and ((S.gear < 0.98 and gear >= 0.98) or (S.gear > 0.02 and gear <= 0.02)) then
        shot({ id = THUD, vol = 0.55, s = { 0.72, 0.78 }, eq = { 4, 0, -6 } })
        shot({ id = TICK, vol = 0.5, s = { 0.55, 0.6 } })
      end
      S.gear = gear
    end

    -- ⑧ 自己挨打（血掉了）
    if a.hp then
      if S.hp and a.hp < S.hp - 0.004 then G.airAudioEvent("damaged") end
      S.hp = a.hp
    end

    -- 「嘀」的队列
    local bv, bh = 0, 1000
    for i = #queue, 1, -1 do
      local q = queue[i]
      if t >= q.t1 then
        table.remove(queue, i)
      elseif t >= q.t0 then
        bv, bh = math.max(bv, q.vol), q.hz
      end
    end
    set("beep", "toneSine", bv, bh)
  end
end

return M
