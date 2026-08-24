# RATS — Fase 4: Correção dos bugs de multiplayer

Lista de prompts para executar **um de cada vez, na ordem**. Cada prompt é
independente o bastante para ser colado sozinho, mas a ordem importa: os
primeiros consertam a *causa raiz* de vários sintomas de baixo, e os últimos
supõem que os primeiros já foram aplicados.

## Diagnóstico rápido (o que a investigação encontrou)

Os 8 bugs relatados não são 8 problemas. São **quatro** causas:

| Causa | Bugs que ela explica |
|---|---|
| **A.** O crew (`SessionManager.players`) não está sendo preenchido nos clientes / no host — o handshake do `JoinGate` não fecha | 2, 3, 4 |
| **B.** Os avatares (`player_avatars.gd`) não sobem ou sobem sem autoridade correta | 1 |
| **C.** Nada em `rat.gd` nem em `trap_weapon.gd` toca a rede — tudo é instanciado **localmente** | 5, 6 |
| **D.** Não existe menu de pause no projeto | 7, 8 |

O ponto mais importante: **B e C não têm relação um com o outro**. Mesmo que o
lobby fique perfeito, ratos e armadilhas continuarão invisíveis, porque
`scripts/rat.gd` (1425 linhas) não tem uma única chamada de `rpc`, e
`trap_weapon._place()` só faz `instantiate()` + `add_child()` na máquina local.

---

## Prompt 1 — Diagnosticar por que o crew fica em 1/1

> Antes de corrigir qualquer coisa, quero entender por que o contador de ready
> mostra `1/1` mesmo com várias pessoas no lobby.
>
> O contador vem de `ReadyManager.counts()`, que devolve
> `[SessionManager.ready_count(), SessionManager.count()]`. Se ele diz 1/1, então
> `SessionManager.players` tem **uma única entrada** em cada máquina — ou seja, o
> handshake do `JoinGate` não está completando.
>
> Investigue e me diga exatamente onde a corrente quebra, sem ainda alterar a
> lógica:
>
> 1. Em `scripts/session/join_gate.gd`, o cliente só bate na porta em
>    `_on_connected_to_server()` (linha ~388), ligado ao sinal
>    `multiplayer.connected_to_server`. Confirme se esse sinal realmente dispara
>    no cliente com o `SteamMultiplayerPeer` — e também no wire ENet local.
> 2. Confirme se `LobbyManager.our_steam_id()` devolve algo diferente de zero no
>    momento do `knock()`. Se devolver 0, o host responde `REFUSAL_UNKNOWN` e o
>    cliente é expulso — o que também explicaria o bug 4.
> 3. Confirme se `JoinGate._admitted` está de fato chegando nas máquinas que já
>    estavam na van (é o `rpc` com `call_local` que constrói a entrada do
>    recém-chegado no crew dos outros).
> 4. Verifique se os autoloads (`JoinGate`, `SessionManager`, `PhaseManager`)
>    têm o **mesmo caminho de nó** nas duas máquinas — um `rpc` em autoload só
>    encontra o destino se o NodePath for idêntico dos dois lados.
>
> Adicione `print()` temporários em: `JoinGate.knock()`, `_handle_knock()`,
> `_admitted()`, `_apply_welcome()` e `SessionManager.register_player()`,
> mostrando o steam_id, o peer id e o tamanho do crew depois de cada passo.
> Rode duas instâncias com o wire ENet local e me mostre os logs dos dois lados.

## Prompt 2 — Corrigir o handshake de entrada no crew (bugs 2, 3, 4)

