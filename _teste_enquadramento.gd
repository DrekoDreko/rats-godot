extends SceneTree
## Bancada do enquadramento: agarra um rato, deixa ele na mão e mede como o corpo
## dele cai na tela — quanto sobe, quanto desce, quanto sai para cada lado — além
## de salvar as imagens do momento parado, de um aperto e do corpo amolecendo.
##
## Rodar com janela (sem `--headless`, que não desenha nada):
##   godot --script _teste_enquadramento.gd
##
## As imagens saem na pasta de dados do projeto, cujo caminho é impresso no fim.

const TAMANHO := Vector2i(1141, 634)
const POSTO := Vector3(0.0, 0.0, 1.6)
const ALTURA_ALVO := 0.2

var _mundo: Node3D
var _jogador: CharacterBody3D
var _cabeca: Node3D
var _maos: Node3D
var _camera: Camera3D
var _rato: Node3D
var _etapa := 0
var _relogio := 0
## Relógio da etapa em segundos. Os retratos vão por ele, e não por quadros:
## gravar um PNG custa tempo, e o gesto anda pelo `delta` como no jogo.
var _tempo := 0.0

func _initialize() -> void:
	Engine.max_fps = 60
	DisplayServer.window_set_size(TAMANHO)
	_mundo = load("res://scenes/mundo.tscn").instantiate()
	root.add_child(_mundo)
	_jogador = _mundo.get_node("Jogador")
	_cabeca = _jogador.get_node("Cabeca")
	_maos = _jogador.get_node("Cabeca/Maos")
	_camera = _jogador.get_node("Cabeca/Camera")
	_jogador.set_physics_process(false)
	_jogador.set_process_unhandled_input(false)

func _process(delta: float) -> bool:
	# O jogador prende o mouse no `_ready`; aqui ele fica solto, senão a bancada
	# sequestra o cursor de quem está rodando.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_relogio += 1
	_tempo += delta
	match _etapa:
		0: return _agarrar()
		1: return _esperar_na_mao()
		2: return _retratar("mao-parado", 0.5)
		3: return _apertar_e_retratar()
		4: return _matar()
		5: return _retratar("amolecendo", 0.12)
		# A guardada: o corpo saindo da mão para a cintura, de quadro em quadro.
		6: return _retratar("guardando-1", 0.45)
		7: return _retratar("guardando-2", 0.12)
		8: return _retratar("guardando-3", 0.12)
	# Um respiro para a última imagem terminar de ser gravada.
	return _relogio > 10

func _agarrar() -> bool:
	if _relogio < 20 or _jogador.captura_iniciada.get_connections().is_empty():
		return false
	_rato = _mais_proximo()
	if _rato == null:
		print("FALHA: nenhum rato por perto")
		return true
	_mirar(_rato)
	_maos.tentar_usar()
	if not _rato.esta_capturado():
		print("FALHA: nao capturou")
		return true
	return _avancar()

func _esperar_na_mao() -> bool:
	if not _rato.esta_na_mao():
		return _relogio > 300
	return _avancar()

## Espera `espera` segundos, mede o enquadramento e salva a imagem.
func _retratar(nome: String, espera: float) -> bool:
	if _tempo < espera:
		return false
	if not is_instance_valid(_rato):
		print("%-12s o rato ja tinha sido guardado" % nome)
		return _avancar()
	_medir(nome)
	_salvar(nome)
	return _avancar()

func _apertar_e_retratar() -> bool:
	if _relogio == 1:
		_maos.apertar_secundario()
		return false
	return _retratar("aperto", 0.05)

func _matar() -> bool:
	while _maos.ocupada():
		_maos.apertar_secundario()
	return _avancar()

# --- Medida ----------------------------------------------------------------

## Onde o corpo do rato cai na tela, em fração do quadro: 0 é a borda de cima (ou
## da esquerda), 1 a de baixo (ou da direita), 0.5 o centro.
func _medir(nome: String) -> void:
	var malha: MeshInstance3D = _rato.get_node("Modelo/Malha/Rat/Skeleton3D/Rat Model")
	var aabb := malha.get_aabb()
	var t := malha.global_transform
	var minimo := Vector2.INF
	var maximo := -Vector2.INF
	var frente := INF
	for i in 8:
		var mundo := t * aabb.get_endpoint(i)
		var tela := _camera.unproject_position(mundo)
		minimo = minimo.min(tela)
		maximo = maximo.max(tela)
		frente = minf(frente, _camera.global_position.distance_to(mundo))
	var quadro := Vector2(root.size)
	var centro := (minimo + maximo) * 0.5 / quadro
	print("%-12s x %.2f..%.2f  y %.2f..%.2f  centro (%.2f, %.2f)  ponta mais perto da camera: %.2f m" % [
		nome, minimo.x / quadro.x, maximo.x / quadro.x,
		minimo.y / quadro.y, maximo.y / quadro.y, centro.x, centro.y, frente,
	])

	# A AABB é a pose de repouso do modelo; quem manda no enquadramento é a pose
	# em que ele está de verdade, e essa só os ossos contam.
	var esqueleto: Skeleton3D = _rato.get_node("Modelo/Malha/Rat/Skeleton3D")
	for i in esqueleto.get_bone_count():
		var osso := esqueleto.get_bone_name(i)
		if osso not in ["Head_end", "Head", "Body_Upper", "Body_Lower", "B_Leg.l", "Tail_2_end"]:
			continue
		var tela := _camera.unproject_position(esqueleto.global_transform * esqueleto.get_bone_global_pose(i).origin) / quadro
		print("    %-12s tela (%.2f, %.2f)" % [osso, tela.x, tela.y])

func _salvar(nome: String) -> void:
	await RenderingServer.frame_post_draw
	var imagem := root.get_texture().get_image()
	var arquivo := "user://enquadramento-%s.png" % nome
	imagem.save_png(arquivo)
	print("    imagem em %s" % ProjectSettings.globalize_path(arquivo))

# --- Utilidades ------------------------------------------------------------

func _mirar(rato: Node3D) -> void:
	var alvo := rato.global_position + Vector3.UP * ALTURA_ALVO
	_jogador.global_position = rato.global_position + POSTO
	_jogador.look_at(Vector3(alvo.x, _jogador.global_position.y, alvo.z), Vector3.UP)
	_jogador.rotation.x = 0.0
	_jogador.rotation.z = 0.0
	var olho := _cabeca.global_position
	_cabeca.rotation.x = atan2(alvo.y - olho.y, Vector2(alvo.x - olho.x, alvo.z - olho.z).length())

func _avancar() -> bool:
	_etapa += 1
	_relogio = 0
	_tempo = 0.0
	return false

func _mais_proximo() -> Node3D:
	var melhor: Node3D = null
	var menor := INF
	for no in get_nodes_in_group("ratos"):
		var rato := no as Node3D
		var distancia := rato.global_position.distance_to(_jogador.global_position)
		if distancia < menor:
			menor = distancia
			melhor = rato
	return melhor
