# CAPRATS — Fase 3: Lobby e Fluxo de Fases
Sequência de prompts para o Antigravity (Godot 4 + GodotSteam, estética PSX, 1ª pessoa).

---

## Decisões de arquitetura (leia antes de rodar qualquer prompt)

1. **Só existem 3 cenas de jogo, não 4.** `Lobby_Van.tscn` (van parada) → `Van_Trajeto.tscn` (van em movimento) → `Casa.tscn`. Vistoria e caça acontecem **na mesma cena `Casa.tscn`**, só mudando a fase. Recarregar a cena entre vistoria e caça apagaria as armadilhas instaladas e teleportaria os jogadores.
2. **O host manda.** O dono do lobby Steam é a autoridade: só ele roda os timers, só ele decide a troca de fase e só ele dispara a troca de cena via RPC. Cliente nunca troca de cena sozinho.
3. **Estado vive fora das cenas.** Cor, contrato, dinheiro e inventário ficam num autoload que sobrevive à troca de cena. Nenhum dado importante mora num nó de cena.

**Máquina de fases:**
`LOBBY` → `TRAJETO` (120s) → `VISTORIA` (60s) → `CACA` → `RESULTADO`

**Ordem de execução:** rode os cards em ordem. Os cards 01–04 são a fundação — nada depois funciona sem eles.

---

## BLOCO A — Fundação

### Card 01 — Autoload `GerenteSessao` (estado persistente)

> **Objetivo:** criar o autoload que guarda todo o estado da partida entre trocas de cena.
>
> **Contexto:** projeto Godot 4, multiplayer via GodotSteam (lobby já existente). Nomes de classes em português, seguindo o padrão `GerenteMaos` da Fase 2.
>
> **O que fazer:**
> 1. Criar `res://autoload/gerente_sessao.gd` e registrar como autoload `GerenteSessao`.
> 2. Guardar um dicionário `jogadores` indexado por `steam_id`, cada entrada com: `nome`, `cor` (Color), `pronto` (bool), `dinheiro` (int), `inventario` (Array de ids de item), `eh_host` (bool).
> 3. Guardar estado global da partida: `contrato_atual` (id), `fase_atual` (enum), `semente_aleatoria` (int, gerada pelo host e replicada — garante que todos vejam a mesma casa).
> 4. Métodos: `registrar_jogador(steam_id, nome)`, `remover_jogador(steam_id)`, `definir_cor(steam_id, cor)`, `definir_pronto(steam_id, valor)`, `todos_prontos() -> bool`, `resetar_prontos()`.
> 5. Sinais: `jogador_entrou(steam_id)`, `jogador_saiu(steam_id)`, `estado_jogador_mudou(steam_id)`.
> 6. **Não** colocar lógica de rede aqui — este autoload só guarda e notifica. Quem sincroniza é o `GerenteRede`.
>
> **Critério de aceite:** trocar de cena via `change_scene_to_file` mantém todos os dados intactos; imprimir `GerenteSessao.jogadores` na cena nova mostra o mesmo conteúdo.

---

### Card 02 — Autoload `GerenteFase` (máquina de estados + timer autoritativo)

