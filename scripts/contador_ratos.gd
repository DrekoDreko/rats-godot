extends Label
## Mostra quantos ratos ainda estão soltos pelo mapa.

const INTERVALO := 0.2

var _total := 0
var _tempo := 0.0

func _ready() -> void:
	# Espera um quadro para que todos os ratos já estejam na árvore.
	await get_tree().process_frame
	_atualizar()

func _process(delta: float) -> void:
	_tempo -= delta
	if _tempo > 0.0:
		return
	_tempo = INTERVALO
	_atualizar()

func _atualizar() -> void:
	var vivos := get_tree().get_nodes_in_group("ratos").size()
	_total = maxi(_total, vivos)
	text = "Ratos: %d / %d" % [vivos, _total]
