# Projeto Smith

Uma mente oculta dentro de GTA San Andreas (single-player, offline).
O documento-mestre é [PROJETO_SMITH.md](PROJETO_SMITH.md); o protocolo está em
[docs/protocolo.md](docs/protocolo.md).

**Fase atual: 1, ponte e sensores.** O jogo envia o que percebe e o cérebro imprime.
Nesta fase Smith **não altera nada** no jogo: só lê.

```
smith/
├── corpo/moonloader/        → copiar para a pasta moonloader do jogo
│   ├── smith.lua            script principal (F10 liga/desliga)
│   └── smith_corpo/         módulos: ponte, sensores, json, api, log, config
├── cerebro/                 Python: ponte TCP, protocolo, impressão
├── ferramentas/corpo_falso.py   imita o jogo, para testar sem o GTA
├── testes/                  pytest (inclui o smith.lua rodando em LuaJIT com a API imitada)
└── config.toml              configuração do cérebro
```

## Instalação

### Jogo
1. GTA San Andreas PC **1.0 US** (Steam/DE precisam de downgrade).
2. ASI Loader + **MoonLoader** (versão 0.26 ou mais nova).
3. **luasocket para MoonLoader**: o script usa `require 'socket'`. Se ele não
   existir, o Smith avisa na tela ("falta o luasocket") e no `smith_corpo.log`.
   O luasocket não vem no MoonLoader básico: pegue o pacote luasocket feito para
   MoonLoader (blast.hk, área de bibliotecas do MoonLoader) e extraia em
   `moonloader/lib` (ficam `socket.lua` e `socket/core.dll` lá dentro).
4. Copie **o conteúdo** de `corpo/moonloader/` para a pasta `moonloader/` do jogo:
   `moonloader/smith.lua` e `moonloader/smith_corpo/...`.

### Cérebro
Python 3.11 ou mais novo. Nesta fase só a biblioteca padrão é usada.

```
cd smith
python -m cerebro          # resumo legível
python -m cerebro --json   # JSON cru de cada mensagem
```

Logs em `smith/logs/`: `smith_cerebro.log`, `percepcoes.jsonl` (tudo o que chegou).
No jogo: `moonloader/smith_corpo.log` (e o `moonloader.log` normal).

### Testes sem o jogo
```
pip install pytest
python -m pytest testes
# ou, com o cérebro rodando em outro terminal:
python ferramentas/corpo_falso.py
```

## Fase 1: o que testar no jogo

1. Inicie `python -m cerebro`, depois o jogo, e carregue um save.
2. **Conexão:** na tela, "Smith: cerebro conectado". No terminal,
   `=== corpo conectado ===`. Se aparecer `ATENÇÃO: funções do MoonLoader ausentes`,
   me mande essa linha: é a conferência dos nomes de função que não consegui
   verificar na documentação.
3. **Percepção:** a cada 2 s um bloco com hora, zona, clima, procurado, você e os
   pedestres/veículos perto. Confira: a hora bate com o relógio do jogo? A zona
   bate com o bairro? Os NPCs de gangue aparecem com a gangue certa (Grove em
   Ganton, Ballas em Idlewood)? Viaturas aparecem como POLÍCIA?
4. **Visibilidade:** o 👁 aparece só para quem está na tela e não está atrás de
   parede? Pare e olhe fixo para um NPC por 3 s: deve sair `EVENTO jogador_observa_npc`.
5. **Eventos:** atire para o alto (`tiro`, autor=jogador); mate um NPC (`morte`);
   ganhe estrela (`procurado_mudou`, depois `policia_chegou`); bata o carro
   (`batida`); entre numa casa/loja (`interior_mudou`); mire num NPC
   (`jogador_mira_npc`); ande atrás de um NPC por 15 s (`jogador_segue_npc`).
6. **Pausa:** ESC → `[estado] pausado: True`; as percepções param. Voltar → `False`.
7. **F10:** "SMITH DESLIGADO" na tela e `corpo se despediu: F10` no terminal.
   F10 de novo reconecta.
8. **Robustez:** feche o Python com o jogo aberto: o jogo não pode travar nem
   engasgar. Abra de novo: reconecta sozinho em alguns segundos.
   Jogue 10 min numa área movimentada (Grove Street à noite, uma guerra de gangue):
   sem travadas e sem crash.
9. Me mande: o que funcionou, o que não funcionou, o `smith_corpo.log` e um
   pedaço do `percepcoes.jsonl`.

## Limitações conhecidas da Fase 1
- `smith` é sempre `null` (possessão é Fase 2); `territorio_dono` é `null` (atlas, Fase 3).
- Explosões e início de guerra de gangue ainda não viram evento (precisam de leitura
  de memória com endereços conferidos).
- Objetos e pickups ainda não entram no entorno.
- Nomes de função do MoonLoader seguem o padrão do Sanny Builder e foram conferidos
  pelo opcode, mas a documentação do MoonLoader não estava acessível; o script
  confere cada nome na partida e relata as ausentes em vez de quebrar.
