# RATS

Jogo 3D feito na Godot 4.7 (Forward Plus, Jolt Physics).

## Rodando o projeto

1. Instale a [Godot 4.7](https://godotengine.org/download).
2. Abra a Godot, clique em **Import** e selecione o `project.godot` deste repositório.
3. Rode com `F5`.

## Controles

| Tecla | Ação |
| --- | --- |
| `WASD` / setas | Andar (relativo a para onde se está olhando) |
| `Shift` | Correr |
| `Espaço` | Pular |
| Mouse | Olhar em volta |
| Botão esquerdo | Agarrar o rato |
| Botão esquerdo (com um rato na mão) | Esganar |
| `Esc` | Soltar/recapturar o mouse |

De mãos ocupadas o mesmo clique que agarrou passa a esganar, e o jogador anda
devagar: com um rato se debatendo nas mãos não se corre nem se pula.

## Os ratos

Dez ratos vivem soltos pelo mapa. Cada um tem quatro comportamentos:

- **Passeando** — anda devagar até um ponto qualquer por perto e às vezes para para farejar.
- **Fugindo** — ao ouvir o jogador a menos de 6 m, ou ao vê-lo a menos de 16 m
  (mais longe ainda se ele estiver correndo), dispara em fuga. O arranque é mais
  rápido que a corrida do jogador, mas depois ele cansa e passa a correr um pouco
  mais devagar do que ela — dá para alcançar.
- **Escondido** — enquanto foge, ele procura os obstáculos em volta e corre para o
  ponto cego atrás de um deles, fora da linha de visão do jogador. Chegando lá,
  se agacha e fica imóvel: só dispara de novo se for visto ou se o jogador chegar
  a menos de 3 m.
- **Capturado** — agarrado, ele é arrancado do chão e vai parar na mão do jogador.
- **Morto** — esganado na mão, ou largado no chão já sem vida.

A caçada, então, é dobrar a esquina: enquanto o rato acha que está escondido,
ele não sai do lugar, e é aí que dá para pegá-lo.

## Matando rato

O jogo vai ter várias armas, e a primeira delas são as próprias mãos. Toda arma
mora debaixo da cabeça do jogador (`scripts/armas/`), herda de `Arma` e procura
o alvo do mesmo jeito: o rato mais próximo dentro de 2,6 m e de um cone de 50°
em volta da mira, desde que não haja parede no caminho. O que muda de uma para
outra é o que ela faz com o rato que achou.

As mãos não matam: elas **agarram**. O rato se encolhe no chão, é arrancado num
arco, dá uma cambalhota no ar e para no meio da tela, preso, se debatendo e
tentando morder. Daí em diante o mesmo clique é que mata: cada um aperta um
pouco mais o pescoço dele, e o aperto escorre sozinho enquanto o jogador não
clica de novo. Martelando sem parar são uns treze apertos. Martelando
devagar são mais — e se a barra chegar a zero e ficar lá, o rato se solta da
mão, pula para longe e dispara em fuga com uns segundos de vantagem em que não
dá para reagarrá-lo.

As mãos são o único jeito de matar rato por enquanto. Uma arma que resolva num
golpe só precisa herdar de `Arma` e sobrescrever o `_usar()`.

### Por onde eles andam

Os ratos andam por uma malha de navegação assada quando o mapa abre, a partir
dos corpos estáticos do grupo `cenario` (`scripts/navegacao.gd`). É ela que
resolve o problema de rato empacado na parede: em vez de correr no rumo do
esconderijo e ir esbarrando no que aparecer, cada um segue um caminho que já vem
contornando as caixas.

Escolher o esconderijo é dar nota a uma dúzia de candidatos — os pontos cegos
atrás dos obstáculos por perto, mais um leque de pontos para trás. Ganha nota
quem está longe do jogador, quem some da linha de visão dele e quem tem saída
por onde correr depois; perde nota quem fica longe demais e, principalmente,
quem só é alcançável passando raspando em quem está caçando. Candidato dentro de
uma caixa ou em cima de uma plataforma que não dá para subir nem entra na
conta — o caminho até ele não existe.

Sobrou um jeito de o rato ficar preso mesmo assim (empurrado para fora da malha,
espremido numa quina): se ele passar meio segundo querendo andar sem sair do
lugar, dá um passo de lado e procura outro caminho.

### O modelo

O rato é o modelo de `mobs/rats/`, com esqueleto de 13 ossos e as animações que
vieram no pacote: `Rat|Idle`, `Rat|Idle_Break` (a pausa em que ele fareja o ar),
`Rat|Run`, `Rat|Death` e `Rat|Attack`. A animação escolhida segue a velocidade do
rato, e o ciclo de corrida acelera junto com ela — passeando ele trota, fugindo
ele dispara, e preso na mão o mesmo ciclo vira o esperneio das patas no ar. A
mordida é a única coisa que este rato medroso nunca faz solto pelo mapa: ela só
aparece quando ele já está sendo esganado e não tem mais o que perder.

Cada rato sorteia uma das quatro pelagens do pacote (`Rat.png` a `Rat_4.png`) ao
nascer, então o bando sai malhado de cinza, marrom e branco.

O FBX foi exportado com a cena inteira do Blender — a luz e a câmera do autor
vieram junto, e todas as animações têm faixas apontando para elas. Quem limpa
isso na importação é `mobs/rats/limpar_importacao.gd`, um script de pós-importação
que também descarta as animações duplicadas e marca o repouso e a corrida como
cíclicas.

O `Rat.blend` fica guardado como arquivo-fonte, mas quem o projeto importa é o
`Rat_Fbx.fbx`. Por isso `filesystem/import/blender/enabled` está desligado nas
configurações do projeto: sem isso a Godot tenta abrir o `.blend` e exige uma
instalação do Blender para rodar o jogo.

## Estrutura

- `scenes/` — cenas do jogo (`mundo.tscn` é a cena principal, `jogador.tscn` é o
  personagem e `rato.tscn` é o mob)
- `scripts/` — scripts GDScript (`jogador.gd` controla o movimento em primeira pessoa,
  `rato.gd` a IA dos ratos e a captura, `navegacao.gd` assa a malha por onde eles
  andam, `contador_ratos.gd` o placar do HUD e `hud_esganamento.gd` o aviso do esganamento)
- `scripts/armas/` — as armas do jogador: `arma.gd` é a base de todas e `maos.gd`
  é a primeira delas, a que agarra e esgana
- `models/` — modelos 3D (`.glb`) e seus arquivos de import
- `mobs/rats/` — o modelo do rato: `Rat_Fbx.fbx` (malha, esqueleto e animações),
  as quatro texturas de pelagem, o `Rat.blend` de origem e o script de
  pós-importação
- `shaders/` — shaders (`chao_xadrez.gdshader` desenha o piso quadriculado)
- `icon.svg` — ícone do projeto

O mapa é um quadrado cinza de 60x60 unidades, cercado por paredes e com blocos,
caixas, colunas, rampas e plataformas feitos de formas geométricas simples — que
são também os esconderijos dos ratos.

As camadas de física são `1: cenario`, `2: jogador` e `3: ratos`. Os ratos não
esbarram no jogador nem uns nos outros; só o cenário os detém.

A pasta `.godot/` é gerada pela engine e não é versionada.
