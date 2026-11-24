-- Verificação das funções do MoonLoader que o corpo usa.
--
-- Os nomes abaixo seguem a convenção do MoonLoader (nome do comando do Sanny
-- Builder em camelCase). Os opcodes foram conferidos na biblioteca do Sanny
-- Builder (sannybuilder/library, sa.json). Como não deu para abrir a
-- documentação do MoonLoader daqui, o script confere na partida se cada
-- função existe e manda a lista das ausentes ao cérebro (mensagem 'ola').
-- Uma função ausente desliga só o sensor que depende dela, nunca o jogo.
local M = {}

-- nome = opcode (para referência e diagnóstico)
M.obrigatorias = {
  getAllChars = 'MoonLoader',
  getAllVehicles = 'MoonLoader',
  getWorkingDirectory = 'MoonLoader',
  isGamePaused = 'MoonLoader',
  wasKeyPressed = 'MoonLoader',
  printStringNow = 'MoonLoader',
  doesCharExist = '056D',
  doesVehicleExist = '056E',
  isCharDead = '0118',
  isCarDead = '0119',
  getCharCoordinates = '00A0',
  getCharHeading = '0172',
  getCharHealth = '0226',
  getCharArmour = '04DD',
  getCharModel = '0665',
  getCharSpeed = '06AC',
  getCurrentCharWeapon = '0470',
  isCharInAnyCar = '00DF',
  storeCarCharIsInNoSave = '03C0',
  getDriverOfCar = '046C',
  getCarModel = '0441',
  getCarCoordinates = '00AA',
  getCarSpeed = '02E3',
  getCarHealth = '0227',
  getPedType = '089F',
  isCharShooting = '02E0',
  isCharOnScreen = '02CB',
  isLineOfSightClear = '06BD',
  getActiveCameraCoordinates = '068D',
  getActiveCameraPointAt = '068E',
  getNameOfZone = '0843',
  getTimeOfDay = '00BF',
  storeWantedLevel = '01C0',
  isPlayerPlaying = '0256',
  getGameTimer = '01BD',
}

-- Funções com nome incerto no MoonLoader: tentamos as alternativas em ordem.
M.alternativas = {
  dinheiro = { 'storeScore', 'getPlayerMoney' },                     -- 010B STORE_SCORE
  interior = { 'getActiveInterior', 'getAreaVisible' },              -- 077E GET_AREA_VISIBLE
  mirando = { 'isPlayerTargettingChar', 'isPlayerTargetingChar' },   -- 0457
  texto_gxt = { 'getGxtText' },                                      -- MoonLoader
}

M.ausentes = {}
M.f = {}

function M.verificar()
  M.ausentes = {}
  for nome in pairs(M.obrigatorias) do
    if type(_G[nome]) ~= 'function' then
      M.ausentes[#M.ausentes + 1] = nome
    end
  end
  for chave, nomes in pairs(M.alternativas) do
    for _, nome in ipairs(nomes) do
      if type(_G[nome]) == 'function' then
        M.f[chave] = _G[nome]
        break
      end
    end
    if not M.f[chave] then
      M.ausentes[#M.ausentes + 1] = table.concat(nomes, '|')
    end
  end
  table.sort(M.ausentes)
  return M.ausentes
end

function M.tem(nome)
  return type(_G[nome]) == 'function'
end

return M
