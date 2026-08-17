extends CharacterBody3D
## Rato: um mob medroso. Passeia devagar pelo mapa, dispara em fuga quando o
## jogador chega perto e procura um ponto fora da linha de visão dele para se
## esconder. Quando o jogador o agarra, ele é arrancado do chão e vai parar na
## mão dele, onde se debate até ser esganado — e então é guardado na cintura — ou
## até se soltar e voltar a fugir.
##
## Tanto o passeio quanto a fuga andam pela malha de navegação assada no
## `mundo.tscn`: ele só escolhe destinos que dá para alcançar, e o caminho até
## eles já vem contornando as paredes e as caixas.

signal morreu(rato: Node3D, tipo_morte: Morte.Tipo)

enum Estado { PASSEANDO, PARADO, FUGINDO, ESCONDIDO, CAPTURADO, MORTO }

## As batidas da captura, do agarrão até o corpo morto ser guardado na cintura.
enum Captura { BOTE, SUBINDO, NA_MAO, AMOLECENDO, GUARDANDO }

@export_group("Espécie")
## Que rato é este: de onde saem a pelagem e o preço dele. Ver
## `recursos/especies/`.
@export var especie: EspecieRato

@export_group("Movimento")
@export var velocidade_passeio := 2.2
## Velocidade de fuga: menor que a corrida do jogador, maior que a caminhada.
@export var velocidade_fuga := 7.0
## Disparada do susto, nos primeiros instantes da fuga.
@export var velocidade_arranque := 9.5
@export var aceleracao := 45.0
@export var gravidade := 22.0
@export var velocidade_giro := 11.0

@export_group("Percepção")
## Distância em que o rato foge se estiver vendo o jogador.
@export var raio_alerta := 16.0
## Distância em que ele foge mesmo sem ver o jogador (ouviu os passos).
@export var raio_panico := 6.0
## Escondido ele prende a respiração e só dispara se o jogador quase o pisa.
@export var raio_panico_escondido := 3.0
## Distância a partir da qual ele se sente seguro de novo.
@export var raio_seguro := 26.0

@export_group("Vida")
@export var vida_maxima := 1
@export var forca_empurrao := 5.0

## Altura dos olhos do rato, usada nos testes de linha de visão.
const ALTURA_OLHOS := 0.25
## Altura do peito do jogador, o ponto que o rato tenta enxergar.
const ALTURA_JOGADOR := 1.2
## Só o cenário entra nos testes de visão e de espaço livre (camada 1).
const CAMADA_CENARIO := 1
## Alcance dos "bigodes" que farejam parede à frente. Eles só entram em campo
## quando o rato está sem caminho pela malha e precisa correr no faro.
const ALCANCE_BIGODE := 2.2
## Ângulos (graus) testados ao contornar um obstáculo, do desvio menor ao maior.
const ANGULOS_DESVIO := [32.0, -32.0, 64.0, -64.0, 100.0, -100.0]
## Quanto tempo dura a disparada inicial da fuga.
const TEMPO_ARRANQUE := 1.2
## De quanto em quanto tempo ele reavalia o esconderijo enquanto foge.
const INTERVALO_BUSCA := 0.6
## Raio em que ele procura obstáculos para usar como cobertura.
const RAIO_COBERTURA := 14.0
## Quantos obstáculos ele considera por busca.
const MAX_COBERTURAS := 10
## Passos dados atrás de um obstáculo à procura do ponto cego.
const PASSOS_COBERTURA := 8
const PASSO_COBERTURA := 1.5
## Pontos sorteados para trás em cada busca, além das coberturas.
const CANDIDATOS := 10
## Abertura (radianos) do leque de fuga, para cada lado do "longe do jogador".
const ABERTURA_LEQUE := 1.8
const DISTANCIA_MIN_BUSCA := 3.0
const DISTANCIA_MAX_BUSCA := 15.0
## Distância máxima que um destino pode estar da malha de navegação. Acima disso
## ele caiu dentro de uma parede ou fora do mapa e não serve de destino.
const TOLERANCIA_MALHA := 1.5
## Desnível máximo aceito num destino — o rato não escala caixas.
const DESNIVEL_MAXIMO := 1.5
## Quanto vale, na nota do esconderijo, sumir da vista do jogador.
const BONUS_ESCONDIDO := 25.0
## Quanto vale cada saída livre em volta do esconderijo: um buraco sem saída
## esconde bem, mas deixa o rato sem para onde correr depois.
const BONUS_SAIDA := 3.0
const ALCANCE_SAIDA := 2.5
## Peso do comprimento do caminho na nota: perto é melhor que longe.
const PESO_CAMINHO := 0.6
## Multa para o caminho que passa raspando no jogador.
const MULTA_PASSAR_PERTO := 60.0
## Tempo empurrando contra uma quina antes de sacudir para o lado.
const TEMPO_TRAVADO := 0.6
## Duração do passo de lado que desencaixa o rato da quina.
const TEMPO_DESVIO := 0.4
## Tempo que a carcaça fica no chão antes de sumir.
const TEMPO_CARCACA := 1.4
## Altura em que o rato é devolvido ao ponto onde nasceu.
const ALTURA_MINIMA := -20.0
## Escala do modelo quando o rato está agachado no esconderijo.
const ESCALA_AGACHADO := Vector3(1.1, 0.6, 1.0)
const PONTO_INVALIDO := Vector3.INF

