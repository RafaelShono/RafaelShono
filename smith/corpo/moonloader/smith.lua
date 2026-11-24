-- SMITH — corpo (MoonLoader). Fase 1: ponte e sensores.
--
-- Este script só lê o mundo e envia ao cérebro (Python) em 127.0.0.1:8765.
-- Ele não cria, move nem altera nada no jogo nesta fase.
-- F10 liga/desliga Smith a qualquer momento.
script_name('Smith')
script_author('Projeto Smith')
script_version('0.1.0-fase1')
script_description('Uma mente oculta em San Andreas: corpo (sensores e ponte)')

local VERSAO = '0.1.0-fase1'

local pasta = getWorkingDirectory()
package.path = pasta .. '/?.lua;' .. pasta .. '/?/init.lua;' .. package.path

local log = require 'smith_corpo.log'
local cfg = require 'smith_corpo.config'
local json = require 'smith_corpo.json'
local api = require 'smith_corpo.api'
local Ponte = require 'smith_corpo.ponte'
local Sensores = require 'smith_corpo.sensores'

local ok_vk, vkeys = pcall(require, 'vkeys')
local TECLA_DESLIGAR = (ok_vk and vkeys[cfg.tecla_desligar]) or 0x79 -- VK_F10

-- Relógio real (segundos) para reconexão; não para na pausa.
local relogio_real = (type(localClock) == 'function') and localClock or os.clock

local ativo = true
local ponte = nil
local sensores = nil
local pausado = nil
local intervalo_percepcao = cfg.intervalo_percepcao_ms

-- Tudo que Smith alterar no mundo registra aqui como desfazer.
-- Na Fase 1 nada é alterado, mas o F10 já passa por este caminho.
local restauradores = {}
local function restaurar_mundo()
  for i = #restauradores, 1, -1 do
    local ok, e = pcall(restauradores[i])
    if not ok then log.erro('restaurar: %s', tostring(e)) end
  end
  restauradores = {}
end

local function aviso_tela(texto, ms)
  if type(printStringNow) == 'function' then pcall(printStringNow, texto, ms or 2000) end
end

local function enviar_estado()
  if ponte then ponte:enviar('estado', { pausado = pausado == true, ativo = ativo }) end
end

local function ao_receber(tipo, dados)
  if tipo == 'ping' then
    ponte:enviar('pong', { id = dados.id })
  elseif tipo == 'ola_ok' or tipo == 'config' then
    local ms = tonumber(dados.intervalo_percepcao_ms)
    if ms then
      intervalo_percepcao = math.max(500, math.min(10000, ms))
      log.info('intervalo de percepcao: %d ms', intervalo_percepcao)
    end
    if tipo == 'ola_ok' then log.info('cerebro %s respondeu', tostring(dados.versao_cerebro)) end
  else
    log.aviso('mensagem ainda nao suportada nesta fase: %s', tipo)
  end
end

local function ao_conectar()
  local ausentes = api.ausentes
  ponte:enviar('ola', {
    jogo = 'gta_sa_1.0_us', versao_corpo = VERSAO,
    api_ausente = json.lista(ausentes),
    capacidades = json.lista({ 'percepcao', 'eventos' }),
  })
  pausado = nil -- força reenvio do estado
  aviso_tela('~g~Smith: cerebro conectado', 1500)
end

local function desligar(motivo)
  if ponte then ponte:encerrar(motivo) end
  restaurar_mundo()
  log.info('Smith desligado (%s)', motivo)
end

function main()
  log.abrir(pasta)
  log.info('Smith %s iniciando', VERSAO)

  local ausentes = api.verificar()
  if #ausentes > 0 then
    log.aviso('funcoes do MoonLoader ausentes: %s', table.concat(ausentes, ', '))
  else
    log.info('todas as funcoes esperadas do MoonLoader existem')
  end

  local ok_sock, socket = pcall(require, 'socket')
  if not ok_sock then
    log.erro('luasocket nao encontrado (require "socket" falhou: %s). Veja o README, secao Instalacao.', tostring(socket))
  end

  -- Espera o jogador existir (carregamento do save).
  repeat wait(200) until isPlayerPlaying(PLAYER_HANDLE)
  wait(1000)

  if not ok_sock then
    aviso_tela('~r~Smith: falta o luasocket (veja smith_corpo.log)', 6000)
    return
  end

  -- Sensores só funcionam com todas as obrigatórias presentes.
  local faltando_obrigatoria = false
  for _, nome in ipairs(ausentes) do
    if api.obrigatorias[nome] then faltando_obrigatoria = true end
  end
  if faltando_obrigatoria then
    log.erro('sensores desativados por falta de funcoes obrigatorias; a ponte so envia o diagnostico')
  else
    sensores = Sensores.novo(cfg, api, json, log)
  end

  ponte = Ponte.nova({
    socket = socket, json = json, log = log,
    host = cfg.host, porta = cfg.porta,
    reconectar_s = cfg.reconectar_s, timeout_conexao_s = cfg.timeout_conexao_s,
    buffer_max_bytes = cfg.buffer_max_bytes,
    relogio = function() return getGameTimer() end,
    ao_conectar = ao_conectar,
    ao_receber = ao_receber,
  })

  local ultima_varredura = getGameTimer()
  local proxima_percepcao = 0
  aviso_tela('~w~Smith: procurando o cerebro em 127.0.0.1:' .. cfg.porta, 2500)

  while true do
    wait(0)

    -- F10 sempre primeiro, antes de qualquer coisa que possa falhar.
    if wasKeyPressed(TECLA_DESLIGAR) then
      ativo = not ativo
      if ativo then
        ponte:religar()
        log.info('Smith religado (F10)')
        aviso_tela('~g~SMITH LIGADO', 1500)
      else
        desligar('F10')
        aviso_tela('~r~SMITH DESLIGADO', 1500)
      end
    end

    if ativo then
      local ok, e = pcall(function()
        ponte:passo(relogio_real())
        if not ponte:conectada() then return end

        local p = isGamePaused()
        if p ~= pausado then
          pausado = p
          enviar_estado()
        end
        if p or not sensores then return end

        local agora = getGameTimer()
        local dt = agora - ultima_varredura
        if dt < 0 or dt > 5000 then dt = cfg.intervalo_sensores_ms end -- save carregado, etc.
        local tiros = sensores:checar_tiros(agora)
        for _, ev in ipairs(tiros) do ponte:enviar('evento', ev) end
        if #tiros > 0 then
          proxima_percepcao = math.min(proxima_percepcao, agora + cfg.atraso_percepcao_evento_ms)
        end
        if agora - ultima_varredura >= cfg.intervalo_sensores_ms or agora < ultima_varredura then
          ultima_varredura = agora
          if isPlayerPlaying(PLAYER_HANDLE) then
            local eventos = sensores:varrer(agora, dt)
            for _, ev in ipairs(eventos) do ponte:enviar('evento', ev) end
            if #eventos > 0 then
              proxima_percepcao = math.min(proxima_percepcao, agora + cfg.atraso_percepcao_evento_ms)
            end
          end
        end
        if agora >= proxima_percepcao and sensores.ultima then
          ponte:enviar('percepcao', sensores.ultima)
          proxima_percepcao = agora + intervalo_percepcao
        end
      end)
      if not ok then
        log.erro('ciclo: %s', tostring(e))
        wait(500) -- não inundar o log se o erro se repetir a cada frame
      end
    end
  end
end

function onScriptTerminate(script, saindo_do_jogo)
  if script == thisScript() then
    pcall(desligar, saindo_do_jogo and 'jogo fechado' or 'script encerrado')
    log.fechar()
  end
end
