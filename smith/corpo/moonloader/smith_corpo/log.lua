-- smith_corpo.log na pasta do MoonLoader.
local M = {}
local arquivo
local caminho

function M.abrir(pasta)
  caminho = pasta .. '/smith_corpo.log'
  -- Rotação simples: se passar de 2 MB, recomeça.
  local f = io.open(caminho, 'rb')
  local modo = 'a'
  if f then
    local tam = f:seek('end')
    f:close()
    if tam and tam > 2 * 1024 * 1024 then modo = 'w' end
  end
  arquivo = io.open(caminho, modo)
end

local function escrever(nivel, fmt, ...)
  local ok, txt = pcall(string.format, fmt, ...)
  if not ok then txt = tostring(fmt) end
  local linha = os.date('%Y-%m-%d %H:%M:%S') .. ' ' .. nivel .. ' ' .. txt
  if arquivo then
    arquivo:write(linha, '\n')
    arquivo:flush()
  end
  print(linha) -- também aparece em moonloader.log
end

function M.info(fmt, ...) escrever('INFO ', fmt, ...) end
function M.aviso(fmt, ...) escrever('AVISO', fmt, ...) end
function M.erro(fmt, ...) escrever('ERRO ', fmt, ...) end

function M.fechar()
  if arquivo then arquivo:close(); arquivo = nil end
end

return M
