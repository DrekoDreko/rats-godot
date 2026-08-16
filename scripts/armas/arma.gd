class_name Arma
extends Node3D
## Base das armas do jogador.
##
## Toda arma mora debaixo da cabeça do jogador, procura o rato na mira do mesmo
## jeito — o mais próximo dentro de um cone em volta do centro da tela, sem
## parede no caminho — e decide sozinha o que fazer com ele. O que muda de uma
## arma para outra é o `_usar()`.
##
## Uma arma pode ficar *ocupada*: enquanto estiver, o jogador não usa outra nem
## se move à vontade. As mãos ficam ocupadas segurando o rato; um martelo, por
## exemplo, nunca ficaria.

## Um uso da arma. `acertou` é falso quando não havia rato na mira.
signal usou(acertou: bool)

# Os três sinais da arma que *prende* um rato em vez de resolver num golpe. Uma
# arma que nunca ocupa o jogador simplesmente não os emite, e o HUD nunca abre.
## Pegou o rato e a partir de agora está ocupada com ele.
signal capturou(rato: Node3D)
## O quanto o serviço já andou, de 0 a 1.
signal pressao_mudou(fracao: float)
## Largou o rato: `matou` diz se foi morto ou se escapou.
signal terminou(matou: bool)

@export_group("Alcance")
@export var alcance := 2.6
## Abertura (graus) do cone em volta da mira.
@export var angulo := 50.0
@export var tempo_entre_usos := 0.4

@export_group("Coice")
## Deslocamento máximo (unidades de câmera) do chacoalhão da visão.
@export var coice_maximo := 0.035
## Quanto do coice sobra depois de um segundo.
@export var coice_amortecimento := 0.0008

## Altura do alvo no rato, na altura do corpo dele.
const ALTURA_ALVO_RATO := 0.2
## Só o cenário bloqueia a mira (camada 1).
const CAMADA_CENARIO := 1

var _tempo_recarga := 0.0
var _coice := Vector2.ZERO
var _rotacao_inicial: Vector3
var _tween_gesto: Tween

@onready var camera: Camera3D = get_parent().get_node("Camera")
## O corpo do jogador: é dele que saem os testes de parede, e é ele que precisa
## ficar de fora deles.
@onready var jogador: CharacterBody3D = get_parent().get_parent() as CharacterBody3D

func _ready() -> void:
	_rotacao_inicial = rotation

func _process(delta: float) -> void:
	_tempo_recarga = maxf(0.0, _tempo_recarga - delta)
	_amortecer_coice(delta)

## Tenta usar a arma. Fora da recarga não acontece nada.
func tentar_usar() -> void:
	if _tempo_recarga > 0.0:
		return
	_tempo_recarga = tempo_entre_usos
	_usar()

## Põe a arma em recarga sem usá-la. Serve para o clique que terminou um serviço
## não emendar no seguinte, agora que agarrar e esganar são o mesmo botão.
func recarregar() -> void:
	_tempo_recarga = tempo_entre_usos

## Verdadeiro enquanto a arma estiver no meio de alguma coisa que prenda o
## jogador. As armas que resolvem tudo num golpe deixam como está.
func ocupada() -> bool:
	return false

## Repasse da ação secundária (o clique, de mãos ocupadas) enquanto a arma está
## ocupada.
func apertar_secundario() -> void:
	pass

## O que a arma faz. Toda arma sobrescreve.
func _usar() -> void:
	pass

# --- Mira ------------------------------------------------------------------

## Rato mais próximo dentro do alcance, dentro do cone e sem parede no caminho.
func _rato_na_mira() -> Node3D:
	var origem := camera.global_position
	var frente := -camera.global_basis.z
	var limite := cos(deg_to_rad(angulo))
	var melhor: Node3D = null
	var menor_distancia := INF

	for no in get_tree().get_nodes_in_group("ratos"):
		var rato := no as Node3D
		if rato == null or not rato.has_method("levar_dano"):
			continue
		# Rato que já está na mão de alguém não conta como alvo.
		if rato.has_method("esta_capturado") and rato.esta_capturado():
			continue
		var ponto := rato.global_position + Vector3.UP * ALTURA_ALVO_RATO
		var ate_rato := ponto - origem
		var distancia := ate_rato.length()
		if distancia > alcance or distancia >= menor_distancia:
			continue
		if distancia > 0.05 and frente.dot(ate_rato / distancia) < limite:
			continue
		if _parede_entre(origem, ponto):
			continue
		melhor = rato
		menor_distancia = distancia

	return melhor

func _parede_entre(de: Vector3, para: Vector3) -> bool:
	var params := PhysicsRayQueryParameters3D.create(de, para, CAMADA_CENARIO, [jogador.get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(params).is_empty()

# --- Retorno na tela -------------------------------------------------------

## A estocada da arma. Enquanto não houver modelo nenhum embaixo deste nó ela
## roda invisível; o dia em que as mãos chegarem, já vêm com o gesto pronto.
func _animar_gesto() -> void:
	if _tween_gesto != null and _tween_gesto.is_running():
		_tween_gesto.kill()
	rotation = _rotacao_inicial
	_tween_gesto = create_tween()
	_tween_gesto.tween_property(self, "rotation", _rotacao_inicial + Vector3(deg_to_rad(-80.0), 0.0, 0.0), 0.09) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween_gesto.tween_property(self, "rotation", _rotacao_inicial, 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

## Chacoalha a visão. Mexe no deslocamento da câmera, e não na rotação da
## cabeça, que é do mouse — as duas coisas brigariam pelo mesmo valor.
func _coicear(forca: float) -> void:
	_coice += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized() * coice_maximo * forca
	_coice = _coice.limit_length(coice_maximo)

func _amortecer_coice(delta: float) -> void:
	if _coice.is_zero_approx():
		# Sobrou um resto imperceptível: zera de uma vez e devolve a câmera ao
		# lugar, em vez de deixar a visão torta para sempre por um milésimo.
		if _coice != Vector2.ZERO:
			_coice = Vector2.ZERO
			camera.h_offset = 0.0
			camera.v_offset = 0.0
		return
	_coice = _coice.lerp(Vector2.ZERO, 1.0 - pow(coice_amortecimento, delta))
	camera.h_offset = _coice.x
	camera.v_offset = _coice.y