> Com base no diagnóstico do prompt anterior, corrija o handshake do `JoinGate`
> para que **todas as máquinas terminem com o mesmo crew**.
>
> Requisitos da correção:
>
> - O cliente deve bater na porta de forma **confiável**, não apenas via
>   `connected_to_server`. Se `LobbyManager.our_steam_id()` ainda for 0 quando o
>   wire subir, o `knock()` deve *esperar* a introdução chegar
>   (`LobbyManager.peer_identified`) e então bater — em vez de bater com
>   `steam_id = 0` e ser recusado com `REFUSAL_UNKNOWN`.
> - Adicione um **retry** com timeout: se um knock ficar sem resposta por ~3
>   segundos e ainda estivermos conectados, bata de novo. O `_knocking` de hoje
>   bloqueia o segundo knock para sempre, então um único pacote perdido deixa o
>   jogador fora do crew permanentemente.
> - Garanta que o host também entre no próprio crew (`_admit_host`) **antes** de
>   qualquer cliente ser admitido, para que `_snapshot()` nunca saia vazio.
> - Mantenha o padrão do arquivo: o host decide, o `rpc` de resposta é
>   `authority` + `call_local`, e clientes nunca escrevem no crew por conta
>   própria.
>
> Depois de corrigir, valide com duas instâncias: o contador em `hud_phase.gd`
> deve mostrar `1/2` e `2/2`, e apertar pronto num cliente deve mudar o número
> **na tela do host** (é o bug 3, que é o mesmo bug do 2 visto de outro ângulo).

## Prompt 3 — Fazer os avatares aparecerem e se moverem (bug 1)

> O host não vê os outros jogadores andando. Os avatares são criados em
> `scripts/steam/player_avatars.gd`, que instancia `player_avatar.tscn` local em
> cada máquina, nomeia como `Player<peer_id>`, e confia num
> `MultiplayerSynchronizer` para replicar a pose.
>
> Investigue e corrija:
>
> 1. Confirme se `_open()` roda de fato. Ele só é chamado se
>    `multiplayer.multiplayer_peer` não for nulo/offline **no `_ready()` da
>    cena** — se o wire subir depois da van carregar, ninguém sobe avatar
>    nenhum. Trate esse caso.
> 2. Confirme se `player_path` (`^"../Player"`) resolve dentro de
>    `lobby_van.tscn`, `van_travel.tscn` e `world.tscn`. Um `get_node` falhando
>    em `_stand_apart()` derruba a função inteira **antes** de qualquer avatar
>    ser criado.
> 3. Verifique o `SceneReplicationConfig` em `scenes/player_avatar.tscn`: quais
>    propriedades estão listadas, se `sync_position`/`sync_rotation` estão lá, e
>    se o modo de replicação é `always`/`on_change` e não `never`.
> 4. Confirme que o avatar local realmente segue o corpo do jogador
>    (`avatar.follow(...)`) e que ele **escreve** nas variáveis `sync_*` todo
>    frame — se ninguém escreve, o sincronizador replica valores parados.
>
> Verifique também se o avatar do próprio jogador está escondido só para ele
> mesmo (é o comportamento pretendido, descrito em `player_avatar.gd`), e não
> para todo mundo — isso sozinho já produziria exatamente o sintoma relatado.

## Prompt 4 — Sincronizar os ratos entre as máquinas (bug 6)

> Nenhum rato aparece para quem está conectado. A causa é direta: **`rat.gd` não
> tem nenhuma rede**. Os ratos nascem em `house.gd::_spawn_rats_if_needed()`,
> que já é `is_host()`-only (linha ~289), então o cliente simplesmente nunca
> instancia rato algum e nada os envia pelo wire.
>
> Implemente a replicação dos ratos:
>
> - Use um `MultiplayerSpawner` no `world.tscn` apontado para o nó `Rats`
>   (`house.rats_root()`), com `res://scenes/rat.tscn` na lista de cenas
>   auto-spawnáveis. Assim o `add_child` do host replica o rato nos clientes.
> - O nome do nó precisa ser determinístico e idêntico nos dois lados —
>   `house.gd` já nomeia `Rat_%d`, mantenha isso, mas confirme que o nome é
>   atribuído **antes** do `add_child`, senão o spawner replica com o nome
>   automático da engine.
> - A autoridade de cada rato deve ser do host (peer 1). Defina antes de entrar
>   na árvore.
> - Adicione um `MultiplayerSynchronizer` em `rat.tscn` replicando posição,
>   rotação e o estado de animação/comportamento que o cliente precisa desenhar.
> - Toda a IA (navegação, decisão, perseguição) deve rodar **só no host**.
>   Adicione uma guarda no `_physics_process` do rato: quem não é autoridade não
>   pensa, só desenha o que chega.
> - A morte do rato (`died`) e a contagem (`_on_rat_died`,
>   `_check_hunt_completion`) já são host-only — garanta que o rato seja
>   removido nos clientes pela mesma via (o spawner cuida disso no `queue_free`
>   do host).
>
> Atenção: `rat.gd` tem 1425 linhas. Não reescreva o arquivo. Adicione as
> guardas de autoridade e o sincronizador com o mínimo de mudança possível,
> mantendo o jogo solo funcionando exatamente como hoje (sem peer, o host é
> sempre a própria máquina).

