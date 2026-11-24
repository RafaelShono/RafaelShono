-- Imita o suficiente da API do MoonLoader para rodar smith.lua fora do jogo.
-- Uso: luajit moonloader_falso.lua <pasta_moonloader> <porta> <frames>
-- Requer luasocket instalado no sistema (lua-socket).
local pasta, porta, frames = arg[1], tonumber(arg[2]), tonumber(arg[3] or 400)
local socket = require 'socket'

local tempo = 100000        -- ms do relógio do jogo
local frame = 0
PLAYER_PED, PLAYER_HANDLE = 1, 1

-- mundo: peds e carros
local peds = {
  [1] = { x = 2495, y = -1687, z = 13.5, vida = 100, modelo = 0, tipo = 0, arma = 0, vel = 0 },
  [256] = { x = 2490, y = -1680, z = 13.4, vida = 100, modelo = 105, tipo = 8, arma = 22, vel = 1.2 },  -- grove
  [512] = { x = 2510, y = -1690, z = 13.4, vida = 100, modelo = 102, tipo = 7, arma = 30, vel = 0 },    -- ballas
  [768] = { x = 2530, y = -1700, z = 13.4, vida = 100, modelo = 280, tipo = 6, arma = 22, vel = 0, surge = 30 }, -- policial
  [1024] = { x = 2496, y = -1677, z = 13.4, vida = 100, modelo = 7, tipo = 4, arma = 0, vel = 0 },     -- civil na frente da câmera
}
local carros = { [5000] = { x = 2480, y = -1670, z = 13.3, vida = 1000, modelo = 596, motorista = 768, vel = 8 } }
local procurado = 0
local teclas = {}

local function ped(h) return peds[h] end
local function existe(h) local p = peds[h]; return p ~= nil and (not p.surge or frame >= p.surge) end

function getWorkingDirectory() return pasta end
function wait(ms)
  coroutine.yield()
  tempo = tempo + 50
  frame = frame + 1
  socket.sleep(0.003)
  -- roteiro do mundo, por frame
  if frame == 40 then peds[512].atirando = true end
  if frame == 41 then peds[512].atirando = false end
  if frame == 60 then peds[256].vida = 0 end
  if frame == 70 then procurado = 2 end
  if frame == 80 then carros[5000].vida = 700 end
  if frame == 200 then teclas[0x79] = true end   -- F10 desliga
  if frame == 260 then teclas[0x79] = true end   -- F10 religa
end
function isGamePaused() return false end
function wasKeyPressed(k) local v = teclas[k]; teclas[k] = nil; return v == true end
function printStringNow(t, ms) print('[tela] ' .. t) end
function isPlayerPlaying() return true end
function getGameTimer() return tempo end
function getAllChars() local t = {} for h in pairs(peds) do if existe(h) then t[#t + 1] = h end end return t end
function getAllVehicles() local t = {} for h in pairs(carros) do t[#t + 1] = h end return t end
function doesCharExist(h) return existe(h) end
function doesVehicleExist(h) return carros[h] ~= nil end
function isCharDead(h) return existe(h) and ped(h).vida <= 0 end
function isCarDead(h) return carros[h].vida <= 0 end
function getCharCoordinates(h) local p = ped(h); return p.x, p.y, p.z end
function getCharHeading() return 180.0 end
function getCharHealth(h) return ped(h).vida end
function getCharArmour() return 0 end
function getCharModel(h) return ped(h).modelo end
function getCharSpeed(h) return ped(h).vel end
function getCurrentCharWeapon(h) return ped(h).arma end
function isCharInAnyCar(h) return false end
function storeCarCharIsInNoSave() error('nao esta em carro') end
function getDriverOfCar(c) return carros[c].motorista end
function getCarModel(c) return carros[c].modelo end
function getCarCoordinates(c) local v = carros[c]; return v.x, v.y, v.z end
function getCarSpeed(c) return carros[c].vel end
function getCarHealth(c) return carros[c].vida end
function getPedType(h) return ped(h).tipo end
function isCharShooting(h) return ped(h).atirando == true end
function isCharOnScreen(h) return ped(h).y > -1687 end
function isLineOfSightClear() return true end
function getActiveCameraCoordinates() return 2495, -1690, 15 end
function getActiveCameraPointAt() return 2495, -1680, 14.2 end
function getNameOfZone() return 'GAN1' end
function getGxtText(k) return k == 'GAN1' and 'Ganton' or k end
function getTimeOfDay() return 21, 37 end
function storeWantedLevel() return procurado end
function storeScore() return 350 end
function getActiveInterior() return 0 end
function isPlayerTargettingChar(_, h) return h == 512 and frame > 100 end
function script_name() end
function script_author() end
function script_version() end
function script_description() end
local este = {}
function thisScript() return este end

dofile(pasta .. '/smith.lua')
local cfg = require 'smith_corpo.config'
cfg.porta = porta
cfg.reconectar_s = 0.05

local co = coroutine.create(main)
for _ = 1, frames do
  local ok, e = coroutine.resume(co)
  if not ok then io.stderr:write('ERRO main: ' .. tostring(e) .. '\n'); os.exit(1) end
  if coroutine.status(co) == 'dead' then break end
end
onScriptTerminate(este, false)
print('fim, frames=' .. frame)
