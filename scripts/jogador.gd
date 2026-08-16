extends CharacterBody3D
## Personagem em primeira pessoa.
## WASD/setas movem em relação a para onde se está olhando, Shift corre,
## Espaço pula, o mouse olha em volta e o botão esquerdo usa a arma da vez.
##
## O jogador não sabe matar rato: quem sabe é a arma pendurada na cabeça dele
## (`scripts/armas/`). Hoje ela é o par de mãos, que agarra o rato em vez de
## matá-lo — e aí o mesmo clique que agarrou passa a esganar, enquanto o jogador
## anda devagar, e sem pular, com o bicho se debatendo na mão.

signal atacou(acertou: bool)
## Repasses da arma para o HUD.
signal captura_iniciada(rato: Node3D)
signal captura_progresso(fracao: float)
signal captura_terminada(matou: bool)

@export_group("Movimento")
@export var velocidade_caminhada := 6.0
@export var velocidade_corrida := 10.5
## Velocidade com um rato se debatendo nas mãos: dá para andar, não para caçar.
@export var velocidade_segurando := 3.5
@export var aceleracao := 52.0
@export var desaceleracao := 68.0
@export var altura_pulo := 1.5
@export var gravidade := 22.0
@export var sensibilidade_mouse := 0.0035

## Limite de inclinação vertical da câmera (graus), para não virar de cabeça para baixo.
const ANGULO_MAX := 89.0
## Tempo em que ainda dá para pular depois de sair do chão.
const TEMPO_COIOTE := 0.12
## Altura em que o personagem é devolvido ao ponto de origem.
const ALTURA_MINIMA := -20.0

@onready var cabeca: Node3D = $Cabeca
@onready var camera: Camera3D = $Cabeca/Camera
@onready var arma: Arma = $Cabeca/Maos

var _posicao_inicial: Vector3
var _tempo_no_ar := 0.0

func _ready() -> void:
	_posicao_inicial = global_position
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	arma.usou.connect(func(acertou: bool) -> void: atacou.emit(acertou))
	arma.capturou.connect(func(rato: Node3D) -> void: captura_iniciada.emit(rato))
	arma.pressao_mudou.connect(func(fracao: float) -> void: captura_progresso.emit(fracao))
	arma.terminou.connect(func(matou: bool) -> void: captura_terminada.emit(matou))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# O corpo inteiro gira na horizontal; só a cabeça olha para cima/baixo.
		rotation.y -= event.relative.x * sensibilidade_mouse
		cabeca.rotation.x = clampf(
			cabeca.rotation.x - event.relative.y * sensibilidade_mouse,
			deg_to_rad(-ANGULO_MAX),
			deg_to_rad(ANGULO_MAX)
		)
	elif event.is_action_pressed("alternar_mouse"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# O mesmo clique agarra e esgana, então de mãos ocupadas ele vem primeiro: não
	# há o que agarrar com um rato já preso na mão.
	elif event.is_action_pressed("esganar") and arma.ocupada():
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			arma.apertar_secundario()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("atacar"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			arma.tentar_usar()
		else:
			# Clicar na janela devolve o controle da câmera ao mouse.
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	var ocupado := arma.ocupada()

	if is_on_floor():
		_tempo_no_ar = 0.0
	else:
		_tempo_no_ar += delta
		velocity.y -= gravidade * delta

	# De mãos ocupadas não se pula: já é trabalho segurar o rato.
	if not ocupado and Input.is_action_just_pressed("pular") and _tempo_no_ar <= TEMPO_COIOTE:
		velocity.y = sqrt(2.0 * gravidade * altura_pulo)
		_tempo_no_ar = TEMPO_COIOTE + 1.0

	var direcao := _direcao_desejada()
	var alvo := direcao * _velocidade_alvo(ocupado)
	var taxa := aceleracao if direcao != Vector3.ZERO else desaceleracao
	velocity.x = move_toward(velocity.x, alvo.x, taxa * delta)
	velocity.z = move_toward(velocity.z, alvo.z, taxa * delta)

	move_and_slide()

	if global_position.y < ALTURA_MINIMA:
		reaparecer()

func _velocidade_alvo(ocupado: bool) -> float:
	if ocupado:
		return velocidade_segurando
	return velocidade_corrida if Input.is_action_pressed("correr") else velocidade_caminhada

## Direção do movimento no plano XZ, relativa a para onde o personagem está virado.
func _direcao_desejada() -> Vector3:
	var entrada := Input.get_vector("mover_esquerda", "mover_direita", "mover_frente", "mover_tras")
	if entrada == Vector2.ZERO:
		return Vector3.ZERO
	var base := global_basis
	var direcao := base.z * entrada.y + base.x * entrada.x
	direcao.y = 0.0
	return direcao.normalized()

func reaparecer() -> void:
	velocity = Vector3.ZERO
	rotation.y = 0.0
	cabeca.rotation.x = 0.0
	global_position = _posicao_inicial