> **Objetivo:** centralizar transição de fases, timers e troca de cena.
>
> **O que fazer:**
> 1. Criar `res://autoload/gerente_fase.gd`, autoload `GerenteFase`.
> 2. `enum Fase { LOBBY, TRAJETO, VISTORIA, CACA, RESULTADO }`.
> 3. Mapa de duração: `LOBBY = 0` (sem timer), `TRAJETO = 120.0`, `VISTORIA = 60.0`, `CACA = 0` (sem timer).
> 4. Mapa de cena por fase: `LOBBY → Lobby_Van.tscn`, `TRAJETO → Van_Trajeto.tscn`, `VISTORIA e CACA → Casa.tscn` (a mesma). Se a cena da próxima fase for igual à atual, **não recarregar** — só emitir o sinal de mudança de fase.
> 5. Só o host roda o `Timer`. A cada 0.5s o host envia `rpc("sincronizar_timer", tempo_restante)`; clientes interpolam localmente entre os pacotes para o HUD não travar.
> 6. `avancar_fase()` — só o host pode chamar. Chama `GerenteSessao.resetar_prontos()`, atualiza `fase_atual`, e envia `rpc("aplicar_fase", nova_fase)` para todos.
> 7. Sinais: `fase_mudou(fase_anterior, fase_nova)`, `timer_atualizado(segundos_restantes)`.
> 8. Cliente que receber `aplicar_fase` faz a troca de cena; se a cena for a mesma, apenas emite `fase_mudou`.
>
> **Critério de aceite:** com 2 instâncias abertas, o host chamando `avancar_fase()` leva as duas para a mesma cena/fase em menos de 1 segundo, e os dois timers batem com diferença menor que 0.5s.

---

### Card 03 — Sistema de "Pronto" reutilizável

> **Objetivo:** um único sistema de pronto usado nas três fases (lobby, trajeto, vistoria).
>
> **O que fazer:**
> 1. Criar `res://sistemas/estacao_pronto.gd` — uma `Area3D` interagível que alterna o pronto do jogador local.
> 2. Ao interagir: chama `rpc_id(host_id, "pedir_alternar_pronto", meu_steam_id)`. Só o host altera o estado e faz broadcast do resultado.
> 3. Feedback visual PSX: uma luz/placa acima da estação que muda de vermelho para verde, mais um som curto. Sem emojis, sem UI moderna — placa física dentro da van.
> 4. O host, ao receber qualquer mudança de pronto, verifica `GerenteSessao.todos_prontos()`; se verdadeiro, chama `GerenteFase.avancar_fase()`.
> 5. Regra especial da fase `TRAJETO` e `VISTORIA`: o timer chegando a zero também avança a fase, mesmo com jogadores não prontos.
> 6. Jogador que se desconecta não pode travar a partida — o cálculo de `todos_prontos()` considera só quem está conectado.
>
> **Critério de aceite:** dois jogadores; a fase só avança quando os dois marcam pronto, ou quando o timer zera.

---

### Card 04 — `HUD_Fase` (barra de estado compartilhada)

> **Objetivo:** HUD única, presente nas três cenas, mostrando fase, tempo e prontos.
>
> **O que fazer:**
> 1. Criar `res://ui/hud_fase.tscn` instanciada por todas as cenas de jogo.
> 2. Mostrar: nome da fase, tempo restante em `M:SS` (oculto quando a fase não tem timer) e contador `X/Y prontos`.
> 3. Lista lateral de jogadores conectados, cada nome pintado com a cor escolhida e com um marcador de pronto.
> 4. Estética PSX: fonte bitmap, sem antialiasing, sem gradiente, sem sombra. Alinhar ao estilo já usado na HUD da Fase 2.
> 5. Nos últimos 10 segundos de qualquer fase com timer, o número pisca e toca um bipe por segundo.
> 6. Conectar aos sinais `GerenteFase.fase_mudou`, `GerenteFase.timer_atualizado` e `GerenteSessao.estado_jogador_mudou`. Zero `_process` fazendo polling de estado.
>
> **Critério de aceite:** a HUD reflete a mudança de qualquer jogador sem precisar recarregar cena.

---

## BLOCO B — Lobby na van parada

### Card 05 — Cena `Lobby_Van`

