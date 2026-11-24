-- Sensores: transformam o estado do motor em percepção estruturada e eventos.
--
-- REGRA DE ESTABILIDADE: handles de ped/veículo expiram quando o motor remove a
-- entidade. Toda varredura roda inteira dentro de um único frame (sem wait()),
-- e cada handle é conferido com doesCharExist/doesVehicleExist antes de qualquer
-- outro opcode. Cada entidade é lida dentro de pcall: uma falha descarta só ela.
local S = {}
S.__index = S

-- ePedType (gta-reversed / Sanny Builder enums.json)
local TIPO_PED = {
  [0] = 'jogador', [1] = 'jogador', [2] = 'jogador', [3] = 'jogador',
  [4] = 'civil', [5] = 'civil', [6] = 'policia',
  [17] = 'traficante', [18] = 'medico', [19] = 'bombeiro', [20] = 'criminoso',
  [21] = 'mendigo', [22] = 'prostituta', [23] = 'especial',
}
local GANGUE = {
  [7] = 'ballas', [8] = 'grove', [9] = 'vagos', [10] = 'rifa', [11] = 'danang',
  [12] = 'mafia', [13] = 'triade', [14] = 'aztecas', [15] = 'mafia_russa', [16] = 'motoqueiros',
}
-- Modelos de veículos de polícia/forças (vehicles.ide do SA 1.0).
local VEICULO_POLICIA = {
  [596] = true, [597] = true, [598] = true, [599] = true, [523] = true, [427] = true,
  [490] = true, [528] = true, [601] = true, [497] = true, [430] = true,
}

local function r1(x) return math.floor(x * 10 + 0.5) / 10 end
local function r2(x) return math.floor(x * 100 + 0.5) / 100 end
local function dist3(ax, ay, az, bx, by, bz)
  local dx, dy, dz = ax - bx, ay - by, az - bz
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function S.novo(cfg, api, json, log)
  local self = setmetatable({}, S)
  self.cfg, self.api, self.json, self.log = cfg, api, json, log
  self.peds = {}        -- handle -> memória entre varreduras
  self.veiculos = {}    -- handle -> memória entre varreduras
  self.ultimo_tiro_jogador = -1e9
  self.procurado = nil
  self.interior = nil
  self.policiais_perto = 0
  self.mirando = nil
  self.zonas = {}       -- cache codigo -> nome
  self.ultima = nil     -- última percepção montada
  self.erros = {}       -- mensagens de erro já registradas (para não inundar o log)
  local ok, memory = pcall(require, 'memory')
  self.memory = ok and memory or nil
  return self
end

function S:_erro_unico(chave, msg)
  if not self.erros[chave] then
    self.erros[chave] = true
    self.log.erro('sensores: %s: %s', chave, tostring(msg))
  end
end

-- Clima: CWeather::OldWeatherType (0xC81320) e NewWeatherType (0xC8131C), int16,
-- endereços do SA 1.0 US conferidos no gta-reversed (Weather.h).
function S:_clima()
  if not self.memory then return nil end
  local ok, atual = pcall(self.memory.getint16, 0xC81320, false)
  if ok then return atual end
  self:_erro_unico('clima', atual)
  return nil
end

function S:_zona(x, y, z)
  local ok, codigo = pcall(getNameOfZone, x, y, z)
  if not ok or not codigo then return { codigo = nil, nome = nil } end
  local nome = self.zonas[codigo]
  if nome == nil then
    nome = false
    if self.api.f.texto_gxt then
      local ok2, t = pcall(self.api.f.texto_gxt, codigo)
      if ok2 and type(t) == 'string' and #t > 0 then nome = t end
    end
    self.zonas[codigo] = nome
  end
  return { codigo = codigo, nome = nome or codigo }
end

-- Câmera: posição e direção unitária para onde o jogador olha.
function S:_camera()
  local cx, cy, cz = getActiveCameraCoordinates()
  local px, py, pz = getActiveCameraPointAt()
  local dx, dy, dz = px - cx, py - cy, pz - cz
  local n = math.sqrt(dx * dx + dy * dy + dz * dz)
  if n < 1e-6 then return cx, cy, cz, 0, 1, 0 end
  return cx, cy, cz, dx / n, dy / n, dz / n
end

