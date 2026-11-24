-- Configuração do corpo de Smith (lado MoonLoader).
return {
  host = '127.0.0.1',          -- só local. Nunca aponte para outra máquina.
  porta = 8765,
  reconectar_s = 3,            -- espera entre tentativas de conexão
  timeout_conexao_s = 2,

  intervalo_sensores_ms = 250,     -- varredura de eventos (relógio do jogo)
  intervalo_percepcao_ms = 2000,   -- o cérebro pode mudar via 'config'
  atraso_percepcao_evento_ms = 300,-- percepção extra logo após um evento

  raio_percepcao = 60,         -- metros: entorno enviado ao cérebro
  raio_eventos = 100,          -- metros: onde detectamos tiros, mortes etc.
  max_pedestres = 20,
  max_veiculos = 10,

  angulo_foco = 10,            -- graus do centro da câmera = "olhando para"
  observa_ms = 3000,           -- olhar fixo por isso => jogador_observa_npc
  segue_ms = 15000,            -- andar perto de um NPC em movimento por isso => jogador_segue_npc
  segue_dist = 35,
  dano_batida = 150,           -- queda de vida do veículo numa varredura
  cooldown_tiro_ms = 2000,

  tecla_desligar = 'VK_F10',
  buffer_max_bytes = 512 * 1024,   -- envio pendente máximo
}