# --- Medidas da captura ----------------------------------------------------
## O bote: o instante em que ele se encolhe no chão, antes de ser arrancado. É
## curto de propósito — é só a antecipação que faz o puxão seguinte ler como puxão.
const TEMPO_BOTE := 0.1
## Quanto dura a subida do chão até a mão.
const TEMPO_SUBIDA := 0.35
## Altura do arco da subida sobre a reta chão-mão: sem isso ele *desliza* até a
## mão em vez de ser arrancado.
const ALTURA_ARCO := 0.55
## A cambalhota que ele dá no ar enquanto sobe, desmanchando conforme ele chega.
const GIRO_CAMBALHOTA := PI
## Como o rato fica na mão: de pé, quase na vertical, com a barriga e o focinho
## virados para o jogador — a cabeça tomba um pouco para a frente, e o corpo fica
## torto de lado, para não ficar de frente chapada para a câmera. O rabo e as
## patas de trás ficam pendurados embaixo dele.
const POSE_SEGURADA := Vector3(66.0, 200.0, 0.0)
## Como ele fica depois de morto, antes de ser guardado: o corpo tomba para a
## frente e desaba de lado, sem força nenhuma segurando a cabeça.
const POSE_AMOLECIDA := Vector3(16.0, 200.0, 28.0)
## Como ele desce pendurado ao ser guardado: de cabeça para baixo, torto, do
## jeito de quem já está segurando o bicho pelo rabo.
const POSE_GUARDADA := Vector3(-72.0, 200.0, 24.0)
## O meio do corpo dele, em coordenadas do próprio rato. A origem do rato está no
## chão, entre as patas, e o tronco (do focinho ao quadril) fica à frente e acima
## dela — é este ponto, e não a origem, que a mão põe no meio da tela. Sem isso o
## bicho é pendurado pelos pés e o corpo sai do quadro; de pé, o focinho chegava
## a passar a um palmo da câmera.
const CENTRO_DO_CORPO := Vector3(0.0, 0.2, -0.125)
## Encolhido no chão, no bote.
const ESCALA_BOTE := Vector3(1.2, 0.7, 1.2)
## Esticado no arranque — a barriga alonga quando ele sai do chão.
const ESCALA_ESTICADA := Vector3(0.85, 1.3, 0.85)
## Espremido, no quadro de cada aperto. Preso de pé, o que a câmera vê encolher é
## o *comprimento* dele, e não a altura de quem anda de quatro: a esmagada sai no
## eixo do corpo (Z) e o resto incha para os lados.
const ESCALA_ESMAGADO := Vector3(1.2, 1.2, 0.78)
## Quanto tempo o corpo leva para amolecer na mão antes de ser guardado.
const TEMPO_AMOLECIMENTO := 0.5
## Quanto dura a guardada: da mão até a cintura. O rato sai do quadro na primeira
## metade do gesto; o resto é o braço terminando de descer com ele.
const TEMPO_GUARDADA := 0.55
## Onde a mão leva o rato morto, em coordenadas do ponto de captura: para baixo,
## para o lado da mão e para perto do corpo do jogador, na altura da cintura.
## Fica fora do quadro — quem olhar para baixo vê o bicho descendo, quem estiver
## olhando para a frente só vê ele sair de cena por baixo.
const CINTURA := Vector3(0.22, -0.68, 0.42)
## O quanto o caminho até a cintura abre para fora antes de descer. É o que faz o
## gesto ler como pulso virando para guardar, e não como corpo caindo.
const DESVIO_GUARDADA := Vector3(0.15, 0.05, -0.08)
## A partir daqui, no fim da guardada, o corpo já sumiu na cintura.
const SUMICO_GUARDADA := 0.62
## Depois de escapar, ele fica um tempo impossível de reagarrar.
const TEMPO_IMUNIDADE := 1.5
## Agitação de quem está preso e ninguém está apertando. Nunca é zero: ele se
## debate o tempo todo.
const AGITACAO_BASE := 0.35
## Quanto da agitação de um aperto sobra depois de um segundo.
const AMORTECIMENTO_AGITACAO := 0.08
## Deslocamento (m) e rotação (graus) do tremor contínuo, com agitação cheia.
const TREMOR := 0.035
const TREMOR_ANGULO := 9.0
## Intervalo entre um esperneio e outro, e a força dele.
const INTERVALO_ESPERNEIO := Vector2(0.6, 1.0)
const FORCA_ESPERNEIO := 0.07
const FORCA_ESPERNEIO_ANGULO := 22.0
## Quanto do solavanco sobra depois de um segundo.
const AMORTECIMENTO_SOLAVANCO := 0.0005
## Chance de o esperneio virar uma mordida.
const CHANCE_MORDIDA := 0.35
## Cadência da corrida enquanto ele espernea no ar.
const CADENCIA_DEBATENDO := 1.8
## O tranco com que ele pula da mão ao se soltar.
const SALTO_ESCAPADA := 2.5

## Animações que vêm prontas do `mobs/rats/Rat_Fbx.fbx`. (Ele também traz uma
## `Rat|Attack`, que este rato medroso nunca usa.)
const ANIM_REPOUSO := "Rat|Idle"
## Pausa em que ele fareja o ar — usada de vez em quando no lugar do repouso.
const ANIM_FAREJANDO := "Rat|Idle_Break"
const ANIM_CORRIDA := "Rat|Run"
const ANIM_MORTE := "Rat|Death"
## A mordida que o rato medroso nunca usa solto pelo mapa — mas usa preso na mão
## de quem está esganando ele.
const ANIM_ATAQUE := "Rat|Attack"
## Chance de escolher a farejada em vez do repouso simples.
const CHANCE_FAREJADA := 0.3
## Velocidade em que o ciclo de corrida roda na cadência natural dele; mais
## devagar que isso ele trota, mais rápido ele dispara as patas.
const VELOCIDADE_CICLO := 4.5
const CADENCIA_MINIMA := 0.35
const CADENCIA_MAXIMA := 2.2
## Abaixo desta velocidade ele conta como parado.
const VELOCIDADE_PARADO := 0.35
## Tempo de mistura entre uma animação e outra.
const MISTURA := 0.15
## De que espécie é o rato que alguém largou no mapa sem dizer qual.
const ESPECIE_PADRAO := preload("res://recursos/especies/rato_comum.tres")

@onready var navegador: NavigationAgent3D = $Navegacao
@onready var modelo: Node3D = $Modelo
@onready var animador: AnimationPlayer = $Modelo/Malha/AnimationPlayer
## Caminho fundo porque acompanha a hierarquia que veio do FBX.
@onready var malha: MeshInstance3D = $"Modelo/Malha/Rat/Skeleton3D/Rat Model"

var _estado := Estado.PASSEANDO
var _vida := 1
var _jogador: Node3D
var _posicao_inicial: Vector3
var _alvo := Vector3.ZERO
var _tem_alvo := false
var _tempo_estado := 0.0
var _tempo_alvo := 0.0
var _tempo_busca := 0.0
var _tempo_travado := 0.0
var _tempo_desvio := 0.0
var _direcao_desvio := Vector3.ZERO
var _duracao_parado := 1.0
var _velocidade_desejada := 0.0
var _posicao_anterior := Vector3.ZERO
var _consulta_cobertura := PhysicsShapeQueryParameters3D.new()

var _fase_captura := Captura.BOTE
var _tempo_captura := 0.0
var _ponto_captura: Node3D
var _pai_original: Node
var _camada_original := 0
var _origem_subida := Vector3.ZERO
var _base_origem := Basis.IDENTITY
## De onde sai a guardada, já em coordenadas do ponto de captura: o corpo mole
## nunca para exatamente na mesma pose, então o gesto começa de onde ele parou.
var _origem_guardada := Vector3.ZERO
var _base_guardada := Basis.IDENTITY
var _agitacao := 1.0
var _solavanco := Vector3.ZERO
var _solavanco_giro := Vector3.ZERO
var _tempo_esperneio := 0.0
var _tempo_imune := 0.0

## De que ele morreu, e o quanto ele é grande para um da espécie dele: as duas
## metades do preço. `_pago` é a tranca para a recompensa não cair duas vezes.
var _tipo_morte := Morte.Tipo.INDEFINIDA
var _tamanho := 1.0
var _pago := false

