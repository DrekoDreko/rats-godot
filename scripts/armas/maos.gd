class_name Maos
extends Arma
## As mãos: a primeira arma do jogo, e a única que não mata de uma vez.
##
## O clique agarra o rato na mira. Ele é arrancado do chão, sobe até a mão e
## fica no meio da tela se debatendo. Daí em diante o mesmo clique é que mata:
## cada um aperta um pouco mais o pescoço dele, e a pressão escorre sozinha
## enquanto o jogador não clica de novo. Parar de martelar é perder o rato.
##
## O que este nó controla é a *regra* do esganamento — quanto vale cada aperto,
## quando o rato morre, quando ele se solta. Como o rato sobe, se debate e morre
## é assunto do `rato.gd`. Os sinais da captura são os da `Arma`.

@export_group("Esganamento")
## Apertos para matar um rato, se o jogador martelar sem parar. Martelando
## devagar são precisos mais, porque a pressão escorre entre um clique e outro.
@export var apertos_para_matar := 12
## Quanto da pressão escorre por segundo com o jogador parado.
@export var decaimento := 0.32
## Tempo com a pressão zerada antes de o rato se soltar da mão.
@export var tempo_ate_escapar := 1.6

@export_group("Mão")
## Distância do rato até a câmera. É o que decide o tamanho dele na tela: o bicho
## tem quase um metro do focinho ao quadril, e de pé a esta distância ele ocupa
## pouco mais da metade da altura do quadro, com o rabo pendurado até embaixo.
@export var distancia_maos := 0.95
## Altura do meio do corpo dele em relação ao centro da tela. Fica abaixo do
## centro de propósito: preso pelo pescoço ele estica a cabeça para cima, e é o
## corpo — e não o meio geométrico do bicho — que precisa cair no meio do quadro.
@export var altura_maos := -0.1

## Força do chacoalhão do agarrão e a de cada aperto.
const COICE_AGARRAO := 1.0
const COICE_APERTO := 0.45
## De que morte estas mãos matam. Esganado o rato chega inteiro, sem um furo na
## pelagem, e é por isso que as mãos são as que mais pagam — nenhuma arma vai
## render mais que elas.
const TIPO_DE_MORTE := Morte.Tipo.ESTRANGULAMENTO

@onready var ponto: Node3D = get_parent().get_node("PontoCaptura")

var _rato: Node3D
var _pressao := 0.0
var _tempo_vazio := 0.0

func _ready() -> void:
	super()
	ponto.position = Vector3(0.0, altura_maos, -distancia_maos)

func _process(delta: float) -> void:
	super(delta)
	if not _segurando():
		return

	_definir_pressao(_pressao - decaimento * delta)

	# Enquanto o rato ainda está subindo ele não conta como largado: o relógio da
	# escapada só começa quando ele chega na mão.
	if _pressao > 0.0 or not _rato.esta_na_mao():
		_tempo_vazio = 0.0
		return
	_tempo_vazio += delta
	if _tempo_vazio >= tempo_ate_escapar:
		_soltar(false)

func ocupada() -> bool:
	return _segurando()

## O agarrão.
func _usar() -> void:
	if _segurando():
		return
	var alvo := _rato_na_mira()
	_animar_gesto()
	usou.emit(alvo != null)
	if alvo == null:
		return
	if not alvo.ser_capturado(ponto):
		return

	_rato = alvo
	_pressao = 0.0
	_tempo_vazio = 0.0
	_coicear(COICE_AGARRAO)
	capturou.emit(_rato)
	pressao_mudou.emit(0.0)

## Um aperto no pescoço.
func apertar_secundario() -> void:
	if not _segurando():
		return
	_rato.apertar()
	_coicear(COICE_APERTO)
	_definir_pressao(_pressao + 1.0 / maxf(1.0, float(apertos_para_matar)))
	if _pressao >= 1.0:
		_soltar(true)

func _segurando() -> bool:
	if _rato != null and not is_instance_valid(_rato):
		# O rato sumiu por baixo do pano (recarga de cena, `queue_free`): larga a
		# referência e devolve o jogador ao normal.
		_rato = null
		terminou.emit(false)
	return _rato != null

func _definir_pressao(valor: float) -> void:
	var novo := clampf(valor, 0.0, 1.0)
	if is_equal_approx(novo, _pressao):
		return
	_pressao = novo
	pressao_mudou.emit(_pressao)

func _soltar(matou: bool) -> void:
	var rato := _rato
	_rato = null
	_pressao = 0.0
	_tempo_vazio = 0.0
	if matou:
		rato.morrer_nas_maos(TIPO_DE_MORTE)
		# O rato morreu no meio de uma martelada e ainda vêm cliques na rabeira:
		# sem esta pausa eles agarrariam o rato seguinte sem o jogador querer.
		recarregar()
	else:
		# Escapou justamente porque ninguém estava clicando; não há o que segurar.
		rato.escapar()
	pressao_mudou.emit(0.0)
	terminou.emit(matou)