> **Objetivo:** montar a van parada onde a partida é configurada.
>
> **O que fazer:**
> 1. Criar `res://cenas/lobby_van.tscn`: interior de van/caminhonete de dedetização, porta traseira aberta, luz interna fraca, névoa PSX na saída.
> 2. Colisão fechada: o jogador anda dentro da van e pode sair alguns passos, mas não escapa do cenário (usar `StaticBody3D` invisível como limite).
> 3. Até 4 `Marker3D` como pontos de spawn, atribuídos por ordem de entrada no lobby.
> 4. Instanciar o player da Fase 2 com o `GerenteMaos` ativo, porém **com armas desabilitadas** — no lobby só existem mãos vazias e interação.
> 5. Três estações físicas dentro da van, cada uma um `Area3D` com prompt de interação: **Cor** (Card 06), **Contrato** (Card 08) e **Pronto** (Card 03).
> 6. Instanciar `HUD_Fase`.
>
> **Critério de aceite:** dois jogadores entram, aparecem em spawns diferentes e conseguem se ver andando pela van.

---

### Card 06 — Estação de cor do personagem

> **Objetivo:** cada jogador escolhe uma cor única para seu macacão.
>
> **O que fazer:**
> 1. Criar um painel físico na parede da van com 8 amostras de cor (paleta PSX saturada, definida como constante em `GerenteSessao`).
> 2. Interagir com uma amostra envia `rpc_id(host_id, "pedir_cor", steam_id, indice_cor)`. O host valida: se a cor já está tomada por outro jogador, recusa e toca som de erro para o solicitante.
> 3. Cor aprovada → host atualiza `GerenteSessao.definir_cor` e faz broadcast. Todos repintam o material do macacão daquele jogador.
> 4. Amostras já tomadas ficam visualmente apagadas com um X pintado.
> 5. Ao entrar no lobby, o jogador recebe automaticamente a primeira cor livre.
> 6. A cor precisa persistir nas cenas seguintes — ler sempre de `GerenteSessao`, nunca guardar no nó do player.
>
> **Critério de aceite:** dois jogadores não conseguem ficar com a mesma cor; a cor escolhida no lobby continua no jogador dentro da casa.

---

### Card 07 — Convite e entrada de jogadores (Steam)

> **Objetivo:** convidar amigos e ver quem entrou.
>
> **O que fazer:**
> 1. Usar o sistema de lobby GodotSteam já existente no projeto (App ID 480 em desenvolvimento). Não reescrever o lobby — só estender.
> 2. Estação de rádio na van: interagir abre o overlay de convite da Steam (`Steam.activateGameOverlayInviteDialog(lobby_id)`).
> 3. Tratar entrada por convite/linha de comando: se o jogo abrir com um lobby id, entrar direto no lobby e carregar `Lobby_Van`.
> 4. Ao entrar, o novo jogador recebe do host um pacote com o estado completo (`jogadores`, `contrato_atual`, `fase_atual`) antes de spawnar.
> 5. Limite de 4 jogadores; lobby cheio recusa com mensagem clara.
> 6. **Só é possível entrar durante a fase `LOBBY`.** Convite aceito em fase posterior recebe recusa educada ("partida em andamento").
> 7. Saída de jogador: remove do `GerenteSessao`, libera a cor e reavalia `todos_prontos()`.
>
> **Critério de aceite:** convite pela overlay funciona com duas contas Steam; o segundo jogador vê a cor e o contrato já escolhidos antes de spawnar.

---

### Card 08 — Estação de contrato

> **Objetivo:** escolher qual casa/contrato será jogado.
>
> **O que fazer:**
> 1. Criar `res://dados/contratos/` com recursos `.tres` (`ContratoRecurso`): id, nome do cliente, endereço, cena da casa, nível de infestação, recompensa, dificuldade e textura da planta baixa.
> 2. Criar 3 contratos de teste, de dificuldade crescente.
> 3. Prancheta física na van: interagir abre uma visão em close (câmera dedicada, não menu flutuante) com as fichas dos contratos e setas para folhear.
> 4. Qualquer jogador pode folhear, mas **só o host confirma**. Cliente interagindo no botão de confirmar recebe aviso "só o líder escolhe o contrato".
> 5. Contrato confirmado → broadcast; a ficha do contrato ativo aparece pregada na parede da van, visível a todos.
> 6. Bloquear o pronto enquanto nenhum contrato estiver selecionado.
>
> **Critério de aceite:** o contrato escolhido pelo host aparece na parede para os dois jogadores e sobrevive à troca de cena.