## Prompt 5 — Sincronizar as armadilhas colocadas (bug 5)

> Armadilhas não aparecem para os outros jogadores. Em
> `scripts/weapons/trap_weapon.gd`, o método `_place()` (linha ~176) faz
> `trap_scene.instantiate()` + `_traps_root().add_child(trap)` — puramente
> local. Nada disso vai para a rede.
>
> Implemente a colocação de armadilhas em rede:
>
> - O cliente **pede** ao host para colocar a armadilha, o host valida e
>   **anuncia** para todos — o mesmo padrão que `ReadyManager.request_set` /
>   `_apply` e `ColorManager` já usam neste projeto. Siga esse padrão, não
>   invente um novo.
> - O pedido carrega: o id/tipo da armadilha, a posição, a rotação (ou o vetor
>   `facing`) e o `length` (o glue trap se estica).
> - O host valida antes de aceitar: a fase é a certa, o jogador tem o item no
>   inventário (`SessionManager.inventory`), e a posição é plausível.
> - O host debita o item do estoque do jogador de forma autoritativa. Hoje
>   `Wallet` e `Stock` ainda são single-player — se o débito não puder ser
>   autoritativo agora, deixe explícito com um comentário `# TODO` e trate na
>   fase seguinte, mas **não** deixe dois jogadores gastando o mesmo item.
> - Use um `MultiplayerSpawner` no nó `Traps` de `world.tscn` com
>   `glue_trap.tscn` e `mousetrap.tscn` registrados, ou um `rpc` `authority` +
>   `call_local` que instancia nas duas pontas. Prefira o spawner por
>   consistência com o prompt anterior.
> - O nome do nó não pode ser o `trap.get_script().get_global_name()` de hoje:
>   duas armadilhas do mesmo tipo colidiriam de nome. Use um contador
>   monotônico do host (`Mousetrap_1`, `Mousetrap_2`, …).
> - O **ghost** (a prévia translúcida) continua local e não deve nunca ir para a
>   rede.
> - A armadilha disparando (pegar um rato) também precisa ser autoritativa do
>   host, senão duas máquinas contam a mesma captura.

## Prompt 6 — Criar o menu de pause (bug 7)

> Não existe menu de pause no projeto — procurei e só há `process_mode` em
> autoloads. Crie um.
>
> Requisitos:
>
> - Nova cena `scenes/pause_menu.tscn` + `scripts/ui/pause_menu.gd`, presente
>   nas cenas jogáveis (`lobby_van.tscn`, `van_travel.tscn`, `world.tscn`).
> - Abre e fecha com `ui_cancel` (Esc). Repare que a ação `cancel` do
>   `project.godot` já mapeia Esc **e** o botão direito do mouse — use
>   `ui_cancel` ou crie uma ação `pause` dedicada, para não abrir o menu quando
>   o jogador clica com o botão direito.
> - Ao abrir: `get_tree().paused = true` e o mouse volta a ficar visível. Ao
>   fechar: despausa e recaptura o mouse.
> - **O pause é local, nunca global.** Este é um jogo online: a pausa de um
>   jogador não pode congelar a partida dos outros. O jogo continua rodando
>   para todo mundo; o menu só solta o mouse e para de ler input do jogador
>   local.
> - Como consequência, os nós que precisam continuar funcionando com a árvore
>   pausada devem ter `PROCESS_MODE_ALWAYS` — os autoloads de sessão já têm
>   (`JoinGate`, `PhaseManager`, `ReadyManager`, `ColorManager`, `SteamManager`
>   e outros já fazem isso e os comentários deles citam o menu de pause
>   nominalmente). Confirme que o avatar local e o sincronizador dele também
>   continuam mandando pose, senão o jogador pausado "congela" na tela dos
>   outros.
> - Botões: Continuar, Sair da partida, Sair do jogo.
> - O "Sair da partida" deve chamar `LobbyManager.leave_lobby()` e voltar para
>   `scenes/lobby.tscn`. Verifique que `NetworkGuard` e `JoinGate._on_lobby_left`
>   limpam o estado direito (o `admitted` volta a false, o crew é esvaziado),
>   para que dar entrar de novo funcione sem reiniciar o jogo.