func _ready() -> void:
	add_to_group("ratos")
	# `_process` é só da captura; solto pelo mapa o rato vive na física.
	set_process(false)
	if especie == null:
		especie = ESPECIE_PADRAO
	_tamanho = especie.sortear_tamanho()
	_vida = vida_maxima
	_preparar_consulta_cobertura()
	_posicao_inicial = global_position
	_posicao_anterior = global_position
	# Espalha as decisões dos ratos por quadros diferentes.
	_tempo_busca = randf() * INTERVALO_BUSCA
	_sortear_pelagem()
	_tocar_repouso()
	# Cada rato entra na animação num ponto diferente do ciclo, senão os dez
	# respiram no mesmo compasso.
	animador.seek(randf() * animador.current_animation_length, true)
	# Pode ser cedo demais: a malha recém-assada ainda não respondeu à primeira
	# sincronização do servidor. Nesse caso ele fica sem destino e o passeio
	# tenta de novo no quadro seguinte.
	_sortear_passeio()

func _physics_process(delta: float) -> void:
	_tempo_imune = maxf(0.0, _tempo_imune - delta)

	if _estado == Estado.MORTO:
		_aplicar_gravidade(delta)
		move_and_slide()
		return

	# Na mão do jogador ele sai da física por inteiro: quem manda no corpo dele
	# agora é o `_process`, que roda no compasso da tela e não no dos 60 Hz —
	# preso na câmera, qualquer descompasso entre os dois aparece como tremida.
	if _estado == Estado.CAPTURADO:
		return

	_tempo_estado += delta
	_reavaliar_estado()

	match _estado:
		Estado.PASSEANDO:
			_processar_passeio(delta)
		Estado.PARADO:
			_processar_parado(delta)
		Estado.FUGINDO:
			_processar_fuga(delta)
		Estado.ESCONDIDO:
			_processar_escondido(delta)

	_aplicar_gravidade(delta)
	move_and_slide()
	_atualizar_animacao()
	_checar_travamento(delta)

	if global_position.y < ALTURA_MINIMA:
		global_position = _posicao_inicial
		velocity = Vector3.ZERO

## Só roda enquanto o rato está capturado — ver `set_process` no `_ready`.
func _process(delta: float) -> void:
	_tempo_captura += delta
	match _fase_captura:
		Captura.BOTE:
			_processar_bote(delta)
		Captura.SUBINDO:
			_processar_subida(delta)
		Captura.NA_MAO:
			_processar_na_mao(delta)
		Captura.AMOLECENDO:
			_processar_amolecimento(delta)
		Captura.GUARDANDO:
			_processar_guardada(delta)

## Leva um golpe. Com `vida_maxima` 1 (o padrão) qualquer acerto mata. `tipo` é
## de que morte a arma mata, e é o que decide quanto o corpo vai pagar.
func levar_dano(quantidade: int = 1, origem: Vector3 = PONTO_INVALIDO,
		tipo := Morte.Tipo.INDEFINIDA) -> void:
	if _estado == Estado.MORTO or _estado == Estado.CAPTURADO:
		return
	_vida -= quantidade
	if _vida <= 0:
		_morrer(origem, 3.0, tipo)
		return
	_mudar_estado(Estado.FUGINDO)
	if origem != PONTO_INVALIDO:
		velocity += _para_longe_de(origem) * forca_empurrao

## Verdadeiro assim que a vida dele acaba, mesmo nos instantes em que o corpo
## ainda está na mão do jogador — amolecendo ou descendo para a cintura.
func esta_morto() -> bool:
	if _estado == Estado.CAPTURADO:
		return _fase_captura == Captura.AMOLECENDO or _fase_captura == Captura.GUARDANDO
	return _estado == Estado.MORTO

func esta_capturado() -> bool:
	return _estado == Estado.CAPTURADO

## Verdadeiro só depois que ele terminou de subir e já está firme na mão.
func esta_na_mao() -> bool:
	return _estado == Estado.CAPTURADO and _fase_captura == Captura.NA_MAO

## Onde está, no mundo, o meio do corpo dele: o ponto que a mão segura e que a
## captura leva até o meio da tela.
func centro_do_corpo() -> Vector3:
	return global_position + global_basis * CENTRO_DO_CORPO

# --- Captura ---------------------------------------------------------------
#
# O jogador agarra o rato, ele é arrancado do chão em arco até `ponto` — um nó
# no meio da tela, filho da cabeça do jogador — e a partir da chegada vira filho
# desse nó. Ser filho é o que garante que ele fique *colado* no meio da tela por
# mais rápido que o jogador gire a câmera: não há transformação sendo perseguida
# quadro a quadro, ele simplesmente vai junto.
#
# Esganado, ele nunca volta para o chão: amolece na mão e desce para a cintura,
# guardado. Carcaça no chão é coisa de rato morto de longe — o que morre na mão
# do jogador some com ele.

## O jogador agarrou este rato. Devolve falso quando não dá: morto, já na mão de
## alguém ou recém-escapado.
func ser_capturado(ponto: Node3D) -> bool:
	if _estado == Estado.MORTO or _estado == Estado.CAPTURADO or _tempo_imune > 0.0:
		return false

	_estado = Estado.CAPTURADO
	_fase_captura = Captura.BOTE
	_tempo_captura = 0.0
	_ponto_captura = ponto
	_pai_original = get_parent()
	_camada_original = collision_layer
	_agitacao = 1.0
	_solavanco = Vector3.ZERO
	_solavanco_giro = Vector3.ZERO
	_tempo_esperneio = randf_range(INTERVALO_ESPERNEIO.x, INTERVALO_ESPERNEIO.y)

	_limpar_alvo()
	velocity = Vector3.ZERO
	# Sai de todas as camadas para não empurrar o jogador nem atrapalhar as
	# linhas de visão dos outros ratos enquanto está pendurado no ar. A máscara
	# fica intacta: é ela que faz a carcaça achar o chão quando ele for largado.
	set_deferred("collision_layer", 0)
	# Continua no grupo `ratos`: para o placar do HUD ele ainda está vivo, e é
	# isso mesmo — o jogador ainda pode perdê-lo.
	set_process(true)
	return true

## Um aperto no pescoço. Quem conta os apertos e decide quando ele morre é a
## arma; aqui o rato só reage.
func apertar() -> void:
	if _estado != Estado.CAPTURADO:
		return
	_agitacao = 1.0
	modelo.scale = ESCALA_ESMAGADO
	_espernear(0.6)