---

## BLOCO C — Van em movimento (preparo, 120s)

### Card 09 — Cena `Van_Trajeto`

> **Objetivo:** a mesma van, agora em movimento, com 2 minutos de preparo.
>
> **O que fazer:**
> 1. Criar `res://cenas/van_trajeto.tscn` reaproveitando o interior de `Lobby_Van`, com as diferenças: porta traseira fechada, luz de teto trepidando e janelas mostrando a estrada.
> 2. Movimento fingido: a van fica parada e o cenário externo passa. Usar um `Sprite3D`/plano com textura de estrada em scroll UV, mais um `AnimationPlayer` com trepidação sutil na câmera. Não mover o jogador nem usar física de veículo.
> 3. Loop de som de motor + rádio abafado ao fundo.
> 4. Ao entrar na fase, `GerenteFase` inicia o timer de 120s automaticamente.
> 5. Adicionar duas estações novas: **Loja** (Card 10) e **Mesa do Mapa** (Card 11). Manter a estação de **Pronto**.
> 6. Armas ficam habilitadas nesta fase — o jogador pode equipar o que comprou e testar o sistema de mãos.
>
> **Critério de aceite:** timer de 120s corre igual nos dois clientes e a fase avança sozinha ao zerar.

---

### Card 10 — Loja da van

> **Objetivo:** comprar armas e armadilhas durante o trajeto.
>
> **O que fazer:**
> 1. Criar `res://dados/itens/` com recursos `ItemRecurso`: id, nome, preço, tipo (`ARMA_UMA_MAO`, `ARMA_DUAS_MAOS`, `ARMADILHA`, `ISCA`, `TAPA_BURACO`), cena do item na mão, ícone.
> 2. Itens iniciais: vassoura, arma de choque, bastão de baseball, pistola, ratoeira, armadilha de cola, isca, tapa-buraco. Respeitar as regras de mãos da Fase 2 (`GerenteMaos`): lanterna sempre na mão esquerda, itens de duas mãos removem a lanterna.
> 3. Prateleira física com os itens expostos; interagir num item compra uma unidade.
> 4. Compra é validada pelo host: confere `dinheiro` em `GerenteSessao`, debita, adiciona ao `inventario` e faz broadcast. Cliente nunca debita localmente.
> 5. Dinheiro é individual por jogador; cada um compra o seu.
> 6. Sem dinheiro → som de recusa e a etiqueta de preço pisca em vermelho.
> 7. Compras só são permitidas na fase `TRAJETO`. Na `VISTORIA` e na `CACA` a prateleira nem existe.
>
> **Critério de aceite:** dois jogadores comprando ao mesmo tempo têm saldos independentes e corretos; o item comprado aparece na mão dentro da casa.

---

### Card 11 — Mesa do mapa (planta da casa)

> **Objetivo:** estudar a planta antes de entrar.
>
> **O que fazer:**
> 1. Mesa no fundo da van com a planta baixa do contrato ativo (textura vinda do `ContratoRecurso`).
> 2. Interagir entra em modo close da mesa: câmera fixa sobre a planta, com zoom e arrasto.
> 3. Marcar na planta os pontos de interesse já conhecidos: entradas, cômodos e buracos suspeitos. Manter genérico — a posição real dos ratos não é revelada aqui.
> 4. Permitir que o jogador coloque até 3 marcadores (pinos) na planta, **visíveis para todos os jogadores** — é a ferramenta de combinação de estratégia da equipe.
> 5. Sair do modo close com `Esc` ou o botão de interação.
> 6. Esta mesma mesa reaparecerá na fase de vistoria como item de mão (mapa dobrado) — deixe o código do visualizador reutilizável, separado do nó da mesa.
>
> **Critério de aceite:** o pino colocado por um jogador aparece na tela do outro em menos de 1 segundo.

