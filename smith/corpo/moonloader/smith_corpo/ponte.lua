-- Cliente TCP não bloqueante (luasocket). Uma mensagem JSON por linha.
-- Nada aqui pode travar o frame do jogo: todo socket tem timeout 0.
local Ponte = {}
Ponte.__index = Ponte

function Ponte.nova(opcoes)
  local self = setmetatable({}, Ponte)
  self.socket = opcoes.socket
  self.json = opcoes.json
  self.log = opcoes.log
  self.host = opcoes.host or '127.0.0.1'
  self.porta = opcoes.porta or 8765
  self.reconectar_s = opcoes.reconectar_s or 3
  self.timeout_conexao_s = opcoes.timeout_conexao_s or 2
  self.buffer_max = opcoes.buffer_max_bytes or 512 * 1024
  self.relogio = opcoes.relogio or function() return 0 end -- ms do jogo para o campo 't'
  self.ao_conectar = opcoes.ao_conectar     -- function()
  self.ao_receber = opcoes.ao_receber       -- function(tipo, dados)
  self.ao_cair = opcoes.ao_cair             -- function(motivo)
  self.estado = 'desligada'
  self.proxima_tentativa = 0
  self.saida = {}        -- pedaços pendentes
  self.saida_bytes = 0
  self.parcial = ''
  self.seq = 0
  self.avisou_falha = false
  return self
end

function Ponte:conectada() return self.estado == 'conectada' end

function Ponte:_fechar(motivo)
  if self.c then pcall(function() self.c:close() end) end
  local estava = self.estado
  self.c = nil
  self.estado = 'desligada'
  self.saida, self.saida_bytes, self.parcial = {}, 0, ''
  if estava == 'conectada' then
    self.log.aviso('ponte: conexao encerrada (%s)', tostring(motivo))
    if self.ao_cair then self.ao_cair(motivo) end
  end
end

function Ponte:_tentar(agora)
  local c, err = self.socket.tcp()
  if not c then
    self.log.erro('ponte: socket.tcp falhou: %s', tostring(err))
    self.proxima_tentativa = agora + self.reconectar_s
    return
  end
  c:settimeout(0)
  pcall(function() c:setoption('tcp-nodelay', true) end)
  local ok, e = c:connect(self.host, self.porta)
  self.c = c
  self.inicio_conexao = agora
  if ok then
    self:_virou_conectada()
  elseif e == 'timeout' or (type(e) == 'string' and e:find('progress')) then
    self.estado = 'conectando'
  else
    if not self.avisou_falha then
      self.log.aviso('ponte: cerebro indisponivel em %s:%d (%s); tentando a cada %ds',
        self.host, self.porta, tostring(e), self.reconectar_s)
      self.avisou_falha = true
    end
    self:_fechar(e)
    self.proxima_tentativa = agora + self.reconectar_s
  end
end

function Ponte:_virou_conectada()
  self.estado = 'conectada'
  self.avisou_falha = false
  self.log.info('ponte: conectada a %s:%d', self.host, self.porta)
  if self.ao_conectar then self.ao_conectar() end
end

function Ponte:_esperar_conexao(agora)
  local _, gravaveis = self.socket.select(nil, { self.c }, 0)
  if gravaveis and (gravaveis[1] == self.c or gravaveis[self.c]) then
    if self.c:getpeername() then
      self:_virou_conectada()
      return
    end
    -- Gravável sem par = conexão recusada.
    if not self.avisou_falha then
      self.log.aviso('ponte: conexao recusada em %s:%d; o cerebro esta rodando? (python -m cerebro)',
        self.host, self.porta)
      self.avisou_falha = true
    end
    self:_fechar('recusada')
    self.proxima_tentativa = agora + self.reconectar_s
  elseif agora - self.inicio_conexao > self.timeout_conexao_s then
    if not self.avisou_falha then
      self.log.aviso('ponte: sem resposta de %s:%d; o cerebro esta rodando? (python -m cerebro)',
        self.host, self.porta)
      self.avisou_falha = true
    end
    self:_fechar('timeout')
    self.proxima_tentativa = agora + self.reconectar_s
  end
end

function Ponte:_escrever()
  while #self.saida > 0 do
    local pedaco = self.saida[1]
    local i, err, ultimo = self.c:send(pedaco)
    if i then
      table.remove(self.saida, 1)
      self.saida_bytes = self.saida_bytes - #pedaco
    elseif err == 'timeout' then
      if ultimo and ultimo > 0 then
        self.saida[1] = pedaco:sub(ultimo + 1)
        self.saida_bytes = self.saida_bytes - ultimo
      end
      return
    else
      self:_fechar(err)
      return
    end
  end
end

function Ponte:_ler()
  for _ = 1, 50 do -- no máximo 50 mensagens por frame
    local linha, err, parcial = self.c:receive('*l', self.parcial)
    if linha then
      self.parcial = ''
      if #linha > 0 then
        local ok, msg = pcall(self.json.decodificar, linha)
        if ok and type(msg) == 'table' and msg.v == 1 and type(msg.tipo) == 'string' then
          if self.ao_receber then
            local ok2, e2 = pcall(self.ao_receber, msg.tipo, msg.dados or {})
            if not ok2 then self.log.erro('ponte: erro tratando %s: %s', msg.tipo, tostring(e2)) end
          end
        else
          self.log.erro('ponte: mensagem invalida do cerebro: %s', linha:sub(1, 200))
        end
      end
    elseif err == 'timeout' then
      self.parcial = parcial or ''
      if #self.parcial > 1024 * 1024 then self:_fechar('linha grande demais') end
      return
    else
      self:_fechar(err)
      return
    end
  end
end

-- Chamar a cada frame. agora = segundos (relógio real, não pausa).
function Ponte:passo(agora)
  if self.parado then return end
  if self.estado == 'desligada' then
    if agora >= self.proxima_tentativa then self:_tentar(agora) end
  elseif self.estado == 'conectando' then
    self:_esperar_conexao(agora)
  end
  if self.estado == 'conectada' then
    self:_escrever()
    if self.estado == 'conectada' then self:_ler() end
  end
end

function Ponte:enviar(tipo, dados)
  if self.estado ~= 'conectada' then return false end
  self.seq = self.seq + 1
  local ok, linha = pcall(self.json.codificar, {
    v = 1, tipo = tipo, seq = self.seq, t = self.relogio(), dados = dados or {},
  })
  if not ok then
    self.log.erro('ponte: falha ao codificar %s: %s', tipo, tostring(linha))
    return false
  end
  linha = linha .. '\n'
  if self.saida_bytes + #linha > self.buffer_max then
    self.log.aviso('ponte: buffer cheio, descartando %s', tipo)
    return false
  end
  self.saida[#self.saida + 1] = linha
  self.saida_bytes = self.saida_bytes + #linha
  return true
end

-- Envia o que der agora (usado no 'adeus' antes de fechar) e desliga.
function Ponte:encerrar(motivo)
  if self.estado == 'conectada' then
    self:enviar('adeus', { motivo = motivo })
    pcall(function() self:_escrever() end)
  end
  self:_fechar(motivo)
  self.parado = true
end

function Ponte:religar()
  self.parado = false
  self.proxima_tentativa = 0
  self.avisou_falha = false
end

return Ponte