## Morreu na mão: amolece por um instante e depois é guardado na cintura. `tipo`
## vem da arma que o matou — hoje só as mãos chegam aqui, esganando.
func morrer_nas_maos(tipo := Morte.Tipo.ESTRANGULAMENTO) -> void:
	if _estado != Estado.CAPTURADO or esta_morto():
		return
	# Quem martelou rápido demais pode matá-lo antes de ele terminar de subir.
	# Nesse caso ele chega na mão de uma vez e amolece de lá — sem isso o corpo
	# amoleceria em coordenadas da mão estando ainda pendurado no mundo.
	if _fase_captura != Captura.NA_MAO:
		_encaixar_na_mao()
	_fase_captura = Captura.AMOLECENDO
	_tempo_captura = 0.0
	_agitacao = 0.0
	animador.speed_scale = 1.0
	animador.play(ANIM_MORTE, MISTURA)
	# Para o placar ele já morreu aqui, no último aperto. O que vem depois —
	# amolecer e ser guardado — é só o gesto. O dinheiro, esse, só entra no fim
	# dele: quem mata e perde o corpo não recebe.
	_registrar_morte(tipo)

## Se soltou da mão do jogador e dispara em fuga.
func escapar() -> void:
	if _estado != Estado.CAPTURADO:
		return
	# Pula para a frente do jogador. A direção sai do corpo dele, e não da
	# posição do rato: pendurado na mão o rato está *em cima* do jogador, e o
	# "longe dele" de sempre não teria para onde apontar.
	var jogador := _obter_jogador()
	var fuga := -jogador.global_basis.z if jogador != null else -global_basis.z
	fuga.y = 0.0
	fuga = Vector3.FORWARD if fuga.is_zero_approx() else fuga.normalized()
	_devolver_ao_mundo()
	_tempo_imune = TEMPO_IMUNIDADE
	# `_mudar_estado` só vale saindo de outro estado, e a fuga precisa começar do
	# zero para o rato pegar a `velocidade_arranque`.
	_estado = Estado.PASSEANDO
	_mudar_estado(Estado.FUGINDO)
	velocity = fuga * velocidade_fuga + Vector3.UP * SALTO_ESCAPADA

## Tira o rato da mão e devolve ele à árvore e à física de onde saiu.
func _devolver_ao_mundo() -> void:
	set_process(false)
	if _pai_original != null and is_instance_valid(_pai_original) and get_parent() != _pai_original:
		reparent(_pai_original, true)
	# Endireita o corpo: ele volta ao chão de pé, não de cabeça para baixo.
	rotation = Vector3(0.0, rotation.y, 0.0)
	set_deferred("collision_layer", _camada_original)
	_ponto_captura = null

## O bote: ele se encolhe no chão e a mão desce em cima.
func _processar_bote(delta: float) -> void:
	modelo.scale = modelo.scale.lerp(ESCALA_BOTE, minf(delta * 22.0, 1.0))
	if _tempo_captura < TEMPO_BOTE:
		return
	_fase_captura = Captura.SUBINDO
	_tempo_captura = 0.0
	_origem_subida = global_position
	_base_origem = global_basis.orthonormalized()
	animador.speed_scale = CADENCIA_DEBATENDO
	animador.play(ANIM_CORRIDA, MISTURA)

## O arranque: do chão até a mão, em arco e cambalhotando.
func _processar_subida(_delta: float) -> void:
	var t := clampf(_tempo_captura / TEMPO_SUBIDA, 0.0, 1.0)
	# Sai rápido do chão e desacelera chegando na mão — é o que dá o puxão.
	var avanco := 1.0 - pow(1.0 - t, 3.0)

	var pose := _ponto_captura.global_basis.orthonormalized() * Basis.from_euler(_radianos(POSE_SEGURADA))

	# O destino é lido a cada quadro: se o jogador anda ou gira enquanto o rato
	# sobe, o rato corrige a rota no ar. A origem, não: ela fica onde o rato
	# estava, no mundo, senão ele subiria "de lugar nenhum" a cada virada de câmera.
	# Quem chega ao ponto é o meio do corpo dele, e não a origem lá nos pés — daí
	# a subida mirar já descontada da ancoragem que ele vai ter na mão.
	var destino := _ponto_captura.global_position + _ancoragem(pose)
	var meio := (_origem_subida + destino) * 0.5 + Vector3.UP * ALTURA_ARCO
	global_position = _bezier(_origem_subida, meio, destino, avanco)

	var giro := _base_origem.get_rotation_quaternion().slerp(pose.get_rotation_quaternion(), avanco)
	# A cambalhota se desmancha conforme ele chega: no fim sobra só a pose.
	var cambalhota := Quaternion(Vector3.RIGHT, GIRO_CAMBALHOTA * (1.0 - avanco))
	global_basis = Basis(giro * cambalhota)

	modelo.scale = ESCALA_ESTICADA.lerp(Vector3.ONE, avanco)

	if t >= 1.0:
		_encaixar_na_mao()

## Chegou: de agora em diante ele *é* filho do ponto no meio da tela.
func _encaixar_na_mao() -> void:
	reparent(_ponto_captura, true)
	var pose := Basis.from_euler(_radianos(POSE_SEGURADA))
	transform = Transform3D(pose, _ancoragem(pose))
	_fase_captura = Captura.NA_MAO
	_tempo_captura = 0.0

## Onde a origem do rato precisa ficar, na pose `base`, para o meio do corpo dele
## cair bem em cima do ponto de captura. É por isso que ele se debate *em volta*
## do meio da tela em vez de varrer o quadro inteiro a cada esperneio.
func _ancoragem(base: Basis) -> Vector3:
	return -(base * CENTRO_DO_CORPO)

## Preso na mão: tremendo o tempo todo, esperneando de vez em quando e mordendo
## quando dá. Tudo em coordenadas locais, sobre o ponto no meio da tela.
func _processar_na_mao(delta: float) -> void:
	_agitacao = lerpf(AGITACAO_BASE, _agitacao, pow(AMORTECIMENTO_AGITACAO, delta))
	_amortecer_solavanco(delta)

	_tempo_esperneio -= delta
	if _tempo_esperneio <= 0.0:
		_tempo_esperneio = randf_range(INTERVALO_ESPERNEIO.x, INTERVALO_ESPERNEIO.y)
		_espernear(1.0)
		if randf() < CHANCE_MORDIDA:
			animador.play(ANIM_ATAQUE, MISTURA)
			animador.queue(ANIM_CORRIDA)

	# Senoides de períodos que não batem entre si: somadas, não se repetem a
	# ponto de o olho pegar o padrão.
	var t := _tempo_captura
	var tremor := Vector3(
		sin(t * 27.0) * 0.6 + sin(t * 41.0) * 0.4,
		sin(t * 33.0 + 1.3) * 0.5 + sin(t * 19.0) * 0.5,
		sin(t * 23.0 + 2.1)
	) * TREMOR * _agitacao
	var giro := Vector3(
		sin(t * 21.0) * 0.5,
		sin(t * 17.0 + 0.7),
		sin(t * 29.0 + 2.2) * 0.7
	) * deg_to_rad(TREMOR_ANGULO) * _agitacao

	basis = Basis.from_euler(_radianos(POSE_SEGURADA) + giro + _solavanco_giro)
	position = _ancoragem(basis) + tremor + _solavanco
	modelo.scale = modelo.scale.lerp(Vector3.ONE, minf(delta * 9.0, 1.0))