-- O jogador consegue ver este ponto? (genérico: serve para o corpo de Smith na Fase 5)
function S:_visibilidade(ped, x, y, z, cam)
  local cx, cy, cz, dx, dy, dz = cam[1], cam[2], cam[3], cam[4], cam[5], cam[6]
  local alvo_z = z + 0.5 -- peito, não pés
  local vx, vy, vz = x - cx, y - cy, alvo_z - cz
  local n = math.sqrt(vx * vx + vy * vy + vz * vz)
  local angulo = 0
  if n > 1e-6 then
    local cos = (vx * dx + vy * dy + vz * dz) / n
    if cos > 1 then cos = 1 elseif cos < -1 then cos = -1 end
    angulo = math.deg(math.acos(cos))
  end
  local na_tela = isCharOnScreen(ped)
  local los = false
  if na_tela then
    -- prédios, carros e objetos bloqueiam; outros pedestres não
    los = isLineOfSightClear(cx, cy, cz, x, y, alvo_z, true, true, false, true, false)
  end
  return na_tela, los, angulo
end

local function atividade(ped, morto)
  if morto then return 'morto' end
  if isCharInAnyCar(ped) then
    local carro = storeCarCharIsInNoSave(ped)
    if carro and doesVehicleExist(carro) and getDriverOfCar(carro) == ped then return 'dirigindo' end
    return 'passageiro'
  end
  if isCharShooting(ped) then return 'atirando' end
  local v = getCharSpeed(ped)
  if v > 3.5 then return 'correndo' end
  if v > 0.3 then return 'andando' end
  return 'parado'
end

