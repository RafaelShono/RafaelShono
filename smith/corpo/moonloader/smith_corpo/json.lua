-- JSON mínimo e previsível (Lua 5.1 / LuaJIT).
-- Usamos o nosso em vez de encodeJson/decodeJson do MoonLoader para controlar:
--   * listas vazias (json.lista({}) vira [] e tabela vazia comum vira {});
--   * NaN/infinito (viram null, que o Python aceita);
--   * saída sempre em uma linha só, ASCII com escapes.
local M = {}

local MARCA_LISTA = {}
local lista_mt = { __jsonlista = MARCA_LISTA }

function M.lista(t)
  return setmetatable(t or {}, lista_mt)
end

M.null = setmetatable({}, { __tostring = function() return 'null' end })

local function eh_lista(t)
  local mt = getmetatable(t)
  if mt and mt.__jsonlista == MARCA_LISTA then return true end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  if n == 0 then return false end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true
end

local escapes = {
  ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
  ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
}

local function texto(s)
  s = s:gsub('[%c"\\\128-\255]', function(c)
    local e = escapes[c]
    if e then return e end
    -- Bytes >127 (texto do jogo em CP1252) viram \u00XX: Latin-1 é igual ao
    -- CP1252 nas letras acentuadas, então "ç" chega como "ç" no Python.
    return string.format('\\u%04x', c:byte())
  end)
  return '"' .. s .. '"'
end

local codificar

local function numero(n)
  if n ~= n or n == math.huge or n == -math.huge then return 'null' end
  if n == math.floor(n) and math.abs(n) < 1e15 then
    return string.format('%d', n)
  end
  local s = string.format('%.4f', n):gsub('0+$', ''):gsub('%.$', '')
  return s
end

codificar = function(v, profundidade)
  profundidade = profundidade or 0
  if profundidade > 32 then error('json: profundidade demais') end
  local tv = type(v)
  if v == nil or v == M.null then return 'null'
  elseif tv == 'boolean' then return v and 'true' or 'false'
  elseif tv == 'number' then return numero(v)
  elseif tv == 'string' then return texto(v)
  elseif tv == 'table' then
    local partes = {}
    if eh_lista(v) then
      for i = 1, #v do partes[i] = codificar(v[i], profundidade + 1) end
      return '[' .. table.concat(partes, ',') .. ']'
    end
    for k, x in pairs(v) do
      if type(k) == 'string' or type(k) == 'number' then
        partes[#partes + 1] = texto(tostring(k)) .. ':' .. codificar(x, profundidade + 1)
      end
    end
    return '{' .. table.concat(partes, ',') .. '}'
  end
  return 'null' -- funções, userdata: ignorados
end

M.codificar = function(v) return codificar(v, 0) end

-- Decodificador ------------------------------------------------------------

local function erro(s, i, msg) error(string.format('json: %s na posicao %d', msg, i)) end

local function pular(s, i)
  local _, f = s:find('^[ \t\r\n]*', i)
  return f + 1
end

local decodificar_valor

local function dec_texto(s, i)
  local partes = {}
  local j = i + 1
  while true do
    local c = s:sub(j, j)
    if c == '' then erro(s, j, 'texto sem fim') end
    if c == '"' then return table.concat(partes), j + 1 end
    if c == '\\' then
      local e = s:sub(j + 1, j + 1)
      local mapa = { b = '\b', f = '\f', n = '\n', r = '\r', t = '\t', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }
      if mapa[e] then
        partes[#partes + 1] = mapa[e]; j = j + 2
      elseif e == 'u' then
        local cod = tonumber(s:sub(j + 2, j + 5), 16)
        if not cod then erro(s, j, 'escape \\u invalido') end
        -- Só mantemos Latin-1; o resto vira '?'. O jogo não exibe mais que isso.
        partes[#partes + 1] = cod < 256 and string.char(cod) or '?'
        j = j + 6
      else
        erro(s, j, 'escape invalido')
      end
    else
      partes[#partes + 1] = c; j = j + 1
    end
  end
end

decodificar_valor = function(s, i, prof)
  if prof > 32 then erro(s, i, 'profundidade demais') end
  i = pular(s, i)
  local c = s:sub(i, i)
  if c == '{' then
    local t = {}
    i = pular(s, i + 1)
    if s:sub(i, i) == '}' then return t, i + 1 end
    while true do
      i = pular(s, i)
      if s:sub(i, i) ~= '"' then erro(s, i, 'chave esperada') end
      local k; k, i = dec_texto(s, i)
      i = pular(s, i)
      if s:sub(i, i) ~= ':' then erro(s, i, '":" esperado') end
      local v; v, i = decodificar_valor(s, i + 1, prof + 1)
      t[k] = v
      i = pular(s, i)
      local d = s:sub(i, i)
      if d == '}' then return t, i + 1 end
      if d ~= ',' then erro(s, i, '"," esperado') end
      i = i + 1
    end
  elseif c == '[' then
    local t = M.lista({})
    i = pular(s, i + 1)
    if s:sub(i, i) == ']' then return t, i + 1 end
    while true do
      local v; v, i = decodificar_valor(s, i, prof + 1)
      t[#t + 1] = v
      i = pular(s, i)
      local d = s:sub(i, i)
      if d == ']' then return t, i + 1 end
      if d ~= ',' then erro(s, i, '"," esperado') end
      i = i + 1
    end
  elseif c == '"' then
    return dec_texto(s, i)
  elseif s:sub(i, i + 3) == 'true' then return true, i + 4
  elseif s:sub(i, i + 4) == 'false' then return false, i + 5
  elseif s:sub(i, i + 3) == 'null' then return nil, i + 4
  else
    local num = s:match('^-?%d+%.?%d*[eE]?[-+]?%d*', i)
    if not num or num == '' then erro(s, i, 'valor inesperado') end
    local n = tonumber(num)
    if not n then erro(s, i, 'numero invalido') end
    return n, i + #num
  end
end

function M.decodificar(s)
  local v, i = decodificar_valor(s, 1, 0)
  i = pular(s, i)
  if i <= #s then erro(s, i, 'lixo depois do valor') end
  return v
end

return M