## Morreu: o corpo amolece na mão antes de ser guardado.
func _processar_amolecimento(delta: float) -> void:
	_amortecer_solavanco(delta)
	var t := minf(_tempo_captura / TEMPO_AMOLECIMENTO, 1.0)
	var pendurado := Basis.from_euler(_radianos(POSE_AMOLECIDA))
	basis = Basis(basis.get_rotation_quaternion().slerp(pendurado.get_rotation_quaternion(), minf(delta * 9.0, 1.0)))
	# Escorrega da mão enquanto amolece — sempre em volta do meio do corpo, senão
	# o corpo mole sairia do quadro no meio do tombo.
	position = position.lerp(_ancoragem(basis) + Vector3(0.0, -0.12, 0.05), minf(delta * 6.0, 1.0))
	modelo.scale = modelo.scale.lerp(Vector3.ONE, minf(delta * 9.0, 1.0))
	if t < 1.0:
		return

	# Sem força nenhuma sobrando no bicho, o braço desce com ele.
	_fase_captura = Captura.GUARDANDO
	_tempo_captura = 0.0
	_origem_guardada = position - _ancoragem(basis)
	_base_guardada = basis

## A guardada: o jogador baixa o rato morto do meio da tela até a cintura, onde
## ele sai do quadro. É aqui que a caçada se encerra — o corpo não volta ao
## mundo, ele some junto com quem o matou.
func _processar_guardada(_delta: float) -> void:
	var t := clampf(_tempo_captura / TEMPO_GUARDADA, 0.0, 1.0)
	# Sai devagar da mão e desacelera na cintura: é um gesto de guardar, não um
	# corpo despencando.
	var avanco := t * t * (3.0 - 2.0 * t)

	# O pulso vira antes de o braço descer. Fora de ordem, o corpo ainda deitado
	# varre o caminho todo com o focinho e passa raspando na câmera, inchando na
	# tela justamente no quadro em que devia estar saindo dela.
	var guardada := Basis.from_euler(_radianos(POSE_GUARDADA))
	basis = Basis(_base_guardada.get_rotation_quaternion().slerp(
		guardada.get_rotation_quaternion(), smoothstep(0.0, 0.55, t)))

	# Quem percorre o caminho é o meio do corpo, como na mão: assim ele desce
	# inteiro em vez de girar em volta das patas.
	var meio := (_origem_guardada + CINTURA) * 0.5 + DESVIO_GUARDADA
	position = _bezier(_origem_guardada, meio, CINTURA, avanco) + _ancoragem(basis)

	# Some encolhendo no fim do caminho, como a carcaça some no chão: quem estiver
	# olhando para baixo vê o rato ser guardado, e não sumir de estalo.
	modelo.scale = Vector3.ONE.lerp(Vector3(0.02, 0.02, 0.02), smoothstep(SUMICO_GUARDADA, 1.0, t))

	if t >= 1.0:
		# Chegou na cintura: é aqui que a caçada deste rato se encerra e que ele
		# vira dinheiro.
		_pagar_recompensa()
		queue_free()

func _espernear(forca: float) -> void:
	_solavanco = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-0.5, 0.5)) \
		.normalized() * FORCA_ESPERNEIO * forca
	_solavanco_giro = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) \
		.normalized() * deg_to_rad(FORCA_ESPERNEIO_ANGULO) * forca

func _amortecer_solavanco(delta: float) -> void:
	var sobra := pow(AMORTECIMENTO_SOLAVANCO, delta)
	_solavanco *= sobra
	_solavanco_giro *= sobra

func _bezier(de: Vector3, meio: Vector3, ate: Vector3, t: float) -> Vector3:
	return de.lerp(meio, t).lerp(meio.lerp(ate, t), t)

func _radianos(graus: Vector3) -> Vector3:
	return Vector3(deg_to_rad(graus.x), deg_to_rad(graus.y), deg_to_rad(graus.z))

# --- Estados ---------------------------------------------------------------

func _reavaliar_estado() -> void:
	var distancia := _distancia_do_jogador()
	# Escondido ele aguenta o jogador bem mais perto antes de disparar de novo.
	var limite_ouvido := raio_panico_escondido if _estado == Estado.ESCONDIDO else raio_panico
	var assustado := distancia <= limite_ouvido or (distancia <= _raio_alerta_atual() and _ve_jogador())

	match _estado:
		Estado.PASSEANDO, Estado.PARADO:
			if assustado:
				_mudar_estado(Estado.FUGINDO)
		Estado.FUGINDO:
			if not assustado and distancia >= raio_seguro:
				_mudar_estado(Estado.PASSEANDO)
		Estado.ESCONDIDO:
			if assustado:
				_mudar_estado(Estado.FUGINDO)
			elif distancia >= raio_seguro and _tempo_estado > 2.0:
				_mudar_estado(Estado.PASSEANDO)

func _mudar_estado(novo: Estado) -> void:
	if _estado == novo:
		return
	_estado = novo
	_tempo_estado = 0.0
	match novo:
		Estado.PASSEANDO:
			_sortear_passeio()
		Estado.PARADO:
			_limpar_alvo()
			_duracao_parado = randf_range(0.8, 2.4)
		Estado.FUGINDO:
			_limpar_alvo()
			_tempo_busca = 0.0
		Estado.ESCONDIDO:
			_limpar_alvo()
			velocity.x = 0.0
			velocity.z = 0.0

func _processar_passeio(delta: float) -> void:
	_tempo_alvo += delta
	if not _tem_alvo or _tempo_alvo > 6.0 or navegador.is_navigation_finished():
		# De vez em quando ele para para farejar em vez de escolher outro destino.
		if randf() < 0.35:
			_mudar_estado(Estado.PARADO)
			return
		_sortear_passeio()
	_mover(_direcao_do_caminho(), velocidade_passeio, delta)

func _processar_parado(delta: float) -> void:
	_mover(Vector3.ZERO, 0.0, delta)
	if _tempo_estado >= _duracao_parado:
		_mudar_estado(Estado.PASSEANDO)

