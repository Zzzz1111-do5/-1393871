-- 把这个项目用到的 Luau 写法转成 Lua 5.4 能跑的（模拟测试用；只在加载脚本时转，源码不动）：
--   复合赋值 a += b、a -= b、a *= b、a /= b、a //= b、a %= b、a ^= b、a ..= b → a = a + (b)
-- 先分词（跳过字符串、注释），往回找赋值左边（名字 / .名字 / [下标] / (调用)），往前按 Lua 表达式规则找右边的结尾
-- （同一行可能接着下一句：`sL += w.dy nL += 1`，不能按行切）
local L = {}

local KW = {}
for w in ("and break do else elseif end false for function goto if in local nil not or repeat return then true until while continue"):gmatch("%S+") do KW[w] = true end

local OPS = { "...", "..=", "//=", "..", "//", "==", "~=", "<=", ">=", "+=", "-=", "*=", "/=", "%=", "^=", "::", "->" }

local function tokenize(s)
  local toks, i, n = {}, 1, #s
  local function push(t, a, b) toks[#toks + 1] = { t = t, v = s:sub(a, b), s = a, e = b } end
  while i <= n do
    local c = s:sub(i, i)
    if c:match("%s") then
      i = i + 1
    elseif s:sub(i, i + 1) == "--" then
      local eq = s:match("^%[(=*)%[", i + 2)
      if eq then
        local close = s:find("]" .. eq .. "]", i, true)
        i = (close or n) + #eq + 2
      else
        local nl = s:find("\n", i, true)
        i = (nl or n) + 1
      end
    elseif c == "'" or c == '"' then
      local j = i + 1
      while j <= n do
        local d = s:sub(j, j)
        if d == "\\" then j = j + 2
        elseif d == c then break
        else j = j + 1 end
      end
      push("str", i, j)
      i = j + 1
    elseif c == "[" and s:match("^%[=*%[", i) then
      local eq = s:match("^%[(=*)%[", i)
      local close = s:find("]" .. eq .. "]", i, true)
      local e = (close or n) + #eq + 1
      push("str", i, e)
      i = e + 1
    elseif c:match("%d") or (c == "." and s:sub(i + 1, i + 1):match("%d")) then
      local j = i
      if s:sub(i, i + 1):lower() == "0x" or s:sub(i, i + 1):lower() == "0b" then
        j = i + 2
        while j <= n and s:sub(j, j):match("[%x_]") do j = j + 1 end
      else
        while j <= n do
          local d = s:sub(j, j)
          if d:match("[%d_%.]") then j = j + 1
          elseif d:match("[eE]") then
            j = j + 1
            if s:sub(j, j):match("[%+%-]") then j = j + 1 end
          else break end
        end
      end
      push("num", i, j - 1)
      i = j
    elseif c:match("[%a_]") then
      local j = i
      while j <= n and s:sub(j, j):match("[%w_]") do j = j + 1 end
      local w = s:sub(i, j - 1)
      push(KW[w] and "kw" or "name", i, j - 1)
      i = j
    else
      local got
      for _, op in ipairs(OPS) do
        if s:sub(i, i + #op - 1) == op then got = op break end
      end
      got = got or c
      push("op", i, i + #got - 1)
      i = i + #got
    end
  end
  return toks
end

local BIN = {}
for w in ("+ - * / // % ^ .. == ~= < <= > >= and or"):gmatch("%S+") do BIN[w] = true end
local UN = { ["not"] = true, ["-"] = true, ["#"] = true, ["~"] = true }
local OPEN = { ["("] = ")", ["["] = "]", ["{"] = "}" }
local BLOCK = { ["function"] = true, ["do"] = true, ["then"] = true, ["repeat"] = true }

-- 从 i 开始跳过一对括号，返回右括号后面的位置
local function skipPair(toks, i)
  local open = toks[i].v
  local close = OPEN[open]
  local depth = 0
  while toks[i] do
    local v = toks[i].v
    if toks[i].t == "op" and v == open then depth = depth + 1
    elseif toks[i].t == "op" and v == close then
      depth = depth - 1
      if depth == 0 then return i + 1 end
    end
    i = i + 1
  end
  error("括号不配对")
end
-- 从 function 开始跳到配对的 end 后面
local function skipFunction(toks, i)
  local depth = 0
  while toks[i] do
    local t = toks[i]
    if t.t == "kw" then
      if t.v == "function" or t.v == "if" or t.v == "do" or t.v == "repeat" then depth = depth + 1
      elseif t.v == "while" or t.v == "for" then -- 它们的 do 会再加一层，这里不加
      elseif t.v == "end" or t.v == "until" then
        depth = depth - 1
        if depth == 0 then return i + 1 end
      end
    end
    i = i + 1
  end
  error("function 没有配对的 end")
end

local parseExpr
local function parseSuffixes(toks, i)
  while toks[i] do
    local t = toks[i]
    if t.t == "op" and t.v == "." then
      i = i + 2
    elseif t.t == "op" and (t.v == "[" or t.v == "(" or t.v == "{") then
      i = skipPair(toks, i)
    elseif t.t == "op" and t.v == ":" then
      i = i + 2
    elseif t.t == "str" then
      i = i + 1
    else
      break
    end
  end
  return i
end
local function parseSimple(toks, i)
  local t = toks[i]
  if not t then error("表达式不完整") end
  if t.t == "num" or (t.t == "kw" and (t.v == "nil" or t.v == "true" or t.v == "false")) or (t.t == "op" and t.v == "...") then return i + 1 end
  if t.t == "str" then return parseSuffixes(toks, i + 1) end
  if t.t == "op" and t.v == "{" then return skipPair(toks, i) end
  if t.t == "kw" and t.v == "function" then return skipFunction(toks, i) end
  if t.t == "name" then return parseSuffixes(toks, i + 1) end
  if t.t == "op" and t.v == "(" then return parseSuffixes(toks, skipPair(toks, i)) end
  error("看不懂的表达式开头：" .. t.v)
end
local function parseUnary(toks, i)
  while toks[i] and UN[toks[i].v] and toks[i].t ~= "str" do i = i + 1 end
  return parseSimple(toks, i)
end
parseExpr = function(toks, i)
  i = parseUnary(toks, i)
  while toks[i] and BIN[toks[i].v] and toks[i].t ~= "str" and toks[i].t ~= "name" do
    i = parseUnary(toks, i + 1)
  end
  return i
end

-- 从 j 往回找赋值左边的开头（名字、.名字、:名字、[下标]、(调用) 连起来的那一串）
local function lhsStart(toks, j)
  local start
  while j >= 1 do
    local t = toks[j]
    if t.t == "op" and (t.v == "]" or t.v == ")") then
      local close, open = t.v, (t.v == "]") and "[" or "("
      local depth = 0
      while j >= 1 do
        local v = toks[j]
        if v.t == "op" and v.v == close then depth = depth + 1
        elseif v.t == "op" and v.v == open then
          depth = depth - 1
          if depth == 0 then break end
        end
        j = j - 1
      end
      start = j
      j = j - 1
    elseif t.t == "name" then
      start = j
      local p = toks[j - 1]
      if p and p.t == "op" and (p.v == "." or p.v == ":") then j = j - 2 else break end
    else
      break
    end
  end
  return start
end

function L.compile(src, chunk)
  local toks = tokenize(src)
  local edits = {}
  for k, t in ipairs(toks) do
    if t.t == "op" and #t.v >= 2 and t.v:sub(-1) == "=" and t.v ~= "==" and t.v ~= "~=" and t.v ~= "<=" and t.v ~= ">=" then
      local op = t.v:sub(1, -2)
      local a = lhsStart(toks, k - 1)
      if not a then error((chunk or "?") .. "：复合赋值左边看不懂（第 " .. t.s .. " 个字符）") end
      local ok, e = pcall(parseExpr, toks, k + 1)
      if not ok then error((chunk or "?") .. "：复合赋值右边看不懂（第 " .. t.s .. " 个字符）：" .. tostring(e)) end
      local lhs = src:sub(toks[a].s, toks[k - 1].e)
      local rhsS, rhsE = toks[k + 1].s, toks[e - 1].e
      edits[#edits + 1] = { s = t.s, e = rhsE, text = "= " .. lhs .. " " .. op .. " (" .. src:sub(rhsS, rhsE) .. ")" }
    end
  end
  for i = #edits, 1, -1 do
    local d = edits[i]
    src = src:sub(1, d.s - 1) .. d.text .. src:sub(d.e + 1)
  end
  return src, #edits
end

L.tokenize = tokenize
return L
