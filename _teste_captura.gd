extends SceneTree
## Teste de bancada da captura: encosta o jogador num rato, agarra e acompanha a
## subida quadro a quadro — quanto falta para a mão, em que fase ele está e como
## está a escala do modelo. Depois roda dois desfechos: um rato martelado até
## morrer e um rato largado, que precisa se soltar e voltar a fugir.
##
## Rodar com: godot --headless --script _teste_captura.gd
##
## O terceiro rato cobre o caso do jogador que martela rápido demais e mata o
## bicho antes de ele terminar de subir.

## Quadros de folga entre uma etapa e outra.
const ESPERA := 8
## Quadros de paciência antes de desistir de uma etapa.
const LIMITE := 240
## De onde o jogador agarra: atrás do rato, dentro do alcance das mãos.
const POSTO := Vector3(0.0, 0.0, 1.6)
## Altura do alvo no rato — a mesma que a arma usa.
const ALTURA_ALVO := 0.2

var _mundo: Node3D
var _jogador: CharacterBody3D
var _cabeca: Node3D
var _maos: Node3D
var _ponto: Node3D
var _aviso: Control
var _mira: Control
var _quadros := 0
var _etapa := 0
var _relogio := 0
var _apertos := 0
var _rato: Node3D
var _distancia_anterior := INF
var _falhas := 0
## Ratos já usados por uma etapa anterior; o recém-escapado ainda está imune, e
## reagarrá-lo daria uma falha que não é do jogo, é do teste.
var _usados: Array[StringName] = []

func _initialize() -> void:
	# Sem tela o laço rodaria a milhares de quadros por segundo e a subida
	# passaria inteira entre dois quadros de física.
	Engine.max_fps = 60
	_mundo = load("res://scenes/mundo.tscn").instantiate()
	root.add_child(_mundo)
	_jogador = _mundo.get_node("Jogador")
	_cabeca = _jogador.get_node("Cabeca")
	_maos = _jogador.get_node("Cabeca/Maos")
	_ponto = _jogador.get_node("Cabeca/PontoCaptura")
	_aviso = _mundo.get_node("HUD/Esganamento")
	_mira = _mundo.get_node("HUD/Mira")
	# O jogador é conduzido daqui: nada de entrada nem de gravidade.
	_jogador.set_physics_process(false)
	_jogador.set_process_unhandled_input(false)

func _physics_process(_delta: float) -> bool:
	_quadros += 1
	_relogio += 1
	match _etapa:
		0: return _agarrar("primeiro")
		1: return _acompanhar_subida()
		2: return _martelar()
		3: return _confirmar_morte()
		4: return _agarrar("segundo")
		5: return _largar()
		6: return _agarrar("terceiro")
		7: return _esganar_no_ar()
		8: return _confirmar_morte()
	return _terminar()

# --- Etapas ----------------------------------------------------------------

func _agarrar(qual: String) -> bool:
	if _relogio < ESPERA:
		return false
	# O HUD só se liga aos sinais do jogador depois de um quadro de idle, e a
	# partida engole vários quadros de física de uma vez enquanto a malha assa:
	# sem esta espera o primeiro agarrão acontecia com o aviso ainda desligado.
	if _jogador.captura_iniciada.get_connections().is_empty():
		return false
	_rato = _mais_proximo()
	if _rato == null:
		print("FALHA: nenhum rato solto para o teste %s" % qual)
		return _terminar()

	_mirar(_rato)
	_maos.tentar_usar()
	if not _rato.esta_capturado():
		print("FALHA: o %s rato nao foi capturado" % qual)
		return _terminar()
	print("--- %s rato (%s) agarrado ---" % [qual, _rato.name])
	_conferir_hud(true, "com o rato na mao")
	_usados.append(_rato.name)
	_distancia_anterior = INF
	_apertos = 0
	return _avancar()

## O ponto do teste: a subida precisa encurtar a distância até a mão sem voltar
## atrás e terminar com o rato exatamente no ponto de captura.
func _acompanhar_subida() -> bool:
	var distancia := _rato.global_position.distance_to(_ponto.global_position)
	print("quadro %2d: ate a mao %.3f m, altura %.2f, na mao=%s, escala %.2v" % [
		_relogio, distancia, _rato.global_position.y, _rato.esta_na_mao(), _rato.get_node("Modelo").scale
	])
	# A distância só pode crescer no bote, enquanto ele ainda está no chão.
	if _relogio > 12 and distancia > _distancia_anterior + 0.001:
		print("FALHA: a subida voltou atras (%.3f -> %.3f)" % [_distancia_anterior, distancia])
		_falhas += 1
	_distancia_anterior = distancia

	if _rato.esta_na_mao():
		if distancia > 0.05:
			print("FALHA: chegou na mao a %.3f m do ponto" % distancia)
			_falhas += 1
		if _rato.get_parent() != _ponto:
			print("FALHA: o rato nao virou filho do ponto de captura")
			_falhas += 1
		print("chegou na mao em %d quadros de fisica" % _relogio)
		return _avancar()
	if _relogio > LIMITE:
		print("FALHA: a subida nao terminou em %d quadros" % LIMITE)
		return _terminar()
	return false