func _processar_fuga(delta: float) -> void:
	_tempo_busca -= delta
	if _tempo_busca <= 0.0:
		_tempo_busca = INTERVALO_BUSCA
		_buscar_esconderijo()

	if _tem_alvo and navegador.is_navigation_finished():
		# Chegou ao esconderijo: se o jogador não o alcança com os olhos, fica quieto.
		if not _ve_jogador() and _distancia_do_jogador() > raio_panico:
			_mudar_estado(Estado.ESCONDIDO)
			return
		_limpar_alvo()
		_tempo_busca = 0.0

	var direcao := _direcao_do_caminho()
	if direcao.is_zero_approx():
		# Nenhum esconderijo alcançável (ou ele caiu fora da malha): corre para
		# longe no faro, farejando parede à frente.
		direcao = _desviar(_para_longe_de(_posicao_do_jogador()))
	var velocidade := velocidade_arranque if _tempo_estado < TEMPO_ARRANQUE else velocidade_fuga
	_mover(direcao, velocidade, delta)

func _processar_escondido(delta: float) -> void:
	_mover(Vector3.ZERO, 0.0, delta)
	modelo.scale = modelo.scale.lerp(ESCALA_AGACHADO, minf(delta * 8.0, 1.0))

# --- Esconderijo -----------------------------------------------------------

func _preparar_consulta_cobertura() -> void:
	var esfera := SphereShape3D.new()
	esfera.radius = RAIO_COBERTURA
	_consulta_cobertura.shape = esfera
	_consulta_cobertura.collision_mask = CAMADA_CENARIO
	_consulta_cobertura.exclude = [get_rid()]

## Escolhe para onde correr: junta os pontos cegos atrás dos obstáculos por perto
## com um leque de pontos para trás e fica com o de melhor nota.
func _buscar_esconderijo() -> void:
	var jogador := _obter_jogador()
	if jogador == null or not _mapa_pronto():
		_limpar_alvo()
		return

	var posicao_jogador := jogador.global_position
	var olhos_jogador := posicao_jogador + Vector3.UP * ALTURA_JOGADOR
	# Achou um esconderijo bom? Não fica trocando de ideia no meio do caminho.
	if _esconderijo_ainda_serve(olhos_jogador):
		return
	_limpar_alvo()

	var melhor := PONTO_INVALIDO
	var melhor_nota := -INF

	for ponto in _candidatos(olhos_jogador, posicao_jogador):
		# A nota do ponto vem primeiro porque é barata; o caminho só desconta,
		# então quem já perde para o líder nem precisa ser consultado.
		var nota := _nota_do_ponto(ponto, olhos_jogador, posicao_jogador)
		if nota <= melhor_nota:
			continue
		var caminho := _caminho_ate(ponto)
		if caminho.is_empty():
			continue
		nota -= _custo_do_caminho(caminho, posicao_jogador)
		if nota > melhor_nota:
			melhor_nota = nota
			melhor = ponto

	if melhor != PONTO_INVALIDO:
		_definir_alvo(melhor)

## Os destinos que ele considera nesta busca, todos já encostados na malha.
func _candidatos(olhos_jogador: Vector3, posicao_jogador: Vector3) -> Array[Vector3]:
	var pontos: Array[Vector3] = []

	_consulta_cobertura.transform = Transform3D(Basis(), global_position)
	for achado in get_world_3d().direct_space_state.intersect_shape(_consulta_cobertura, MAX_COBERTURAS):
		var corpo := achado.get("collider") as Node3D
		if corpo == null:
			continue
		# Cobertura é coisa que fica de pé na frente do jogador: o chão e as
		# rampas entram na consulta, mas não escondem ninguém.
		if corpo.global_position.y < global_position.y + 0.5:
			continue
		if _distancia_plana(corpo.global_position, global_position) > RAIO_COBERTURA:
			continue
		var ponto := _ponto_cego_atras_de(corpo.global_position, olhos_jogador)
		if ponto != PONTO_INVALIDO:
			pontos.append(ponto)

	var fuga := _para_longe_de(posicao_jogador)
	for i in CANDIDATOS:
		var direcao := fuga.rotated(Vector3.UP, randf_range(-ABERTURA_LEQUE, ABERTURA_LEQUE))
		var bruto := global_position + direcao * randf_range(DISTANCIA_MIN_BUSCA, DISTANCIA_MAX_BUSCA)
		var ponto := _ponto_navegavel(bruto)
		if ponto != PONTO_INVALIDO:
			pontos.append(ponto)

	return pontos

## Anda para trás do obstáculo, afastando-se do jogador, até sair da vista dele.
func _ponto_cego_atras_de(centro: Vector3, olhos_jogador: Vector3) -> Vector3:
	var direcao := centro - olhos_jogador
	direcao.y = 0.0
	if direcao.is_zero_approx():
		return PONTO_INVALIDO
	direcao = direcao.normalized()
	# Parte da altura do rato, não do centro do obstáculo, que pode ser bem alto.
	var base := Vector3(centro.x, global_position.y, centro.z)

	for i in PASSOS_COBERTURA:
		var ponto := _ponto_navegavel(base + direcao * (PASSO_COBERTURA * (i + 1)))
		if ponto == PONTO_INVALIDO:
			continue
		if _distancia_plana(ponto, global_position) > DISTANCIA_MAX_BUSCA:
			continue
		if _bloqueado(olhos_jogador, ponto + Vector3.UP * ALTURA_OLHOS):
			return ponto
	return PONTO_INVALIDO

## Nota do candidato antes de olhar o caminho: longe do jogador é bom, sumir da
## vista dele é melhor ainda, e um buraco sem saída perde pontos.
func _nota_do_ponto(ponto: Vector3, olhos_jogador: Vector3, posicao_jogador: Vector3) -> float:
	var distancia := _distancia_plana(ponto, posicao_jogador)
	if distancia < raio_panico:
		return -INF
	var nota := distancia
	if _bloqueado(olhos_jogador, ponto + Vector3.UP * ALTURA_OLHOS):
		nota += BONUS_ESCONDIDO
	return nota + _saidas_do_ponto(ponto) * BONUS_SAIDA

## Quantas das quatro direções em volta do ponto estão livres. Uma quina fechada
## devolve zero ou um: esconde bem enquanto o jogador não chega, e vira armadilha
## quando ele chega.
func _saidas_do_ponto(ponto: Vector3) -> int:
	var origem := ponto + Vector3.UP * ALTURA_OLHOS
	var livres := 0
	for i in 4:
		var direcao := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 4.0)
		if not _bloqueado(origem, origem + direcao * ALCANCE_SAIDA):
			livres += 1
	return livres

## Quanto o caminho desconta da nota: o comprimento dele e uma multa alta se ele
## passar raspando no jogador — não adianta o esconderijo ser ótimo se o rato
## precisa cruzar com quem está caçando ele.
func _custo_do_caminho(caminho: PackedVector3Array, posicao_jogador: Vector3) -> float:
	var jogador_plano := Vector3(posicao_jogador.x, 0.0, posicao_jogador.z)
	var comprimento := 0.0
	var mais_perto := INF

	for i in range(1, caminho.size()):
		var de := Vector3(caminho[i - 1].x, 0.0, caminho[i - 1].z)
		var para := Vector3(caminho[i].x, 0.0, caminho[i].z)
		comprimento += de.distance_to(para)
		var raspa := Geometry3D.get_closest_point_to_segment(jogador_plano, de, para)
		mais_perto = minf(mais_perto, raspa.distance_to(jogador_plano))

	var custo := comprimento * PESO_CAMINHO
	if mais_perto < raio_panico:
		custo += MULTA_PASSAR_PERTO
	return custo