-- Tiros: isCharShooting só fica verdadeiro no frame do disparo, então isto
-- roda a CADA frame, só sobre o jogador e os peds já conhecidos da última
-- varredura (dentro do raio de eventos). Retorna lista de eventos.
function S:checar_tiros(agora)
  local eventos = {}
  if not doesCharExist(PLAYER_PED) then return eventos end
  if isCharShooting(PLAYER_PED) and agora - self.ultimo_tiro_jogador > self.cfg.cooldown_tiro_ms then
    self.ultimo_tiro_jogador = agora
    local x, y, z = getCharCoordinates(PLAYER_PED)
    eventos[#eventos + 1] = { nome = 'tiro', autor = 'jogador', pos = self.json.lista({ r1(x), r1(y), r1(z) }) }
  end
  for ped, mem in pairs(self.peds) do
    if mem.vivo and doesCharExist(ped) and not isCharDead(ped) and isCharShooting(ped)
        and agora - mem.ultimo_tiro > self.cfg.cooldown_tiro_ms then
      mem.ultimo_tiro = agora
      local x, y, z = getCharCoordinates(ped)
      eventos[#eventos + 1] = { nome = 'tiro', autor = ped, pos = self.json.lista({ r1(x), r1(y), r1(z) }) }
    end
  end
  return eventos
end

-- Varredura completa. agora = ms do relógio do jogo; dt = ms desde a anterior.
-- Retorna a lista de eventos novos; a percepção fica em self.ultima.
function S:varrer(agora, dt)
  local cfg = self.cfg
  local eventos = {}
  local function evento(nome, campos)
    campos = campos or {}
    campos.nome = nome
    eventos[#eventos + 1] = campos
  end

  if not doesCharExist(PLAYER_PED) then return eventos end
  local jx, jy, jz = getCharCoordinates(PLAYER_PED)
  local cam = { self:_camera() }

  -- ---- jogador ----------------------------------------------------------
  local procurado = storeWantedLevel(PLAYER_HANDLE)
  if self.procurado ~= nil and procurado ~= self.procurado then
    evento('procurado_mudou', { de = self.procurado, para = procurado })
  end
  self.procurado = procurado

  local interior = self.api.f.interior and self.api.f.interior() or nil
  if self.interior ~= nil and interior ~= nil and interior ~= self.interior then
    evento('interior_mudou', { de = self.interior, para = interior })
  end
  self.interior = interior


  local veiculo_jogador = nil
  local carro_jogador = nil
  local vel_jogador = getCharSpeed(PLAYER_PED)
  if isCharInAnyCar(PLAYER_PED) then
    carro_jogador = storeCarCharIsInNoSave(PLAYER_PED)
    if carro_jogador and doesVehicleExist(carro_jogador) then
      vel_jogador = getCarSpeed(carro_jogador)
      veiculo_jogador = {
        id = carro_jogador, modelo = getCarModel(carro_jogador), velocidade = r1(vel_jogador),
        motorista = getDriverOfCar(carro_jogador) == PLAYER_PED,
      }
    end
  end

  -- ---- pedestres --------------------------------------------------------
  local vistos = {}
  local proximos = {}
  local policiais = 0
  local mirando = nil
  local todos = getAllChars() or {}
  for _, ped in ipairs(todos) do
    if ped ~= PLAYER_PED and doesCharExist(ped) then
      local ok, e = pcall(function()
        local x, y, z = getCharCoordinates(ped)
        local d = dist3(x, y, z, jx, jy, jz)
        if d > cfg.raio_eventos then return end
        vistos[ped] = true
        local mem = self.peds[ped]
        local morto = isCharDead(ped)
        local tipo_num = getPedType(ped)
        local modelo = getCharModel(ped)
        if not mem then
          mem = { vivo = not morto, ultimo_tiro = -1e9, olhado_ms = 0, observa_avisado = false,
                  segue_ms = 0, segue_avisado = false, modelo = modelo }
          self.peds[ped] = mem
        end
        -- morte: transição vivo -> morto
        if morto and mem.vivo then
          evento('morte', { vitima = ped, modelo = modelo,
                            tipo = GANGUE[tipo_num] and 'gangue' or (TIPO_PED[tipo_num] or 'outro'),
                            gangue = GANGUE[tipo_num],
                            pos = self.json.lista({ r1(x), r1(y), r1(z) }) })
        end
        mem.vivo = not morto
        if morto then
          if d <= cfg.raio_percepcao then
            proximos[#proximos + 1] = { ped = ped, d = d, x = x, y = y, z = z, morto = true,
                                        tipo_num = tipo_num, modelo = modelo }
          end
          return
        end
        if tipo_num == 6 and d <= cfg.raio_percepcao then policiais = policiais + 1 end
        if self.api.f.mirando and not mirando and self.api.f.mirando(PLAYER_HANDLE, ped) then
          mirando = ped
        end
        -- seguir: jogador e NPC em movimento, perto, por muito tempo
        local vel = getCharSpeed(ped)
        if d <= cfg.segue_dist and vel > 1 and vel_jogador > 1 then
          mem.segue_ms = mem.segue_ms + dt
          if mem.segue_ms >= cfg.segue_ms and not mem.segue_avisado then
            mem.segue_avisado = true
            evento('jogador_segue_npc', { alvo = ped, ms = mem.segue_ms, dist = r1(d) })
          end
        elseif d > cfg.segue_dist or vel_jogador <= 1 then
          mem.segue_ms, mem.segue_avisado = 0, false
        end
        if d <= cfg.raio_percepcao then
          proximos[#proximos + 1] = { ped = ped, d = d, x = x, y = y, z = z, morto = false,
                                      tipo_num = tipo_num, modelo = modelo, mem = mem }
        end
      end)
      if not ok then self:_erro_unico('ped', e) end
    end
  end
  -- esquece quem saiu do raio ou sumiu
  for ped in pairs(self.peds) do
    if not vistos[ped] then self.peds[ped] = nil end
  end

  if policiais > 0 and self.policiais_perto == 0 then
    evento('policia_chegou', { quantos = policiais, pos = self.json.lista({ r1(jx), r1(jy), r1(jz) }) })
  end
  self.policiais_perto = policiais

  if mirando and mirando ~= self.mirando then
    evento('jogador_mira_npc', { alvo = mirando })
  end
  self.mirando = mirando

  table.sort(proximos, function(a, b) return a.d < b.d end)
  local lista_peds = self.json.lista({})
  for i = 1, math.min(#proximos, cfg.max_pedestres) do
    local p = proximos[i]
    local ok, e = pcall(function()
      if not doesCharExist(p.ped) then return end
      local na_tela, los, angulo = self:_visibilidade(p.ped, p.x, p.y, p.z, cam)
      local mem = p.mem
      if mem then
        if na_tela and los and angulo <= cfg.angulo_foco then
          mem.olhado_ms = mem.olhado_ms + dt
          if mem.olhado_ms >= cfg.observa_ms and not mem.observa_avisado then
            mem.observa_avisado = true
            evento('jogador_observa_npc', { alvo = p.ped, ms = mem.olhado_ms, dist = r1(p.d) })
          end
        else
          mem.olhado_ms, mem.observa_avisado = 0, false
        end
      end
      local arma = p.morto and 0 or getCurrentCharWeapon(p.ped)
      local gangue = GANGUE[p.tipo_num]
      lista_peds[#lista_peds + 1] = {
        id = p.ped, modelo = p.modelo,
        tipo = gangue and 'gangue' or (TIPO_PED[p.tipo_num] or 'outro'),
        gangue = gangue, policial = p.tipo_num == 6,
        arma = arma, armado = arma ~= 0,
        atividade = atividade(p.ped, p.morto),
        pos = self.json.lista({ r1(p.x), r1(p.y), r1(p.z) }), dist = r1(p.d),
        vida = getCharHealth(p.ped),
        visibilidade = { na_tela = na_tela, linha_de_visao = los, angulo = r1(angulo),
                         olhado_ms = mem and mem.olhado_ms or 0 },
      }
    end)
    if not ok then self:_erro_unico('ped_percepcao', e) end
  end

  -- ---- veículos ---------------------------------------------------------
  local carros = {}
  local vistos_v = {}
  for _, carro in ipairs(getAllVehicles() or {}) do
    if doesVehicleExist(carro) then
      local ok, e = pcall(function()
        local x, y, z = getCarCoordinates(carro)
        local d = dist3(x, y, z, jx, jy, jz)
        if d > cfg.raio_eventos then return end
        vistos_v[carro] = true
        local vida = getCarHealth(carro)
        local mem = self.veiculos[carro]
        if mem and not isCarDead(carro) and mem.vida - vida >= cfg.dano_batida then
          evento('batida', { veiculo = carro, dano = mem.vida - vida,
                             jogador = carro == carro_jogador,
                             pos = self.json.lista({ r1(x), r1(y), r1(z) }) })
        end
        self.veiculos[carro] = { vida = vida }
        if d <= cfg.raio_percepcao and carro ~= carro_jogador then
          carros[#carros + 1] = { carro = carro, d = d, x = x, y = y, z = z, vida = vida }
        end
      end)
      if not ok then self:_erro_unico('veiculo', e) end
    end
  end
  for carro in pairs(self.veiculos) do
    if not vistos_v[carro] then self.veiculos[carro] = nil end
  end
  table.sort(carros, function(a, b) return a.d < b.d end)
  local lista_veic = self.json.lista({})
  for i = 1, math.min(#carros, cfg.max_veiculos) do
    local c = carros[i]
    local ok, e = pcall(function()
      if not doesVehicleExist(c.carro) then return end
      local modelo = getCarModel(c.carro)
      local motorista = getDriverOfCar(c.carro)
      if not (motorista and motorista ~= -1 and doesCharExist(motorista)) then motorista = nil end
      lista_veic[#lista_veic + 1] = {
        id = c.carro, modelo = modelo, pos = self.json.lista({ r1(c.x), r1(c.y), r1(c.z) }),
        dist = r1(c.d), velocidade = r1(getCarSpeed(c.carro)), motorista = motorista,
        policia = VEICULO_POLICIA[modelo] == true, vida = c.vida,
      }
    end)
    if not ok then self:_erro_unico('veiculo_percepcao', e) end
  end

  -- ---- percepção --------------------------------------------------------
  local h, m = getTimeOfDay()
  self.ultima = {
    mundo = {
      hora = string.format('%02d:%02d', h, m),
      clima = self:_clima(),
      zona = self:_zona(jx, jy, jz),
      territorio_dono = nil, -- Fase 3 (atlas)
      interior = interior,
      procurado_jogador = procurado,
      densidade = { raio = cfg.raio_percepcao, pedestres = #proximos, veiculos = #carros },
    },
    smith = nil, -- Fase 2 (possessão)
    jogador = {
      pos = self.json.lista({ r1(jx), r1(jy), r1(jz) }),
      rumo = r1(getCharHeading(PLAYER_PED)),
      velocidade = r1(vel_jogador),
      vida = getCharHealth(PLAYER_PED),
      colete = getCharArmour(PLAYER_PED),
      dinheiro = self.api.f.dinheiro and self.api.f.dinheiro(PLAYER_HANDLE) or nil,
      arma = getCurrentCharWeapon(PLAYER_PED),
      procurado = procurado,
      veiculo = veiculo_jogador,
      olhar = self.json.lista({ r2(cam[4]), r2(cam[5]), r2(cam[6]) }),
      mirando_em = mirando,
    },
    entorno = { pedestres = lista_peds, veiculos = lista_veic },
  }
  return eventos
end

return S
