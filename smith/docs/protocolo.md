# Protocolo corpo ↔ cérebro (v1)

Transporte: **TCP local `127.0.0.1:8765`**, uma mensagem JSON por linha (`\n` no fim,
UTF-8, sem quebras de linha dentro do JSON). O cérebro é o servidor; o corpo
(MoonLoader) é o cliente e reconecta sozinho.

> Por que TCP com linhas e não WebSocket/HTTP? O documento-mestre permite
> "WebSocket ou HTTP". O luasocket do MoonLoader só fala TCP cru; implementar o
> handshake WebSocket em Lua seria código extra e frágil dentro do jogo, e HTTP
> exigiria uma conexão por mensagem. JSON por linha é o mais simples que funciona
> nos dois sentidos, sem bloquear o frame do jogo. Se um dia precisarmos de
> WebSocket (por exemplo, para o painel no navegador), o cérebro faz a ponte.

## Envelope

Toda mensagem, nos dois sentidos:

```json
{"v": 1, "tipo": "percepcao", "seq": 42, "t": 1234567, "dados": {}}
```

| campo | tipo | significado |
|---|---|---|
| `v` | int | versão do protocolo (1) |
| `tipo` | string | tipo da mensagem (tabelas abaixo) |
| `seq` | int | contador do remetente, crescente |
| `t` | int | relógio de quem envia em ms (no corpo: relógio do jogo, que para na pausa) |
| `dados` | objeto | conteúdo; pode ser `{}` |

Mensagem que não segue o envelope é descartada e registrada no log como erro.
Linhas maiores que 1 MiB derrubam a conexão.

## Corpo → cérebro

| tipo | quando | dados |
|---|---|---|
| `ola` | ao conectar | `jogo`, `versao_corpo`, `api_ausente` (funções do MoonLoader que não existem nesta instalação), `capacidades` |
| `percepcao` | a cada `intervalo_percepcao_ms` (padrão 2000) e logo após um evento | ver abaixo |
| `evento` | imediatamente | `nome` + campos do evento |
| `estado` | quando muda | `pausado` (bool), `ativo` (bool) |
| `adeus` | antes de desconectar (F10, fim do script) | `motivo` |
| `pong` | resposta a `ping` | `id` |

### `percepcao`

As chaves são neutras (servem para qualquer jogo); os **valores** podem ser
específicos do jogo (nomes de zona, códigos de modelo). O cérebro trata os
valores como texto/número opaco.

```json
{
  "mundo": {
    "hora": "21:37", "clima": 8,
    "zona": {"codigo": "GAN1", "nome": "Ganton"},
    "territorio_dono": null,
    "interior": 0,
    "procurado_jogador": 0,
    "densidade": {"raio": 60, "pedestres": 14, "veiculos": 6}
  },
  "smith": null,
  "jogador": {
    "pos": [2495.1, -1687.4, 13.5], "rumo": 182.0, "velocidade": 0.0,
    "vida": 100, "colete": 0, "dinheiro": 350, "arma": 0,
    "procurado": 0, "veiculo": null,
    "olhar": [0.0, -1.0, -0.1], "mirando_em": null
  },
  "entorno": {
    "pedestres": [
      {"id": 12345, "modelo": 105, "tipo": "gangue", "gangue": "grove",
       "policial": false, "arma": 22, "armado": true, "atividade": "andando",
       "pos": [2490.0, -1680.2, 13.4], "dist": 8.9, "vida": 100,
       "visibilidade": {"na_tela": true, "linha_de_visao": true,
                        "angulo": 12.5, "olhado_ms": 0}}
    ],
    "veiculos": [
      {"id": 6789, "modelo": 596, "pos": [2480.0, -1670.0, 13.3], "dist": 22.1,
       "velocidade": 11.2, "motorista": 4321, "policia": true, "vida": 1000}
    ]
  }
}
```

- `smith`: o corpo que Smith habita. `null` até a Fase 2 (possessão).
- `id`: handle do motor. **Expira**: quando o NPC some, o mesmo número pode
  voltar inválido. O cérebro nunca deve supor que um id vale para sempre.
- `atividade`: `morto`, `dirigindo`, `passageiro`, `atirando`, `correndo`,
  `andando`, `parado`.
- `visibilidade.angulo`: ângulo (graus) entre o centro da câmera e o NPC.
  `olhado_ms`: há quanto tempo o jogador mantém o NPC perto do centro da tela.
- `territorio_dono`: ainda `null`; depende do atlas (Fase 3).

### Eventos (Fase 1)

| `nome` | campos |
|---|---|
| `tiro` | `autor` (id ou `"jogador"`), `pos` |
| `morte` | `vitima` (id), `modelo`, `tipo`, `pos` |
| `batida` | `veiculo` (id), `dano`, `pos` |
| `procurado_mudou` | `de`, `para` |
| `policia_chegou` | `quantos`, `pos` |
| `interior_mudou` | `de`, `para` |
| `jogador_observa_npc` | `alvo` (id), `ms`, `dist` |
| `jogador_segue_npc` | `alvo` (id), `ms`, `dist` |
| `jogador_mira_npc` | `alvo` (id) |

Explosões e guerras de gangue ainda não são detectadas (exigem leitura de
memória do motor; entram depois, com endereços conferidos no gta-reversed).

## Cérebro → corpo

| tipo | quando | dados |
|---|---|---|
| `ola_ok` | resposta ao `ola` | `versao_cerebro`, `intervalo_percepcao_ms` |
| `ping` | periódico | `id` |
| `config` | quando quiser | `intervalo_percepcao_ms` (500–10000) |

Na Fase 2 entra `comando` (poderes) e a resposta `resultado`.
