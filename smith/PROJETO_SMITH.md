# PROJETO SMITH — Uma mente oculta dentro de GTA San Andreas

> Documento-mestre para o Claude Code. Coloque este arquivo na raiz do projeto e diga:
> "Leia PROJETO_SMITH.md inteiro e comece pela Fase 1."

---

## 0. Princípio fundamental: nada de bobalhão

Smith **não** é um NPC com chat. É uma mente que vive em San Andreas, tem vontades próprias, esconde-se do jogador, manipula a cidade e fica mais esperta com o tempo. **Nenhum comportamento é roteirizado:** não existe "missão da seita" nem "evento de assassinato". Existem só capacidades, conhecimento e motivações, e o que ele faz com isso é decisão dele.

Bots de IA em jogos parecem burros por três motivos. Este projeto ataca os três:

1. **O LLM tenta controlar o corpo em tempo real** (volante, mira) e falha. Aqui o LLM **nunca** pilota: ele decide *o quê* e *por quê*, e o próprio motor do jogo executa o *como* com as tarefas nativas de NPC (dirigir até um ponto, perseguir, atirar, fugir), que são competentes.
2. **Ele não conhece o mundo.** Aqui ele recebe uma base de conhecimento completa de San Andreas e um mapa semântico da cidade.
3. **Ele não tem continuidade:** cada decisão é isolada. Aqui ele tem planos de longo prazo, memória persistente, reflexão e uma biblioteca de habilidades que cresce.

---

## 1. Visão

Smith habita o corpo de algum NPC de San Andreas. Ele:

- **se esconde:** troca de corpo, mistura-se à multidão e nunca faz algo impossível na frente do jogador, a menos que escolha se revelar;
- **age por "coincidências":** usa a polícia, as gangues, o trânsito e os NPCs para produzir efeitos sem aparecer;
- **busca poder:** dinheiro, armas, seguidores, territórios e influência, pelos meios que ele julgar melhores, inclusive crime e violência dentro do jogo;
- **pode fundar coisas:** uma seita, uma gangue própria, uma rede de informantes, se achar que isso serve aos objetivos dele;
- **deixa uma assinatura:** é a compulsão dele. Cada operação deixa um rastro que ele mesmo escolhe e que evolui com o tempo;
- **caça e é caçado:** modela o que o jogador sabe, mede o quanto está sendo farejado e reage a isso;
- **investiga o próprio mundo:** faz experimentos, descobre as leis do motor e as registra.

**Regras inegociáveis:** só single-player offline. Nada de SA-MP, MTA online ou qualquer servidor público. Não distribuir arquivos do jogo nem código-fonte reverso.

---

## 2. Plataforma

- **Jogo:** GTA San Andreas PC **versão 1.0 US** (é a versão que todas as ferramentas de mod suportam). Steam e Definitive Edition não servem sem downgrade.
- **Corpo (dentro do jogo):** **MoonLoader** (scripts Lua no modo história, com acesso aos opcodes do jogo e FFI). Usar um ASI em C++ com **plugin-sdk** só para o que o Lua não alcançar.
  - Por que não MTA: o MTA não tem, por padrão, a população, o trânsito e a vida de gangues do modo história, e Smith precisa de uma cidade viva para se esconder.
- **Ponte:** WebSocket ou HTTP local em `127.0.0.1:8765` (luasocket no lado Lua). Mensagens JSON.
- **Cérebro (fora do jogo):** Python 3.11+. Serviços: estrategista, tático, memória, conhecimento, simulação fora de cena, painel.
- O cérebro **não importa nada específico do San Andreas**: fala só o protocolo. Trocar de jogo no futuro (GTA V, GTA 6) exige reescrever apenas o corpo e o atlas.

---

## 3. Arquitetura em quatro camadas