func _martelar() -> bool:
	if not _maos.ocupada():
		print("soltou o rato depois de %d apertos" % _apertos)
		return _avancar()
	if _apertos > _maos.apertos_para_matar * 3:
		print("FALHA: %d apertos e o rato continua na mao" % _apertos)
		_falhas += 1
		return _terminar()
	_maos.apertar_secundario()
	_apertos += 1
	return false

func _confirmar_morte() -> bool:
	if not _rato.esta_morto():
		if _relogio > LIMITE:
			print("FALHA: o rato nao morreu depois de esganado")
			_falhas += 1
			return _terminar()
		return false
	if _rato.get_parent() == _ponto:
		print("FALHA: o rato morreu mas continua pendurado na mao")
		_falhas += 1
	if _rato.is_in_group("ratos"):
		print("FALHA: o rato morreu mas continua no grupo dos vivos")
		_falhas += 1
	# O corpo é largado da mão: cai aos pés do jogador. Se aparecer longe, ele
	# amoleceu em coordenadas da mão sem estar preso nela.
	var distancia := _plana(_rato.global_position, _jogador.global_position)
	if distancia > 3.0:
		print("FALHA: o corpo caiu a %.1f m do jogador" % distancia)
		_falhas += 1
	_conferir_hud(false, "depois da morte")
	print("morreu %.2f s depois do ultimo aperto, a %.2f m do jogador, largado em %s" % [
		_relogio / 60.0, distancia, _rato.get_parent().name
	])
	return _avancar()

## O jogador que martela rápido demais: todos os apertos no quadro seguinte ao
## agarrão, com o rato ainda no ar. Ele tem de morrer assim mesmo.
func _esganar_no_ar() -> bool:
	if _rato.esta_na_mao():
		print("FALHA: o rato ja tinha chegado na mao; o caso testado nao aconteceu")
		_falhas += 1
	for i in _maos.apertos_para_matar + 2:
		_maos.apertar_secundario()
	if _maos.ocupada():
		print("FALHA: apertos de sobra e o rato continua na mao")
		_falhas += 1
		return _terminar()
	print("esganado ainda no ar, sem ter chegado na mao")
	return _avancar()

## Sem apertar nada, o rato tem de se soltar sozinho e voltar a fugir.
func _largar() -> bool:
	if _maos.ocupada():
		if _relogio > LIMITE:
			print("FALHA: o rato nunca escapou")
			_falhas += 1
			return _terminar()
		return false
	if _rato.esta_capturado():
		print("FALHA: escapou mas continua capturado")
		_falhas += 1
	if _rato.get_parent() == _ponto:
		print("FALHA: escapou mas continua filho da mao")
		_falhas += 1
	if not _rato.is_in_group("ratos"):
		print("FALHA: escapou mas saiu do grupo dos vivos")
		_falhas += 1
	_conferir_hud(false, "depois da escapada")
	print("escapou em %.2f s, de volta ao mundo em %s" % [_relogio / 60.0, _rato.get_parent().name])
	return _avancar()

# --- Utilidades ------------------------------------------------------------

## Põe o jogador atrás do rato e aponta corpo e cabeça para ele, para o rato
## cair dentro do alcance e do cone das mãos.
func _mirar(rato: Node3D) -> void:
	var alvo := rato.global_position + Vector3.UP * ALTURA_ALVO
	_jogador.global_position = rato.global_position + POSTO
	_jogador.look_at(Vector3(alvo.x, _jogador.global_position.y, alvo.z), Vector3.UP)
	_jogador.rotation.x = 0.0
	_jogador.rotation.z = 0.0
	var olho := _cabeca.global_position
	_cabeca.rotation.x = atan2(alvo.y - olho.y, Vector2(alvo.x - olho.x, alvo.z - olho.z).length())

## O aviso do esganamento e a mira se revezam: um aparece exatamente quando o outro
## some. Confere de quebra se o `mira` exportado no `mundo.tscn` chegou ligado.
func _conferir_hud(segurando: bool, quando: String) -> void:
	if _aviso.visible != segurando:
		print("FALHA: o aviso do esganamento devia estar %s %s" % ["visivel" if segurando else "escondido", quando])
		_falhas += 1
	if _mira.visible == segurando:
		print("FALHA: a mira devia estar %s %s" % ["escondida" if segurando else "visivel", quando])
		_falhas += 1

func _avancar() -> bool:
	_etapa += 1
	_relogio = 0
	return false

func _terminar() -> bool:
	print("--- %d quadros, %d falha(s) ---" % [_quadros, _falhas])
	return true

func _mais_proximo() -> Node3D:
	var melhor: Node3D = null
	var menor := INF
	for no in get_nodes_in_group("ratos"):
		var rato := no as Node3D
		if rato.name in _usados:
			continue
		var distancia := _plana(rato.global_position, _jogador.global_position)
		if distancia < menor:
			menor = distancia
			melhor = rato
	return melhor

func _plana(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