## O esconderijo atual continua valendo enquanto o jogador não o alcançar com os
## olhos nem chegar perto demais dele.
func _esconderijo_ainda_serve(olhos_jogador: Vector3) -> bool:
	if not _tem_alvo:
		return false
	if _distancia_plana(_alvo, _posicao_do_jogador()) < raio_panico:
		return false
	return _bloqueado(olhos_jogador, _alvo + Vector3.UP * ALTURA_OLHOS)

func _sortear_passeio() -> void:
	var direcao := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	if direcao.is_zero_approx():
		direcao = Vector3.FORWARD
	var ponto := _ponto_navegavel(global_position + direcao.normalized() * randf_range(4.0, 12.0))
	if ponto == PONTO_INVALIDO:
		_limpar_alvo()
		return
	_definir_alvo(ponto)

# --- Navegação -------------------------------------------------------------

## A malha é assada quando o mapa abre e só passa a responder consultas depois
## da primeira sincronização do servidor de navegação. Até lá o rato não tem para
## onde ir, e perguntar antes disso é erro.
func _mapa_pronto() -> bool:
	var mapa := navegador.get_navigation_map()
	return mapa.is_valid() and NavigationServer3D.map_get_iteration_id(mapa) > 0

func _definir_alvo(ponto: Vector3) -> void:
	_alvo = ponto
	_tem_alvo = true
	_tempo_alvo = 0.0
	navegador.target_position = ponto

func _limpar_alvo() -> void:
	_tem_alvo = false
	# Alvo em cima do próprio corpo: o agente se dá por chegado e para de pedir
	# caminho até a próxima decisão.
	navegador.target_position = global_position

## Para onde andar agora: o próximo passo do caminho até o alvo. Enquanto durar
## um desvio de emergência, ele manda mais que o caminho.
func _direcao_do_caminho() -> Vector3:
	if _tempo_desvio > 0.0:
		return _direcao_desvio
	if not _tem_alvo or navegador.is_navigation_finished():
		return Vector3.ZERO
	var passo := navegador.get_next_path_position() - global_position
	passo.y = 0.0
	return Vector3.ZERO if passo.is_zero_approx() else passo.normalized()

## Encosta um ponto solto na malha de navegação. Devolve `PONTO_INVALIDO` quando
## ele cai longe dela — dentro de uma caixa, atravessado numa parede, fora do
## mapa — ou num nível que o rato não alcança.
func _ponto_navegavel(ponto: Vector3) -> Vector3:
	if not _mapa_pronto():
		return PONTO_INVALIDO
	var encostado := NavigationServer3D.map_get_closest_point(navegador.get_navigation_map(), ponto)
	if _distancia_plana(encostado, ponto) > TOLERANCIA_MALHA:
		return PONTO_INVALIDO
	if absf(encostado.y - ponto.y) > DESNIVEL_MAXIMO:
		return PONTO_INVALIDO
	return encostado

## Caminho até o ponto pela malha. Vem vazio quando o destino está numa ilha
## separada — em cima de uma plataforma, do outro lado de um muro — e o caminho
## morre antes de chegar lá.
func _caminho_ate(ponto: Vector3) -> PackedVector3Array:
	var mapa := navegador.get_navigation_map()
	var caminho := NavigationServer3D.map_get_path(mapa, global_position, ponto, true)
	if caminho.size() < 2 or _distancia_plana(caminho[-1], ponto) > TOLERANCIA_MALHA:
		return PackedVector3Array()
	return caminho

# --- Percepção -------------------------------------------------------------

func _obter_jogador() -> Node3D:
	if not is_instance_valid(_jogador):
		_jogador = get_tree().get_first_node_in_group("jogador") as Node3D
	return _jogador

func _posicao_do_jogador() -> Vector3:
	var jogador := _obter_jogador()
	return jogador.global_position if jogador != null else PONTO_INVALIDO

func _distancia_do_jogador() -> float:
	var jogador := _obter_jogador()
	if jogador == null:
		return INF
	return _distancia_plana(global_position, jogador.global_position)

## O rato repara mais em quem passa correndo do que em quem anda devagar.
func _raio_alerta_atual() -> float:
	var jogador := _obter_jogador()
	if jogador is CharacterBody3D and (jogador as CharacterBody3D).velocity.length() > 7.0:
		return raio_alerta * 1.4
	return raio_alerta

func _ve_jogador() -> bool:
	var jogador := _obter_jogador()
	if jogador == null:
		return false
	return not _bloqueado(
		global_position + Vector3.UP * ALTURA_OLHOS,
		jogador.global_position + Vector3.UP * ALTURA_JOGADOR
	)