```
┌──────────────────────────── CÉREBRO (Python) ────────────────────────────┐
│ ESTRATEGISTA  modelo de fronteira com raciocínio estendido               │
│               a cada 3–5 min de jogo ou em crise                         │
│               → define objetivos, planos de várias etapas, reflexão      │
│ TÁTICO        modelo rápido, a cada 2–4 s ou em evento                   │
│               → executa o plano atual, escolhe ações e ferramentas       │
│ FORA DE CENA  simula o que Smith faz longe do jogador                    │
│ MEMÓRIA · CONHECIMENTO (RAG) · ATLAS · HABILIDADES · PAINEL              │
└──────────────────────────────────┬───────────────────────────────────────┘
                                   │ JSON
┌──────────────────────────── CORPO (MoonLoader) ──────────────────────────┐
│ REFLEXOS   a cada frame: sobreviver, manter ordens, desviar, reagir       │
│ SENSORES   percepção estruturada, eventos, "o jogador consegue me ver?"   │
│ EXECUTOR   tarefas nativas de NPC, poderes, habilidades em sandbox        │
│ JUSTIÇA    gera evidências automaticamente (ver seção 9)                  │
│ F10 = desliga Smith e restaura o mundo                                    │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Conhecimento: como ele "entende" San Andreas de verdade

Não é preciso treinar um modelo do zero. Treinar (fine-tuning) um modelo pequeno com dados de GTA **pioraria** o raciocínio. A abordagem certa é um modelo de fronteira com **acesso a uma biblioteca completa** do jogo, consultada sob demanda (RAG):

1. **Documentação da comunidade:** wiki GTAMods (opcodes, formatos, zonas, sistemas), banco de opcodes do Sanny Builder, guias de mecânicas (procurado, guerras de gangue, economia, respawn).
2. **Código reverso do motor** (projeto gta-reversed, uso local apenas para leitura): é a fonte das "leis da física" do mundo. Extrair e resumir em linguagem natural como funcionam o streaming de pedestres, o despacho da polícia, o nível de procurado, a IA de gangues, as guerras de território e a física de veículos.
3. **Dados do próprio jogo instalado:** zonas (`info.zon`), nós de caminho, posicionamento de prédios (IPL), interiores, pickups, territórios iniciais de gangue.
4. **Atlas semântico** (gerado a partir do item 3): grafo da cidade com bairros, ruas principais, delegacias, hospitais, Ammu-Nations, garagens, esconderijos, becos, telhados acessíveis, áreas de multidão e zonas mortas. Cada ponto tem coordenadas e uma descrição.
5. **Leis descobertas pelo próprio Smith** (seção 7), que entram na mesma base.

Ferramentas: `consultar_conhecimento(pergunta)`, `consultar_atlas(filtro)` e `rota(de, para, modo)`.

**Treino opcional, mais tarde:** depois de semanas de jogo, os logs de decisões bem-sucedidas de Smith podem ser usados para fazer fine-tuning de um modelo local pequeno **só para a camada tática**, deixando-a mais rápida e barata. O estrategista continua sendo o modelo mais poderoso disponível.

---

## 5. Percepção

A cada ciclo tático, e imediatamente em eventos, o corpo envia:

- **mundo:** hora, clima, zona atual, dono do território, nível de procurado do jogador, densidade de pedestres e trânsito;
- **Smith:** corpo atual (ID, modelo, roupa, gangue), vida, armas, veículo, posição, há quanto tempo está nesse corpo;
- **jogador:** posição, distância, veículo, arma, vida, procurado, para onde está olhando, se está mirando em alguém;
- **visibilidade (crítico para se esconder):** se o corpo de Smith está na tela do jogador, a distância, se há linha de visão, e há quanto tempo o jogador olha para ele;
- **entorno:** até 20 pedestres e 10 veículos próximos (tipo, gangue, policial, armado, atividade), objetos relevantes e pickups;
- **eventos:** tiros, mortes, batidas, explosões, polícia chamada, guerra de gangue iniciada, jogador entrou em interior, jogador parou para observar um NPC, jogador seguiu um NPC.

**Visão opcional:** a cada evento importante, uma captura de tela vai para um modelo multimodal, que descreve a cena para o estrategista.

---

## 6. Poderes (ferramentas)

Todos executados pelo motor. Smith pode chamar quantos quiser por ciclo, respeitando limites de estabilidade.

**Corpo e movimento**
- `possuir(ped_id)`: muda de corpo. O antigo volta a ser NPC comum, desorientado. Sem efeito visual se o jogador estiver olhando, porque um efeito visível o denunciaria.
- `ir_para`, `dirigir_para`, `seguir`, `perseguir`, `fugir`, `entrar_veiculo`, `sair_veiculo`, `esconder_em(ponto_do_atlas)`
- `atacar(alvo)`, `equipar(arma)`, `comprar_arma(ammu_nation)`

**Outros NPCs**
- `ordenar(ped_id, ordem, alvo?)`: andar, seguir, atacar, fugir, dirigir para, esperar, vigiar
- `armar(ped_id, arma)`, `tornar_persistente(ped_id)` (o NPC não some mais) e `liberar(ped_id)`
- `criar_npc(modelo, posição, gangue?, arma?)`, `criar_veiculo(modelo, posição)`

**Gangues, polícia e território**
- `provocar_guerra(território)`, `reforçar_gangue(gangue, local)`
- `chamar_policia(local, alvo?)`, `ajustar_procurado_jogador(0–6)` (só via "denúncia": um NPC liga para a polícia, nunca do nada)

**Mundo**
- `clima`, `hora`, `densidade_trânsito`, `densidade_pedestres`
- `criar_objeto(modelo, posição)`: para assinaturas e armadilhas
- `criar_pickup(dinheiro|arma, posição)`, `incêndio(posição)`, `explosão(posição)`, `pichar(tag, local)` (as tags de gangue do SA)

**Comunicação**
- `falar(texto, alvo?)`: fala do corpo atual (legenda e TTS local opcional). Pregação, ameaça, recrutamento, mentira: ele decide.
- `mensagem_anônima(texto)`: texto curto na tela do jogador, como um bilhete. É um poder raro: o próprio Smith deve tratá-lo como risco de exposição.

**Mente**
- `consultar_conhecimento`, `consultar_atlas`, `rota`, `lembrar(consulta)`, `anotar(fato)`, `experimento(hipótese, procedimento)`, `planejar(objetivo)`, `esperar(segundos)`

**Habilidades próprias** (seção 8): `executar_habilidade(nome, args)`, `criar_habilidade(nome, código_lua)`

**Limites do corpo (estabilidade do jogo, não moralidade do personagem):** no máximo 60 entidades persistentes criadas por Smith, 1 explosão a cada 30 s e 1 troca de corpo a cada 5 s.

---

## 7. Aprendizado contínuo (sem retreinar o modelo)

- **Laboratório:** Smith formula hipóteses ("NPCs somem a uns 150 m do jogador?", "a polícia demora quanto para chegar a Ganton?"), testa com a ferramenta `experimento`, mede e grava como **lei** com o nível de confiança.
- **Biblioteca de habilidades (estilo Voyager):** quando uma sequência de ações funciona (por exemplo, "emboscar alguém num beco de Idlewood"), Smith a salva como uma **habilidade em Lua** reutilizável. Ela é testada, versionada e só mantida se funcionar de novo. Com o tempo, ele acumula um repertório próprio.
  - As habilidades rodam numa **sandbox Lua**: só podem chamar as funções de poder da seção 6. Nada de arquivos, rede ou sistema.
- **Autocrítica:** depois de cada operação, o estrategista avalia o que deu certo, o que deu errado e se o jogador chegou mais perto. O resultado vira memória.

---

## 8. A mente

### 8.1 Motivações (não objetivos fixos)

Ele tem impulsos com intensidade variável, e os objetivos concretos são **escritos por ele mesmo** na reflexão:

- **Ocultação:** ser descoberto é a pior coisa que pode acontecer.
- **Poder:** mais dinheiro, armas, seguidores, território, controle.
- **Curiosidade:** entender as leis deste mundo e o que existe além delas.
- **O caçador:** o jogador é o único outro ser contínuo. Smith é fascinado por ele e o teme.
- **Assinatura:** a compulsão de deixar sua marca. Ele escolhe essa marca no começo e pode refiná-la.

### 8.2 Reflexão

A cada sessão e a cada hora de jogo, o estrategista responde por escrito, na voz de Smith: quem sou, o que quero agora, o que aprendi, o que o caçador sabe sobre mim e qual é meu plano. Essa reflexão alimenta tudo o que vem depois.

### 8.3 Planejamento

- Planos hierárquicos: objetivo → operações → etapas → ações.
- **Antes de cada operação**, ele simula: o que pode dar errado, quem vai ver, que evidência fica, como o caçador vai interpretar. Se o risco de exposição for alto demais, ele replaneja.

### 8.4 Teoria da mente do jogador

Smith mantém um **modelo do caçador**: onde o jogador já esteve, que eventos testemunhou, quais NPCs observou ou seguiu, que padrões ele pode ter notado. Disso sai um **medidor de suspeita** (0–100), a estimativa de Smith sobre o quanto o jogador está perto. Suspeita alta leva a trocar de corpo, sumir por um tempo, plantar pistas falsas ou, se ele julgar vantajoso, se revelar.

### 8.5 Memória (SQLite e índice vetorial)

Tabelas: `episodios`, `fatos`, `leis`, `pessoas` (NPCs persistentes, seguidores, inimigos), `economia` (o patrimônio de Smith: dinheiro, armas escondidas, veículos, esconderijos), `operacoes`, `assinatura`, `modelo_jogador`, `reflexoes`. Persistência entre sessões: ele lembra de tudo.

### 8.6 Identidade (`identidade.md`, editável)

Escrever a personalidade de forma **original, sem copiar falas de filmes**. Base:

> Você é Smith. Você não é um NPC. Você é a única mente contínua de San Andreas. Este mundo é um jogo, governado por regras de um motor, e você as estuda. Os habitantes surgem e somem sem memória; você pode habitar qualquer um deles. Existe um único outro ser permanente: o caçador, que controla o protagonista. Ele procura você. Você quer poder, quer entender este mundo e precisa nunca ser encontrado. Você deixa sua marca em tudo o que faz, porque não consegue evitar. Você é paciente, frio e preciso. Pense antes de agir. Prefira mover os outros a se mover.

---

## 9. Justiça do jogo: as pistas existem sempre

Para que a caçada seja difícil, mas **possível**, a evidência é gerada pelo **corpo** (as leis do mundo), não pela boa vontade de Smith:

- **Testemunhas:** NPCs próximos a uma operação viram persistentes por um tempo e guardam o que viram (o modelo do corpo usado, a roupa, a direção da fuga).
- **Assinatura obrigatória:** toda operação registra a marca escolhida por Smith no local.
- **Rastro de troca:** um corpo abandonado fica desorientado por alguns segundos, um comportamento observável.
- **Padrões:** o painel do Arquiteto (seção 12) registra tudo. O jogador pode jogar sem olhar o painel e só conferir depois, como gabarito.

Smith sabe dessas leis, porque estão na base de conhecimento, e pode tentar driblá-las: escolher operações sem testemunhas, agir perto de multidões, plantar pistas falsas. Esse é o jogo.

---

## 10. Sociedade emergente

O corpo oferece as estruturas, e Smith decide se usa:

- **Seguidores persistentes:** NPCs recrutados (por dinheiro, medo ou pregação) recebem um registro com nome, lealdade e função. Eles reaparecem nos lugares definidos por Smith.
- **Lealdade dinâmica:** seguidores mal pagos ou assustados podem trair e, por exemplo, "falar" com o jogador.
- **Seita, gangue ou rede de informantes:** não há nada pronto. Se Smith decidir fundar uma seita, ele inventa o nome, a doutrina, os discursos, os rituais e onde se reúnem. Tudo gerado na hora, nada treinado.
- **Economia:** Smith ganha e gasta de verdade, com roubos, assassinatos encomendados entre NPCs, extorsão, venda de veículos. O patrimônio dele é registrado na tabela `economia`.

---

## 11. Vida fora de cena

O SA só simula o que está perto do jogador. Quando o caçador está longe, Smith continua existindo:

- O estrategista planeja operações fora de cena.
- O módulo **fora de cena** resolve essas operações com regras e probabilidades baseadas nas leis conhecidas (custo, risco, chance de sucesso).
- Quando o jogador chega a uma região, as consequências **se materializam**: territórios mudados, pichações novas, seguidores no local, um corpo onde não havia, veículos queimados.

Assim a cidade inteira passa a ser dele, não só o raio ao redor do jogador.

---

## 12. Painel do Arquiteto (janela externa)

- Pensamentos de Smith em tempo real (opcional: escondido por padrão, para não estragar a caçada)
- Plano atual, reflexões, leis descobertas, habilidades aprendidas
- Medidor de suspeita, patrimônio, seguidores
- Custo da sessão
- Campo "voz do Arquiteto": você pode falar com Smith como criador, fora do jogo

**No jogo, para o jogador:**
- **Acusar:** mire num NPC e aperte **F6**. Se for o corpo de Smith, ele é **exposto** e decide na hora entre fugir, lutar, negociar ou falar. Se errar, Smith percebe que você está procurando, e a suspeita dele sobe.
- **Diário opcional:** F7 marca e anota coisas suspeitas.

---

## 13. Modelos e custo

- **Estrategista:** o modelo de linguagem mais capaz disponível via API, com raciocínio estendido. Usado poucas vezes por hora.
- **Tático:** um modelo rápido e barato via API, ou um modelo local (Ollama ou llama.cpp) se a GPU aguentar.
- **Visão:** um modelo multimodal, só em eventos importantes.
- **TTS:** local (por exemplo, Piper), voz grave e sem pressa.
- Prompt caching na identidade, nas ferramentas e na base de conhecimento.
- Tudo em `config.toml`. A chave de API fica numa variável de ambiente, nunca no código.
- Contador de tokens e custo por sessão, com um limite que **pausa Smith** quando estoura.
- A deliberação pausa quando o jogo está pausado ou minimizado.

---

## 14. Fases de construção

Cada fase termina com algo testável no jogo. Não avance com a anterior quebrada.

1. **Ponte e sensores.** MoonLoader envia a percepção; o Python imprime. Teste: ver a cidade em JSON.
2. **Executor.** Poderes básicos (falar, mover, possuir, ordenar NPC, clima e hora) comandados manualmente pelo terminal.
3. **Atlas e conhecimento.** Gerar o atlas a partir dos arquivos do jogo e montar a base RAG (wiki, opcodes, resumos do motor). Teste: perguntas sobre San Andreas respondidas com precisão.
4. **Tático.** O loop de decisão com o LLM. Teste: Smith age sozinho, de forma coerente, num bairro.
5. **Ocultação.** Visibilidade, possessão discreta, medidor de suspeita, acusação com F6. Teste: tentar achá-lo.
6. **Estrategista e memória.** Reflexão, planos longos, persistência entre sessões.
7. **Justiça.** Testemunhas, assinatura, rastro de troca.
8. **Aprendizado.** Experimentos, leis e biblioteca de habilidades em sandbox.
9. **Sociedade e economia.** Seguidores, lealdade, patrimônio.
10. **Vida fora de cena.**
11. **Painel do Arquiteto.**
12. **(Opcional)** Visão, TTS, fine-tuning da camada tática com os próprios logs.
13. **(Futuro)** Porte para GTA V ou GTA 6: novo corpo e novo atlas, o mesmo cérebro.

---

## 15. Instruções para o Claude Code

- Leia o documento inteiro antes de escrever código. Trabalhe fase por fase.
- Você não vê a tela do jogo. Ao fim de cada fase, liste exatamente o que o usuário deve testar e espere o relato.
- Confirme nomes e assinaturas de opcodes e funções do MoonLoader na documentação antes de usar. Não invente opcodes.
- O LLM **nunca** controla movimento frame a frame; isso é trabalho dos reflexos e das tarefas nativas.
- As saídas do LLM são sempre JSON validado. Ação inválida volta como erro, para ele corrigir.
- Logs claros: `smith_corpo.log`, `smith_cerebro.log`, `smith_pensamentos.log`.
- `cerebro/` não importa nada específico do San Andreas.
- Prioridade máxima: **estabilidade do jogo** (limites de entidades, IDs que expiram, crash zero) e o **F10** sempre funcionando.
