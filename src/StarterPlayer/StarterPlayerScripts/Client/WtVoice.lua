-- Roblox全面大战场（客户端）——车组语音（用户 11-25「全部都做」⑬：战雷的「击穿！」「跳弹」「着火了」「炮长阵亡」「装填完毕」）
--   G.wtVoice(键)：一次说一句（排队最多两句，同一句 3 秒内不重复）。声音从哪来，按顺序试：
--   ① Config.WtVoice[键] 配了音频（rbxassetid://…，自己上传的录音）就放它；
--   ② 没配：用 Roblox 的文字转语音（AudioTextToSpeech，读英文——战雷默认的英文车组）；第一次用到某句时先加载好存起来
--   ③ 引擎没有文字转语音（老版本、测试台）：不出声（命中提示、损伤面板照旧写字）
--   谁调：WtHud（打出去的命中、自己挨打、换位、灭火、修好）、WtTank（装填完毕）
local RS = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local WtVoice = {}

function WtVoice.init(G)
  local Config = require(RS:WaitForChild("Config"))
  -- 每句：英文（文字转语音读）、语速（1 正常）
  local LINES = {
    pen = { "Penetration!", 1.1 }, ric = { "Ricochet!", 1.1 }, np = { "Not penetrated!", 1.1 }, kill = { "Target destroyed!", 1.05 },
    killAmmo = { "Ammo rack! Target destroyed!", 1.1 }, crit = { "Critical hit!", 1.1 }, hit = { "Hit!", 1.1 },
    hurtPen = { "We've been penetrated!", 1.15 }, hurtRic = { "Ricochet off our armor!", 1.15 }, fire = { "We're on fire!", 1.2 },
    fireOut = { "Fire's out.", 1 }, fixed = { "Repairs complete.", 1 },
    gnr = { "Gunner is down!", 1.15 }, drv = { "Driver is down!", 1.15 }, ldr = { "Loader is down!", 1.15 }, cmd = { "Commander is down!", 1.15 },
    loaded = { "Loaded!", 1.15 }, swap = { "Replacing crew member.", 1.05 }, resupply = { "Resupplying.", 1 },
    engine = { "Engine damaged!", 1.15 }, track = { "Track is broken!", 1.15 }, barrel = { "Barrel damaged!", 1.15 }, breech = { "Breech damaged!", 1.15 },
    spotted = { "We've been spotted!", 1.1 }, scout = { "Target spotted.", 1.05 },
  }
  local VCFG = (Config.WtVoice or {})
  local ttsOk = nil   -- nil 还没试、true 能用、false 没有
  local cache = {}    -- 键 → 已经加载好的 AudioTextToSpeech（或 Sound）
  local queue, busyTill, lastSaid = {}, 0, {}

  local folder = Instance.new("Folder")
  folder.Name = "WtVoice"
  folder.Parent = SoundService

  local function makeTts(key)
    local L = LINES[key]
    if not L then return nil end
    local ok, tts = pcall(function()
      local t = Instance.new("AudioTextToSpeech")
      t.Text = L[1]
      pcall(function() t.VoiceId = tostring(VCFG.voiceId or "1") end)
      pcall(function() t.Speed = L[2] or 1 end)
      pcall(function() t.Volume = VCFG.volume or 1.4 end)
      local out = Instance.new("AudioDeviceOutput")
      out.Parent = t
      local wire = Instance.new("Wire")
      wire.SourceInstance, wire.TargetInstance = t, out
      wire.Parent = t
      t.Parent = folder
      return t
    end)
    if not ok or not tts then ttsOk = false return nil end
    ttsOk = true
    task.spawn(function() pcall(function() tts:LoadAsync() end) end)
    return tts
  end
  local function makeSound(key)
    local id = VCFG[key]
    if type(id) ~= "string" or id == "" then return nil end
    local s = Instance.new("Sound")
    s.SoundId = id
    s.Volume = VCFG.volume or 1.4
    s.Parent = folder
    return s
  end
  local function get(key)
    if cache[key] ~= nil then return cache[key] or nil end
    local v = makeSound(key)
    if not v and ttsOk ~= false then v = makeTts(key) end
    cache[key] = v or false
    return v
  end
  local function say(key)
    local v = get(key)
    if not v then return end
    pcall(function()
      if v:IsA("Sound") then v:Play() else v:Play() end
    end)
  end

  function G.wtVoice(key)
    if VCFG.off or G.voiceOff or not LINES[key] then return end   -- 设置里关了车组语音
    local t = os.clock()
    if t - (lastSaid[key] or -9) < 3 then return end
    lastSaid[key] = t
    if #queue >= 2 then table.remove(queue, 1) end
    table.insert(queue, key)
  end
  G.wtVoiceTts = function() return ttsOk end   -- 测试用

  -- 一句一句说：一句约 1.3 秒（按字数估），说完再说下一句
  G.frameConn("WtVoice", function()
    local t = os.clock()
    if t < busyTill or #queue == 0 then return end
    local key = table.remove(queue, 1)
    G.try_(say, key)
    busyTill = t + 0.45 + #(LINES[key] and LINES[key][1] or "") * 0.055
  end)
end

return WtVoice