## Verdadeiro se houver cenário entre os dois pontos.
func _bloqueado(de: Vector3, para: Vector3) -> bool:
	var params := PhysicsRayQueryParameters3D.create(de, para, CAMADA_CENARIO, [get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(params).is_empty()

# --- Movimento -------------------------------------------------------------

## Desvia a direção pedida quando há parede à frente, testando aberturas cada
## vez mais abertas para os dois lados. É o plano B de quem está sem caminho
## pela malha; quem tem caminho já vem contornando o cenário.
func _desviar(direcao: Vector3) -> Vector3:
	if direcao.is_zero_approx():
		return direcao
	var origem := global_position + Vector3.UP * ALTURA_OLHOS
	if not _bigode_bateu(origem, direcao):
		return direcao
	for graus: float in ANGULOS_DESVIO:
		var tentativa := direcao.rotated(Vector3.UP, deg_to_rad(graus))
		if not _bigode_bateu(origem, tentativa):
			return tentativa
	return -direcao

func _bigode_bateu(origem: Vector3, direcao: Vector3) -> bool:
	return _bloqueado(origem, origem + direcao.normalized() * ALCANCE_BIGODE)

func _mover(direcao: Vector3, velocidade: float, delta: float) -> void:
	direcao.y = 0.0
	var parado := direcao.is_zero_approx()
	_velocidade_desejada = 0.0 if parado else velocidade
	var alvo := Vector3.ZERO if parado else direcao.normalized() * velocidade
	velocity.x = move_toward(velocity.x, alvo.x, aceleracao * delta)
	velocity.z = move_toward(velocity.z, alvo.z, aceleracao * delta)
	_virar_para(Vector3(velocity.x, 0.0, velocity.z), delta)
	modelo.scale = modelo.scale.lerp(Vector3.ONE, minf(delta * 8.0, 1.0))

func _virar_para(direcao: Vector3, delta: float) -> void:
	if direcao.length() < 0.2:
		return
	var angulo := atan2(-direcao.x, -direcao.z)
	rotation.y = lerp_angle(rotation.y, angulo, 1.0 - exp(-velocidade_giro * delta))

func _aplicar_gravidade(delta: float) -> void:
	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity.y -= gravidade * delta

## O rato ainda pode ficar encaixado numa quina: empurrado pelo jogador, jogado
## para fora da malha ou espremido contra outro rato. Se ele passar tempo demais
## querendo andar sem sair do lugar, dá um passo de lado e procura outro caminho.
func _checar_travamento(delta: float) -> void:
	if _tempo_desvio > 0.0:
		_tempo_desvio -= delta

	# A conta usa a velocidade que ele *pediu*, não a `velocity`: quem esbarra de
	# frente numa parede tem a velocidade zerada pelo `move_and_slide` e passaria
	# por quem parou de propósito.
	var esperado := _velocidade_desejada * delta * 0.3
	var andou := _distancia_plana(global_position, _posicao_anterior)
	if _velocidade_desejada > VELOCIDADE_PARADO and andou < esperado:
		_tempo_travado += delta
	else:
		_tempo_travado = 0.0
	_posicao_anterior = global_position

	if _tempo_travado > TEMPO_TRAVADO:
		_tempo_travado = 0.0
		_sacudir_para_o_lado()
		_limpar_alvo()
		_tempo_busca = 0.0
		if _estado == Estado.PASSEANDO:
			_sortear_passeio()

## Escolhe um lado livre e corre para ele por um instante, o bastante para se
## soltar da quina antes de voltar a seguir o caminho.
func _sacudir_para_o_lado() -> void:
	var frente := _direcao_ate(_alvo) if _tem_alvo else -global_basis.z
	var origem := global_position + Vector3.UP * ALTURA_OLHOS
	# Sorteia por qual lado começa, senão dez ratos presos na mesma quina saem
	# todos para a direita.
	var lados := [1.0, -1.0] if randf() < 0.5 else [-1.0, 1.0]
	_tempo_desvio = TEMPO_DESVIO
	for lado: float in lados:
		_direcao_desvio = frente.rotated(Vector3.UP, lado * PI * 0.5)
		if not _bigode_bateu(origem, _direcao_desvio):
			return
	_direcao_desvio = -frente

# --- Aparência e animação --------------------------------------------------

## Dá a este rato uma das pelagens da espécie dele, sem mexer no material que os
## outros compartilham. Espécie sem pelagem nenhuma fica com o material do modelo.
func _sortear_pelagem() -> void:
	var pelagem := especie.sortear_pelagem()
	if pelagem == null:
		return
	var material := malha.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	material.albedo_texture = pelagem
	malha.set_surface_override_material(0, material)

## A animação segue a velocidade, não o estado: passeando ele trota, fugindo
## dispara, e parado ou escondido volta para o repouso.
func _atualizar_animacao() -> void:
	var velocidade_plana := Vector2(velocity.x, velocity.z).length()
	if velocidade_plana < VELOCIDADE_PARADO:
		_tocar_repouso()
		return
	if animador.current_animation != ANIM_CORRIDA:
		animador.play(ANIM_CORRIDA, MISTURA)
	animador.speed_scale = clampf(velocidade_plana / VELOCIDADE_CICLO, CADENCIA_MINIMA, CADENCIA_MAXIMA)

## Repouso e farejada contam como a mesma coisa: enquanto uma das duas estiver
## rodando não se troca de animação. Assim a farejada termina em paz e emenda
## de volta no repouso.
func _tocar_repouso() -> void:
	if animador.current_animation == ANIM_REPOUSO or animador.current_animation == ANIM_FAREJANDO:
		return
	animador.speed_scale = 1.0
	if randf() < CHANCE_FAREJADA:
		animador.play(ANIM_FAREJANDO, MISTURA)
		animador.queue(ANIM_REPOUSO)
	else:
		animador.play(ANIM_REPOUSO, MISTURA)

# --- Morte -----------------------------------------------------------------

## A morte nos livros do jogo, valha ela no chão ou na mão do jogador: ele sai da
## conta dos vivos, para de poder levar golpe, guarda de que morreu e avisa quem
## estiver escutando. Não paga nada — pagar é do `_pagar_recompensa`.
func _registrar_morte(tipo: Morte.Tipo) -> void:
	_tipo_morte = tipo
	remove_from_group("ratos")
	# Sai da camada dos ratos para não levar golpe de novo. A máscara fica: a
	# carcaça ainda precisa achar o chão.
	set_deferred("collision_layer", 0)
	morreu.emit(self, tipo)

## Fecha a conta deste rato, uma vez só. Vale quando a caçada dele terminou, e
## cada morte termina num lugar: esganado, é na cintura do jogador; morto de
## longe, é onde o corpo caiu. Escapar da mão não fecha conta nenhuma.
func _pagar_recompensa() -> void:
	if _pago:
		return
	_pago = true
	Carteira.receber(especie, _tipo_morte, _tamanho)

## Cai morto onde estava, de pé no mundo. `salto` é o pulinho que o corpo dá ao
## levar o golpe. Quem morre esganado não passa por aqui: some na cintura do
## jogador, sem carcaça.
func _morrer(origem: Vector3, salto := 3.0, tipo := Morte.Tipo.INDEFINIDA) -> void:
	_estado = Estado.MORTO
	_registrar_morte(tipo)
	# Morto de longe, o corpo cai e o serviço acabou ali mesmo: paga na hora.
	_pagar_recompensa()

	velocity = Vector3.UP * salto
	if origem != PONTO_INVALIDO:
		velocity += _para_longe_de(origem) * forca_empurrao

	animador.speed_scale = 1.0
	# A animação de morte não repete: ela tomba o rato e segura o último quadro.
	animador.play(ANIM_MORTE, MISTURA)

	var tween := create_tween()
	# Desfaz o agachamento do esconderijo, se ele morreu escondido.
	tween.tween_property(modelo, "scale", Vector3.ONE, 0.2)
	tween.tween_interval(TEMPO_CARCACA)
	tween.tween_property(modelo, "scale", Vector3(0.02, 0.02, 0.02), 0.3).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

# --- Utilidades ------------------------------------------------------------

func _direcao_ate(ponto: Vector3) -> Vector3:
	var direcao := ponto - global_position
	direcao.y = 0.0
	return direcao.normalized()

func _para_longe_de(ponto: Vector3) -> Vector3:
	if ponto == PONTO_INVALIDO:
		return -global_basis.z
	var direcao := global_position - ponto
	direcao.y = 0.0
	if direcao.is_zero_approx():
		return -global_basis.z
	return direcao.normalized()

func _distancia_plana(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