---

## BLOCO D — Casa: vistoria e caça

### Card 12 — Cena `Casa` e fase `VISTORIA` (60s)

> **Objetivo:** entrar na casa com 1 minuto para inspecionar e instalar armadilhas.
>
> **O que fazer:**
> 1. Criar `res://cenas/casa.tscn` que carrega dinamicamente a casa do `contrato_atual`. Spawn de todos os jogadores na porta da frente.
> 2. Ao entrar na fase `VISTORIA`: timer de 60s, **nenhum rato spawnado**, todos os buracos e rotas de fuga visíveis com um leve destaque visual (partícula de poeira ou contorno sutil, coerente com PSX).
> 3. Armas de ataque ficam **bloqueadas** nesta fase; só armadilhas, iscas, tapa-buracos, lanterna e mapa podem ser equipados. `GerenteMaos` deve recusar o equipamento com som de negação.
> 4. Instalação de armadilha: posicionamento por raycast com pré-visualização fantasma, validado pelo host e replicado para todos. Armadilha instalada é um nó persistente que **não some na troca de fase**.
> 5. Mapa dobrado como item de mão, reaproveitando o visualizador do Card 11.
> 6. Estação de pronto vira um botão físico no hall de entrada; todos prontos ou timer zerado avança para `CACA`.
>
> **Critério de aceite:** armadilha instalada durante a vistoria continua exatamente no lugar quando a caça começa.

---

### Card 13 — Início da fase `CACA`

> **Objetivo:** transição da vistoria para a caça sem recarregar a cena.
>
> **O que fazer:**
> 1. `GerenteFase` muda para `CACA` mantendo `Casa.tscn` na tela. Jogadores, armadilhas e inventário permanecem exatamente como estavam.
> 2. Transição sentida: cortar a luz da casa por 1 segundo, tocar um som de guincho de ratos e ligar a iluminação de fase de caça (mais escura, lanterna passa a ser essencial).
> 3. Host spawna os ratos com base na `semente_aleatoria` e no nível de infestação do contrato, sempre em ninhos longe dos jogadores.
> 4. Destaque visual dos buracos é removido — a partir daqui vale o que a equipe memorizou na vistoria.
> 5. Desbloquear todas as armas no `GerenteMaos`. Instalação de armadilha continua permitida, mas com um tempo de aplicação maior (o rato já está solto).
> 6. Sem timer nesta fase; ela termina quando todos os ratos forem eliminados ou capturados, indo para `RESULTADO`.
>
> **Critério de aceite:** a troca de vistoria para caça acontece sem tela de loading e sem reposicionar ninguém.

---

### Card 14 — Robustez de rede (rodar por último)

> **Objetivo:** impedir que a partida trave por causa de desconexões.
>
> **O que fazer:**
> 1. **Host sai:** encerrar a partida para todos com uma tela de aviso e voltar ao menu principal. Não tentar migração de host nesta fase do projeto.
> 2. **Cliente sai no meio da partida:** remover do `GerenteSessao`, sumir com o corpo, manter as armadilhas dele instaladas e reavaliar `todos_prontos()` imediatamente.
> 3. **Entrada tardia:** bloqueada fora da fase `LOBBY`, com mensagem clara.
> 4. Cliente que receber uma mudança de fase de alguém que não é o host deve ignorar o pacote e logar aviso.
> 5. Todos os `rpc` de compra, cor, pronto e instalação devem ser `rpc("any_peer")` chamando **apenas o host**, que valida e faz o broadcast com `rpc("authority")`. Auditar se nenhum RPC está escrito para aplicar efeito direto sem passar pelo host.
> 6. Teste manual documentado: matar o processo do cliente 2 em cada uma das quatro fases e confirmar que o cliente 1 continua jogando.
>
> **Critério de aceite:** nenhum dos cenários acima deixa a partida travada esperando um jogador que não existe mais.