## Prompt 7 — Lista de jogadores conectados com ping no pause (bug 8)

> Com o menu de pause já existindo, adicione nele a lista de todos os jogadores
> conectados, com o ping de cada um.
>
> - A lista deve vir de `SessionManager.players` (o crew), não de
>   `LobbyManager.list_players()` — o crew é a verdade sobre quem está de fato
>   na partida, e depois do Prompt 2 ele estará correto. Mostre o nome, a cor
>   que a pessoa está usando e um marcador para o host.
> - O ping: para o wire ENet, `ENetMultiplayerPeer.get_peer(id)` devolve um
>   `ENetPacketPeer`, de onde sai o round-trip time. `lobby_manager.gd` já faz
>   exatamente esse acesso em `_set_timeout` (linha ~486) — reaproveite o mesmo
>   caminho. Para o `SteamMultiplayerPeer` esse dado pode não existir; nesse
>   caso implemente um ping próprio: um `rpc` de ida e volta com carimbo de
>   tempo, medido a cada 1–2 segundos.
> - Exponha isso como um método em `LobbyManager` (algo como
>   `ping_of_peer(peer_id) -> int`, em ms, com -1 para desconhecido) em vez de o
>   menu de pause cavar dentro do peer sozinho.
> - Atualize a lista a cada meio segundo enquanto o menu estiver aberto, e não
>   todo frame.
> - Trate o jogo solo: sem wire, a lista mostra só o jogador local, sem ping.

## Prompt 8 — Teste de ponta a ponta com duas instâncias

> Rode o fluxo inteiro com duas instâncias usando o wire ENet local e confirme,
> um por um, os 8 bugs originais:
>
> 1. O host vê o outro jogador andando pela van.
> 2. O contador mostra `x/2` e não `1/1`.
> 3. Dar pronto num cliente muda o número na tela do host.
> 4. A lista mostra todos os conectados.
> 5. Uma armadilha colocada por um aparece para o outro.
> 6. Os ratos aparecem para o cliente na fase de caça.
> 7. Esc abre o pause e "Sair da partida" volta ao lobby limpo.
> 8. O pause lista todos os conectados com ping.
>
> Depois disso, teste o caminho inverso, que é onde esse tipo de correção
> costuma quebrar: entrar, sair pelo pause, e **entrar de novo na mesma sessão**
> sem fechar o jogo. E teste o host saindo no meio de uma caça — todo mundo deve
> cair de volta na tela de lobby com uma mensagem, que é o que `NetworkGuard`
> promete fazer.
>
> Lembre-se: depois de qualquer `class_name` novo, rode
> `--headless --import` antes de testar.

---

## Ordem e dependências

```
Prompt 1 (diagnóstico)
   └─> Prompt 2 (crew)  ──> conserta bugs 2, 3, 4
         ├─> Prompt 3 (avatares)     ──> conserta bug 1
         └─> Prompt 7 (lista+ping)   ──> conserta bug 8   [precisa do Prompt 6]

Prompt 4 (ratos)      ──> conserta bug 6   [independente do lobby]
Prompt 5 (armadilhas) ──> conserta bug 5   [independente do lobby]
Prompt 6 (pause)      ──> conserta bug 7   [independente de tudo]

Prompt 8 (validação final)
```

Os prompts 4, 5 e 6 não dependem do 1–3. Se quiser resultado visível rápido,
o **Prompt 6** é o mais barato e o mais isolado de todos.
