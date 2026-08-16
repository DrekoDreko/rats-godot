extends Control
## O aviso do esganamento: aparece quando o jogador agarra um rato, mostra o
## botão que o mata e o quanto o pescoço dele já foi apertado.
##
## Enquanto isso a mira sai da tela — não há o que mirar com as mãos cheias.

## A pressão fica vermelha e o aviso começa a piscar quando o rato está prestes
## a se soltar.
const PRESSAO_DE_PERIGO := 0.12
const COR_NORMAL := Color(0.94, 0.86, 0.36)
const COR_PERIGO := Color(0.95, 0.32, 0.28)
## Piscadas por segundo do aviso, quando a pressão está no fim.
const PISCADAS := 6.0

## A mira, que sai da tela enquanto as mãos estão ocupadas. É um caminho, e não
## uma referência direta ao nó: exportar nó só se liga sozinho em cena salva
## pelo editor, e o HUD do `mundo.tscn` é escrito à mão.
@export var caminho_da_mira := NodePath("../Mira")

@onready var botao: Label = $Botao
@onready var barra: ProgressBar = $Barra
@onready var mira: Control = get_node_or_null(caminho_da_mira)

var _pressao := 0.0

func _ready() -> void:
	hide()
	set_process(false)
	# Espera um quadro para o jogador já estar na árvore.
	await get_tree().process_frame
	var jogador := get_tree().get_first_node_in_group("jogador")
	if jogador == null:
		return
	jogador.captura_iniciada.connect(_ao_capturar)
	jogador.captura_progresso.connect(_ao_progredir)
	jogador.captura_terminada.connect(_ao_terminar)

func _process(_delta: float) -> void:
	if _pressao > PRESSAO_DE_PERIGO:
		botao.modulate.a = 1.0
		return
	# Quase escapando: o aviso pisca para o jogador martelar mais rápido.
	botao.modulate.a = 0.35 + 0.65 * absf(sin(Time.get_ticks_msec() / 1000.0 * PI * PISCADAS))

func _ao_capturar(_rato: Node3D) -> void:
	_pressao = 0.0
	_atualizar_cores()
	show()
	set_process(true)
	if mira != null:
		mira.hide()

func _ao_progredir(fracao: float) -> void:
	_pressao = fracao
	barra.value = fracao
	_atualizar_cores()

func _ao_terminar(_matou: bool) -> void:
	hide()
	set_process(false)
	if mira != null:
		mira.show()

func _atualizar_cores() -> void:
	var perigo := _pressao <= PRESSAO_DE_PERIGO
	var cor := COR_PERIGO if perigo else COR_NORMAL
	botao.add_theme_color_override("font_color", cor)
	barra.modulate = cor
